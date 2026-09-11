from __future__ import annotations

import enderecobr

from typing import TYPE_CHECKING

import duckdb
import pyarrow as pa

from .cache import caminho_parquet
from .db import create_geocodebr_db
from .download_cnefe import download_cnefe
from .geo import arrow_to_geodataframe
from .utils import (
    assert_bool,
    normalize_h3_res,
    sql_string,
    add_h3_columns
)

if TYPE_CHECKING:
    import geopandas as gpd


def busca_por_cep(
    cep: int | str | list[str|int],
    h3_res: int | list[int] | tuple[int, ...] | None = None,
    resultado_gpd: bool = False,
    verboso: bool = True,
    cache: bool = True,
) -> pa.Table | gpd.GeoDataFrame:
    assert_bool(verboso, "verboso")
    assert_bool(cache, "cache")
    h3_values = normalize_h3_res(h3_res)
    ceps = _normalize_ceps(cep)
    
    cnefe_dir = download_cnefe("municipio_logradouro_cep_localidade", verboso=verboso, cache=cache)
    con = create_geocodebr_db()
    try:
        path_to_parquet = caminho_parquet(
            "municipio_logradouro_cep_localidade", cnefe_dir
        )
        unique_ceps = ", ".join(sql_string(value) for value in sorted(set(ceps)))
        con.execute(
            f"""
            CREATE OR REPLACE TEMP TABLE output_df AS
            SELECT cep, estado, municipio, logradouro, localidade, lon, lat
            FROM read_parquet('{path_to_parquet}')
            WHERE cep IN ({unique_ceps})
            """
        )
        found_ceps = {
            row[0]
            for row in con.execute("SELECT DISTINCT cep FROM output_df").fetchall()
        }
        missing = sorted(set(ceps) - found_ceps)
        if len(missing) == len(set(ceps)):
            raise ValueError("Nenhum CEP foi encontrado.")
        if missing:
            values = ", ".join(f"({sql_string(value)})" for value in missing)
            con.execute(f"INSERT INTO output_df (cep) VALUES {values}")
        add_h3_columns(con, "output_df", h3_values)
        result = con.execute("SELECT * FROM output_df").to_arrow_table()

        if resultado_gpd:
            return arrow_to_geodataframe(result)

        return result
    finally:
        con.close()


def _normalize_ceps(cep: int | str | list[str|int]) -> list[str]:
    values = cep if isinstance(cep, list) else [cep]
    out = [enderecobr.padronizar_cep_numerico(c) if isinstance(c, int) else enderecobr.padronizar_cep(str(c)) for c in values]

    return sorted(set(out))