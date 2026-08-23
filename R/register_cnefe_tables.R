register_cnefe_table <- function(con, match_type) {
  # nocov start

  # message("register_cnefe_table")

  # match_type = "dn01"

  # get corresponding table and key cols
  cnefe_table_name <- get_reference_table(match_type)

  # build path to local file
  path_to_parquet <- caminho_parquet(cnefe_table_name)



  # # ----------------------------------------------------------------------------
  # # check if table already exists
  # recorded_tbls <- duckdb::duckdb_list_arrow(conn = con)
  # if (cnefe_table_name %in% recorded_tbls) {
  #   return(TRUE)
  # }
  #
  # # determine geographical scope of the search
  # input_states <- DBI::dbGetQuery(con, "SELECT DISTINCT estado FROM input_padrao_db;")$estado |>
  #   sort()
  #
  # input_municipio <- DBI::dbGetQuery(con, "SELECT DISTINCT municipio FROM input_padrao_db;")$municipio |>
  #   sort()
  #
  # # connect to parquet file
  # cnefe_tbl <- arrow_open_dataset( path_to_parquet )
  #
  # # filter cnefe to include only states and municipalities
  # if (length(input_municipio) < 5000 | length(input_states) < 27) {
  #
  #   cnefe_tbl <- cnefe_tbl |>
  #     dplyr::filter(estado %in% input_states) |>
  #     dplyr::filter(municipio %in% input_municipio) |>
  #     dplyr::compute()
  # }
  #
  # # register filtered_cnefe to db
  # duckdb::duckdb_register_arrow(
  #   conn = con,
  #   name =  cnefe_table_name,
  #   arrow_scannable = cnefe_tbl
  #   )
  #
  # # ----------------------------------------------------------------------------

  # if table already exists, stop
  if (duckdb::dbExistsTable(con, cnefe_table_name)) {
    return(TRUE)
  }

  query_filter_cnefe <- glue::glue(
    "CREATE TEMP TABLE IF NOT EXISTS {cnefe_table_name} AS
          WITH unique_munis AS (
              SELECT DISTINCT municipio
              FROM input_padrao_db
          ),
          unique_states AS (
              SELECT DISTINCT estado
              FROM input_padrao_db
          )
          SELECT *
          FROM read_parquet('{path_to_parquet}') m
          WHERE m.estado IN (SELECT estado FROM unique_states)
               AND m.municipio IN (SELECT municipio FROM unique_munis);"
  )

  DBI::dbExecute(con, query_filter_cnefe)

  # # create index
  # if (cnefe_table_name %in% c("municipio_logradouro_cep_localidade",
  #                             "municipio_logradouro_numero_cep_localidade")) {
  #
  #   # index name
  #   idx_name <- paste0("idx_", cnefe_table_name)
  #
  #   # columns to index
  #   cols_index <- strsplit(x = cnefe_table_name, "_") |> unlist()
  #   cols_index <- cols_index[!cols_index %in% "numero"]
  #
  #   cols_index <- c("municipio", "logradouro")
  #   cols_expr <- paste(c("estado", cols_index), collapse = ", ")
  #
  #     query_index <- glue::glue("
  #       CREATE INDEX IF NOT EXISTS {idx_name}
  #         ON {cnefe_table_name} ({cols_expr});")
  #
  #     DBI::dbExecute(con, query_index)
  # }

  return(TRUE)
} # nocov end


