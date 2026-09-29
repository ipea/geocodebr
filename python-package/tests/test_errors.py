from geocodebr.errors import (
    GeocodeBRError,
    InputNaoPadronizadoError,
    SemCorrespondenciaError,
)


def test_input_nao_padronizado_error_herda_de_geocodebr():
    assert issubclass(InputNaoPadronizadoError, GeocodeBRError)


def test_sem_correspondencia_error_herda_de_geocodebr():
    assert issubclass(SemCorrespondenciaError, GeocodeBRError)
