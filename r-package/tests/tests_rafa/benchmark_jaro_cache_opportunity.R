# Medicao da oportunidade de um cache cumulativo (por par de strings) para o
# calculo de distancia de Jaro em calculate_string_dist(), pedida pelo usuario
# em 2026-08-26 -- ver conversa da sessao. Objetivo: quantificar, ANTES de
# mexer em qualquer codigo, (a) quanto tempo o pipeline gasta em
# calculate_string_dist()/register_unique_logradouros_table() (Rprof, mesmo
# padrao dos benchmarks anteriores) e (b) quanta redundancia existe -- tanto
# DENTRO de uma etapa (mesma string de logradouro em varias linhas do input)
# quanto ENTRE etapas (pn01 -> pn02 -> pn03) -- que um cache chaveado por
# (logradouro_input, logradouro_cnefe) eliminaria.
#
# Nao mexe em nenhum arquivo de R/ -- so instrumenta com queries de leitura
# (SELECT) rodadas ANTES da chamada real de cada match_fun, entao nao altera
# o estado real do pipeline nem o resultado final.

devtools::load_all('.')

data_path <- system.file("extdata/large_sample.parquet", package = "geocodebr")
input_df  <- arrow::read_parquet(data_path)

campos <- geocodebr::definir_campos(
  logradouro = 'logradouro',
  numero     = 'numero',
  cep        = 'cep',
  localidade = 'bairro',
  municipio  = 'municipio',
  estado     = 'uf'
)

out_dir <- "tests/tests_rafa/_benchmark_jaro_cache_out"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# =============================================================================
# PARTE 1: Rprof macro -- pipeline real completo, mesmo padrao dos benchmarks
# anteriores (benchmark_empty_field_guard.R)
# =============================================================================

message("== PARTE 1: Rprof, pipeline real completo (geocode_core) ==")

prof_file <- file.path(out_dir, "rprof_full.out")
Rprof(prof_file, interval = 0.01)
invisible(geocodebr:::geocode_core(
  enderecos            = input_df,
  campos_endereco      = campos,
  resultado_completo   = FALSE,
  resolver_empates     = TRUE,
  resultado_sf         = FALSE,
  h3_res               = NULL,
  padronizar_enderecos = TRUE,
  verboso              = FALSE,
  cache                = TRUE,
  n_cores              = 7
))
Rprof(NULL)

prof_summary <- summaryRprof(prof_file)
saveRDS(prof_summary, file.path(out_dir, "prof_summary_full.rds"))

bt <- prof_summary$by.total
alvo <- bt[grepl(
  "calculate_string_dist|register_unique_logradouros_table|match_cases_probabilistic|match_weighted_cases_probabilistic|register_cnefe_table",
  rownames(bt)
), ]
message("-- tempo (by.total) em funcoes-alvo --")
print(alvo)
message(sprintf("Tempo total amostrado: %.2fs", prof_summary$sampling.time))

# =============================================================================
# PARTE 2: replica manual do pipeline (mesmas funcoes internas, mesma ordem),
# com instrumentacao de leitura ANTES de cada etapa probabilistica pn0k/pa0k
# =============================================================================

message("\n== PARTE 2: instrumentacao SQL por etapa (pn01/pa01/pn02/pa02/pn03/pa03) ==")

enderecos <- data.table::copy(input_df)
geocodebr:::check_clean_colnames(enderecos)

campos_endereco <- geocodebr:::assert_and_assign_address_fields(campos, enderecos)
missing_cols <- campos_endereco[unlist(lapply(campos_endereco, is.null))]
campos_nao_declarados <- names(missing_cols)

if (length(missing_cols) >= 1) {
  data.table::setDT(enderecos)
  new_colnames <- paste0(names(missing_cols), "tempgeocodebr")
  enderecos[, (new_colnames) := NA_character_]
  campos_endereco[sapply(campos_endereco, is.null)] <- as.list(new_colnames)
}

