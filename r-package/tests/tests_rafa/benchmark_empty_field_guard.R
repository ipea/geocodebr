# Benchmark antes/depois da correcao do item #1 de
# quality_reports/diagnoses/2026-08-24_geocode-eficiencia-consolidado.md:
# o guarda do laco em geocode.R agora pula match_types cujo key_cols inclui
# um campo que o usuario nao declarou (campos_nao_declarados), em vez de so
# checar presenca da coluna-fantasma.
#
# Uso:
#   SCENARIO  = "full" (todos os 6 campos) ou "cep_only" (sem logradouro/numero)
#   CODE_TAG  = "before" ou "after" -- so rotula os arquivos de saida, nao
#               muda nada no codigo; o estado do codigo tem que ser trocado
#               manualmente (git checkout / reaplicar o diff) entre as rodadas.

devtools::load_all('.')

data_path <- system.file("extdata/large_sample.parquet", package = "geocodebr")
input_df  <- arrow::read_parquet(data_path)

scenario <- Sys.getenv("SCENARIO", unset = "full")
code_tag <- Sys.getenv("CODE_TAG", unset = "run")
tag <- paste(scenario, code_tag, sep = "_")

campos <- if (scenario == "cep_only") {
  geocodebr::definir_campos(
    cep        = 'cep',
    localidade = 'bairro',
    municipio  = 'municipio',
    estado     = 'uf'
  )
} else {
  geocodebr::definir_campos(
    logradouro = 'logradouro',
    numero     = 'numero',
    localidade = 'bairro',
    cep        = 'cep',
    municipio  = 'municipio',
    estado     = 'uf'
  )
}

out_dir <- "tests/tests_rafa/_benchmark_guard_out"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

message(sprintf("== %s ==", tag))

# ---------------------------------------------------------------------------
# 1) Rodada de corretude (n_cores = 1, deterministico)
# ---------------------------------------------------------------------------
message("-- corretude (n_cores = 1) --")

res_correct <- geocodebr:::geocode_core(
  enderecos            = input_df,
  campos_endereco      = campos,
  resultado_completo   = FALSE,
  resolver_empates     = TRUE,
  resultado_sf         = FALSE,
  h3_res               = NULL,
  padronizar_enderecos = TRUE,
  verboso              = FALSE,
  cache                = TRUE,
  n_cores              = 1
)
data.table::setDT(res_correct)
data.table::setorder(res_correct, id)
saveRDS(res_correct, file.path(out_dir, paste0("correctness_", tag, ".rds")))

message(sprintf("nrow = %d | NA lat = %d", nrow(res_correct), sum(is.na(res_correct$lat))))
print(table(res_correct$tipo_resultado, useNA = "ifany"))

# ---------------------------------------------------------------------------
# 2) Rodada de tempo total (n_cores = 7, bench::mark)
# ---------------------------------------------------------------------------
message("-- tempo total (n_cores = 7, 5 iteracoes) --")

bm <- bench::mark(
  iterations = 5,
  check = FALSE,
  geocode_core = geocodebr:::geocode_core(
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
  )
)
print(bm[, c("expression", "min", "median", "itr/sec", "mem_alloc", "n_itr", "n_gc", "total_time")])
saveRDS(bm, file.path(out_dir, paste0("timing_", tag, ".rds")))

# ---------------------------------------------------------------------------
# 3) Tempo por fase via Rprof (n_cores = 7)
# ---------------------------------------------------------------------------
message("-- profiling (Rprof), n_cores = 7 --")

prof_file <- file.path(out_dir, paste0("rprof_", tag, ".out"))
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
saveRDS(prof_summary, file.path(out_dir, paste0("prof_summary_", tag, ".rds")))

bt <- prof_summary$by.total
alvo <- bt[grepl("register_cnefe_table|calculate_string_dist", rownames(bt)), ]
message("-- tempo (by.total) em funcoes-alvo --")
print(alvo)
message(sprintf("Tempo total amostrado: %.2fs", prof_summary$sampling.time))
message("== FIM ==")
