# Profiling harness for geocodebr::geocode()
# Usage: Rscript prof_geocode.R --lib=<libpath> --data=<parquet> --label=<label>
#        [--n=all] [--out=<dir>] [--completo=FALSE] [--ncores=NULL] [--empates=TRUE] [--save=TRUE]
#        [--mode=core|geocode]
#
# mode=core (default): mirrors geocode() -- a callr child loads the INSTALLED package from
#   <libpath> and runs geocode_core(); every internal stage is wrapped with timers, DuckDB memory
#   probes (duckdb_memory(), PRAGMA database_size) and process working-set probes (ps).
# mode=geocode: calls the exported geocode() as a user would (no per-stage instrumentation);
#   child peak memory comes from an external poller that samples all R processes every second.
args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(name, default = NULL) {
  hit <- grep(paste0("^--", name, "="), args, value = TRUE)
  if (length(hit) == 0) return(default)
  sub(paste0("^--", name, "="), "", hit[1])
}
libpath   <- get_arg("lib")
data_path <- get_arg("data")
label     <- get_arg("label", "run")
n_rows    <- get_arg("n", "all")
out_dir   <- get_arg("out", "runs")
completo  <- as.logical(get_arg("completo", "FALSE"))
empates   <- as.logical(get_arg("empates", "TRUE"))
ncores    <- get_arg("ncores", "NULL"); ncores <- if (ncores == "NULL") NULL else as.integer(ncores)
save_result <- as.logical(get_arg("save", "TRUE"))
mode      <- get_arg("mode", "core")

.libPaths(c(libpath, .libPaths()))
suppressPackageStartupMessages({ library(geocodebr); library(arrow) })
cat(sprintf("[harness] geocodebr %s from %s | mode=%s\n", packageVersion("geocodebr"), find.package("geocodebr"), mode))
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

t_read0 <- proc.time()[["elapsed"]]
df <- arrow::read_parquet(data_path, as_data_frame = TRUE)
if (n_rows != "all") df <- df[seq_len(as.integer(n_rows)), ]
df <- as.data.frame(df)
t_read <- proc.time()[["elapsed"]] - t_read0
cat(sprintf("[harness] input: %d rows x %d cols, read in %.1fs\n", nrow(df), ncol(df), t_read))

campos <- geocodebr::definir_campos(
  logradouro = "logradouro", numero = "numero", cep = "cep",
  localidade = "bairro", municipio = "code_muni", estado = "abbrev_state"
)

