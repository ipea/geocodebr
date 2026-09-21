# -----------------------------------------------------------------------------
# Auditoria CNEFE, Etapa 5: checagens de conteudo entre dois releases.
#
# Complementa compare_cnefe_releases.R (que so le metadados). Aqui lemos dados,
# mas todas as agregacoes sao empurradas para dentro do DuckDB -- nada e
# materializado no R.
#
#   Passo A  (12 tabelas x 2 versoes): 1 varredura por arquivo, GROUP BY estado
#            -> linhas, sum(n_casos), nulos em lat, faixa de lat/lon
#   Passo B  (tabelas alvo): anti-join na chave natural para caracterizar as
#            linhas que sumiram (remocao real vs. renomeacao de string)
#   Passo C  compara lat/lon entre as versoes, com cast para FLOAT
#   Passo D  casas decimais armazenadas + custo puro do cast double->float,
#            e quanto do deslocamento observado NAO cabe nesse custo
#
# Uso: Rscript quality_reports/diagnoses/compare_cnefe_values.R
# -----------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(duckdb); library(DBI); library(data.table)
})

BASE   <- "//STORAGE6/bases/DADOS/PUBLICO/CNEFE/cnefe_padrao_geocodebr/2022"
V1_DIR <- file.path(BASE, "v0.4.1", "dados_agregados")
V2_DIR <- file.path(BASE, "v0.5.0", "dados_agregados")
V1 <- "v0.4.1"; V2 <- "v0.5.0"

OUT_DIR <- if (nzchar(Sys.getenv("CNEFE_AUDIT_OUT"))) Sys.getenv("CNEFE_AUDIT_OUT") else file.path(tempdir(), "cnefe_audit")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

msg <- function(...) cat(sprintf(...), "\n", sep = "")

con <- dbConnect(duckdb::duckdb())
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)
dbExecute(con, "PRAGMA threads=8")
dbExecute(con, "PRAGMA memory_limit='8GB'")
qs <- function(x) dbQuoteString(con, x)

tabelas <- sort(basename(list.files(V1_DIR, pattern = "\\.parquet$")))

# Chave natural de cada tabela = os segmentos do nome do arquivo.
# municipio_logradouro_numero_cep_localidade -> estado, municipio, logradouro, numero, cep, localidade
chave_natural <- function(tb) {
  seg <- strsplit(sub("\\.parquet$", "", tb), "_")[[1]]
  c("estado", seg)
}


# -- Passo A: agregados por estado, uma varredura por arquivo ------------------

msg("== Passo A: agregados por estado ==")

