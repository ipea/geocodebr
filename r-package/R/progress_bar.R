create_progress_bar <- function(standard_locations, .envir = parent.frame()) {
  cli::cli_progress_bar(
    total = nrow(standard_locations),
    format = " Casos processados: {formatC(cli::pb_current, big.mark = ',', format = 'd')}/{formatC(cli::pb_total, big.mark = ',', format = 'd')} {cli::pb_bar} {cli::pb_percent} - {cli::pb_status}",
    clear = FALSE,
    .envir = .envir
  )
}

update_progress_bar <- function(
  matched_rows,
  formatted_case,
  .envir = parent.frame()
) {
  cli::cli_progress_update(
    set = matched_rows,
    status = glue::glue("{formatted_case}"),
    force = TRUE,
    .envir = .envir
  )
}

finish_progress_bar <- function(matched_rows, .envir = parent.frame()) {
  cli::cli_progress_update(
    set = matched_rows,
    status = "Fim!",
    force = TRUE,
    .envir = .envir
  )
}
