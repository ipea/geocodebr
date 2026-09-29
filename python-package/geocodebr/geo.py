"""Conversão do resultado final para formatos geoespaciais.

Equivalente Python de ``sfheaders::sf_point(..., keep = TRUE)`` +
``sf::st_crs(...) <- 4674`` usados no pacote R: as colunas ``lon``/``lat``
viram uma coluna de geometria de pontos (e são consumidas por ela, como no
R, onde ``keep`` controla a manutenção das linhas com coordenada ``NA``),
e o CRS é fixado em SIRGAS 2000 (EPSG 4674).
"""

from __future__ import annotations

from typing import TYPE_CHECKING

import pyarrow as pa

if TYPE_CHECKING:
    import geopandas as gpd

CRS_SIRGAS_2000 = "EPSG:4674"


def arrow_to_geodataframe(table: pa.Table) -> gpd.GeoDataFrame:
    """Converte a tabela de resultado em um GeoDataFrame de pontos.

    Levanta ``ImportError`` com instrução de instalação caso o extra ``geo``
    (geopandas) não esteja instalado.
    """
    gpd = _import_geopandas("resultado_gpd=True")
    return _points_geodataframe(gpd, table.to_pandas(), "lon", "lat")


def table_coords_to_geodataframe(
    table: pa.Table, lon_col: str, lat_col: str
) -> gpd.GeoDataFrame:
    """Converte tabela + colunas de coordenadas em GeoDataFrame de pontos.

    Usada pelo ``geocode_reverso()``, cuja geometria do output é o próprio
    ponto de input. Levanta ``ImportError`` com instrução de instalação caso
    o extra ``geo`` (geopandas) não esteja instalado.
    """
    gpd = _import_geopandas("geocode_reverso")
    return _points_geodataframe(gpd, table.to_pandas(), lon_col, lat_col)


def _import_geopandas(contexto: str):
    try:
        import geopandas as gpd
    except ImportError as exc:
        raise ImportError(
            f"{contexto} requer geopandas. Instale o extra 'geo': "
            "python -m pip install geocodebr[geo]"
        ) from exc
    return gpd


def _points_geodataframe(gpd, df, lon_col: str, lat_col: str) -> gpd.GeoDataFrame:
    geometry = gpd.points_from_xy(df[lon_col], df[lat_col])
    # paridade com sfheaders::sf_point(keep = TRUE): lon/lat são consumidas
    # pela geometria, igual ao sf do R
    df = df.drop(columns=[lon_col, lat_col])
    return gpd.GeoDataFrame(df, geometry=geometry, crs=CRS_SIRGAS_2000)
