from __future__ import annotations

from pathlib import Path
from typing import Any

from tqdm import tqdm
import pyarrow as pa
import polars as pl
import pandas as pd

from .constants import ALL_POSSIBLE_MATCH_TYPES
from .standardize import enderecobr_padronizar_enderecos
from .db import create_geocodebr_db
from .download_cnefe import download_cnefe
from .errors import error_input_nao_padronizado
from .fields import (
    assert_and_assign_address_fields,
    definir_campos,
    fill_missing_fields,
    ADDRESS_FIELDS
)
from .matching import (
    create_output_db,
    select_match_function,
    trata_empates_geocode_duckdb,
)
from .messages import (
    message_looking_for_matches,
    message_preparando_output,
    message_standardizing_addresses,
)
from .utils import (
    assert_bool,
    normalize_h3_res,
    add_precision_col,
    check_clean_colnames,
    cria_col_logradouro_confusao,
    find_cached_parquet,
    get_key_cols,
    db_table_columns,
    merge_results_to_input,
    quote_ident,
    add_h3_columns,
    tabelas_necessarias,
)


def geocode(
    enderecos: Any,
    campos_endereco: dict[str, str | None] | None = None,
    resultado_completo: bool = False,
    resolver_empates: bool = True,
    resultado_sf: bool = False,
    h3_res: int | list[int] | tuple[int, ...] | None = None,
    padronizar_enderecos: bool = True,
    verboso: bool = True,
    cache: bool = True,
    n_cores: int | None = None,
) -> pa.Table:
    if resultado_sf:
        raise NotImplementedError("resultado_sf=True sera implementado com geopandas na proxima etapa.")
    for name, value in {
        "resultado_completo": resultado_completo,
        "resolver_empates": resolver_empates,
        "padronizar_enderecos": padronizar_enderecos,
        "verboso": verboso,
        "cache": cache,
    }.items():
        assert_bool(value, name)
    h3_values = normalize_h3_res(h3_res)
    if campos_endereco is None:
        campos_endereco = definir_campos(estado="estado", municipio="municipio")

    con = create_geocodebr_db(n_cores=n_cores)
    try:

        df_input = _materialize_input(enderecos)
        input_columns = df_input.columns

        check_clean_colnames(input_columns)

        # Fix eventual missing fields in input data
        # geocode requires all adress fields to be present
        # if one or more fileds are missing, we add mock empty columns
        campos_endereco = assert_and_assign_address_fields(campos_endereco, input_columns)
        df_input, campos_endereco, campos_nao_declarados = fill_missing_fields(df_input, campos_endereco)

        # downloading cnefe -- so as tabelas que as etapas ativas do laco de
        # matching abaixo vao de fato usar, dado quais campos o usuario
        # declarou (campos_nao_declarados, calculado acima)
        cnefe_dir = download_cnefe(
            tabelas_necessarias(campos_nao_declarados),
            verboso=verboso,
            cache=cache,
        )


        if padronizar_enderecos:
            message_standardizing_addresses(verboso)
            df_padrao = enderecobr_padronizar_enderecos(
                enderecos=df_input,
                campos_do_endereco=campos_endereco,
                formato_estados="sigla",
                formato_numeros="integer",
                manter_cols_extras=True,
            )
        else:
            df_padrao = df_input.clone()

        _assert_standardized_columns(df_padrao)
        df_padrao = _keep_rename_padr_columns(df_padrao)

        # Create temp id in both tables
        df_input = df_input.with_row_count("tempidgeocodebr")
        original_columns = [col for col in input_columns] + ["tempidgeocodebr"]
        df_padrao = df_padrao.with_columns(df_input["tempidgeocodebr"])
        # Create temp `logradouro` columns to be used in probabilistic match
        df_padrao = df_padrao.with_columns(
            pl.lit("").alias("temp_lograd_determ"),
            pl.lit(None).alias("similaridade_logradouro"),
        )

        con.register("input_db", df_input)

        con.register("input_padrao_view", df_padrao)
        con.execute("CREATE TEMP TABLE input_padrao_db AS SELECT * FROM input_padrao_view")

        cria_col_logradouro_confusao(con)
        create_output_db(con, resultado_completo)

        if verboso:
            message_looking_for_matches(verboso)

        n_rows = con.execute("SELECT COUNT(*) FROM input_padrao_db").fetchone()[0]
        matched_rows = 0
        input_padrao_columns = set(db_table_columns(con, "input_padrao_db"))
        with tqdm(
            total=n_rows,
            disable=not verboso,
            desc="Geolocalizando",
            unit="end",
            bar_format="{l_bar}{bar}| {n_fmt}/{total_fmt} [{postfix}]",
        ) as pbar:
             for match_type in ALL_POSSIBLE_MATCH_TYPES:
                key_cols = get_key_cols(match_type)
                if all(col in input_padrao_columns for col in key_cols) and not any(
                    col in campos_nao_declarados for col in key_cols
                ):
                    pbar.set_postfix_str(match_type)
                    match_fun = select_match_function(match_type)
                    affected = match_fun(
                        con, match_type=match_type, key_cols=key_cols,
                        resultado_completo=resultado_completo,
                        pasta_dados=cnefe_dir,
                    )
                    matched_rows += affected
                    pbar.update(affected)
                    if matched_rows == n_rows:
                        break

        message_preparando_output(verboso)
        empates_resolvidos = trata_empates_geocode_duckdb(
            con, resultado_completo, resolver_empates, verboso
        )
        output_table_to_use = "output_db" if empates_resolvidos == 0 else "output_db2"
        add_precision_col(con, output_table_to_use)
        if resultado_completo and "empate" not in db_table_columns(con, output_table_to_use):
            con.execute(f"ALTER TABLE {output_table_to_use} ADD COLUMN empate BOOLEAN")
        merge_results_to_input(
            con,
            x="input_db",
            y=output_table_to_use,
            select_columns=original_columns,
            resultado_completo=resultado_completo,
        )
        add_h3_columns(con, "geocodebr_result", h3_values)
        con.execute(
            """
            CREATE OR REPLACE TEMP TABLE geocodebr_result AS
            SELECT * EXCLUDE (tempidgeocodebr)
            FROM geocodebr_result
            ORDER BY tempidgeocodebr
            """
        )
        return con.execute("SELECT * FROM geocodebr_result").to_arrow_table()
    finally:
        con.close()


