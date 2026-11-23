# Gerador de SQL dos métodos de interpolação — usado IGUAL no benchmark isolado (03) e no override do
# geocode() (05). Convenção de colunas da tabela de candidatos (uma linha por número de referência):
#   numero (buscado), numero_cnefe, lat, lon, desvio_metros, e as colunas de janela lat_c, lon_c (eixo
#   suavizado, M4) e rk (posto por |Δn|, M2) — ver janelas_sql().
# Todos os métodos: puro SQL DuckDB, determinísticos (desempates explícitos), portáveis ao Python.

EXPOENTES <- c(2L, 3L, 4L, 5L, 6L, 7L, 9L, 10L, 11L)   # expoentes do IDW testados (issue #36); 1 = B0
METODOS <- c("B0", paste0("W", EXPOENTES), "B1", "B2", "M1", "M2", "M4")

# colunas de janela a acrescentar à tabela de candidatos; `part` = partição de um "alvo"
janelas_sql <- function(part) sprintf(
  "median(lat) OVER (PARTITION BY %1$s ORDER BY numero_cnefe ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING) AS lat_c,
   median(lon) OVER (PARTITION BY %1$s ORDER BY numero_cnefe ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING) AS lon_c,
   row_number() OVER (PARTITION BY %1$s ORDER BY abs(numero - numero_cnefe), numero_cnefe, lat, lon) AS rk", part)

# agregados; `f` = filtro de linhas (ex.: 'mc' = mesma rua-chave), `p` = prefixo dos aliases
agregados_sql <- function(f = "TRUE", p = "") {
  F <- function(cond) sprintf("FILTER (%s AND %s)", f, cond)
  ord1 <- "ORDER BY abs(numero - numero_cnefe), numero_cnefe, lat, lon"
  lin <- c(
    # B0 (atual)
    sprintf("sum(lat / abs(numero - numero_cnefe)) %s / sum(1 / abs(numero - numero_cnefe)) %s AS %sb0_lat", F("TRUE"), F("TRUE"), p),
    sprintf("sum(lon / abs(numero - numero_cnefe)) %s / sum(1 / abs(numero - numero_cnefe)) %s AS %sb0_lon", F("TRUE"), F("TRUE"), p),
    sprintf("avg(desvio_metros) %s AS %sdesvio_med", F("TRUE"), p),
    # Wk (issue #36): o mesmo IDW do B0 com expoente k em |Δn| (sensibilidade: k em EXPOENTES)
    unlist(lapply(EXPOENTES, function(k) sprintf(
      "sum(%1$s / pow(abs(numero - numero_cnefe), %2$d)) %3$s / sum(1 / pow(abs(numero - numero_cnefe), %2$d)) %3$s AS %4$sw%2$d_%1$s",
      c("lat", "lon"), k, F("TRUE"), p))),
    # B1 (vizinho mais próximo)
    sprintf("first(lat %s) %s AS %sb1_lat", ord1, F("TRUE"), p),
    sprintf("first(lon %s) %s AS %sb1_lon", ord1, F("TRUE"), p),
    sprintf("first(desvio_metros %s) %s AS %sb1_desvio", ord1, F("TRUE"), p),
    sprintf("count(*) %s AS %sn_cand", F("TRUE"), p),
    # M2 (mediana dos k mais próximos)
    sprintf("median(lat) %s AS %sm2_lat", F(sprintf("rk <= %d", K_M2)), p),
    sprintf("median(lon) %s AS %sm2_lon", F(sprintf("rk <= %d", K_M2)), p))
  # vizinhos inferior (L) / superior (U): qualquer lado (sufixo ''), mesmo lado ('s')
  for (lado in c("", "s")) {
    cl <- if (lado == "s") "numero_cnefe % 2 = numero % 2 AND " else ""
    lo <- paste0(cl, "numero_cnefe < numero"); hi <- paste0(cl, "numero_cnefe > numero")
    lin <- c(lin,
      sprintf("max(numero_cnefe) %s AS %snl%s", F(lo), p, lado),
      sprintf("arg_max(lat, numero_cnefe) %s AS %slatl%s", F(lo), p, lado),
      sprintf("arg_max(lon, numero_cnefe) %s AS %slonl%s", F(lo), p, lado),
      sprintf("min(numero_cnefe) %s AS %snu%s", F(hi), p, lado),
      sprintf("arg_min(lat, numero_cnefe) %s AS %slatu%s", F(hi), p, lado),
      sprintf("arg_min(lon, numero_cnefe) %s AS %slonu%s", F(hi), p, lado))
  }
  # M4: mesmos L/U (qualquer lado) sobre o eixo suavizado; nas pontas, o ponto suavizado mais próximo
  lin <- c(lin,
    sprintf("arg_max(lat_c, numero_cnefe) %s AS %slatl_c", F("numero_cnefe < numero"), p),
    sprintf("arg_max(lon_c, numero_cnefe) %s AS %slonl_c", F("numero_cnefe < numero"), p),
    sprintf("arg_min(lat_c, numero_cnefe) %s AS %slatu_c", F("numero_cnefe > numero"), p),
    sprintf("arg_min(lon_c, numero_cnefe) %s AS %slonu_c", F("numero_cnefe > numero"), p),
    sprintf("first(lat_c %s) %s AS %sb1_lat_c", ord1, F("TRUE"), p),
    sprintf("first(lon_c %s) %s AS %sb1_lon_c", ord1, F("TRUE"), p))
  paste(lin, collapse = ",\n  ")
}

# expressões finais (sobre o resultado dos agregados). Retorna list(lat=, lon=) por método.
.interp <- function(c, lado, p = "", suf = "") {
  # c = 'lat' ou 'lon'; suf = '' ou '_c' (eixo)
  sprintf("(%1$s%2$sl%5$s%4$s + (numero - %1$snl%3$s) / (%1$snu%3$s - %1$snl%3$s) * (%1$s%2$su%5$s%4$s - %1$s%2$sl%5$s%4$s))",
          p, c, lado, suf, lado)
}
.tem <- function(lado, p = "") sprintf("(%1$snl%2$s IS NOT NULL AND %1$snu%2$s IS NOT NULL)", p, lado)
.salto <- function(lado, p = "") sprintf(
  "(hav(%1$slatl%2$s, %1$slonl%2$s, %1$slatu%2$s, %1$slonu%2$s) > %3$f * (%1$snu%2$s - %1$snl%2$s) + %4$f)",
  p, lado, TRAVA_A, TRAVA_B)
.maisprox <- function(c, lado, p = "") sprintf(
  "(CASE WHEN numero - %1$snl%3$s <= %1$snu%3$s - numero THEN %1$s%2$sl%3$s ELSE %1$s%2$su%3$s END)", p, c, lado)
.bracket_trava <- function(c, lado, p = "") sprintf("CASE WHEN %s THEN %s ELSE %s END",
  .salto(lado, p), .maisprox(c, lado, p), .interp(c, lado, p))

finais_sql <- function(m, c, ponte = FALSE) {
  b1 <- sprintf("b1_%s", c)
  if (grepl("^W[0-9]+$", m)) return(sprintf("%s_%s", tolower(m), c))
  switch(m,
    B0 = sprintf("b0_%s", c),
    B1 = b1,
    B2 = sprintf("CASE WHEN %s THEN %s ELSE %s END", .tem(""), .interp(c, ""), b1),
    M2 = sprintf("m2_%s", c),
    M4 = sprintf("CASE WHEN %s THEN %s ELSE b1_%s_c END", .tem(""),
                 sprintf("(%1$sl_c + (numero - nl) / (nu - nl) * (%1$su_c - %1$sl_c))", c), c),
    # ablação declarada na avaliação: M1 sem a trava de salto
    M1n = sprintf("CASE WHEN %s THEN %s WHEN %s THEN %s ELSE %s END",
                  .tem("s"), .interp(c, "s"), .tem(""), .interp(c, ""), b1),
    M1 = {
      fim <- if (ponte) sprintf("CASE WHEN %s THEN %s WHEN %s THEN %s ELSE %s END",
                                .tem("s", "br_"), .bracket_trava(c, "s", "br_"),
                                .tem("", "br_"), .bracket_trava(c, "", "br_"), b1) else b1
      sprintf("CASE WHEN %s THEN %s WHEN %s THEN %s ELSE %s END",
              .tem("s"), .bracket_trava(c, "s"), .tem(""), .bracket_trava(c, ""), fim)
    })
}

# rótulo do caminho seguido pelo M1 (diagnóstico: quanto cai em fallback)
caminho_m1_sql <- function() sprintf(
  "CASE WHEN %s THEN (CASE WHEN %s THEN 'mesmo_lado_trava' ELSE 'mesmo_lado' END)
        WHEN %s THEN (CASE WHEN %s THEN 'qualquer_lado_trava' ELSE 'qualquer_lado' END)
        ELSE 'ponta_b1' END", .tem("s"), .salto("s"), .tem(""), .salto(""))
