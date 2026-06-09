from __future__ import annotations

import tempfile
from pathlib import Path

import duckdb


def create_geocodebr_db(
    db_path: str = "tempdir",
    n_cores: int | None = None,
    load_spatial: bool = False,
) -> duckdb.DuckDBPyConnection:
    if n_cores is not None and (not isinstance(n_cores, int) or n_cores < 1):
        raise ValueError("n_cores deve ser um inteiro positivo ou None.")

    if db_path == "tempdir":
        handle = tempfile.NamedTemporaryFile(prefix="geocodebr", suffix=".duckdb", delete=True)
        db_file = handle.name
        handle.close()
        Path(db_file).unlink(missing_ok=True)
    elif db_path == "memory":
        db_file = ":memory:"
    else:
        db_file = db_path

    con = duckdb.connect(db_file)
    if n_cores is not None:
        con.execute(f"SET threads = {n_cores}")
    con.execute("SET enable_progress_bar = false")

    if load_spatial:
        con.execute("INSTALL spatial")
        con.execute("LOAD spatial")

    return con

