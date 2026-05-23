devtools::load_all('.')
library(dplyr)
library(sf)


# input data

pontos <- readRDS(
   system.file("extdata/pontos.rds", package = "geocodebr")
   )

pontos <- pontos[1:500,]



# reverse geocode
bench::system_time(
 out <-  geocode_reverso(
   pontos = pontos,
   dist_max = 1000
   )
)
View(out)


# ttt <- data.frame(id=1, lat=-15.814192047159876, lon=-47.90534614672923)
# reverse_geocode(df = ttt)

# take aways
# ok reverse_geocode_filter  # mais rapdido e eficiente, mas sem progress bar
# ok reverse_geocode_join    # igual o _filter, mas usa join
# ok reverse_geocode_hybrid  # com progress bar mas um pouco mais lento e bem mais memoria
# ok reverse_geocode_arrow   # tempo igual a _hybrid, mas usa bem mais memoria
# ok           filterloop    # disparado o mais lento, com progress e memoria media

# essa funcao pode fica muito mais rapida / eficiente se usarmos a biblioteca de
# dados espaciais do duckdb

b5 <- bench::mark(
  current = geocode_reverso(pontos = pontos, dist_max = 1000),
  iterations = 5,
  check = F
)

b5
#

# # 500 pontos
#     expression           min median `itr/sec` mem_alloc `gc/sec` n_itr  n_gc total_time result memory
#   1 duck_filter4       1.54m  1.62m   0.0101    221.5MB  0.0423      5    21      8.28m <NULL> <Rprofmem>
#   2 duck_filter_loop4  5.35m  6.88m   0.00255    14.5MB  0.00357     5     7      32.7m <NULL> <Rprofmem>
#   3 hybrid4            2.41m  2.47m   0.00663    34.5MB  0.302       5   228     12.56m <NULL> <Rprofmem>
#   v0.6.2                2.9s    3.02s     0.330     153MB     1.39     5    21      15.1s <NULL>
#   0.6.2.9000 duck       4.41s    4.73s     0.175    94.9MB    0.281     5     8      28.5s <NULL>


# # 1000 pontos
#     expression   min median `itr/sec` mem_alloc `gc/sec` n_itr  n_gc total_time result memory
#     <bch:expr> <bch> <bch:>     <dbl> <bch:byt>    <dbl> <int> <dbl>   <bch:tm> <list> <list>
#   1 duck_filt… 2.97m  2.97m   0.00560    11.3MB    0         1     0      2.97m <NULL> <Rprofmem>
#   2 duck_join4 3.03m  3.03m   0.00550    11.5MB    0         1     0      3.03m <NULL> <Rprofmem>
#   3 arrow4     4.27m  4.27m   0.00391   240.1MB    0.316     1    81      4.27m <NULL> <Rprofmem>
#   4 hybrid4    4.24m  4.24m   0.00393   122.4MB    0.110     1    28      4.24m <NULL> <Rprofmem>
#   4 filterloop 10.7m 11.27m   0.00146    19.8MB  0.00195     3     4     34.19m <NULL> <Rprofmem> <bench_tm [3]> <tibble>
# 1 current      1.92s  1.98s     0.496  247.62MB    3.17      5    32     10.08s <NULL> <Rprofmem [22,026 × 3]> <bench_tm [5]> <tibble>
# 2 geocrev2     1.28s  1.33s     0.730    8.03MB    0.730     5     5      6.85s <NULL> <Rprofmem [13,876 × 3]> <bench_tm [5]> <tibble>
# 3 geocrev3     1.38s  1.61s     0.626    8.29MB    0.752     5     6      7.98s <NULL> <Rprofmem [15,238 × 3]> <bench_tm [5]> <tibble>
#



# aternativas da funcao de geocode reverso -----------------------------------------------------------

#' muni join + haversine
#' (usa spatial join para detectar munis candidatos, e depois calcular haversine na unha)
#' a diferenca dessa para a versao implementada é que a implementada calcula distancias dentro do duckspatial com ST_DIST

