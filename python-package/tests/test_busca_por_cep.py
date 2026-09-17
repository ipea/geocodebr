import pytest
import pyarrow as pa

from geocodebr import busca_por_cep
from geocodebr.cep import _normalize_ceps
from geocodebr.errors import SemCorrespondenciaError


def test_normalize_ceps_deduplicates_sorts_and_accepts_int():
    ceps = _normalize_ceps(["70390-025", "70390-025", "", "99999-999", 70390025])

    # dedup + ordenacao; int e string padronizam igual. A string vazia e
    # mantida (diferenca conhecida vs o R, que descarta vazios em
    # busca_por_cep) e vira linha "nao encontrado" no output
    assert ceps == ["", "70390-025", "99999-999"]
    # escalar chega como lista
    assert _normalize_ceps("70390-025") == ["70390-025"]


def test_busca_por_cep_duckdb_flow(cnefe_cache):
    table = pa.table(
        {
            "cep": ["70390-025", "20071-001"],
            "estado": ["DF", "RJ"],
            "municipio": ["BRASILIA", "RIO DE JANEIRO"],
            "logradouro": ["AVENIDA TESTE", "RUA TESTE"],
            "localidade": ["CENTRO", "CENTRO"],
            "lon": [-47.9, -43.2],
            "lat": [-15.8, -22.9],
        }
    )
    cnefe_cache(table, "municipio_logradouro_cep_localidade")

    out = busca_por_cep(["70390-025", "99999-999"], h3_res=3, verboso=False)

    assert out.num_rows == 2
    assert "h3_03" in out.schema.names
    assert out.column("cep").to_pylist() == ["70390-025", "99999-999"]


def test_busca_por_cep_none_found(cnefe_cache):
    table = pa.table(
        {
            "cep": ["70390-025"],
            "estado": ["DF"],
            "municipio": ["BRASILIA"],
            "logradouro": ["AVENIDA TESTE"],
            "localidade": ["CENTRO"],
            "lon": [-47.9],
            "lat": [-15.8],
        }
    )
    cnefe_cache(table, "municipio_logradouro_cep_localidade")

    with pytest.raises(SemCorrespondenciaError, match="Nenhum CEP"):
        busca_por_cep(["99999-999"], verboso=False)
