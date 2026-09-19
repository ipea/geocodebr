#' Safely use arrow to open a Parquet file
#'
#' This function handles some failure modes, including if the Parquet file is
#' corrupted.
#'
#' @param filename A local Parquet file
#' @return An `arrow::Dataset`
#'
#' @keywords internal
arrow_open_dataset <- function(filename) {
  # nocov start

  tryCatch(
    arrow::open_dataset(filename, format = 'parquet'),
    error = function(e) {
      msg <- paste(
        "Arquivo local possivelmente corrompido. ",
        "Apague os arquivos do cache com 'geocodebr::deletar_pasta_cache()' e tente novamente.",
        sep = "\n"
      )
      stop(msg)
    }
  )
} # nocov end

#' Message when caching file
#'
#' @param local_file The address of a file passed from the download_file function.
#' @param cache Logical. Whether the cached data should be used.

#' @return A message
#'
#' @keywords internal
cache_message <- function(local_file, cache) {
  # nocov start

  # name of local file
  file_name <- basename(local_file[1])
  dir_name <- dirname(local_file[1])

  ## if file already exists
  # YES cache
  if (file.exists(local_file) & isTRUE(cache)) {
    message('Reading data cached locally.')
  }

  # NO cache
  if (file.exists(local_file) & isFALSE(cache)) {
    message('Overwriting data cached locally.')
  }

  ## if file does not exist yet
  # YES cache
  if (!file.exists(local_file) & isTRUE(cache)) {
    message(paste("Downloading data and storing it locally for future use."))
  }

  # NO cache
  if (!file.exists(local_file) & isFALSE(cache)) {
    message(paste(
      "Downloading data. Setting 'cache = TRUE' is strongly recommended to speed up future use. File will be stored locally at:",
      dir_name
    ))
  }
} # nocov end


#' Update input_padrao_db to remove observations previously matched
#'
#' @param con A db connection
#' @param update_tb String. Name of a table to be updated in con
#' @param reference_tb A table written in con used as reference
#' @param match_type String. Se informado, apaga apenas os ids inseridos em
#'   `reference_tb` com esse `tipo_resultado` (os da etapa corrente)
#'
#' @return Drops observations from input_padrao_db
#'
#' @keywords internal
update_input_db <- function(
  con,
  update_tb = 'input_padrao_db',
  reference_tb,
  match_type = NULL
) {
  # nocov start

  # update_tb = 'input_padrao_db'
  # reference_tb = 'output_caso_1'

  # so os ids inseridos NESTA etapa precisam sair de input_padrao_db: pelo
  # invariante do laco (input e output nunca compartilham id apos o DELETE de
  # cada etapa), os ids das etapas anteriores ja nao estao na tabela. Filtrar
  # por tipo_resultado evita varrer a output_db inteira -- que cresce a cada
  # etapa -- 25 vezes. A contagem de linhas apagadas e a mesma.
  filtro_etapa <- if (is.null(match_type)) {
    ""
  } else {
    glue::glue("WHERE tipo_resultado = '{match_type}'")
  }

  query_remove_matched <- glue::glue(
    "DELETE FROM {update_tb}
     WHERE tempidgeocodebr IN (
      SELECT tempidgeocodebr
      FROM {reference_tb}
      {filtro_etapa}
    );"
  )

  DBI::dbExecute(con, query_remove_matched)
} # nocov end


