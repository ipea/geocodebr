match_weighted_cases <- function(
  # nocov start
  con = con,
  x = 'input_padrao_db',
  output_tb = "output_db",
  key_cols = key_cols,
  match_type = match_type,
  resultado_completo,
  pasta_dados
) {
  # match_type = "da01"
  # key_cols <- geocodebr:::get_key_cols(match_type)

  # get corresponding parquet table
  cnefe_table_name <- get_reference_table(match_type)
  y <- cnefe_table_name
  key_cols <- get_key_cols(match_type)

  # write cnefe table to db
  register_cnefe_table(con, match_type, pasta_dados)


  # cols that cannot be null
  cols_not_null <- paste(
    glue::glue("{x}.{key_cols} IS NOT NULL"),
    collapse = ' AND '
  )

  # remove numero from key cols to allow for the matching
  key_cols <- key_cols[key_cols != 'numero']

  # Create the JOIN condition by concatenating the key columns
  join_condition <- paste(
    glue::glue("{y}.{key_cols} = {x}.{key_cols}"),
    collapse = ' AND '
  )

  # colunas de y que compoem endereco_completo e nao estao fixadas pelo join
  # (key_cols aqui ja sem 'numero'); e por elas que os candidatos de um mesmo
  # tempidgeocodebr se separam em enderecos distintos. Sao essas colunas que
  # entram no GROUP BY da parte 2, em vez da string endereco_encontrado (~70
  # bytes): a particao (tempidgeocodebr, endereco_encontrado) e identica a
  # (tempidgeocodebr, cols_livres), porque endereco_completo e constante dentro
  # de cada grupo (estado, municipio, logradouro, cep, localidade) do CNEFE e
  # valores distintos de cep/localidade geram strings distintas. Assim o regex
  # roda 1x por grupo, e nao 1x por candidato (~17-21 candidatos por endereco)
  cols_livres <- setdiff(intersect(c("cep", "localidade"), strsplit(y, "_")[[1]]), key_cols)
  sel_livres <- if (length(cols_livres)) {
    paste0(glue::glue(", {y}.{cols_livres} AS {cols_livres}_cnefe"), collapse = "")
  } else ""
  grp_livres <- if (length(cols_livres)) {
    paste0(glue::glue(", {cols_livres}_cnefe"), collapse = "")
  } else ""

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
             {y}.endereco_completo{sel_livres},
             {y}.desvio_metros,
             {x}.log_causa_confusao,
             {y}.n_casos AS contagem_cnefe {additional_cols_first}
      FROM {x}
      INNER JOIN {y}
      ON {join_condition}
      WHERE {cols_not_null}
    )

    -- PART 2: aggregate and interpolate get aprox location
  INSERT INTO output_db (tempidgeocodebr, lat, lon, endereco_encontrado, tipo_resultado, desvio_metros, log_causa_confusao, contagem_cnefe {colunas_encontradas})
      SELECT tempidgeocodebr,
        SUM((1/ABS(numero - numero_cnefe) * lat)) / SUM(1/ABS(numero - numero_cnefe)) AS lat,
        SUM((1/ABS(numero - numero_cnefe) * lon)) / SUM(1/ABS(numero - numero_cnefe)) AS lon,
        REGEXP_REPLACE(FIRST(endereco_completo {ordem_first}), ', \\d+ -', CONCAT(', ', numero, ' (aprox) -')) AS endereco_encontrado,
        '{match_type}' AS tipo_resultado,
        AVG(desvio_metros) as desvio_metros,
        FIRST(log_causa_confusao {ordem_first}) AS log_causa_confusao,
        FIRST(contagem_cnefe {ordem_first}) AS contagem_cnefe {additional_cols_second}
    FROM temp_db
    GROUP BY tempidgeocodebr, numero {grp_livres};"
  )

  DBI::dbExecute(con, query_match)
  # b <- DBI::dbReadTable(con, 'output_db')
  # summary(b$desvio_metros)

  # b <- DBI::dbGetQuery(con, query_match)

  # UPDATE input_padrao_db: Remove observations found in previous step
  temp_n <- update_input_db(
    con,
    update_tb = x,
    reference_tb = output_tb,
    match_type = match_type
  )

  return(temp_n)
} # nocov end
