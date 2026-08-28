import pyarrow as pa
import pyarrow.parquet as pq

from geocodebr import definir_pasta_cache, geocode_reverso
from geocodebr.constants import DATA_RELEASE


def test_geocode_reverso_with_duckdb_spatial(tmp_path):
    definir_pasta_cache(str(tmp_path), verboso=False)
    data_dir = tmp_path / f"geocodebr_data_release_{DATA_RELEASE}"
    data_dir.mkdir()
    cnefe = pa.table(
        {
            "estado": ["DF", "DF"],
            "municipio": ["BRASILIA", "BRASILIA"],
            "logradouro": ["AVENIDA PROXIMA", "AVENIDA DISTANTE"],
            "cep": ["70000000", "70000001"],
            "localidade": ["CENTRO", "CENTRO"],
            "lon": [-47.9000, -48.5000],
            "lat": [-15.8000, -16.3000],
        }
    )
    pq.write_table(cnefe, data_dir / "municipio_logradouro_cep_localidade.parquet")
    pontos = pa.table({"id": [1], "lon": [-47.9001], "lat": [-15.8001]})

    out = geocode_reverso(pontos, dist_max=1000, verboso=False)

    assert out.num_rows == 1
    assert out.column("logradouro").to_pylist() == ["AVENIDA PROXIMA"]
    assert out.column("distancia_metros").to_pylist()[0] < 100

