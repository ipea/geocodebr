#' Especifica as colunas que descrevem os campos dos endereços
#'
#' Cria um vetor de caracteres especificando as colunas que representam cada
#' campo do endereço na tabela de endereços. Os campos `estado` e `municipio`
#' são obrigatórios.

#' @param estado Uma string. O nome da coluna que representa o estado do
#'   endereço. Campo obrigatório. Na tabela de endereços, essa coluna pode
#'   conter os nomes dos estados por extenso, ou a abrevição oficial dos estados
#'   com duas letras, e.g. "AM", "SP", "DF", "RJ".
#' @param municipio Uma string. O nome da coluna que representa o município do
#'   endereço. Campo obrigatório. Na tabela de endereços, essa coluna pode
#'   conter o nome dos municípios, ou o seu código IBGE de 7 dígitos.
#' @param logradouro Uma string. O nome da coluna que representa o *logradouro*
#'   (endereço da rua) do endereço. Pode ser `NULL` se o campo não estiver
#'   especificado na tabela de endereços. Na tabela de endereços, essa coluna
#'   deve incluir o *tipo* e o *nome* do lograoduro, indicando se trata-se de
#'   uma "Rua" ou "Avenida" etc, por exemplo "Avenida Presidente Getúlio Vargas".
#'   Além disso, essa coluna *não* deve incluir o `numero` do endereço, pois o
#'   número deve ser indicado numa coluna separada.
#' @param numero Uma string. O nome da coluna que representa o número do endereço.
#'    Pode ser `NULL` se o campo não estiver especificado na tabela de endereços.
#'    Na tabela de endereços, valores como `0` ou caracteres não numerciso como
#'    `"S/N"` ou `"10a"` são considerados como `NA`.
#' @param cep Uma string. O nome da coluna que representa o *CEP* (Código de
#'    Endereçamento Postal) do endereço. Pode ser `NULL` se o campo não estiver
#'    especificado na tabela de endereços.
#' @param localidade Uma string. O nome da coluna que representa a localidade
#'   (equivalente ao 'bairro' em áreas urbanas) do endereço. Pode ser `NULL` se
#'   esse campo não estiver presente na tabela de endereços.
#'
#' @return Um vetor de caracteres no qual os nomes são os campos do endereço e os
#'   valores são as colunas que os representam na tabela de endereços.
#'
#' @examples
#' definir_campos(
#'   logradouro = "Nome_logradouro",
#'   numero = "Numero",
#'   cep = "CEP",
#'   localidade = "Bairro",
#'   municipio = "Cidade",
#'   estado = "UF"
#' )
#'
#' @export
definir_campos <- function(
  estado,
  municipio,
  logradouro = NULL,
  numero = NULL,
  cep = NULL,
  localidade = NULL
) {
  col <- checkmate::makeAssertCollection()
  checkmate::assert_string(logradouro, null.ok = TRUE, add = col)
  checkmate::assert_string(numero, null.ok = TRUE, add = col)
  checkmate::assert_string(cep, null.ok = TRUE, add = col)
  checkmate::assert_string(localidade, null.ok = TRUE, add = col)
  checkmate::assert_string(municipio, null.ok = TRUE, add = col)
  checkmate::assert_string(estado, null.ok = TRUE, add = col)
  checkmate::reportAssertions(col)

  address_fields <- c(
    logradouro = logradouro,
    numero = numero,
    cep = cep,
    localidade = localidade,
    municipio = municipio,
    estado = estado
  )

  if (is.null(address_fields)) {
    error_null_address_fields()
  }

  return(address_fields)
}

error_null_address_fields <- function() {
  geocodebr_error(
    "Pelo menos um campo n\u00e3o pode ser nulo {.code NULL}.",
    call = rlang::caller_env()
  )
}
