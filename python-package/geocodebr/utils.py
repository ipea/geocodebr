from __future__ import annotations

import re
from pathlib import Path

import duckdb

from .constants import DATA_RELEASE, RESERVED_COLUMN_NAMES


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

