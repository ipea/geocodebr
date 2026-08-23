#' Busca por CEP
#'
#' Busca endereços e suas coordenadas geográficas a partir de um CEP. As
#' coordenadas de output utilizam o sistema de coordenadas geográficas SIRGAS
#' 2000, EPSG 4674.
#'
#' @param cep Vetor. Um CEP ou um vetor de CEPs com 8 dígitos.
#' @template h3_res
#' @template resultado_sf
#' @template verboso
#' @template cache
#'
#' @return Retorna um `data.frame` com os CEPs de input e os endereços presentes
#'   naquele CEP com suas coordenadas geográficas de latitude (`lat`) e
#'   longitude (`lon`). Alternativamente, o resultado pode ser um objeto `sf`.
#'
#' @examplesIf identical(tolower(Sys.getenv("NOT_CRAN")), "true")
#' library(geocodebr)
#'
#' # amostra de CEPs
#' ceps <- c("70390-025", "20071-001", "99999-999")
#'
#' df <- geocodebr::busca_por_cep(
#'   cep = ceps,
#'   h3_res = 10,
#'   verboso = TRUE
#'   )
#'
#' head(df)
#'
#' @export
busca_por_cep <- function(
  cep,
  h3_res = NULL,
  resultado_sf = FALSE,
  verboso = TRUE,
  cache = TRUE
) {
  # check input
  checkmate::assert_vector(cep)
  checkmate::assert_logical(resultado_sf, any.missing = FALSE, len = 1)
  checkmate::assert_logical(verboso, any.missing = FALSE, len = 1)
  checkmate::assert_logical(cache, any.missing = FALSE, len = 1)
  checkmate::assert_numeric(
    h3_res,
    null.ok = TRUE,
    lower = 0,
    upper = 15,
    max.len = 16
  )

  # normalize input data -------------------------------------------------------

  cep_padrao <- enderecobr::padronizar_ceps(cep)
  cep_padrao <- unique(cep_padrao)
  cep_padrao <- na.omit(cep_padrao)
  cep_padrao <- cep_padrao[cep_padrao != ""]

  # download cnefe  -------------------------------------------------------

  # downloading cnefe
  cnefe_dir <- download_cnefe(
    tabela = 'municipio_logradouro_cep_localidade',
    verboso = verboso,
    cache = cache
  )
  # creating a temporary db and register the input table data
  con <- create_geocodebr_db()

  # garante que a conexao seja fechada em qualquer saida da funcao, inclusive
  # quando ela aborta porque nenhum cep foi encontrado
  on.exit(duckdb::dbDisconnect(con), add = TRUE)

  # build path to local file
  path_to_parquet <- fs::path(
    listar_pasta_cache(),
    glue::glue("geocodebr_data_release_{data_release}"),
    paste0("municipio_logradouro_cep_localidade.parquet")
  )

  # ceps string
  unique_ceps <- glue::glue_collapse(glue::single_quote(cep_padrao), sep = ",")

  # select columns
  cols_to_keep <- c(
    "cep",
    "estado",
    "municipio",
    "logradouro",
    "localidade",
    "lon",
    "lat"
  )
  cols_to_keep <- paste0(cols_to_keep, collapse = ", ")

  # filtrar por uf ?
  query_filter_cnefe <- glue::glue(
    "SELECT {cols_to_keep}
        FROM read_parquet('{path_to_parquet}') m
        WHERE m.cep IN ({unique_ceps});"
  )

  output_df <- DBI::dbGetQuery(con, query_filter_cnefe)

  # add any missing cep
  missing_cep <- cep_padrao[!cep_padrao %in% output_df$cep]

  if (length(missing_cep) == length(cep_padrao)) {
    cli::cli_abort("Nenhum CEP foi encontrado.")
  }

  if (length(missing_cep) > 0) {
    temp_dt <- data.table::data.table(cep = missing_cep)
    output_df <- data.table::rbindlist(list(output_df, temp_dt), fill = TRUE)
  }

  data.table::setDT(output_df)

  # add H3
  if (!is.null(h3_res)) {
    for (i in h3_res) {
      colname <- paste0(
        'h3_',
        formatC(i, width = 2, flag = "0")
      )

      output_df[
        !is.na(lat),
        {{ colname }} := h3r::latLngToCell(lat = lat, lng = lon, resolution = i)
      ]
    }
  }

  # convert df to simple feature
  if (isTRUE(resultado_sf)) {
    output_sf <- sfheaders::sf_point(
      obj = output_df,
      x = 'lon',
      y = 'lat',
      keep = TRUE
    )

    sf::st_crs(output_sf) <- 4674
    return(output_sf)
  }

  return(output_df)
}
