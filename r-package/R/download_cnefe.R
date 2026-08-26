#' Faz download dos dados do CNEFE
#'
#' Faz o download de uma versão pre-processada e enriquecida do CNEFE (Cadastro
#' Nacional de Endereços para Fins Estatísticos) que foi criada para o uso deste
#' pacote.
#'
#' @param tabela Nome da tabela para ser baixada. Por padrão, baixa `"todas"`.
#' @template verboso
#' @template cache
#'
#' @return Retorna o caminho para o diretório onde os dados foram salvos.
#'
#' @examplesIf identical(tolower(Sys.getenv("NOT_CRAN")), "true")
#' download_cnefe(verboso = FALSE)
#'
#' @export
download_cnefe <- function(tabela = "todas", verboso = TRUE, cache = TRUE) {
  all_files <- c(
    "municipio_logradouro_numero_localidade.parquet", # 4 largest files       ok 3
    "municipio_logradouro_numero_cep_localidade.parquet", # 4 largest files    ok 1
    "municipio.parquet",
    "municipio_cep.parquet",
    "municipio_cep_localidade.parquet",
    "municipio_localidade.parquet",
    # "municipio_logradouro.parquet",
    # "municipio_logradouro_numero_cep.parquet", # 4 largest files
    # "municipio_logradouro_cep.parquet",
    "municipio_logradouro_cep_localidade.parquet", #  ok 1
    # "municipio_logradouro_numero.parquet", # 4 largest files
    "municipio_logradouro_localidade.parquet" #  ok 3
  )
  all_files_basename <- fs::path_ext_remove(all_files)

  # check input
  checkmate::assert_logical(verboso, any.missing = FALSE, len = 1)
  checkmate::assert_logical(cache, any.missing = FALSE, len = 1)

  # seleciona tabela
  if (tabela != "todas") {
    if (!any(all_files %like% tabela)) {
      cli::cli_abort(
        "A 'tabela' deve ser uma das seguintes op\u00e7\u00f5es: {all_files_basename}"
      )
    }

    all_files <- all_files_basename[all_files_basename == tabela]
    all_files <- paste0(all_files, ".parquet")
  }

  data_urls <- glue::glue(
    "https://github.com/ipeaGIT/padronizacao_cnefe/releases/",
    "download/{data_release}/{all_files}"
  )

  # create dir with data release inside the cache dir / dir is versioned
  if (!cache) {
    cache_dir <- as.character(fs::path_norm(tempfile("geocodebr_temp")))
    data_dir <- glue::glue("{cache_dir}/geocodebr_data_release_{data_release}")
    if (!dir.exists(data_dir)) {
      fs::dir_create(data_dir, recurse = TRUE)
    }
  } else {
    # apaga release antigo se houver
    apaga_data_release_antigo()

    cache_dir <- geocodebr::listar_pasta_cache()
    data_dir <- glue::glue("{cache_dir}/geocodebr_data_release_{data_release}")
    if (!dir.exists(data_dir)) {
      fs::dir_create(data_dir, recurse = TRUE)
    }
  }

  # we only need to download data that hasn't been downloaded yet. note that if
  # cache=FALSE data_dir is always empty, so we download all required data

  existing_files <- list.files(data_dir)

  files_to_download <- setdiff(all_files, existing_files)
  files_to_download <- data_urls[all_files %in% files_to_download]

  if (length(files_to_download) == 0) {
    if (verboso) {
      message_usando_cnefe_local()
    }

    return(invisible(cache_dir))
  }

  downloaded_files <- download_files(data_dir, files_to_download, verboso)

  # the download_dir object below should be identical to data_dir, but we return
  # its value, instead of data_dir, just to make sure the that data is
  # downloaded to the correct dir and that nothing went wrong between setting
  # data_dir and downloading the data

  download_dir <- unique(fs::path_dir(downloaded_files))

  return(invisible(cache_dir))
}


download_files <- function(data_dir, files_to_download, verboso) {
  requests <- lapply(files_to_download, httr2::request)

  dest_files <- fs::path(data_dir, basename(files_to_download))

  responses <- perform_requests_in_parallel(requests, dest_files, verboso)

  response_errored <- purrr::map_lgl(
    responses,
    function(r) inherits(r, "error")
  )

  if (any(response_errored)) {
    error_cnefe_download_failed()
  }

  return(dest_files)
}

perform_requests_in_parallel <- function(requests, dest_files, verboso) {
  # we create this wrapper around httr2::req_perform_parallel just for testing
  # purposes. it's easier to mock this function when testing than to mock a
  # function from another package.
  #
  # related test: "errors if could not download the data for one or more states"
  # in test-download_cnefe
  #
  # related help page:
  # https://testthat.r-lib.org/reference/local_mocked_bindings.html

  if (verboso) {
    message_baixando_cnefe()
  }

  httr2::req_perform_parallel(
    requests,
    paths = dest_files,
    on_error = "continue",
    progress = ifelse(verboso == TRUE, ' ', FALSE)
  )
}

error_cnefe_download_failed <- function() {
  geocodebr_error(
    c(
      "Nao foi possivel baixar os dados do CNEFE.",
      "i" = "Por favor, tente novamente."
    ),
    call = rlang::caller_env(n = 2)
  )
}
