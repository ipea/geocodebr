from __future__ import annotations

import shutil
from pathlib import Path

try:
    from platformdirs import user_cache_dir, user_config_dir
except ModuleNotFoundError:  # pragma: no cover
    def user_cache_dir(appname: str) -> str:
        return str(Path.home() / "AppData" / "Local" / appname / "Cache")

    def user_config_dir(appname: str) -> str:
        return str(Path.home() / "AppData" / "Roaming" / appname)

from .messages import message_cache
from .constants import DATA_RELEASE


def caminho_parquet(nome_tabela: str, pasta_dados: str | None = None) -> str:
    """Monta o caminho de um arquivo parquet do CNEFE no disco.

    Espelha ``caminho_parquet()`` em ``r-package/R/cache.R``. ``pasta_dados`` e
    o ``data_release`` vigente ja foram resolvidos pelo chamador (via
    ``download_cnefe``), nao sao redescobertos aqui. O arquivo nao precisa
    existir.
    """
    if not isinstance(nome_tabela, str):
        raise TypeError("nome_tabela deve ser uma string.")
    if pasta_dados is None:
        pasta_dados = listar_pasta_cache()
    if not isinstance(pasta_dados, str):
        raise TypeError("pasta_dados deve ser uma string.")

    path = Path(pasta_dados) / f"geocodebr_data_release_{DATA_RELEASE}" / f"{nome_tabela}.parquet"
    return path.as_posix()


def listar_pasta_cache_padrao() -> str:
    return str(Path(user_cache_dir("geocodebr")))


def listar_arquivo_config() -> str:
    return str(Path(user_config_dir("geocodebr")) / "cache_dir")


def definir_pasta_cache(path: str | None, verboso: bool = True) -> str:
    if path is not None and not isinstance(path, str):
        raise TypeError("path deve ser uma string ou None.")
    if not isinstance(verboso, bool):
        raise TypeError("verboso deve ser True ou False.")

    cache_dir = Path(listar_pasta_cache_padrao()) if path is None else Path(path)
    cache_dir = cache_dir.expanduser()

    config_file = Path(listar_arquivo_config())
    config_file.parent.mkdir(parents=True, exist_ok=True)
    config_file.write_text(str(cache_dir), encoding="utf-8")

    if verboso:
        print(f"Definido como pasta de cache {cache_dir}.")

    return str(cache_dir)


def listar_pasta_cache() -> str:
    config_file = Path(listar_arquivo_config())
    if config_file.exists():
        value = config_file.read_text(encoding="utf-8").strip()
        if value:
            return str(Path(value).expanduser())
    return listar_pasta_cache_padrao()


def listar_dados_cache(print_tree: bool = False) -> list[str]:
    if not isinstance(print_tree, bool):
        raise TypeError("print_tree deve ser True ou False.")

    cache_dir = Path(listar_pasta_cache())
    if not cache_dir.exists():
        message_cache(True)
        return []

    files = sorted(str(path) for path in cache_dir.rglob("*") if path.is_file())
    if print_tree:
        _print_tree(cache_dir)
    return files


def deletar_pasta_cache() -> str:
    cache_dir = Path(listar_pasta_cache())
    if cache_dir.exists():
        shutil.rmtree(cache_dir)
    print(f"Deletada a pasta de cache que se encontrava em {cache_dir}.")
    return str(cache_dir)


def apaga_data_release_antigo(data_release: str) -> str:
    cache_dir = Path(listar_pasta_cache())
    if not cache_dir.exists():
        return str(cache_dir)

    release_dirs = [
        path
        for path in cache_dir.iterdir()
        if path.is_dir() and path.name.startswith("geocodebr_data_release_")
    ]
    expected = cache_dir / f"geocodebr_data_release_{data_release}"
    stale_dirs = [path for path in release_dirs if path != expected]
    for path in stale_dirs:
        shutil.rmtree(path)
    return str(cache_dir)


def _print_tree(root: Path) -> None:
    print(root)
    for path in sorted(root.rglob("*")):
        depth = len(path.relative_to(root).parts)
        prefix = "  " * depth
        print(f"{prefix}{path.name}")
