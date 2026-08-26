# skip tests because they take too much time
skip_if(Sys.getenv("TEST_ONE") != "")
testthat::skip_on_cran()
testthat::skip_if_not_installed("arrow")

cache_config_file <- geocodebr:::listar_arquivo_config()
default_cache_dir <- geocodebr:::listar_pasta_cache_padrao()

# definir_pasta_cache -----------------------------------------------------------

tester <- function(path = NULL) definir_pasta_cache(path)

test_that("errors with incorrect input", {
  expect_error(tester(1))
  expect_error(tester(c("aaa", "bbb")))
  expect_error(tester(path))

})

test_that("behaves correctly", {
  # if the cache config file exists, we save its current content just to make
  # sure our tests don't disturb any workflows we have. if it doesn't, we delete
  # the file we created during the test

  if (fs::file_exists(cache_config_file)) {
    config_file_content <- readLines(cache_config_file)
    on.exit(writeLines(config_file_content, cache_config_file), add = TRUE)
  } else {
    on.exit(fs::file_delete(cache_config_file), add = TRUE)
  }

  # by default uses a versioned dir inside the default R cache dir

  fn_result <- suppressMessages(definir_pasta_cache(path = NULL))
  expect_type(fn_result, "character")
  expect_identical(fn_result, as.character(default_cache_dir))
  expect_identical(readLines(cache_config_file), unclass(default_cache_dir))

  fn_result <- suppressMessages(definir_pasta_cache("aaa"))
  expect_type(fn_result, "character")
  expect_identical(fn_result, "aaa")
  expect_identical(readLines(cache_config_file), "aaa")
})

test_that("messages are formatted correctly", {
  if (fs::file_exists(cache_config_file)) {
    config_file_content <- readLines(cache_config_file)
    on.exit(writeLines(config_file_content, cache_config_file), add = TRUE)
  } else {
    on.exit(fs::file_delete(cache_config_file), add = TRUE)
  }

  expect_snapshot(
    definir_pasta_cache(path = NULL),
    transform = function(x) sub(default_cache_dir, "<path_to_default_dir>", x),
    cnd_class = TRUE
  )

  expect_snapshot(definir_pasta_cache("aaa"), cnd_class = TRUE)
})

# listar_pasta_cache -----------------------------------------------------------

test_that("behaves correctly", {
  # if the cache config file exists, we save its current content just to make
  # sure our tests don't disturb any workflows we have. if it doesn't, we delete
  # the file we created during the test

  if (fs::file_exists(cache_config_file)) {
    config_file_content <- readLines(cache_config_file)
    on.exit(writeLines(config_file_content, cache_config_file), add = TRUE)
  } else {
    on.exit(fs::file_delete(cache_config_file), add = TRUE)
  }

  # if the cache config file exists, return its content. otherwise, returns the
  # default cache dir

  if (fs::file_exists(cache_config_file)) fs::file_delete(cache_config_file)
  expect_identical(listar_pasta_cache(), as.character(default_cache_dir))

  writeLines("aaa", cache_config_file)
  expect_identical(listar_pasta_cache(), "aaa")
})

# listar_dados_cache --------------------------------------------------------

test_that("errors with incorrect input", {
  expect_error(listar_dados_cache(1))
  expect_error(listar_dados_cache(NA))
  expect_error(listar_dados_cache(c(TRUE, TRUE)))
})

test_that("behaves correctly", {
  # if the cache config file exists, we save its current content just to make
  # sure our tests don't disturb any workflows we have. if it doesn't, we delete
  # the file we created during the test

  if (fs::file_exists(cache_config_file)) {
    config_file_content <- readLines(cache_config_file)
    on.exit(writeLines(config_file_content, cache_config_file), add = TRUE)
  } else {
    on.exit(fs::file_delete(cache_config_file), add = TRUE)
  }

  # we set the cache dir to a temporary directory to not mess with any cached
  # data we may already have

  tmpdir <- tempfile()
  fs::dir_create(tmpdir)

  suppressMessages(definir_pasta_cache(tmpdir))

  expect_identical(listar_dados_cache(), character(0))

  # previously, we used download_cnefe(progress = FALSE) here to download cnefe
  # data before listing the content. however, this takes a long time, and
  # afterall we only need to make sure that the function lists whatever files we
  # have in the directory. so we create empty temp files to test if the function
  # is working

  file.create(fs::path(tmpdir, c("oie.parquet", "hello.parquet")))

  cnefe_files <- listar_dados_cache()
  expect_identical(basename(cnefe_files), c("hello.parquet", "oie.parquet"))

  # expect a tree-like message and invisible value when print_tree=TRUE

  expect_snapshot(
    listar_dados_cache(print_tree = TRUE),
    transform = function(x) sub(listar_pasta_cache(), "<path_to_cache_dir>", x)
  )
})

