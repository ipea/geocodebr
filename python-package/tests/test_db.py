import tempfile
from pathlib import Path

import duckdb
import pytest

from geocodebr.db import close_geocodebr_db, create_geocodebr_db


def test_create_db_default_tempdir():
    con = create_geocodebr_db()
    try:
        con.execute("CREATE TEMP TABLE t AS SELECT 1 AS v")
        assert con.execute("SELECT COUNT(*) FROM t").fetchone()[0] == 1
    finally:
        con.close()


def test_close_geocodebr_db_remove_temp_file():
    con = create_geocodebr_db()
    db_file = Path(
        con.execute("SELECT path FROM duckdb_databases()").fetchone()[0]
    )
    assert db_file.exists()
    close_geocodebr_db(con)
    assert not db_file.exists()
    assert not Path(str(db_file) + ".wal").exists()


def test_close_geocodebr_db_keeps_custom_file(tmp_path):
    db_file = tmp_path / "meu_banco.duckdb"
    con = create_geocodebr_db(db_path=str(db_file))
    close_geocodebr_db(con)
    assert db_file.exists()


def test_close_geocodebr_db_ignores_other_files_in_tempdir(monkeypatch):
    # banco nao-geocodebr no tempdir do sistema nao pode ser apagado
    con = create_geocodebr_db()
    db_file = Path(
        con.execute("SELECT path FROM duckdb_databases()").fetchone()[0]
    )
    outro = Path(tempfile.gettempdir()) / "outro_pacote.duckdb"
    duckdb.connect(str(outro)).close()
    try:
        close_geocodebr_db(con)
        assert not db_file.exists()
        assert outro.exists()
    finally:
        outro.unlink(missing_ok=True)


def test_create_db_memory_with_n_cores():
    con = create_geocodebr_db(db_path="memory", n_cores=2)
    try:
        assert con.execute("SELECT current_setting('threads')").fetchone()[0] == 2
    finally:
        con.close()


def test_create_db_with_custom_path(tmp_path):
    db_file = tmp_path / "meu_banco.duckdb"
    con = create_geocodebr_db(db_path=str(db_file))
    try:
        con.execute("CREATE TABLE t AS SELECT 1 AS v")
    finally:
        con.close()
    assert db_file.exists()
