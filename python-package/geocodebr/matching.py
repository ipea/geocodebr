from __future__ import annotations

import duckdb

from .constants import (
    EXACT_TYPES_NO_NUMBER,
    MATCH_TYPES_JARO_REDUNDANTE,
    NUMBER_EXACT_TYPES,
    NUMBER_INTERPOLATION_TYPES,
    PROBABILISTIC_EXACT_TYPES,
    PROBABILISTIC_INTERPOLATION_TYPES,
    PROBABILISTIC_TYPES_NO_NUMBER,
)
from .string_dist import calculate_string_dist
from .tables import register_cnefe_table, register_unique_logradouros_table
from .utils import get_key_cols, get_reference_table, update_input_db


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
    pasta_dados: str | None = None,
) -> int:
    y = get_reference_table(match_type)
    key_cols = get_key_cols(match_type)
    register_cnefe_table(con, match_type, pasta_dados)

    join_condition = " AND ".join(f"{y}.{col} = {x}.{col}" for col in key_cols)
    cols_not_null = " AND ".join(f"{x}.{col} IS NOT NULL" for col in key_cols)
    colunas_encontradas, additional_cols = _build_found_columns(y, key_cols, resultado_completo)

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
    pasta_dados: str | None = None,
) -> int:
    y = get_reference_table(match_type)
    original_key_cols = get_key_cols(match_type)
    register_cnefe_table(con, match_type, pasta_dados)

    cols_not_null = " AND ".join(f"{x}.{col} IS NOT NULL" for col in original_key_cols)
    key_cols = [col for col in original_key_cols if col != "numero"]
    join_condition = " AND ".join(f"{y}.{col} = {x}.{col}" for col in key_cols)
    ordem_first = "ORDER BY ABS(numero - numero_cnefe), numero_cnefe, lat, lon"
    colunas_encontradas, additional_first, additional_second = _complete_weighted_columns(
        y, key_cols, resultado_completo, ordem_first
    )

    con.execute(
        f"""
        WITH temp_db AS (
          SELECT {x}.tempidgeocodebr,
                 {x}.numero,
                 {y}.numero AS numero_cnefe,
                 ABS({x}.numero - {y}.numero) AS distancia_numero,
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
          FIRST(endereco_encontrado {ordem_first}) AS endereco_encontrado,
          '{match_type}' AS tipo_resultado,
          AVG(desvio_metros) AS desvio_metros,
          FIRST(log_causa_confusao {ordem_first}) AS log_causa_confusao,
          FIRST(contagem_cnefe {ordem_first}) AS contagem_cnefe {additional_second}
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
    pasta_dados: str | None = None,
) -> int:
    y = get_reference_table(match_type)
    key_cols = get_key_cols(match_type)
    register_cnefe_table(con, match_type, pasta_dados)
    unique_logradouros_tbl = register_unique_logradouros_table(con, match_type, pasta_dados)
    calculate_string_dist(con, match_type, unique_logradouros_tbl)

    join_condition = " AND ".join(f"{y}.{col} = {x}.{col}" for col in key_cols)
    join_condition = join_condition.replace("input_padrao_db.logradouro", "input_padrao_db.temp_lograd_determ")
    cols_not_null = " AND ".join(f"{x}.{col} IS NOT NULL" for col in key_cols)
    cols_not_null = cols_not_null.replace(".logradouro", ".temp_lograd_determ")
    colunas_prefix = ""
    additional_prefix = ""
    if resultado_completo:
        colunas_prefix = ", similaridade_logradouro"
        additional_prefix = f", {x}.similaridade_logradouro AS similaridade_logradouro"
    colunas_encontradas, additional_cols = _build_found_columns(
        y, key_cols, resultado_completo,
        colunas_prefix=colunas_prefix,
        additional_prefix=additional_prefix,
    )

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
    pasta_dados: str | None = None,
) -> int:
    y = get_reference_table(match_type)
    original_key_cols = get_key_cols(match_type)
    register_cnefe_table(con, match_type, pasta_dados)
    if match_type not in MATCH_TYPES_JARO_REDUNDANTE:
        unique_logradouros_tbl = register_unique_logradouros_table(con, match_type, pasta_dados)
        calculate_string_dist(con, match_type, unique_logradouros_tbl)

    cols_not_null = " AND ".join(f"{x}.{col} IS NOT NULL" for col in original_key_cols)
    key_cols = [col for col in original_key_cols if col != "numero"]
    join_condition = " AND ".join(f"{y}.{col} = {x}.{col}" for col in key_cols)
    join_condition = join_condition.replace("input_padrao_db.logradouro", "input_padrao_db.temp_lograd_determ")
    cols_not_null_match = cols_not_null.replace(".logradouro", ".temp_lograd_determ")
    ordem_first = "ORDER BY ABS(numero - numero_cnefe), numero_cnefe, lat, lon"
    colunas_prefix = ""
    additional_prefix_first = ""
    additional_prefix_second = ""
    if resultado_completo:
        colunas_prefix = ", similaridade_logradouro"
        additional_prefix_first = f", {x}.similaridade_logradouro"
        additional_prefix_second = (
            f", FIRST(similaridade_logradouro {ordem_first}) AS similaridade_logradouro"
        )
    colunas_encontradas, additional_first, additional_second = _complete_weighted_columns(
        y, key_cols, resultado_completo, ordem_first,
        colunas_prefix=colunas_prefix,
        additional_prefix_first=additional_prefix_first,
        additional_prefix_second=additional_prefix_second,
    )

    con.execute(
        f"""
        WITH temp_db AS (
          SELECT {x}.tempidgeocodebr,
                 {x}.numero,
                 {y}.numero AS numero_cnefe,
                 ABS({x}.numero - {y}.numero) AS distancia_numero,
                 {y}.lat, {y}.lon,
                 REGEXP_REPLACE({y}.endereco_completo, ', \\d+ -', CONCAT(', ', {x}.numero, ' (aprox) -')) AS endereco_encontrado,
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
          desvio_metros, log_causa_confusao, contagem_cnefe {colunas_encontradas}
        )
        SELECT tempidgeocodebr,
          SUM((1 / ABS(numero - numero_cnefe) * lat)) / SUM(1 / ABS(numero - numero_cnefe)) AS lat,
          SUM((1 / ABS(numero - numero_cnefe) * lon)) / SUM(1 / ABS(numero - numero_cnefe)) AS lon,
          FIRST(endereco_encontrado {ordem_first}) AS endereco_encontrado,
          '{match_type}' AS tipo_resultado,
          AVG(desvio_metros) AS desvio_metros,
          FIRST(log_causa_confusao {ordem_first}) AS log_causa_confusao,
          FIRST(contagem_cnefe {ordem_first}) AS contagem_cnefe {additional_second}
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
    # 1) identifica e materializa os casos de empate --------------------------------
    con.execute(
        """
        CREATE OR REPLACE TEMP TABLE ids_empatados AS
        SELECT tempidgeocodebr
        FROM output_db
        GROUP BY tempidgeocodebr
        HAVING COUNT(*) > 1
        """
      )

    n_casos_empate = con.execute(
        """
        SELECT COUNT(*) AS n_casos_empate FROM ids_empatados
        """
    ).fetchone()[0]

    # 2) se nao tiver mais empates, termina aqui --------------------------------------
    # Adiciona a coluna de empate
    if n_casos_empate == 0:
        con.execute(
          """
          ALTER TABLE output_db
          ADD COLUMN IF NOT EXISTS empate BOOLEAN DEFAULT FALSE;
          """
        )
        return 0

    # 3) se nao for para resolver empates: ------------------------------------------
    # - calcula / identifica casos de empate
    # - gera warning
    # - retorna resultado 
    if not resolver_empates:
        con.execute(
            """
            ALTER TABLE output_db
            ADD COLUMN IF NOT EXISTS empate BOOLEAN DEFAULT FALSE
            """
        )
        con.execute(
            """
            UPDATE output_db SET empate = TRUE
            WHERE tempidgeocodebr IN (SELECT tempidgeocodebr FROM ids_empatados)
            """
        )
        con.execute(
            """
            ALTER TABLE output_db RENAME TO output_db2
            """
        )

        plural = "caso" if n_casos_empate == 1 else "casos"
        print(
          f"Foram encontrados {n_casos_empate} {plural} de empate. " 
          "Estes casos foram marcados com valor `TRUE` na coluna 'empate', "
          "e podem ser inspecionados na coluna 'endereco_encontrado'. "
          "Alternativamente, use `resolver_empates = TRUE` para que o pacote lide "
          "com os empates automaticamente."
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

    # 4) se for para resolver empates, trata de 3 casos separados -----------------
    # D) nao empatados
    # E) empatados perdidos (dist > 1Km e lograoduros ambiguos)
    #    solucao: usa caso com maior contagem_cnefe
    # F) empatados mas que da pra salvar (dist < 1km e logradouros nao ambiguos)
    #    solucao: agrega casos provaveis de serem na mesma rua com media ponderada
    #    das coordenadas, mas retorna  endereco_encontrado do caso com maior
    #    contagem_cnefe
    additional_cols_final = ""
    cols_encontradas = ""
    cols_passthrough = ""

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
        # Cria a coluna de empate para os não empatados
        cols_passthrough = """
          , logradouro_encontrado, numero_encontrado, cep_encontrado,
        localidade_encontrada, municipio_encontrado, estado_encontrado,
        similaridade_logradouro, contagem_cnefe, FALSE AS empate, cod_setor
        """

   # 4a) pipeline de classificacao, SOMENTE sobre os grupos empatados ------------
    con.execute(
        """
        CREATE OR REPLACE TEMP TABLE empates_classif AS
        WITH
        -- A) tabela *base* ranqueia os candidatos de cada grupo empatado
        -- (inclui mesmo aqueles a menos de 300 metros)
          base AS (
            SELECT
              o.*,
              ROW_NUMBER() OVER (PARTITION BY tempidgeocodebr ORDER BY contagem_cnefe DESC, desvio_metros, endereco_encontrado) AS id
            FROM output_db o
            WHERE EXISTS (SELECT 1 FROM ids_empatados i WHERE i.tempidgeocodebr = o.tempidgeocodebr)
          ),

        -- B) tabela *distd* calcula distancia entre os casos empatados
        -- Usa LAG (e nao LEAD): a distancia de cada linha eh medida
        -- contra a linha ANTERIOR, que por construcao do 'id' tem contagem_cnefe
        -- maior ou igual. Assim, quando o filtro (C) descarta um par a menos de
        -- 300 metros, quem sai eh sempre a linha de MENOR contagem_cnefe.
        -- Na primeira linha de cada grupo o LAG e NULL e a haversine propaga NULL.
        distd AS (
            SELECT
              b.*,
              haversine(
                lat, lon,
                LAG(lat) OVER (PARTITION BY tempidgeocodebr ORDER BY id),
                LAG(lon) OVER (PARTITION BY tempidgeocodebr ORDER BY id)
              ) AS dist_geocodebr_metros
            FROM base b
          )

        -- C) mantem apenas casos de empate que estao a mais de 300 metros e
        -- recalcula a coluna de empate sobre os sobreviventes
        -- A linha com dist NULL eh a primeira da particao (id = 1), i.e. a de maior
        -- contagem_cnefe, que por isso eh sempre preservada.
        SELECT
          d.*,
          (COUNT(*) OVER (PARTITION BY tempidgeocodebr) > 1) AS empate,
          MAX(dist_geocodebr_metros) OVER (PARTITION BY tempidgeocodebr) AS max_dist
        FROM distd d
        WHERE dist_geocodebr_metros IS NULL
          OR dist_geocodebr_metros > 300;
        """
    )

    # 4b) monta output_db2: nao-empatados passam direto de output_db (sem nenhuma
    # window function); D/E/F sao derivados de empates_classif
    con.execute(
        f"""
        CREATE OR REPLACE TEMP TABLE output_db2 AS
        WITH
        -- D) tabela *df_sem_empate* com os casos que deixaram de ser empate
        -- apos o colapso de 300 metros
        df_sem_empate AS (
            SELECT
              tempidgeocodebr,
              lat,
              lon,
              endereco_encontrado,
              tipo_resultado,
              contagem_cnefe,
              desvio_metros,
              empate {cols_encontradas}
            FROM empates_classif
            WHERE empate = FALSE
          ),

          -- E) empatados perdidos (exemplo: max_dist > 1000; acrescente demais regras aqui)
          df_empates_perdidos AS (
            SELECT
              tempidgeocodebr,
              lat,
              lon,
              endereco_encontrado,
              tipo_resultado,
              contagem_cnefe,
              desvio_metros,
              TRUE AS empate {cols_encontradas}
            FROM empates_classif
            WHERE empate = TRUE
              -- so match com logradouro pode ser 'perdido': nas categorias sem
              -- logradouro (dc01, dc02, db01, dm01) o empate e entre enderecos do
              -- mesmo CEP/bairro/municipio, e a media ponderada e o centroide que
              -- a precisao correspondente promete
              AND logradouro_encontrado IS NOT NULL
              AND (
                max_dist > 1000
                OR log_causa_confusao
                -- o regex de numeros por extenso casa por substring (pega 'RUA
                -- QUINZE' dentro de 'RUA QUINZE DE NOVEMBRO'), entao a excecao
                -- de ruas-data neutraliza APENAS este braco: nomes-data seguem
                -- podendo ser 'perdidos' pela distancia (max_dist) acima
                OR (
                  REGEXP_MATCHES(endereco_encontrado,
                      '(RUA (QUATRO|QUATORZE|QUINZE|DEZESSEIS|DEZESSETE|DEZOITO|DEZENOVE|VINTE|TRINTA|QUARENTA|CINQUENTA|SESSENTA|SETENTA|OITENTA|NOVENTA))'
                  )
                  AND NOT REGEXP_MATCHES(logradouro_encontrado, '\\bDE (JANEIRO|FEVEREIRO|MARCO|ABRIL|MAIO|JUNHO|JULHO|AGOSTO|SETEMBRO|OUTUBRO|NOVEMBRO|DEZEMBRO)\\b')
                )
              )
            QUALIFY ROW_NUMBER()
              OVER (PARTITION BY tempidgeocodebr ORDER BY contagem_cnefe DESC, desvio_metros, endereco_encontrado) = 1
          ),

          -- F) empatados salvaveis = restantes (empatados que nao cairam em E)
          -- 'empate' e constante por tempidgeocodebr, entao empate = TRUE ja
          -- exclui os grupos de df_sem_empate (D) sem precisar de anti-join
          empates_restantes AS (
            SELECT f.*
            FROM empates_classif f
            WHERE f.empate = TRUE
              AND NOT EXISTS (SELECT 1 FROM df_empates_perdidos p WHERE p.tempidgeocodebr = f.tempidgeocodebr)
          ),
          empates_wavg AS (
            SELECT
              e.*,
              (SUM(lat * contagem_cnefe) OVER (PARTITION BY tempidgeocodebr)
                / NULLIF(SUM(contagem_cnefe) OVER (PARTITION BY tempidgeocodebr), 0)) AS lat_wavg,
              (SUM(lon * contagem_cnefe) OVER (PARTITION BY tempidgeocodebr)
                / NULLIF(SUM(contagem_cnefe) OVER (PARTITION BY tempidgeocodebr), 0)) AS lon_wavg
            FROM empates_restantes e
          ),
          df_empates_salve AS (
            SELECT
              tempidgeocodebr,
              lat_wavg AS lat,
              lon_wavg AS lon,
              endereco_encontrado,
              tipo_resultado,
              contagem_cnefe,
              desvio_metros,
              TRUE AS empate {cols_encontradas}
            FROM empates_wavg
            QUALIFY ROW_NUMBER()
              OVER (PARTITION BY tempidgeocodebr ORDER BY contagem_cnefe DESC, desvio_metros, endereco_encontrado) = 1
          )

        -- junta as 3 tabelas (df_sem_empate, df_empates_perdidos, df_empates_salve)
        -- e o passthrough dos casos que nunca tiveram empate
        SELECT
          tempidgeocodebr, lat, lon, tipo_resultado, desvio_metros,
          endereco_encontrado {additional_cols_final}
        FROM df_sem_empate
        UNION ALL
        SELECT
          tempidgeocodebr, lat, lon, tipo_resultado, desvio_metros,
          endereco_encontrado {additional_cols_final}
        FROM df_empates_perdidos
        UNION ALL
        SELECT
          tempidgeocodebr, lat, lon, tipo_resultado, desvio_metros,
          endereco_encontrado {additional_cols_final}
        FROM df_empates_salve
        UNION ALL
        SELECT
          tempidgeocodebr, lat, lon, tipo_resultado, desvio_metros,
          endereco_encontrado {cols_passthrough}
        FROM output_db o
        WHERE NOT EXISTS (SELECT 1 FROM ids_empatados i WHERE i.tempidgeocodebr = o.tempidgeocodebr)
        """
    )

    if verboso:
        plural = "caso" if n_casos_empate == 1 else "casos"
        print(f"Foram encontrados e resolvidos {n_casos_empate} {plural} de empate.")
    return n_casos_empate


def _build_found_columns(
    y: str,
    key_cols: list[str],
    resultado_completo: bool,
    colunas_prefix: str = "",
    additional_prefix: str = "",
    agregado: bool = False,
    ordem_first: str = "",
) -> tuple[str, str]:
    """Monta as colunas `*_encontrado` da query de match.

    Espelha ``monta_colunas_encontradas()`` em ``r-package/R/match_helpers.R``.

    ``logradouro_encontrado`` e coluna de trabalho interna (a resolucao de
    empates em ``trata_empates_geocode_duckdb()`` a usa para aplicar a excecao
    dos logradouros com nome de data). Por isso e populada sempre que
    ``'logradouro'`` esta em ``key_cols``, independentemente de
    ``resultado_completo``. As demais colunas ``*_encontrado`` e ``cod_setor``
    so entram quando ``resultado_completo=True``.

    ``colunas_prefix``/``additional_prefix`` permitem ao chamador injetar
    colunas extras antes deste helper (ex.: ``similaridade_logradouro`` nos
    caminhos probabilisticos, condicional a ``resultado_completo`` mas nao
    parte de ``key_cols``).

    Com ``agregado=True``, cada coluna e embrulhada em
    ``FIRST(... {ordem_first})`` em vez do ``SELECT`` direto -- usado na
    segunda parte da query (agregada por ``GROUP BY``) de
    ``match_weighted_cases()`` e ``match_weighted_cases_probabilistic()``.
    """
    colunas_encontradas = colunas_prefix
    additional_cols = additional_prefix

    if "logradouro" in key_cols:
        if agregado:
            select_lograd = (
                f"FIRST(logradouro_encontrado {ordem_first}) AS logradouro_encontrado"
            )
        else:
            select_lograd = f"{y}.logradouro AS logradouro_encontrado"
        colunas_encontradas = f"{colunas_encontradas}, logradouro_encontrado"
        additional_cols = f"{additional_cols}, {select_lograd}"

    if not resultado_completo:
        return colunas_encontradas, additional_cols

    demais_key_cols = [c for c in key_cols if c != "logradouro"]
    if demais_key_cols:
        nomes = ", ".join(_found_col_name(c) for c in demais_key_cols)
        if agregado:
            select = ", ".join(
                f"FIRST({_found_col_name(c)} {ordem_first}) AS {_found_col_name(c)}"
                for c in demais_key_cols
            )
        else:
            select = ", ".join(
                f"{y}.{c} AS {_found_col_name(c)}" for c in demais_key_cols
            )
        colunas_encontradas = f"{colunas_encontradas}, {nomes}"
        additional_cols = f"{additional_cols}, {select}"

    if agregado:
        cod_select = f", FIRST(cod_setor {ordem_first}) AS cod_setor"
    else:
        cod_select = f", {y}.cod_setor AS cod_setor"
    additional_cols = f"{additional_cols}{cod_select}"
    colunas_encontradas = f"{colunas_encontradas}, cod_setor"

    return colunas_encontradas, additional_cols


def _complete_weighted_columns(
    y: str,
    key_cols: list[str],
    resultado_completo: bool,
    ordem_first: str,
    colunas_prefix: str = "",
    additional_prefix_first: str = "",
    additional_prefix_second: str = "",
) -> tuple[str, str, str]:
    """Wrapper para os dois passes (temp_db + agregado) dos ``match_weighted_*``.

    Espelha a estrutura de ``r-package/R/match_weighted_cases.R`` (chamada
    dupla de ``monta_colunas_encontradas``): o primeiro passe (nao agregado)
    popula o ``temp_db``; o segundo (agregado, ``FIRST(... ordem_first)``)
    alimenta o SELECT final apos o ``GROUP BY``.
    """
    colunas_encontradas, additional_first = _build_found_columns(
        y, key_cols, resultado_completo,
        colunas_prefix=colunas_prefix,
        additional_prefix=additional_prefix_first,
    )
    _, additional_second = _build_found_columns(
        y, key_cols, resultado_completo,
        colunas_prefix=colunas_prefix,
        additional_prefix=additional_prefix_second,
        agregado=True,
        ordem_first=ordem_first,
    )
    return colunas_encontradas, additional_first, additional_second


def _found_col_name(col: str) -> str:
    if col == "localidade":
        return "localidade_encontrada"
    return f"{col}_encontrado"
