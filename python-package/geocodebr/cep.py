from __future__ import annotations

import enderecobr

from typing import TYPE_CHECKING

import duckdb
import pyarrow as pa

from .cache import caminho_parquet
from .db import close_geocodebr_db, create_geocodebr_db
from .download_cnefe import download_cnefe
from .geo import arrow_to_geodataframe
from .matching import add_h3_columns
from .utils import (
    normalize_h3_res,
    sql_string
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
    """Busca endereços e coordenadas a partir de CEPs.

    Recebe um CEP (ou uma lista de CEPs) e retorna os endereços associados a
    cada CEP presentes no CNEFE, com suas coordenadas geográficas. As
    coordenadas de output utilizam o sistema de referência SIRGAS 2000,
    EPSG 4674.

    Parameters
    ----------
    cep : int, str ou list[int | str]
        Um CEP ou uma lista de CEPs. CEPs duplicados são eliminados antes da
        consulta, e o output não guarda relação de 1 para 1 com o input.
    h3_res : int, list[int] ou None, opcional
        Número que indica a resolução espacial das células hexagonais H3 da
        localização dos pontos retornados. Também aceita uma lista de
        números, e.g. `[8, 10]`. Por padrão, é `None`. Detalhes sobre as
        resoluções disponíveis em https://h3geo.org/docs/core-library/restable/
    resultado_gpd : bool, opcional
        Indica se o retorno deve ser um `geopandas.GeoDataFrame` de pontos no
        CRS SIRGAS 2000 (EPSG 4674), equivalente ao `sf` do R. Por padrão, é
        `False`, e o retorno é um `pyarrow.Table`. Requer o extra `geo`
        (`pip install geocodebr[geo]`).
    verboso : bool, opcional
        Indica se barras de progresso e mensagens devem ser exibidas durante
        o download dos dados do CNEFE. O padrão é `True`.
    cache : bool, opcional
        Indica se os dados do CNEFE devem ser salvos ou lidos do cache,
        reduzindo o tempo de processamento em chamadas futuras. O padrão é
        `True`. Quando `False`, os dados do CNEFE são baixados para um
        diretório temporário.

    Returns
    -------
    pyarrow.Table or geopandas.GeoDataFrame
        Os endereços presentes nos CEPs informados, com as colunas `cep`,
        `estado`, `municipio`, `logradouro`, `localidade`, `lon` e `lat`. Um
        mesmo CEP pode cobrir vários logradouros/localidades, de modo que o
        output pode ter mais linhas que o número de CEPs informados. CEPs sem
        correspondência retornam como linhas com apenas a coluna `cep`
        preenchida. Se nenhum CEP for encontrado, a função interrompe com
        erro.
    """
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
        close_geocodebr_db(con)


def _normalize_ceps(cep: int | str | list[str|int]) -> list[str]:
    values = cep if isinstance(cep, list) else [cep]
    out = [enderecobr.padronizar_cep_numerico(c) if isinstance(c, int) else enderecobr.padronizar_cep(str(c)) for c in values]

    return sorted(set(out))