from __future__ import annotations

from pathlib import Path
from typing import TYPE_CHECKING, Any

from tqdm import tqdm
import pyarrow as pa
import polars as pl
import pandas as pd

from ._heap import n_cores_efetivo
from .geo import arrow_to_geodataframe
from .constants import ALL_POSSIBLE_MATCH_TYPES
from .standardize import enderecobr_padronizar_enderecos
from .db import close_geocodebr_db, create_geocodebr_db
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
    message_add_precision,
    message_merge_input,
    message_as_arrow,
    message_fim,
    message_conexao_fechada
)
if TYPE_CHECKING:
    import geopandas as gpd

from .utils import (
    normalize_h3_res,
    add_precision_col,
    assert_no_reserved_columns,
    check_clean_colnames,
    cria_col_logradouro_confusao,
    get_key_cols,
    db_table_columns,
    merge_results_to_input,
    add_h3_columns,
    tabelas_necessarias,
)


def geocode(
    enderecos: Any,
    campos_endereco: dict[str, str | None] | None = None,
    resultado_completo: bool = False,
    resolver_empates: bool = True,
    resultado_gpd: bool = False,
    h3_res: int | list[int] | tuple[int, ...] | None = None,
    padronizar_enderecos: bool = True,
    verboso: bool = True,
    cache: bool = True,
    n_cores: int | None = None,
) -> pa.Table | gpd.GeoDataFrame:
    """Geolocaliza endereços no Brasil.

    Geocodifica endereços brasileiros com base nos dados do CNEFE (Cadastro
    Nacional de Endereços para Fins Estatísticos), publicado pelo IBGE. Os
    endereços de input devem ser passados como uma tabela na qual cada coluna
    descreve um campo do endereço (logradouro, número, CEP, etc.). As
    coordenadas de output utilizam o sistema de referência SIRGAS 2000,
    EPSG 4674.

    Parameters
    ----------
    enderecos : pyarrow.Table, polars.DataFrame, pandas.DataFrame, str ou Path
        Os endereços a serem geolocalizados. Cada coluna deve representar um
        campo do endereço. Também aceita o caminho para um arquivo `.csv`,
        `.txt` ou `.parquet`.
    campos_endereco : dict[str, str | None], opcional
        A correspondência entre cada campo de endereço e o nome da coluna que
        o descreve na tabela `enderecos`. A função `definir_campos()` auxilia
        na criação deste dicionário e realiza verificações nos dados de
        entrada. Campos de endereço passados como `None` são ignorados, e a
        função deve receber pelo menos um campo não nulo, além dos campos
        `"estado"` e `"municipio"`, obrigatórios. Note que o campo
        `"localidade"` é equivalente a 'bairro', e que o campo `"logradouro"`
        deve conter o tipo e o nome do logradouro (e.g. "Rua Castro Alves",
        "Avenida Ipiranga"). Por padrão (`None`), assume-se que as colunas se
        chamam `"estado"` e `"municipio"`.
    resultado_completo : bool, opcional
        Indica se o output deve incluir colunas adicionais, como o endereço
        encontrado de referência. Por padrão, é `False`.
    resolver_empates : bool, opcional
        Alguns resultados da geolocalização podem indicar diferentes
        coordenadas possíveis (e.g. duas ruas diferentes com o mesmo nome em
        uma mesma cidade). Esses casos são tratados como 'empate' e o
        parâmetro `resolver_empates` indica se a função deve resolver esses
        empates automaticamente. Por padrão, é `True`, e a função retorna
        apenas o caso mais provável, preservando uma linha de output por
        linha de input. Com `False`, cada endereço empatado retorna uma linha
        por coordenada candidata (o output pode ter mais linhas que o input)
        e a coluna `empate` é incluída no output para identificar esses casos.
    resultado_gpd : bool, opcional
        Indica se o retorno deve ser um `geopandas.GeoDataFrame` de pontos no
        CRS SIRGAS 2000 (EPSG 4674), equivalente ao `sf` do R. Por padrão, é
        `False`, e o retorno é um `pyarrow.Table`. Requer o extra `geo`
        (`pip install geocodebr[geo]`).
    h3_res : int, list[int] ou None, opcional
        Número que indica a resolução espacial das células hexagonais H3 da
        localização dos pontos retornados. Também aceita uma lista de
        números, e.g. `[8, 10]`. Por padrão, é `None`. Detalhes sobre as
        resoluções disponíveis em https://h3geo.org/docs/core-library/restable/
    padronizar_enderecos : bool, opcional
        Indica se os dados de endereço de entrada devem ser padronizados. Por
        padrão, é `True`. Essa padronização é essencial para uma
        geolocalização correta. Alerta! Apenas utilize
        `padronizar_enderecos = False` caso os dados de input já tenham sido
        padronizados anteriormente com `enderecobr_padronizar_enderecos(...)`,
        com `formato_estados = "sigla"` e `formato_numeros = "integer"`.
    verboso : bool, opcional
        Indica se barras de progresso e mensagens devem ser exibidas durante
        o download dos dados do CNEFE e a geocodificação dos endereços. O
        padrão é `True`.
    cache : bool, opcional
        Indica se os dados do CNEFE devem ser salvos ou lidos do cache,
        reduzindo o tempo de processamento em chamadas futuras. O padrão é
        `True`. Quando `False`, os dados do CNEFE são baixados para um
        diretório temporário.
    n_cores : int, opcional
        O número de núcleos de CPU a serem utilizados no processamento dos
        dados. Por padrão, `n_cores = None` e o pacote utiliza o número
        máximo de núcleos disponíveis. No Windows sem Segment Heap, o número
        de threads do DuckDB é limitado a `min(4, núcleos disponíveis)`, com
        aviso, como mitigação à degradação de performance do DuckDB (veja a
        seção "Windows e performance" do README). Um valor explícito é
        respeitado.

    Returns
    -------
    pyarrow.Table or geopandas.GeoDataFrame
        O input `enderecos` adicionado das colunas de latitude (`lat`) e
        longitude (`lon`), bem como das colunas `precisao` e `tipo_resultado`
        que indicam o nível de precisão e o tipo de resultado. Endereços não
        encontrados retornam `lat`/`lon` e as colunas de precisão vazias.

    See Also
    --------
    definir_campos : Especifica as colunas que descrevem os campos dos
        endereços.
    download_cnefe : Faz o download dos dados do CNEFE.

    Notes
    -----
    Os resultados são classificados em seis categorias de `precisao`
    ("numero", "numero_aproximado", "logradouro", "cep", "localidade" e
    "municipio"), desagregadas em códigos de `tipo_resultado` (e.g. `dn01`,
    `pa03`), e incluem a coluna `desvio_metros` com a estimativa de incerteza
    da localização encontrada. Com `resultado_completo = True`, o output
    também inclui a coluna `cod_setor` com o código do setor censitário.

    A interpretação dessas colunas, o significado de cada código de
    `tipo_resultado` e as regras de resolução de empates (comuns aos pacotes
    R e Python) estão documentadas na vignette "geocode":
    https://ipea.github.io/geocodebr/articles/geocode.html

    Examples
    --------
    >>> import pyarrow.csv as pv
    >>> from geocodebr import definir_campos, geocode
    >>> enderecos = pv.read_csv("enderecos.csv")
    >>> campos = definir_campos(
    ...     logradouro="nm_logradouro",
    ...     numero="Numero",
    ...     cep="Cep",
    ...     localidade="Bairro",
    ...     municipio="nm_municipio",
    ...     estado="nm_uf",
    ... )
    >>> resultado = geocode(
    ...     enderecos=enderecos,
    ...     campos_endereco=campos,
    ...     resolver_empates=True,
    ...     verboso=False,
    ... )
    """

    if n_cores is not None and (not isinstance(n_cores, int) or n_cores < 1):
        raise ValueError("n_cores deve ser um inteiro positivo ou None.")
    n_cores = n_cores_efetivo(n_cores)

    h3_values = normalize_h3_res(h3_res)
    if campos_endereco is None:
        campos_endereco = definir_campos(estado="estado", municipio="municipio")

    con = create_geocodebr_db(n_cores=n_cores)
    try:

        df_input = _materialize_input(enderecos)
        input_columns = df_input.columns

        check_clean_colnames(input_columns)
        # guarda de nomes reservados: so no geocode() -- o geocode_reverso()
        # exige lat/lon no input e nao pode ser rejeitado por elas
        assert_no_reserved_columns(input_columns)

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
        message_add_precision(verboso)
        add_precision_col(con, output_table_to_use)
        message_merge_input(verboso)
        merge_results_to_input(
            con,
            x="input_db",
            y=output_table_to_use,
            select_columns=original_columns,
            resultado_completo=resultado_completo,
            incluir_empate=not resolver_empates,
        )
        add_h3_columns(con, "geocodebr_result", h3_values)
        message_as_arrow(verboso)
        result = con.execute("SELECT * FROM geocodebr_result").to_arrow_table()
        message_fim(verboso)

        if resultado_gpd:
            return arrow_to_geodataframe(result)

        return result
    finally:
        close_geocodebr_db(con)
        message_conexao_fechada(verboso)


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
