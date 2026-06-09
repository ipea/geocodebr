from __future__ import annotations

import duckdb

from .constants import (
    EXACT_TYPES_NO_NUMBER,
    NUMBER_EXACT_TYPES,
    NUMBER_INTERPOLATION_TYPES,
    PROBABILISTIC_EXACT_TYPES,
    PROBABILISTIC_INTERPOLATION_TYPES,
    PROBABILISTIC_TYPES_NO_NUMBER,
)
from .string_dist import calculate_string_dist
from .tables import register_cnefe_table, register_unique_logradouros_table
from .utils import get_key_cols, get_reference_table, quote_ident, update_input_db


def create_output_db(con: duckdb.DuckDBPyConnection, resultado_completo: bool) -> None:
    columns = [
        "tempidgeocodebr INTEGER",
        "lat DOUBLE",
        "lon DOUBLE",
        "endereco_encontrado TEXT",
        "logradouro_encontrado TEXT",
        "tipo_resultado TEXT",
        "contagem_cnefe INTEGER",
        "desvio_metros INTEGER",
        "log_causa_confusao BOOLEAN",
        "similaridade_logradouro DOUBLE",
    ]
    if resultado_completo:
        columns.extend(
            [
                "numero_encontrado INTEGER",
                "localidade_encontrada TEXT",
                "cep_encontrado TEXT",
                "municipio_encontrado TEXT",
                "estado_encontrado TEXT",
                "empate BOOLEAN",
                "cod_setor TEXT",
            ]
        )
    con.execute(f"CREATE OR REPLACE TEMP TABLE output_db ({', '.join(columns)})")


def match_cases(
    con: duckdb.DuckDBPyConnection,
    x: str = "input_padrao_db",
    output_tb: str = "output_db",
    key_cols: list[str] | None = None,
    match_type: str = "",
    resultado_completo: bool = False,
) -> int:
    y = get_reference_table(match_type)
    key_cols = get_key_cols(match_type)
    register_cnefe_table(con, match_type)

    join_condition = " AND ".join(f"{y}.{col} = {x}.{col}" for col in key_cols)
    cols_not_null = " AND ".join(f"{x}.{col} IS NOT NULL" for col in key_cols)
    colunas_encontradas, additional_cols = _complete_columns(y, key_cols, resultado_completo)

    con.execute(
        f"""
        INSERT INTO output_db (
          tempidgeocodebr, lat, lon, endereco_encontrado, tipo_resultado,
          desvio_metros, log_causa_confusao, contagem_cnefe {colunas_encontradas}
        )
        SELECT {x}.tempidgeocodebr,
          {y}.lat,
          {y}.lon,
          {y}.endereco_completo AS endereco_encontrado,
          '{match_type}' AS tipo_resultado,
          {y}.desvio_metros,
          {x}.log_causa_confusao,
          {y}.n_casos AS contagem_cnefe {additional_cols}
        FROM {x}
        INNER JOIN {y}
        ON {join_condition}
        WHERE {cols_not_null}
        """
    )
    return update_input_db(con, update_tb=x, reference_tb=output_tb)


