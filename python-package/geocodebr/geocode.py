from __future__ import annotations

from pathlib import Path
from typing import Any

import duckdb
import pyarrow as pa

from .cache import listar_pasta_cache
from .constants import ALL_POSSIBLE_MATCH_TYPES, DATA_RELEASE
from .db import create_geocodebr_db
from .download_cnefe import download_cnefe
from .errors import error_input_nao_padronizado
from .fields import assert_and_assign_address_fields, definir_campos
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
    add_precision_col,
    check_clean_colnames,
    cria_col_logradouro_confusao,
    find_cached_parquet,
    get_key_cols,
    merge_results_to_input,
    quote_ident,
    sql_string,
)


def busca_por_cep(
    cep: str | list[str] | tuple[str, ...],
    h3_res: int | list[int] | tuple[int, ...] | None = None,
    resultado_sf: bool = False,
    verboso: bool = True,
    cache: bool = True,
) -> pa.Table:
    if resultado_sf:
        raise NotImplementedError("resultado_sf=True sera implementado com geopandas na proxima etapa.")
    _assert_bool(verboso, "verboso")
    _assert_bool(cache, "cache")
    h3_values = _normalize_h3_res(h3_res)
    ceps = _normalize_ceps(cep)
    if not ceps:
        raise ValueError("Nenhum CEP valido foi informado.")

    download_cnefe("municipio_logradouro_cep_localidade", verboso=verboso, cache=cache)
    con = create_geocodebr_db()
    try:
        path_to_parquet = (
            Path(listar_pasta_cache())
            / f"geocodebr_data_release_{DATA_RELEASE}"
            / "municipio_logradouro_cep_localidade.parquet"
        ).as_posix()
        unique_ceps = ", ".join(sql_string(value) for value in sorted(set(ceps)))
        con.execute(
            f"""
            CREATE OR REPLACE TEMP TABLE output_df AS
            SELECT cep, estado, municipio, logradouro, localidade, lon, lat
            FROM read_parquet('{path_to_parquet}') m
            WHERE REGEXP_REPLACE(CAST(m.cep AS VARCHAR), '[^0-9]', '', 'g') IN ({unique_ceps})
            """
        )
        found_ceps = set(
            row[0]
            for row in con.execute(
                "SELECT DISTINCT REGEXP_REPLACE(CAST(cep AS VARCHAR), '[^0-9]', '', 'g') FROM output_df"
            ).fetchall()
        )
        missing = sorted(set(ceps) - found_ceps)
        if len(missing) == len(set(ceps)):
            raise ValueError("Nenhum CEP foi encontrado.")
        if missing:
            values = ", ".join(f"({sql_string(value)})" for value in missing)
            con.execute(f"INSERT INTO output_df (cep) VALUES {values}")
        _add_h3_columns(con, "output_df", h3_values)
        return con.execute("SELECT * FROM output_df").to_arrow_table()
    finally:
        con.close()


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
        _assert_bool(value, name)
    h3_values = _normalize_h3_res(h3_res)
    if campos_endereco is None:
        campos_endereco = definir_campos(estado="estado", municipio="municipio")

    download_cnefe("todas", verboso=verboso, cache=cache)
    con = create_geocodebr_db(n_cores=n_cores)
    try:
        _register_input(con, enderecos)
        input_columns = _table_columns(con, "enderecos_input")
        check_clean_colnames(input_columns)
        campos_endereco = assert_and_assign_address_fields(campos_endereco, input_columns)

        con.execute(
            """
            CREATE OR REPLACE TEMP TABLE input_db AS
            SELECT *, ROW_NUMBER() OVER ()::INTEGER AS tempidgeocodebr
            FROM enderecos_input
            """
        )
        original_columns = [col for col in input_columns] + ["tempidgeocodebr"]

        if padronizar_enderecos:
            message_standardizing_addresses(verboso)
            _create_standardized_input(con, campos_endereco)
        else:
            _create_standardized_input_from_padr(con)

        _assert_standardized_columns(con)
        con.execute("ALTER TABLE input_padrao_db ADD COLUMN temp_lograd_determ TEXT")
        con.execute("ALTER TABLE input_padrao_db ADD COLUMN similaridade_logradouro DOUBLE")
        cria_col_logradouro_confusao(con)
        create_output_db(con, resultado_completo)

        if verboso:
            message_looking_for_matches(verboso)

        n_rows = con.execute("SELECT COUNT(*) FROM input_padrao_db").fetchone()[0]
        matched_rows = 0
        input_padrao_columns = set(_table_columns(con, "input_padrao_db"))
        for match_type in ALL_POSSIBLE_MATCH_TYPES:
            key_cols = get_key_cols(match_type)
            if all(col in input_padrao_columns for col in key_cols):
                match_fun = select_match_function(match_type)
                affected = match_fun(
                    con,
                    match_type=match_type,
                    key_cols=key_cols,
                    resultado_completo=resultado_completo,
                )
                matched_rows += affected
                if matched_rows == n_rows:
                    break

        message_preparando_output(verboso)
        empates_resolvidos = trata_empates_geocode_duckdb(
            con, resultado_completo, resolver_empates, verboso
        )
        output_table_to_use = "output_db" if empates_resolvidos == 0 else "output_db2"
        add_precision_col(con, output_table_to_use)
        merge_results_to_input(
            con,
            x="input_db",
            y=output_table_to_use,
            select_columns=original_columns,
            resultado_completo=resultado_completo,
        )
        _add_h3_columns(con, "geocodebr_result", h3_values)
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


