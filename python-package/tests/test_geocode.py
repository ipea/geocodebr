import pyarrow as pa
import pyarrow.parquet as pq

from geocodebr import definir_campos, definir_pasta_cache, geocode
from geocodebr.constants import ALL_CNEFE_FILES, DATA_RELEASE


def test_geocode_exact_number_match_with_duckdb(tmp_path):
    definir_pasta_cache(str(tmp_path), verboso=False)
    data_dir = tmp_path / f"geocodebr_data_release_{DATA_RELEASE}"
    data_dir.mkdir()
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
    for file in ALL_CNEFE_FILES:
        pq.write_table(cnefe, data_dir / file)

    enderecos = pa.table(
        {
            "uf": ["Distrito Federal"],
            "cidade": ["Brasilia"],
            "rua": ["Avenida Teste"],
            "num": ["100"],
            "cep_in": ["70000-000"],
            "bairro": ["Centro"],
        }
    )
    campos = definir_campos(
        estado="uf",
        municipio="cidade",
        logradouro="rua",
        numero="num",
        cep="cep_in",
        localidade="bairro",
    )

    out = geocode(enderecos, campos, resultado_completo=True, h3_res=3, verboso=False)

    assert out.num_rows == 1
    assert out.column("tipo_resultado").to_pylist() == ["dn01"]
    assert out.column("precisao").to_pylist() == ["numero"]
    assert "h3_03" in out.schema.names


def test_geocode_treats_zero_number_as_missing(tmp_path):
    definir_pasta_cache(str(tmp_path), verboso=False)
    data_dir = tmp_path / f"geocodebr_data_release_{DATA_RELEASE}"
    data_dir.mkdir()
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
    for file in ALL_CNEFE_FILES:
        pq.write_table(cnefe, data_dir / file)

    enderecos = pa.table(
        {
            "uf": ["RJ"],
            "cidade": ["Angra dos Reis"],
            "rua": ["Rua Dona Judite"],
            "num": ["0"],
            "cep_in": ["23915-700"],
            "bairro": ["Caputera II"],
        }
    )
    campos = definir_campos(
        estado="uf",
        municipio="cidade",
        logradouro="rua",
        numero="num",
        cep="cep_in",
        localidade="bairro",
    )

    out = geocode(enderecos, campos, resultado_completo=True, verboso=False)

    assert out.column("tipo_resultado").to_pylist() == ["dl01"]
    assert out.column("precisao").to_pylist() == ["logradouro"]
