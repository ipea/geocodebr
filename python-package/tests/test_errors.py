import pytest

from geocodebr.errors import (
    InputNaoPadronizadoError,
    error_input_nao_padronizado,
)


def test_error_input_nao_padronizado():
    with pytest.raises(InputNaoPadronizadoError, match="padronizados"):
        error_input_nao_padronizado()
