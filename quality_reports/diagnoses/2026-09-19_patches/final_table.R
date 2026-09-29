# Builds the final per-patch table: for each patch, the metric it targets (stage seconds or GB)
# vs the median of the warm core-mode baselines, plus total wall time and peaks.
# Usage: Rscript final_table.R <runs_dir>
runs_dir <- commandArgs(trailingOnly = TRUE)[1]
ct <- read.csv(file.path(runs_dir, "comparison_table.csv"), stringsAsFactors = FALSE)
get <- function(run) ct[ct$run == run, ]
base <- ct[ct$run %in% c("base43M_r2", "base43M_r3", "base43M_r4"), ]
med <- function(col) median(base[[col]], na.rm = TRUE)
rng <- function(col) sprintf("%.0f-%.0f", min(base[[col]], na.rm = TRUE), max(base[[col]], na.rm = TRUE))
fmt <- function(b, v, unit = "s") sprintf("%.1f -> %.1f %s (%+.0f%%)", b, v, unit, 100 * (v - b) / b)

rows <- list(
  list(id = "P1", run = "p01_43M", desc = "Jaro: pular linhas com numero nas etapas pl0k", metric = "jaro", unit = "s"),
  list(id = "P2", run = "p02_43M", desc = "Jaro: DISTINCT nos candidatos (chave usada)", metric = "jaro", unit = "s"),
  list(id = "P8", run = "p08_43M", desc = "Jaro: dedup do input + FIRST/MAX no lugar de RANK (inclui P2)", metric = "jaro", unit = "s"),
  list(id = "P5", run = "p05_43M", desc = "Padronizar por campo sobre unique() + chmatch()", metric = "padroniza", unit = "s"),
  list(id = "P6", run = "p06_43M", desc = "GROUP BY estreito nas queries ponderadas (regex 1x por grupo)", metric = "inserts", unit = "s"),
  list(id = "P3", run = "p03_43M", desc = "duckdb_register() zero-copia para input_db", metric = "write_input_db", unit = "s"),
  list(id = "P4", run = "p04_43M", desc = "DELETE so dos ids da etapa corrente", metric = "delete", unit = "s"),
  list(id = "P9-12", run = "mem_43M", desc = "Bundle memoria: DROP apos ultimo uso + rm() no R + projecao de colunas + schema", metric = "child_peak_gb", unit = "GB")
)
cat(sprintf("Baselines quentes (core): total %s s (mediana %.0f); jaro %s; inserts %s; register %s; padroniza %s; merge %s; child peak %s GB\n\n",
            rng("total_s"), med("total_s"), rng("jaro"), rng("inserts"), rng("register"), rng("padroniza"), rng("merge"), rng("child_peak_gb")))
cat("| # | Acao | Metrica-alvo (mediana base -> patch) | Total 43,9M (s) | Pico filho (GB) | Pico DuckDB (GB) |\n|---|---|---|---|---|---|\n")
for (r in rows) {
  v <- get(r$run); if (nrow(v) == 0) next
  cat(sprintf("| %s | %s | %s: %s | %.0f (base %.0f) | %.1f (base %.1f) | %.1f (base %.1f) |\n",
              r$id, r$desc, r$metric, fmt(med(r$metric), v[[r$metric]], r$unit),
              v$total_s, med("total_s"), v$child_peak_gb, med("child_peak_gb"), v$duck_peak_gb, med("duck_peak_gb")))
}
cat("\nModo geocode() real:\n")
for (run in c("base43M_geo", "p07_43M_geo", "cum_43M_geo", "cum2_43M_geo")) {
  v <- get(run); if (nrow(v) == 0) next
  cat(sprintf("| %s | total %.0f s | pico filho %.1f GB | pico pai %.1f GB |\n", run, v$total_s, v$child_peak_gb, v$parent_peak_gb))
}
cat("\nCumulativo instrumentado (core):\n")
v <- get("cum_43M_core")
if (nrow(v)) {
  cols <- c("padroniza", "prep_r", "write_input", "loop", "jaro", "inserts", "register", "delete", "empates", "write_input_db", "merge")
  for (cn in cols) cat(sprintf("  %-15s %7.1f -> %7.1f s\n", cn, med(cn), v[[cn]]))
}