def _materialize_input(enderecos: Any) -> pl.DataFrame:
    if isinstance(enderecos, (str, Path)):
        path = Path(enderecos)
        if not path.is_file():
            raise FileNotFoundError(f"Arquivo não encontrado: {path}")
        suffix = path.suffix.lower()
        path = path.as_posix()
        if suffix == ".parquet":
            return pl.scan_parquet(path).collect()
        elif suffix in {".csv", ".txt"}:
            return pl.scan_csv(path).collect()
        else:
            raise ValueError("Arquivos suportados: .parquet, .csv, .txt.")
    elif isinstance(enderecos, pa.Table):
        return pl.from_arrow(enderecos)          
    elif isinstance(enderecos, pl.DataFrame):
        return enderecos.clone()
    elif isinstance(enderecos, pd.DataFrame):
        return pl.from_pandas(enderecos)
    else:
        raise TypeError(
            "`enderecos` deve ser caminho de arquivo (.parquet/.csv/.txt), "
            "pyarrow.Table, polars.DataFrame ou pandas.DataFrame."
        )


def _assert_standardized_columns(df: pl.DataFrame) -> None:
    expected = {field+"_padr" for field in ADDRESS_FIELDS}
    if not expected.issubset(df.columns):
        error_input_nao_padronizado()

def _keep_rename_padr_columns(df: pl.DataFrame) -> pl.DataFrame:
    # Select only "_padr" columns
    padr_cols = [col for col in df.columns if col.endswith("_padr")]
    df = df.select(padr_cols)

    # Remove "_padr" siffix to keep the same CNEFE column names
    rename_map = {col: col.removesuffix("_padr") for col in padr_cols}
    df = df.rename(rename_map)

    return df
