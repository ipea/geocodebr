# Override de match_weighted_cases() e match_weighted_cases_probabilistic() no namespace do geocodebr
# (sem editar r-package/R/). Mesma estrutura das funções originais; só a PARTE 2 (agregação/
# interpolação) passa a vir de 02_metodos_sql.R, escolhida por options(interp_metodo = "B0"|"B1"|...).
# Requer: 00_config.R e 02_metodos_sql.R carregados, e geocodebr carregado (load_all).

.parte2 <- function(match_type, grp_livres, ordem_first, colunas_encontradas, additional_cols_second) {
  m <- getOption("interp_metodo", "B0")
  glue::glue("
  , temp_w AS (SELECT *, {janelas_sql(paste0('tempidgeocodebr, numero', grp_livres))} FROM temp_db),
  agg AS (
    SELECT tempidgeocodebr, numero {grp_livres},
      {agregados_sql()},
      REGEXP_REPLACE(FIRST(endereco_completo {ordem_first}), ', \\d+ -', CONCAT(', ', numero, ' (aprox) -')) AS endereco_encontrado,
      '{match_type}' AS tipo_resultado,
      AVG(desvio_metros) AS desvio_metros,
      FIRST(log_causa_confusao {ordem_first}) AS log_causa_confusao,
      FIRST(contagem_cnefe {ordem_first}) AS contagem_cnefe {additional_cols_second}
    FROM temp_w
    GROUP BY tempidgeocodebr, numero {grp_livres})
  INSERT INTO output_db (tempidgeocodebr, lat, lon, endereco_encontrado, tipo_resultado, desvio_metros,
                         log_causa_confusao, contagem_cnefe {colunas_encontradas})
  SELECT tempidgeocodebr, {finais_sql(m, 'lat')}, {finais_sql(m, 'lon')}, endereco_encontrado, tipo_resultado,
         desvio_metros, log_causa_confusao, contagem_cnefe {colunas_encontradas}
  FROM agg;")
}

.cria_hav <- function(con) DBI::dbExecute(con, "
  CREATE OR REPLACE MACRO hav(la1, lo1, la2, lo2) AS
    2 * 6371008.8 * asin(sqrt(pow(sin(radians(la2 - la1) / 2), 2) +
      cos(radians(la1)) * cos(radians(la2)) * pow(sin(radians(lo2 - lo1) / 2), 2)))")

mwc_override <- function(con = con, x = 'input_padrao_db', output_tb = "output_db", key_cols = key_cols,
                         match_type = match_type, resultado_completo, pasta_dados) {
  y <- get_reference_table(match_type)
  key_cols <- get_key_cols(match_type)
  register_cnefe_table(con, match_type, pasta_dados, resultado_completo)
  .cria_hav(con)
  cols_not_null <- paste(glue::glue("{x}.{key_cols} IS NOT NULL"), collapse = ' AND ')
  key_cols <- key_cols[key_cols != 'numero']
  join_condition <- paste(glue::glue("{y}.{key_cols} = {x}.{key_cols}"), collapse = ' AND ')
  cols_livres <- setdiff(intersect(c("cep", "localidade"), strsplit(y, "_")[[1]]), key_cols)
  sel_livres <- if (length(cols_livres)) paste0(glue::glue(", {y}.{cols_livres} AS {cols_livres}_cnefe"), collapse = "") else ""
  grp_livres <- if (length(cols_livres)) paste0(glue::glue(", {cols_livres}_cnefe"), collapse = "") else ""
  ordem_first <- "ORDER BY ABS(numero - numero_cnefe), numero_cnefe, lat, lon"
  first <- monta_colunas_encontradas(y, key_cols, resultado_completo)
  second <- monta_colunas_encontradas(y, key_cols, resultado_completo, agregado = TRUE, ordem_first = ordem_first)
  q <- paste0(glue::glue("
    WITH temp_db AS (
      SELECT {x}.tempidgeocodebr, {x}.numero, {y}.numero AS numero_cnefe, {y}.lat, {y}.lon,
             {y}.endereco_completo{sel_livres}, {y}.desvio_metros, {x}.log_causa_confusao,
             {y}.n_casos AS contagem_cnefe {first$additional_cols}
      FROM {x} INNER JOIN {y} ON {join_condition}
      WHERE {cols_not_null})"),
    .parte2(match_type, grp_livres, ordem_first, first$colunas_encontradas, second$additional_cols))
  DBI::dbExecute(con, q)
  update_input_db(con, update_tb = x, reference_tb = output_tb, match_type = match_type)
}

mwcp_override <- function(con = con, x = 'input_padrao_db', output_tb = "output_db", key_cols = key_cols,
                          match_type = match_type, resultado_completo, pasta_dados) {
  y <- get_reference_table(match_type)
  key_cols <- get_key_cols(match_type)
  register_cnefe_table(con, match_type, pasta_dados, resultado_completo)
  .cria_hav(con)
  if (!match_type %in% match_types_jaro_redundante) {
    unique_logradouros_tbl <- register_unique_logradouros_table(con, match_type, pasta_dados)
    calculate_string_dist(con, match_type, unique_logradouros_tbl)
  }
  cols_not_null <- paste(glue::glue("{x}.{key_cols} IS NOT NULL"), collapse = ' AND ')
  key_cols <- key_cols[key_cols != 'numero']
  join_condition_determ <- paste(glue::glue("{y}.{key_cols} = {x}.{key_cols}"), collapse = ' AND ')
  join_condition_determ <- gsub('input_padrao_db.logradouro', 'input_padrao_db.temp_lograd_determ', join_condition_determ)
  cols_not_null_match <- gsub('.logradouro', '.temp_lograd_determ', cols_not_null)
  cols_livres <- setdiff(intersect(c("cep", "localidade"), strsplit(y, "_")[[1]]), key_cols)
  sel_livres <- if (length(cols_livres)) paste0(glue::glue(", {y}.{cols_livres} AS {cols_livres}_cnefe"), collapse = "") else ""
  grp_livres <- if (length(cols_livres)) paste0(glue::glue(", {cols_livres}_cnefe"), collapse = "") else ""
  ordem_first <- "ORDER BY ABS(numero - numero_cnefe), numero_cnefe, lat, lon"
  cb <- ""; a1 <- ""; a2 <- ""
  if (isTRUE(resultado_completo)) {
    cb <- ", similaridade_logradouro"; a1 <- glue::glue(", {x}.similaridade_logradouro")
    a2 <- glue::glue(", FIRST(similaridade_logradouro {ordem_first}) AS similaridade_logradouro")
  }
  first <- monta_colunas_encontradas(y, key_cols, resultado_completo, colunas_encontradas = cb, additional_cols = a1)
  second <- monta_colunas_encontradas(y, key_cols, resultado_completo, additional_cols = a2,
                                      agregado = TRUE, ordem_first = ordem_first)
  q <- paste0(glue::glue("
    WITH temp_db AS (
      SELECT {x}.tempidgeocodebr, {x}.numero, {y}.numero AS numero_cnefe, {y}.lat, {y}.lon,
             {y}.endereco_completo{sel_livres}, {y}.desvio_metros, {x}.log_causa_confusao,
             {y}.n_casos AS contagem_cnefe {first$additional_cols}
      FROM {x} INNER JOIN {y} ON {join_condition_determ}
      WHERE {cols_not_null_match})"),
    .parte2(match_type, grp_livres, ordem_first, first$colunas_encontradas, second$additional_cols))
  DBI::dbExecute(con, q)
  update_input_db(con, update_tb = x, reference_tb = output_tb, match_type = match_type)
}

instala_override <- function() {
  ns <- asNamespace("geocodebr")
  # o namespace é trancado: os auxiliares vão num ambiente-filho do namespace, que vira o
  # ambiente das duas funções substitutas (elas enxergam os internos do pacote e os auxiliares)
  e <- new.env(parent = ns)
  for (nm in c("janelas_sql", "agregados_sql", "finais_sql", ".interp", ".tem", ".salto", ".maisprox",
               ".bracket_trava", "K_M2", "TRAVA_A", "TRAVA_B", ".parte2", ".cria_hav")) {
    obj <- get(nm, envir = globalenv())
    if (is.function(obj)) environment(obj) <- e
    assign(nm, obj, envir = e)
  }
  f1 <- mwc_override; environment(f1) <- e
  f2 <- mwcp_override; environment(f2) <- e
  for (nm in c("match_weighted_cases", "match_weighted_cases_probabilistic"))
    if (bindingIsLocked(nm, ns)) unlockBinding(nm, ns)
  assign("match_weighted_cases", f1, envir = ns)
  assign("match_weighted_cases_probabilistic", f2, envir = ns)
  invisible(TRUE)
}
