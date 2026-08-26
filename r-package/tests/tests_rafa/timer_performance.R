#' Geolocaliza endereços no Brasil
#'
#' Geocodifica endereços brasileiros com base nos dados do CNEFE. Os endereços
#' de input devem ser passados como um `data.frame`, no qual cada coluna
#' descreve um campo do endereço (logradouro, número, cep, etc). Os resuldos dos
#' endereços geolocalizados podem seguir diferentes níveis de precisão. Consulte
#' abaixo a seção "Detalhes" para mais informações. As coordenadas de output
#' utilizam o sistema de coordenadas geográficas SIRGAS 2000, EPSG 4674.
#'
#' @param enderecos Um `data.frame`. Os endereços a serem geolocalizados. Cada
#'    coluna deve representar um campo do endereço.
#' @param campos_endereco Um vetor de caracteres. A correspondência entre cada
#'    campo de endereço e o nome da coluna que o descreve na tabela `enderecos`.
#'    A função [definir_campos()] auxilia na criação deste vetor e realiza
#'    algumas verificações nos dados de entrada. Campos de endereço passados
#'    como `NULL` serão ignorados, e a função deve receber pelo menos um campo
#'    não nulo, além  dos campos `"estado"` e `"municipio"`, que são
#'    obrigatórios. Note que o campo  `"localidade"` é equivalente a 'bairro'.
#' @param resultado_completo Lógico. Indica se o output deve incluir colunas
#'    adicionais, como o endereço encontrado de referência. Por padrão, é `FALSE`.
#' @param resolver_empates Lógico. Alguns resultados da geolocalização podem
#'    indicar diferentes coordenadas possíveis (e.g. duas ruas diferentes com o
#'    mesmo nome em uma mesma cidade). Esses casos são trados como 'empate' e o
#'    parâmetro `resolver_empates` indica se a função deve resolver esses empates
#'    automaticamente. Por padrão, é `FALSE`, e a função retorna apenas o caso
#'    mais provável. Para mais detalhes sobre como é feito o processo de
#'    desempate, consulte abaixo a seção "Detalhes".
#' @template h3_res
#' @template resultado_sf
#' @template verboso
#' @template cache
#' @template n_cores
#'
#' @return Retorna o `data.frame` de input `enderecos` adicionado das colunas de
#'   latitude (`lat`) e longitude (`lon`), bem como as colunas (`precisao` e
#'   `tipo_resultado`) que indicam o nível de precisão e o tipo de resultado.
#'   Alternativamente, o resultado pode ser um objeto `sf`.
#'
#' @template precision_section
#' @template empates_section
#'
#' @examplesIf identical(tolower(Sys.getenv("NOT_CRAN")), "true")
#' library(geocodebr)
#'
#' # ler amostra de dados
#' data_path <- system.file("extdata/small_sample.csv", package = "geocodebr")
#' input_df <- read.csv(data_path)[1:2,]
#'
#' fields <- geocodebr::definir_campos(
#'   logradouro = "nm_logradouro",
#'   numero = "Numero",
#'   cep = "Cep",
#'   localidade = "Bairro",
#'   municipio = "nm_municipio",
#'   estado = "nm_uf"
#' )
#'
#' df <- geocodebr::geocode(
#'   enderecos = input_df,
#'   campos_endereco = fields,
#'   resolver_empates = TRUE,
#'   verboso = FALSE
#'   )
#'
#' head(df)
#'
#' @export
geocode <- function(enderecos,
                    campos_endereco = definir_campos(),
                    resultado_completo = FALSE,
                    resolver_empates = FALSE,
                    h3_res = NULL,
                    resultado_sf = FALSE,
                    verboso = TRUE,
                    cache = TRUE,
                    n_cores = 1 ){


  ## ---- tiny timing toolkit (self-contained) ------------------------------
  .make_timer <- function(verbose = TRUE) {
    .marks <- list()
    .t0_rt  <- proc.time()[["elapsed"]]     # monotonic wall clock
    .t_prev <- .t0_rt

    fmt <- function(secs) sprintf("%.3f s", secs)

    mark <- function(label) {
      now <- proc.time()[["elapsed"]]
      step  <- now - .t_prev
      total <- now - .t0_rt
      .marks <<- append(.marks, list(list(label = label, step = step, total = total)))
      .t_prev <<- now
      if (verbose) message(sprintf("[%s] +%s (total %s)", label, fmt(step), fmt(total)))
      invisible(now)
    }

    summary <- function(print_summary = verbose) {
      if (length(.marks) == 0) return(invisible(data.frame()))
      df <- data.frame(
        step = vapply(.marks, `[[`, "", "label"),
        step_sec = vapply(.marks, `[[`, 0.0, "step"),
        total_sec = vapply(.marks, `[[`, 0.0, "total"),
        stringsAsFactors = FALSE
      ) |>
        dplyr::mutate(step_relative = round(step_sec / max(total_sec)*100, 1))

      if (print_summary) {
        message("— Timing summary —")
        print(df, row.names = FALSE)
      }
      df
    }

    time_it <- function(label, expr) {
      force(label)
      res <- eval.parent(substitute(expr))
      mark(label)
      invisible(res)
    }

    list(mark = mark, summary = summary, time_it = time_it)
  }
  timer <- .make_timer(verbose = isTRUE(verboso))
  on.exit(timer$summary(), add = TRUE)
  ## -----------------------------------------------------------------------


  # check input
  checkmate::assert_data_frame(enderecos)
  checkmate::assert_logical(resultado_completo, any.missing = FALSE, len = 1)
  checkmate::assert_logical(resolver_empates, any.missing = FALSE, len = 1)
  checkmate::assert_logical(resultado_sf, any.missing = FALSE, len = 1)
  checkmate::assert_logical(verboso, any.missing = FALSE, len = 1)
  checkmate::assert_logical(cache, any.missing = FALSE, len = 1)
  checkmate::assert_number(n_cores, lower = 1, finite = TRUE)
  checkmate::assert_number(h3_res, null.ok = TRUE, lower = 0, upper = 15)
  campos_endereco <- assert_and_assign_address_fields(
    campos_endereco,
    enderecos
  )

  # normalize input data -------------------------------------------------------

  # standardizing the addresses table to increase the chances of finding a match
  # in the CNEFE data

  if (verboso) message_standardizing_addresses()

  # systime start 66666 ----------------
  timer$mark("Start")

  input_padrao <- enderecobr::padronizar_enderecos(
    enderecos,
    campos_do_endereco = enderecobr::correspondencia_campos(
      logradouro = campos_endereco[["logradouro"]],
      numero = campos_endereco[["numero"]],
      cep = campos_endereco[["cep"]],
      bairro = campos_endereco[["localidade"]],
      municipio = campos_endereco[["municipio"]],
      estado = campos_endereco[["estado"]]
    ),
    formato_estados = "sigla",
    formato_numeros = 'integer'
  )


  # keep and rename colunms of input_padrao to use the
  # same column names used in cnefe data set
  data.table::setDT(input_padrao)
  cols_to_keep <- names(input_padrao)[ names(input_padrao) %like% '_padr']
  input_padrao <- input_padrao[, .SD, .SDcols = c(cols_to_keep)]
  names(input_padrao) <- c(gsub("_padr", "", names(input_padrao)))

  if ('bairro' %in% names(input_padrao)) {
    data.table::setnames(
      x = input_padrao, old = 'bairro', new = 'localidade'
    )
  }

  # systime padronizacao 66666 ----------------
  timer$mark("Padronizacao")


  # create temp id
  data.table::setDT(enderecos)[, tempidgeocodebr := 1:nrow(input_padrao) ]
  input_padrao[, tempidgeocodebr := 1:nrow(input_padrao) ]

  # temp coluna de logradouro q sera usada no match probabilistico
  input_padrao[, temp_lograd_determ := NA_character_ ]
  input_padrao[, similaridade_logradouro := NA_real_ ]

  # # sort input data
  # input_padrao <- input_padrao[order(estado, municipio, logradouro, numero, cep, localidade)]

  # downloading cnefe
  cnefe_dir <- download_cnefe(
    tabela = 'todas',
    verboso = verboso,
    cache = cache
  )

  # creating a temporary db and register the input table data
  con <- create_geocodebr_db(n_cores = n_cores)



  # register standardized input data
  input_padrao_arrw <- arrow::as_arrow_table(input_padrao)
  DBI::dbWriteTableArrow(con, name = "input_padrao_db", input_padrao_arrw,
                         overwrite = TRUE, temporary = TRUE)


  # systime register standardized 66666 ----------------
  timer$mark("Register standardized input")


  # cria coluna "log_causa_confusao" identificando logradouros que geram confusao
  # issue https://github.com/ipeaGIT/geocodebr/issues/67
  cria_col_logradouro_confusao(con)


  # systime cria coluna "log_causa_confusao 66666 ----------------
  timer$mark("Cria coluna log_causa_confusao")



  # create an empty output table that will be populated -----------------------------------------------

  # Define schema
  schema_output_db <- arrow::schema(
    tempidgeocodebr = arrow::int32(),
    lat = arrow::float16(),  # Equivalent to NUMERIC(8,6)
    lon = arrow::float16(),
    endereco_encontrado = arrow::string(),
    logradouro_encontrado = arrow::string(),
    tipo_resultado = arrow::string(),
    contagem_cnefe = arrow::int32(),
    desvio_metros = arrow::int32(),
    log_causa_confusao = arrow::boolean()
  )

  if (isTRUE(resultado_completo)) {

    schema_output_db <- arrow::schema(
      tempidgeocodebr = arrow::int32(),
      lat = arrow::float16(),  # Equivalent to NUMERIC(8,6)
      lon = arrow::float16(),
      endereco_encontrado = arrow::string(),
      logradouro_encontrado = arrow::string(),
      tipo_resultado = arrow::string(),
      contagem_cnefe = arrow::int32(),
      desvio_metros = arrow::int32(),
      log_causa_confusao = arrow::boolean(),
      #
      numero_encontrado = arrow::int32(),
      localidade_encontrada = arrow::string(),
      cep_encontrado = arrow::string(),
      municipio_encontrado = arrow::string(),
      estado_encontrado = arrow::string(),
      similaridade_logradouro = arrow::float16()
    )
  }

  output_db_arrow <- arrow::arrow_table(schema = schema_output_db)
  DBI::dbWriteTableArrow(con, name = "output_db", output_db_arrow,
                         overwrite = TRUE, temporary = TRUE)


  # START MATCHING -----------------------------------------------

  # start progress bar
  if (verboso) {
    prog <- create_progress_bar(input_padrao)
    message_looking_for_matches()
  }

  n_rows <- nrow(input_padrao)
  matched_rows <- 0

  # start matching
  for (match_type in all_possible_match_types ) {

    # get key cols
    key_cols <- get_key_cols(match_type)

    if (verboso) update_progress_bar(matched_rows, match_type)

    # somente busca essa categoria match_type se todas colunas estiverem na base
    # caso contrario, passa para proxima categoria
    if (all(key_cols %in% names(input_padrao))) {

      # select match function
      match_fun <-
        if (match_type %in% c(number_exact_types, exact_types_no_number)) { match_cases
        } else if (match_type %in% number_interpolation_types ) { match_weighted_cases
        } else if (match_type %in% c(probabilistic_exact_types, probabilistic_types_no_number)) { match_cases_probabilistic
        } else if (match_type %in% probabilistic_interpolation_types) { match_weighted_cases_probabilistic
        }

      n_rows_affected <- match_fun(
        con,
        match_type = match_type,
        key_cols = key_cols,
        resultado_completo = resultado_completo
      )

      matched_rows <- matched_rows + n_rows_affected

      # leave the loop early if we find all addresses before covering all cases
      if (matched_rows == n_rows) break
    }

  }

  if (verboso) finish_progress_bar(matched_rows)

  # systime matching 66666 ----------------
  timer$mark("Matching")


  if (verboso) message_preparando_output()

  # add precision column
  add_precision_col(con, update_tb = 'output_db')


  # systime add precision 66666 ----------------
  timer$mark("Add precision")


  # casos de empate -----------------------------------------------

  empates_resolvidos <- trata_empates_geocode_duckdb3(con, resolver_empates, verboso)



  # systime resolve empates 66666 ----------------
  timer$mark("Resolve empates")


  # bring original input back -----------------------------------------------

  # output with all original columns
  duckdb::dbWriteTable(con, "input_db", enderecos,
                       temporary = TRUE, overwrite=TRUE)
  # enderecos_arrw <- arrow::as_arrow_table(enderecos)
  # DBI::dbWriteTableArrow(con, name = "input_db", enderecos_arrw,
  #                        overwrite = TRUE, temporary = TRUE)


  # systime write original input back 66666 ----------------
  timer$mark("Write original input back")



  x_columns <- names(enderecos)

  output_df <- merge_results_to_input(
    con,
    x='input_db',
    y='output_db2',
    key_column='tempidgeocodebr',
    select_columns = x_columns,
    resultado_completo = resultado_completo
  )

  # systime merge results 66666 ----------------
  timer$mark("Merge results")


  data.table::setDT(output_df)

  # drop geocodebr temp id column
  output_df[, tempidgeocodebr := NULL]


  # Disconnect from DuckDB when done
  duckdb::dbDisconnect(con)



  if(isFALSE(resultado_completo)){ output_df[, logradouro_encontrado := NULL]}

  # add H3
  if( !is.null(h3_res) ) {

    colname <- paste0(
      'h3_',
      formatC(h3_res, width = 2, flag = "0")
    )

    output_df[!is.na(lat),
              {{colname}} := h3r::latLngToCell(lat = lat,
                                               lng = lon,
                                               resolution = h3_res)
    ]

    # systime add h3 66666 ----------------
    timer$mark("Add H3")

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

    # systime convert to sf 66666 ----------------
    timer$mark("Convert to sf")

    return(output_sf)
  }

  return(output_df[])
}





