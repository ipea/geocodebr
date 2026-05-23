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
#'    automaticamente. Por padrão, é `TRUE`, e a função retorna apenas o caso
#'    mais provável. Para mais detalhes sobre como é feito o processo de
#'    desempate, consulte abaixo a seção "Detalhes".
#' @template resultado_sf
#' @template h3_res
#' @param padronizar_enderecos Lógico. Indica se os dados de endereço de entrada
#'    devem ser padronizados. Por padrão, é `TRUE`. Essa padronização é essencial
#'    para uma geolocalizaçao correta. Alerta! Apenas utilize
#'    `padronizar_enderecos = FALSE` caso os dados de input já tenham sido
#'    padronizados anteriormente com `enderecobr::padronizar_enderecos(..., formato_estados = 'sigla', formato_numeros = 'integer')`.
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
#'   resolver_empates = TRUE
#'   )
#'
#' head(df)
#'
#' @export
geocode <- function(
  enderecos,
  campos_endereco = definir_campos(),
  resultado_completo = FALSE,
  resolver_empates = TRUE,
  resultado_sf = FALSE,
  h3_res = NULL,
  padronizar_enderecos = TRUE,
  verboso = TRUE,
  cache = TRUE,
  n_cores = NULL
) {
  callr::r(
    func = function(
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
    ) {
      # Run internal engine
      geocode_core(
        enderecos = enderecos,
        campos_endereco = campos_endereco,
        resultado_completo = resultado_completo,
        resolver_empates = resolver_empates,
        resultado_sf = resultado_sf,
        h3_res = h3_res,
        padronizar_enderecos = padronizar_enderecos,
        verboso = verboso,
        cache = cache,
        n_cores = n_cores
      )
    },
    args = list(
      enderecos = enderecos,
      campos_endereco = campos_endereco,
      resultado_completo = resultado_completo,
      resolver_empates = resolver_empates,
      resultado_sf = resultado_sf,
      h3_res = h3_res,
      padronizar_enderecos = padronizar_enderecos,
      verboso = verboso,
      cache = cache,
      n_cores = n_cores
    ),
    show = TRUE,
    package = TRUE
  )
}


