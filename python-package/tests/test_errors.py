import pytest

from geocodebr.errors import (
    InputNaoPadronizadoError,
    SemCorrespondenciaError,
    error_input_nao_padronizado,
    error_sem_correspondencia,
)


def test_error_input_nao_padronizado():
    with pytest.raises(InputNaoPadronizadoError, match="padronizados"):
        error_input_nao_padronizado()


def test_error_sem_correspondencia():
    with pytest.raises(SemCorrespondenciaError, match="não nulo"):
        error_sem_correspondencia()