#' Add a column with info of geocode match_type
#'
#' @param con A db connection
#' @param update_tb String. Name of a table to be updated in con
#'
#' @return Adds a new column to a table in con
#'
#' @keywords internal
add_precision_col <- function(con, update_tb = NULL) {
  # nocov start

  # update_tb = "output_db"

  # add empty column
  query_add_col <- glue::glue(
    "ALTER TABLE {update_tb} ADD COLUMN precisao TEXT;"
  )
  DBI::dbExecute(con, query_add_col)

  # populate column
  query_precision_cats <- glue::glue(
    "
  UPDATE {update_tb}
  SET precisao = CASE
  WHEN tipo_resultado IN ('dn01', 'dn02', 'dn03', 'dn04',
                          'pn01', 'pn02', 'pn03', 'pn04') THEN 'numero'
  WHEN tipo_resultado IN ('da01', 'da02', 'da03', 'da04',
                          'pa01', 'pa02', 'pa03', 'pa04') THEN 'numero_aproximado'
  WHEN tipo_resultado IN ('dl01', 'dl02', 'dl03', 'dl04',
                          'pl01', 'pl02', 'pl03', 'pl04') THEN 'logradouro'
  WHEN tipo_resultado IN ('dc01', 'dc02') THEN 'cep'
  WHEN tipo_resultado = 'db01' THEN 'localidade'
  WHEN tipo_resultado = 'dm01' THEN 'municipio'
  ELSE NULL
  END;"
  )

  # DBI::dbExecute(con, query_precision_cats )
  DBI::dbExecute(con, query_precision_cats)
} # nocov end


merge_results_to_input <- function(
  con,
  x,
  y,
  key_column,
  select_columns,
  resultado_completo,
  incluir_empate = FALSE,
  arquivo_saida = NULL
) {
  # nocov start

  select_columns_y <- c(
    'lat',
    'lon',
    'precisao',
    'tipo_resultado',
    'desvio_metros',
    'endereco_encontrado'
  )

  # com resolver_empates = FALSE os casos empatados voltam em duplicidade
  # (uma linha por candidato), entao a coluna 'empate' precisa acompanhar o
  # output mesmo sem resultado_completo, para o usuario identificar essas
  # linhas. Com resultado_completo = TRUE ela ja entra na lista abaixo.
  if (isTRUE(incluir_empate) && isFALSE(resultado_completo)) {
    select_columns_y <- c(select_columns_y, 'empate')
  }

  if (isTRUE(resultado_completo)) {
    # select additional columns to output
    select_columns_y <- c(
      select_columns_y,
      'logradouro_encontrado',
      'numero_encontrado',
      'cep_encontrado',
      'localidade_encontrada',
      'municipio_encontrado',
      'estado_encontrado',
      'similaridade_logradouro',
      'contagem_cnefe',
      'empate',
      'cod_setor'
    )

    # relace NULL similaridade_logradouro as 1 because they were found deterministically
    DBI::dbExecute(
      con,
      glue::glue(
        "UPDATE {y}
      SET similaridade_logradouro = COALESCE(similaridade_logradouro, 1);"
      )
    )
  }

  # Create the SELECT clause dynamically
  # a chave temporaria e interna ao pacote e nao faz parte do output: fica de
  # fora do SELECT (mas segue valida no JOIN e no ORDER BY abaixo), evitando
  # materializar uma coluna inteira que seria descartada em seguida
  cols_x <- setdiff(select_columns, key_column)
  expr_x <- paste0(x, '.', cols_x)

  # No caminho via parquet, colunas INTERVAL precisam de tratamento: o DuckDB
  # grava difftime como INTERVAL, e INTERVAL vira um FIXED_SIZE_BINARY de 12
  # bytes no parquet -- que o arrow le como blob, nao como difftime. epoch()
  # devolve o total em segundos, que e exatamente o que o dbGetQuery entregava
  # (difftime com units = "secs"). A classe e reposta em restaura_classes_input()
  if (!is.null(arquivo_saida)) {
    tipos_x <- DBI::dbGetQuery(con, glue::glue("DESCRIBE {x}"))
    eh_interval <- cols_x %in% tipos_x$column_name[
      tipos_x$column_type == "INTERVAL"
    ]

    if (any(eh_interval)) {
      expr_x[eh_interval] <- glue::glue(
        "epoch({expr_x[eh_interval]}) AS {cols_x[eh_interval]}"
      )
    }
  }

  select_x <- paste0(expr_x, collapse = ', ')

  select_clause <- paste0(
    select_x,
    ',',
    paste0(glue::glue('{y}'), ".", select_columns_y, collapse = ", ")
  )

  # Create the JOIN clause dynamically
  join_condition <- paste(
    glue::glue("{x}.{key_column} = {y}.{key_column}"),
    collapse = ' ON '
  )

  # Create SQL query (sem ';' -- ele e adicionado abaixo, e a variante COPY
  # precisa da query como subconsulta)
  query <- glue::glue(
    "SELECT {select_clause}
        FROM {x}
        LEFT JOIN {y}
        ON {join_condition}
      ORDER BY
        {x}.tempidgeocodebr"
  )

  # Com arquivo_saida, o resultado sai do DuckDB direto para parquet em disco,
  # sem materializar no R. Quem chama (o processo filho de geocode()) devolve
  # apenas o caminho, e o processo pai le com arrow::read_parquet(). Isso evita
  # o dbGetQuery + o serialize/unserialize do callr sobre o resultado inteiro.
  # A ordem das linhas e preservada pelo preserve_insertion_order do DuckDB
  # (ver create_geocodebr_db())
  if (!is.null(arquivo_saida)) {
    # o caminho entra literal na string SQL: dobra eventual apostrofo
    caminho_sql <- gsub("'", "''", arquivo_saida, fixed = TRUE)

    DBI::dbExecute(
      con,
      glue::glue("COPY ({query}) TO '{caminho_sql}' (FORMAT PARQUET);")
    )

    return(invisible(arquivo_saida))
  }

  # Execute the query and fetch the merged data
  merged_data <- DBI::dbGetQuery(con, paste0(query, ";"))

  return(merged_data)
} # nocov end