#' @keywords internal
geocode_core <- function(
  enderecos = parent.frame()$enderecos,
  campos_endereco = parent.frame()$campos_endereco,
  resultado_completo = parent.frame()$resultado_completo,
  resolver_empates = parent.frame()$resolver_empates,
  resultado_sf = parent.frame()$resultado_sf,
  h3_res = parent.frame()$h3_res,
  padronizar_enderecos = parent.frame()$padronizar_enderecos,
  verboso = parent.frame()$verboso,
  cache = parent.frame()$cache,
  n_cores = parent.frame()$n_cores
) {
  # ## ---- tiny timing toolkit (self-contained) ------------------------------
  # .make_timer <- function(verbose = TRUE) {
  #   .marks <- list()
  #   .t0_rt  <- proc.time()[["elapsed"]]     # monotonic wall clock
  #   .t_prev <- .t0_rt
  #
  #   fmt <- function(secs) sprintf("%.3f s", secs)
  #
  #   mark <- function(label) {
  #     now <- proc.time()[["elapsed"]]
  #     step  <- now - .t_prev
  #     total <- now - .t0_rt
  #     .marks <<- append(.marks, list(list(label = label, step = step, total = total)))
  #     .t_prev <<- now
  #     if (verbose) message(sprintf("[%s] +%s (total %s)", label, fmt(step), fmt(total)))
  #     invisible(now)
  #   }
  #
  #   summary <- function(print_summary = verbose) {
  #     if (length(.marks) == 0) return(invisible(data.frame()))
  #     df <- data.frame(
  #       step = vapply(.marks, `[[`, "", "label"),
  #       step_sec = vapply(.marks, `[[`, 0.0, "step"),
  #       total_sec = vapply(.marks, `[[`, 0.0, "total"),
  #       stringsAsFactors = FALSE
  #     ) |>
  #       dplyr::mutate(step_relative = round(step_sec / max(total_sec)*100, 1))
  #
  #     if (print_summary) {
  #       message("— Timing summary —")
  #       print(df, row.names = FALSE)
  #     }
  #     df
  #   }
  #
  #   time_it <- function(label, expr) {
  #     force(label)
  #     res <- eval.parent(substitute(expr))
  #     mark(label)
  #     invisible(res)
  #   }
  #
  #   list(mark = mark, summary = summary, time_it = time_it)
  # }
  # timer <- .make_timer(verbose = isTRUE(verboso))
  # on.exit(timer$summary(), add = TRUE)
  # ## -----------------------------------------------------------------------

  # check input
  checkmate::assert_data_frame(enderecos)
  checkmate::assert_logical(resultado_completo, any.missing = FALSE, len = 1)
  checkmate::assert_logical(resolver_empates, any.missing = FALSE, len = 1)
  checkmate::assert_logical(resultado_sf, any.missing = FALSE, len = 1)
  checkmate::assert_logical(padronizar_enderecos, any.missing = FALSE, len = 1)
  checkmate::assert_logical(verboso, any.missing = FALSE, len = 1)
  checkmate::assert_logical(cache, any.missing = FALSE, len = 1)
  checkmate::assert_numeric(
    h3_res,
    null.ok = TRUE,
    lower = 0,
    upper = 15,
    max.len = 16
  )

  # allow only letters, numbers, and underscore in colnames
  check_clean_colnames(enderecos)


  # systime start 66666 ----------------
  # timer$mark("Start")

  # fix eventual missing fields in input data -------------------------------------------------------
  # geocodebr requires all address fields to be declared
  # if one or more fields are empty, we add mock columns with empty strings

  campos_endereco <- assert_and_assign_address_fields(
    campos_endereco,
    enderecos
  )

  # determine which columns are missing, if any
  missing_cols <- campos_endereco[unlist(lapply(campos_endereco, is.null))]

  if (length(missing_cols)>=1) {

    # add empty string to missing cols
    data.table::setDT(enderecos)
    new_colnames <- paste0(names(missing_cols), "tempgeocodebr")
    enderecos[, (new_colnames) := NA_character_ ]

    # update address fields with fake columns
    campos_endereco[sapply(campos_endereco, is.null)] <- as.list(new_colnames)
  }


  # normalize input data -------------------------------------------------------
  # standardizing the addresses table to increase the chances of finding a match
  # in the CNEFE data

  if (isTRUE(padronizar_enderecos)) {
    if (verboso) {
      message_standardizing_addresses()
    }

    input_padrao <- enderecobr::padronizar_enderecos(
      enderecos = enderecos,
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
  }

  if (isFALSE(padronizar_enderecos)) {
    input_padrao <- data.table::copy(enderecos)
  }

  # checa se input foi mesmo padronizado
  all_cols_padr <- c(
    "estado_padr",
    "municipio_padr",
    "logradouro_padr",
    "numero_padr",
    "cep_padr",
    "bairro_padr"
  )
  check_padr <- all(all_cols_padr %in% names(input_padrao))

  if (isFALSE(check_padr)) {
    error_input_nao_padronizado()
  }

  # keep and rename colunms of input_padrao to use the
  # same column names used in cnefe data set
  data.table::setDT(input_padrao)
  cols_to_keep <- names(input_padrao)[names(input_padrao) %like% '_padr']
  input_padrao <- input_padrao[, .SD, .SDcols = c(cols_to_keep)]
  names(input_padrao) <- c(gsub("_padr", "", names(input_padrao)))

  if ('bairro' %in% names(input_padrao)) {
    data.table::setnames(
      x = input_padrao,
      old = 'bairro',
      new = 'localidade'
    )
  }

  # systime padronizacao 66666 ----------------
  # timer$mark("Padronizacao")

  # create temp id
  data.table::setDT(enderecos)[, tempidgeocodebr := 1:nrow(input_padrao)]
  input_padrao[, tempidgeocodebr := 1:nrow(input_padrao)]

  # temp coluna de logradouro q sera usada no match probabilistico
  input_padrao[, temp_lograd_determ := NA_character_]
  input_padrao[, similaridade_logradouro := NA_real_]

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
  DBI::dbWriteTableArrow(
    con,
    name = "input_padrao_db",
    input_padrao_arrw,
    overwrite = TRUE,
    temporary = TRUE
  )

  # systime register standardized 66666 ----------------
  # timer$mark("Register standardized input")

  # cria coluna "log_causa_confusao" identificando logradouros que geram confusao
  # issue https://github.com/ipeaGIT/geocodebr/issues/67
  cria_col_logradouro_confusao(con)

  # create an empty output table that will be populated -----------------------------------------------

  # Define schema
  if (isFALSE(resultado_completo)) {

    schema_output_db <- arrow::schema(
      tempidgeocodebr = arrow::int32(),
      lat = arrow::float16(),
      # Equivalent to NUMERIC(8,6)
      lon = arrow::float16(),
      endereco_encontrado = arrow::string(),
      logradouro_encontrado = arrow::string(),
      tipo_resultado = arrow::string(),
      contagem_cnefe = arrow::int32(),
      desvio_metros = arrow::int32(),
      log_causa_confusao = arrow::boolean(),
      similaridade_logradouro = arrow::float16()
    )

  } else {
    schema_output_db <- arrow::schema(
      tempidgeocodebr = arrow::int32(),
      lat = arrow::float16(),
      # Equivalent to NUMERIC(8,6)
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
      similaridade_logradouro = arrow::float16(),
      cod_setor = arrow::string()
    )
  }

  output_db_arrow <- arrow::arrow_table(schema = schema_output_db)
  DBI::dbWriteTableArrow(
    con,
    name = "output_db",
    output_db_arrow,
    overwrite = TRUE,
    temporary = TRUE
  )

  # START MATCHING -----------------------------------------------

  # start progress bar
  if (verboso) {
    prog <- create_progress_bar(input_padrao)
    message_looking_for_matches()
  }

  n_rows <- nrow(input_padrao)
  matched_rows <- 0

  # start matching
  for (match_type in all_possible_match_types) {
    # get key cols
    key_cols <- get_key_cols(match_type)

    if (verboso) {
      update_progress_bar(matched_rows, match_type)
    }

    # somente busca essa categoria match_type se todas colunas estiverem na base
    # caso contrario, passa para proxima categoria
    if (all(key_cols %in% names(input_padrao))) {
      # select match function
      match_fun <-
        if (match_type %in% c(number_exact_types, exact_types_no_number)) {
          match_cases
        } else if (match_type %in% number_interpolation_types) {
          match_weighted_cases
        } else if (
          match_type %in%
            c(probabilistic_exact_types, probabilistic_types_no_number)
        ) {
          match_cases_probabilistic
        } else if (match_type %in% probabilistic_interpolation_types) {
          match_weighted_cases_probabilistic
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

  if (verboso) {
    finish_progress_bar(matched_rows)
  }

  # systime matching 66666 ----------------
  # timer$mark("Matching")

  if (verboso) {
    message_preparando_output()
  }

  # casos de empate -----------------------------------------------

  empates_resolvidos <- trata_empates_geocode_duckdb(
    con,
    resultado_completo,
    resolver_empates,
    verboso
  )

  # systime resolve empates 66666 ----------------
  # timer$mark("Resolve empates")

  # bring original input back -----------------------------------------------

  # output with all original columns
  duckdb::dbWriteTable(
    con,
    "input_db",
    enderecos,
    temporary = TRUE,
    overwrite = TRUE
  )
  # enderecos_arrw <- arrow::as_arrow_table(enderecos)
  # DBI::dbWriteTableArrow(con, name = "input_db", enderecos_arrw,
  #                        overwrite = TRUE, temporary = TRUE)

  # systime write original input back 66666 ----------------
  # timer$mark("Write original input back")

  # add precision column ----------------
  output_table_to_use <- ifelse(
    empates_resolvidos == 0,
    'output_db',
    'output_db2'
  )
  add_precision_col(con, update_tb = output_table_to_use)

  # systime add precision 66666 ----------------
  # timer$mark("Add precision")

  x_columns <- names(enderecos)

  output_df <- merge_results_to_input(
    con,
    x = 'input_db',
    y = output_table_to_use,
    key_column = 'tempidgeocodebr',
    select_columns = x_columns,
    resultado_completo = resultado_completo
  )

  # systime merge results 66666 ----------------
  # timer$mark("Merge results")

  data.table::setDT(output_df)

  # drop geocodebr temp id column
  output_df[, tempidgeocodebr := NULL]

  # # col precisao como ordered factor
  # ordem_precisao <- c(
  #   "numero",
  #   "numero_aproximado",
  #   "logradouro",
  #   "cep",
  #   "localidade",
  #   "municipio"
  # )
  # output_df[, precisao := factor(
  #   precisao,
  #   levels = ordem_precisao,
  #   ordered = TRUE
  # )]

  # Disconnect from DuckDB when done
  duckdb::dbDisconnect(con)

  # add H3
  if (!is.null(h3_res)) {
    for (i in h3_res) {
      colname <- paste0(
        'h3_',
        formatC(h3_res, width = 2, flag = "0")
      )

      output_df[
        !is.na(lat),
        {{ colname }} := h3r::latLngToCell(lat = lat, lng = lon, resolution = i)
      ]
    }

    # systime add h3 66666 ----------------
    # timer$mark("Add H3")
  }

  # drop eventual mock columns with empty strings
  if (length(missing_cols)>=1) {
    output_df[, (new_colnames) := NULL]
  }

  # remove data.table class
  data.table::setindex(output_df, NULL)
  data.table::setDF(output_df)

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
    # timer$mark("Convert to sf")

    return(output_sf)
  }

  return(output_df[])
}
