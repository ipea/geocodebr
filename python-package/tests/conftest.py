from pathlib import Path

import pytest

from geocodebr.cache import listar_arquivo_config


@pytest.fixture(autouse=True)
def restore_cache_config():
    config_file = Path(listar_arquivo_config())
    existed = config_file.exists()
    content = config_file.read_text(encoding="utf-8") if existed else None
    yield
    if existed:
        config_file.parent.mkdir(parents=True, exist_ok=True)
        config_file.write_text(content, encoding="utf-8")
    elif config_file.exists():
        config_file.unlink()

