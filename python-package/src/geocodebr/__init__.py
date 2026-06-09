from .cache import (
    definir_pasta_cache,
    deletar_pasta_cache,
    listar_dados_cache,
    listar_pasta_cache,
)
from .download_cnefe import download_cnefe
from .fields import definir_campos
from .geocode import busca_por_cep, geocode

try:
    from .reverse import geocode_reverso
except Exception:  # pragma: no cover
    geocode_reverso = None

__all__ = [
    "busca_por_cep",
    "definir_campos",
    "definir_pasta_cache",
    "deletar_pasta_cache",
    "download_cnefe",
    "geocode",
    "geocode_reverso",
    "listar_dados_cache",
    "listar_pasta_cache",
]

