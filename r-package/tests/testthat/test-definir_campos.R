tester <- function(logradouro = NULL,
                   numero = NULL,
                   cep = NULL,
                   localidade = NULL,
                   municipio = NULL,
                   estado = NULL) {
  definir_campos(
    logradouro,
    numero,
    cep,
    localidade,
    municipio,
    estado
  )
}

test_that("definir_campos expected behavior", {

  testthat::expect_vector(
    test <- tester(
    logradouro = 'nm_logradouro',
    numero = 'Numero',
    cep = 'Cep',
    localidade = 'Bairro',
    municipio = 'nm_municipio',
    estado = 'nm_uf')
  )

  testthat::expect_true(
    all(names(test) == c("logradouro","numero", "cep",
                         "localidade", "municipio", "estado"))
  )


})

test_that("errors with incorrect input", {
  expect_error(tester(logradouro = 1))
  expect_error(tester(logradouro = c("aaa", "bbb")))

  expect_error(tester(numero = 1))
  expect_error(tester(numero = c("aaa", "bbb")))

  expect_error(tester(cep = 1))
  expect_error(tester(cep = c("aaa", "bbb")))

  expect_error(tester(localidade = 1))
  expect_error(tester(localidade = c("aaa", "bbb")))

  expect_error(tester(municipio = 1))
  expect_error(tester(municipio = c("aaa", "bbb")))

  expect_error(tester(estado = 1))
  expect_error(tester(estado = c("aaa", "bbb")))
})

test_that("errors when all fields are NULL", {
  expect_error(tester(), class = "geocodebr_error_null_address_fields")

  expect_snapshot(tester(), error = TRUE, cnd_class = TRUE)
})

# test_that("returns a character vector", {
#   expect_identical(
#     tester(
#       logradouro = "Nome_logradouro",
#       numero = "Numero",
#       cep = "CEP",
#       localidade = "Bairro",
#       municipio = "Cidade",
#       estado = "UF"
#     ),
#     c(
#       logradouro = "Nome_logradouro",
#       numero = "Numero",
#       cep = "CEP",
#       localidade = "Bairro",
#       municipio = "Cidade",
#       estado = "UF"
#     )
#   )
#
#   expect_identical(
#     tester(logradouro = "oi", numero = "ola"),
#     c(logradouro = "oi", numero = "ola")
#   )
# })
