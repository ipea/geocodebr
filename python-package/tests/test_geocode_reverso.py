import pytest
import pyarrow as pa
import pyarrow.parquet as pq
from shapely import LineString

gpd = pytest.importorskip("geopandas")

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
    pontos = gpd.GeoDataFrame(
        {"id": [1]},
        geometry=gpd.points_from_xy([-47.9001], [-15.8001]),
        crs="EPSG:4674",
    )

    out = geocode_reverso(pontos, dist_max=1000, verboso=False)

    assert isinstance(out, gpd.GeoDataFrame)
    assert out.crs.to_epsg() == 4674
    assert len(out) == 1
    assert out["logradouro"].tolist() == ["AVENIDA PROXIMA"]
    assert out["distancia_metros"].iloc[0] < 100
    # a geometria do output e o proprio ponto de input, como no sf do R
    assert out.geometry.iloc[0].x == pytest.approx(-47.9001)
    assert out.geometry.iloc[0].y == pytest.approx(-15.8001)


def test_geocode_reverso_exige_geodataframe():
    with pytest.raises(ValueError, match="GeoDataFrame"):
        geocode_reverso(
            pa.table({"id": [1], "lon": [-47.9], "lat": [-15.8]}),
            verboso=False,
        )


def test_geocode_reverso_exige_geometria_point():
    pontos = gpd.GeoDataFrame(
        {"id": [1]},
        geometry=[LineString([(-47.9, -15.8), (-47.8, -15.9)])],
        crs="EPSG:4674",
    )
    with pytest.raises(ValueError, match="POINT"):
        geocode_reverso(pontos, verboso=False)


def test_geocode_reverso_exige_epsg_4674():
    pontos = gpd.GeoDataFrame(
        {"id": [1]},
        geometry=gpd.points_from_xy([-47.9], [-15.8]),
        crs="EPSG:4326",
    )
    with pytest.raises(ValueError, match="EPSG 4674"):
        geocode_reverso(pontos, verboso=False)
