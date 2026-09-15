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


def test_definir_campos_rejects_all_null():
    with pytest.raises(ValueError, match="nao pode ser nulo"):
        definir_campos(estado=None, municipio=None)


def test_assert_and_assign_address_fields_rejects_non_dict():
    from geocodebr.fields import assert_and_assign_address_fields

    with pytest.raises(TypeError, match="dict"):
        assert_and_assign_address_fields(["logradouro"], ["logradouro"])


def test_assert_and_assign_address_fields_rejects_unknown_fields():
    from geocodebr.fields import assert_and_assign_address_fields

    with pytest.raises(ValueError, match="desconhecidos"):
        assert_and_assign_address_fields({"bairro": "b"}, ["b"])


def test_assert_and_assign_address_fields_rejects_missing_column():
    from geocodebr.fields import assert_and_assign_address_fields

    with pytest.raises(ValueError, match="ausentes"):
        assert_and_assign_address_fields({"logradouro": "rua"}, ["outra"])