# Pos-processamento do output do geocode(): etapas finais comuns aos dois
# caminhos de transporte do resultado (data.frame devolvido pelo callr, ou
# parquet lido pelo processo pai) -- colunas H3, remocao da classe data.table e
# conversao para sf. Mantido como funcao unica de proposito: sao justamente as
# etapas em que os dois caminhos precisam produzir o mesmo objeto
pos_processa_output <- function(output_df, h3_res, resultado_sf) {
  # nocov start

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

    return(output_sf)
  }

  return(output_df[])
} # nocov end


# Restaura as classes das colunas de input perdidas no trajeto via parquet.
# O `enderecos` original (que o processo pai ainda tem intacto em memoria) serve
# de gabarito para saber QUAIS colunas tratar; o valor restaurado, porem, e o que
# o caminho antigo (dbWriteTable -> dbGetQuery) produzia, nao necessariamente o
# do input -- o objetivo aqui e nao mudar o output de geocode():
#
#   factor   o DuckDB mapeia factor para ENUM e de volta para factor, sempre NAO
#            ordenado (um factor ordenado de input ja perdia o `ordered` no
#            caminho antigo). Via parquet volta como character
#   POSIXct  o DuckDB guarda TIMESTAMP sem fuso e o driver rotula o resultado
#            como "UTC", qualquer que fosse o tzone do input. Via parquet o
#            tzone volta vazio, com o mesmo valor numerico -- so falta o rotulo
#   difftime chega aqui como o total em segundos (epoch(), ver
#            merge_results_to_input()), que e o que o caminho antigo devolvia
#
# Demais tipos (character, integer, double, logical, Date, integer64) atravessam
# o parquet sem alteracao e nao sao tocados aqui
restaura_classes_input <- function(output_df, enderecos) {
  # nocov start

  cols_comuns <- intersect(names(enderecos), names(output_df))

  for (cn in cols_comuns) {
    orig <- enderecos[[cn]]

    if (is.factor(orig)) {
      output_df[[cn]] <- factor(
        as.character(output_df[[cn]]),
        levels = levels(orig)
      )
    } else if (inherits(orig, "difftime")) {
      output_df[[cn]] <- as.difftime(
        as.numeric(output_df[[cn]]),
        units = "secs"
      )
    } else if (inherits(orig, "POSIXct")) {
      attr(output_df[[cn]], "tzone") <- "UTC"
    }
  }

  return(output_df)
} # nocov end