def match_weighted_cases(
    con: duckdb.DuckDBPyConnection,
    x: str = "input_padrao_db",
    output_tb: str = "output_db",
    key_cols: list[str] | None = None,
    match_type: str = "",
    resultado_completo: bool = False,
) -> int:
    y = get_reference_table(match_type)
    original_key_cols = get_key_cols(match_type)
    register_cnefe_table(con, match_type)

    cols_not_null = " AND ".join(f"{x}.{col} IS NOT NULL" for col in original_key_cols)
    key_cols = [col for col in original_key_cols if col != "numero"]
    join_condition = " AND ".join(f"{y}.{col} = {x}.{col}" for col in key_cols)
    colunas_encontradas, additional_first, additional_second = _complete_weighted_columns(y, key_cols, resultado_completo)

    con.execute(
        f"""
        WITH temp_db AS (
          SELECT {x}.tempidgeocodebr,
                 {x}.numero,
                 {y}.numero AS numero_cnefe,
                 {y}.lat, {y}.lon,
                 REGEXP_REPLACE({y}.endereco_completo, ', \\d+ -', CONCAT(', ', {x}.numero, ' (aprox) -')) AS endereco_encontrado,
                 {y}.desvio_metros,
                 {x}.log_causa_confusao,
                 {y}.n_casos AS contagem_cnefe {additional_first}
          FROM {x}
          INNER JOIN {y}
          ON {join_condition}
          WHERE {cols_not_null}
        )
        INSERT INTO output_db (
          tempidgeocodebr, lat, lon, endereco_encontrado, tipo_resultado,
          desvio_metros, log_causa_confusao, contagem_cnefe {colunas_encontradas}
        )
        SELECT tempidgeocodebr,
          SUM((1 / ABS(numero - numero_cnefe) * lat)) / SUM(1 / ABS(numero - numero_cnefe)) AS lat,
          SUM((1 / ABS(numero - numero_cnefe) * lon)) / SUM(1 / ABS(numero - numero_cnefe)) AS lon,
          FIRST(endereco_encontrado) AS endereco_encontrado,
          '{match_type}' AS tipo_resultado,
          AVG(desvio_metros) AS desvio_metros,
          FIRST(log_causa_confusao) AS log_causa_confusao,
          FIRST(contagem_cnefe) AS contagem_cnefe {additional_second}
        FROM temp_db
        GROUP BY tempidgeocodebr, endereco_encontrado
        """
    )
    return update_input_db(con, update_tb=x, reference_tb=output_tb)


def match_cases_probabilistic(
    con: duckdb.DuckDBPyConnection,
    x: str = "input_padrao_db",
    output_tb: str = "output_db",
    key_cols: list[str] | None = None,
    match_type: str = "",
    resultado_completo: bool = False,
) -> int:
    y = get_reference_table(match_type)
    key_cols = get_key_cols(match_type)
    register_cnefe_table(con, match_type)
    unique_logradouros_tbl = register_unique_logradouros_table(con, match_type)
    calculate_string_dist(con, match_type, unique_logradouros_tbl)

    join_condition = " AND ".join(f"{y}.{col} = {x}.{col}" for col in key_cols)
    join_condition = join_condition.replace("input_padrao_db.logradouro", "input_padrao_db.temp_lograd_determ")
    cols_not_null = " AND ".join(f"{x}.{col} IS NOT NULL" for col in key_cols)
    cols_not_null = cols_not_null.replace(".logradouro", ".temp_lograd_determ")
    colunas_encontradas, additional_cols = _complete_columns(y, key_cols, resultado_completo, probabilistic=True)

    con.execute(
        f"""
        INSERT INTO output_db (
          tempidgeocodebr, lat, lon, endereco_encontrado, tipo_resultado,
          desvio_metros, log_causa_confusao, contagem_cnefe {colunas_encontradas}
        )
        SELECT {x}.tempidgeocodebr,
          {y}.lat,
          {y}.lon,
          {y}.endereco_completo AS endereco_encontrado,
          '{match_type}' AS tipo_resultado,
          {y}.desvio_metros,
          {x}.log_causa_confusao,
          {y}.n_casos AS contagem_cnefe {additional_cols}
        FROM {x}
        INNER JOIN {y}
        ON {join_condition}
        WHERE {cols_not_null}
        """
    )
    return update_input_db(con, update_tb=x, reference_tb=output_tb)


