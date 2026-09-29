import pandas as pd
import polars as pl
import pyarrow as pa
import pyarrow.parquet as pq
import pytest

from geocodebr import definir_campos, geocode
from geocodebr.errors import InputNaoPadronizadoError
from geocodebr.geocode import _materialize_input


def test_geocode_exact_number_match_with_duckdb(cnefe_cache):
    cnefe = pa.table(
        {
            "estado": ["DF"],
            "municipio": ["BRASILIA"],
            "logradouro": ["AVENIDA TESTE"],
            "numero": [100],
            "cep": ["70000-000"],
            "localidade": ["CENTRO"],
            "lon": [-47.9],
            "lat": [-15.8],
            "endereco_completo": ["AVENIDA TESTE, 100 - CENTRO, BRASILIA - DF"],
            "desvio_metros": [10],
            "n_casos": [1],
            "cod_setor": ["001"],
        }
    )
    cnefe_cache(cnefe)

    addresses = pa.table(
        {
            "uf": ["Distrito Federal"],
            "cidade": ["Brasilia"],
            "rua": ["Avenida Teste"],
            "num": ["100"],
            "cep_in": ["70000-000"],
            "bairro": ["Centro"],
        }
    )
    fields = definir_campos(
        estado="uf",
        municipio="cidade",
        logradouro="rua",
        numero="num",
        cep="cep_in",
        localidade="bairro",
    )

    out = geocode(addresses, fields, resultado_completo=True, h3_res=3, verboso=False)

    assert out.num_rows == 1
    assert out.column("tipo_resultado").to_pylist() == ["dn01"]
    assert out.column("precisao").to_pylist() == ["numero"]
    assert "h3_03" in out.schema.names


def test_geocode_treats_zero_number_as_missing(cnefe_cache):
    cnefe = pa.table(
        {
            "estado": ["RJ"],
            "municipio": ["ANGRA DOS REIS"],
            "logradouro": ["RUA DONA JUDITE"],
            "numero": [7],
            "cep": ["23915-700"],
            "localidade": ["CAPUTERA II"],
            "lon": [-44.2],
            "lat": [-22.9],
            "endereco_completo": ["RUA DONA JUDITE, 7 - CAPUTERA II, ANGRA DOS REIS - RJ, 23915-700"],
            "desvio_metros": [10],
            "n_casos": [1],
            "cod_setor": ["001"],
        }
    )
    cnefe_cache(cnefe)

    addresses = pa.table(
        {
            "uf": ["RJ"],
            "cidade": ["Angra dos Reis"],
            "rua": ["Rua Dona Judite"],
            "num": ["0"],
            "cep_in": ["23915-700"],
            "bairro": ["Caputera II"],
        }
    )
    fields = definir_campos(
        estado="uf",
        municipio="cidade",
        logradouro="rua",
        numero="num",
        cep="cep_in",
        localidade="bairro",
    )

    out = geocode(addresses, fields, resultado_completo=True, verboso=False)

    assert out.column("tipo_resultado").to_pylist() == ["dl01"]
    assert out.column("precisao").to_pylist() == ["logradouro"]


def test_geocode_probabilistic_similarity_below_one(cnefe_cache):
    # Regressao do report de paridade 2026-09-21, §3.3: a coluna de trabalho
    # `similaridade_logradouro` era criada como Null (polars) -> INTEGER no
    # DuckDB, e todo Jaro aceito (0,85-0,99) era truncado para 1. A coluna
    # precisa ser float, casar por Jaro e ficar estritamente abaixo de 1.
    # Jaro('RUA CARLO', 'RUA MARCO') = 0,884.
    cnefe = pa.table(
        {
            "estado": ["DF"],
            "municipio": ["BRASILIA"],
            "logradouro": ["RUA MARCO"],
            "numero": [100],
            "cep": ["70000-000"],
            "localidade": ["CENTRO"],
            "lon": [-47.9],
            "lat": [-15.8],
            "endereco_completo": ["RUA MARCO, 100 - CENTRO, BRASILIA - DF"],
            "desvio_metros": [10],
            "n_casos": [1],
            "cod_setor": ["001"],
        }
    )
    cnefe_cache(cnefe)

    addresses = pa.table(
        {
            "uf": ["Distrito Federal"],
            "cidade": ["Brasilia"],
            "rua": ["Rua Carlo"],
            "num": ["100"],
            "cep_in": ["70000-000"],
            "bairro": ["Centro"],
        }
    )
    fields = definir_campos(
        estado="uf",
        municipio="cidade",
        logradouro="rua",
        numero="num",
        cep="cep_in",
        localidade="bairro",
    )

    out = geocode(addresses, fields, resultado_completo=True, verboso=False)

    assert out.column("tipo_resultado").to_pylist() == ["pn01"]
    similaridade = out.column("similaridade_logradouro").to_pylist()[0]
    assert similaridade == pytest.approx(0.884, abs=1e-3)
    assert similaridade < 1


def test_geocode_rejects_invalid_n_cores():
    with pytest.raises(ValueError, match="n_cores"):
        geocode(pa.table({"a": [1]}), n_cores=0)


def test_geocode_rejects_unstandardized_input(cnefe_cache):
    cnefe = pa.table({"estado": ["DF"], "municipio": ["BRASILIA"]})
    cnefe_cache(cnefe)

    addresses = pa.table({"estado": ["DF"], "municipio": ["BRASILIA"]})

    with pytest.raises(InputNaoPadronizadoError):
        geocode(addresses, padronizar_enderecos=False, verboso=False)


def test_materialize_input_accepts_multiple_formats(tmp_path):
    df_pl = pl.DataFrame({"a": [1]})
    pa_table = pa.table({"a": [1]})
    df_pd = pd.DataFrame({"a": [1]})

    parquet = tmp_path / "input.parquet"
    pq.write_table(pa_table, parquet)
    csv = tmp_path / "input.csv"
    df_pd.to_csv(csv, index=False)

    assert _materialize_input(df_pl).equals(df_pl)
    assert _materialize_input(pa_table).equals(df_pl)
    assert _materialize_input(df_pd).equals(df_pl)
    assert _materialize_input(str(parquet)).equals(df_pl)
    assert _materialize_input(str(csv)).equals(df_pl)


def test_materialize_input_rejects_invalid_inputs(tmp_path):
    with pytest.raises(FileNotFoundError):
        _materialize_input(str(tmp_path / "inexistente.parquet"))

    bad = tmp_path / "input.xlsx"
    bad.write_text("")
    with pytest.raises(ValueError, match="suportados"):
        _materialize_input(str(bad))

    with pytest.raises(TypeError):
        _materialize_input(123)
