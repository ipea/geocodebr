#' Geocode reverso de coordenadas espaciais no Brasil
#'
#' @description
#' Geocode reverso de coordenadas geográficas para endereços. A função recebe um
#' `sf data frame` com pontos e retorna o endereço mais próximo dando uma
#' distância máxima de busca.
#'
#' @param pontos Uma tabela de dados com classe espacial `sf data frame` no
#'        sistema de coordenadas geográficas SIRGAS 2000, EPSG 4674.
#' @param dist_max Integer. Distancia máxima aceitável (em metros) entre os
#'        pontos de input e o endereço Por padrão, a distância é de 1000 metros.
#' @template verboso
#' @template cache
#' @template n_cores
#'
#' @return Retorna o `sf data.frame` de input adicionado das colunas do endereço
#'         encontrado. O output inclui uma coluna "distancia_metros" que indica
#'         a distância entre o ponto de input e o endereço mais próximo
#'         encontrado.
#'
#' @examplesIf identical(tolower(Sys.getenv("NOT_CRAN")), "true")
#' library(geocodebr)
#' library(sf)
#'
#' # ler amostra de dados
#' pontos <- readRDS(
#'     system.file("extdata/pontos.rds", package = "geocodebr")
#'     )
#'
#' pontos <- pontos[1:3,]
#'
#' # geocode reverso
#' df_enderecos <- geocodebr::geocode_reverso(
#'   pontos = pontos,
#'   dist_max = 800,
#'   verboso = TRUE
#'   )
#'
#'head(df_enderecos)
#'
#' @export
geocode_reverso <- function(
    pontos,
    dist_max = 1000,
    verboso = TRUE,
    cache = TRUE,
    n_cores = NULL
  ){

  # check input
  checkmate::assert_class(pontos, 'sf')
  checkmate::assert_number(dist_max, lower = 500, upper = 100000) # max 100 Km
  checkmate::assert_logical(verboso)
  checkmate::assert_logical(cache)

  # check if geometry type is POINT
  if (any(sf::st_geometry_type(pontos) != 'POINT')) {
    cli::cli_abort(
      "Input precisa ser um sf data frame com geometria do tipo POINT."
    )
  }

  epsg <- sf::st_crs(pontos)$epsg
  if (epsg != 4674) {
    cli::cli_abort(
      "Dados de input precisam estar com sistema de coordenadas geogr\u00e1ficas SIRGAS 2000, EPSG 4674."
    )
  }

  # prep input -------------------------------------------------------

  # converte pontos de input para data.frame
  pontos$tempidgeocodebr <- 1:nrow(pontos)


  # check if input falls within Brazil
  bbox <- sf::st_bbox(pontos)

  bbox_brazil <- data.frame(
    xmin = -73.99044997,
    ymin = -33.75208127,
    xmax = -28.83594354,
    ymax = 5.27184108
  )

  error_msg <- 'Coordenadas de input localizadas fora do bounding box do Brasil.'
  if (
    bbox[[1]] < bbox_brazil$xmin |
    bbox[[3]] > bbox_brazil$xmax |
    bbox[[2]] < bbox_brazil$ymin |
    bbox[[4]] > bbox_brazil$ymax
  ) {
    cli::cli_abort(error_msg)
  }

  # download cnefe  -------------------------------------------------------

  # downloading cnefe
  cnefe_dir <- geocodebr::download_cnefe(
    tabela = 'municipio_logradouro_numero_cep_localidade',
    verboso = verboso,
    cache = cache
  )

  # creating a temporary db and register the input table data
  conn <- create_geocodebr_db(
    n_cores = n_cores,
    load_spatial = TRUE
  )

  # limita escopo de busca aos municipios  -------------------------------------------------------
  # determine potential municipalities
  munis <- system.file("extdata/munis_bbox_2022.parquet", package = "geocodebr") |>
    duckspatial::ddbs_open_dataset()


  potential_munis <- duckspatial::ddbs_join(
    x = pontos,
    y = munis,
    join = "within",
    quiet = TRUE
  ) |>
    dplyr::pull(code_muni) |>
    unique()

  potential_munis <- enderecobr::padronizar_municipios(potential_munis)

  # lida com munis com apostrofe no nome tipo Olho d'agua
  potential_munis <- gsub("'", "''", potential_munis, fixed = TRUE)

  unique_munis <- paste(glue::glue("'{potential_munis}'"), collapse = ",")


  # build path to local file
  path_to_parquet <- fs::path(
    listar_pasta_cache(),
    glue::glue("geocodebr_data_release_{data_release}"),
    paste0("municipio_logradouro_numero_cep_localidade.parquet")
  )

  # create filtered_cnefe table, filter on the fly
  cols_to_keep <- c(
    "estado",
    "municipio",
    "logradouro",
    "numero",
    "cep",
    "localidade"
  )

  cols_to_keep_string <- paste0(cols_to_keep, collapse = ", ")

  # Load CNEFE data and filter it to narrow search global scope of cnefe to the
  # bounding box of input points
  query_filter_cnefe <- glue::glue(
    "CREATE OR REPLACE TEMP VIEW cnefe_tb AS
        SELECT {cols_to_keep_string},
               ST_Point(lon, lat)::GEOMETRY('EPSG:4674') AS geometry
     FROM read_parquet('{path_to_parquet}') m
          WHERE m.municipio IN ({unique_munis});"
  )

  DBI::dbExecute(conn, query_filter_cnefe)
  # b <- duckspatial::ddbs_read_table(conn = conn, name = "cnefe_tb")
  # duckspatial::ddbs_crs(con, "filtered_cnefe")
  # ST_Point(lon, lat)::GEOMETRY('EPSG:4674') AS geom


  # converte cnefe para UTM
  cnefe_utm_duck <- duckspatial::ddbs_transform(
    x = 'cnefe_tb',
    y = 'EPSG:31983',
    conn = conn,
    quiet = TRUE
  )

  # converte pontos para UTM
  input_utm_duck <- duckspatial::ddbs_transform(
    x = pontos,
    y = 'EPSG:31983',
    conn = conn,
    name = "pontos_utm",
    overwrite = T,
    quiet = TRUE
  )

  # buffer around input points
  buff <- duckspatial::ddbs_buffer(
    x = "pontos_utm",
    conn = conn,
    distance = dist_max,
    quiet = TRUE
  )

  # Lazy join - computation stays in DuckDB
  suppressWarnings(
    result <- duckspatial::ddbs_join(
      x = cnefe_utm_duck,
      y = buff,
      join = "intersects", # intersects within
      conn = conn,
      name = "join_result",
      overwrite = T,
      quiet = TRUE
    )
  )

  # Get column names from both tables
  cols_a <- DBI::dbGetQuery(conn, "SELECT column_name FROM (DESCRIBE pontos_utm)")$column_name
  cols_b <- DBI::dbGetQuery(conn, "SELECT column_name FROM (DESCRIBE join_result)")$column_name

  # Find overlapping columns (plus the ones you want to exclude anyway)
  exclude_from_b <- unique(c(
    "tempidgeocodebr", "geometry",
    intersect(cols_a, cols_b)
  ))

  exclude_clause <- paste0("EXCLUDE (", paste(exclude_from_b, collapse = ", "), ")")

  query <- glue::glue("
    CREATE OR REPLACE TEMP TABLE output AS
    SELECT * EXCLUDE (rn)
    FROM (
      SELECT
        a.*,
        b.* {exclude_clause},
        ST_Distance(a.geometry, b.geometry) AS distancia_metros,
        ROW_NUMBER() OVER (
          PARTITION BY a.id
          ORDER BY distancia_metros
        ) AS rn
      FROM pontos_utm AS a
      JOIN join_result AS b
        ON a.tempidgeocodebr = b.tempidgeocodebr
    ) t
    WHERE rn = 1
    ORDER BY tempidgeocodebr
    ")

  DBI::dbExecute(conn, query)
  # output <- duckspatial::ddbs_read_table(conn, name = "output")
  # head(output)

  output <- duckspatial::ddbs_transform(
    x = "output",
    conn = conn,
    y = 'EPSG:4674',
    quiet = TRUE
  )

  output <- duckspatial::ddbs_collect(output)


  # TODO
  if (nrow(output)==0){
    stop("Nenhum endereco proximo foi encontrados")
  }


  output <- output |>
    dplyr::select(-tempidgeocodebr) |>
    dplyr::relocate(geometry, .after = dplyr::last_col())

  duckdb::dbDisconnect(conn)

  return(output)
}
