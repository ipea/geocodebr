# Confirmação da ablação pós-hoc (M1 com vs sem trava) numa amostra NOVA (outra semente, outras ruas).
# Uso: INTERP_SEED=confirmacao INTERP_DB=<scratch>/interp_conf.duckdb, depois de 01_amostra.R e 03_placebos.R P1/P2
source("L:/Proj_acess_oport/git_rafa/geocodebr/quality_reports/comparisons/2026-11-22_interpolacao/00_config.R")
stopifnot(SUF == "_conf")
con <- con_interp(2L)
sink(file.path(SAI, "confirmacao_m1_trava.txt"), split = TRUE)
cat("Amostra de confirmação — semente:", SEED, "\n")
print(dbGetQuery(con, "SELECT count(DISTINCT sid) AS ruas, count(*) AS alvos FROM alvos WHERE NOT ancora"))
dbExecute(con, sprintf("ATTACH '%s' AS p (READ_ONLY)", file.path(OUT2, "interp.duckdb")))
print(dbGetQuery(con, "SELECT count(*) AS ruas_em_comum_com_amostra_principal FROM (SELECT sid FROM alvos INTERSECT SELECT sid FROM p.alvos)"))
for (e in c("P1", "P2")) {
  cat("\n--", e, "interior (alvos não-ponta) --\n")
  print(dbGetQuery(con, sprintf("
    SELECT metodo, count(*) n, round(median(erro_m), 1) mediana, round(quantile_cont(erro_m, .9), 0) p90,
           round(100 * avg((erro_m < 50)::INT), 1) pct_50m
    FROM read_parquet('%s') e JOIN alvos t USING (tid)
    WHERE NOT t.ponta AND NOT t.ancora GROUP BY 1 ORDER BY mediana", file.path(OUT2, sprintf("erro_%s_conf.parquet", e)))))
}
sink(); dbDisconnect(con, shutdown = TRUE)
