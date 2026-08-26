geocodebr_message <- function(message, .envir = parent.frame()) {
  message_call <- sys.call(-1)
  message_function <- as.name(message_call[[1]])

  message_classes <- c(
    paste0("geocodebr_message_", sub("^message_", "", message_function)),
    "geocodebr_message"
  )

  cli::cli_inform(message, class = message_classes, .envir = .envir)
}

message_standardizing_addresses <- function() {
  geocodebr_message(c("i" = "Padronizando endere\u00e7os de entrada"))
}

message_baixando_cnefe <- function() {
  geocodebr_message(c("i" = "Baixando dados do CNEFE"))
}

message_usando_cnefe_local <- function() {
  geocodebr_message(c("i" = "Utilizando dados do CNEFE armazenados localmente"))
}

message_looking_for_matches <- function() {
  geocodebr_message(c("i" = "Geolocalizando endere\u00e7os"))
}

message_preparando_output <- function() {
  geocodebr_message(c("i" = "Preparando resultados"))
}

message_cache <- function() {
  geocodebr_message(c("i" = "Nenhum dado em cache local"))
}