input_padrao <- enderecobr::padronizar_enderecos(
  enderecos = enderecos,
  campos_do_endereco = enderecobr::correspondencia_campos(
    logradouro = campos_endereco[["logradouro"]],
    numero     = campos_endereco[["numero"]],
    cep        = campos_endereco[["cep"]],
    bairro     = campos_endereco[["localidade"]],
    municipio  = campos_endereco[["municipio"]],
    estado     = campos_endereco[["estado"]]
  ),
  formato_estados = "sigla",
  formato_numeros = 'integer'
)

data.table::setDT(input_padrao)
cols_to_keep <- names(input_padrao)[names(input_padrao) %like% '_padr']
input_padrao <- input_padrao[, .SD, .SDcols = c(cols_to_keep)]
names(input_padrao) <- gsub("_padr", "", names(input_padrao))
if ('bairro' %in% names(input_padrao)) {
  data.table::setnames(input_padrao, old = 'bairro', new = 'localidade')
}

data.table::setDT(enderecos)[, tempidgeocodebr := 1:nrow(input_padrao)]
input_padrao[, tempidgeocodebr := 1:nrow(input_padrao)]
input_padrao[, temp_lograd_determ := NA_character_]
input_padrao[, similaridade_logradouro := NA_real_]

cnefe_dir <- geocodebr:::download_cnefe(tabela = 'todas', verboso = FALSE, cache = TRUE)

con <- geocodebr:::create_geocodebr_db(n_cores = 7)
message(sprintf("con valido apos create_geocodebr_db: %s", DBI::dbIsValid(con)))

input_padrao_arrw <- arrow::as_arrow_table(input_padrao)
DBI::dbWriteTableArrow(con, name = "input_padrao_db", input_padrao_arrw, overwrite = TRUE, temporary = TRUE)
message(sprintf("con valido apos dbWriteTableArrow: %s", DBI::dbIsValid(con)))

geocodebr:::cria_col_logradouro_confusao(con)
message(sprintf("con valido apos cria_col_logradouro_confusao: %s", DBI::dbIsValid(con)))

# output_db precisa existir pq os match_fun() reais fazem INSERT INTO nele
schema_output_db <- arrow::schema(
  tempidgeocodebr = arrow::int32(), lat = arrow::float16(), lon = arrow::float16(),
  endereco_encontrado = arrow::string(), logradouro_encontrado = arrow::string(),
  tipo_resultado = arrow::string(), contagem_cnefe = arrow::int32(),
  desvio_metros = arrow::int32(), log_causa_confusao = arrow::boolean(),
  similaridade_logradouro = arrow::float16()
)
output_db_arrow <- arrow::arrow_table(schema = schema_output_db)
DBI::dbWriteTableArrow(con, name = "output_db", output_db_arrow, overwrite = TRUE, temporary = TRUE)
message(sprintf("con valido apos criar output_db: %s", DBI::dbIsValid(con)))

resultado_completo <- FALSE
etapas_alvo <- c("pn01", "pa01", "pn02", "pa02", "pn03", "pa03")
instrumentacao <- list()

n_rows <- nrow(input_padrao)
matched_rows <- 0