#create_index <- function(con, tb, cols, operation, overwrite = TRUE) {
#  # nocov start
#
#  idx <- paste0('idx_', tb)
#  cols_group <- paste(cols, collapse = ", ")
#
#  # check if table already has index
#  i <- DBI::dbGetQuery(
#    con,
#    sprintf("SELECT * FROM duckdb_indexes WHERE table_name = '%s';", tb)
#  )
#
#  if (nrow(i) > 0 & isFALSE(overwrite)) {
#    return(NULL)
#  }
#  if (nrow(i) > 0 & isTRUE(overwrite)) {
#    DBI::dbExecute(con, sprintf('DROP INDEX IF EXISTS %s', idx))
#  }
#
#  query_index <- sprintf(
#    '%s INDEX %s ON %s(%s);',
#    operation,
#    idx,
#    tb,
#    cols_group
#  )
#  DBI::dbExecute(con, query_index)
#} # nocov end


get_key_cols <- function(match_type) {
  # nocov start
  relevant_cols <- if (match_type %in% c('dn01', 'da01', 'pn01', 'pa01')) {
    c("estado", "municipio", "logradouro", "numero", "cep", "localidade")
  } else if (match_type %in% c('dn02', 'da02', 'pn02', 'pa02')) {
    c("estado", "municipio", "logradouro", "numero", "cep")
  } else if (match_type %in% c('dn03', 'da03', 'pn03', 'pa03')) {
    c("estado", "municipio", "logradouro", "numero", "localidade")
  } else if (match_type %in% c('dn04', 'da04', 'pn04', 'pa04')) {
    c("estado", "municipio", "logradouro", "numero")
  } else if (match_type %in% c('dl01', 'pl01')) {
    c("estado", "municipio", "logradouro", "cep", "localidade")
  } else if (match_type %in% c('dl02', 'pl02')) {
    c("estado", "municipio", "logradouro", "cep")
  } else if (match_type %in% c('dl03', 'pl03')) {
    c("estado", "municipio", "logradouro", "localidade")
  } else if (match_type %in% c('dl04', 'pl04')) {
    c("estado", "municipio", "logradouro")
  } else if (match_type == 'dc01') {
    c("estado", "municipio", "cep", "localidade")
  } else if (match_type == 'dc02') {
    c("estado", "municipio", "cep")
  } else if (match_type == 'db01') {
    c("estado", "municipio", "localidade")
  } else if (match_type == 'dm01') {
    c("estado", "municipio")
  }

  return(relevant_cols)
} # nocov end

### ideal sequence of match types
all_possible_match_types <- c(
  "dn01",
  "da01",
  "pn01",
  "pa01",
  "dn02",
  "da02",
  "pn02",
  "pa02",
  "dn03",
  "da03",
  "pn03",
  "pa03",
  "dn04",
  "da04", #"pn04", "pa04", # too costly
  "dl01",
  "pl01",
  "dl02",
  "pl02",
  "dl03",
  "pl03",
  "dl04", # pl04",  # too costly
  "dc01",
  "dc02",
  "db01",
  "dm01"
)

# ### 2nd best viable sequence of match types for really large datasets ? testando com cadunico
# all_possible_match_types <- c(
#   "dn01", "da01",
#   "dn02", "da02",
#   "dn03", "da03",
#   "dn04", "da04",
#   "pn01", "pa01", "pn02", "pa02", "pn03", "pa03", #"pn04", "pa04", # too costly
#   "dl01",         "pl01",
#   "dl02",         "pl02",
#   "dl03",         "pl03",
#   "dl04",         # pl04",  # too costly
#   "dc01", "dc02", "db01", "dm01"
# )

number_exact_types <- c(
  "dn01",
  "dn02",
  "dn03",
  "dn04"
)

number_interpolation_types <- c(
  "da01",
  "da02",
  "da03",
  "da04"
)

probabilistic_exact_types <- c(
  "pn01",
  "pn02",
  "pn03",
  "pn04"
)

probabilistic_interpolation_types <- c(
  "pa01",
  "pa02",
  "pa03",
  "pa04"
)