# deletar_pasta_cache ---------------------------------------------------------

test_that("deletar_pasta_cache behaves correctly", {
  # if the cache config file exists, we save its current content just to make
  # sure our tests don't disturb any workflows we have. if it doesn't, we delete
  # the file we created during the test

  if (fs::file_exists(cache_config_file)) {
    config_file_content <- readLines(cache_config_file)
    on.exit(writeLines(config_file_content, cache_config_file), add = TRUE)
  } else {
    on.exit(fs::file_delete(cache_config_file), add = TRUE)
  }

  # we set the cache dir to a temporary directory to not mess with any cached
  # data we may already have

  tmpdir <- tempfile()
  fs::dir_create(tmpdir)

  suppressMessages(definir_pasta_cache(tmpdir))

  file.create(fs::path(tmpdir, "oie.parquet"))
  expect_identical(basename(listar_dados_cache()), "oie.parquet")

  expect_snapshot(
    res <- deletar_pasta_cache(),
    cnd_class = TRUE,
    transform = function(x) sub(listar_pasta_cache(), "<path_to_cache_dir>", x)
  )

  # mensagem se pasta de cache estiver vazia
  expect_message( geocodebr::listar_dados_cache() )

  expect_identical(res, as.character(fs::path_norm(tmpdir)))
  expect_false(dir.exists(res))


})

# caminho_parquet --------------------------------------------------------------

test_that("caminho_parquet monta o caminho dentro do release corrente", {
  if (fs::file_exists(cache_config_file)) {
    config_file_content <- readLines(cache_config_file)
    on.exit(writeLines(config_file_content, cache_config_file), add = TRUE)
  } else {
    on.exit(fs::file_delete(cache_config_file), add = TRUE)
  }

  tmpdir <- tempfile()
  fs::dir_create(tmpdir)
  suppressMessages(definir_pasta_cache(tmpdir))

  caminho <- geocodebr:::caminho_parquet("municipio_cep")

  expect_type(caminho, "character")
  expect_length(caminho, 1)
  expect_identical(basename(caminho), "municipio_cep.parquet")
  expect_identical(
    basename(dirname(caminho)),
    paste0("geocodebr_data_release_", geocodebr:::data_release)
  )
  expect_identical(
    as.character(fs::path_norm(dirname(dirname(caminho)))),
    as.character(fs::path_norm(tmpdir))
  )

  # o arquivo nao precisa existir, mas o input precisa ser uma string unica
  expect_error(geocodebr:::caminho_parquet(1))
  expect_error(geocodebr:::caminho_parquet(c("aaa", "bbb")))
})

# apaga_data_release_antigo ----------------------------------------------------

test_that("apaga_data_release_antigo preserva o release corrente", {
  if (fs::file_exists(cache_config_file)) {
    config_file_content <- readLines(cache_config_file)
    on.exit(writeLines(config_file_content, cache_config_file), add = TRUE)
  } else {
    on.exit(fs::file_delete(cache_config_file), add = TRUE)
  }

  # usa uma pasta temporaria para nao mexer em dados que ja estejam em cache
  tmpdir <- tempfile()
  fs::dir_create(tmpdir)
  suppressMessages(definir_pasta_cache(tmpdir))

  dir_corrente <- paste0("geocodebr_data_release_", geocodebr:::data_release)

  cria_releases <- function(dirs) {
    unlink(list.dirs(tmpdir, recursive = FALSE), recursive = TRUE)
    for (d in dirs) {
      fs::dir_create(fs::path(tmpdir, d))
      file.create(fs::path(tmpdir, d, "municipio.parquet"))
    }
  }

  releases_no_cache <- function() {
    basename(list.dirs(geocodebr:::listar_pasta_cache(), recursive = FALSE))
  }

  # release antigo convivendo com o corrente: apaga so o antigo
  cria_releases(c("geocodebr_data_release_v0.0.1", dir_corrente))
  geocodebr:::apaga_data_release_antigo()
  expect_identical(releases_no_cache(), dir_corrente)
  expect_true(file.exists(fs::path(tmpdir, dir_corrente, "municipio.parquet")))

  # pasta de release com nome fora do padrao nao derruba a funcao
  cria_releases(c("geocodebr_data_release_dev", dir_corrente))
  expect_no_error(geocodebr:::apaga_data_release_antigo())
  expect_identical(releases_no_cache(), dir_corrente)

  # so o release corrente: nada e apagado
  cria_releases(dir_corrente)
  geocodebr:::apaga_data_release_antigo()
  expect_identical(releases_no_cache(), dir_corrente)

  # cache sem nenhuma pasta de release
  cria_releases(character(0))
  expect_no_error(geocodebr:::apaga_data_release_antigo())
})