def _register_input(con: duckdb.DuckDBPyConnection, enderecos: Any) -> None:
    if isinstance(enderecos, (str, Path)):
        path = Path(enderecos)
        suffix = path.suffix.lower()
        path_sql = path.as_posix()
        if suffix == ".parquet":
            con.execute(f"CREATE OR REPLACE TEMP TABLE enderecos_input AS SELECT * FROM read_parquet('{path_sql}')")
        elif suffix in {".csv", ".txt"}:
            con.execute(f"CREATE OR REPLACE TEMP TABLE enderecos_input AS SELECT * FROM read_csv_auto('{path_sql}')")
        else:
            raise ValueError("Arquivos suportados: .parquet, .csv, .txt.")
        return

    con.register("enderecos_input_view", enderecos)
    con.execute("CREATE OR REPLACE TEMP TABLE enderecos_input AS SELECT * FROM enderecos_input_view")
    con.unregister("enderecos_input_view")


def _create_standardized_input(
    con: duckdb.DuckDBPyConnection,
    campos_endereco: dict[str, str | None],
) -> None:
    select_parts = []
    for field in ["estado", "municipio", "logradouro", "numero", "cep", "localidade"]:
        source = campos_endereco.get(field)
        if source is None:
            expr = "NULL"
        elif field == "numero":
            expr = f"TRY_CAST(NULLIF(REGEXP_REPLACE(CAST({quote_ident(source)} AS VARCHAR), '[^0-9]', '', 'g'), '') AS INTEGER)"
        elif field == "cep":
            expr = f"NULLIF(REGEXP_REPLACE(CAST({quote_ident(source)} AS VARCHAR), '[^0-9]', '', 'g'), '')"
        else:
            expr = f"NULLIF(_geocodebr_norm(CAST({quote_ident(source)} AS VARCHAR)), '')"
        out_name = "bairro" if field == "localidade" else field
        select_parts.append(f"{expr} AS {out_name}")

    _install_normalize_function(con)
    con.execute(
        f"""
        CREATE OR REPLACE TEMP TABLE input_padrao_db AS
        SELECT {", ".join(select_parts)}, tempidgeocodebr
        FROM input_db
        """
    )
    con.execute("ALTER TABLE input_padrao_db RENAME bairro TO localidade")
    _resolve_estado_names(con)
    _resolve_municipio_codes(con)


def _create_standardized_input_from_padr(con: duckdb.DuckDBPyConnection) -> None:
    cols = _table_columns(con, "input_db")
    padded = {
        "estado_padr": "estado",
        "municipio_padr": "municipio",
        "logradouro_padr": "logradouro",
        "numero_padr": "numero",
        "cep_padr": "cep",
        "bairro_padr": "localidade",
    }
    if not set(padded).issubset(cols):
        error_input_nao_padronizado()
    selects = [f"{src} AS {dst}" for src, dst in padded.items()]
    selects.append("tempidgeocodebr")
    con.execute(f"CREATE OR REPLACE TEMP TABLE input_padrao_db AS SELECT {', '.join(selects)} FROM input_db")


def _assert_standardized_columns(con: duckdb.DuckDBPyConnection) -> None:
    expected = {"estado", "municipio", "logradouro", "numero", "cep", "localidade"}
    if not expected.issubset(set(_table_columns(con, "input_padrao_db"))):
        error_input_nao_padronizado()


def _install_normalize_function(con: duckdb.DuckDBPyConnection) -> None:
    import unicodedata

    estados = {
        "ACRE": "AC",
        "ALAGOAS": "AL",
        "AMAPA": "AP",
        "AMAZONAS": "AM",
        "BAHIA": "BA",
        "CEARA": "CE",
        "DISTRITO FEDERAL": "DF",
        "ESPIRITO SANTO": "ES",
        "GOIAS": "GO",
        "MARANHAO": "MA",
        "MATO GROSSO": "MT",
        "MATO GROSSO DO SUL": "MS",
        "MINAS GERAIS": "MG",
        "PARA": "PA",
        "PARAIBA": "PB",
        "PARANA": "PR",
        "PERNAMBUCO": "PE",
        "PIAUI": "PI",
        "RIO DE JANEIRO": "RJ",
        "RIO GRANDE DO NORTE": "RN",
        "RIO GRANDE DO SUL": "RS",
        "RONDONIA": "RO",
        "RORAIMA": "RR",
        "SANTA CATARINA": "SC",
        "SAO PAULO": "SP",
        "SERGIPE": "SE",
        "TOCANTINS": "TO",
    }

    def normalize(value: str | None) -> str | None:
        if value is None:
            return None
        text = unicodedata.normalize("NFKD", str(value))
        text = "".join(ch for ch in text if not unicodedata.combining(ch))
        text = text.upper()
        text = "".join(ch if ch.isalnum() else " " for ch in text)
        return " ".join(text.split())

    def normalize_uf(value: str | None) -> str | None:
        text = normalize(value)
        if text is None:
            return None
        if len(text) == 2:
            return text
        return estados.get(text, text)

    try:
        con.create_function("_geocodebr_norm", normalize, ["VARCHAR"], "VARCHAR")
    except duckdb.InvalidInputException:
        pass
    try:
        con.create_function("_geocodebr_uf", normalize_uf, ["VARCHAR"], "VARCHAR")
    except duckdb.InvalidInputException:
        pass


