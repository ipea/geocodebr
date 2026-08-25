# 1st step: create small table with unique logradouros
# 2nd step: update input_padrao_db with the most probable logradouro
# 3rd step: deterministic match
# 4th step: aggregate

match_weighted_cases_probabilistic <- function(
  # nocov start
  con = con,
  x = 'input_padrao_db',
  output_tb = "output_db",
  key_cols = key_cols,
  match_type = match_type,
  resultado_completo,
  pasta_dados) {

  # match_type = "pn01"

  # get corresponding parquet table
  cnefe_table_name <- get_reference_table(match_type)
  y <- cnefe_table_name
  key_cols <- get_key_cols(match_type)

  # write cnefe table to db
  register_cnefe_table(con, match_type, pasta_dados)


  # 1st + 2nd steps: recalcula o logradouro provavel (Jaro)  eatualiza input_padrao_db   --------------------------------------------------------
  # aqui a gente pula os match_types_jaro_redundante, pq a etapa
  # "pn0k" anterior ja fez esse trabalho para o mesmo candidato e mesmo corte
  # (ver comentario em utils.R). Reexecutar ali e um no-op comprovado.
  if (!match_type %in% match_types_jaro_redundante) {

    # step 1: create small table with unique logradouros
    unique_logradouros_tbl <- register_unique_logradouros_table(con, match_type, pasta_dados)

    # step 2: update input_padrao_db with the most probable logradouro
    calculate_string_dist(con, match_type, unique_logradouros_tbl)
  }

  # 3rd step: match deterministico --------------------------------------------------------

  # cols that cannot be null
  cols_not_null <- paste(
    glue::glue("{x}.{key_cols} IS NOT NULL"),
    collapse = ' AND '
  )

  key_cols <- key_cols[key_cols != 'numero']

  # Create the JOIN condition by concatenating the key columns
  join_condition_determ <- paste(
    glue::glue("{y}.{key_cols} = {x}.{key_cols}"),
    collapse = ' AND '
  )

  # update join condition to use probable logradouro
  join_condition_determ <- gsub(
    'input_padrao_db.logradouro',
    'input_padrao_db.temp_lograd_determ',
    join_condition_determ
  )

  # cols that cannot be null
  cols_not_null_match <- gsub(
    '.logradouro',
    '.temp_lograd_determ',
    cols_not_null
  )

  # ordem canonica de desempate dentro do GROUP BY da parte 2 da query: o
  # candidato mais proximo do numero buscado vence; empate exato de distancia
  # (ex.: numero 50 entre candidatos 48 e 52) desempata por numero_cnefe,
  # depois lat/lon -- garante resultado identico entre execucoes, mesmo em
  # paralelo (ver MEMORY.md [LEARN:duckdb], match_type da0x/pa0x)
  ordem_first <- "ORDER BY ABS(numero - numero_cnefe), numero_cnefe, lat, lon"


  # parte 1 (CTE, sem agregacao)
  # `logradouro_encontrado` eh coluna de trabalho interna, e nao apenas uma coluna
  # de output: a resolucao de empates em trata_empates_geocode_duckdb() usa essa
  # coluna para aplicar a excecao dos logradouros com nome de data. Por isso ela
  # precisa ser preenchida sempre, independentemente de `resultado_completo` -- o
  # schema de output_db em geocode.R ja a declara nos dois casos. As demais
  # colunas `*_encontrado` seguem condicionadas a `resultado_completo`.
  first <- monta_colunas_encontradas(y, key_cols, resultado_completo)
  colunas_encontradas <- first$colunas_encontradas
  additional_cols_first <- first$additional_cols

  # parte 2 (SELECT agregado por GROUP BY) -- cada coluna, inclusive
  # logradouro_encontrado, embrulhada em FIRST(... ordem_first)
  second <- monta_colunas_encontradas(
    y, key_cols, resultado_completo,
    agregado = TRUE,
    ordem_first = ordem_first
  )
  additional_cols_second <- second$additional_cols

  # Match query  --------------------------------------------------------

  query_match <- glue::glue(
    "
  -- PART 1) inner join to get all cases that match
  WITH temp_db AS (
      SELECT {x}.tempidgeocodebr,
             {x}.numero,
             {y}.numero AS numero_cnefe,
             {y}.lat, {y}.lon,
             REGEXP_REPLACE( {y}.endereco_completo, ', \\d+ -', CONCAT(', ', {x}.numero, ' (aprox) -')) AS endereco_encontrado,
             {x}.similaridade_logradouro,
             {y}.desvio_metros,
             {x}.log_causa_confusao,
             {y}.n_casos AS contagem_cnefe {additional_cols_first}
          FROM {x}
          INNER JOIN {y}
          ON {join_condition_determ}
          WHERE {cols_not_null_match}
          )

  -- PART 2: aggregate and interpolate get aprox location

  INSERT INTO output_db (tempidgeocodebr, lat, lon, endereco_encontrado, tipo_resultado, desvio_metros,
                         log_causa_confusao, similaridade_logradouro, contagem_cnefe {colunas_encontradas})
       SELECT tempidgeocodebr,
         SUM((1/ABS(numero - numero_cnefe) * lat)) / SUM(1/ABS(numero - numero_cnefe)) AS lat,
         SUM((1/ABS(numero - numero_cnefe) * lon)) / SUM(1/ABS(numero - numero_cnefe)) AS lon,
         FIRST(endereco_encontrado {ordem_first}) AS endereco_encontrado,
         '{match_type}' AS tipo_resultado,
         AVG(desvio_metros) AS desvio_metros,
         FIRST(log_causa_confusao {ordem_first}) AS log_causa_confusao,
         FIRST(similaridade_logradouro {ordem_first}) AS similaridade_logradouro,
         FIRST(contagem_cnefe {ordem_first}) AS contagem_cnefe {additional_cols_second}
      FROM temp_db
      GROUP BY tempidgeocodebr, endereco_encontrado;"
  )

  DBI::dbExecute(con, query_match)
  # DBI::dbExecute(con, query_aggregate)
  # d <- DBI::dbReadTable(con, 'output_db')
  # d <- DBI::dbReadTable(con, 'aaa')

  # UPDATE input_padrao_db: Remove observations found in previous step
  temp_n <- update_input_db(
    con,
    update_tb = x,
    reference_tb = output_tb
  )

  return(temp_n)
} # nocov end
