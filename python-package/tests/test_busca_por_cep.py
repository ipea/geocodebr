import pyarrow as pa
import pyarrow.parquet as pq

from geocodebr import busca_por_cep, definir_pasta_cache
from geocodebr.constants import DATA_RELEASE


def test_busca_por_cep_duckdb_flow(tmp_path):
    definir_pasta_cache(str(tmp_path), verboso=False)
    data_dir = tmp_path / f"geocodebr_data_release_{DATA_RELEASE}"
    data_dir.mkdir()
    table = pa.table(
        {
            "cep": ["70390025", "20071001"],
            "estado": ["DF", "RJ"],
            "municipio": ["BRASILIA", "RIO DE JANEIRO"],
            "logradouro": ["AVENIDA TESTE", "RUA TESTE"],
            "localidade": ["CENTRO", "CENTRO"],
            "lon": [-47.9, -43.2],
            "lat": [-15.8, -22.9],
        }
    )
    pq.write_table(table, data_dir / "municipio_logradouro_cep_localidade.parquet")

    out = busca_por_cep(["70390-025", "99999-999"], h3_res=3, verboso=False)

    assert out.num_rows == 2
    assert "h3_03" in out.schema.names
    assert out.column("cep").to_pylist() == ["70390-025", "99999-999"]