# cad unico 1 milhao de casos

# resolve empate com duckdb2
#                           step step_sec total_sec
#                          Start     0.01      0.01
#                   Padronizacao    17.11     17.12
#    Register standardized input     2.19     19.31
# Cria coluna log_causa_confusao     0.05     19.36
#                       Matching    90.73    110.09
#                  Add precision     0.19    110.28
#                Resolve empates   338.43    448.71
#      Write original input back     0.40    449.11
#                  Merge results     2.57    451.68
#                         Add H3     1.91    453.59
#                  Convert to sf     2.28    455.87

# resolve empate com duckdb 3
#                           step step_sec total_sec
#                          Start     0.02      0.02
#                   Padronizacao    17.28     17.30
#    Register standardized input     2.13     19.43
# Cria coluna log_causa_confusao     0.04     19.47
#                       Matching    95.38    114.85
#                  Add precision     0.20    115.05
#                Resolve empates    10.33    125.38
#      Write original input back     0.39    125.77
#                  Merge results     3.11    128.88
#                         Add H3     1.64    130.52
#                  Convert to sf     2.30    132.82


# resolve empate com data.table
#                            step step_sec total_sec
#                           Start     0.04      0.04
#                    Padronizacao    19.32     19.36
#     Register standardized input     2.82     22.18
#  Cria coluna log_causa_confusao     0.08     22.26
#                        Matching   112.00    134.26
#                   Add precision     0.17    134.43
#       Write original input back     0.41    134.84
#                   Merge results     5.77    140.61
#                 Resolve empates    23.28    163.89
#                          Add H3     1.47    165.36
#                   Convert to sf     3.09    168.45

