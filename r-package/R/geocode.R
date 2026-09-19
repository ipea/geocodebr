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
#'    obrigatórios. Note que o campo  `"localidade"` é equivalente a 'bairro', e
#'    que o campo `"lograoduro"` deve conter o tipo e o nome do logradouro (e.g.
#'    "Rua Castro Alves", "Avenida Ipiranga").
#' @param resultado_completo Lógico. Indica se o output deve incluir colunas
#'    adicionais, como o endereço encontrado de referência. Por padrão, é `FALSE`.
#' @param resolver_empates Lógico. Alguns resultados da geolocalização podem
#'    indicar diferentes coordenadas possíveis (e.g. duas ruas diferentes com o
#'    mesmo nome em uma mesma cidade). Esses casos são trados como 'empate' e o
#'    parâmetro `resolver_empates` indica se a função deve resolver esses empates
#'    automaticamente. Por padrão, é `TRUE`, e a função retorna apenas o caso
#'    mais provável, preservando uma linha de output por linha de input. Com
#'    `FALSE`, cada endereço empatado retorna uma linha por coordenada candidata
#'    (o output pode ter mais linhas que o input) e a coluna `empate` é incluída
#'    no output para identificar esses casos. Para mais detalhes sobre como é
#'    feito o processo de desempate, consulte abaixo a seção "Detalhes".
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
  # O corpo roda em um subprocesso via callr. Atencao: o subprocesso NAO herda o
  # namespace desta sessao - ele carrega o geocodebr que estiver instalado na
  # biblioteca (.libPaths()). Se os dois divergirem - tipico ao desenvolver com
  # devtools::load_all(), ou com uma instalacao antiga na biblioteca - as funcoes
  # internas simplesmente somem la dentro ("could not find function geocode_core").
  # Por isso: em modo dev, mandamos o subprocesso carregar o mesmo codigo-fonte;
  # fora dele, conferimos que as versoes batem antes de rodar.
  dev_path <- caminho_pacote_dev()
  versao_sessao <- as.character(getNamespaceVersion(asNamespace("geocodebr")))

  # O resultado NAO volta do subprocesso como objeto R. O filho grava o output
  # em parquet neste caminho e devolve so o caminho; o pai le com arrow. Trazer
  # 43M de linhas como data.frame serializado pelo callr custava ~160s (RDS de
  # ida e volta) mais uma copia de ~7GB dentro do filho. Barras normalizadas
  # porque o caminho vai literal para dentro de um COPY ... TO '<path>' do DuckDB
  arquivo_saida <- normalizePath(
    tempfile(pattern = "geocodebr_output", fileext = ".parquet"),
    winslash = "/",
    mustWork = FALSE
  )
  on.exit(unlink(arquivo_saida), add = TRUE)

  resumo_filho <- callr::r(
    func = function(
      dev_path,
      versao_sessao,
      enderecos,
      campos_endereco,
      resultado_completo,
      resolver_empates,
      resultado_sf,
      h3_res,
      padronizar_enderecos,
      verboso,
      cache,
      n_cores,
      arquivo_saida
    ) {
      if (!is.null(dev_path)) {
        if (!requireNamespace("pkgload", quietly = TRUE)) {
          stop(
            "O geocodebr foi carregado em modo de desenvolvimento ",
            "(devtools::load_all()), e o pacote 'pkgload' e necessario para ",
            "reproduzir esse carregamento no subprocesso usado por geocode(). ",
            "Instale o pkgload ou instale o geocodebr normalmente.",
            call. = FALSE
          )
        }
        pkgload::load_all(dev_path, quiet = TRUE)
      }

      ns <- asNamespace("geocodebr")
      versao_subprocesso <- as.character(getNamespaceVersion(ns))
      if (!identical(versao_subprocesso, versao_sessao)) {
        stop(
          "Divergencia de versao do geocodebr: a sessao usa a ", versao_sessao,
          " e o subprocesso interno carregou a ", versao_subprocesso,
          " de ", dirname(getNamespaceInfo(ns, "path")), ". ",
          "Reinstale o geocodebr para que as duas coincidam.",
          call. = FALSE
        )
      }

      # Run internal engine
      # resultado_sf/h3_res seguem sendo passados mesmo que o pos-processamento
      # (H3, sf) rode no processo pai: e o geocode_core() que valida os dois com
      # checkmate, e essa validacao precisa continuar acontecendo aqui
      geocode_core <- get("geocode_core", envir = ns)
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
        n_cores = n_cores,
        arquivo_saida = arquivo_saida
      )
    },
    args = list(
      dev_path = dev_path,
      versao_sessao = versao_sessao,
      enderecos = enderecos,
      campos_endereco = campos_endereco,
      resultado_completo = resultado_completo,
      resolver_empates = resolver_empates,
      resultado_sf = resultado_sf,
      h3_res = h3_res,
      padronizar_enderecos = padronizar_enderecos,
      verboso = verboso,
      cache = cache,
      n_cores = n_cores,
      arquivo_saida = arquivo_saida
    ),
    show = TRUE,
    package = FALSE
  )

  # le o resultado gravado pelo filho ------------------------------------------
  # altrep desligado de proposito: com altrep as colunas voltam lazy e o custo de
  # materializacao apenas migra para a primeira vez que cada coluna e tocada
  # (inclusive dentro do setDT/H3 abaixo), o que torna o ganho ilusorio
  old_altrep <- getOption("arrow.use_altrep")
  options(arrow.use_altrep = FALSE)
  on.exit(options(arrow.use_altrep = old_altrep), add = TRUE)

  output_df <- tryCatch(
    as.data.frame(arrow::read_parquet(resumo_filho$arquivo)),
    error = function(e) {
      cli::cli_abort(
        c(
          "Nao foi possivel ler o resultado intermediario do geocode().",
          "x" = "Falha ao ler {.file {resumo_filho$arquivo}}: {conditionMessage(e)}"
        ),
        call = NULL
      )
    }
  )

  # factor, tzone de POSIXct e difftime nao sobrevivem ao parquet -- reconstroi
  # usando o input original, que continua intacto neste processo, como gabarito
  output_df <- restaura_classes_input(output_df, enderecos)

  # pos-processamento que antes rodava dentro do filho
  pos_processa_output(
    output_df = output_df,
    h3_res = h3_res,
    resultado_sf = resultado_sf
  )
}


