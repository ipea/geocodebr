from __future__ import annotations

from pathlib import Path
from typing import Any

import duckdb
import pyarrow as pa

from .cache import listar_pasta_cache
from .constants import DATA_RELEASE
from .db import create_geocodebr_db
from .download_cnefe import download_cnefe
from .utils import check_clean_colnames, quote_ident, db_table_columns

def geocode_reverso(
    pontos: Any,
    dist_max: int = 1000,
    verboso: bool = True,
    cache: bool = True,
    n_cores: int | None = None,
) -> pa.Table:
    if not isinstance(dist_max, (int, float)) or dist_max < 500 or dist_max > 100000:
        raise ValueError("dist_max deve estar entre 500 e 100000 metros.")
    if not isinstance(verboso, bool) or not isinstance(cache, bool):
        raise TypeError("verboso e cache devem ser True ou False.")

    download_cnefe(
        "municipio_logradouro_cep_localidade",
        verboso=verboso,
        cache=cache,
    )

    con = create_geocodebr_db(n_cores=n_cores, load_spatial=True)
    try:
        _register_points_input(con, pontos)
        input_columns = db_table_columns(con, "pontos_input")
        check_clean_colnames(input_columns)
        lon_col, lat_col = _detect_coordinate_columns(input_columns)

        con.execute(
            f"""
            CREATE OR REPLACE TEMP TABLE pontos_db AS
            SELECT *,
              ROW_NUMBER() OVER ()::INTEGER AS tempidgeocodebr,
              CAST({quote_ident(lon_col)} AS DOUBLE) AS _geocodebr_lon,
              CAST({quote_ident(lat_col)} AS DOUBLE) AS _geocodebr_lat
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

        path_to_parquet = (
            Path(listar_pasta_cache())
            / f"geocodebr_data_release_{DATA_RELEASE}"
            / "municipio_logradouro_cep_localidade.parquet"
        ).as_posix()

        con.execute(
            f"""
            CREATE OR REPLACE TEMP TABLE cnefe_tb AS
            SELECT
              estado, municipio, logradouro, cep, localidade,
              lon AS cnefe_lon,
              lat AS cnefe_lat,
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
                c.cnefe_lon AS lon_encontrado,
                c.cnefe_lat AS lat_encontrado,
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
        return con.execute("SELECT * FROM geocodebr_reverse_result").to_arrow_table()
    finally:
        con.close()


def _register_input(con: duckdb.DuckDBPyConnection, enderecos: Any) -> None:
    if isinstance(enderecos, (str, Path)):
        path = Path(enderecos)
        suffix = path.suffix.lower()
        path_sql = path.as_posix()
        if suffix == ".parquet":
            con.execute(f"CREATE OR REPLACE TEMP TABLE enderecos_input AS SELECT * FROM read_parquet('{path_sql}')")
        elif suffix in {".csv", ".txt"}:
            con.execute(f"CREATE OR REPLACE TEMP TABLE enderecos_input AS SELECT * FROM read_csv_auto('{path_sql}')")
        else:
            raise ValueError("Arquivos suportados: .parquet, .csv, .txt.")
        return

    con.register("enderecos_input_view", enderecos)
    con.execute("CREATE OR REPLACE TEMP TABLE enderecos_input AS SELECT * FROM enderecos_input_view")
    con.unregister("enderecos_input_view")


def _register_points_input(con: duckdb.DuckDBPyConnection, pontos: Any) -> None:
    if _looks_like_geodataframe(pontos):
        epsg = pontos.crs.to_epsg() if pontos.crs is not None else None
        if epsg != 4674:
            raise ValueError("Dados de input precisam estar em SIRGAS 2000, EPSG 4674.")
        geometry_name = pontos.geometry.name
        attrs = pontos.drop(columns=[geometry_name]).copy()
        attrs["_geocodebr_lon"] = pontos.geometry.x
        attrs["_geocodebr_lat"] = pontos.geometry.y
        con.register("pontos_input_view", attrs)
        con.execute("CREATE OR REPLACE TEMP TABLE pontos_input AS SELECT * FROM pontos_input_view")
        con.unregister("pontos_input_view")
        return

    _register_input(con, pontos)
    con.execute("CREATE OR REPLACE TEMP TABLE pontos_input AS SELECT * FROM enderecos_input")


def _looks_like_geodataframe(value: Any) -> bool:
    return hasattr(value, "geometry") and hasattr(value, "crs")


def _detect_coordinate_columns(columns: list[str]) -> tuple[str, str]:
    candidates = [
        ("lon", "lat"),
        ("longitude", "latitude"),
        ("x", "y"),
        ("_geocodebr_lon", "_geocodebr_lat"),
    ]
    column_set = set(columns)
    for lon_col, lat_col in candidates:
        if lon_col in column_set and lat_col in column_set:
            return lon_col, lat_col
    raise ValueError("pontos deve ter colunas lon/lat, longitude/latitude, x/y ou ser um GeoDataFrame.")


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
