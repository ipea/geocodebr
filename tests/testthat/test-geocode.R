# skip tests because they take too much time
skip_if(Sys.getenv("TEST_ONE") != "")
testthat::skip_on_cran()
testthat::skip_if_not_installed("arrow")


data_path <- system.file("extdata/small_sample.csv", package = "geocodebr")
input_df <- read.csv(data_path)

campos <- geocodebr::definir_campos(
  logradouro = "nm_logradouro",
  numero = "Numero",
  cep = "Cep",
  localidade = "Bairro",
  municipio = "nm_municipio",
  estado = "nm_uf"
)

tester <- function(enderecos = input_df,
                   campos_endereco = campos,
                   resultado_completo = FALSE,
                   resolver_empates = FALSE,
                   resultado_sf = FALSE,
                   h3_res = NULL,
                   padronizar_enderecos = TRUE,
                   verboso = FALSE,
                   cache = TRUE,
                   n_cores = 1) {
  geocode(
    enderecos,
    campos_endereco,
    resultado_completo,
    resolver_empates,
    resultado_sf,
    h3_res,
    padronizar_enderecos,
    verboso,
    cache,
    n_cores
  )
}

test_that("expected output", {

  std_output <- tester()

  # find expected match cases
  match_types_found <- unique(std_output$tipo_resultado)
  testthat::expect_true(length(match_types_found) == 17)

  # full results
  full_output <- tester(resultado_completo = TRUE)


  all_cols_completas <- c("lat", "lon", "precisao", "tipo_resultado",
    "desvio_metros", "endereco_encontrado", "logradouro_encontrado",
    "numero_encontrado", "cep_encontrado", "localidade_encontrada",
    "municipio_encontrado", "estado_encontrado", "similaridade_logradouro",
    "contagem_cnefe", "empate", "cod_setor")

  testthat::expect_true(all(all_cols_completas %in% names(full_output)))

  # add h3
  std_output_h3 <- tester(h3_res = c(3,4))
  testthat::expect_true(all(c('h3_03', 'h3_04') %in% names(std_output_h3)))

  # output in sf format
  sf_output <- tester(resultado_sf = TRUE)
  testthat::expect_true(is(sf_output , 'sf'))
})



test_that("partial address in the input", {

  df_parcial <- data.frame(
    uf        = c("PA", "PA"),
    municipio = c("Santarem", "Santarem"),
    cep_estab = c("68005000", "68000000"),
    stringsAsFactors = FALSE
  )

  campos_parcial <- geocodebr::definir_campos(
    estado    = "uf",
    municipio = "municipio",
    cep       = "cep_estab"
  )

  testthat::succeed(
    tester(enderecos = df_parcial, campos_endereco = campos_parcial)
  )

  # missing critical column uf of muni
  testthat::expect_error(
    geocodebr::definir_campos(
      # estado    = "uf",
      municipio = "municipio")
    )

  # quando colunas de dados e campos nao correspondem
  df_parcial2 <- data.frame(
     uf        = c("PA", "PA"),
    municipio = c("Santarem", "Santarem"),
    #cep_estab = c("68005000", "68000000"),
    stringsAsFactors = FALSE
  )

  testthat::expect_error(
    tester(enderecos = df_parcial2, campos_endereco = campos_parcial)
  )


})


test_that("precisao Ipea", {

  df_ipea <- data.frame(
    uf        = c("DF", "RJ"),
    municipio = c("Brasilia", "Rio de Janeiro"),
    cep = c("70390-025", "20071-001"),
    stringsAsFactors = FALSE
  )

  campos_ipea <- geocodebr::definir_campos(
    estado    = "uf",
    municipio = "municipio",
    cep       = "cep"
  )

  out_ipea <- tester(enderecos = df_ipea, campos_endereco = campos_ipea)

  testthat::expect_true(all(out_ipea$desvio_metros < 115))

})



test_that("argumento padronizar endereco", {

  # erro se input nao estiver padronizado
  testthat::expect_error( tester(padronizar_enderecos = FALSE) )

  # sucesso se tiver sido padronizado
  campos2 <- enderecobr::correspondencia_campos(
    logradouro = "nm_logradouro",
    numero = "Numero",
    cep = "Cep",
    bairro = "Bairro",
    municipio = "nm_municipio",
    estado = "nm_uf"
  )

  input_padr <- enderecobr::padronizar_enderecos(
    enderecos = input_df,
    campos_do_endereco = campos2,
    formato_estados = "sigla",
    formato_numeros = 'integer'
    )

  testthat::succeed(
    tester(enderecos = input_padr, padronizar_enderecos = FALSE)
  )

})


test_that("test empates", {

  # com empates
  std_output <- tester(resolver_empates = FALSE)
  testthat::expect_true(nrow(std_output) > nrow(input_df))

  # resolvendo empates
  std_output <- tester(verboso = TRUE, resolver_empates = TRUE)
  testthat::expect_true(nrow(std_output) == nrow(input_df))

  # output ordenado como input
  testthat::expect_true( all(std_output$id == 1:nrow(input_df)) )

  # add h3
  std_output_h3 <- tester(h3_res = 3)
  testthat::expect_true('h3_03' %in% names(std_output_h3))
})

# test_that("test no messages", {
#
#   testthat::expect_no_message(
#     testthat::expect_warning(
#       std_output <- tester(verboso = FALSE,
#                            resolver_empates = FALSE)
#                                )
#     )
#
#    testthat::expect_no_message(
#     std_output <- tester(verboso = FALSE, resolver_empates = TRUE)
#                             )
# })


test_that("errors with incorrect input", {


  expect_error(tester(unclass(input_df)))

  # df com caracter especial nas colunas
  input_df2 <- input_df |> mutate("col!test" = 1)
  expect_error(tester(enderecos = input_df2))

  expect_error(tester(campos_endereco = 1))
  expect_error(tester(campos_endereco = c(hehe = "nm_logradouro")))
  expect_error(tester(campos_endereco = c(logradouro = "hehe")))

  expect_error(tester(resultado_completo = 1))
  expect_error(tester(resultado_completo = NA))
  expect_error(tester(resultado_completo = c(TRUE, TRUE)))

  expect_error(tester(resolver_empates = 1))
  expect_error(tester(resolver_empates = NA))
  expect_error(tester(resolver_empates = c(TRUE, TRUE)))

  expect_error(tester(resultado_sf = 1))
  expect_error(tester(resultado_sf = NA))
  expect_error(tester(resultado_sf = c(TRUE, TRUE)))

  expect_error(tester(padronizar_enderecos = "a"))
  expect_error(tester(padronizar_enderecos = 50))
  expect_error(tester(padronizar_enderecos = Inf))

  expect_error(tester(h3_res = "a"))
  expect_error(tester(h3_res = 50))
  expect_error(tester(h3_res = Inf))

  expect_error(tester(n_cores = "a"))
  expect_error(tester(n_cores = 0))
  expect_error(tester(n_cores = Inf))

  expect_error(tester(verboso = 1))
  expect_error(tester(verboso = NA))
  expect_error(tester(verboso = c(TRUE, TRUE)))

  expect_error(tester(cache = 1))
  expect_error(tester(cache = NA))
  expect_error(tester(cache = c(TRUE, TRUE)))
})

