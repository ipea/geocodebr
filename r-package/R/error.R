geocodebr_error <- function(message, call, .envir = parent.frame()) {
  error_call <- sys.call(-1)
  error_function <- as.name(error_call[[1]])

  error_classes <- c(
    paste0("geocodebr_error_", sub("^error_", "", error_function)),
    "geocodebr_error"
  )

  cli::cli_abort(message, class = error_classes, call = call, .envir = .envir)
}


error_input_nao_padronizado <- function() {
  geocodebr_error(
    c(
      "Os dados de entrada nao estao padronizados.",
      "i" = "Use o argumento `padronizar_enderecos = TRUE`, ou
      padronize os dados de input com `enderecobr::padronizar_enderecos(..., formato_estados = 'sigla', formato_numeros = 'integer')`."
    ),
    call = rlang::caller_env(n = 2)
  )
}
