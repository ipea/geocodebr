# Usage: Rscript analyze_runs.R <runs_dir> <label1> <label2> ...
# Builds a comparison table across runs: total time, transport, child/parent/DuckDB peaks,
# per-block times (from the per-stage profile when available), and checksums.
args <- commandArgs(trailingOnly = TRUE)
runs_dir <- args[1]; labels <- args[-1]
nested <- c("register_cnefe_table", "register_unique_logradouros_table", "calculate_string_dist",
            "update_input_db", "dropa_tabelas_obsoletas",
            "padronizar_logradouros", "padronizar_numeros", "padronizar_ceps", "padronizar_bairros",
            "padronizar_municipios", "padronizar_estados")
matchfun <- c("match_cases", "match_cases_probabilistic", "match_weighted_cases",
              "match_weighted_cases_probabilistic")
rows <- list()
for (lb in labels) {
  sf <- file.path(runs_dir, paste0(lb, "_summary.csv"))
  if (!file.exists(sf)) { message("missing ", sf); next }
  s <- read.csv(sf, stringsAsFactors = FALSE)
  g <- function(nm, default = NA) if (nm %in% names(s)) s[[nm]] else default
  pf <- file.path(runs_dir, paste0(lb, "_prof.csv"))
  p <- if (file.exists(pf)) read.csv(pf, stringsAsFactors = FALSE) else NULL
  blk <- c(padroniza = NA, prep_r = NA, write_input = NA, loop = NA, jaro = NA, inserts = NA,
           register = NA, delete = NA, drops = NA, empates = NA, write_input_db = NA, merge = NA,
           duck_peak_mb = NA, duck_end_mb = NA)
  if (!is.null(p)) {
    sumf <- function(f) sum(p$secs[p$fun %in% f], na.rm = TRUE)
    top <- p[!p$fun %in% nested, ]; top <- top[order(top$t_start), ]
    gap <- function(after, before) {
      a <- top$t_end[top$fun == after]; b <- top$t_start[top$fun == before]
      if (length(a) && length(b)) min(b[b >= max(a)]) - max(a) else NA
    }
    blk["padroniza"] <- sumf(c("padronizar_enderecos", "padronizar_input"))
    if (!"padronizar_enderecos" %in% top$fun) blk["padroniza"] <- sumf(c("padronizar_logradouros", "padronizar_numeros", "padronizar_ceps", "padronizar_bairros", "padronizar_municipios", "padronizar_estados"))
    blk["prep_r"] <- gap("padronizar_enderecos", "download_cnefe")
    blk["write_input"] <- gap("create_geocodebr_db", "cria_col_logradouro_confusao")
    blk["loop"] <- sumf(matchfun)
    blk["jaro"] <- sumf("calculate_string_dist")
    blk["register"] <- sumf(c("register_cnefe_table", "register_unique_logradouros_table"))
    blk["delete"] <- sumf("update_input_db")
    blk["drops"] <- sumf("dropa_tabelas_obsoletas")
    blk["inserts"] <- blk["loop"] - blk["jaro"] - blk["register"] - blk["delete"]
    blk["empates"] <- sumf("trata_empates_geocode_duckdb")
    blk["write_input_db"] <- gap("trata_empates_geocode_duckdb", "add_precision_col")
    blk["merge"] <- sumf("merge_results_to_input")
    blk["duck_peak_mb"] <- max(p$duck_mem_mb, na.rm = TRUE)
    blk["duck_end_mb"] <- tail(p$duck_mem_mb[!is.na(p$duck_mem_mb)], 1)
  }
  child_peak <- if (!is.na(g("child_peak_wset_mb"))) g("child_peak_wset_mb") else g("child_peak_wset_poll_mb")
  rows[[lb]] <- data.frame(
    run = lb, mode = g("mode", "core"), total_s = round(s$t_total_callr, 1),
    child_core_s = round(s$t_child_core, 1), transport_s = round(s$t_transport_overhead, 1),
    child_peak_gb = round(child_peak / 1024, 1), parent_peak_gb = round(s$parent_peak_wset_mb / 1024, 1),
    duck_peak_gb = round(blk["duck_peak_mb"] / 1024, 1),
    padroniza = round(blk["padroniza"], 1), prep_r = round(blk["prep_r"], 1),
    write_input = round(blk["write_input"], 1), loop = round(blk["loop"], 1), jaro = round(blk["jaro"], 1),
    inserts = round(blk["inserts"], 1), register = round(blk["register"], 1), delete = round(blk["delete"], 1),
    empates = round(blk["empates"], 1), write_input_db = round(blk["write_input_db"], 1),
    merge = round(blk["merge"], 1),
    n_out = s$n_output, sum_lat = g("sum_lat"), sum_lon = g("sum_lon"), hash_end = g("hash_end"),
    stringsAsFactors = FALSE
  )
}
out <- do.call(rbind, rows); rownames(out) <- NULL
options(width = 250)
print(out[, c("run", "mode", "total_s", "child_core_s", "transport_s", "child_peak_gb", "parent_peak_gb", "duck_peak_gb")], row.names = FALSE)
cat("\n")
print(out[, c("run", "padroniza", "prep_r", "write_input", "loop", "jaro", "inserts", "register", "delete", "empates", "write_input_db", "merge")], row.names = FALSE)
cat("\n")
print(out[, c("run", "n_out", "sum_lat", "sum_lon", "hash_end")], row.names = FALSE, digits = 15)
write.csv(out, file.path(runs_dir, "comparison_table.csv"), row.names = FALSE)
