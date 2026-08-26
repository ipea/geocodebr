# skip tests because they take too much time
skip_if(Sys.getenv("TEST_ONE") != "")
testthat::skip_on_cran()
testthat::skip_if_not_installed("arrow")


tester <- function(tabela = "municipio_localidade", verboso = TRUE, cache = TRUE) {
  download_cnefe(tabela, verboso, cache)
}

test_that("errors with incorrect input", {
  expect_error(tester(tabela = 'banana'))
  expect_error(tester(tabela = 1))
  expect_error(tester(tabela = NA))
  expect_error(tester(tabela = c(TRUE, TRUE)))

  expect_error(tester(verboso = 1))
  expect_error(tester(verboso = NA))
  expect_error(tester(verboso = c(TRUE, TRUE)))

  expect_error(tester(cache = 1))
  expect_error(tester(cache = NA))
  expect_error(tester(cache = c(TRUE, TRUE)))
})

test_that("returns the path to the directory where the files were saved", {
  result <- tester()
  expect_identical(result, file.path(listar_pasta_cache()))

  result <- tester(tabela = "municipio_cep")
  expect_identical(result, file.path(listar_pasta_cache()))

})

test_that("accepts a vector with more than one tabela name", {
  local_mocked_bindings(
    perform_requests_in_parallel = function(...) TRUE
  )

  result <- tester(tabela = c("municipio", "municipio_cep"), cache = FALSE)
  expect_true(
    grepl(file.path(fs::path_norm(tempdir()), "geocodebr_temp"), result)
  )
})

test_that("a vector with a duplicated tabela name does not error nor download twice", {
  local_mocked_bindings(
    perform_requests_in_parallel = function(...) TRUE
  )

  expect_no_error(
    tester(tabela = c("municipio", "municipio"), cache = FALSE)
  )
})

test_that("a vector with any invalid tabela name errors, listing what was invalid", {
  expect_error(tester(tabela = c("municipio", "banana"), cache = FALSE))
})

test_that("'todas' cannot be combined with other tabela names", {
  expect_error(tester(tabela = c("todas", "municipio"), cache = FALSE))
})

test_that("an empty tabela vector does not error -- it just downloads nothing", {
  # cenario degenerado (ver R/utils.R, tabelas_necessarias()): se
  # campos_nao_declarados exclui todo match_type, download_cnefe() recebe
  # character(0) e so precisa devolver o cache_dir sem baixar nada, sem
  # travar com erro cru de validacao
  expect_no_error(tester(tabela = character(0), cache = FALSE))
})

test_that("cache usage is controlled by the cache argument", {

  result <- tester(cache = TRUE)

  expect_identical(
    result,
    as.character( fs::path(tools::R_user_dir("geocodebr", which = "cache")))
    )

  # using a mocked binding for perform_requests_in_parallel here just to save us
  # some time. as long as none of its elements is a failed request, the function
  # will make download_files return the path to the files that would be
  # downloaded, which is basically what we want to test here
  local_mocked_bindings(
    perform_requests_in_parallel = function(...) TRUE
  )

  result <- tester(cache = FALSE)
  expect_true(
    grepl(file.path(fs::path_norm(tempdir()), "geocodebr_temp"), result)
  )
})

# geocode_core() -> download_cnefe() wiring -------------------------------
#
# identical() ponta a ponta (feito em outra verificacao, nao aqui) confirma
# que o RESULTADO do geocode nao muda, mas nao pegaria uma falha de wiring
# (ex.: geocode.R continuar passando 'todas' por engano) -- o resultado do
# matching seria o mesmo de qualquer jeito, so o download nao teria sido
# reduzido. Estes dois testes mockam download_cnefe() e abortam logo depois
# de capturar o argumento `tabela`, sem rodar o resto do pipeline (sem
# precisar de dados do CNEFE nem de rede).

test_that("geocode_core() passa tabelas_necessarias(), nao 'todas', quando todos os campos sao declarados", {
  tabela_capturada <- NULL

  local_mocked_bindings(
    download_cnefe = function(tabela, verboso, cache) {
      tabela_capturada <<- tabela
      stop("sentinela: abortando geocode_core() apos capturar `tabela`")
    }
  )

  input_df <- read.csv(
    system.file("extdata/small_sample.csv", package = "geocodebr")
  )[1:2, ]

  campos <- definir_campos(
    logradouro = "nm_logradouro",
    numero = "Numero",
    cep = "Cep",
    localidade = "Bairro",
    municipio = "nm_municipio",
    estado = "nm_uf"
  )

  expect_error(
    geocode_core(
      enderecos = input_df,
      campos_endereco = campos,
      resultado_completo = FALSE,
      resolver_empates = TRUE,
      resultado_sf = FALSE,
      h3_res = NULL,
      padronizar_enderecos = TRUE,
      verboso = FALSE,
      cache = TRUE,
      n_cores = 1
    ),
    "sentinela"
  )

  # todos os 6 campos declarados -> campos_nao_declarados vazio -> as 8
  # tabelas distribuidas, nao o sentinela 'todas'
  tabelas_distribuidas <- c(
    "municipio",
    "municipio_cep",
    "municipio_cep_localidade",
    "municipio_localidade",
    "municipio_logradouro_cep_localidade",
    "municipio_logradouro_localidade",
    "municipio_logradouro_numero_cep_localidade",
    "municipio_logradouro_numero_localidade"
  )

  expect_false(identical(tabela_capturada, "todas"))
  expect_setequal(tabela_capturada, tabelas_distribuidas)
})

test_that("geocode_core() passa um subconjunto reduzido quando logradouro/numero nao sao declarados", {
  tabela_capturada <- NULL

  local_mocked_bindings(
    download_cnefe = function(tabela, verboso, cache) {
      tabela_capturada <<- tabela
      stop("sentinela: abortando geocode_core() apos capturar `tabela`")
    }
  )

  input_df <- read.csv(
    system.file("extdata/small_sample.csv", package = "geocodebr")
  )[1:2, ]

  campos <- definir_campos(
    cep = "Cep",
    localidade = "Bairro",
    municipio = "nm_municipio",
    estado = "nm_uf"
  )

  expect_error(
    geocode_core(
      enderecos = input_df,
      campos_endereco = campos,
      resultado_completo = FALSE,
      resolver_empates = TRUE,
      resultado_sf = FALSE,
      h3_res = NULL,
      padronizar_enderecos = TRUE,
      verboso = FALSE,
      cache = TRUE,
      n_cores = 1
    ),
    "sentinela"
  )

  # logradouro/numero nao declarados -> so as 4 tabelas sem numero no nome,
  # excluindo justamente as 2 maiores (municipio_logradouro_numero_*)
  tabelas_sem_logradouro_numero <- c(
    "municipio",
    "municipio_cep",
    "municipio_cep_localidade",
    "municipio_localidade"
  )

  expect_false(identical(tabela_capturada, "todas"))
  expect_setequal(tabela_capturada, tabelas_sem_logradouro_numero)
})

# test_that("errors if could not download one or more files", {
#   local_mocked_bindings(
#     perform_requests_in_parallel = function(...) {
#       httr2::req_perform_parallel(
#         list(httr2::request("FAILURE")),
#         on_error = "continue"
#       )
#     }
#   )
#
#   expect_error(
#     tester(cache = FALSE),
#     class = "geocodebr_error_cnefe_download_failed"
#   )
#
#   expect_snapshot(tester(cache = FALSE), error = TRUE, cnd_class = TRUE)
# })
