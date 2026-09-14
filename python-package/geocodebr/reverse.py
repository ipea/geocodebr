from __future__ import annotations

from typing import TYPE_CHECKING, Any

import duckdb
import pyarrow as pa

from .cache import caminho_parquet
from .db import create_geocodebr_db
from .download_cnefe import download_cnefe
from .geo import table_coords_to_geodataframe
from .utils import check_clean_colnames, quote_ident, db_table_columns

if TYPE_CHECKING:
    import geopandas as gpd

def geocode_reverso(
    pontos: Any,
    dist_max: int = 1000,
    verboso: bool = True,
    cache: bool = True,
    n_cores: int | None = None,
) -> gpd.GeoDataFrame:
    """Geocode reverso de coordenadas geograficas para enderecos.

    Recebe um `GeoDataFrame` com geometria do tipo POINT no CRS SIRGAS 2000
    (EPSG 4674) e retorna o endereco mais proximo dentro de `dist_max`
    (em metros). O output e o proprio `GeoDataFrame` de input acrescido das
    colunas do endereco encontrado e de `distancia_metros`; a geometria e o
    proprio ponto de input, como no sf do R. Requer o extra `geo`.
    """
    _validate_pontos(pontos)
    if not isinstance(dist_max, (int, float)) or dist_max < 500 or dist_max > 100000:
        raise ValueError("dist_max deve estar entre 500 e 100000 metros.")
    if not isinstance(verboso, bool) or not isinstance(cache, bool):
        raise TypeError("verboso e cache devem ser True ou False.")

    cnefe_dir = download_cnefe(
        "municipio_logradouro_cep_localidade",
        verboso=verboso,
        cache=cache,
    )

    con = create_geocodebr_db(n_cores=n_cores, load_spatial=True)
    try:
        _register_points_input(con, pontos)
        input_columns = db_table_columns(con, "pontos_input")
        check_clean_colnames(input_columns)

        attrs_columns = [
            col for col in input_columns if col not in {"_geocodebr_lon", "_geocodebr_lat"}
        ]
        point_select = ", ".join(
            [
                *(quote_ident(col) for col in attrs_columns),
                "CAST(_geocodebr_lon AS DOUBLE) AS _geocodebr_lon",
                "CAST(_geocodebr_lat AS DOUBLE) AS _geocodebr_lat",
            ]
        )

        con.execute(
            f"""
            CREATE OR REPLACE TEMP TABLE pontos_db AS
            SELECT
              {point_select},
              ROW_NUMBER() OVER ()::INTEGER AS tempidgeocodebr
            FROM pontos_input
            """
        )

        bbox = _validate_points_bbox(con)

        margin = float(dist_max) / 111_320 + 0.05
        xmin, ymin, xmax, ymax = (
            bbox[0] - margin,
            bbox[1] - margin,
            bbox[2] + margin,
            bbox[3] + margin,
        )

        path_to_parquet = caminho_parquet(
            "municipio_logradouro_cep_localidade", cnefe_dir
        )

        con.execute(
            f"""
            CREATE OR REPLACE TEMP TABLE cnefe_tb AS
            SELECT
              estado, municipio, logradouro, cep, localidade,
              ST_Transform(
                ST_Point(CAST(lon AS DOUBLE), CAST(lat AS DOUBLE)),
                'EPSG:4674',
                'EPSG:31983',
                always_xy := true
              ) AS cnefe_geom_utm
            FROM read_parquet('{path_to_parquet}')
            WHERE lon BETWEEN {xmin} AND {xmax}
              AND lat BETWEEN {ymin} AND {ymax}
            """
        )
        con.execute(
            """
            CREATE OR REPLACE TEMP TABLE pontos_utm AS
            SELECT *,
              ST_Transform(
                ST_Point(_geocodebr_lon, _geocodebr_lat),
                'EPSG:4674',
                'EPSG:31983',
                always_xy := true
              ) AS ponto_geom_utm
            FROM pontos_db
            """
        )

        original_columns = [
            col
            for col in input_columns
            if col not in {"_geocodebr_lon", "_geocodebr_lat", "tempidgeocodebr"}
        ]
        select_original = ", ".join(f"p.{quote_ident(col)}" for col in original_columns)
        address_select = _address_select_clause(set(original_columns))
        leading_comma = ", " if select_original else ""

        con.execute(
            f"""
            CREATE OR REPLACE TEMP TABLE geocodebr_reverse_result AS
            WITH ranked AS (
              SELECT
                {select_original}{leading_comma}
                {address_select},
                p._geocodebr_lon,
                p._geocodebr_lat,
                ST_Distance(p.ponto_geom_utm, c.cnefe_geom_utm) AS distancia_metros,
                ROW_NUMBER() OVER (
                  PARTITION BY p.tempidgeocodebr
                  ORDER BY distancia_metros
                ) AS rn,
                p.tempidgeocodebr
              FROM pontos_utm p
              JOIN cnefe_tb c
                ON ST_DWithin(p.ponto_geom_utm, c.cnefe_geom_utm, {float(dist_max)})
            )
            SELECT * EXCLUDE (rn, tempidgeocodebr)
            FROM ranked
            WHERE rn = 1
            ORDER BY tempidgeocodebr
            """
        )
        n_rows = con.execute("SELECT COUNT(*) FROM geocodebr_reverse_result").fetchone()[0]
        if n_rows == 0:
            raise ValueError("Nenhum endereco proximo foi encontrado.")
        table = con.execute("SELECT * FROM geocodebr_reverse_result").to_arrow_table()
        return table_coords_to_geodataframe(table, "_geocodebr_lon", "_geocodebr_lat")
    finally:
        con.close()


