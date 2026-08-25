#' Monta as colunas `*_encontrado` da query de match
#'
#' Monta `logradouro_encontrado` (sempre presente quando `key_cols` inclui
#' `'logradouro'`, independente de `resultado_completo`) e, quando
#' `resultado_completo = TRUE`, as demais colunas de `key_cols` e
#' `cod_setor`. Usada pelas quatro funcoes de match (`match_cases()`,
#' `match_cases_probabilistic()`, `match_weighted_cases()`,
#' `match_weighted_cases_probabilistic()`) para nao repetir a mesma logica
#' de `glue()`/`gsub()` quatro vezes.
#'
#' @param y String. Nome da tabela de referencia do CNEFE (`cnefe_table_name`
#'   em cada `match_*()`), usada para qualificar as colunas nas expressoes
#'   do `SELECT` (ex.: `"municipio_cep.cep"`).
#' @param key_cols Vetor de caracteres com as colunas-chave do `match_type`
#'   corrente (retorno de `get_key_cols()`), ja sem `'numero'`.
#' @param resultado_completo Logico. Se `FALSE`, so `logradouro_encontrado`
#'   (quando `'logradouro'` esta em `key_cols`) e acrescentada; as demais
#'   colunas ficam de fora.
#' @param colunas_encontradas String. Fragmento inicial da lista de nomes de
#'   coluna (para o `INSERT INTO ... (...)`), ao qual esta funcao acrescenta
#'   os seus proprios nomes. Permite ao chamador injetar uma coluna extra
#'   antes de entrar aqui -- ex.: `similaridade_logradouro` em
#'   `match_cases_probabilistic()`, que e condicional a `resultado_completo`
#'   mas nao faz parte de `key_cols`. Por padrao `""`.
#' @param additional_cols String. Fragmento inicial da lista de expressoes do
#'   `SELECT`, equivalente a `colunas_encontradas` mas do lado das
#'   expressoes (ex.: `"y.cep AS cep_encontrado"`). Por padrao `""`.
#' @param agregado Logico. Se `TRUE`, cada coluna (inclusive
#'   `logradouro_encontrado` e `cod_setor`) e embrulhada em
#'   `FIRST(... ordem_first)` em vez do `SELECT` direto -- usado na segunda
#'   parte da query (agregada por `GROUP BY`) de `match_weighted_cases()` e
#'   `match_weighted_cases_probabilistic()`. Por padrao `FALSE`.
#' @param ordem_first String com a clausula `ORDER BY` usada dentro de cada
#'   `FIRST(...)` quando `agregado = TRUE` (ver `ordem_first` definido em
#'   `match_weighted_cases()`/`match_weighted_cases_probabilistic()`).
#'   Obrigatorio se `agregado = TRUE`; ignorado caso contrario. Por padrao
#'   `NULL`.
#'
#' @return Uma lista com tres elementos:
#' - `colunas_encontradas`: string com a lista de nomes de coluna completa,
#'   pronta para o `INSERT INTO output_db (...)`.
#' - `additional_cols`: string com a lista de expressoes completa, pronta
#'   para o `SELECT` da query de match.
#' - `tem_logradouro`: logico, se `'logradouro'` estava em `key_cols`.
#'
#' @keywords internal
monta_colunas_encontradas <- function(
  y,
  key_cols,
  resultado_completo,
  colunas_encontradas = "",
  additional_cols = "",
  agregado = FALSE,
  ordem_first = NULL
) {
  tem_logradouro <- 'logradouro' %in% key_cols

  if (tem_logradouro) {
    select_lograd <- if (agregado) {
      glue::glue("FIRST(logradouro_encontrado {ordem_first}) AS logradouro_encontrado")
    } else {
      glue::glue("{y}.logradouro AS logradouro_encontrado")
    }
    colunas_encontradas <- paste0(colunas_encontradas, ", logradouro_encontrado")
    additional_cols <- paste0(additional_cols, ", ", select_lograd)
  }

  if (!isTRUE(resultado_completo)) {
    return(list(
      colunas_encontradas = colunas_encontradas,
      additional_cols = additional_cols,
      tem_logradouro = tem_logradouro
    ))
  }

  demais_key_cols <- setdiff(key_cols, 'logradouro')

  if (length(demais_key_cols) > 0) {
    nomes <- paste0(glue::glue("{demais_key_cols}_encontrado"), collapse = ', ')
    nomes <- gsub('localidade_encontrado', 'localidade_encontrada', nomes)

    select <- if (agregado) {
      paste0(
        glue::glue("FIRST({demais_key_cols}_encontrado {ordem_first}) AS {demais_key_cols}_encontrado"),
        collapse = ', '
      )
    } else {
      paste0(
        glue::glue("{y}.{demais_key_cols} AS {demais_key_cols}_encontrado"),
        collapse = ', '
      )
    }
    select <- gsub('localidade_encontrado', 'localidade_encontrada', select)

    colunas_encontradas <- paste0(colunas_encontradas, ", ", nomes)
    additional_cols <- paste0(additional_cols, ", ", select)
  }

  # adiciona codigo do setor censitario
  cod_setor_select <- if (agregado) {
    glue::glue(", FIRST(cod_setor {ordem_first}) AS cod_setor")
  } else {
    glue::glue(", {y}.cod_setor AS cod_setor")
  }
  additional_cols <- paste0(additional_cols, cod_setor_select)
  colunas_encontradas <- paste0(colunas_encontradas, ", cod_setor")

  list(
    colunas_encontradas = colunas_encontradas,
    additional_cols = additional_cols,
    tem_logradouro = tem_logradouro
  )
}