def match_weighted_cases_probabilistic(
    con: duckdb.DuckDBPyConnection,
    x: str = "input_padrao_db",
    output_tb: str = "output_db",
    key_cols: list[str] | None = None,
    match_type: str = "",
    resultado_completo: bool = False,
) -> int:
    y = get_reference_table(match_type)
    original_key_cols = get_key_cols(match_type)
    register_cnefe_table(con, match_type)
    unique_logradouros_tbl = register_unique_logradouros_table(con, match_type)
    calculate_string_dist(con, match_type, unique_logradouros_tbl)

    cols_not_null = " AND ".join(f"{x}.{col} IS NOT NULL" for col in original_key_cols)
    key_cols = [col for col in original_key_cols if col != "numero"]
    join_condition = " AND ".join(f"{y}.{col} = {x}.{col}" for col in key_cols)
    join_condition = join_condition.replace("input_padrao_db.logradouro", "input_padrao_db.temp_lograd_determ")
    cols_not_null_match = cols_not_null.replace(".logradouro", ".temp_lograd_determ")
    colunas_encontradas, additional_first, additional_second = _complete_weighted_columns(y, key_cols, resultado_completo)

    con.execute(
        f"""
        WITH temp_db AS (
          SELECT {x}.tempidgeocodebr,
                 {x}.numero,
                 {y}.numero AS numero_cnefe,
                 {y}.lat, {y}.lon,
                 REGEXP_REPLACE({y}.endereco_completo, ', \\d+ -', CONCAT(', ', {x}.numero, ' (aprox) -')) AS endereco_encontrado,
                 {x}.similaridade_logradouro,
                 {y}.desvio_metros,
                 {x}.log_causa_confusao,
                 {y}.n_casos AS contagem_cnefe {additional_first}
          FROM {x}
          INNER JOIN {y}
          ON {join_condition}
          WHERE {cols_not_null_match}
        )
        INSERT INTO output_db (
          tempidgeocodebr, lat, lon, endereco_encontrado, tipo_resultado,
          desvio_metros, log_causa_confusao, similaridade_logradouro, contagem_cnefe {colunas_encontradas}
        )
        SELECT tempidgeocodebr,
          SUM((1 / ABS(numero - numero_cnefe) * lat)) / SUM(1 / ABS(numero - numero_cnefe)) AS lat,
          SUM((1 / ABS(numero - numero_cnefe) * lon)) / SUM(1 / ABS(numero - numero_cnefe)) AS lon,
          FIRST(endereco_encontrado) AS endereco_encontrado,
          '{match_type}' AS tipo_resultado,
          AVG(desvio_metros) AS desvio_metros,
          FIRST(log_causa_confusao) AS log_causa_confusao,
          FIRST(similaridade_logradouro) AS similaridade_logradouro,
          FIRST(contagem_cnefe) AS contagem_cnefe {additional_second}
        FROM temp_db
        GROUP BY tempidgeocodebr, endereco_encontrado
        """
    )
    return update_input_db(con, update_tb=x, reference_tb=output_tb)


def select_match_function(match_type: str):
    if match_type in NUMBER_EXACT_TYPES or match_type in EXACT_TYPES_NO_NUMBER:
        return match_cases
    if match_type in NUMBER_INTERPOLATION_TYPES:
        return match_weighted_cases
    if match_type in PROBABILISTIC_EXACT_TYPES or match_type in PROBABILISTIC_TYPES_NO_NUMBER:
        return match_cases_probabilistic
    if match_type in PROBABILISTIC_INTERPOLATION_TYPES:
        return match_weighted_cases_probabilistic
    raise ValueError(f"match_type sem funcao: {match_type}")