geocode_reverso2 <- function(
    pontos,
    dist_max = 1000,
    verboso = TRUE,
    cache = TRUE,
    n_cores = NULL
) {
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

  # converte para data.frame
  coords <- sfheaders::sf_to_df(pontos, fill = TRUE)
  data.table::setDT(coords)
  coords[, c('sfg_id', 'point_id') := NULL]
  data.table::setnames(coords, old = c('x', 'y'), new = c('lon', 'lat'))

  # create temp id
  coords[, tempidgeocodebr := 1:nrow(coords)]

  # convert max_dist to degrees
  # 1 degree of latitude is always 111320 meters
  margin_lat <- dist_max / 111320

  # 1 degree of longitude is 111320 * cos(lat)
  coords[, c("lat_min", "lat_max") := .(lat - margin_lat, lat + margin_lat)]

  coords[,
         c("lon_min", "lon_max") := .(
           lon - dist_max / 111320 * cos(lat),
           lon + dist_max / 111320 * cos(lat)
         )
  ]

  # get bounding box around input points
  # using a range of max dist around input points
  bbox_lat_min <- min(coords$lat_min)
  bbox_lat_max <- max(coords$lat_max)
  bbox_lon_min <- min(coords$lon_min)
  bbox_lon_max <- max(coords$lon_max)

  # check if input falls within Brazil
  bbox_brazil <- data.frame(
    xmin = -73.99044997,
    ymin = -33.75208127,
    xmax = -28.83594354,
    ymax = 5.27184108
  )

  error_msg <- 'Coordenadas de input localizadas fora do bounding box do Brasil.'
  if (
    bbox_lon_min < bbox_brazil$xmin |
    bbox_lon_max > bbox_brazil$xmax |
    bbox_lat_min < bbox_brazil$ymin |
    bbox_lat_max > bbox_brazil$ymax
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
  con <- create_geocodebr_db(n_cores = n_cores)


  # limita escopo de busca aos municipios  -------------------------------------------------------
  # determine potential municipalities
  munis <- system.file("extdata/munis_bbox_2022.parquet", package = "geocodebr") |>
    arrow::open_dataset() |>
    sf::st_as_sf()
  # munis_path <- system.file("extdata/munis_2022.parquet", package = "geocodebr")
  #
  # query_register_muni <- glue::glue(
  #   "CREATE OR REPLACE TEMP VIEW munis AS
  #       SELECT *,
  #       geometry::GEOMETRY AS geometry
  #   FROM read_parquet('{munis_path}');"
  # )
  #
  # DBI::dbExecute(conn, query_register_muni)

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
    "localidade",
    "endereco_completo",
    "lon",
    "lat"
  )
  cols_to_keep <- paste0(cols_to_keep, collapse = ", ")

  # Load CNEFE data and filter it to include only municipalities
  # present in the input table, reducing the search scope
  # Narrow search global scope of cnefe to bounding box
  query_filter_cnefe <- glue::glue(
    "CREATE TEMP VIEW filtered_cnefe AS
        SELECT {cols_to_keep}
        FROM read_parquet('{path_to_parquet}') m
          WHERE m.municipio IN ({unique_munis});"
  )

  DBI::dbExecute(con, query_filter_cnefe)
  # DBI::dbExecute(con, query_filter_cnefe)
  # b <- DBI::dbReadTable(con, "filtered_cnefe")

  # Convert input data frame to DuckDB table
  duckdb::dbWriteTable(con, "input_table_db", coords, temporary = TRUE)

  # Haversine macro (kept for speed; consider spatial extension later)
  DBI::dbExecute(
    con,
    "
    CREATE MACRO IF NOT EXISTS haversine(lat1, lon1, lat2, lon2) AS (
      6378137 * 2 * ASIN(
        SQRT(
          POWER(l(lat2 - lat1) / 2), 2) +
          COS(RADIANS(lat1)) * COS(RADIANS(lat2)) *
          POWER(SIN(RADIANS(lon2 - lon1) / 2), 2)
        )
      )
    );
  "
  )

  # TO OPTMIZE 666666666666666666666 -------------------------------------------
  # 1.1) calc dist mantendo apenas tempidgeocodebr
  # 1.2) calc de dist sucessivo: primeiro 1k, dpeois a distancia q o usuario passa
  # 1.3) dist usando duckspatial
  # 2) depois dar um left join do input_table_db com resultado da dist para retornar input original


  # Find cases nearby -------------------------------------------------------
  query_filter_cases_nearby <- glue::glue(
    "WITH dist_data AS (
        SELECT
              input_table_db.* EXCLUDE (lon_min, lon_max, lat_min, lat_max),
              filtered_cnefe.endereco_completo,
              filtered_cnefe.estado,
              filtered_cnefe.municipio,
              filtered_cnefe.logradouro,
              filtered_cnefe.numero,
              filtered_cnefe.cep,
              filtered_cnefe.localidade,
              haversine(
                    input_table_db.lat, input_table_db.lon,
                    filtered_cnefe.lat, filtered_cnefe.lon
              ) AS distancia_metros
        FROM
              input_table_db, filtered_cnefe
        WHERE
              input_table_db.lat_min < filtered_cnefe.lat
          AND input_table_db.lat_max > filtered_cnefe.lat
          AND input_table_db.lon_min < filtered_cnefe.lon
          AND input_table_db.lon_max > filtered_cnefe.lon
    ),

    ranked AS (
        SELECT
            *,
            RANK() OVER (
                PARTITION BY tempidgeocodebr
                ORDER BY distancia_metros ASC
            ) AS ranking
        FROM dist_data
    )

    SELECT * EXCLUDE(tempidgeocodebr, ranking)
    FROM ranked
    WHERE ranking = 1;"
  )



  output <- DBI::dbGetQuery(con, query_filter_cases_nearby)

  # TODO 6666666
  if (nrow(output)==0){
    stop("Nenhum endereco proximo foi encontrados")
  }

  # organize output -------------------------------------------------

  # convert df to simple feature
  output_sf <- sfheaders::sf_point(
    obj = output,
    x = 'lon',
    y = 'lat',
    keep = TRUE
  )

  sf::st_crs(output_sf) <- 4674

  duckdb::dbDisconnect(con)

  return(output_sf)
}















