# Benchmark ad hoc: CREATE TEMP TABLE vs CREATE TEMP VIEW em register_cnefe_table()
#
# Roda geocode_core() diretamente (NAO geocode(), que usa callr::r(package = TRUE) e carregaria a
# versao instalada do pacote, nao o source modificado em dev - ver [LEARN:testes] em MEMORY.md).
#
# Uso:
#   1. Rodar este script no estado atual do codigo (baseline), guardar o output (ou renomear).
#   2. Aplicar a mudanca TEMP TABLE -> TEMP VIEW em R/register_cnefe_tables.R.
#   3. Rodar de novo, comparar.

devtools::load_all('.')

data_path <- system.file("extdata/large_sample.parquet", package = "geocodebr")
input_df  <- arrow::read_parquet(data_path)

campos <- geocodebr::definir_campos(
  logradouro = 'logradouro',
  numero     = 'numero',
  localidade = 'bairro',
  cep        = 'cep',
  municipio  = 'municipio',
  estado     = 'uf'
)

out_dir <- "tests/tests_rafa/_benchmark_temp_view_out"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

tag <- Sys.getenv("BENCH_TAG", unset = "run")

# ---------------------------------------------------------------------------
# 1) Rodada de corretude (n_cores = 1, deterministico)
# ---------------------------------------------------------------------------
message("== Rodada de corretude (n_cores = 1) ==")

resultado_corretude <- geocodebr:::geocode_core(
  enderecos            = input_df,
  campos_endereco      = campos,
  resultado_completo   = TRUE,
  resolver_empates     = TRUE,
  resultado_sf         = FALSE,
  h3_res               = NULL,
  padronizar_enderecos = TRUE,
  verboso              = FALSE,
  cache                = TRUE,
  n_cores              = 1
)

data.table::setDT(resultado_corretude)
data.table::setorder(resultado_corretude, id)

saveRDS(
  resultado_corretude,
  file.path(out_dir, paste0("correctness_", tag, ".rds"))
)

message(sprintf("nrow = %d | NA lat = %d", nrow(resultado_corretude), sum(is.na(resultado_corretude$lat))))
print(table(resultado_corretude$tipo_resultado, useNA = "ifany"))

# ---------------------------------------------------------------------------
# 2) Rodada de tempo total (n_cores = 7, bench::mark)
# ---------------------------------------------------------------------------
message("== Rodada de tempo (n_cores = 7, 5 iteracoes) ==")

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
# 3) Tempo por fase via Rprof (isolar register_cnefe_table)
# ---------------------------------------------------------------------------
message("== Profiling (Rprof) de uma chamada, n_cores = 7 ==")

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

by_total <- prof_summary$by.total
alvo <- by_total[grepl("register_cnefe_table|register_unique_logradouros_table", rownames(by_total)), ]
message("-- tempo (by.total) em funcoes de registro de tabela --")
print(alvo)

message(sprintf("Tempo total amostrado pelo Rprof: %.2fs", prof_summary$sampling.time))

message("== FIM ==")
