import enderecobr

from pathlib import Path
import duckdb
import pyarrow as pa

from .constants import DATA_RELEASE
from .cache import listar_pasta_cache
from .db import create_geocodebr_db
from .download_cnefe import download_cnefe
from .utils import (
    assert_bool,
    normalize_h3_res,
    sql_string,
    add_h3_columns
)


def busca_por_cep(
    cep: int | str | list[str|int],
    h3_res: int | list[int] | tuple[int, ...] | None = None,
    resultado_sf: bool = False,
    verboso: bool = True,
    cache: bool = True,
) -> pa.Table:
    if resultado_sf:
        raise NotImplementedError("resultado_sf=True sera implementado com geopandas na proxima etapa.")
    assert_bool(verboso, "verboso")
    assert_bool(cache, "cache")
    h3_values = normalize_h3_res(h3_res)
    ceps = _normalize_ceps(cep)
    
    download_cnefe("municipio_logradouro_cep_localidade", verboso=verboso, cache=cache)
    con = create_geocodebr_db()
    try:
        path_to_parquet = (
            Path(listar_pasta_cache())
            / f"geocodebr_data_release_{DATA_RELEASE}"
            / "municipio_logradouro_cep_localidade.parquet"
        ).as_posix()
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
        return con.execute("SELECT * FROM output_df").to_arrow_table()
    finally:
        con.close()


def _normalize_ceps(cep: int | str | list[str|int]) -> list[str]:
    values = cep if isinstance(cep, list) else [cep]
    out = [enderecobr.padronizar_cep_numerico(c) if isinstance(c, int) else enderecobr.padronizar_cep(str(c)) for c in values]

    return sorted(set(out))