def trata_empates_geocode_duckdb(
    con: duckdb.DuckDBPyConnection,
    resultado_completo: bool,
    resolver_empates: bool,
    verboso: bool,
) -> int:
    n_casos_empate = con.execute(
        """
        SELECT COUNT(*) AS n_casos_empate
        FROM (
          SELECT tempidgeocodebr
          FROM output_db
          GROUP BY tempidgeocodebr
          HAVING COUNT(*) > 1
        ) AS repeated
        """
    ).fetchone()[0]

    if n_casos_empate == 0:
        return 0

    if not resolver_empates:
        con.execute(
            """
            CREATE OR REPLACE TEMP TABLE output_db2 AS
            SELECT *,
              (COUNT(*) OVER (PARTITION BY tempidgeocodebr) > 1) AS empate
            FROM output_db
            """
        )
        return n_casos_empate

    con.execute(
        """
        CREATE MACRO IF NOT EXISTS haversine(lat1, lon1, lat2, lon2) AS (
          6378137 * 2 * ASIN(
            SQRT(
              POWER(SIN(RADIANS(lat2 - lat1) / 2), 2) +
              COS(RADIANS(lat1)) * COS(RADIANS(lat2)) *
              POWER(SIN(RADIANS(lon2 - lon1) / 2), 2)
            )
          )
        )
        """
    )

    additional_cols_final = ""
    cols_encontradas = ""
    if resultado_completo:
        additional_cols_final = """
          , logradouro_encontrado, numero_encontrado, cep_encontrado,
          localidade_encontrada, municipio_encontrado, estado_encontrado,
          similaridade_logradouro, contagem_cnefe, empate, cod_setor
        """
        cols_encontradas = """
          , logradouro_encontrado, numero_encontrado, cep_encontrado,
          localidade_encontrada, municipio_encontrado, estado_encontrado,
          similaridade_logradouro, cod_setor
        """

    con.execute(
        f"""
        CREATE OR REPLACE TEMP TABLE output_db2 AS
        WITH
          base AS (
            SELECT *,
              (COUNT(*) OVER (PARTITION BY tempidgeocodebr) > 1) AS empate_inicial,
              ROW_NUMBER() OVER (
                PARTITION BY tempidgeocodebr
                ORDER BY contagem_cnefe DESC, desvio_metros, endereco_encontrado
              ) AS id
            FROM output_db
          ),
          distd AS (
            SELECT b.*,
              CASE WHEN empate_inicial THEN
                haversine(
                  lat, lon,
                  LEAD(lat) OVER (PARTITION BY tempidgeocodebr ORDER BY id),
                  LEAD(lon) OVER (PARTITION BY tempidgeocodebr ORDER BY id)
                )
              END AS dist_geocodebr_metros
            FROM base b
          ),
          filtered AS (
            SELECT d.*,
              (COUNT(*) OVER (PARTITION BY tempidgeocodebr) > 1) AS empate,
              MAX(dist_geocodebr_metros) OVER (PARTITION BY tempidgeocodebr) AS max_dist
            FROM distd d
            WHERE (empate_inicial IS FALSE)
               OR (empate_inicial AND dist_geocodebr_metros IS NULL)
               OR (empate_inicial AND dist_geocodebr_metros > 300)
          ),
          df_sem_empate AS (
            SELECT tempidgeocodebr, lat, lon, endereco_encontrado, tipo_resultado,
              contagem_cnefe, desvio_metros, empate {cols_encontradas}
            FROM filtered
            WHERE empate = FALSE
          ),
          df_empates_perdidos AS (
            SELECT tempidgeocodebr, lat, lon, endereco_encontrado, tipo_resultado,
              contagem_cnefe, desvio_metros, TRUE AS empate {cols_encontradas}
            FROM filtered
            WHERE empate = TRUE
              AND (
                max_dist > 1000
                OR log_causa_confusao
                OR REGEXP_MATCHES(endereco_encontrado,
                    '(RUA (QUATRO|QUATORZE|QUINZE|DEZESSEIS|DEZESSETE|DEZOITO|DEZENOVE|VINTE|TRINTA|QUARENTA|CINQUENTA|SESSENTA|SETENTA|OITENTA|NOVENTA))'
                )
              )
              AND NOT REGEXP_MATCHES(logradouro_encontrado, '\\bDE (JANEIRO|FEVEREIRO|MARCO|ABRIL|MAIO|JUNHO|JULHO|AGOSTO|SETEMBRO|OUTUBRO|NOVEMBRO|DEZEMBRO)\\b')
            QUALIFY ROW_NUMBER() OVER (PARTITION BY tempidgeocodebr ORDER BY contagem_cnefe DESC) = 1
          ),
          empates_restantes AS (
            SELECT f.*
            FROM filtered f
            WHERE f.empate = TRUE
              AND NOT EXISTS (SELECT 1 FROM df_sem_empate s WHERE s.tempidgeocodebr = f.tempidgeocodebr)
              AND NOT EXISTS (SELECT 1 FROM df_empates_perdidos p WHERE p.tempidgeocodebr = f.tempidgeocodebr)
          ),
          empates_wavg AS (
            SELECT e.*,
              (SUM(lat * contagem_cnefe) OVER (PARTITION BY tempidgeocodebr)
                / NULLIF(SUM(contagem_cnefe) OVER (PARTITION BY tempidgeocodebr), 0)) AS lat_wavg,
              (SUM(lon * contagem_cnefe) OVER (PARTITION BY tempidgeocodebr)
                / NULLIF(SUM(contagem_cnefe) OVER (PARTITION BY tempidgeocodebr), 0)) AS lon_wavg
            FROM empates_restantes e
          ),
          df_empates_salve AS (
            SELECT tempidgeocodebr, lat_wavg AS lat, lon_wavg AS lon,
              endereco_encontrado, tipo_resultado, contagem_cnefe,
              desvio_metros, TRUE AS empate {cols_encontradas}
            FROM empates_wavg
            QUALIFY ROW_NUMBER() OVER (PARTITION BY tempidgeocodebr ORDER BY contagem_cnefe DESC) = 1
          )
        SELECT tempidgeocodebr, lat, lon, tipo_resultado, desvio_metros,
          endereco_encontrado {additional_cols_final}
        FROM df_sem_empate
        UNION ALL
        SELECT tempidgeocodebr, lat, lon, tipo_resultado, desvio_metros,
          endereco_encontrado {additional_cols_final}
        FROM df_empates_perdidos
        UNION ALL
        SELECT tempidgeocodebr, lat, lon, tipo_resultado, desvio_metros,
          endereco_encontrado {additional_cols_final}
        FROM df_empates_salve
        """
    )

    if verboso:
        plural = "caso" if n_casos_empate == 1 else "casos"
        print(f"Foram encontrados e resolvidos {n_casos_empate} {plural} de empate.")
    return n_casos_empate