# pa01/pa02/pa03 tem exatamente o mesmo key_cols (get_key_cols()), a mesma
# tabela de referencia (get_reference_table()) e o mesmo corte de similaridade
# (get_prob_match_cutoff()) que pn01/pn02/pn03, a etapa imediatamente anterior
# em all_possible_match_types. calculate_string_dist() so calcula Jaro para
# linhas com similaridade_logradouro IS NULL -- ou seja, as linhas que sobram
# para pa0k sao exatamente as que pn0k ja testou contra o mesmo candidato com o
# mesmo corte e nao passou. Recalcular em pa0k e um no-op garantido (medido:
# 0 matches em pa01/pa02/pa03 em 20.028 enderecos -- ver
# quality_reports/diagnoses/2026-08-23_geocode-diagnostico-performance.md §6).
# NAO inclui "pa04": pn04 esta desativado (# too costly, ver acima), entao nao
# ha etapa anterior que preencha similaridade_logradouro para pa04 reaproveitar.
# Se pn04/pa04 forem reativados juntos, pa04 pode entrar aqui; separados, nao.
match_types_jaro_redundante <- c("pa01", "pa02", "pa03")

exact_types_no_number <- c(
  "dl01",
  "dl02",
  "dl03",
  "dl04",
  "dc01",
  "dc02",
  "db01",
  "dm01"
)

probabilistic_types_no_number <- c(
  "pl01",
  "pl02",
  "pl03",
  "pl04"
)

exact_types_no_logradouro <- c(
  "dc01",
  "dc02",
  "db01",
  "dm01"
)

# Padroniza UM campo do endereco rodando `enderecobr::padronizar_enderecos()`
# apenas sobre os valores distintos de `x`, e expande o resultado de volta para o
# comprimento original via `chmatch()`.
#
# Duas economias em relacao a chamar `padronizar_enderecos()` uma vez sobre a
# tabela inteira: o trabalho por campo passa a ser proporcional a cardinalidade
# distinta da coluna (nas colunas de endereco, uma fracao pequena do total), e
# nao se paga a copia integral do input que `padronizar_enderecos()` faz via
# `as.data.table()`. As seis funcoes `padronizar_*` do enderecobr sao
# element-wise puras (checkmate + um `.Call` em Rust), logo o resultado e
# `identical()` ao da chamada sobre o vetor inteiro -- inclusive no tratamento de
# NA, nos ramos numericos de `padronizar_numeros()` / `padronizar_ceps()` e em
# input marcado como latin1.
#
# Por que chamar `padronizar_enderecos()` (e nao `padronizar_logradouros()` etc.
# direto): os construtores de mensagem do enderecobr inspecionam a pilha de
# chamadas por deslocamento fixo (`sys.call(-15)` em `warning_conversao_invalida()`,
# `sys.call(-10)` nos `erro_cep_*`). Chamar as funcoes de campo diretamente muda a
# profundidade da pilha e faz esses construtores falharem com
# "cannot coerce type 'closure'" -- o que transforma um aviso benigno
# (numero nao convertivel para integer) em erro fatal. Mantendo
# `padronizar_enderecos()` na pilha, avisos e erros saem exatamente como hoje.
padronizar_dedup <- function(x, campo, formato_estados = "sigla",
                             formato_numeros = "integer") {
  ux <- unique(x)
  idx <- if (is.character(x)) data.table::chmatch(x, ux) else match(x, ux)

  campos <- list()
  campos[[campo]] <- "v"
  campos <- do.call(enderecobr::correspondencia_campos, campos)
  col_padr <- paste0(campo, "_padr")

  padroniza <- function(v) {
    enderecobr::padronizar_enderecos(
      enderecos = data.table::data.table(v = v),
      campos_do_endereco = campos,
      formato_estados = formato_estados,
      formato_numeros = formato_numeros
    )[[col_padr]]
  }

  # se a padronizacao falhar (ex.: CEP com letra), reexecuta no vetor inteiro
  # para que a mensagem de erro cite os indices originais, como hoje
  y <- tryCatch(padroniza(ux), error = function(e) padroniza(x))

  y[idx]
}




