from __future__ import annotations

import tempfile
from pathlib import Path

import duckdb


def create_geocodebr_db(
    db_path: str = "tempdir",
    n_cores: int | None = None,
    load_spatial: bool = False,
) -> duckdb.DuckDBPyConnection:
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


def close_geocodebr_db(con: duckdb.DuckDBPyConnection) -> None:
    """Fecha a conexao e apaga o arquivo do banco se for temporario do pacote.

    Com ``db_path="tempdir"`` (o padrao), o DuckDB recria o arquivo no
    ``connect`` mesmo apos o ``unlink`` do placeholder do NamedTemporaryFile,
    e o arquivo permanece no disco apos ``con.close()`` — um `.duckdb` por
    chamada se acumula no diretorio temporario do sistema. Bancos em memoria
    nao tem arquivo associado e caminhos customizados pelo usuario sao
    preservados.
    """
    paths = [
        row[0]
        for row in con.execute(
            "SELECT path FROM duckdb_databases() WHERE path IS NOT NULL AND path != ''"
        ).fetchall()
    ]
    con.close()
    for path in paths:
        _remove_temp_db_file(path)


def _remove_temp_db_file(path: str) -> None:
    arquivo = Path(path)
    no_diretorio_temporario = _mesmo_diretorio(
        arquivo.parent, Path(tempfile.gettempdir())
    )
    if not (
        no_diretorio_temporario
        and arquivo.name.startswith("geocodebr")
        and arquivo.suffix == ".duckdb"
    ):
        return
    try:
        arquivo.unlink(missing_ok=True)
        # WAL do DuckDB, caso tenha sobrado de um fechamento anormal
        Path(str(arquivo) + ".wal").unlink(missing_ok=True)
    except OSError:
        # remocao cosmetica: nao deve interromper o fluxo do usuario
        pass


def _mesmo_diretorio(a: Path, b: Path) -> bool:
    """Compara dois diretorios resolvendo symlinks e nomes curtos.

    O DuckDB canonicaliza o caminho do banco no connect: no macOS resolve
    o symlink /var -> /private/var e no Windows pode expandir nomes curtos
    8.3 do TEMP, de modo que a comparacao textual com tempfile.gettempdir()
    falha mesmo tratando-se do mesmo diretorio.
    """
    try:
        return a.resolve() == b.resolve()
    except OSError:
        return a.absolute() == b.absolute()

