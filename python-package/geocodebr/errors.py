class GeocodeBRError(Exception):
    """Erro base do geocodebr Python."""


class InputNaoPadronizadoError(GeocodeBRError):
    """Entrada sem colunas padronizadas esperadas."""


class SemCorrespondenciaError(GeocodeBRError):
    """Busca não encontrou nenhum resultado no CNEFE."""