# ---- external memory poller: samples every R process other than this one ---------------------
poll_file <- file.path(out_dir, paste0(label, "_mempoll.csv"))
poller_code <- sprintf('
  me <- %d; out <- "%s"; peak <- list(); t0 <- Sys.time()
  repeat {
    ps <- tryCatch(ps::ps(), error = function(e) NULL)
    if (!is.null(ps)) {
      ps <- ps[grepl("^(Rscript|R|Rterm)(\\\\.exe)?$", ps$name) & ps$pid != me & ps$pid != Sys.getpid(), ]
      for (i in seq_len(nrow(ps))) {
        w <- tryCatch(ps::ps_memory_info(ps$ps_handle[[i]])[["wset"]], error = function(e) NA)
        if (!is.na(w)) { k <- as.character(ps$pid[i]); peak[[k]] <- max(peak[[k]] %%||%% 0, w) }
      }
      if (length(peak)) {
        d <- data.frame(pid = names(peak), peak_wset_mb = unlist(peak) / 2^20)
        try(write.csv(d, out, row.names = FALSE), silent = TRUE)
      }
    }
    Sys.sleep(1)
  }', Sys.getpid(), gsub("\\\\", "/", poll_file))
`%||%` <- function(a, b) if (is.null(a)) b else a
poller <- processx::process$new("Rscript", c("-e", poller_code), stdout = "|", stderr = "|")

parent_mem0 <- ps::ps_memory_info()
t_call0 <- proc.time()[["elapsed"]]
wall0 <- Sys.time()

child_fun <- function(libpath, enderecos, campos_endereco, resultado_completo,
                      resolver_empates, n_cores) {
  .libPaths(c(libpath, .libPaths()))
  t_child0 <- proc.time()[["elapsed"]]
  library(geocodebr, lib.loc = libpath)
  ns <- asNamespace("geocodebr")
  ns_end <- asNamespace("enderecobr")

  prof <- new.env()
  prof$rows <- list()
  prof$current_mt <- NA_character_
  prof$t0 <- t_child0

  duck_probe <- function(con) {
    out <- c(duck_mem_mb = NA_real_, duck_tmp_mb = NA_real_, db_file_mb = NA_real_)
    if (is.null(con) || !inherits(con, "DBIConnection")) return(out)
    tryCatch({
      m <- DBI::dbGetQuery(con, "SELECT COALESCE(SUM(memory_usage_bytes),0) AS m, COALESCE(SUM(temporary_storage_bytes),0) AS t FROM duckdb_memory()")
      d <- DBI::dbGetQuery(con, "PRAGMA database_size")
      db_mb <- tryCatch(as.numeric(d$total_blocks[1]) * as.numeric(d$block_size[1]) / 2^20,
                        error = function(e) NA_real_)
      out <- c(duck_mem_mb = as.numeric(m$m) / 2^20, duck_tmp_mb = as.numeric(m$t) / 2^20, db_file_mb = db_mb)
    }, error = function(e) NULL)
    out
  }

  record <- function(fun, lbl, t_start, t_end, con = NULL) {
    pm <- ps::ps_memory_info()
    dp <- duck_probe(con)
    prof$rows[[length(prof$rows) + 1]] <- data.frame(
      fun = fun, label = lbl, match_type = prof$current_mt,
      t_start = t_start - prof$t0, t_end = t_end - prof$t0, secs = t_end - t_start,
      wset_mb = pm[["wset"]] / 2^20, peak_wset_mb = pm[["peak_wset"]] / 2^20,
      duck_mem_mb = dp[["duck_mem_mb"]], duck_tmp_mb = dp[["duck_tmp_mb"]], db_file_mb = dp[["db_file_mb"]],
      stringsAsFactors = FALSE
    )
  }

  wrap <- function(fname, ns, label_fun = function(a) NA_character_, sets_mt = FALSE, con_pos = 1) {
    if (!exists(fname, envir = ns, inherits = FALSE)) return(invisible(NULL))
    f <- get(fname, envir = ns)
    w <- function(...) {
      a <- list(...)
      lbl <- tryCatch(label_fun(a), error = function(e) NA_character_)
      if (sets_mt) prof$current_mt <- lbl
      con <- if (!is.na(con_pos) && length(a) >= con_pos) a[[con_pos]] else NULL
      t0 <- proc.time()[["elapsed"]]
      r <- f(...)
      t1 <- proc.time()[["elapsed"]]
      record(fname, lbl, t0, t1, con)
      r
    }
    unlockBinding(fname, ns); assign(fname, w, envir = ns); lockBinding(fname, ns)
    invisible(NULL)
  }
  mt_lab <- function(a) {
    if (!is.null(a[["match_type"]])) return(as.character(a[["match_type"]]))
    if (length(a) >= 2 && is.character(a[[2]])) return(as.character(a[[2]]))
    NA_character_
  }
  for (fn in c("match_cases", "match_cases_probabilistic", "match_weighted_cases",
               "match_weighted_cases_probabilistic"))
    wrap(fn, ns, mt_lab, sets_mt = TRUE, con_pos = 1)
  for (fn in c("register_cnefe_table", "register_unique_logradouros_table", "calculate_string_dist"))
    wrap(fn, ns, mt_lab, con_pos = 1)
  wrap("update_input_db", ns, con_pos = 1)
  wrap("cria_col_logradouro_confusao", ns, con_pos = 1)
  wrap("trata_empates_geocode_duckdb", ns, con_pos = 1)
  wrap("add_precision_col", ns, con_pos = 1)
  wrap("merge_results_to_input", ns, con_pos = 1)
  wrap("dropa_tabelas_obsoletas", ns, con_pos = 1)
  wrap("download_cnefe", ns, con_pos = NA)
  wrap("create_geocodebr_db", ns, con_pos = NA)
  wrap("padronizar_input", ns, con_pos = NA)
  for (fn in c("padronizar_enderecos", "padronizar_logradouros", "padronizar_numeros",
               "padronizar_ceps", "padronizar_bairros", "padronizar_municipios", "padronizar_estados"))
    wrap(fn, ns_end, con_pos = NA)

  t_core0 <- proc.time()[["elapsed"]]
  out <- geocodebr:::geocode_core(
    enderecos = enderecos, campos_endereco = campos_endereco,
    resultado_completo = resultado_completo, resolver_empates = resolver_empates,
    resultado_sf = FALSE, h3_res = NULL, padronizar_enderecos = TRUE,
    verboso = TRUE, cache = TRUE, n_cores = n_cores
  )
  t_core1 <- proc.time()[["elapsed"]]
  pm <- ps::ps_memory_info()
  prof_df <- do.call(rbind, prof$rows)
  list(
    result = out,
    prof = prof_df,
    child = c(t_core_start = t_core0 - t_child0, t_core = t_core1 - t_core0,
              t_after_core = proc.time()[["elapsed"]] - t_child0,
              child_peak_wset_mb = pm[["peak_wset"]] / 2^20,
              child_wset_end_mb = pm[["wset"]] / 2^20),
    duckdb_version = as.character(packageVersion("duckdb"))
  )
}

if (mode == "core") {
  res <- callr::r(
    func = child_fun,
    args = list(libpath = libpath, enderecos = df, campos_endereco = campos,
                resultado_completo = completo, resolver_empates = empates, n_cores = ncores),
    show = TRUE, package = FALSE
  )
  result <- res$result
} else {
  result <- geocodebr::geocode(
    enderecos = df, campos_endereco = campos,
    resultado_completo = completo, resolver_empates = empates,
    resultado_sf = FALSE, h3_res = NULL, padronizar_enderecos = TRUE,
    verboso = TRUE, cache = TRUE, n_cores = ncores
  )
  res <- list(result = result, prof = NULL,
              child = c(t_core_start = NA, t_core = NA, t_after_core = NA,
                        child_peak_wset_mb = NA, child_wset_end_mb = NA),
              duckdb_version = as.character(packageVersion("duckdb")))
}
t_call <- proc.time()[["elapsed"]] - t_call0
parent_mem1 <- ps::ps_memory_info()
Sys.sleep(1.5)
poller$kill()
poll <- tryCatch(read.csv(poll_file), error = function(e) NULL)
poll_peak <- if (!is.null(poll) && nrow(poll)) max(poll$peak_wset_mb) else NA_real_

is_df <- is.data.frame(result)
# checksums baratos para comparar corridas grandes sem gravar o resultado
chk <- if (is_df) c(
  n_na_lat = sum(is.na(result$lat)),
  sum_lat = sum(result$lat, na.rm = TRUE), sum_lon = sum(result$lon, na.rm = TRUE),
  sum_desvio = sum(as.numeric(result$desvio_metros), na.rm = TRUE),
  n_tipos = length(unique(result$tipo_resultado)),
  hash_end = sum(as.numeric(nchar(result$endereco_encontrado)), na.rm = TRUE)
) else c(n_na_lat = NA, sum_lat = NA, sum_lon = NA, sum_desvio = NA, n_tipos = NA, hash_end = NA)
prof <- res$prof
if (!is.null(prof)) prof$run <- label
child <- res$child
summary_row <- data.frame(
  label = label, mode = mode, n_input = nrow(df), n_output = if (is_df) nrow(result) else NA,
  t_total_callr = t_call,
  t_child_core = unname(child["t_core"]),
  t_child_startup = unname(child["t_core_start"]),
  t_transport_overhead = t_call - unname(child["t_after_core"]),
  child_peak_wset_mb = unname(child["child_peak_wset_mb"]),
  child_peak_wset_poll_mb = poll_peak,
  parent_peak_wset_mb = parent_mem1[["peak_wset"]] / 2^20,
  parent_wset_before_mb = parent_mem0[["wset"]] / 2^20,
  parent_wset_after_mb = parent_mem1[["wset"]] / 2^20,
  result_size_mb = if (is_df) as.numeric(object.size(result)) / 2^20 else NA,
  duckdb = res$duckdb_version,
  started = format(wall0, "%Y-%m-%d %H:%M:%S"),
  n_na_lat = unname(chk["n_na_lat"]), sum_lat = unname(chk["sum_lat"]), sum_lon = unname(chk["sum_lon"]),
  sum_desvio = unname(chk["sum_desvio"]), n_tipos = unname(chk["n_tipos"]), hash_end = unname(chk["hash_end"]),
  stringsAsFactors = FALSE
)
if (!is.null(prof)) write.csv(prof, file.path(out_dir, paste0(label, "_prof.csv")), row.names = FALSE)
write.csv(summary_row, file.path(out_dir, paste0(label, "_summary.csv")), row.names = FALSE)
if (is_df && save_result) arrow::write_parquet(result, file.path(out_dir, paste0(label, "_result.parquet")))
if (is_df) {
  tab <- as.data.frame(table(tipo_resultado = result$tipo_resultado, useNA = "ifany"))
  write.csv(tab, file.path(out_dir, paste0(label, "_tipos.csv")), row.names = FALSE)
}

cat("\n[harness] ===== SUMMARY", label, "=====\n")
print(summary_row, row.names = FALSE)
if (!is.null(prof)) {
  cat("\n[harness] per-function totals (secs):\n")
  agg <- aggregate(secs ~ fun, data = prof, FUN = sum)
  agg <- agg[order(-agg$secs), ]
  print(agg, row.names = FALSE)
  cat("\n[harness] per match_type (top-level match fn):\n")
  mt <- prof[prof$fun %in% c("match_cases", "match_cases_probabilistic", "match_weighted_cases",
                             "match_weighted_cases_probabilistic"),
             c("match_type", "fun", "secs", "duck_mem_mb", "duck_tmp_mb", "wset_mb")]
  print(mt, row.names = FALSE, digits = 4)
}
cat("\n[harness] DONE\n")
