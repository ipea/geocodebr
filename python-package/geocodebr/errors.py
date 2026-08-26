class GeocodeBRError(Exception):
    """Erro base do geocodebr Python."""

class SemCorrespondenciaError(GeocodeBRError):
    """Todos os nomes coluna de correspondência com campos de endereço nulos"""


class InputNaoPadronizadoError(GeocodeBRError):
    """Entrada sem colunas padronizadas esperadas."""


def error_input_nao_padronizado() -> None:
    raise InputNaoPadronizadoError(
        "Os dados de entrada nao estao padronizados. Use "
        "padronizar_enderecos=True ou informe colunas *_padr equivalentes."
    )

def error_sem_correspondencia() -> None:
    raise SemCorrespondenciaError(
        "Ao menos um dos campos de endreço deve ser não nulo"
    )

