from __future__ import annotations

import re
from pathlib import Path

import duckdb

from .constants import ALL_POSSIBLE_MATCH_TYPES, DATA_RELEASE, RESERVED_COLUMN_NAMES


def assert_bool(value: bool, name: str) -> None:
    if not isinstance(value, bool):
        raise TypeError(f"{name} deve ser True ou False.")


def normalize_h3_res(h3_res: int | list[int] | tuple[int, ...] | None) -> list[int]:
    if h3_res is None:
        return []
    values = [h3_res] if isinstance(h3_res, int) else list(h3_res)
    for value in values:
        if not isinstance(value, int) or value < 0 or value > 15:
            raise ValueError("h3_res deve conter inteiros entre 0 e 15.")
    return values


def quote_ident(name: str) -> str:
    if not re.match(r"^[A-Za-z0-9_]+$", name):
        raise ValueError(f"Nome SQL invalido: {name}")
    return name


def sql_string(value: str) -> str:
    return "'" + value.replace("'", "''") + "'"


def check_clean_colnames(columns: list[str]) -> None:
    bad_cols = [col for col in columns if not re.match(r"^[A-Za-z0-9_]+$", col)]
    if bad_cols:
        raise ValueError(
            "Column names must use only letters, numbers, and underscores. "
            f"Please rename: {bad_cols}"
        )


def assert_no_reserved_columns(columns: list[str]) -> None:
    reserved_cols = [col for col in columns if col in RESERVED_COLUMN_NAMES]
    if reserved_cols:
        raise ValueError(
            "Reserved column names detected. "
            "These column names are created in the output and cannot be present in the input. "
            f"Please rename: {reserved_cols}"
        )


def get_key_cols(match_type: str) -> list[str]:
    if match_type in {"dn01", "da01", "pn01", "pa01"}:
        return ["estado", "municipio", "logradouro", "numero", "cep", "localidade"]
    if match_type in {"dn02", "da02", "pn02", "pa02"}:
        return ["estado", "municipio", "logradouro", "numero", "cep"]
    if match_type in {"dn03", "da03", "pn03", "pa03"}:
        return ["estado", "municipio", "logradouro", "numero", "localidade"]
    if match_type in {"dn04", "da04", "pn04", "pa04"}:
        return ["estado", "municipio", "logradouro", "numero"]
    if match_type in {"dl01", "pl01"}:
        return ["estado", "municipio", "logradouro", "cep", "localidade"]
    if match_type in {"dl02", "pl02"}:
        return ["estado", "municipio", "logradouro", "cep"]
    if match_type in {"dl03", "pl03"}:
        return ["estado", "municipio", "logradouro", "localidade"]
    if match_type in {"dl04", "pl04"}:
        return ["estado", "municipio", "logradouro"]
    if match_type == "dc01":
        return ["estado", "municipio", "cep", "localidade"]
    if match_type == "dc02":
        return ["estado", "municipio", "cep"]
    if match_type == "db01":
        return ["estado", "municipio", "localidade"]
    if match_type == "dm01":
        return ["estado", "municipio"]
    raise ValueError(f"match_type desconhecido: {match_type}")


def get_reference_table(match_type: str) -> str:
    key_cols = get_key_cols(match_type)
    table_name = "_".join(key_cols).replace("estado_municipio", "municipio")

    if re.search(r"dn02|pn02|da02|pa02|dn03|pn03", match_type):
        table_name = "municipio_logradouro_numero_cep_localidade"
    if re.search(r"da03|pa03|dn04|da04", match_type):
        table_name = "municipio_logradouro_numero_localidade"
    if re.search(r"dl02|pl02|dl03|pl03", match_type):
        table_name = "municipio_logradouro_cep_localidade"
    if re.search(r"dl04", match_type):
        table_name = "municipio_logradouro_localidade"

    return table_name


def tabelas_necessarias(campos_nao_declarados: list[str]) -> list[str]:
    """Subconjunto de tabelas do CNEFE que o laço de matching vai usar.

    Espelha ``tabelas_necessarias()`` em ``r-package/R/utils.R:496-504``:
    filtra ``ALL_POSSIBLE_MATCH_TYPES`` excluindo os match_types cujas
    ``key_cols`` incluam algum campo em ``campos_nao_declarados``, mapeia
    via ``get_reference_table`` e dedup.
    """
    ativos = [
        mt
        for mt in ALL_POSSIBLE_MATCH_TYPES
        if not any(col in campos_nao_declarados for col in get_key_cols(mt))
    ]
    return list(dict.fromkeys(get_reference_table(mt) for mt in ativos))


def get_prob_match_cutoff(match_type: str) -> float:
    return 0.85 if match_type in {"pn01", "pa01", "pl01"} else 0.9


def find_cached_parquet(cache_files: list[str], table_name: str) -> str:
    suffix = f"{table_name}.parquet"
    matches = [
        file
        for file in cache_files
        if Path(file).name == suffix and DATA_RELEASE in str(file)
    ]
    if not matches:
        raise FileNotFoundError(
            f"Arquivo {suffix} nao encontrado no cache. Execute download_cnefe()."
        )
    return matches[0].replace("\\", "/")


def db_table_columns(con: duckdb.DuckDBPyConnection, table_name: str) -> list[str]:
    return [row[1] for row in con.execute(f"PRAGMA table_info('{table_name}')").fetchall()]