def _validate_pontos(pontos: Any) -> None:
    if not _looks_like_geodataframe(pontos):
        raise ValueError(
            "pontos deve ser um GeoDataFrame com geometria do tipo POINT."
        )
    if any(gt != "Point" for gt in pontos.geom_type):
        raise ValueError(
            "pontos deve ser um GeoDataFrame com geometria do tipo POINT."
        )
    epsg = pontos.crs.to_epsg() if pontos.crs is not None else None
    if epsg != 4674:
        raise ValueError(
            "Dados de input precisam estar com sistema de coordenadas "
            "geograficas SIRGAS 2000, EPSG 4674."
        )


def _register_points_input(con: duckdb.DuckDBPyConnection, pontos: Any) -> None:
    geometry_name = pontos.geometry.name
    attrs = pontos.drop(columns=[geometry_name]).copy()
    attrs["_geocodebr_lon"] = pontos.geometry.x
    attrs["_geocodebr_lat"] = pontos.geometry.y
    con.register("pontos_input_view", attrs)
    con.execute("CREATE OR REPLACE TEMP TABLE pontos_input AS SELECT * FROM pontos_input_view")
    con.unregister("pontos_input_view")


def _looks_like_geodataframe(value: Any) -> bool:
    return hasattr(value, "geometry") and hasattr(value, "crs")


def _validate_points_bbox(con: duckdb.DuckDBPyConnection) -> None:
    xmin, ymin, xmax, ymax = con.execute(
        """
        SELECT
          MIN(_geocodebr_lon), MIN(_geocodebr_lat),
          MAX(_geocodebr_lon), MAX(_geocodebr_lat)
        FROM pontos_db
        """
    ).fetchone()
    bbox_brazil = {
        "xmin": -73.99044997,
        "ymin": -33.75208127,
        "xmax": -28.83594354,
        "ymax": 5.27184108,
    }
    if (
        xmin < bbox_brazil["xmin"]
        or xmax > bbox_brazil["xmax"]
        or ymin < bbox_brazil["ymin"]
        or ymax > bbox_brazil["ymax"]
    ):
        raise ValueError("Coordenadas de input localizadas fora do bounding box do Brasil.")
    
    return xmin, ymin, xmax, ymax


def _address_select_clause(original_columns: set[str]) -> str:
    parts = []
    for col in ["estado", "municipio", "logradouro", "cep", "localidade"]:
        out_col = col if col not in original_columns else f"{col}_encontrado"
        parts.append(f"c.{col} AS {out_col}")
    return ", ".join(parts)
