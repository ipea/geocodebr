# Portão do harness (plano, "Verificação"):
#  A) override com B0 ≡ geocode() original no large_sample (todas as etapas da0x/pa0x, desempate incluído)
#  B) B0 isolado (03_placebos.R, P1) ≡ geocode() com holdout em 200 alvos internos (etapa da01)
# Tolerância: 1 m (haversine, DOUBLE). Se falhar, nada segue.
source("L:/Proj_acess_oport/git_rafa/geocodebr/quality_reports/comparisons/2026-11-22_interpolacao/00_config.R")
source(file.path(DIR, "02_metodos_sql.R")); source(file.path(DIR, "05_override.R"))
carregar_geocodebr()
hav_r <- function(la1, lo1, la2, lo2) {
  r <- pi / 180; a <- sin((la2 - la1) * r / 2)^2 + cos(la1 * r) * cos(la2 * r) * sin((lo2 - lo1) * r / 2)^2
  2 * 6371008.8 * asin(sqrt(a))
}
campos <- definir_campos(estado = "estado", municipio = "municipio", logradouro = "logradouro",
                         numero = "numero", cep = "cep", localidade = "localidade")
camposA <- definir_campos(estado = "uf", municipio = "municipio", logradouro = "logradouro",
                          numero = "numero", cep = "cep", localidade = "bairro")

# ---- A ---------------------------------------------------------------------------------------
amostra20 <- as.data.frame(arrow::read_parquet(SAMPLE))
orig <- geocode(amostra20, camposA, resultado_completo = TRUE, verboso = FALSE, n_cores = N_THREADS)
options(interp_metodo = "B0"); instala_override()
ovr <- geocode(amostra20, camposA, resultado_completo = TRUE, verboso = FALSE, n_cores = N_THREADS)
stopifnot(nrow(orig) == nrow(ovr), identical(orig$tipo_resultado, ovr$tipo_resultado))
dA <- hav_r(orig$lat, orig$lon, ovr$lat, ovr$lon)
interp <- grepl("^(da|pa)", orig$tipo_resultado)
cat(sprintf("Portão A: %d linhas, %d interpoladas; max |Δ| = %.3g m; endereco_encontrado idêntico: %s\n",
            nrow(orig), sum(interp), max(dA, na.rm = TRUE), identical(orig$endereco_encontrado, ovr$endereco_encontrado)))
print(table(orig$tipo_resultado[interp]))
okA <- max(dA, na.rm = TRUE) <= 1 && identical(is.na(orig$lat), is.na(ovr$lat))

# ---- B ---------------------------------------------------------------------------------------
con <- con_interp(threads = 8L)
g <- dbGetQuery(con, sprintf("
  SELECT t.tid, a.estado, a.municipio, a.logradouro, t.numero, a.cep, a.localidade, r.b0_lat, r.b0_lon
  FROM alvos t JOIN amostra a USING (sid) JOIN res_P1 r USING (tid)
  WHERE NOT t.ponta AND NOT t.ancora QUALIFY row_number() OVER (PARTITION BY t.sid ORDER BY t.tid) = 1
  ORDER BY hash(t.tid, '%s') LIMIT 200", SEED))  # 1 alvo por rua: o holdout retira todos juntos
HOLD <- file.path(OUT2, "cache_gate"); HOLD_DIR <- file.path(HOLD, basename(CACHE)); dir.create(HOLD_DIR, recursive = TRUE, showWarnings = FALSE)
dbWriteTable(con, "g", g[, c("estado", "municipio", "logradouro", "numero", "localidade")], overwrite = TRUE)
for (f in list.files(CACHE, "\\.parquet$")) {
  if (grepl("_numero_", f)) {
    dbExecute(con, sprintf("COPY (SELECT * FROM read_parquet('%s') t WHERE NOT EXISTS (SELECT 1 FROM g WHERE
      g.estado = t.estado AND g.municipio = t.municipio AND g.logradouro = t.logradouro AND
      g.numero = t.numero AND g.localidade = t.localidade)) TO '%s' (FORMAT parquet)", file.path(CACHE, f), file.path(HOLD_DIR, f)))
  } else file.copy(file.path(CACHE, f), file.path(HOLD_DIR, f), overwrite = TRUE)
}
dbDisconnect(con, shutdown = TRUE)
ns <- asNamespace("geocodebr")
if (bindingIsLocked("listar_pasta_cache", ns)) unlockBinding("listar_pasta_cache", ns)
assign("listar_pasta_cache", function() HOLD, envir = ns)
carregar_orig <- function() { carregar_geocodebr(); ns <- asNamespace("geocodebr")
  if (bindingIsLocked("listar_pasta_cache", ns)) unlockBinding("listar_pasta_cache", ns)
  assign("listar_pasta_cache", function() HOLD, envir = ns) }
carregar_orig()   # sem override: geocode() de produção
gb <- geocode(g[, 2:7], campos, resultado_completo = TRUE, verboso = FALSE, n_cores = N_THREADS)
dB <- hav_r(gb$lat, gb$lon, g$b0_lat, g$b0_lon)
cat("Portão B: tipos ", paste(names(table(gb$tipo_resultado)), table(gb$tipo_resultado), collapse = "; "), "\n")
cat(sprintf("Portão B: %d casos da01; max |Δ| = %.3g m; mediana %.3g m\n",
            sum(gb$tipo_resultado == "da01"), max(dB[gb$tipo_resultado == "da01"]), median(dB[gb$tipo_resultado == "da01"])))
okB <- all(gb$tipo_resultado == "da01") && max(dB) <= 1
writeLines(c(sprintf("Portão A (override B0 ≡ produção, large_sample): %s — max %.3g m em %d linhas interpoladas",
                     if (okA) "PASSOU" else "FALHOU", max(dA, na.rm = TRUE), sum(interp)),
             sprintf("Portão B (B0 isolado ≡ geocode() com holdout, 200 alvos): %s — max %.3g m; tipos: %s",
                     if (okB) "PASSOU" else "FALHOU", max(dB, na.rm = TRUE),
                     paste(names(table(gb$tipo_resultado)), table(gb$tipo_resultado), collapse = ", "))),
           file.path(SAI, "portao.txt"))
arrow::write_parquet(orig, file.path(OUT2, "large_sample_B0_orig.parquet"))