assert_and_assign_address_fields <- function(address_fields, addresses_table) {
  # nocov start
  possible_fields <- c(
    "logradouro",
    "numero",
    "cep",
    "localidade",
    "municipio",
    "estado"
  )

  col <- checkmate::makeAssertCollection()
  checkmate::assert_names(
    names(address_fields),
    type = "unique",
    subset.of = possible_fields,
    add = col
  )
  checkmate::assert_names(
    address_fields,
    subset.of = names(addresses_table),
    add = col
  )
  checkmate::reportAssertions(col)

  missing_fields <- setdiff(possible_fields, names(address_fields))

  missing_fields_list <- vector(mode = "list", length = length(missing_fields))
  names(missing_fields_list) <- missing_fields

  complete_fields_list <- append(as.list(address_fields), missing_fields_list)

  return(complete_fields_list)
} # nocov end


# Tabela de referencia do CNEFE lida por cada match_type.
#
# O mapeamento NAO e derivavel das key_cols da etapa: varias etapas leem uma
# tabela mais detalhada do que a sua chave exige. Por exemplo, `dn04` tem chave
# municipio + logradouro + numero, mas le a tabela ..._numero_localidade, porque
# so um subconjunto das combinacoes e distribuido (ver `all_files` em
# `download_cnefe()`). Manter isso como um mapa explicito evita ter de reconstruir
# essa excecao mentalmente a cada leitura.
#
# Cobre os 28 match_types que `get_key_cols()` conhece, inclusive `pn04`, `pa04`
# e `pl04`, que hoje estao fora de `all_possible_match_types` por serem caros.
reference_table_by_match_type <- c(
  dn01 = "municipio_logradouro_numero_cep_localidade",
  dn02 = "municipio_logradouro_numero_cep_localidade",
  dn03 = "municipio_logradouro_numero_cep_localidade",
  dn04 = "municipio_logradouro_numero_localidade",

  da01 = "municipio_logradouro_numero_cep_localidade",
  da02 = "municipio_logradouro_numero_cep_localidade",
  da03 = "municipio_logradouro_numero_localidade",
  da04 = "municipio_logradouro_numero_localidade",

  pn01 = "municipio_logradouro_numero_cep_localidade",
  pn02 = "municipio_logradouro_numero_cep_localidade",
  pn03 = "municipio_logradouro_numero_cep_localidade",
  pn04 = "municipio_logradouro_numero",

  pa01 = "municipio_logradouro_numero_cep_localidade",
  pa02 = "municipio_logradouro_numero_cep_localidade",
  pa03 = "municipio_logradouro_numero_localidade",
  pa04 = "municipio_logradouro_numero",

  dl01 = "municipio_logradouro_cep_localidade",
  dl02 = "municipio_logradouro_cep_localidade",
  dl03 = "municipio_logradouro_cep_localidade",
  dl04 = "municipio_logradouro_localidade",

  pl01 = "municipio_logradouro_cep_localidade",
  pl02 = "municipio_logradouro_cep_localidade",
  pl03 = "municipio_logradouro_cep_localidade",
  pl04 = "municipio_logradouro",

  dc01 = "municipio_cep_localidade",
  dc02 = "municipio_cep",
  db01 = "municipio_localidade",
  dm01 = "municipio"
)


get_reference_table <- function(match_type) {
  # nocov start

  table_name <- reference_table_by_match_type[match_type]

  if (anyNA(table_name)) {
    desconhecidos <- match_type[is.na(table_name)]
    cli::cli_abort(
      "Nao ha tabela de refer\u00eancia definida para o match_type {.val {desconhecidos}}."
    )
  }

  return(unname(table_name))
} # nocov end


# Subconjunto de tabelas de referencia do CNEFE que o laco de matching de
# efetivamente vai usar, dado quais campos de endereco o usuario NAO declarou
# (`campos_nao_declarados`)
#
# os match_types probabilisticos (pn0X/pa0X/pl0X) usam uma tabela diferente da
# que reference_table_by_match_type por design, nao por acidente: a distancia de
# Jaro so deve comparar o texto do logradouro, nunca o numero, entao a tabela de
# candidatos do calculo de string sempre corresponde ao match_type "irmao" sem
# numero (dl0X/dc0X). Por isso essa tabela nunca fica de fora do conjunto
# devolvido aqui
tabelas_necessarias <- function(campos_nao_declarados) {
  # nocov start
  match_types_ativos <- Filter(
    function(mt) !any(get_key_cols(mt) %in% campos_nao_declarados),
    all_possible_match_types
  )

  unique(unname(reference_table_by_match_type[match_types_ativos]))
} # nocov end


