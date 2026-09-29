from __future__ import annotations

import duckdb

from .cache import caminho_parquet
from .match_types import (
    ALL_POSSIBLE_MATCH_TYPES,
    get_key_cols,
    get_reference_table,
    tables_still_needed,
)
from .utils import quote_ident


def drop_obsolete_tables(
    con: duckdb.DuckDBPyConnection,
    remaining_match_types: list[str],
    campos_nao_declarados: list[str],
) -> None:
    """Drop the temporary tables that no remaining step of the loop uses.

    DuckDB frees the memory of a TEMP TABLE on DROP; without this, the largest
    reference tables (~10 GB each at national scale) would stay alive until
    the end of geocode(). Mirrors ``dropa_tabelas_obsoletas()`` in R.
    """
    candidates = {get_reference_table(mt) for mt in ALL_POSSIBLE_MATCH_TYPES} | {
        "unique_logr_municipio_logradouro_localidade",
        "unique_logr_municipio_logradouro_cep_localidade",
    }
    needed = tables_still_needed(remaining_match_types, campos_nao_declarados)
    for tb in sorted(candidates - needed):
        con.execute(f"DROP TABLE IF EXISTS {quote_ident(tb)}")


def register_cnefe_table(
    con: duckdb.DuckDBPyConnection,
    match_type: str,
    pasta_dados: str | None = None,
    resultado_completo: bool = True,
) -> bool:
    cnefe_table_name = get_reference_table(match_type)
    exists = con.execute(
        "SELECT COUNT(*) FROM information_schema.tables WHERE table_name = ?",
        [cnefe_table_name],
    ).fetchone()[0]
    if exists:
        return True

    path_to_parquet = caminho_parquet(cnefe_table_name, pasta_dados)

    # columns that no query reads: code_muni and n_setor never; cod_setor only
    # with resultado_completo. Mirrors register_cnefe_table() in R (~10% less
    # memory). The list comes from the parquet schema because EXCLUDE of a
    # nonexistent column is an error in DuckDB
    exclude = ["code_muni", "n_setor"] + ([] if resultado_completo else ["cod_setor"])
    present = {
        r[0]
        for r in con.execute(
            f"DESCRIBE SELECT * FROM read_parquet('{path_to_parquet}')"
        ).fetchall()
    }
    exclude = [c for c in exclude if c in present]
    projection = f"* EXCLUDE ({', '.join(exclude)})" if exclude else "*"

    con.execute(
        f"""
        CREATE TEMP TABLE IF NOT EXISTS {quote_ident(cnefe_table_name)} AS
        WITH unique_munis AS (
            SELECT DISTINCT municipio FROM input_padrao_db
        ),
        unique_states AS (
            SELECT DISTINCT estado FROM input_padrao_db
        )
        SELECT {projection}
        FROM read_parquet('{path_to_parquet}') m
        WHERE m.estado IN (SELECT estado FROM unique_states)
          AND m.municipio IN (SELECT municipio FROM unique_munis)
        """
    )
    return True


def register_unique_logradouros_table(
    con: duckdb.DuckDBPyConnection,
    match_type: str,
    pasta_dados: str | None = None,
) -> str:
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
        path_to_parquet = caminho_parquet(cnefe_table_name, pasta_dados)
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
            FROM read_parquet('{path_to_parquet}') m
            WHERE m.estado IN (SELECT estado FROM unique_states)
              AND m.municipio IN (SELECT municipio FROM unique_munis)
            """
        )
    return table_name

