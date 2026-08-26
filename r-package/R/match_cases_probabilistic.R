# prolema atual é que a pacote recalcula distancias de string TODA VEZ
# seria melhor criar uma tabela de distancia e ir populando

# 1st step: create small table with unique logradouros
# 2nd step: update input_padrao_db with the most probable logradouro
# 3rd step: deterministic match to update output

match_cases_probabilistic <- function(
  con = con,
  x = 'input_padrao_db',
  output_tb = "output_db",
  key_cols = key_cols,
  match_type = match_type,
  resultado_completo,
  pasta_dados
) {
  # nocov start

  # match_type = "pn01"

  # get corresponding parquet table and key columns
  cnefe_table_name <- get_reference_table(match_type)
  y <- cnefe_table_name
  key_cols <- get_key_cols(match_type)

  # write cnefe table to db
  register_cnefe_table(con, match_type, pasta_dados)

  # 1st step: create small table with unique logradouros -----------------------
  unique_logradouros_tbl <- register_unique_logradouros_table(con, match_type, pasta_dados)

  # 2nd step: update input_padrao_db with the most probable logradouro ---------

  calculate_string_dist(con, match_type, unique_logradouros_tbl)

  # 3rd step: update output table com match deterministico --------------------------------------------------------

  # update join condition to use probable logradouro and deterministic number
  join_condition_match <- paste(
    glue::glue("{y}.{key_cols} = {x}.{key_cols}"),
    collapse = ' AND '
  )

  join_condition_match <- gsub(
    'input_padrao_db.logradouro',
    'input_padrao_db.temp_lograd_determ',
    join_condition_match
  )

  # update cols that cannot be null
  cols_not_null <- paste(
    glue::glue("{x}.{key_cols} IS NOT NULL"),
    collapse = ' AND '
  )

  # cols that cannot be null
  cols_not_null <- gsub('.logradouro', '.temp_lograd_determ', cols_not_null)

  # `logradouro_encontrado` eh coluna de trabalho interna, e nao apenas uma coluna
  # de output: a resolucao de empates em trata_empates_geocode_duckdb() usa essa
  # coluna para aplicar a excecao dos logradouros com nome de data. Por isso ela
  # precisa ser preenchida sempre, independentemente de `resultado_completo` -- o
  # schema de output_db em geocode.R ja a declara nos dois casos. As demais
  # colunas `*_encontrado` seguem condicionadas a `resultado_completo`.
  # similaridade_logradouro eh especifica do caminho probabilistico -- soma
  # como base antes de chamar o helper comum, que decide sozinho (via
  # resultado_completo) o que mais acrescentar
  colunas_encontradas <- ""
  additional_cols <- ""
  if (isTRUE(resultado_completo)) {
    colunas_encontradas <- ", similaridade_logradouro"
    additional_cols <- ", input_padrao_db.similaridade_logradouro AS similaridade_logradouro"
  }

  extra <- monta_colunas_encontradas(
    y, key_cols, resultado_completo,
    colunas_encontradas = colunas_encontradas,
    additional_cols = additional_cols
  )
  colunas_encontradas <- extra$colunas_encontradas
  additional_cols <- extra$additional_cols

  # summarize query
  query_update_db <- glue::glue(
    "INSERT INTO output_db (tempidgeocodebr, lat, lon, endereco_encontrado, tipo_resultado,
                            desvio_metros, log_causa_confusao, contagem_cnefe {colunas_encontradas} )
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
      ON {join_condition_match}
      WHERE {cols_not_null};"
  )

  DBI::dbExecute(con, query_update_db)
  # DBI::dbExecute(con, query_update_db)
  # b <- DBI::dbReadTable(con, 'output_db')

  # UPDATE input_padrao_db: Remove observations found in previous step
  temp_n <- update_input_db(
    con,
    update_tb = x,
    reference_tb = output_tb
  )

  return(temp_n)
} # nocov end
