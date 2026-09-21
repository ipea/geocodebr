# Invariantes de dados que sustentam a otimizacao do GROUP BY das queries
# ponderadas (match_weighted_cases() / match_weighted_cases_probabilistic()).
#
# Nessas queries o GROUP BY agrupa por (tempidgeocodebr, numero, <cols_livres>)
# em vez de pela string `endereco_encontrado`. Isso so devolve o mesmo resultado
# se, nas duas tabelas de referencia com `numero`:
#
#   (i)   o regex ', \d+ -' casa exatamente uma vez em cada `endereco_completo`
#         (senao REGEXP_REPLACE trocaria outro trecho da string);
#   (ii)  `endereco_completo` normalizado (com o numero mascarado) e constante
#         dentro de cada grupo de colunas nao-numero -- ou seja, a string nao
#         carrega nenhuma informacao extra alem dessas colunas;
#   (iii) dentro das colunas fixadas pelo join, valores distintos das colunas
#         livres (`cep`/`localidade`) geram strings distintas (bijecao) -- e o
#         que garante que agrupar por elas nao junta enderecos diferentes.
#
# Os testes rodam so quando o cache do CNEFE esta presente (sao ~50M linhas por
# tabela, lidas direto do parquet pelo DuckDB).

pasta_cache_release <- function() {
  fs::path(
    geocodebr::listar_pasta_cache(),
    paste0("geocodebr_data_release_", geocodebr:::data_release)
  )
}

parquet_numero <- function() {
  arquivos <- fs::path(
    pasta_cache_release(),
    paste0(
      c(
        "municipio_logradouro_numero_cep_localidade",
        "municipio_logradouro_numero_localidade"
      ),
      ".parquet"
    )
  )
  arquivos[fs::file_exists(arquivos)]
}

# colunas nao-numero de cada tabela (o grupo dentro do qual o endereco
# normalizado precisa ser constante) e a coluna livre de cada match_type
# ponderado que usa aquela tabela
grupos_por_tabela <- list(
  municipio_logradouro_numero_cep_localidade = list(
    grupo = c("estado", "municipio", "logradouro", "cep", "localidade"),
    # da02/pa02: join sem localidade -> localidade e a coluna livre
    join_fixo = c("estado", "municipio", "logradouro", "cep"),
    livre = "localidade"
  ),
  municipio_logradouro_numero_localidade = list(
    grupo = c("estado", "municipio", "logradouro", "localidade"),
    # da04: join sem localidade -> localidade e a coluna livre
    join_fixo = c("estado", "municipio", "logradouro"),
    livre = "localidade"
  )
)

test_that("invariantes de dados do GROUP BY estreito das queries ponderadas", {
  skip_on_cran()
  skip_if_not_installed("duckdb")

  arquivos <- parquet_numero()
  skip_if_not(
    length(arquivos) == 2,
    "cache do CNEFE (tabelas com numero) ausente"
  )

  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE), add = TRUE)

  for (arquivo in arquivos) {
    tabela <- fs::path_ext_remove(fs::path_file(arquivo))
    spec <- grupos_por_tabela[[tabela]]
    src <- glue::glue("read_parquet('{arquivo}')")
    grupo <- paste(spec$grupo, collapse = ", ")
    join_fixo <- paste(spec$join_fixo, collapse = ", ")
    norm <- "REGEXP_REPLACE(endereco_completo, ', \\d+ -', '#')"

    # (i) o regex casa exatamente uma vez por linha
    n_regex_ruim <- DBI::dbGetQuery(
      con,
      glue::glue(
        "SELECT COUNT(*) AS n FROM {src}
         WHERE LEN(REGEXP_EXTRACT_ALL(endereco_completo, ', \\d+ -')) <> 1"
      )
    )$n
    expect_identical(as.numeric(n_regex_ruim), 0, label = glue::glue("{tabela}: regex 1x"))

    # (ii) endereco normalizado constante dentro do grupo de colunas nao-numero
    n_grupo_ruim <- DBI::dbGetQuery(
      con,
      glue::glue(
        "SELECT COUNT(*) AS n FROM (
           SELECT {grupo} FROM {src}
           GROUP BY {grupo}
           HAVING COUNT(DISTINCT {norm}) > 1
         )"
      )
    )$n
    expect_identical(
      as.numeric(n_grupo_ruim), 0,
      label = glue::glue("{tabela}: endereco constante no grupo")
    )

    # (iii) dentro das colunas fixadas pelo join, bijecao entre os valores
    # distintos da coluna livre e as strings normalizadas distintas
    n_bijecao_ruim <- DBI::dbGetQuery(
      con,
      glue::glue(
        "SELECT COUNT(*) AS n FROM (
           SELECT {join_fixo} FROM {src}
           GROUP BY {join_fixo}
           HAVING COUNT(DISTINCT COALESCE({spec$livre}, '<NULO>')) <> COUNT(DISTINCT {norm})
         )"
      )
    )$n
    expect_identical(
      as.numeric(n_bijecao_ruim), 0,
      label = glue::glue("{tabela}: bijecao {spec$livre} <-> endereco")
    )
  }
})
