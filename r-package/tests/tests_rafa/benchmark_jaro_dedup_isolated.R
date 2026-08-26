# Medicao do ganho REAL do dedup intra-etapa em calculate_string_dist(),
# isolado (cache NAO sobrevive entre etapas -- ver critica adversarial em
# 2026-08-26: o design anterior reintroduzia o item #8, ja medido e
# refutado). Compara, em cada uma de pn01/pn02/pn03, a query atual (variante
# A, copia exata de R/string_dist.R) contra uma variante com dedup via
# tabela cache CRIADA E DESCARTADA dentro da mesma chamada (variante B) --
# nao usa CREATE TEMP TABLE IF NOT EXISTS reaproveitado entre etapas.
#
# Nao mexe em nenhum arquivo de R/. So mede.

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

out_dir <- "tests/tests_rafa/_benchmark_jaro_dedup_out"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

N_REPS <- 5

# =============================================================================
# Setup -- identico ao benchmark_jaro_cache_opportunity.R (mesma preparacao
# de input_padrao/con/output_db que geocode_core() faz)
# =============================================================================

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

input_padrao_arrw <- arrow::as_arrow_table(input_padrao)
DBI::dbWriteTableArrow(con, name = "input_padrao_db", input_padrao_arrw, overwrite = TRUE, temporary = TRUE)

geocodebr:::cria_col_logradouro_confusao(con)

schema_output_db <- arrow::schema(
  tempidgeocodebr = arrow::int32(), lat = arrow::float16(), lon = arrow::float16(),
  endereco_encontrado = arrow::string(), logradouro_encontrado = arrow::string(),
  tipo_resultado = arrow::string(), contagem_cnefe = arrow::int32(),
  desvio_metros = arrow::int32(), log_causa_confusao = arrow::boolean(),
  similaridade_logradouro = arrow::float16()
)
output_db_arrow <- arrow::arrow_table(schema = schema_output_db)
DBI::dbWriteTableArrow(con, name = "output_db", output_db_arrow, overwrite = TRUE, temporary = TRUE)

resultado_completo <- FALSE
etapas_alvo <- c("pn01", "pn02", "pn03")
resultados <- list()

n_rows <- nrow(input_padrao)
matched_rows <- 0

# =============================================================================
# Funcoes das duas variantes (copias isoladas -- nao tocam R/string_dist.R)
# =============================================================================

query_variant_a <- function(con, unique_tbl, join_cond, cols_not_null, min_cutoff) {
  q <- glue::glue(
    "
    WITH to_compute AS (
      SELECT
          input_padrao_db.tempidgeocodebr,
          input_padrao_db.logradouro AS logradouro_input,
          {unique_tbl}.logradouro AS logradouro_cnefe
      FROM input_padrao_db
      JOIN {unique_tbl} ON {join_cond}
      WHERE input_padrao_db.similaridade_logradouro IS NULL
        AND input_padrao_db.log_causa_confusao = FALSE
        AND {cols_not_null}
        ),
    computed AS (
      SELECT
          tempidgeocodebr,
          logradouro_cnefe,
          CAST(jaro_similarity(logradouro_input, logradouro_cnefe) AS NUMERIC(5,3)) AS similarity,
          RANK() OVER (PARTITION BY tempidgeocodebr ORDER BY similarity DESC, logradouro_cnefe) AS rank
      FROM to_compute
      WHERE similarity > {min_cutoff}
      )
    UPDATE input_padrao_db
      SET temp_lograd_determ = computed.logradouro_cnefe,
          similaridade_logradouro = computed.similarity
      FROM computed
      WHERE input_padrao_db.tempidgeocodebr = computed.tempidgeocodebr
            AND computed.rank = 1;"
  )
  DBI::dbExecute(con, q)
}

