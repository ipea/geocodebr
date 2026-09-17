from __future__ import annotations

import shutil
from pathlib import Path

from platformdirs import user_cache_dir, user_config_dir

from .messages import confirm
from .constants import DATA_RELEASE


def caminho_parquet(nome_tabela: str, pasta_dados: str | None = None) -> str:
    """Monta o caminho de um arquivo parquet do CNEFE no disco.

    Espelha ``caminho_parquet()`` em ``r-package/R/cache.R``. ``pasta_dados`` e
    o ``data_release`` vigente já foram resolvidos pelo chamador (via
    ``download_cnefe``), não são redescobertos aqui. O arquivo não precisa
    existir.
    """
    if pasta_dados is None:
        pasta_dados = listar_pasta_cache()

    path = Path(pasta_dados) / f"geocodebr_data_release_{DATA_RELEASE}" / f"{nome_tabela}.parquet"
    return path.as_posix()


def listar_pasta_cache_padrao() -> str:
    return str(Path(user_cache_dir("geocodebr")))


def listar_arquivo_config() -> str:
    return str(Path(user_config_dir("geocodebr")) / "cache_dir")


def definir_pasta_cache(path: str | None, verboso: bool = True) -> str:
    """Define a pasta de cache do geocodebr.

    Define o diretório de cache para os dados do geocodebr. Essa configuração
    é persistente entre sessões do Python.

    Parameters
    ----------
    path : str ou None
        O caminho para o diretório usado para armazenar os dados em cache.
        Se `None`, o pacote usará o diretório padrão do pacote.
    verboso : bool, opcional
        Indica se uma mensagem de confirmação deve ser exibida. O padrão é
        `True`.

    Returns
    -------
    str
        O caminho do diretório de cache configurado.

    Examples
    --------
    >>> definir_pasta_cache("D:/dados/geocodebr-cache")

    # retoma pasta padrão do pacote
    >>> definir_pasta_cache(path=None)
    """
    cache_dir = Path(listar_pasta_cache_padrao()) if path is None else Path(path)
    cache_dir = cache_dir.expanduser()

    config_file = Path(listar_arquivo_config())
    config_file.parent.mkdir(parents=True, exist_ok=True)
    config_file.write_text(str(cache_dir), encoding="utf-8")

    if verboso:
        confirm(f"Definido como pasta de cache {cache_dir}.")

    return str(cache_dir)


def listar_pasta_cache() -> str:
    """Obtém a pasta de cache usada pelo geocodebr.

    Obtém o caminho da pasta utilizada para armazenar em cache os dados do
    geocodebr. Útil para inspecionar a pasta configurada com
    `definir_pasta_cache()` em uma sessão anterior. Retorna a pasta de cache
    padrão caso nenhuma pasta personalizada tenha sido configurada
    anteriormente.

    Returns
    -------
    str
        O caminho da pasta de cache.
    """
    config_file = Path(listar_arquivo_config())
    if config_file.exists():
        value = config_file.read_text(encoding="utf-8").strip()
        if value:
            return str(Path(value).expanduser())
    return listar_pasta_cache_padrao()


def listar_dados_cache(print_tree: bool = False) -> list[str]:
    """Lista os dados salvos localmente na pasta de cache.

    Parameters
    ----------
    print_tree : bool, opcional
        Indica se o conteúdo da pasta de cache deve ser exibido em um formato
        de árvore. O padrão é `False`.

    Returns
    -------
    list[str]
        Os caminhos para os arquivos em cache.
    """
    cache_dir = Path(listar_pasta_cache())
    if not cache_dir.exists():
        confirm("Nenhum dado em cache local")
        return []

    files = sorted(str(path) for path in cache_dir.rglob("*") if path.is_file())
    if print_tree:
        _print_tree(cache_dir)
    return files


def deletar_pasta_cache() -> str:
    """Deleta todos os arquivos da pasta de cache do geocodebr.

    Returns
    -------
    str
        O caminho do diretório de cache deletado.
    """
    cache_dir = Path(listar_pasta_cache())
    if cache_dir.exists():
        shutil.rmtree(cache_dir)
    confirm(f"Deletada a pasta de cache que se encontrava em {cache_dir}.")
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
