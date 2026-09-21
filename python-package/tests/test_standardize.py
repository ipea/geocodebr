import polars as pl
import pytest

from geocodebr.standardize import enderecobr_padronizar_enderecos


def make_df(**overrides):
    data = {
        "logradouro": ["RUA DONA JUDITE"],
        "numero": ["7"],
        "cep": ["23915700"],
        "localidade": ["CAPUTERA II"],
        "municipio": ["ANGRA DOS REIS"],
        "estado": ["RJ"],
        "extra": ["x"],
    }
    data.update(overrides)
    return pl.DataFrame(data)


FIELDS = {
    "logradouro": "logradouro",
    "numero": "numero",
    "cep": "cep",
    "localidade": "localidade",
    "municipio": "municipio",
    "estado": "estado",
}


def test_rejects_non_polars():
    with pytest.raises(TypeError, match="pl.DataFrame"):
        enderecobr_padronizar_enderecos({"estado": "RJ"}, FIELDS)


def test_rejects_invalid_estado_format():
    with pytest.raises(ValueError, match="formato_estados"):
        enderecobr_padronizar_enderecos(make_df(), FIELDS, formato_estados="uc")


def test_rejects_invalid_numero_format():
    with pytest.raises(ValueError, match="formato_numeros"):
        enderecobr_padronizar_enderecos(make_df(), FIELDS, formato_numeros="int")


def test_cep_numeric_and_string_produce_same_result():
    out_str = enderecobr_padronizar_enderecos(make_df(), FIELDS)
    out_int = enderecobr_padronizar_enderecos(make_df(cep=[23915700]), FIELDS)

    assert out_str["cep_padr"].to_list() == ["23915-700"]
    assert out_int["cep_padr"].to_list() == ["23915-700"]


def test_numero_integer_with_character_format():
    out = enderecobr_padronizar_enderecos(
        make_df(numero=[0]), FIELDS, formato_numeros="character"
    )
    assert out["numero_padr"].to_list() == ["S/N"]


def test_numero_integer_format_zero_becomes_null():
    df = make_df(
        logradouro=["RUA A", "RUA B"],
        numero=[7, 0],
        cep=["23915700", "23915700"],
        localidade=["C1", "C2"],
        municipio=["ANGRA DOS REIS", "ANGRA DOS REIS"],
        estado=["RJ", "RJ"],
        extra=["x", "y"],
    )
    out = enderecobr_padronizar_enderecos(df, FIELDS)
    assert out["numero_padr"].to_list() == [7, None]


def test_numero_string_with_character_format():
    out = enderecobr_padronizar_enderecos(
        make_df(numero=["S/N"]), FIELDS, formato_numeros="character"
    )
    assert out["numero_padr"].to_list() == ["S/N"]


def test_estado_por_extenso_format():
    out = enderecobr_padronizar_enderecos(
        make_df(), FIELDS, formato_estados="por_extenso"
    )
    assert out["estado_padr"].to_list() == ["RIO DE JANEIRO"]


def test_manter_cols_extras_false():
    out = enderecobr_padronizar_enderecos(make_df(), FIELDS, manter_cols_extras=False)
    assert out.columns == [
        "logradouro_padr",
        "numero_padr",
        "cep_padr",
        "localidade_padr",
        "municipio_padr",
        "estado_padr",
    ]
