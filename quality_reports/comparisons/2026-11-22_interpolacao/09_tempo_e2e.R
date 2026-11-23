# Passo 4 — ponta a ponta, B0 vs W3/W5 (issue #36) vs o vencedor (M1 sem trava = "M1n"), sem outros processos rodando.
# large_sample (20 mil): 1 aquecimento + 3 rodadas por método, alternadas; P0b (200 mil): 1 rodada.
source("L:/Proj_acess_oport/git_rafa/geocodebr/quality_reports/comparisons/2026-11-22_interpolacao/00_config.R")
source(file.path(DIR, "02_metodos_sql.R")); source(file.path(DIR, "05_override.R"))
carregar_geocodebr(); instala_override()
a20 <- as.data.frame(arrow::read_parquet(SAMPLE))
cA <- definir_campos(estado = "uf", municipio = "municipio", logradouro = "logradouro", numero = "numero", cep = "cep", localidade = "bairro")
p0b <- as.data.frame(arrow::read_parquet(file.path(OUT2, "p0b_input.parquet")))
cB <- definir_campos(estado = "estado", municipio = "municipio", logradouro = "logradouro", numero = "numero", cep = "cep_input", localidade = "localidade")
roda <- function(m, x, cp) { options(interp_metodo = m)
  t <- system.time(r <- geocode(x, cp, resultado_completo = FALSE, verboso = FALSE, n_cores = N_THREADS))[["elapsed"]]
  list(t = t, r = r) }
MS <- c("B0", "W3", "W5", "M1n")
for (m in MS) invisible(roda(m, a20, cA))   # aquecimento
out <- list(); res <- list()
for (k in 1:3) for (m in MS) { z <- roda(m, a20, cA); res[[m]] <- z$r
  out[[length(out) + 1]] <- data.frame(base = "large_sample", n = nrow(a20), metodo = m, rodada = k, seg = z$t) }
for (m in MS) { z <- roda(m, p0b, cB)
  out[[length(out) + 1]] <- data.frame(base = "P0b", n = nrow(p0b), metodo = m, rodada = 1, seg = z$t) }
o <- do.call(rbind, out); write.csv(o, file.path(SAI, "tempo_ponta_a_ponta_vencedor.csv"), row.names = FALSE)
print(aggregate(seg ~ base + metodo, o, median))
mud <- !is.na(res$B0$lat) & (abs(res$B0$lat - res$M1n$lat) > 1e-7 | abs(res$B0$lon - res$M1n$lon) > 1e-7)
cat(sprintf("large_sample: %d de %d linhas mudam de coordenada (%.1f%%); todas interpoladas: %s\n", sum(mud), nrow(a20),
            100 * mean(mud), all(grepl("^(da|pa)", res$B0$tipo_resultado[mud]))))
for (m in c("W3", "W5")) { mu <- !is.na(res$B0$lat) & (abs(res$B0$lat - res[[m]]$lat) > 1e-7 | abs(res$B0$lon - res[[m]]$lon) > 1e-7)
  cat(sprintf("large_sample %s: %d linhas mudam vs B0 (%.1f%%)\n", m, sum(mu), 100 * mean(mu))) }
