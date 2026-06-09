from __future__ import annotations

import duckdb

from .cache import listar_dados_cache
from .utils import find_cached_parquet, get_key_cols, get_reference_table, quote_ident


def register_cnefe_table(con: duckdb.DuckDBPyConnection, match_type: str) -> bool:
    cnefe_table_name = get_reference_table(match_type)
    exists = con.execute(
        "SELECT COUNT(*) FROM information_schema.tables WHERE table_name = ?",
        [cnefe_table_name],
    ).fetchone()[0]
    if exists:
        return True

    path_to_parquet = find_cached_parquet(listar_dados_cache(), cnefe_table_name)
    con.execute(
        f"""
        CREATE TEMP TABLE IF NOT EXISTS {quote_ident(cnefe_table_name)} AS
        WITH unique_munis AS (
            SELECT DISTINCT municipio FROM input_padrao_db
        ),
        unique_states AS (
            SELECT DISTINCT estado FROM input_padrao_db
        )
        SELECT *
        FROM read_parquet('{path_to_parquet}') m
        WHERE m.estado IN (SELECT estado FROM unique_states)
          AND m.municipio IN (SELECT municipio FROM unique_munis)
        """
    )
    return True


def register_unique_logradouros_table(con: duckdb.DuckDBPyConnection, match_type: str) -> str:
    key_cols = get_key_cols(match_type)
    cnefe_table_name = (
        "municipio_logradouro_localidade"
        if match_type in {"pn03", "pa03", "pl03"}
        else "municipio_logradouro_cep_localidade"
    )
    table_name = f"unique_logr_{cnefe_table_name}"
    exists = con.execute(
        "SELECT COUNT(*) FROM information_schema.tables WHERE table_name = ?",
        [table_name],
    ).fetchone()[0]
    if exists:
        return table_name

    select_cols = [col for col in key_cols if col != "numero"]
    distinct = ""
    if not (cnefe_table_name == "municipio_logradouro_localidade" or {"localidade", "cep"} <= set(select_cols)):
        distinct = "DISTINCT"
    select_cols_sql = ", ".join(quote_ident(col) for col in select_cols)

    base_exists = con.execute(
        "SELECT COUNT(*) FROM information_schema.tables WHERE table_name = ?",
        [cnefe_table_name],
    ).fetchone()[0]
    if base_exists:
        con.execute(
            f"""
            CREATE TEMP TABLE IF NOT EXISTS {quote_ident(table_name)} AS
            WITH unique_munis AS (
                SELECT DISTINCT municipio FROM input_padrao_db
            ),
            unique_states AS (
                SELECT DISTINCT estado FROM input_padrao_db
            )
            SELECT {distinct} {select_cols_sql}
            FROM {quote_ident(cnefe_table_name)}
            WHERE estado IN (SELECT estado FROM unique_states)
              AND municipio IN (SELECT municipio FROM unique_munis)
            """
        )
    else:
        path_to_parquet = find_cached_parquet(listar_dados_cache(), cnefe_table_name)
        con.execute(
            f"""
            CREATE TEMP TABLE IF NOT EXISTS {quote_ident(table_name)} AS
            WITH unique_munis AS (
                SELECT DISTINCT municipio FROM input_padrao_db
            )
            SELECT {distinct} {select_cols_sql}
            FROM read_parquet('{path_to_parquet}') m
            WHERE m.municipio IN (SELECT municipio FROM unique_munis)
            """
        )
    return table_name

