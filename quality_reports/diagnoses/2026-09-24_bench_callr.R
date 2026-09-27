# Uso: Rterm --vanilla --no-echo -f bench_callr.R --args <modo> <rodadas> <rotulo> <saida.csv> [n_cores]
# modo: inproc (geocode_core no proprio processo) | callr (geocode(), subprocesso)
args <- commandArgs(trailingOnly = TRUE)
modo <- args[1]; rodadas <- as.integer(args[2]); rotulo <- args[3]; saida <- args[4]
n_cores <- if (length(args) >= 5) as.integer(args[5]) else NULL

suppressPackageStartupMessages(library(geocodebr))
stopifnot(as.character(packageVersion("geocodebr")) == "0.7.0")

exe <- ps::ps_exe(ps::ps_handle())
sh  <- length(grepRaw("SegmentHeap", readBin(exe, "raw", file.size(exe)), fixed = TRUE)) > 0

enderecos <- as.data.frame(arrow::read_parquet(
  "R:/Dropbox/git/geocodebr/r-package/inst/extdata/large_sample.parquet"))
campos <- definir_campos(logradouro = "logradouro", numero = "numero", cep = "cep",
                         localidade = "bairro", municipio = "municipio", estado = "uf")

h <- ps::ps_handle()
res <- vector("list", rodadas)
for (i in seq_len(rodadas)) {
  gc()
  mem0 <- ps::ps_memory_info(h)[["rss"]]
  cpu0 <- sum(ps::ps_cpu_times(h)[c("user", "system")])
  t0 <- Sys.time()
  out <- if (modo == "inproc") {
    geocodebr:::geocode_core(
      enderecos = enderecos, campos_endereco = campos, resultado_completo = FALSE,
      resolver_empates = TRUE, resultado_sf = FALSE, h3_res = NULL,
      padronizar_enderecos = TRUE, verboso = FALSE, cache = TRUE, n_cores = n_cores)
  } else {
    geocode(enderecos, campos_endereco = campos, resultado_completo = FALSE,
            resolver_empates = TRUE, verboso = FALSE, cache = TRUE, n_cores = n_cores)
  }
  wall <- as.numeric(difftime(Sys.time(), t0, units = "secs"))
  cpu <- sum(ps::ps_cpu_times(h)[c("user", "system")]) - cpu0
  mem1 <- ps::ps_memory_info(h)[["rss"]]
  chk <- sum(round(out$lat, 6), na.rm = TRUE)
  res[[i]] <- data.frame(rotulo = rotulo, modo = modo, segment_heap = sh, rodada = i,
                         wall_s = round(wall, 2), cpu_pai_s = round(cpu, 2),
                         rss_antes_mb = round(mem0 / 2^20), rss_depois_mb = round(mem1 / 2^20),
                         threads = ps::ps_num_threads(h), n = nrow(out),
                         checksum_lat = chk)
  print(res[[i]])
  rm(out)
}
res <- do.call(rbind, res)
write.csv(res, saida, row.names = FALSE)
