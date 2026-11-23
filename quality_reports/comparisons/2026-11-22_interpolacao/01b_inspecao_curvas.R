# Inspeção visual da classificação de forma (variante 3: curvatura PCA robusta + classe 'desordenada')
# 12 'curva' logo acima do corte, 12 'intermediaria' logo abaixo, 8 bem curvas, 8 desordenadas
source("L:/Proj_acess_oport/git_rafa/geocodebr/quality_reports/comparisons/2026-11-22_interpolacao/00_config.R")
library(ggplot2)
con <- con_interp(threads = 8L)
q <- "(SELECT sid, '%s' AS grupo, curvatura, desordem, n_pontos, logradouro FROM amostra
       WHERE n_pontos >= 16 AND %s ORDER BY hash(sid) LIMIT %d)"
sel <- dbGetQuery(con, paste(
  sprintf(q, "1 acima", sprintf("forma = 'curva' AND curvatura < %f", CORTE_CURVA + 0.05), 12),
  sprintf(q, "2 abaixo", sprintf("forma = 'intermediaria' AND curvatura > %f", CORTE_CURVA - 0.05), 12),
  sprintf(q, "3 muito curva", "forma = 'curva' AND curvatura > 0.3", 8),
  sprintf(q, "4 desordenada", "forma = 'desordenada'", 8), sep = " UNION ALL "))
dbWriteTable(con, "sel", sel[, "sid", drop = FALSE], overwrite = TRUE)
pts <- dbGetQuery(con, "SELECT r.sid, r.numero, r.lon * 111320 * cos(radians(r.lat)) AS x, r.lat * 110540 AS y,
    percent_rank() OVER (PARTITION BY r.sid ORDER BY r.numero) AS pos FROM ref r SEMI JOIN sel USING (sid)")
pts <- merge(pts, sel, by = "sid")
# metros, centrados por rua, mesma escala nos dois eixos (forma não distorcida)
pts <- do.call(rbind, lapply(split(pts, pts$sid), function(d) {
  d$x <- d$x - median(d$x); d$y <- d$y - median(d$y); d[order(d$numero), ] }))
pts$painel <- sprintf("%s | c=%.2f d=%.1f n=%d\n%s", pts$grupo, pts$curvatura, pts$desordem,
                      pts$n_pontos, substr(pts$logradouro, 1, 28))
pts$painel <- factor(pts$painel, levels = unique(pts$painel[order(pts$grupo, pts$curvatura)]))
g <- ggplot(pts, aes(x, y, colour = pos)) +
  geom_path(colour = "#b9b8b3", linewidth = 0.3) + geom_point(size = 0.9) +
  scale_colour_gradient(low = "#9ec5f4", high = "#104281", name = "posição do número\n(0 = menor)") +
  facet_wrap(~painel, scales = "free", ncol = 8) +
  theme_void(base_size = 7) + theme(strip.text = element_text(size = 5.5, colour = "#52514e"),
    aspect.ratio = 1, plot.background = element_rect(fill = "#fcfcfb", colour = NA), legend.position = "bottom")
ggsave(file.path(SAI, "inspecao_curvatura.png"), g, width = 14, height = 9.5, dpi = 130)
print(table(sel$grupo))
dbDisconnect(con, shutdown = TRUE)