# ----------------------------------------------------------------------------

# NAO resolve empate com duckdb2
#                            step step_sec total_sec
#                           Start     0.01      0.01
#                    Padronizacao    18.21     18.22
#     Register standardized input     2.17     20.39
#  Cria coluna log_causa_confusao     0.05     20.44
#                        Matching   100.59    121.03
#                   Add precision     0.17    121.20
#                 Resolve empates     6.13    127.33
#       Write original input back     0.34    127.67
#                   Merge results     3.81    131.48
#                          Add H3     1.86    133.34
#                   Convert to sf     2.99    136.33


# NAO resolve empate com data.table
#                           step step_sec total_sec
#                          Start     0.02      0.02
#                   Padronizacao    18.03     18.05
#    Register standardized input     2.61     20.66
# Cria coluna log_causa_confusao     0.06     20.72
#                       Matching    98.80    119.52
#                  Add precision     0.17    119.69
#      Write original input back     0.36    120.05
#                  Merge results     4.73    124.78
#                Resolve empates     6.72    131.50
#                         Add H3     1.45    132.95
#                  Convert to sf     2.19    135.14




# resolve empate com data.table 3 (43 milhoes)
#                           step step_sec total_sec
#                          Start     0.02      0.02
#                   Padronizacao   433.21    433.23
#    Register standardized input    79.50    512.73
# Cria coluna log_causa_confusao     2.86    515.59
#                       Matching  2163.66   2679.25
#                  Add precision    87.53   2766.78
#      Write original input back    47.19   2813.97
#                  Merge results  1913.81   4727.78
#                Resolve empates  1302.81   6030.59
#                         Add H3    51.11   6081.70
#                  Convert to sf   422.74   6504.44