query_variant_b <- function(con, unique_tbl, join_cond, cols_not_null, min_cutoff) {
  DBI::dbExecute(con, "DROP TABLE IF EXISTS jaro_pair_cache_temp;")
  DBI::dbExecute(con, "
    CREATE TEMP TABLE jaro_pair_cache_temp (
      logradouro_input VARCHAR,
      logradouro_cnefe VARCHAR,
      similarity NUMERIC(5,3),
      UNIQUE(logradouro_input, logradouro_cnefe)
    );")

  q_insert <- glue::glue(
    "
    INSERT INTO jaro_pair_cache_temp
    SELECT DISTINCT
        logradouro_input,
        logradouro_cnefe,
        CAST(jaro_similarity(logradouro_input, logradouro_cnefe) AS NUMERIC(5,3)) AS similarity
    FROM (
        SELECT
            input_padrao_db.logradouro AS logradouro_input,
            {unique_tbl}.logradouro AS logradouro_cnefe
        FROM input_padrao_db
        JOIN {unique_tbl} ON {join_cond}
        WHERE input_padrao_db.similaridade_logradouro IS NULL
          AND input_padrao_db.log_causa_confusao = FALSE
          AND {cols_not_null}
          AND {unique_tbl}.logradouro IS NOT NULL
    ) to_compute
    ON CONFLICT DO NOTHING;"
  )
  DBI::dbExecute(con, q_insert)

  q_update <- glue::glue(
    "
    WITH to_compute AS (
      SELECT
          input_padrao_db.tempidgeocodebr,
          input_padrao_db.logradouro AS logradouro_input,
          {unique_tbl}.logradouro AS logradouro_cnefe
      FROM input_padrao_db
      JOIN {unique_tbl} ON {join_cond}
      WHERE input_padrao_db.similaridade_logradouro IS NULL
        AND input_padrao_db.log_causa_confusao = FALSE
        AND {cols_not_null}
        ),
    computed AS (
      SELECT
          to_compute.tempidgeocodebr,
          to_compute.logradouro_cnefe,
          jaro_pair_cache_temp.similarity AS similarity,
          RANK() OVER (
            PARTITION BY to_compute.tempidgeocodebr
            ORDER BY jaro_pair_cache_temp.similarity DESC, to_compute.logradouro_cnefe
          ) AS rank
      FROM to_compute
      JOIN jaro_pair_cache_temp
        ON jaro_pair_cache_temp.logradouro_input = to_compute.logradouro_input
       AND jaro_pair_cache_temp.logradouro_cnefe = to_compute.logradouro_cnefe
      WHERE jaro_pair_cache_temp.similarity > {min_cutoff}
      )
    UPDATE input_padrao_db
      SET temp_lograd_determ = computed.logradouro_cnefe,
          similaridade_logradouro = computed.similarity
      FROM computed
      WHERE input_padrao_db.tempidgeocodebr = computed.tempidgeocodebr
            AND computed.rank = 1;"
  )
  DBI::dbExecute(con, q_update)
  DBI::dbExecute(con, "DROP TABLE jaro_pair_cache_temp;")
}

snapshot_cols <- function(con) {
  DBI::dbGetQuery(con, "SELECT tempidgeocodebr, temp_lograd_determ, similaridade_logradouro FROM input_padrao_db;")
}

restore_cols <- function(con, snap) {
  DBI::dbWriteTable(con, "snap_restore_tmp", snap, temporary = TRUE, overwrite = TRUE)
  DBI::dbExecute(con, "
    UPDATE input_padrao_db
       SET temp_lograd_determ = snap_restore_tmp.temp_lograd_determ,
           similaridade_logradouro = snap_restore_tmp.similaridade_logradouro
      FROM snap_restore_tmp
     WHERE input_padrao_db.tempidgeocodebr = snap_restore_tmp.tempidgeocodebr;")
  DBI::dbExecute(con, "DROP TABLE snap_restore_tmp;")
}

# =============================================================================
# Laco principal
# =============================================================================

for (match_type in geocodebr:::all_possible_match_types) {
  key_cols <- geocodebr:::get_key_cols(match_type)

  if (!(all(key_cols %in% names(input_padrao)) && !any(key_cols %in% campos_nao_declarados))) {
    next
  }

  if (match_type %in% etapas_alvo) {
    cols_not_null <- paste(glue::glue("input_padrao_db.{key_cols} IS NOT NULL"), collapse = ' AND ')
    unique_tbl <- geocodebr:::register_unique_logradouros_table(con, match_type, cnefe_dir)
    key_cols_string_dist <- key_cols[!key_cols %in% c("numero", "logradouro")]
    join_cond <- paste(
      glue::glue("{unique_tbl}.{key_cols_string_dist} = input_padrao_db.{key_cols_string_dist}"),
      collapse = ' AND '
    )
    min_cutoff <- geocodebr:::get_prob_match_cutoff(match_type)

    snap <- snapshot_cols(con)
    n_pool <- sum(is.na(snap$similaridade_logradouro))
    message(sprintf("\n== %s == (pool = %d linhas)", match_type, n_pool))

    # --- timing variante A (codigo atual) ---
    t_a <- numeric(N_REPS)
    for (i in seq_len(N_REPS)) {
      restore_cols(con, snap)
      t0 <- proc.time()[["elapsed"]]
      query_variant_a(con, unique_tbl, join_cond, cols_not_null, min_cutoff)
      t_a[i] <- proc.time()[["elapsed"]] - t0
    }
    res_a <- DBI::dbGetQuery(con, "SELECT tempidgeocodebr, temp_lograd_determ, similaridade_logradouro FROM input_padrao_db WHERE similaridade_logradouro IS NOT NULL ORDER BY tempidgeocodebr;")

    # --- timing variante B (dedup, escopado so a essa chamada) ---
    t_b <- numeric(N_REPS)
    for (i in seq_len(N_REPS)) {
      restore_cols(con, snap)
      t0 <- proc.time()[["elapsed"]]
      query_variant_b(con, unique_tbl, join_cond, cols_not_null, min_cutoff)
      t_b[i] <- proc.time()[["elapsed"]] - t0
    }
    res_b <- DBI::dbGetQuery(con, "SELECT tempidgeocodebr, temp_lograd_determ, similaridade_logradouro FROM input_padrao_db WHERE similaridade_logradouro IS NOT NULL ORDER BY tempidgeocodebr;")

    identico <- isTRUE(all.equal(res_a, res_b, tolerance = 1e-6))

    message(sprintf(
      "  variante A (atual):  mediana=%.3fs  (reps: %s)",
      median(t_a), paste(round(t_a, 3), collapse = ", ")
    ))
    message(sprintf(
      "  variante B (dedup):  mediana=%.3fs  (reps: %s)",
      median(t_b), paste(round(t_b, 3), collapse = ", ")
    ))
    message(sprintf(
      "  ganho: %.1f%% | resultado identico: %s",
      100 * (median(t_a) - median(t_b)) / median(t_a), identico
    ))

    resultados[[match_type]] <- list(
      n_pool = n_pool, t_a = t_a, t_b = t_b, identico = identico
    )

    # deixa o estado real (variante A = producao) antes de seguir o laco
    restore_cols(con, snap)
    query_variant_a(con, unique_tbl, join_cond, cols_not_null, min_cutoff)
  }

  match_fun <- geocodebr:::reference_match_fun_by_match_type(match_type)
  n_rows_affected <- match_fun(
    con, match_type = match_type, key_cols = key_cols,
    resultado_completo = resultado_completo, pasta_dados = cnefe_dir
  )
  matched_rows <- matched_rows + n_rows_affected
  if (matched_rows == n_rows) break
}

saveRDS(resultados, file.path(out_dir, "resultados_isolado.rds"))

message("\n== RESUMO ==")
resumo <- do.call(rbind, lapply(names(resultados), function(mt) {
  r <- resultados[[mt]]
  data.frame(
    match_type = mt, n_pool = r$n_pool,
    mediana_a_s = round(median(r$t_a), 3),
    mediana_b_s = round(median(r$t_b), 3),
    ganho_pct = round(100 * (median(r$t_a) - median(r$t_b)) / median(r$t_a), 1),
    identico = r$identico
  )
}))
print(resumo, row.names = FALSE)
write.csv(resumo, file.path(out_dir, "resumo_isolado.csv"), row.names = FALSE)

message("\n== FIM ==")

if (DBI::dbIsValid(con)) duckdb::dbDisconnect(con)
