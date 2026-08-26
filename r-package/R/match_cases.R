match_cases <- function(
  # nocov start
  con = con,
  x = "input_padrao_db",
  output_tb = "output_db",
  key_cols = key_cols,
  match_type = match_type,
  resultado_completo,
  pasta_dados
) {
  # match_type = "dn01"

  # get corresponding parquet table
  cnefe_table_name <- get_reference_table(match_type)
  y <- cnefe_table_name
  key_cols <- get_key_cols(match_type)

  # write cnefe table to db
  register_cnefe_table(con, match_type, pasta_dados)

  # Create the JOIN condition by concatenating the key columns
  join_condition <- paste(
    glue::glue("{y}.{key_cols} = {x}.{key_cols}"),
    collapse = ' AND '
  )

  # cols from x that cannot be null
  # isso serve como filtro pre-join, pra fazer o join soh em quem nao foi encontrado ainda
  cols_not_null <- paste(
    glue::glue("{x}.{key_cols} IS NOT NULL"),
    collapse = ' AND '
  )

  # `logradouro_encontrado` eh coluna de trabalho interna, e nao apenas uma coluna
  # de output: a resolucao de empates em trata_empates_geocode_duckdb() usa essa
  # coluna para aplicar a excecao dos logradouros com nome de data. Por isso ela
  # precisa ser preenchida sempre, independentemente de `resultado_completo` -- o
  # schema de output_db em geocode.R ja a declara nos dois casos. As demais
  # colunas `*_encontrado` seguem condicionadas a `resultado_completo`.
  extra <- monta_colunas_encontradas(y, key_cols, resultado_completo)
  colunas_encontradas <- extra$colunas_encontradas
  additional_cols <- extra$additional_cols

  # summarize query
  query_match <- glue::glue(
    "INSERT INTO output_db (tempidgeocodebr, lat, lon, endereco_encontrado, tipo_resultado,
                            desvio_metros, log_causa_confusao, contagem_cnefe {colunas_encontradas})
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
      WHERE {cols_not_null};"
  )

  DBI::dbExecute(con, query_match)
  # a <- DBI::dbReadTable(con, 'output_db')
  # summary(a$desvio_metros)
  # summary(a$lat)

  # UPDATE input_padrao_db: Remove observations found in previous step
  temp_n <- update_input_db(
    con,
    update_tb = x,
    reference_tb = output_tb
  )

  return(temp_n)
} # nocov end