for (match_type in geocodebr:::all_possible_match_types) {
  key_cols <- geocodebr:::get_key_cols(match_type)

  if (!(all(key_cols %in% names(input_padrao)) && !any(key_cols %in% campos_nao_declarados))) {
    next
  }

  if (match_type %in% etapas_alvo) {
    cols_not_null <- paste(
      glue::glue("input_padrao_db.{key_cols} IS NOT NULL"),
      collapse = ' AND '
    )

    n_pool <- as.integer(DBI::dbGetQuery(con, glue::glue(
      "SELECT COUNT(*) AS n FROM input_padrao_db
       WHERE similaridade_logradouro IS NULL
         AND log_causa_confusao = FALSE
         AND {cols_not_null};"
    ))$n)

    if (n_pool > 0) {
      unique_tbl <- geocodebr:::register_unique_logradouros_table(con, match_type, cnefe_dir)
      key_cols_string_dist <- key_cols[!key_cols %in% c("numero", "logradouro")]
      join_cond <- paste(
        glue::glue("{unique_tbl}.{key_cols_string_dist} = input_padrao_db.{key_cols_string_dist}"),
        collapse = ' AND '
      )

      pairs <- DBI::dbGetQuery(con, glue::glue(
        "SELECT DISTINCT
            input_padrao_db.logradouro AS logradouro_input,
            {unique_tbl}.logradouro AS logradouro_cnefe
         FROM input_padrao_db
         JOIN {unique_tbl} ON {join_cond}
         WHERE input_padrao_db.similaridade_logradouro IS NULL
           AND input_padrao_db.log_causa_confusao = FALSE
           AND {cols_not_null};"
      ))
    } else {
      pairs <- data.frame(logradouro_input = character(), logradouro_cnefe = character())
    }

    instrumentacao[[match_type]] <- list(
      n_pool = n_pool,
      n_pares = nrow(pairs),
      n_distinct_input = length(unique(pairs$logradouro_input)),
      pares = paste(pairs$logradouro_input, pairs$logradouro_cnefe, sep = "")
    )

    message(sprintf(
      "%s: pool=%d linhas | pares_a_computar=%d | strings_input_distintas=%d",
      match_type, n_pool, nrow(pairs), length(unique(pairs$logradouro_input))
    ))
  }

  if (!DBI::dbIsValid(con)) {
    stop(sprintf("conexao invalida ANTES de match_fun em match_type=%s", match_type))
  }

  match_fun <- geocodebr:::reference_match_fun_by_match_type(match_type)
  n_rows_affected <- match_fun(
    con,
    match_type = match_type,
    key_cols = key_cols,
    resultado_completo = resultado_completo,
    pasta_dados = cnefe_dir
  )
  matched_rows <- matched_rows + n_rows_affected
  message(sprintf("  -> %s: %d linhas casadas (con valido: %s)", match_type, n_rows_affected, DBI::dbIsValid(con)))

  if (matched_rows == n_rows) break
}

saveRDS(instrumentacao, file.path(out_dir, "instrumentacao.rds"))

# =============================================================================
# PARTE 3: analise -- quanto do trabalho de cada etapa seria cache hit se
# reaproveitassemos os pares (logradouro_input, logradouro_cnefe) ja
# computados nas etapas anteriores?
# =============================================================================

message("\n== PARTE 3: overlap de pares entre etapas consecutivas ==")

pares_ja_vistos <- character(0)
resumo <- data.frame()

for (match_type in etapas_alvo) {
  info <- instrumentacao[[match_type]]
  if (is.null(info) || info$n_pares == 0) {
    resumo <- rbind(resumo, data.frame(
      match_type = match_type, n_pool = if (is.null(info)) NA else info$n_pool,
      n_pares_totais = if (is.null(info)) 0 else info$n_pares,
      n_pares_ja_cacheados = 0, pct_cacheavel = NA,
      n_strings_input_distintas = if (is.null(info)) 0 else info$n_distinct_input,
      dedup_intra_etapa = NA
    ))
    next
  }

  pares_atuais <- info$pares
  n_cache_hit <- sum(pares_atuais %in% pares_ja_vistos)

  resumo <- rbind(resumo, data.frame(
    match_type = match_type,
    n_pool = info$n_pool,
    n_pares_totais = info$n_pares,
    n_pares_ja_cacheados = n_cache_hit,
    pct_cacheavel = round(100 * n_cache_hit / info$n_pares, 1),
    n_strings_input_distintas = info$n_distinct_input,
    dedup_intra_etapa = round(info$n_pool / max(info$n_distinct_input, 1), 1)
  ))

  # acumula pro cache "global" (cumulativo real, entre todas as etapas)
  pares_ja_vistos <- unique(c(pares_ja_vistos, pares_atuais))
}

print(resumo, row.names = FALSE)
saveRDS(resumo, file.path(out_dir, "resumo_overlap.rds"))
write.csv(resumo, file.path(out_dir, "resumo_overlap.csv"), row.names = FALSE)

message("\n== FIM ==")