# Caminho do codigo-fonte quando o pacote foi carregado com devtools::load_all().
# Retorna NULL quando estamos rodando a versao instalada normalmente.
caminho_pacote_dev <- function() {
  ns <- asNamespace("geocodebr")
  if (exists(".__DEVTOOLS__", envir = ns, inherits = FALSE)) {
    getNamespaceInfo(ns, "path")
  } else {
    NULL
  }
}


#' @keywords internal
#
# arquivo_saida: string ou NULL. Caminho de um .parquet onde o resultado deve ser
#   gravado em vez de devolvido como data.frame. Com NULL (padrao), a funcao
#   devolve o resultado pos-processado, como sempre. Com um caminho, o resultado
#   sai do DuckDB direto para disco e a funcao devolve, invisivelmente, apenas
#   list(arquivo =, new_colnames =) -- o pos-processamento (colunas-fantasma, H3,
#   sf) fica a cargo de quem chamou. Usado por geocode() para nao trazer o
#   resultado inteiro de volta pelo callr.
geocode_core <- function(
  enderecos,
  campos_endereco,
  resultado_completo,
  resolver_empates,
  resultado_sf,
  h3_res,
  padronizar_enderecos,
  verboso,
  cache,
  n_cores,
  arquivo_saida = NULL
) {
  # ## ---- tiny timing toolkit (self-contained) ------------------------------
  # .make_timer <- function(verbose = TRUE) {
  #   .marks <- list()
  #   .t0_rt  <- proc.time()[["elapsed"]]     # monotonic wall clock
  #   .t_prev <- .t0_rt
  
  #   fmt <- function(secs) sprintf("%.3f s", secs)
  
  #   mark <- function(label) {
  #     now <- proc.time()[["elapsed"]]
  #     step  <- now - .t_prev
  #     total <- now - .t0_rt
  #     .marks <<- append(.marks, list(list(label = label, step = step, total = total)))
  #     .t_prev <<- now
  #     if (verbose) message(sprintf("[%s] +%s (total %s)", label, fmt(step), fmt(total)))
  #     invisible(now)
  #   }
  
  #   summary <- function(print_summary = verbose) {
  #     if (length(.marks) == 0) return(invisible(data.frame()))
  #     df <- data.frame(
  #       step = vapply(.marks, `[[`, "", "label"),
  #       step_sec = vapply(.marks, `[[`, 0.0, "step"),
  #       total_sec = vapply(.marks, `[[`, 0.0, "total"),
  #       stringsAsFactors = FALSE
  #     )
  #     df$step_relative <- round(df$step_sec / max(df$total_sec) * 100, 1)
  
  #     if (print_summary) {
  #       message("-- Timing summary --")
  #       print(df, row.names = FALSE)
  #     }
  #     df
  #   }
  
  #   time_it <- function(label, expr) {
  #     force(label)
  #     res <- eval.parent(substitute(expr))
  #     mark(label)
  #     invisible(res)
  #   }
  
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

  # nomes dos campos que o usuario nao declarou -- viram coluna-fantasma
  # NA_character_ logo abaixo, entao nenhum match_type cujo key_cols inclua
  # um desses campos pode gerar match (o filtro "IS NOT NULL" da query de
  # match sempre vai zerar). Usado no laco de matching mais abaixo para pular
  # essas etapas sem materializar a tabela de referencia correspondente.
  campos_nao_declarados <- names(missing_cols)

  # nomes das colunas-fantasma efetivamente criadas (vazio quando o usuario
  # declarou todos os campos)
  new_colnames <- character(0)

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

    # padroniza campo a campo em vez de uma chamada unica a
    # enderecobr::padronizar_enderecos() sobre a tabela inteira: cada coluna passa
    # por padronizar_dedup() (ver R/utils.R), que padroniza so os valores
    # distintos daquele campo e expande de volta com chmatch(). O resultado e
    # identical() ao da chamada antiga, incluindo a ORDEM das colunas
    # (logradouro, numero, cep, localidade, municipio, estado), que precisa ser
    # preservada porque define o schema da tabela gravada no DuckDB.
    input_padrao <- data.table::data.table(
      logradouro = padronizar_dedup(
        enderecos[[campos_endereco[["logradouro"]]]],
        "logradouro"
      ),
      numero = padronizar_dedup(
        enderecos[[campos_endereco[["numero"]]]],
        "numero"
      ),
      cep = padronizar_dedup(
        enderecos[[campos_endereco[["cep"]]]],
        "cep"
      ),
      localidade = padronizar_dedup(
        enderecos[[campos_endereco[["localidade"]]]],
        "bairro"
      ),
      municipio = padronizar_dedup(
        enderecos[[campos_endereco[["municipio"]]]],
        "municipio"
      ),
      estado = padronizar_dedup(
        enderecos[[campos_endereco[["estado"]]]],
        "estado"
      )
    )
  }

  if (isFALSE(padronizar_enderecos)) {
    input_padrao <- data.table::copy(enderecos)

    # checa se input foi mesmo padronizado -- so faz sentido neste ramo, ja que
    # no ramo TRUE as colunas padronizadas sao construidas aqui mesmo
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
    # remove as colunas extras por referencia em vez de copiar as 6 colunas
    # padronizadas para uma tabela nova (.SD copia)
    input_padrao[, setdiff(names(input_padrao), cols_to_keep) := NULL]
    names(input_padrao) <- c(gsub("_padr", "", names(input_padrao)))

    if ('bairro' %in% names(input_padrao)) {
      data.table::setnames(
        x = input_padrao,
        old = 'bairro',
        new = 'localidade'
      )
    }
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

  # downloading cnefe -- so as tabelas que as etapas ativas do laco de
  # matching abaixo (all_possible_match_types, guarda mais adiante) vao de
  # fato usar, dado quais campos o usuario declarou (campos_nao_declarados,
  # calculado acima). Ver tabelas_necessarias() em R/utils.R
  cnefe_dir <- download_cnefe(
    tabela = tabelas_necessarias(campos_nao_declarados),
    verboso = verboso,
    cache = cache
  )

  # systime padronizacao 66666 ----------------
  # timer$mark("Download cnefe")

  # creating a temporary db and register the input table data
  con <- create_geocodebr_db(n_cores = n_cores)

  # rede de seguranca: garante que a conexao seja fechada mesmo se a funcao
  # falhar no meio do caminho. O dbDisconnect() explicito mais abaixo continua
  # sendo o fechamento normal, e o teste dbIsValid() evita o aviso
  # "Connection already closed" quando a funcao termina sem erro
  on.exit(if (DBI::dbIsValid(con)) duckdb::dbDisconnect(con), add = TRUE)

  # systime padronizacao 66666 ----------------
  # timer$mark("Criacao do duckdb")

  # register standardized input data
  # escreve o data.frame direto, sem converter para arrow antes: a conversao
  # (arrow::as_arrow_table) dominava o custo desta etapa e nao traz beneficio
  # aqui, ja que a tabela precisa ser materializada e mutavel de todo modo
  # (o laco de matching faz DELETE/UPDATE nela). Medicoes em
  # quality_reports/plans/ -- benchmark de 1M, 5 variantes de registro
  duckdb::dbWriteTable(
    con,
    "input_padrao_db",
    input_padrao,
    overwrite = TRUE,
    temporary = TRUE
  )

  # daqui em diante so o numero de linhas e os nomes das colunas sao usados:
  # libera o data.table padronizado (uma copia integral do input) antes do
  # laco de matching, que e a fase mais longa
  n_rows <- nrow(input_padrao)
  cols_input_padrao <- names(input_padrao)
  rm(input_padrao)

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
      log_causa_confusao = arrow::boolean()
      # similaridade_logradouro so e gravada (e lida) com resultado_completo =
      # TRUE; declara-la aqui alocava uma coluna DOUBLE inteira sempre NULL
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
    prog <- create_progress_bar(n_rows)
    message_looking_for_matches()
  }

  matched_rows <- 0

  # start matching
  for (match_type in all_possible_match_types) {
    # get key cols
    key_cols <- get_key_cols(match_type)

    if (verboso) {
      update_progress_bar(matched_rows, match_type)
    }

    # somente busca essa categoria match_type se todas colunas estiverem na base
    # e nenhuma delas for um campo que o usuario nao declarou -- caso
    # contrario, passa para proxima categoria
    if (all(key_cols %in% cols_input_padrao) && !any(key_cols %in% campos_nao_declarados)) {
      # select match function
      match_fun <- reference_match_fun_by_match_type(match_type)

      n_rows_affected <- match_fun(
        con,
        match_type = match_type,
        key_cols = key_cols,
        resultado_completo = resultado_completo,
        pasta_dados = cnefe_dir
      )

      matched_rows <- matched_rows + n_rows_affected

      # libera as tabelas de referencia que as etapas restantes nao usam mais
      restantes <- all_possible_match_types[
        seq_along(all_possible_match_types) > match(match_type, all_possible_match_types)
      ]
      dropa_tabelas_obsoletas(con, restantes, campos_nao_declarados)

      # leave the loop early if we find all addresses before covering all cases
      if (matched_rows == n_rows) break
    }
  }

  if (verboso) {
    finish_progress_bar(matched_rows)
  }

  # nada apos o laco le input_padrao_db nem as tabelas de referencia: so
  # output_db (empates) e input_db (merge). Liberar aqui derruba o pico de
  # memoria do DuckDB nas etapas finais.
  dropa_tabelas_obsoletas(con, character(0), campos_nao_declarados)
  DBI::dbExecute(con, "DROP TABLE IF EXISTS input_padrao_db;")

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
  # registra o data.frame como view (zero copia) em vez de gravar uma tabela:
  # input_db so e lido uma vez, pelo LEFT JOIN de merge_results_to_input(),
  # nunca alterado. dbWriteTable() e exatamente register + CREATE TABLE AS,
  # entao os tipos das colunas sao os mesmos -- sem a copia integral do input
  # dentro do DuckDB nem o tempo de escrita. A view some no dbDisconnect().
  duckdb::duckdb_register(con, "input_db", enderecos)

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

  # com arquivo_saida, as colunas-fantasma sao deixadas de fora ja no SELECT --
  # assim nunca chegam ao parquet e nao precisam ser removidas depois. A ordem
  # das colunas e a mesma dos dois jeitos, porque as fantasmas ficam sempre
  # entre as colunas do usuario e as colunas do resultado
  x_columns <- names(enderecos)

  if (!is.null(arquivo_saida)) {
    x_columns <- setdiff(x_columns, new_colnames)
  }

  output_df <- merge_results_to_input(
    con,
    x = 'input_db',
    y = output_table_to_use,
    key_column = 'tempidgeocodebr',
    select_columns = x_columns,
    resultado_completo = resultado_completo,
    incluir_empate = isFALSE(resolver_empates),
    arquivo_saida = arquivo_saida
  )

  # Disconnect from DuckDB when done
  duckdb::dbDisconnect(con)

  # o resultado ja esta em disco: devolve so o necessario para o processo pai
  # fazer o pos-processamento (ver geocode())
  if (!is.null(arquivo_saida)) {
    return(invisible(list(
      arquivo = arquivo_saida,
      new_colnames = new_colnames
    )))
  }

  # systime merge results 66666 ----------------
  # timer$mark("Merge results")

  data.table::setDT(output_df)

  # nota: 'tempidgeocodebr' nao precisa ser removida aqui -- ela ja fica de fora
  # do SELECT em merge_results_to_input(), embora siga valida no JOIN/ORDER BY

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


  # drop eventual mock columns with empty strings
  if (length(new_colnames) >= 1) {
    output_df[, (new_colnames) := NULL]
  }

  # H3, remocao da classe data.table e conversao para sf -- mesmas etapas que o
  # processo pai aplica no caminho com arquivo_saida (ver R/utils.R)
  pos_processa_output(
    output_df = output_df,
    h3_res = h3_res,
    resultado_sf = resultado_sf
  )
}
