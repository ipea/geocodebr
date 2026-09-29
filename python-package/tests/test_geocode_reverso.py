import pytest
import pyarrow as pa
from shapely import LineString

gpd = pytest.importorskip("geopandas")

from geocodebr import geocode_reverso
from geocodebr.errors import SemCorrespondenciaError


def test_geocode_reverso_with_duckdb_spatial(cnefe_cache):
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
    cnefe_cache(cnefe, "municipio_logradouro_cep_localidade")
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


def test_geocode_reverso_requires_geodataframe():
    with pytest.raises(ValueError, match="GeoDataFrame"):
        geocode_reverso(
            pa.table({"id": [1], "lon": [-47.9], "lat": [-15.8]}),
            verboso=False,
        )


def test_geocode_reverso_requires_point_geometry():
    pontos = gpd.GeoDataFrame(
        {"id": [1]},
        geometry=[LineString([(-47.9, -15.8), (-47.8, -15.9)])],
        crs="EPSG:4674",
    )
    with pytest.raises(ValueError, match="POINT"):
        geocode_reverso(pontos, verboso=False)


def test_geocode_reverso_requires_epsg_4674():
    pontos = gpd.GeoDataFrame(
        {"id": [1]},
        geometry=gpd.points_from_xy([-47.9], [-15.8]),
        crs="EPSG:4326",
    )
    with pytest.raises(ValueError, match="EPSG 4674"):
        geocode_reverso(pontos, verboso=False)


def test_geocode_reverso_rejects_dist_max_out_of_range():
    pontos = gpd.GeoDataFrame(
        {"id": [1]},
        geometry=gpd.points_from_xy([-47.9], [-15.8]),
        crs="EPSG:4674",
    )
    with pytest.raises(ValueError, match="dist_max"):
        geocode_reverso(pontos, dist_max=100, verboso=False)
    with pytest.raises(ValueError, match="dist_max"):
        geocode_reverso(pontos, dist_max=200000, verboso=False)


def test_geocode_reverso_rejects_invalid_n_cores():
    pontos = gpd.GeoDataFrame(
        {"id": [1]},
        geometry=gpd.points_from_xy([-47.9], [-15.8]),
        crs="EPSG:4674",
    )
    with pytest.raises(ValueError, match="n_cores"):
        geocode_reverso(pontos, n_cores=0, verboso=False)


def test_geocode_reverso_no_address_within_radius(cnefe_cache):
    cnefe = pa.table(
        {
            "estado": ["DF"],
            "municipio": ["BRASILIA"],
            "logradouro": ["AVENIDA DISTANTE"],
            "cep": ["70000001"],
            "localidade": ["CENTRO"],
            "lon": [-48.5000],
            "lat": [-16.3000],
        }
    )
    cnefe_cache(cnefe, "municipio_logradouro_cep_localidade")
    pontos = gpd.GeoDataFrame(
        {"id": [1]},
        geometry=gpd.points_from_xy([-47.9001], [-15.8001]),
        crs="EPSG:4674",
    )

    with pytest.raises(SemCorrespondenciaError, match="Nenhum endereco proximo"):
        geocode_reverso(pontos, dist_max=500, verboso=False)


def test_validate_points_bbox_rejects_point_outside_brazil():
    import duckdb

    from geocodebr.reverse import _validate_points_bbox

    con = duckdb.connect(":memory:")
    try:
        con.execute(
            "CREATE TABLE pontos_db (_geocodebr_lon DOUBLE, _geocodebr_lat DOUBLE)"
        )
        con.execute("INSERT INTO pontos_db VALUES (-120.0, -15.8)")
        with pytest.raises(ValueError, match="bounding box"):
            _validate_points_bbox(con)
    finally:
        con.close()


def test_geocode_reverso_mixed_input_drops_unmatched_points(cnefe_cache):
    # caso misto: o ponto com endereco no raio volta, o ponto sem endereco a
    # dist_max e descartado silenciosamente (join interno) — output < input
    cnefe_cache(
        pa.table(
            {
                "estado": ["DF"],
                "municipio": ["BRASILIA"],
                "logradouro": ["AVENIDA PROXIMA"],
                "cep": ["70000000"],
                "localidade": ["CENTRO"],
                "lon": [-47.9000],
                "lat": [-15.8000],
            }
        ),
        "municipio_logradouro_cep_localidade",
    )
    pontos = gpd.GeoDataFrame(
        {"id": [1, 2]},
        geometry=gpd.points_from_xy([-47.9001, -48.0], [-15.8001, -16.0]),
        crs="EPSG:4674",
    )

    out = geocode_reverso(pontos, dist_max=1000, verboso=False)

    assert len(out) == 1
    assert out["id"].tolist() == [1]
    assert out["logradouro"].tolist() == ["AVENIDA PROXIMA"]