# create small table with unique logradouros
register_unique_logradouros_table <- function(con, match_type) {
  # nocov start

  # match_type = "pn03"
  # get_reference_table(match_type)

  # get corresponding key cols and unique cols to keep
  key_cols <- get_key_cols(match_type)

  # determine reference table
  cnefe_table_name <- ifelse(
    match_type %in% c("pn03", "pa03", "pl03"),
    "municipio_logradouro_localidade",
    "municipio_logradouro_cep_localidade"
  )

  # create name of table with unique logradouros
  unique_logr_tbl_name <- paste0("unique_logr_", cnefe_table_name)

  # cols to keep unique values
  select_cols <- key_cols[!key_cols %in% c("numero")]

  # path to parquet
  path_to_parquet <- caminho_parquet(cnefe_table_name)

  # should use DISTINCT rows
  DISTINCT <- "DISTINCT"
  if (
    cnefe_table_name == "municipio_logradouro_localidade" |
      all(c("localidade", "cep") %in% select_cols)
  ) {
    DISTINCT <- ""
  }

  # # ----------------------------------------------------------------------------
  # # check if table already exists
  # recorded_tbls <- duckdb::duckdb_list_arrow(conn = con)
  # if (unique_logr_tbl_name %in% recorded_tbls) {
  #   return(unique_logr_tbl_name)
  # }
  #
  # # determine geographical scope of the search
  # input_states <- DBI::dbGetQuery(con, "SELECT DISTINCT estado FROM input_padrao_db;")$estado |>
  #   sort()
  # input_municipio <- DBI::dbGetQuery(con, "SELECT DISTINCT municipio FROM input_padrao_db;")$municipio |>
  #   sort()
  #
  # # connect to parquet file
  # unique_logradouros_arrw <- arrow_open_dataset( path_to_parquet )
  #
  #
  # # filter unique logradouros to include only states and municipalities
  # if (length(input_municipio) < 5000 | length(input_states) < 27) {
  #
  #   unique_logradouros_arrw <- unique_logradouros_arrw |>
  #     dplyr::filter(estado %in% input_states) |>
  #     dplyr::filter(municipio %in% input_municipio) |>
  #     dplyr::compute()
  # }
  #
  # if (DISTINCT=="DISTINCT") {
  #   unique_logradouros_arrw <- unique_logradouros_arrw |>
  #     dplyr::select(dplyr::all_of(select_cols))
  #     dplyr::distinct() |>
  #     dplyr::compute()
  # }
  #
  #
  # duckdb::duckdb_register_arrow(
  #   conn = con,
  #   name = unique_logr_tbl_name,
  #   arrow_scannable = unique_logradouros_arrw
  # )
  # # ----------------------------------------------------------------------------

  # ainda dah pra fazer (1) manter apenas as unique_cols, fazer filtro apenas quando
  # forem poucos munis < 5000

  # if table already exists, stop
  if (duckdb::dbExistsTable(con, unique_logr_tbl_name)) {
    return(unique_logr_tbl_name)
  }

  select_cols <- paste(select_cols, collapse = ', ')

  # se tabela raiz ja existe, filtra dela
  if (duckdb::dbExistsTable(con, cnefe_table_name)) {
    query_unique_logradouros <- glue::glue(
      "CREATE TEMP TABLE IF NOT EXISTS {unique_logr_tbl_name} AS
          WITH unique_munis AS (
              SELECT DISTINCT municipio
              FROM input_padrao_db
          ),
          unique_states AS (
              SELECT DISTINCT estado
              FROM input_padrao_db
          )

          SELECT {DISTINCT} {select_cols}
            FROM {cnefe_table_name}
            WHERE {cnefe_table_name}.estado IN (SELECT estado FROM unique_states)
              AND {cnefe_table_name}.municipio IN (SELECT municipio FROM unique_munis);"
      )

    # caso contrario, leia o parquet
  } else {
    query_unique_logradouros <- glue::glue(
      "CREATE TEMP TABLE IF NOT EXISTS {unique_logr_tbl_name} AS
            WITH unique_munis AS (
                SELECT DISTINCT municipio
                FROM input_padrao_db
            )

          SELECT {DISTINCT} {select_cols}
              FROM read_parquet('{path_to_parquet}') m
              WHERE m.municipio IN (SELECT municipio FROM unique_munis);"
    )
  }
  DBI::dbExecute(con, query_unique_logradouros)

  # set index ?
  # key_cols <- get_key_cols(match_type)

  return(unique_logr_tbl_name)
} # nocov end


# write_all_cnefe_tables_to_db <- function(con){
#
#   all_tables <- c("municipio_logradouro_numero_cep_localidade",
#                   "municipio_logradouro_numero_localidade",
#                   "municipio_logradouro_cep_localidade",
#                   "municipio_logradouro_localidade",
#                   "municipio_cep_localidade",
#                   "municipio_cep",
#                   "municipio_localidade",
#                   "municipio"
#   )
#
#
#   # build path to local file
#   files <- geocodebr::listar_dados_cache()
#
#
#   for (i in all_tables){
#
#     path_to_parquet <- files[grepl( paste0(i, ".parquet"), files)]
#
#     query_filter_cnefe <- glue::glue(
#       "CREATE TEMP TABLE {i} AS
#           WITH unique_munis AS (
#               SELECT DISTINCT municipio
#               FROM input_padrao_db
#           ),
#           unique_states AS (
#               SELECT DISTINCT estado
#               FROM input_padrao_db
#           )
#           SELECT *
#           FROM read_parquet('{path_to_parquet}') m
#           WHERE m.municipio IN (SELECT municipio FROM unique_munis)
#                AND m.estado IN (SELECT estado FROM unique_states);"
#
#     )
#
#     DBI::dbExecute(con, query_filter_cnefe)
#   }
#
# }

# register all geocodebr-cnefe tables
register_geocodebr_tables <- function(con) {
  # nocov start

  all_tables <- geocodebr::listar_dados_cache()

  for (i in all_tables) {
    tb_name <- basename(i)
    tb_name <- fs::path_ext_remove(tb_name)

    temp_arrow <- arrow::open_dataset(i)

    duckdb::duckdb_register_arrow(con, tb_name, temp_arrow)
  }
} # nocov ends
