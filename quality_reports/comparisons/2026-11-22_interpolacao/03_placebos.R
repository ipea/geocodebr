# Passo 2/3 — placebos P1 (leave-one-out) e P2 (leave-window-out) com a chave da etapa da01
# Uso: Rscript 03_placebos.R P1|P2
source("L:/Proj_acess_oport/git_rafa/geocodebr/quality_reports/comparisons/2026-11-22_interpolacao/00_config.R")
source(file.path(DIR, "02_metodos_sql.R"))
esq <- commandArgs(TRUE)[1]; stopifnot(esq %in% c("P1", "P2"))
con <- con_interp(threads = 8L)   # não cronometrado; tempos no 04

# Remoção aplicada à rua inteira (todos os CEPs da mesma rua+localidade), para que a ponte de CEP
# não reencontre o número retirado.
remove <- switch(esq,
  P1 = "r.numero = t.numero",
  P2 = "abs(r.numero - t.numero) <= 10 OR hav(r.lat, r.lon, t.lat_v, t.lon_v) <= 5")

t0 <- Sys.time()
dbExecute(con, sprintf("
  CREATE OR REPLACE TEMP TABLE cand AS
  SELECT t.tid, t.numero, r.numero AS numero_cnefe, r.lat, r.lon, r.desvio AS desvio_metros,
         r.sid = t.sid AS mc
  FROM alvos t JOIN amostra a USING (sid)
  JOIN ref r ON r.estado = a.estado AND r.municipio = a.municipio
            AND r.logradouro = a.logradouro AND r.localidade = a.localidade
  WHERE NOT (%s)", remove))
dbExecute(con, sprintf("
  CREATE OR REPLACE TEMP TABLE cand_s AS
  SELECT *, %s FROM cand WHERE mc
  UNION ALL BY NAME SELECT * FROM cand WHERE NOT mc", janelas_sql("tid")))

dbExecute(con, sprintf("
  CREATE OR REPLACE TEMP TABLE agg AS
  SELECT tid, numero,
  %s,
  %s
  FROM cand_s GROUP BY tid, numero", agregados_sql("mc"), agregados_sql("TRUE", "br_")))

fin <- unlist(lapply(c(METODOS, "M1n"), function(m) sprintf("%s AS %s_lat, %s AS %s_lon",
  finais_sql(m, "lat"), tolower(m), finais_sql(m, "lon"), tolower(m))))
fin <- c(fin, sprintf("%s AS m1c_lat, %s AS m1c_lon", finais_sql("M1", "lat", TRUE), finais_sql("M1", "lon", TRUE)))
dbExecute(con, sprintf("
  CREATE OR REPLACE TABLE res_%s AS
  SELECT a.tid, a.numero, a.n_cand, a.desvio_med, a.b1_desvio, a.nl, a.nu, a.nls, a.nus,
    %s AS caminho_m1,
    CASE WHEN a.nl IS NOT NULL AND a.nu IS NOT NULL THEN hav(a.latl, a.lonl, a.latu, a.lonu) END AS dist_lu,
    %s
  FROM agg a WHERE n_cand > 0", esq, caminho_m1_sql(), paste(fin, collapse = ",\n    ")))

# curvatura da rua SEM o alvo/janela (mesma receita robusta do 01_amostra.R), por alvo
dbExecute(con, sprintf("
  CREATE OR REPLACE TABLE curv_%s AS
  WITH p0 AS (SELECT tid, lon * 111320 * cos(radians(lat)) AS x, lat * 110540 AS y FROM cand WHERE mc),
  c0 AS (SELECT tid, median(x) cx, median(y) cy, count(*) n FROM p0 GROUP BY tid),
  d0 AS (SELECT p0.*, sqrt(pow(x - cx, 2) + pow(y - cy, 2)) AS dc FROM p0 JOIN c0 USING (tid) WHERE n >= 4),
  p AS (SELECT tid, x, y FROM d0 QUALIFY dc <= greatest(100, 3 * quantile_cont(dc, 0.75) OVER (PARTITION BY tid))),
  m AS (SELECT tid, avg(x) mx, avg(y) my, var_pop(x) vx, var_pop(y) vy, covar_pop(x, y) cxy FROM p GROUP BY tid),
  q AS (SELECT p.tid, 0.5 * atan2(2 * cxy, vx - vy) AS th, x - mx AS dx, y - my AS dy FROM p JOIN m USING (tid)),
  e AS (SELECT tid, dx * cos(th) + dy * sin(th) AS al, abs(-dx * sin(th) + dy * cos(th)) AS perp FROM q)
  SELECT tid, quantile_cont(perp, 0.9) AS flecha_t,
         quantile_cont(perp, 0.9) / nullif(quantile_cont(al, 0.95) - quantile_cont(al, 0.05), 0) AS curvatura_t
  FROM e GROUP BY tid", esq))

# distância ao eixo suavizado (descritiva) e erro contra a verdade, formato longo
mets <- c(tolower(METODOS), "m1c", "m1n")
unp <- paste(sprintf("SELECT tid, '%1$s' AS metodo, %1$s_lat AS lat, %1$s_lon AS lon FROM res_%2$s", mets, esq),
             collapse = " UNION ALL ")
dbExecute(con, sprintf("
  CREATE OR REPLACE TABLE eixo_%1$s AS
  WITH seg AS (
    SELECT tid, lat_c AS alat, lon_c AS alon, lead(lat_c) OVER w AS blat, lead(lon_c) OVER w AS blon
    FROM cand_s WHERE mc WINDOW w AS (PARTITION BY tid ORDER BY numero_cnefe)),
  est AS (%2$s),
  xy AS (
    SELECT e.tid, e.metodo,
      (e.lon - s.alon) * 111320 * cos(radians(e.lat)) AS px, (e.lat - s.alat) * 110540 AS py,
      (coalesce(s.blon, s.alon) - s.alon) * 111320 * cos(radians(e.lat)) AS vx,
      (coalesce(s.blat, s.alat) - s.alat) * 110540 AS vy
    FROM est e JOIN seg s USING (tid)),
  d AS (SELECT tid, metodo,
      greatest(0, least(1, (px * vx + py * vy) / nullif(vx * vx + vy * vy, 0))) AS u, px, py, vx, vy FROM xy)
  SELECT tid, metodo, min(sqrt(pow(px - coalesce(u, 0) * vx, 2) + pow(py - coalesce(u, 0) * vy, 2))) AS dist_eixo
  FROM d GROUP BY tid, metodo", esq, unp))

dbExecute(con, sprintf("
  CREATE OR REPLACE TABLE erro_%1$s AS
  WITH est AS (%2$s)
  SELECT e.tid, e.metodo, hav(e.lat, e.lon, t.lat_v, t.lon_v) AS erro_m, x.dist_eixo
  FROM est e JOIN alvos t USING (tid) LEFT JOIN eixo_%1$s x USING (tid, metodo)", esq, unp))

print(dbGetQuery(con, sprintf("
  SELECT metodo, count(*) n, count(erro_m) n_ok, round(median(erro_m), 1) mediana,
         round(quantile_cont(erro_m, 0.9), 1) p90, round(avg((erro_m < 50)::INT) * 100, 1) pct50
  FROM erro_%s GROUP BY metodo ORDER BY mediana", esq)))
print(dbGetQuery(con, sprintf("SELECT caminho_m1, count(*) FROM res_%s GROUP BY 1 ORDER BY 2 DESC", esq)))
for (tb in c("res", "erro", "curv")) arrow::write_parquet(dbGetQuery(con, sprintf("SELECT * FROM %s_%s", tb, esq)),
  file.path(OUT2, sprintf("%s_%s%s.parquet", tb, esq, SUF)))
cat(esq, "tempo:", format(Sys.time() - t0), "\n")
dbDisconnect(con, shutdown = TRUE)
