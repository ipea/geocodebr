# P0 — conjunto "real": entradas que caem em interpolação (da0x/pa0x) no geocode() de produção, mas cujo
# número existe exatamente no CNEFE sob outra chave. Rodado ponta a ponta com o override (todas as etapas,
# desempate incluído), um método por vez.
#  P0a: large_sample.parquet (20 mil endereços reais); verdade = ponto exato único de
#       (estado, municipio, logradouro_encontrado, numero) na tabela sem CEP.
#  P0b: 200 mil endereços do CNEFE com o CEP trocado por outro CEP da mesma rua+localidade onde o número
#       não existe (CEP genérico / faixa errada) → dn01 falha, da01 interpola no outro trecho.
# Uso: Rscript 06_p0.R build | Rscript 06_p0.R run
source("L:/Proj_acess_oport/git_rafa/geocodebr/quality_reports/comparisons/2026-11-22_interpolacao/00_config.R")
source(file.path(DIR, "02_metodos_sql.R")); source(file.path(DIR, "05_override.R"))
arg <- commandArgs(TRUE)[1]
P0B <- file.path(OUT2, "p0b_input.parquet")

if (arg == "build") {
  con <- con_interp(threads = 8L)
  dbExecute(con, sprintf("
    CREATE OR REPLACE TABLE p0b AS
    WITH ceps AS (
      SELECT estado, municipio, logradouro, localidade, cep, count(*) AS n FROM ref GROUP BY ALL HAVING n >= 2),
    multi AS (
      SELECT estado, municipio, logradouro, localidade FROM ceps GROUP BY ALL HAVING count(*) >= 2),
    src AS (
      SELECT r.* FROM ref r SEMI JOIN multi USING (estado, municipio, logradouro, localidade)
      QUALIFY row_number() OVER (ORDER BY hash(r.sid, r.numero, '%1$s', 'p0b')) <= 600000),
    par AS (
      SELECT s.estado, s.municipio, s.logradouro, s.localidade, s.numero, s.cep AS cep_verdade,
             s.lat AS lat_v, s.lon AS lon_v, c.cep AS cep_input
      FROM src s JOIN ceps c USING (estado, municipio, logradouro, localidade)
      WHERE c.cep <> s.cep AND NOT EXISTS (SELECT 1 FROM ref r2 WHERE r2.estado = s.estado AND
            r2.municipio = s.municipio AND r2.logradouro = s.logradouro AND r2.localidade = s.localidade AND
            r2.cep = c.cep AND r2.numero = s.numero)
      QUALIFY row_number() OVER (PARTITION BY s.sid, s.numero ORDER BY hash(c.cep, '%1$s')) = 1)
    SELECT row_number() OVER () AS id, * FROM par
    QUALIFY row_number() OVER (ORDER BY hash(estado, municipio, logradouro, numero, '%1$s')) <= 200000", SEED))
  print(dbGetQuery(con, "SELECT count(*), count(DISTINCT estado) FROM p0b"))
  arrow::write_parquet(dbGetQuery(con, "SELECT * FROM p0b"), P0B)
  # verdade do P0a: ponto exato único por (estado, municipio, logradouro, numero), qualquer localidade/CEP
  dbExecute(con, sprintf("
    CREATE OR REPLACE TABLE verdade_unica AS
    SELECT estado, municipio, logradouro, numero, any_value(lat)::DOUBLE AS lat_v, any_value(lon)::DOUBLE AS lon_v
    FROM read_parquet('%s') GROUP BY ALL HAVING count(*) = 1",
    file.path(CACHE, "municipio_logradouro_numero_localidade.parquet")))
  dbDisconnect(con, shutdown = TRUE)
}

if (arg == "run") {
  carregar_geocodebr()
  amostra20 <- as.data.frame(arrow::read_parquet(SAMPLE))
  camposA <- definir_campos(estado = "uf", municipio = "municipio", logradouro = "logradouro",
                            numero = "numero", cep = "cep", localidade = "bairro")
  p0b <- as.data.frame(arrow::read_parquet(P0B))
  camposB <- definir_campos(estado = "estado", municipio = "municipio", logradouro = "logradouro",
                            numero = "numero", cep = "cep_input", localidade = "localidade")
  instala_override()
  tempos <- list()
  for (m in strsplit(Sys.getenv("P0_METODOS", paste(METODOS, collapse = ",")), ",")[[1]]) {
    options(interp_metodo = m)
    for (base in c("A", "B")) {
      x <- if (base == "A") amostra20 else p0b[, c("id", "estado", "municipio", "logradouro", "numero", "cep_input", "localidade")]
      cp <- if (base == "A") camposA else camposB
      t <- system.time(r <- geocode(x, cp, resultado_completo = TRUE, verboso = FALSE, n_cores = N_THREADS))[["elapsed"]]
      tempos[[length(tempos) + 1]] <- data.frame(metodo = m, base = base, n = nrow(x), seg = t)
      keep <- intersect(names(r), c("id", "numero", "estado", "uf", "municipio", "lat", "lon", "tipo_resultado",
                                    "logradouro_encontrado", "desvio_metros", "empate"))
      arrow::write_parquet(r[, keep], file.path(OUT2, sprintf("p0%s_%s.parquet", tolower(base), toupper(m))))
      cat(m, base, round(t, 1), "s\n")
    }
  }
  if (!nzchar(Sys.getenv("P0_METODOS"))) write.csv(do.call(rbind, tempos), file.path(SAI, "tempo_ponta_a_ponta.csv"), row.names = FALSE)
}