# resolve empate com duckdb 3 OLD (43 milhoes)
#
#                           step step_sec total_sec
#                          Start     0.00      0.00
#                   Padronizacao   432.72    432.72
#    Register standardized input    81.80    514.52
# Cria coluna log_causa_confusao     2.86    517.38
#                       Matching  2293.57   2810.95
#                  Add precision    88.21   2899.16
#                Resolve empates  3043.82   5942.98
#      Write original input back    67.85   6010.83
#                  Merge results   436.00   6446.83
#                         Add H3   479.51   6926.34
#                  Convert to sf   297.13   7223.47



# resolve empate com duckdb 3 NEW (43 milhoes)
#                           step step_sec total_sec step_relative
#                          Start     0.03      0.03           0.0
#                   Padronizacao   445.64    445.67           6.2
#    Register standardized input    80.77    526.44           1.1
# Cria coluna log_causa_confusao     2.56    529.00           0.0
#                       Matching  2402.55   2931.55          33.3
#                  Add precision   107.81   3039.36           1.5
#                Resolve empates  2677.19   5716.55          37.1
#      Write original input back    67.67   5784.22           0.9
#                  Merge results   526.64   6310.86           7.3
#                         Add H3   545.69   6856.55           7.6
#                  Convert to sf   362.96   7219.51           5.0



# resolve empate com duckdb 3 NEW (43 milhoes) precisao pra depois
#                           step step_sec total_sec step_relative
#                          Start     0.03      0.03           0.0
#                   Padronizacao   431.75    431.78           7.1
#    Register standardized input    79.56    511.34           1.3
# Cria coluna log_causa_confusao     2.68    514.02           0.0
#                       Matching  2077.87   2591.89          34.0
#                Resolve empates  2176.24   4768.13          35.6
#      Write original input back    57.73   4825.86           0.9
#                  Add precision    64.05   4889.91           1.0
#                  Merge results   413.50   5303.41           6.8
#                         Add H3   449.43   5752.84           7.4
#                  Convert to sf   352.99   6105.83           5.8