# Funcao de match utilizada por cada match_type.
#
# Cada match_type pertence a exatamente um dos grupos definidos acima
# (number_exact_types / exact_types_no_number, number_interpolation_types,
# probabilistic_exact_types / probabilistic_types_no_number,
# probabilistic_interpolation_types).
reference_match_fun_by_match_type <- function(match_type) {
  # nocov start
  if (match_type %in% c(number_exact_types, exact_types_no_number)) {
    return(match_cases)
  }

  if (match_type %in% number_interpolation_types) {
    return(match_weighted_cases)
  }

  if (
    match_type %in% c(probabilistic_exact_types, probabilistic_types_no_number)
  ) {
    return(match_cases_probabilistic)
  }

  if (match_type %in% probabilistic_interpolation_types) {
    return(match_weighted_cases_probabilistic)
  }

  cli::cli_abort(
    "Nao ha fun\u00e7\u00e3o de match definida para o match_type {.val {match_type}}."
  )
} # nocov end


# min cutoff for string match
# min cutoff for probabilistic string match of logradouros
get_prob_match_cutoff <- function(match_type) {
  # nocov start
  min_cutoff <- ifelse(match_type %in% c('pn01', 'pa01', 'pl01'), 0.85, 0.9)
  return(min_cutoff)
} # nocov end


# create a dummy function that uses nanoarrow with no effect
# nanoarrow is only used internally in DBI::dbWriteTableArrow()
# however, if we do not put this dummy function here, CRAN check flags an error
dummy <- function() {
  # nocov start
  nanoarrow::as_nanoarrow_schema
} # nocov end


# Cria coluna dummy no input padronizado identificando se logradouro é daqueles
# que gera confusao (e.g. uma letra (e.g. RUA A, RUA B, RUA C, ....) ou compostos
# só por dígitos (RUA 1, RUA 10, RUA 20, ...))
cria_col_logradouro_confusao <- function(con) {
  # nocov start

  # Add the column with default 0 (avoids updating all rows later)
  DBI::dbExecute(
    con,
    "ALTER TABLE input_padrao_db
      ADD COLUMN log_causa_confusao BOOLEAN DEFAULT false;"
  )

  # Ambiguos numero por extenso
  ruas_num_ext <- paste(
    paste(
      "RUA",
      c(
        'UM',
        'DOIS',
        'TRES',
        'QUATRO',
        'CINCO',
        'SEIS',
        'SETE',
        'OITO',
        'NOVE',
        'DEZ',
        'ONZE',
        'DOZE',
        'TREZE'
      )
    ),
    collapse = "|"
  )
  ruas_num_ext <- paste0("(", ruas_num_ext, ")$")

  # 2) Flip to 1 for rows matching our regex
  DBI::dbExecute(
    con,
    glue::glue(
      r"{UPDATE input_padrao_db
    SET log_causa_confusao = true
    WHERE
      (REGEXP_MATCHES(logradouro, '^(RUA|TRAVESSA|RAMAL|BECO|BLOCO|AVENIDA|RODOVIA|ESTRADA)\s+([A-Z]{{1,2}}-?|[0-9]{{1,3}}|[A-Z]{{1,2}}-?[0-9]{{1,3}}|[A-Z]{{1,2}}\s+[0-9]{{1,3}}|[0-9]{{1,3}}-?[A-Z]{{1,2}})(\s+KM( \d+)?)?$')
       OR REGEXP_MATCHES(logradouro, '{ruas_num_ext}')
       )
        -- ainda dah pra salvar enderecos com datas (e.g. 'RUA 15 DE NOVEMBRO')
        AND NOT REGEXP_MATCHES(logradouro, '\bDE (JANEIRO|FEVEREIRO|MARCO|ABRIL|MAIO|JUNHO|JULHO|AGOSTO|SETEMBRO|OUTUBRO|NOVEMBRO|DEZEMBRO)\b');}"
    )
  )
} # nocov end



