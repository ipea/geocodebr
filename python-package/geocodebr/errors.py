class GeocodeBRError(Exception):
    """Erro base do geocodebr Python."""


class InputNaoPadronizadoError(GeocodeBRError):
    """Entrada sem colunas padronizadas esperadas."""


def error_input_nao_padronizado() -> None:
    raise InputNaoPadronizadoError(
        "Os dados de entrada nao estao padronizados. Use "
        "padronizar_enderecos=True ou informe colunas *_padr equivalentes."
    )