def _complete_columns(
    y: str,
    key_cols: list[str],
    resultado_completo: bool,
    probabilistic: bool = False,
) -> tuple[str, str]:
    if not resultado_completo:
        return "", ""

    output_cols = [_found_col_name(col) for col in key_cols]
    select_cols = [f"{y}.{col} AS {_found_col_name(col)}" for col in key_cols]
    if probabilistic:
        output_cols.append("similaridade_logradouro")
        select_cols.append("input_padrao_db.similaridade_logradouro AS similaridade_logradouro")
    output_cols.append("cod_setor")
    select_cols.append(f"{y}.cod_setor AS cod_setor")
    return ", " + ", ".join(output_cols), ", " + ", ".join(select_cols)


def _complete_weighted_columns(
    y: str,
    key_cols: list[str],
    resultado_completo: bool,
) -> tuple[str, str, str]:
    if not resultado_completo:
        return "", "", ""

    output_cols = [_found_col_name(col) for col in key_cols] + ["cod_setor"]
    first_cols = [f"{y}.{col} AS {_found_col_name(col)}" for col in key_cols]
    first_cols.append(f"{y}.cod_setor AS cod_setor")
    second_cols = [f"FIRST({_found_col_name(col)}) AS {_found_col_name(col)}" for col in key_cols]
    second_cols.append("FIRST(cod_setor) AS cod_setor")
    return ", " + ", ".join(output_cols), ", " + ", ".join(first_cols), ", " + ", ".join(second_cols)


def _found_col_name(col: str) -> str:
    if col == "localidade":
        return "localidade_encontrada"
    return f"{col}_encontrado"
