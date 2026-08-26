# skip tests because they take too much time
skip_if(Sys.getenv("TEST_ONE") != "")
testthat::skip_on_cran()
testthat::skip_if_not_installed("arrow")


ceps_valid <- c("70390-025", "20071-001", "99999-999")
ceps_not_valid <- c("99999-999")


tester <- function(cep,
                   h3_res = NULL,
                   resultado_sf = FALSE,
                   verboso = TRUE,
                   cache = TRUE) {
  busca_por_cep(
    cep,
    h3_res,
    resultado_sf,
    verboso,
    cache
  )
}

test_that("expected output", {

  # expected results
  output <- tester(cep = ceps_valid)
  testthat::expect_true(nrow(output) == 5)

  # expected class
  testthat::expect_s3_class(output, 'data.frame')

  # add h3
  h3_output <- tester(cep = ceps_valid, h3_res = c(3,4))
  testthat::expect_true(all(c('h3_03', 'h3_04') %in% names(h3_output)))


  # output in sf format
  sf_output <- tester(cep = ceps_valid, resultado_sf = TRUE)
  testthat::expect_true(is(sf_output , 'sf'))
})



test_that("errors with incorrect input", {
  expect_error(tester(unclass(ceps_not_valid)))

  expect_error(tester(cep = 1))
  expect_error(tester(cep = 'banana'))
  expect_error(tester(cep = ceps_not_valid))

  expect_error(tester(resultado_completo = 1))
  expect_error(tester(resultado_completo = NA))
  expect_error(tester(resultado_completo = c(TRUE, TRUE)))

  expect_error(tester(resultado_sf = 1))
  expect_error(tester(resultado_sf = NA))
  expect_error(tester(resultado_sf = c(TRUE, TRUE)))

  expect_error(tester(verboso = 1))
  expect_error(tester(verboso = NA))
  expect_error(tester(verboso = c(TRUE, TRUE)))

  expect_error(tester(cache = 1))
  expect_error(tester(cache = NA))
  expect_error(tester(cache = c(TRUE, TRUE)))
})

# cache = FALSE ---------------------------------------------------------------

test_that("busca_por_cep le os dados que acabou de baixar quando cache = FALSE", {
  # com cache = FALSE os dados vao para um diretorio temporario. A leitura tem
  # que seguir para la, e nao para a pasta de cache persistente

  cache_config_file <- geocodebr:::listar_arquivo_config()
  if (fs::file_exists(cache_config_file)) {
    config_file_content <- readLines(cache_config_file)
    on.exit(writeLines(config_file_content, cache_config_file), add = TRUE)
  } else {
    on.exit(fs::file_delete(cache_config_file), add = TRUE)
  }

  # pasta de cache vazia: se a funcao ler de la, nao acha nada
  tmpdir <- tempfile()
  fs::dir_create(tmpdir)
  suppressMessages(definir_pasta_cache(tmpdir))

  cnefe_falso <- data.frame(
    estado           = "DF",
    municipio        = "BRASILIA",
    logradouro       = "SQN 999 BLOCO Z",
    numero           = 1L,
    cep              = "70390-025",
    localidade       = "ASA NORTE",
    lat              = -15.79,
    lon              = -47.89,
    endereco_completo = "SQN 999 BLOCO Z, 1 - ASA NORTE, BRASILIA - DF",
    n_casos          = 1L,
    desvio_metros    = 0L,
    cod_setor        = "530010805000001",
    stringsAsFactors = FALSE
  )

  # em vez de baixar, escreve o parquet sintetico no destino escolhido pelo
  # download_cnefe() -- que com cache = FALSE e um tempdir
  local_mocked_bindings(
    perform_requests_in_parallel = function(requests, dest_files, verboso) {
      fs::dir_create(fs::path_dir(dest_files[[1]]))
      arrow::write_parquet(cnefe_falso, dest_files[[1]])
      lapply(seq_along(dest_files), function(i) list(status_code = 200L))
    }
  )

  res <- suppressMessages(
    busca_por_cep("70390-025", verboso = FALSE, cache = FALSE)
  )

  expect_s3_class(res, "data.frame")
  expect_identical(nrow(res), 1L)
  expect_identical(res$cep, "70390-025")
  expect_identical(res$logradouro, "SQN 999 BLOCO Z")

  # e a pasta de cache continua vazia: nada foi gravado la
  expect_identical(listar_dados_cache(), character(0))
})
