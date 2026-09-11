import pandas as pd
import pyarrow as pa
import pyarrow.parquet as pq
import pytest

from geocodebr import busca_por_cep, definir_campos, definir_pasta_cache, geocode
from geocodebr.constants import ALL_CNEFE_FILES, DATA_RELEASE
from geocodebr.geo import arrow_to_geodataframe

gpd = pytest.importorskip("geopandas")


def test_arrow_to_geodataframe_drops_lat_lon_and_sets_crs():
    table = pa.table(
        {
            "id": [1, 2],
            "lon": [-47.9, None],
            "lat": [-15.8, None],
        }
    )

    gdf = arrow_to_geodataframe(table)

    assert isinstance(gdf, gpd.GeoDataFrame)
    assert gdf.crs.to_epsg() == 4674
    # paridade com o R: lon/lat sao consumidas pela geometria
    assert "lat" not in gdf.columns and "lon" not in gdf.columns
    assert gdf.geometry.iloc[0].x == pytest.approx(-47.9)
    assert gdf.geometry.iloc[0].y == pytest.approx(-15.8)
    # coordenada ausente vira ponto nulo (NaN), assim como POINT(NA NA) no R
    assert gdf.geometry.iloc[1].is_empty is False
    assert gdf.geometry.isna().sum() == 0
    assert bool(pd.isna(gdf.geometry.iloc[1].x))


def test_geocode_resultado_gpd(tmp_path):
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

    out = geocode(
        enderecos,
        campos,
        resultado_completo=True,
        resultado_gpd=True,
        verboso=False,
    )

    assert isinstance(out, gpd.GeoDataFrame)
    assert out.crs.to_epsg() == 4674
    assert len(out) == 1
    assert out.geometry.iloc[0].x == pytest.approx(-47.9)
    assert out.geometry.iloc[0].y == pytest.approx(-15.8)
    assert out["tipo_resultado"].tolist() == ["dn01"]
    assert "lat" not in out.columns and "lon" not in out.columns


def test_busca_por_cep_resultado_gpd(tmp_path):
    definir_pasta_cache(str(tmp_path), verboso=False)
    data_dir = tmp_path / f"geocodebr_data_release_{DATA_RELEASE}"
    data_dir.mkdir()
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
    pq.write_table(table, data_dir / "municipio_logradouro_cep_localidade.parquet")

    out = busca_por_cep(
        ["70390-025", "99999-999"],
        resultado_gpd=True,
        verboso=False,
    )

    assert isinstance(out, gpd.GeoDataFrame)
    assert out.crs.to_epsg() == 4674
    assert len(out) == 2
    assert out.geometry.iloc[0].x == pytest.approx(-47.9)
    assert out.geometry.iloc[0].y == pytest.approx(-15.8)
    # cep nao encontrado mantem a linha com geometria nula (NaN)
    assert out.geometry.iloc[1].is_empty is False
    assert bool(pd.isna(out.geometry.iloc[1].x))
