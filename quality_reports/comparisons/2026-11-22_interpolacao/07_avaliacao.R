# Passo 3/5 — avaliação: tabelas por estrato, bootstrap por rua, calibração, P0, figuras
source("L:/Proj_acess_oport/git_rafa/geocodebr/quality_reports/comparisons/2026-11-22_interpolacao/00_config.R")
source(file.path(DIR, "02_metodos_sql.R"))
library(ggplot2)
VENC <- "m1n"   # vencedor: M1 sem trava (ablação pós-hoc confirmada em amostra nova, 08_confirmacao.R)
MET  <- c("b0", "w3", "w5", "b1", "b2", "m1", "m1c", "m2", "m4")
ROT  <- c(b0 = "B0 IDW (atual)", w3 = "W3 IDW |Δn|³", w5 = "W5 IDW |Δn|⁵", b1 = "B1 vizinho", b2 = "B2 bracket", m1 = "M1 bracket mesmo lado",
          m1c = "M1 + ponte CEP", m1n = "M1 sem trava", m2 = "M2 mediana k=4", m4 = "M4 eixo")
med <- function(x) median(x, na.rm = TRUE)
sink(file.path(SAI, "metricas_interp.txt"), split = TRUE)
con <- con_interp(threads = 2L)

resumo <- function(where, by = "") dbGetQuery(con, sprintf("
  SELECT %s metodo, count(*) AS n, round(median(erro_m), 1) AS mediana, round(quantile_cont(erro_m, 0.9), 0) AS p90,
         round(100 * avg((erro_m < 50)::INT), 1) AS pct_50m, round(100 * avg((erro_m > erro_b1 + 50)::INT), 1) AS pct_pior_b1_50m
  FROM base WHERE %s GROUP BY ALL ORDER BY ALL", if (nzchar(by)) paste0(by, ",") else "", where))
larga <- function(d, by, val = "mediana") {
  w <- reshape(d[, c(by, "metodo", val)], idvar = by, timevar = "metodo", direction = "wide")
  names(w) <- sub(paste0(val, "."), "", names(w), fixed = TRUE); w }

for (esq in c("P1", "P2")) {
  dbExecute(con, sprintf("
    CREATE OR REPLACE TEMP TABLE base AS
    WITH e AS (SELECT * FROM read_parquet('%1$s/erro_%2$s.parquet')),
    b1 AS (SELECT tid, erro_m AS erro_b1 FROM e WHERE metodo = 'b1')
    SELECT e.*, b1.erro_b1, t.sid, t.ponta, t.ancora, t.n_casos, t.desvio_v, a.tam, a.forma, a.estado,
           a.lado_conforme, a.numeracao_metrica, a.n_cep > 1 AS multi_cep, a.df,
           r.caminho_m1, r.dist_lu, r.desvio_med, r.b1_desvio, c.curvatura_t, c.flecha_t
    FROM e JOIN b1 USING (tid) JOIN alvos t USING (tid) JOIN amostra a USING (sid)
    JOIN read_parquet('%1$s/res_%2$s.parquet') r USING (tid)
    LEFT JOIN read_parquet('%1$s/curv_%2$s.parquet') c USING (tid)
    WHERE NOT t.ancora", OUT2, esq))
  cat("\n================", esq, "================\n")
  cat("\n-- interior vs ponta (todas as formas) --\n"); print(resumo("TRUE", "ponta"))
  cat("\n-- interior: mediana por forma --\n"); print(larga(resumo("NOT ponta", "forma"), "forma"))
  cat("\n-- interior: p90 por forma --\n"); print(larga(resumo("NOT ponta", "forma"), "forma", "p90"))
  cat("\n-- interior: % < 50 m por forma --\n"); print(larga(resumo("NOT ponta", "forma"), "forma", "pct_50m"))
  cat("\n-- interior: mediana por tamanho --\n"); print(larga(resumo("NOT ponta", "tam"), "tam"))
  cat("\n-- interior: % piora > 50 m vs B1, por forma --\n"); print(larga(resumo("NOT ponta", "forma"), "forma", "pct_pior_b1_50m"))
  for (cut in c("n_casos > 1", "lado_conforme", "numeracao_metrica", "multi_cep", "df", "dist_lu > 2000")) {
    cat("\n-- interior: mediana por", cut, "--\n"); print(larga(resumo("NOT ponta", sprintf("(%s) AS corte", cut)), "corte"))
  }
  cat("\n-- interior: mediana por região --\n")
  dbWriteTable(con, "reg", data.frame(estado = names(REGIAO), regiao = REGIAO), overwrite = TRUE)
  dbExecute(con, "CREATE OR REPLACE TEMP TABLE base AS SELECT b.*, r.regiao FROM base b JOIN reg r USING (estado)")
  print(larga(resumo("NOT ponta", "regiao"), "regiao"))
  cat("\n-- caminho do M1 (todos os alvos) --\n")
  print(dbGetQuery(con, "SELECT caminho_m1, count(*) FILTER (metodo = 'm1') n,
      round(median(erro_m) FILTER (metodo = 'm1'), 1) med_m1, round(median(erro_m) FILTER (metodo = 'm1n'), 1) med_m1_sem_trava,
      round(quantile_cont(erro_m, .9) FILTER (metodo = 'm1'), 0) p90_m1, round(quantile_cont(erro_m, .9) FILTER (metodo = 'm1n'), 0) p90_m1_sem_trava,
      round(median(erro_m) FILTER (metodo = 'b1'), 1) med_b1
    FROM base GROUP BY 1 ORDER BY 2 DESC"))
  cat("\n-- distância ao eixo suavizado (descritiva; favorece M4 por construção), interior, mediana m --\n")
  print(larga(dbGetQuery(con, "SELECT forma, metodo, round(median(dist_eixo), 1) AS mediana FROM base WHERE NOT ponta GROUP BY ALL"), "forma"))
  cat("\n-- calibração: % com erro <= desvio_metros reportado --\n")
  print(dbGetQuery(con, sprintf("
    SELECT metodo, round(100 * avg((erro_m <= desvio_med)::INT), 1) AS pct_cobertura_desvio_atual,
           round(median(desvio_med), 1) AS desvio_atual_mediano,
           round(100 * avg((erro_m <= greatest(b1_desvio, dist_lu / 2))::INT) FILTER (dist_lu IS NOT NULL), 1) AS pct_cobertura_proposta
    FROM base WHERE NOT ponta AND metodo IN ('b0', 'w3', 'w5', '%s') GROUP BY 1", VENC)))

  # bootstrap por rua (1.000 reamostras): diferença de mediana, vencedor - B0 e vencedor - B1
  d <- data.table::as.data.table(dbGetQuery(con, sprintf(
    "SELECT sid, tid, metodo, erro_m FROM base WHERE NOT ponta AND metodo IN ('b0', 'b1', 'w3', 'w5', '%s')", VENC)))
  w <- data.table::dcast(d, sid + tid ~ metodo, value.var = "erro_m")
  ids <- unique(w$sid); idx <- split(seq_len(nrow(w)), w$sid)
  set.seed(20261122)
  comp <- c("b0", "b1", "w3", "w5")
  bt <- t(replicate(1000, { s <- unlist(idx[sample(length(ids), replace = TRUE)])
    sapply(comp, function(k) med(w[[VENC]][s]) - med(w[[k]][s])) }))
  cat(sprintf("\nBootstrap por rua (%s, interior, %d ruas), diferença de mediana %s - X:\n", esq, length(ids), VENC))
  for (k in comp) cat(sprintf("  %s - %s = %.1f m [IC95%% %.1f; %.1f]\n", VENC, toupper(k),
    med(w[[VENC]]) - med(w[[k]]), quantile(bt[, k], .025), quantile(bt[, k], .975)))
  arrow::write_parquet(dbGetQuery(con, "SELECT * FROM base"), file.path(OUT2, sprintf("base_%s.parquet", esq)))
}

# ---------------------------------------------------------------- P0 ------------------------------
cat("\n================ P0 ================\n")
orig <- as.data.frame(arrow::read_parquet(file.path(OUT2, "large_sample_B0_orig.parquet")))
amostra20 <- as.data.frame(arrow::read_parquet(SAMPLE))
orig$numero_p <- suppressWarnings(enderecobr::padronizar_numeros(amostra20$numero[match(orig$id, amostra20$id)], formato = "integer"))
dbWriteTable(con, "p0a_chave", orig[grepl("^(da|pa)", orig$tipo_resultado),
  c("id", "estado_encontrado", "municipio_encontrado", "logradouro_encontrado", "numero_p", "tipo_resultado")], overwrite = TRUE)
dbExecute(con, sprintf("CREATE OR REPLACE TEMP TABLE vu AS SELECT * FROM verdade_unica"))
for (base in c("a", "b")) {
  dbExecute(con, "CREATE OR REPLACE TEMP TABLE p0 (metodo VARCHAR, id BIGINT, tipo VARCHAR, erro_m DOUBLE)")
  for (m in c("B0", paste0("W", EXPOENTES), "B1", "B2", "M1", "M1N", "M2", "M4")) {
    f <- file.path(OUT2, sprintf("p0%s_%s.parquet", base, m))
    if (base == "a") dbExecute(con, sprintf("
      INSERT INTO p0 SELECT '%s', k.id, k.tipo_resultado, hav(r.lat, r.lon, v.lat_v, v.lon_v)
      FROM p0a_chave k JOIN read_parquet('%s') r USING (id)
      JOIN vu v ON v.estado = k.estado_encontrado AND v.municipio = k.municipio_encontrado
               AND v.logradouro = k.logradouro_encontrado AND v.numero = k.numero_p", tolower(m), f))
    else dbExecute(con, sprintf("
      INSERT INTO p0 SELECT '%s', r.id, r.tipo_resultado, hav(r.lat, r.lon, v.lat_v, v.lon_v)
      FROM read_parquet('%s') r JOIN read_parquet('%s') v USING (id)
      WHERE regexp_matches(r.tipo_resultado, '^(da|pa)')", tolower(m), f, file.path(OUT2, "p0b_input.parquet")))
  }
  cat(sprintf("\n-- P0%s: tipos (B0) --\n", base))
  print(dbGetQuery(con, "SELECT tipo, count(*) n FROM p0 WHERE metodo = 'b0' GROUP BY 1 ORDER BY 2 DESC"))
  cat(sprintf("\n-- P0%s: erro por método --\n", base))
  print(dbGetQuery(con, "
    WITH b1 AS (SELECT id, erro_m AS e1 FROM p0 WHERE metodo = 'b1')
    SELECT metodo, count(*) n, round(median(erro_m), 1) mediana, round(quantile_cont(erro_m, .9), 0) p90,
           round(100 * avg((erro_m < 50)::INT), 1) pct_50m, round(100 * avg((erro_m > e1 + 50)::INT), 1) pct_pior_b1_50m
    FROM p0 JOIN b1 USING (id) GROUP BY 1 ORDER BY mediana"))
  arrow::write_parquet(dbGetQuery(con, "SELECT * FROM p0"), file.path(OUT2, sprintf("p0%s_erros.parquet", base)))
}

# ---------------------------------------------------------------- tempo ---------------------------
cat("\n================ TEMPO ================\n")
print(read.csv(file.path(SAI, "tempo_isolado.csv")))
print(read.csv(file.path(SAI, "tempo_ponta_a_ponta.csv")))
sink()

# ---------------------------------------------------------------- figuras -------------------------
pal <- c(b0 = "#2a78d6", b1 = "#eb6834", m1n = "#1baf7a", w3 = "#6250d6", b2 = "#eda100", w5 = "#e87ba4")
fig_a <- dbGetQuery(con, sprintf("
  WITH b AS (SELECT 'P1' AS esq, * FROM read_parquet('%1$s/base_P1.parquet')
             UNION ALL BY NAME SELECT 'P2' AS esq, * FROM read_parquet('%1$s/base_P2.parquet')),
  d AS (SELECT *, ntile(10) OVER (PARTITION BY esq, metodo ORDER BY curvatura_t) AS decil
        FROM b WHERE NOT ponta AND curvatura_t IS NOT NULL AND forma <> 'desordenada')
  SELECT esq, metodo, decil, median(curvatura_t) AS curv, median(erro_m) AS mediana, count(*) n
  FROM d WHERE metodo IN ('b0', 'w3', 'w5', 'b1', 'b2', 'm1n') GROUP BY ALL", OUT2))
fig_a$esq <- factor(fig_a$esq, levels = c("P1", "P2"), labels = c("P1 — retira 1 número", "P2 — retira ±10 números e pontos a ≤ 5 m"))
ga <- ggplot(fig_a, aes(decil, mediana, colour = metodo)) +
  geom_line(linewidth = 0.7) + geom_point(size = 2.2) +
  facet_wrap(~esq, scales = "free_y") +
  scale_colour_manual(values = pal, labels = ROT, name = NULL) +
  scale_x_continuous(breaks = 1:10, labels = function(b) ifelse(b %in% c(1, 10), c("1\nreta", "10\ncurva")[(b == 10) + 1], b)) +
  labs(x = "decil de curvatura da rua (calculada sem o alvo)", y = "erro mediano (m)",
       title = "Erro da interpolação por curvatura da rua (alvos internos, ruas não desordenadas)") +
  theme_minimal(base_size = 10) +
  theme(plot.background = element_rect(fill = "#fcfcfb", colour = NA), panel.grid.minor = element_blank(),
        panel.grid.major.x = element_blank(), legend.position = "top", text = element_text(colour = "#0b0b0b"),
        axis.text = element_text(colour = "#52514e"), strip.text = element_text(face = "bold"))
ggsave(file.path(SAI, "fig_a_erro_por_curvatura.png"), ga, width = 10, height = 4.6, dpi = 150)

# (b) ruas-âncora: verdade e estimativas P1 de B0, W3, B1 e vencedor
anc <- dbGetQuery(con, sprintf("
  SELECT t.tid, a.logradouro, a.cep, t.numero, t.lat_v, t.lon_v, r.b0_lat, r.b0_lon, r.w3_lat, r.w3_lon, r.b1_lat, r.b1_lon,
         r.%1$s_lat AS venc_lat, r.%1$s_lon AS venc_lon
  FROM alvos t JOIN amostra a USING (sid) JOIN read_parquet('%2$s/res_P1.parquet') r USING (tid)
  WHERE t.ancora AND a.n_pontos >= 15", VENC, OUT2))
l <- do.call(rbind, lapply(c("b0", "w3", "b1", "venc"), function(m) data.frame(
  rua = paste0(sub("^AVENIDA", "AV.", anc$logradouro), " (", anc$cep, ")"), metodo = m, lon_v = anc$lon_v, lat_v = anc$lat_v,
  lon = anc[[paste0(m, "_lon")]], lat = anc[[paste0(m, "_lat")]])))
l$metodo <- factor(l$metodo, levels = c("b0", "w3", "b1", "venc"), labels = c(ROT["b0"], ROT["w3"], ROT["b1"], ROT[VENC]))
l$erro <- with(l, 2 * 6371008.8 * asin(sqrt(sin((lat - lat_v) * pi / 360)^2 + cos(lat * pi / 180) *
                 cos(lat_v * pi / 180) * sin((lon - lon_v) * pi / 360)^2)))
lab <- aggregate(erro ~ rua + metodo, l, function(e) sprintf("mediana %.0f m", median(e)))
# metros, centrados por rua; mesma janela quadrada nos 4 painéis de cada rua (forma não distorcida)
for (r in unique(l$rua)) { i <- l$rua == r; lat0 <- median(l$lat_v[i]); lon0 <- median(l$lon_v[i])
  k <- 111320 * cos(lat0 * pi / 180)
  l$xv[i] <- (l$lon_v[i] - lon0) * k; l$yv[i] <- (l$lat_v[i] - lat0) * 110540
  l$x[i] <- (l$lon[i] - lon0) * k;   l$y[i] <- (l$lat[i] - lat0) * 110540 }
caixa <- do.call(rbind, lapply(split(l, l$rua), function(d) {
  h <- max(abs(c(d$xv, d$yv, d$x, d$y))) * 1.05
  expand.grid(rua = d$rua[1], metodo = levels(l$metodo), x = c(-h, h), y = c(-h, h)) }))
caixa$metodo <- factor(caixa$metodo, levels = levels(l$metodo))
l$painel <- interaction(l$metodo, l$rua, sep = " · ", lex.order = FALSE)
caixa$painel <- interaction(caixa$metodo, caixa$rua, sep = " · ", lex.order = FALSE)
lab$painel <- interaction(lab$metodo, lab$rua, sep = " · ", lex.order = FALSE)
gb <- ggplot(l) +
  geom_blank(data = caixa, aes(x, y)) +
  geom_segment(aes(xv, yv, xend = x, yend = y), colour = "#e34948", linewidth = 0.3, alpha = 0.7) +
  geom_point(aes(xv, yv), colour = "#9a9994", size = 0.8) +
  geom_point(aes(x, y), colour = "#e34948", size = 1) +
  geom_text(data = lab, aes(x = -Inf, y = Inf, label = erro), hjust = -0.05, vjust = 1.3, size = 3, colour = "#52514e") +
  facet_wrap(~painel, scales = "free", ncol = 4) +
  labs(title = "Ruas-âncora da issue #10 — cada número retirado (P1) e reestimado",
       subtitle = "cinza: posição verdadeira no CNEFE · vermelho: estimativa · traço: erro") +
  theme_void(base_size = 9) + theme(plot.background = element_rect(fill = "#fcfcfb", colour = NA),
    strip.text = element_text(face = "bold", size = 7.5, margin = margin(4, 4, 4, 4)),
    plot.title = element_text(face = "bold"), aspect.ratio = 1)
ggsave(file.path(SAI, "fig_b_ruas_ancora.png"), gb, width = 13, height = 10.5, dpi = 150)

# ------------------------------------------- sensibilidade ao expoente do IDW (issue #36) -----------
# k = 1 é o B0 atual; B1 (vizinho) e M1n entram como referência
ks <- c(1L, EXPOENTES); mk <- c("b0", paste0("w", EXPOENTES))
refs <- c("b1", "b2", "m1n")
sens <- dbGetQuery(con, sprintf("
  WITH b AS (SELECT 'P1' AS esq, metodo, erro_m, ponta, forma FROM read_parquet('%1$s/base_P1.parquet')
             UNION ALL BY NAME SELECT 'P2' AS esq, metodo, erro_m, ponta, forma FROM read_parquet('%1$s/base_P2.parquet')),
  p0 AS (SELECT 'P0a' AS conj, metodo, erro_m FROM read_parquet('%1$s/p0a_erros.parquet')
         UNION ALL SELECT 'P0b', metodo, erro_m FROM read_parquet('%1$s/p0b_erros.parquet')),
  l AS (
    SELECT esq || ' internos' AS conj, metodo, erro_m FROM b WHERE NOT ponta
    UNION ALL SELECT esq || ' pontas', metodo, erro_m FROM b WHERE ponta
    UNION ALL SELECT 'P2 curvas (internos)', metodo, erro_m FROM b WHERE NOT ponta AND esq = 'P2' AND forma = 'curva'
    UNION ALL SELECT conj, metodo, erro_m FROM p0)
  SELECT conj, metodo, count(*) n, median(erro_m) AS mediana, quantile_cont(erro_m, 0.9) AS p90
  FROM l WHERE metodo IN (%2$s) GROUP BY ALL", OUT2, paste(sprintf("'%s'", c(mk, refs)), collapse = ", ")))
tempo <- read.csv(file.path(SAI, "tempo_isolado.csv"))
tempo <- tempo[tempo$metodo %in% toupper(c(mk, "b1", "m1")) & tempo$n %in% c(1e6, 1e7), ]
tempo <- tempo[!duplicated(tempo[, c("metodo", "n")], fromLast = TRUE), ]   # última medição de cada
sink(file.path(SAI, "sensibilidade_expoente.txt"), split = TRUE)
cat("Sensibilidade ao expoente k do IDW 1/|Δn|^k (k = 1 é o B0 atual). Erro em m.\n\n")
for (v in c("mediana", "p90")) {
  w <- reshape(transform(sens[, c("conj", "metodo", v)], val = round(get(v), 1))[, c("conj", "metodo", "val")],
               idvar = "metodo", timevar = "conj", direction = "wide")
  names(w) <- sub("val.", "", names(w), fixed = TRUE)
  w$k <- ifelse(w$metodo %in% mk, ks[match(w$metodo, mk)], NA)
  w <- w[order(is.na(w$k), w$k, w$metodo), c("metodo", "k", setdiff(names(w), c("metodo", "k")))]
  cat("--", v, "--\n"); print(w, row.names = FALSE); cat("\n")
}
cat("-- tempo isolado (s; M1 = M1n) --\n"); print(tempo[, c("metodo", "n", "seg_mediana", "pico_gb")], row.names = FALSE)
sink()
conj_ord <- c("P1 internos", "P2 internos", "P2 curvas (internos)", "P1 pontas", "P2 pontas", "P0a", "P0b")
s <- sens[sens$metodo %in% mk, ]; s$k <- ks[match(s$metodo, mk)]
r <- sens[sens$metodo %in% c("b1", "m1n"), ]
r$ref <- ifelse(r$metodo == "b1", "B1 vizinho", "M1 sem trava")
s$conj <- factor(s$conj, conj_ord); r$conj <- factor(r$conj, conj_ord)
gc <- ggplot(s, aes(k, mediana)) +
  geom_hline(data = r, aes(yintercept = mediana, colour = ref), linewidth = 0.6, linetype = "22") +
  geom_line(colour = "#2a78d6", linewidth = 0.7) + geom_point(colour = "#2a78d6", size = 2.2) +
  facet_wrap(~conj, scales = "free_y", ncol = 4) +
  scale_colour_manual(values = c("B1 vizinho" = "#eb6834", "M1 sem trava" = "#1baf7a"), name = "referência") +
  scale_x_continuous(breaks = ks) +
  labs(x = "expoente k do peso 1/|Δn|^k (k = 1: método atual)", y = "erro mediano (m)",
       title = "Sensibilidade do IDW ao expoente — erro mediano por conjunto de teste") +
  theme_minimal(base_size = 10) +
  theme(plot.background = element_rect(fill = "#fcfcfb", colour = NA), panel.grid.minor = element_blank(),
        legend.position = "top", text = element_text(colour = "#0b0b0b"),
        axis.text = element_text(colour = "#52514e"), strip.text = element_text(face = "bold"))
ggsave(file.path(SAI, "fig_c_sensibilidade_expoente.png"), gc, width = 12, height = 6, dpi = 150)
dbDisconnect(con, shutdown = TRUE)