agrega <- function(path, versao, tb) {
  t0 <- Sys.time()
  q <- sprintf("
    SELECT %s AS versao, %s AS tabela, estado,
           count(*)::BIGINT                        AS linhas,
           sum(n_casos)::HUGEINT                   AS soma_n_casos,
           count(*) FILTER (WHERE lat IS NULL)     AS lat_nulos,
           count(*) FILTER (WHERE lon IS NULL)     AS lon_nulos,
           min(lat) AS lat_min, max(lat) AS lat_max,
           min(lon) AS lon_min, max(lon) AS lon_max
    FROM read_parquet(%s)
    GROUP BY estado", qs(versao), qs(tb), qs(path))
  r <- as.data.table(dbGetQuery(con, q))
  msg("  %-8s %-52s %5.1fs", versao, tb, as.numeric(difftime(Sys.time(), t0, units = "secs")))
  r
}

passoA <- rbindlist(lapply(tabelas, function(tb) {
  rbind(agrega(file.path(V1_DIR, tb), V1, tb),
        agrega(file.path(V2_DIR, tb), V2, tb))
}))

fwrite(passoA, file.path(OUT_DIR, "passoA_por_estado.csv"))

# Roll-up por tabela
por_tab <- dcast(passoA[, .(linhas = sum(linhas), n_casos = sum(as.numeric(soma_n_casos)),
                           lat_nulos = sum(lat_nulos)),
                        by = .(tabela, versao)],
                 tabela ~ versao, value.var = c("linhas", "n_casos", "lat_nulos"))
setnames(por_tab, gsub("v0\\.4\\.1", "v1", gsub("v0\\.5\\.0", "v2", names(por_tab))))
por_tab[, `:=`(d_linhas  = linhas_v2 - linhas_v1,
               d_n_casos = n_casos_v2 - n_casos_v1)]
por_tab[, d_n_casos_pct := 100 * d_n_casos / n_casos_v1]

msg("\n-- Linhas vs soma de n_casos (o teste de perda de enderecos) --")
print(por_tab[, .(tabela, d_linhas,
                  n_casos_v1 = format(n_casos_v1, big.mark = ","),
                  n_casos_v2 = format(n_casos_v2, big.mark = ","),
                  d_n_casos, d_n_casos_pct = round(d_n_casos_pct, 4),
                  lat_nulos_v1, lat_nulos_v2)])

# Delta de linhas por estado
por_uf <- dcast(passoA[, .(tabela, versao, estado, linhas)], tabela + estado ~ versao, value.var = "linhas")
setnames(por_uf, c(V1, V2), c("linhas_v1", "linhas_v2"))
por_uf[, d := linhas_v2 - linhas_v1]
fwrite(por_uf, file.path(OUT_DIR, "passoA_delta_por_uf.csv"))

msg("\n-- Delta de linhas por UF, somado sobre as 12 tabelas --")
uf_tot <- por_uf[, .(d_total = sum(d), linhas_v1 = sum(linhas_v1)), by = estado][order(d_total)]
uf_tot[, d_pct := round(100 * d_total / linhas_v1, 4)]
print(uf_tot)

msg("\n-- UFs com delta ZERO (nenhuma linha perdida) --")
print(uf_tot[d_total == 0, estado])


# -- Passo B: caracterizar as linhas removidas --------------------------------

msg("\n== Passo B: anti-join na chave natural ==")

alvos <- c("municipio_cep.parquet", "municipio_localidade.parquet",
           "municipio_cep_localidade.parquet", "municipio_logradouro.parquet")

antijoin <- function(tb) {
  k <- chave_natural(tb)
  kq <- paste0("a.", k, collapse = ", ")
  on <- paste(sprintf("a.%s IS NOT DISTINCT FROM b.%s", k, k), collapse = " AND ")
  t0 <- Sys.time()

  # 1. Duplicatas na chave natural em cada versao
  dup <- dbGetQuery(con, sprintf("
    SELECT %s AS versao, count(*) AS linhas, count(DISTINCT (%s)) AS chaves_distintas
    FROM (SELECT %s FROM read_parquet(%s)) a",
    qs(V1), paste0("a.", k, collapse = ", "), paste(k, collapse = ", "), qs(file.path(V1_DIR, tb))))
  dup2 <- dbGetQuery(con, sprintf("
    SELECT %s AS versao, count(*) AS linhas, count(DISTINCT (%s)) AS chaves_distintas
    FROM (SELECT %s FROM read_parquet(%s)) a",
    qs(V2), paste0("a.", k, collapse = ", "), paste(k, collapse = ", "), qs(file.path(V2_DIR, tb))))

  # 2. Linhas presentes em v1 e ausentes em v2 (e vice-versa)
  so_v1 <- dbGetQuery(con, sprintf("
    SELECT count(*) AS n FROM (SELECT %s FROM read_parquet(%s)) a
    ANTI JOIN (SELECT %s FROM read_parquet(%s)) b ON %s",
    paste(k, collapse = ", "), qs(file.path(V1_DIR, tb)),
    paste(k, collapse = ", "), qs(file.path(V2_DIR, tb)), on))$n
  so_v2 <- dbGetQuery(con, sprintf("
    SELECT count(*) AS n FROM (SELECT %s FROM read_parquet(%s)) a
    ANTI JOIN (SELECT %s FROM read_parquet(%s)) b ON %s",
    paste(k, collapse = ", "), qs(file.path(V2_DIR, tb)),
    paste(k, collapse = ", "), qs(file.path(V1_DIR, tb)), on))$n

  msg("  %-40s chave=[%s]  (%.0fs)", tb, paste(k, collapse = ","),
      as.numeric(difftime(Sys.time(), t0, units = "secs")))
  msg("    %s: %s linhas / %s chaves distintas (dups: %s)",
      V1, format(dup$linhas, big.mark=","), format(dup$chaves_distintas, big.mark=","),
      format(dup$linhas - dup$chaves_distintas, big.mark=","))
  msg("    %s: %s linhas / %s chaves distintas (dups: %s)",
      V2, format(dup2$linhas, big.mark=","), format(dup2$chaves_distintas, big.mark=","),
      format(dup2$linhas - dup2$chaves_distintas, big.mark=","))
  msg("    chaves so em %s: %s | so em %s: %s",
      V1, format(so_v1, big.mark=","), V2, format(so_v2, big.mark=","))

  data.table(tabela = tb, chave = paste(k, collapse = ","),
             linhas_v1 = dup$linhas, chaves_v1 = dup$chaves_distintas,
             linhas_v2 = dup2$linhas, chaves_v2 = dup2$chaves_distintas,
             so_em_v1 = so_v1, so_em_v2 = so_v2)
}

passoB <- rbindlist(lapply(alvos, antijoin))
fwrite(passoB, file.path(OUT_DIR, "passoB_antijoin.csv"))


# -- Passo C: as coordenadas mudaram, ou so foram truncadas para float32? -----

msg("\n== Passo C: precisao das coordenadas ==")

precisao <- function(tb) {
  k <- chave_natural(tb)
  on <- paste(sprintf("a.%s IS NOT DISTINCT FROM b.%s", k, k), collapse = " AND ")
  q <- sprintf("
    SELECT count(*)                                          AS pares,
           max(abs(a.lat::FLOAT - b.lat))                    AS max_dif_lat_apos_cast,
           max(abs(a.lon::FLOAT - b.lon))                    AS max_dif_lon_apos_cast,
           max(abs(a.lat - b.lat::DOUBLE))                   AS max_dif_lat_bruta,
           max(abs(a.lon - b.lon::DOUBLE))                   AS max_dif_lon_bruta,
           count(*) FILTER (WHERE a.lat::FLOAT <> b.lat
                               OR a.lon::FLOAT <> b.lon)     AS n_divergentes
    FROM (SELECT %s, lat, lon FROM read_parquet(%s)) a
    JOIN (SELECT %s, lat, lon FROM read_parquet(%s)) b ON %s",
    paste(k, collapse=", "), qs(file.path(V1_DIR, tb)),
    paste(k, collapse=", "), qs(file.path(V2_DIR, tb)), on)
  r <- as.data.table(dbGetQuery(con, q))
  r[, tabela := tb]
  print(r)
  r
}

passoC <- rbindlist(lapply(c("municipio.parquet", "municipio_cep.parquet"), precisao))
fwrite(passoC, file.path(OUT_DIR, "passoC_precisao.csv"))


# -- Passo D: casas decimais e custo puro do cast double->float ----------------
#
# Responde "as coordenadas perderam precisao?" separando duas perguntas:
#   (a) quantas casas decimais estao de fato armazenadas em cada versao
#   (b) quanto o cast double->float custa em metros -- medido SO sobre o v0.4.1
#       (cast(lat AS FLOAT) vs o lat original), o que isola o arredondamento de
#       qualquer recomputacao que o v0.5.0 tenha feito

msg("\n== Passo D: precisao decimal e custo do cast ==")

TB_D <- "municipio_cep.parquet"

casas_decimais <- function(path, versao) {
  pt <- dbQuoteString(con, ".")
  q <- sprintf("
    SELECT %s AS versao,
           round(avg(length(split_part(abs(lat)::VARCHAR, %s, 2))), 2) AS dec_lat_medio,
           max(length(split_part(abs(lat)::VARCHAR, %s, 2)))           AS dec_lat_max,
           round(avg(length(split_part(abs(lon)::VARCHAR, %s, 2))), 2) AS dec_lon_medio,
           max(length(split_part(abs(lon)::VARCHAR, %s, 2)))           AS dec_lon_max
    FROM read_parquet(%s)", qs(versao), pt, pt, pt, pt, qs(path))
  as.data.table(dbGetQuery(con, q))
}

msg("\n-- D1: casas decimais armazenadas (%s) --", TB_D)
passoD1 <- rbind(casas_decimais(file.path(V1_DIR, TB_D), V1),
                 casas_decimais(file.path(V2_DIR, TB_D), V2))
print(passoD1)

# Custo puro do cast: mede sobre o v0.4.1, sem tocar no v0.5.0
msg("\n-- D2: erro do cast double->float, medido so no %s --", V1)
passoD2 <- as.data.table(dbGetQuery(con, sprintf("
  SELECT avg(abs(lat - lat::FLOAT::DOUBLE))                    AS err_lat_graus_medio,
         max(abs(lat - lat::FLOAT::DOUBLE))                    AS err_lat_graus_max,
         avg(abs(lon - lon::FLOAT::DOUBLE))                    AS err_lon_graus_medio,
         max(abs(lon - lon::FLOAT::DOUBLE))                    AS err_lon_graus_max,
         avg(abs(lat - lat::FLOAT::DOUBLE)) * 111320           AS err_lat_m_medio,
         max(abs(lat - lat::FLOAT::DOUBLE)) * 111320           AS err_lat_m_max,
         avg(abs(lon - lon::FLOAT::DOUBLE)) * 111320 * cos(radians(avg(lat))) AS err_lon_m_medio,
         max(abs(lon - lon::FLOAT::DOUBLE)) * 111320 * cos(radians(avg(lat))) AS err_lon_m_max
  FROM read_parquet(%s)", qs(file.path(V1_DIR, TB_D)))))
print(t(data.frame(lapply(passoD2, signif, 3))))

teto_cast <- sqrt(passoD2$err_lat_m_max^2 + passoD2$err_lon_m_max^2)
msg("teto combinado do cast: %.2f m", teto_cast)

# Quanto do deslocamento observado NAO cabe dentro desse teto
msg("\n-- D3: deslocamento observado vs teto do cast --")
k <- chave_natural(TB_D)
on <- paste(sprintf("a.%s IS NOT DISTINCT FROM b.%s", k, k), collapse = " AND ")
passoD3 <- as.data.table(dbGetQuery(con, sprintf("
  WITH j AS (
    SELECT a.lat la, a.lon lo, b.lat lb, b.lon lb2
    FROM (SELECT %s, lat, lon FROM read_parquet(%s)) a
    JOIN (SELECT %s, lat, lon FROM read_parquet(%s)) b ON %s),
  d AS (SELECT *, 111320*sqrt(pow(la-lb,2) + pow((lo-lb2)*cos(radians(la)),2)) AS m FROM j)
  SELECT count(*)                                      AS pares,
         count(*) FILTER (WHERE m <= %f)               AS dentro_do_teto,
         count(*) FILTER (WHERE m > %f  AND m <= 1)    AS teto_a_1m,
         count(*) FILTER (WHERE m > 1   AND m <= 10)   AS m1_10,
         count(*) FILTER (WHERE m > 10)                AS gt_10m,
         100.0 * count(*) FILTER (WHERE m > %f) / count(*) AS pct_acima_do_teto,
         quantile_cont(m, 0.5) AS p50, quantile_cont(m, 0.95) AS p95, max(m) AS max_m
  FROM d",
  paste(k, collapse = ", "), qs(file.path(V1_DIR, TB_D)),
  paste(k, collapse = ", "), qs(file.path(V2_DIR, TB_D)), on,
  teto_cast, teto_cast, teto_cast)))
print(t(round(passoD3, 3)))
msg("=> %.2f%% das coordenadas se moveram MAIS do que o cast consegue explicar.",
    passoD3$pct_acima_do_teto)

fwrite(passoD1, file.path(OUT_DIR, "passoD1_casas_decimais.csv"))
fwrite(passoD2, file.path(OUT_DIR, "passoD2_erro_cast.csv"))
fwrite(passoD3, file.path(OUT_DIR, "passoD3_deslocamento_vs_teto.csv"))

msg("\nOK. CSVs em: %s", OUT_DIR)