def update_input_db(
    con: duckdb.DuckDBPyConnection,
    update_tb: str = "input_padrao_db",
    reference_tb: str = "output_db",
) -> int:
    before = con.execute(f"SELECT COUNT(*) FROM {quote_ident(update_tb)}").fetchone()[0]
    con.execute(
        f"""
        DELETE FROM {quote_ident(update_tb)}
        WHERE tempidgeocodebr IN (
          SELECT tempidgeocodebr FROM {quote_ident(reference_tb)}
        )
        """
    )
    after = con.execute(f"SELECT COUNT(*) FROM {quote_ident(update_tb)}").fetchone()[0]
    return before - after


def add_precision_col(con: duckdb.DuckDBPyConnection, update_tb: str) -> None:
    update_tb = quote_ident(update_tb)
    con.execute(f"ALTER TABLE {update_tb} ADD COLUMN precisao TEXT")
    con.execute(
        f"""
        UPDATE {update_tb}
        SET precisao = CASE
          WHEN tipo_resultado IN ('dn01', 'dn02', 'dn03', 'dn04',
                                  'pn01', 'pn02', 'pn03', 'pn04') THEN 'numero'
          WHEN tipo_resultado IN ('da01', 'da02', 'da03', 'da04',
                                  'pa01', 'pa02', 'pa03', 'pa04') THEN 'numero_aproximado'
          WHEN tipo_resultado IN ('dl01', 'dl02', 'dl03', 'dl04',
                                  'pl01', 'pl02', 'pl03', 'pl04') THEN 'logradouro'
          WHEN tipo_resultado IN ('dc01', 'dc02') THEN 'cep'
          WHEN tipo_resultado = 'db01' THEN 'localidade'
          WHEN tipo_resultado = 'dm01' THEN 'municipio'
          ELSE NULL
        END
        """
    )


def merge_results_to_input(
    con: duckdb.DuckDBPyConnection,
    x: str,
    y: str,
    select_columns: list[str],
    resultado_completo: bool,
    incluir_empate: bool = False,
) -> None:
    select_columns_y = [
        "lat",
        "lon",
        "precisao",
        "tipo_resultado",
        "desvio_metros",
        "endereco_encontrado",
    ]

    # com resolver_empates = False os casos empatados voltam em duplicidade
    # (uma linha por candidato), entao a coluna 'empate' precisa acompanhar o
    # output mesmo sem resultado_completo, para o usuario identificar essas
    # linhas. Com resultado_completo = True ela ja entra na lista abaixo.
    if incluir_empate and not resultado_completo:
        select_columns_y.append('empate')

    if resultado_completo:
        select_columns_y.extend(
            [
                "logradouro_encontrado",
                "numero_encontrado",
                "cep_encontrado",
                "localidade_encontrada",
                "municipio_encontrado",
                "estado_encontrado",
                "similaridade_logradouro",
                "contagem_cnefe",
                "empate",
                "cod_setor",
            ]
        )

    # espelha o setdiff(select_columns, key_column) do R: tempidgeocodebr é
    # interno e sai da projeção, eliminando o re-sort com EXCLUDE no geocode()
    select_x = ", ".join(
        f"{quote_ident(x)}.{quote_ident(col)}"
        for col in select_columns
        if col != "tempidgeocodebr"
    )

    # COALESCE na projeção substitui o UPDATE de tabela inteira (mesma
    # semântica: match determinístico tem similaridade NULL, exibida como 1)
    y_exprs: list[str] = []
    for col in select_columns_y:
        if resultado_completo and col == "similaridade_logradouro":
            expr = f"COALESCE({quote_ident(y)}.similaridade_logradouro, 1)"
        else:
            expr = f"{quote_ident(y)}.{quote_ident(col)}"
        y_exprs.append(f"{expr} AS {quote_ident(col)}")
    select_y = ", ".join(y_exprs)
    con.execute(
        f"""
        CREATE OR REPLACE TEMP TABLE geocodebr_result AS
        SELECT {select_x}, {select_y}
        FROM {quote_ident(x)}
        LEFT JOIN {quote_ident(y)}
          ON {quote_ident(x)}.tempidgeocodebr = {quote_ident(y)}.tempidgeocodebr
        ORDER BY {quote_ident(x)}.tempidgeocodebr
        """
    )


def cria_col_logradouro_confusao(con: duckdb.DuckDBPyConnection) -> None:
    con.execute("ALTER TABLE input_padrao_db ADD COLUMN log_causa_confusao BOOLEAN DEFAULT false")
    ruas_num_ext = "|".join(
        "RUA " + value
        for value in ["UM", "DOIS", "TRES", "QUATRO", "CINCO", "SEIS", "SETE", "OITO", "NOVE", "DEZ", "ONZE", "DOZE", "TREZE"]
    )
    con.execute(
        rf"""
        UPDATE input_padrao_db
        SET log_causa_confusao = true
        WHERE
          (
            REGEXP_MATCHES(logradouro, '^(RUA|TRAVESSA|RAMAL|BECO|BLOCO|AVENIDA|RODOVIA|ESTRADA)\s+([A-Z]{{1,2}}-?|[0-9]{{1,3}}|[A-Z]{{1,2}}-?[0-9]{{1,3}}|[A-Z]{{1,2}}\s+[0-9]{{1,3}}|[0-9]{{1,3}}-?[A-Z]{{1,2}})(\s+KM( \d+)?)?$')
            OR REGEXP_MATCHES(logradouro, '({ruas_num_ext})$')
          )
          AND NOT REGEXP_MATCHES(logradouro, '\bDE (JANEIRO|FEVEREIRO|MARCO|ABRIL|MAIO|JUNHO|JULHO|AGOSTO|SETEMBRO|OUTUBRO|NOVEMBRO|DEZEMBRO)\b')
        """
    )


def add_h3_columns(
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

