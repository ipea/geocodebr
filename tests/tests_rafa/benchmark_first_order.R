# Benchmark do item #3 de quality_reports/diagnoses/2026-08-24_geocode-eficiencia-consolidado.md:
# FIRST() sem ORDER BY em match_weighted_cases.R / match_weighted_cases_probabilistic.R
# (etapas da0x/pa0x) causa nao-determinismo entre execucoes. Fix: ORDER BY
# ABS(numero - numero_cnefe), numero_cnefe, lat, lon dentro de cada FIRST().
#
# CODE_TAG = "before" ou "after" -- so rotula os arquivos de saida; o estado do
# codigo tem que ser trocado manualmente entre as rodadas.

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

code_tag <- Sys.getenv("CODE_TAG", unset = "run")
out_dir <- "tests/tests_rafa/_benchmark_first_order_out"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

message(sprintf("== %s ==", code_tag))

roda <- function(n_cores) {
  geocodebr:::geocode_core(
    enderecos            = input_df,
    campos_endereco      = campos,
    resultado_completo   = TRUE,
    resolver_empates     = TRUE,
    resultado_sf         = FALSE,
    h3_res               = NULL,
    padronizar_enderecos = TRUE,
    verboso              = FALSE,
    cache                = TRUE,
    n_cores              = n_cores
  )
}

# ---------------------------------------------------------------------------
# A) reprodutibilidade: mesma chamada, duas vezes, n_cores = 7 (paralelo)
# ---------------------------------------------------------------------------
message("-- reprodutibilidade (n_cores = 7, duas chamadas identicas) --")

r1 <- suppressWarnings(roda(7))
r2 <- suppressWarnings(roda(7))
data.table::setDT(r1); data.table::setorder(r1, id)
data.table::setDT(r2); data.table::setorder(r2, id)

reprodutivel <- identical(r1, r2)
message(sprintf("identical(r1, r2): %s", reprodutivel))

if (!reprodutivel) {
  common_cols <- intersect(names(r1), names(r2))
  diffs <- Filter(function(cc) !isTRUE(all.equal(r1[[cc]], r2[[cc]])), common_cols)
  message("colunas diferentes entre r1 e r2: ", paste(diffs, collapse = ", "))
  n_diff <- sum(!mapply(isTRUE, Map(all.equal, r1$lat, r2$lat)))
  message(sprintf("linhas com lat diferente entre r1 e r2: %d de %d", n_diff, nrow(r1)))
}

# ---------------------------------------------------------------------------
# B) corretude para comparacao antes/depois: n_cores = 1, uma chamada
# ---------------------------------------------------------------------------
message("-- corretude p/ comparacao antes-depois (n_cores = 1) --")

res_correct <- suppressWarnings(roda(1))
data.table::setDT(res_correct)
data.table::setorder(res_correct, id)
saveRDS(res_correct, file.path(out_dir, paste0("correctness_", code_tag, ".rds")))
message(sprintf("nrow = %d | NA lat = %d", nrow(res_correct), sum(is.na(res_correct$lat))))

# ---------------------------------------------------------------------------
# C) tempo total (n_cores = 7, bench::mark)
# ---------------------------------------------------------------------------
message("-- tempo total (n_cores = 7, 5 iteracoes) --")

bm <- suppressWarnings(bench::mark(
  iterations = 5,
  check = FALSE,
  geocode_core = roda(7)
))
print(bm[, c("expression", "min", "median", "itr/sec", "mem_alloc", "n_itr", "n_gc", "total_time")])
saveRDS(bm, file.path(out_dir, paste0("timing_", code_tag, ".rds")))

message("== FIM ==")