pontos <- readRDS(
  system.file("extdata/pontos.rds", package = "geocodebr")
)

bench::mark(
  # duck_filter1 = reverse_geocode_filter(coordenadas = pontos, dist_max = 2000, n_cores = 1),
  # duck_filter8 = reverse_geocode_filter(coordenadas = pontos, dist_max = 2000, n_cores = 8),
  # duck_join1 =  reverse_geocode_join(coordenadas = pontos, dist_max = 2000, n_cores = 1),
  # duck_join8 =  reverse_geocode_join(coordenadas = pontos, dist_max = 2000, n_cores = 8),
  hybrid1 = reverse_geocode_hybrid(coordenadas = pontos, dist_max = 2000, n_cores = 1),
  hybrid8 = reverse_geocode_hybrid(coordenadas = pontos, dist_max = 2000, n_cores = 8),
  iterations = 5,
  check = F
)

# 1000 pontos
#     expression      min   median `itr/sec` mem_alloc `gc/sec` n_itr  n_gc total_time result memory
#     <bch:expr>   <bch:>   <bch:>     <dbl> <bch:byt>    <dbl> <int> <dbl>   <bch:tm> <list> <list>
# 1 duck_filter1    3.19m    3.31m   0.00490      75MB  0.0108      5    11        17m <NULL> <Rprofmem>
# 2 duck_filter8    2.93m    3.04m   0.00516      51MB  0.00723     5     7      16.1m <NULL> <Rprofmem>
#
# 1 duck_join1      2.93m    3.54m   0.00475    76.2MB  0.00854     5     9      17.6m <NULL> <Rprofmem>
# 2 duck_join8      3.62m    4.05m   0.00407    51.2MB  0.00651     5     8      20.5m <NULL> <Rprofmem>
#
# 1 hybrid1         5.13m     5.9m   0.00277    88.3MB    0.262     5   473      30.1m <NULL> <Rprofmem>
# 2 hybrid8         5.09m    5.19m   0.00321      66MB    0.307     5   478      25.9m <NULL> <Rprofmem>
