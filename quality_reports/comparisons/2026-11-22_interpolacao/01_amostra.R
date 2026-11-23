# Passo 1 — universo, atributos por rua-chave e amostra estratificada (+ alvos P1/P2)
# Rua-chave = (estado, municipio, logradouro, cep, localidade) = chave da etapa da01, tabela mais completa.
source("L:/Proj_acess_oport/git_rafa/geocodebr/quality_reports/comparisons/2026-11-22_interpolacao/00_config.R")
con <- con_interp(threads = 8L)   # preparação não é cronometrada

t0 <- Sys.time()
dbExecute(con, sprintf("
  CREATE OR REPLACE TABLE ref AS
  SELECT hash(estado, municipio, logradouro, cep, localidade) AS sid,
         estado, municipio, code_muni, logradouro, numero, cep, localidade, n_casos,
         lat::DOUBLE AS lat, lon::DOUBLE AS lon, desvio_metros::DOUBLE AS desvio
  FROM read_parquet('%s') WHERE code_muni NOT IN (%s)", PQ_NUM, paste(MUNIS_FORA, collapse = ",")))

dbExecute(con, "
  CREATE OR REPLACE TABLE ruas AS
  WITH r AS (SELECT sid, estado, municipio, logradouro, cep, localidade, count(*) AS n_pontos
             FROM ref GROUP BY ALL),
       c AS (SELECT estado, municipio, logradouro, localidade, count(DISTINCT cep) AS n_cep
             FROM ref GROUP BY ALL)
  SELECT r.*, c.n_cep,
    CASE WHEN n_pontos <= 3 THEN 'a_2-3' WHEN n_pontos <= 15 THEN 'b_4-15'
         WHEN n_pontos <= 60 THEN 'c_16-60' ELSE 'd_60+' END AS tam
  FROM r JOIN c USING (estado, municipio, logradouro, localidade)
  WHERE n_pontos >= 2")
print(dbGetQuery(con, "SELECT tam, count(*) ruas, sum(n_pontos) pontos FROM ruas GROUP BY 1 ORDER BY 1"))

# candidatos: 40 mil ruas por faixa (todas as > 60 pontos, onde curvas ordenadas são raras) de tamanho, ordem pseudo-aleatória determinística
dbExecute(con, sprintf("
  CREATE OR REPLACE TABLE cand AS
  SELECT * FROM ruas QUALIFY row_number() OVER (PARTITION BY tam ORDER BY hash(sid, '%s')) <= CASE WHEN tam = 'd_60+' THEN 150000 ELSE 40000 END", SEED))
# ruas-âncora da issue #10
dbExecute(con, "
  INSERT INTO cand SELECT * FROM ruas WHERE sid NOT IN (SELECT sid FROM cand) AND (
    (municipio = 'SAO PAULO' AND localidade = 'BUTANTA' AND logradouro = 'RUA IQUIRIRIM') OR
    (municipio = 'RIO DE JANEIRO' AND logradouro = 'AVENIDA MINISTRO IVAN LINS'))")
print(dbGetQuery(con, "SELECT logradouro, localidade, cep, n_pontos FROM ruas WHERE
   (municipio = 'SAO PAULO' AND localidade = 'BUTANTA' AND logradouro = 'RUA IQUIRIRIM') OR
   (municipio = 'RIO DE JANEIRO' AND logradouro = 'AVENIDA MINISTRO IVAN LINS')"))

# atributos geométricos de cada rua candidata (rua completa; a versão sem o alvo é feita no passo 3)
dbExecute(con, "
  CREATE OR REPLACE TABLE attr AS
  WITH p AS (
    SELECT r.sid, r.numero, r.lat, r.lon, r.numero % 2 AS lado
    FROM ref r SEMI JOIN cand c ON r.sid = c.sid),
  s AS (
    SELECT *,
      median(lat) OVER w5 AS lat_c, median(lon) OVER w5 AS lon_c,
      lag(lat) OVER wl AS lat_ls, lag(lon) OVER wl AS lon_ls,
      lead(lat) OVER wl AS lat_ns, lead(lon) OVER wl AS lon_ns,
      lag(lat) OVER wn AS lat_p, lag(lon) OVER wn AS lon_p, lag(lado) OVER wn AS lado_p,
      lead(lat) OVER wn AS lat_n, lead(lon) OVER wn AS lon_n, lead(lado) OVER wn AS lado_n
    FROM p
    WINDOW w5 AS (PARTITION BY sid ORDER BY numero ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING),
           wn AS (PARTITION BY sid ORDER BY numero),
           wl AS (PARTITION BY sid, lado ORDER BY numero)),
  g AS (
    SELECT *,
      hav(lag(lat_c) OVER wn, lag(lon_c) OVER wn, lat_c, lon_c) AS seg,
      least(hav(lat, lon, lat_ls, lon_ls), hav(lat, lon, lat_ns, lon_ns)) AS d_mesmo,
      least(CASE WHEN lado_p <> lado THEN hav(lat, lon, lat_p, lon_p) END,
            CASE WHEN lado_n <> lado THEN hav(lat, lon, lat_n, lon_n) END) AS d_oposto
    FROM s WINDOW wn AS (PARTITION BY sid ORDER BY numero)),
  cum AS (SELECT *, sum(coalesce(seg, 0)) OVER (PARTITION BY sid ORDER BY numero) AS s_m FROM g)
  SELECT sid,
    sum(coalesce(seg, 0)) AS comprimento,
    hav(arg_min(lat_c, numero), arg_min(lon_c, numero), arg_max(lat_c, numero), arg_max(lon_c, numero)) AS corda,
    sum(coalesce(seg, 0)) / nullif(hav(arg_min(lat_c, numero), arg_min(lon_c, numero),
                                       arg_max(lat_c, numero), arg_max(lon_c, numero)), 0) AS sinuosidade,
    corr(numero, s_m) AS corr_metrica,
    median(d_mesmo) AS d_mesmo_lado, median(d_oposto) AS d_lado_oposto,
    count(*) FILTER (lado = 0) AS n_par, count(*) FILTER (lado = 1) AS n_impar,
    median(abs(numero - lag_num)) AS gap_mediano
  FROM (SELECT *, lag(numero) OVER (PARTITION BY sid ORDER BY numero) AS lag_num FROM cum)
  GROUP BY sid")

# sinuosidade robusta: polilinha de 3–10 vértices (mediana das coordenadas por faixa de número).
# A versão com todos os pontos suavizados (sinuosidade_bruta) é inflada pelo ruído do GPS em ruas longas
# (77% das ruas com > 60 pontos saíam "curvas").
dbExecute(con, "
  CREATE OR REPLACE TABLE attr_v AS
  WITH p AS (SELECT r.sid, r.numero, r.lat, r.lon, least(10, greatest(3, c.n_pontos // 3)) AS nb
             FROM ref r JOIN cand c ON r.sid = c.sid WHERE c.n_pontos >= 4),
  b AS (SELECT *, ntile(nb) OVER (PARTITION BY sid ORDER BY numero) AS bin FROM p),
  v AS (SELECT sid, bin, median(lat) AS lat, median(lon) AS lon FROM b GROUP BY sid, bin),
  g AS (SELECT *, hav(lag(lat) OVER w, lag(lon) OVER w, lat, lon) AS seg FROM v
        WINDOW w AS (PARTITION BY sid ORDER BY bin))
  SELECT sid, sum(coalesce(seg, 0)) / nullif(hav(arg_min(lat, bin), arg_min(lon, bin),
                                                 arg_max(lat, bin), arg_max(lon, bin)), 0) AS sinuosidade
  FROM g GROUP BY sid")
dbExecute(con, "ALTER TABLE attr RENAME COLUMN sinuosidade TO sinuosidade_bruta")
dbExecute(con, "CREATE OR REPLACE TABLE attr AS SELECT a.*, v.sinuosidade FROM attr a LEFT JOIN attr_v v USING (sid)")

# Inspeção visual (01b_inspecao_curvas.R, variante 2) mostrou que as duas sinuosidades acima medem
# sobretudo a DESORDEM da numeração (números que vão e voltam numa rua reta), não a curva.
# Curvatura geométrica, independente da ordem dos números: eixo principal (PCA) dos pontos em metros;
# flecha = p90 de |distância perpendicular ao eixo|; extensão = p95 - p5 ao longo do eixo.
# curvatura = flecha / extensão. A desordem fica como atributo separado (sinuosidade_bruta).
dbExecute(con, "
  CREATE OR REPLACE TABLE attr_pca AS
  WITH p0 AS (SELECT r.sid, r.lon * 111320 * cos(radians(r.lat)) AS x, r.lat * 110540 AS y
              FROM ref r JOIN cand c ON r.sid = c.sid WHERE c.n_pontos >= 4),
  -- robustez (variante 3): descarta pontos a mais de 3x o p75 da distância ao centro mediano
  -- (e no mínimo 100 m), que de outro modo giram o eixo principal sozinhos
  c0 AS (SELECT sid, median(x) cx, median(y) cy FROM p0 GROUP BY sid),
  d0 AS (SELECT p0.*, sqrt(pow(x - cx, 2) + pow(y - cy, 2)) AS dc FROM p0 JOIN c0 USING (sid)),
  p AS (SELECT sid, x, y FROM d0 QUALIFY dc <= greatest(100, 3 * quantile_cont(dc, 0.75) OVER (PARTITION BY sid))),
  m AS (SELECT sid, avg(x) mx, avg(y) my, var_pop(x) vx, var_pop(y) vy, covar_pop(x, y) cxy FROM p GROUP BY sid),
  q AS (SELECT p.sid, 0.5 * atan2(2 * cxy, vx - vy) AS th, x - mx AS dx, y - my AS dy FROM p JOIN m USING (sid)),
  e AS (SELECT sid, dx * cos(th) + dy * sin(th) AS ao_longo, abs(-dx * sin(th) + dy * cos(th)) AS perp FROM q)
  SELECT sid, quantile_cont(perp, 0.9) AS flecha_m,
         quantile_cont(ao_longo, 0.95) - quantile_cont(ao_longo, 0.05) AS extensao_m,
         quantile_cont(perp, 0.9) / nullif(quantile_cont(ao_longo, 0.95) - quantile_cont(ao_longo, 0.05), 0) AS curvatura
  FROM e GROUP BY sid")
dbExecute(con, "CREATE OR REPLACE TABLE attr AS SELECT a.*, v.flecha_m, v.extensao_m, v.curvatura
                FROM attr a LEFT JOIN attr_pca v USING (sid)")

dbExecute(con, sprintf("
  CREATE OR REPLACE TABLE cand2 AS
  SELECT c.*, a.* EXCLUDE (sid),
    comprimento / nullif(extensao_m, 0) AS desordem,
    CASE WHEN n_pontos < 4 OR curvatura IS NULL THEN 'nd'
         WHEN comprimento / nullif(extensao_m, 0) > 2.5 THEN 'desordenada'
         WHEN curvatura > %f AND flecha_m > 25 THEN 'curva'
         WHEN curvatura < %f OR flecha_m <= 12 THEN 'reta' ELSE 'intermediaria' END AS forma,
    (n_par >= 2 AND n_impar >= 2 AND d_lado_oposto > d_mesmo_lado) AS lado_conforme,
    coalesce(corr_metrica, 0) >= 0.5 AS numeracao_metrica,
    (estado = 'DF') AS df
  FROM cand c JOIN attr a USING (sid)", CORTE_CURVA, CORTE_RETA))
print(dbGetQuery(con, "SELECT tam, forma, count(*) n FROM cand2 GROUP BY ALL ORDER BY ALL"))

# amostra final: até 1.000 ruas por célula tamanho × forma (n<=3: 1.000 ruas), + âncoras + DF à parte
dbExecute(con, sprintf("
  CREATE OR REPLACE TABLE amostra AS
  SELECT *, false AS ancora FROM cand2
  QUALIFY row_number() OVER (PARTITION BY tam, forma ORDER BY hash(sid, '%s', 2)) <= 1000
  UNION ALL BY NAME
  SELECT *, true AS ancora FROM cand2 WHERE
    (municipio = 'SAO PAULO' AND localidade = 'BUTANTA' AND logradouro = 'RUA IQUIRIRIM') OR
    (municipio = 'RIO DE JANEIRO' AND logradouro = 'AVENIDA MINISTRO IVAN LINS')", SEED))
dbExecute(con, "CREATE OR REPLACE TABLE amostra AS SELECT DISTINCT ON (sid) * FROM amostra ORDER BY sid, ancora DESC")
# DF próprio: até 300 ruas DF adicionais (estrato sinalizado)
dbExecute(con, sprintf("
  INSERT INTO amostra SELECT *, false FROM cand2 WHERE df AND sid NOT IN (SELECT sid FROM amostra)
  QUALIFY row_number() OVER (ORDER BY hash(sid, '%s', 3)) <= 300", SEED))
print(dbGetQuery(con, "SELECT tam, forma, count(*) ruas FROM amostra GROUP BY ALL ORDER BY ALL"))

# alvos: 2 internos + 1 ponta por rua (n=2: as 2 pontas; n=3: 1 interno + 1 ponta); âncoras: todos os números
dbExecute(con, sprintf("
  CREATE OR REPLACE TABLE alvos AS
  WITH p AS (
    SELECT r.sid, r.numero, r.lat, r.lon, r.n_casos, r.desvio, a.ancora,
      r.numero = min(r.numero) OVER (PARTITION BY r.sid) OR r.numero = max(r.numero) OVER (PARTITION BY r.sid) AS ponta
    FROM ref r JOIN amostra a USING (sid)),
  o AS (SELECT *, row_number() OVER (PARTITION BY sid, ponta ORDER BY hash(sid, numero, '%s')) AS ord FROM p)
  SELECT row_number() OVER (ORDER BY sid, numero) AS tid, sid, numero, lat AS lat_v, lon AS lon_v,
         n_casos, desvio AS desvio_v, ponta, ancora
  FROM o WHERE ancora OR (NOT ponta AND ord <= 2) OR (ponta AND ord <= 1) OR
               (ponta AND ord <= 2 AND sid IN (SELECT sid FROM amostra WHERE n_pontos = 2))", SEED))
print(dbGetQuery(con, "SELECT ponta, ancora, count(*) alvos FROM alvos GROUP BY ALL"))

if (SUF == "") arrow::write_parquet(dbGetQuery(con, "SELECT * EXCLUDE (sid), CAST(sid AS VARCHAR) sid FROM amostra"),
                     file.path(SAI, "amostra_ruas.parquet"))
cat("tempo:", format(Sys.time() - t0), "\n")
dbDisconnect(con, shutdown = TRUE)