def _resolve_estado_names(con: duckdb.DuckDBPyConnection) -> None:
    con.execute(
        """
        UPDATE input_padrao_db
        SET estado = _geocodebr_uf(estado)
        WHERE estado IS NOT NULL
        """
    )


def _resolve_municipio_codes(con: duckdb.DuckDBPyConnection) -> None:
    from .cache import listar_dados_cache

    try:
        path = find_cached_parquet(listar_dados_cache(), "municipio")
    except FileNotFoundError:
        return

    con.execute(
        f"""
        CREATE OR REPLACE TEMP TABLE _geocodebr_municipio_ref AS
        SELECT * FROM read_parquet('{path}') LIMIT 0
        """
    )
    cols = set(_table_columns(con, "_geocodebr_municipio_ref"))
    code_col = next(
        (col for col in ["cod_muni", "code_muni", "cod_municipio", "codigo_municipio"] if col in cols),
        None,
    )
    if code_col is None or "municipio" not in cols:
        return

    con.execute(
        f"""
        CREATE OR REPLACE TEMP TABLE _geocodebr_municipio_ref AS
        SELECT DISTINCT CAST({quote_ident(code_col)} AS VARCHAR) AS municipio_codigo,
               municipio AS municipio_nome
        FROM read_parquet('{path}')
        WHERE {quote_ident(code_col)} IS NOT NULL
        """
    )
    con.execute(
        """
        UPDATE input_padrao_db
        SET municipio = ref.municipio_nome
        FROM _geocodebr_municipio_ref ref
        WHERE REGEXP_MATCHES(input_padrao_db.municipio, '^[0-9]{7}$')
          AND input_padrao_db.municipio = ref.municipio_codigo
        """
    )


def _add_h3_columns(
    con: duckdb.DuckDBPyConnection,
    table_name: str,
    h3_values: list[int],
) -> None:
    if not h3_values:
        return
    import h3

    def h3_cell(lat: float | None, lon: float | None, res: int) -> str | None:
        if lat is None or lon is None:
            return None
        if hasattr(h3, "latlng_to_cell"):
            return h3.latlng_to_cell(lat, lon, res)
        return h3.geo_to_h3(lat, lon, res)

    try:
        con.create_function("_geocodebr_h3", h3_cell, ["DOUBLE", "DOUBLE", "INTEGER"], "VARCHAR")
    except duckdb.InvalidInputException:
        pass

    for value in h3_values:
        colname = f"h3_{value:02d}"
        con.execute(f"ALTER TABLE {quote_ident(table_name)} ADD COLUMN {quote_ident(colname)} TEXT")
        con.execute(
            f"""
            UPDATE {quote_ident(table_name)}
            SET {quote_ident(colname)} = _geocodebr_h3(lat, lon, {value})
            WHERE lat IS NOT NULL
            """
        )


def _normalize_ceps(cep: str | list[str] | tuple[str, ...]) -> list[str]:
    values = [cep] if isinstance(cep, str) else list(cep)
    out = []
    for value in values:
        if not isinstance(value, str):
            raise TypeError("cep deve ser string ou sequencia de strings.")
        digits = "".join(ch for ch in value if ch.isdigit())
        if len(digits) == 8:
            out.append(digits)
    return sorted(set(out))


def _normalize_h3_res(h3_res: int | list[int] | tuple[int, ...] | None) -> list[int]:
    if h3_res is None:
        return []
    values = [h3_res] if isinstance(h3_res, int) else list(h3_res)
    for value in values:
        if not isinstance(value, int) or value < 0 or value > 15:
            raise ValueError("h3_res deve conter inteiros entre 0 e 15.")
    return values


def _assert_bool(value: bool, name: str) -> None:
    if not isinstance(value, bool):
        raise TypeError(f"{name} deve ser True ou False.")


def _table_columns(con: duckdb.DuckDBPyConnection, table_name: str) -> list[str]:
    return [row[1] for row in con.execute(f"PRAGMA table_info('{table_name}')").fetchall()]
