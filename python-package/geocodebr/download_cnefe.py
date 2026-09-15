from __future__ import annotations

import tempfile
from collections.abc import Iterable
from pathlib import Path

import requests
from tqdm import tqdm

from .cache import apaga_data_release_antigo, listar_pasta_cache
from .constants import ALL_CNEFE_FILES, DATA_RELEASE
from .messages import message_baixando_cnefe, message_usando_cnefe_local


def download_cnefe(
    tabela: str | Iterable[str] = "todas",
    verboso: bool = True,
    cache: bool = True,
) -> str:
    if not isinstance(tabela, Iterable):
        raise TypeError("`tabela` deve ser uma string ou lista de strings.")

    files = _select_files(tabela)
    urls = [
        f"https://github.com/ipeaGIT/padronizacao_cnefe/releases/download/{DATA_RELEASE}/{file}"
        for file in files
    ]

    if cache:
        apaga_data_release_antigo(DATA_RELEASE)
        cache_dir = Path(listar_pasta_cache())
    else:
        cache_dir = Path(tempfile.mkdtemp(prefix="geocodebr_temp"))

    data_dir = cache_dir / f"geocodebr_data_release_{DATA_RELEASE}"
    data_dir.mkdir(parents=True, exist_ok=True)

    existing = {path.name for path in data_dir.iterdir() if path.is_file()}
    to_download = [(url, data_dir / Path(url).name) for url in urls if Path(url).name not in existing]

    if not to_download:
        message_usando_cnefe_local(verboso)
        return str(cache_dir)

    message_baixando_cnefe(verboso)
    for url, dest in tqdm(to_download, disable=not verboso):
        _download_file(url, dest)

    return str(cache_dir)


def _select_files(tabela: str | Iterable[str]) -> list[str]:
    if tabela == "todas":
        return ALL_CNEFE_FILES.copy()

    valid = {Path(file).stem: file for file in ALL_CNEFE_FILES}
    tabelas = [tabela] if isinstance(tabela, str) else list(tabela)
    invalidas = [t for t in tabelas if t not in valid]
    if invalidas:
        options = ", ".join(sorted(valid))
        invalidas_str = ", ".join(map(str, invalidas))
        raise ValueError(
            f"`tabela` deve ser 'todas' ou um vetor com uma ou mais das "
            f"seguintes opções: {options}. Valores inválidos: {invalidas_str}."
        )
    # Lista vazia (character(0) no R) e valida: devolve [] sem baixar nada
    return [valid[t] for t in tabelas]


def _download_file(url: str, dest: Path) -> None:
    tmp = dest.with_suffix(dest.suffix + ".part")
    with requests.get(url, stream=True, timeout=120) as response:
        response.raise_for_status()
        with tmp.open("wb") as file:
            for chunk in response.iter_content(chunk_size=1024 * 1024):
                if chunk:
                    file.write(chunk)
    tmp.replace(dest)

