"""Conversão do resultado final para formatos geoespaciais.

Equivalente Python de ``sfheaders::sf_point(..., keep = TRUE)`` +
``sf::st_crs(...) <- 4674`` usados no pacote R: as colunas ``lon``/``lat``
viram uma coluna de geometria de pontos (e sao consumidas por ela, como no
R, onde ``keep`` controla a manutencao das linhas com coordenada ``NA``),
e o CRS e fixado em SIRGAS 2000 (EPSG 4674).
"""

from __future__ import annotations

from typing import TYPE_CHECKING

import pyarrow as pa

if TYPE_CHECKING:
    import geopandas as gpd

CRS_SIRGAS_2000 = "EPSG:4674"


def arrow_to_geodataframe(table: pa.Table) -> gpd.GeoDataFrame:
    """Converte a tabela de resultado em um GeoDataFrame de pontos.

    Levanta ``ImportError`` com instrucao de instalacao caso o extra ``geo``
    (geopandas) nao esteja instalado.
    """
    try:
        import geopandas as gpd
    except ImportError as exc:
        raise ImportError(
            "resultado_gpd=True requer geopandas. Instale o extra 'geo': "
            "python -m pip install geocodebr[geo]"
        ) from exc

    df = table.to_pandas()
    geometry = gpd.points_from_xy(df["lon"], df["lat"])
    # paridade com sfheaders::sf_point(keep = TRUE): lon/lat sao consumidas
    # pela geometria, igual ao sf do R
    df = df.drop(columns=["lon", "lat"])
    return gpd.GeoDataFrame(df, geometry=geometry, crs=CRS_SIRGAS_2000)
