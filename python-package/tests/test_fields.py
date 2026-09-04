import pytest

from geocodebr import definir_campos


def test_definir_campos_preserves_public_names():
    campos = definir_campos(
        estado="uf",
        municipio="cidade",
        logradouro="rua",
        numero="num",
        cep="cep",
        localidade="bairro",
    )
    assert list(campos) == ["logradouro", "numero", "cep", "localidade", "municipio", "estado"]
    assert campos["estado"] == "uf"


def test_definir_campos_rejects_non_string():
    with pytest.raises(TypeError):
        definir_campos(estado="uf", municipio=1)

