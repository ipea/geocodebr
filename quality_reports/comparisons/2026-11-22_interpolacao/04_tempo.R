# Passo 4 — tempo isolado por método (etapa da01: chave com CEP + localidade, tabela já materializada)
# Uso: Rscript 04_tempo.R prep             -> cria entradas (SP+RJ+MG, número inexistente na rua)
#      Rscript 04_tempo.R <metodo> <n>     -> 1 aquecimento descartado + 3 rodadas (1 se n >= 1e7),
#                                             2 threads; imprime mediana e pico de memória do processo
# Cada execução roda num processo novo (pico de memória limpo). M1_asof = M1 com ASOF JOIN em vez de
# juntar todos os números da rua (mesma resposta — conferido em 'equiv').
source("L:/Proj_acess_oport/git_rafa/geocodebr/quality_reports/comparisons/2026-11-22_interpolacao/00_config.R")
source(file.path(DIR, "02_metodos_sql.R"))
a <- commandArgs(TRUE)
KEY <- c("estado", "municipio", "logradouro", "cep", "localidade")
on_key <- function(l, r) paste(sprintf("%s.%s = %s.%s", l, KEY, r, KEY), collapse = " AND ")

if (a[1] == "prep") {
  con <- con_interp(threads = 8L)
  # entrada típica de da01: número vizinho (n+1 ou n+2) que não existe na mesma rua-chave
  dbExecute(con, sprintf("
    CREATE OR REPLACE TABLE entrada_t AS
    WITH b AS (SELECT r.* FROM ref r WHERE estado IN ('SP', 'RJ', 'MG')),
    c AS (SELECT b.estado, b.municipio, b.logradouro, b.cep, b.localidade, b.numero + d.d AS numero
          FROM b CROSS JOIN (VALUES (1), (2), (3)) d(d)
          WHERE NOT EXISTS (SELECT 1 FROM ref r WHERE r.sid = b.sid AND r.numero = b.numero + d.d))
    SELECT row_number() OVER (ORDER BY hash(estado, municipio, logradouro, cep, numero, '%s')) AS id, *
    FROM (SELECT DISTINCT * FROM c)
    QUALIFY id <= 10000000", SEED))
  print(dbGetQuery(con, "SELECT count(*) FROM entrada_t"))
  dbExecute(con, "CREATE OR REPLACE TABLE ref_t AS SELECT estado, municipio, logradouro, cep, localidade, numero, lat, lon, desvio AS desvio_metros FROM ref")
  dbDisconnect(con, shutdown = TRUE); quit(save = "no")
}

# --- SQL mínimo de cada método (só os agregados/janelas que ele usa) ------------------------------
ag <- strsplit(agregados_sql(), ",\n  ", fixed = TRUE)[[1]]
alias <- sub(".* AS ([a-z0-9_]+)$", "\\1", ag)
jan <- strsplit(janelas_sql("id"), ",\n   ", fixed = TRUE)[[1]]
precisa <- list(
  B0 = list(a = c("b0_lat", "b0_lon"), j = NULL),
  B1 = list(a = c("b1_lat", "b1_lon"), j = NULL),
  B2 = list(a = c("b1_lat", "b1_lon", "nl", "latl", "lonl", "nu", "latu", "lonu"), j = NULL),
  M1 = list(a = c("b1_lat", "b1_lon", "nl", "latl", "lonl", "nu", "latu", "lonu",
                  "nls", "latls", "lonls", "nus", "latus", "lonus"), j = NULL),
  M2 = list(a = c("m2_lat", "m2_lon"), j = 3),
  M4 = list(a = c("b1_lat", "b1_lon", "nl", "nu", "latl_c", "lonl_c", "latu_c", "lonu_c", "b1_lat_c", "b1_lon_c"), j = 1:2))
for (k in EXPOENTES) precisa[[paste0("W", k)]] <- list(a = sprintf("w%d_%s", k, c("lat", "lon")), j = NULL)

sql_metodo <- function(m, entrada) {
  if (m %in% c("M1_asof", "M1_asof_f")) {
    # M1_asof_f: referência antes restrita às ruas-chave presentes na entrada (como register_cnefe_table()
    # restringe por município) — o ASOF ordena a referência inteira, e a nacional custa ~70 s fixos
    rt <- if (m == "M1_asof_f") sprintf("(SELECT * FROM ref_t SEMI JOIN (SELECT DISTINCT %s FROM %s) k USING (%s))",
      paste(KEY, collapse = ", "), entrada, paste(KEY, collapse = ", ")) else "ref_t"
    # vizinhos L/U por ASOF (qualquer lado e mesmo lado). O vizinho mais próximo (fallback de ponta)
    # é o L ou o U mais perto — com desempate igual ao do B1 (menor |Δn|, depois menor número).
    asof <- function(lado, dir) {
      cond <- if (dir == "l") "e.numero > r.numero" else "e.numero < r.numero"
      par <- if (lado == "s") "AND e.numero % 2 = r.numero % 2" else ""
      tb <- if (lado == "s") sprintf("(SELECT *, numero %% 2 AS lado FROM %s)", rt) else rt
      sprintf("(SELECT e.id, r.numero AS n%1$s%2$s, r.lat AS lat%1$s%2$s, r.lon AS lon%1$s%2$s
                FROM %3$s e ASOF LEFT JOIN %4$s r ON %5$s %6$s AND %7$s)",
              dir, lado, entrada, tb, on_key("e", "r"),
              if (lado == "s") "AND e.numero % 2 = r.lado" else "", cond)
    }
    return(sprintf("
      CREATE OR REPLACE TEMP TABLE saida AS
      WITH j AS (
        SELECT e.id, e.numero, l.nl, l.latl, l.lonl, u.nu, u.latu, u.lonu,
               ls.nls, ls.latls, ls.lonls, us.nus, us.latus, us.lonus
        FROM %1$s e JOIN %2$s l USING (id) JOIN %3$s u USING (id) JOIN %4$s ls USING (id) JOIN %5$s us USING (id)
        WHERE l.nl IS NOT NULL OR u.nu IS NOT NULL),
      b AS (SELECT *, CASE WHEN nu IS NULL OR (nl IS NOT NULL AND numero - nl <= nu - numero) THEN latl ELSE latu END AS b1_lat,
                      CASE WHEN nu IS NULL OR (nl IS NOT NULL AND numero - nl <= nu - numero) THEN lonl ELSE lonu END AS b1_lon
            FROM j)
      SELECT id, %6$s AS lat, %7$s AS lon FROM b",
      entrada, asof("", "l"), asof("", "u"), asof("s", "l"), asof("s", "u"),
      finais_sql("M1", "lat"), finais_sql("M1", "lon")))
  }
  p <- precisa[[m]]
  jw <- if (length(p$j)) paste0(", ", paste(jan[p$j], collapse = ", ")) else ""
  sprintf("
    CREATE OR REPLACE TEMP TABLE saida AS
    WITH c AS (SELECT e.id, e.numero, r.numero AS numero_cnefe, r.lat, r.lon, r.desvio_metros
               FROM %s e JOIN ref_t r ON %s),
    w AS (SELECT * %s FROM c),
    g AS (SELECT id, numero, %s FROM w GROUP BY id, numero)
    SELECT id, %s AS lat, %s AS lon FROM g",
    entrada, on_key("e", "r"), jw, paste(ag[alias %in% p$a], collapse = ", "),
    finais_sql(m, "lat"), finais_sql(m, "lon"))
}

if (a[1] == "equiv") {
  # M1_asof ≡ M1 (agregado) e determinismo de todos com a entrada embaralhada, em 100 mil entradas
  con <- con_interp(threads = 2L)
  dbExecute(con, "CREATE OR REPLACE TEMP TABLE e1 AS SELECT * FROM entrada_t WHERE id <= 100000 ORDER BY id")
  dbExecute(con, "CREATE OR REPLACE TEMP TABLE e2 AS SELECT * FROM entrada_t WHERE id <= 100000 ORDER BY hash(id, 'embaralha')")
  out <- list()
  for (m in c(METODOS, "M1_asof", "M1_asof_f")) {
    dbExecute(con, sql_metodo(m, "e1")); r1 <- dbGetQuery(con, "SELECT * FROM saida ORDER BY id")
    dbExecute(con, sql_metodo(m, "e2")); r2 <- dbGetQuery(con, "SELECT * FROM saida ORDER BY id")
    out[[m]] <- r1
    cat(sprintf("%-8s n=%d determinístico=%s (max |Δ| %.3g grau)\n", m, nrow(r1),
                identical(r1, r2), max(abs(c(r1$lat - r2$lat, r1$lon - r2$lon)), na.rm = TRUE)))
  }
  d <- merge(out$M1, out$M1_asof, by = "id", suffixes = c("", "_asof"))
  cat(sprintf("M1_asof vs M1: %d/%d linhas; max |Δ| %.3g grau\n", nrow(d), nrow(out$M1),
              max(abs(c(d$lat - d$lat_asof, d$lon - d$lon_asof)), na.rm = TRUE)))
  dbDisconnect(con, shutdown = TRUE); quit(save = "no")
}

m <- a[1]; n <- as.numeric(a[2])
con <- con_interp(threads = N_THREADS)
dbExecute(con, sprintf("CREATE OR REPLACE TEMP TABLE ent AS SELECT * FROM entrada_t WHERE id <= %d", as.integer(n)))
q <- sql_metodo(m, "ent")
dbExecute(con, q)   # aquecimento (descartado)
reps <- if (n >= 1e7) 1 else 3
ts <- replicate(reps, system.time(dbExecute(con, q))[["elapsed"]])
n_out <- dbGetQuery(con, "SELECT count(*) n FROM saida")$n
pico <- ps::ps_memory_info(ps::ps_handle())[["peak_wset"]] / 2^30
linha <- data.frame(metodo = m, n = n, reps = reps, seg_mediana = median(ts), seg_min = min(ts),
                    seg_por_1k = median(ts) / n * 1000, n_saida = n_out, pico_gb = round(pico, 2))
print(linha)
f <- file.path(SAI, "tempo_isolado.csv")
write.table(linha, f, sep = ",", row.names = FALSE, col.names = !file.exists(f), append = file.exists(f))
dbDisconnect(con, shutdown = TRUE)