check_clean_colnames <- function(df) {  # nocov start

  # # basic input check
  # if (!is.data.frame(df)) {
  #   cli::cli_abort("{.arg df} must be a data.frame.")
  # }

  cols <- colnames(df)

  # allow only letters, numbers, and underscore
  bad_cols <- cols[!grepl("^[A-Za-z0-9_]+$", cols)]

  if (length(bad_cols) > 0) {
    cli::cli_abort(c(
      "Invalid column names detected.",
      "x" = "Column names must use only letters, numbers, and underscores ({.val _}).",
      "i" = "Please rename these columns: {.val {bad_cols}}"
    ),
    "call" = rlang::caller_env()
    )
  }

  # nomes reservados: colunas que o proprio geocode() cria no output ou usa
  # como chave interna. Se ja existirem no input, o merge final produziria
  # colunas duplicadas/ambiguas (e.g. duas colunas 'lat') e o pos-processamento
  # (H3, sf) leria a coluna errada em silencio -- melhor abortar cedo.
  reserved <- c(
    'tempidgeocodebr', 'lat', 'lon', 'precisao', 'tipo_resultado',
    'desvio_metros', 'endereco_encontrado', 'logradouro_encontrado',
    'numero_encontrado', 'cep_encontrado', 'localidade_encontrada',
    'municipio_encontrado', 'estado_encontrado', 'similaridade_logradouro',
    'contagem_cnefe', 'empate', 'cod_setor'
  )
  reserved_cols <- cols[cols %in% reserved]

  if (length(reserved_cols) > 0) {
    cli::cli_abort(c(
      "Reserved column names detected.",
      "x" = "These column names are created by {.fn geocode} in the output and cannot be present in the input.",
      "i" = "Please rename these columns: {.val {reserved_cols}}"
    ),
    "call" = rlang::caller_env()
    )
  }

} # nocov end


# Tabelas temporarias (de referencia do CNEFE e de logradouros unicos) que as
# etapas restantes do laco de matching ainda vao usar. Espelha o criterio de
# tabelas_necessarias() para as etapas que faltam, mais as duas tabelas
# unique_logr_* de register_unique_logradouros_table() (a base delas depende
# so de o match_type ser *03 ou nao).
tabelas_ainda_necessarias <- function(match_types_restantes, campos_nao_declarados) {
  # nocov start
  ativos <- Filter(
    function(mt) !any(get_key_cols(mt) %in% campos_nao_declarados),
    match_types_restantes
  )

  tabs <- unique(unname(reference_table_by_match_type[ativos]))

  probabilisticos <- ativos[ativos %in% c(
    probabilistic_exact_types,
    probabilistic_interpolation_types,
    probabilistic_types_no_number
  )]

  if (any(probabilisticos %in% c("pn03", "pa03", "pl03"))) {
    tabs <- c(tabs, "unique_logr_municipio_logradouro_localidade")
  }
  if (any(!probabilisticos %in% c("pn03", "pa03", "pl03"))) {
    tabs <- c(tabs, "unique_logr_municipio_logradouro_cep_localidade")
  }

  unique(tabs)
} # nocov end


# Apaga do banco as tabelas temporarias que nenhuma etapa restante do laco vai
# usar. O DuckDB libera a memoria de uma TEMP TABLE no DROP; sem isso as duas
# tabelas de referencia maiores (~10 GB cada em escala nacional) ficariam vivas
# ate o fim de geocode(), embora so sejam lidas nas primeiras etapas.
dropa_tabelas_obsoletas <- function(con, match_types_restantes, campos_nao_declarados) {
  # nocov start
  candidatas <- c(
    unique(unname(reference_table_by_match_type)),
    "unique_logr_municipio_logradouro_localidade",
    "unique_logr_municipio_logradouro_cep_localidade"
  )

  necessarias <- tabelas_ainda_necessarias(match_types_restantes, campos_nao_declarados)
  existentes <- DBI::dbListTables(con)

  for (tb in setdiff(intersect(candidatas, existentes), necessarias)) {
    DBI::dbExecute(con, glue::glue("DROP TABLE IF EXISTS {tb};"))
  }

  invisible(NULL)
} # nocov end
