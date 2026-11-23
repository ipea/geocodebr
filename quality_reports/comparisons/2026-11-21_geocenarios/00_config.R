# Configuração comum — comparação geocodebr × Geocenarios (UnB)
# Plano: quality_reports/plans/zippy-giggling-yao-of-427a6eaf-071a-41dc-9168-5d59170fbe46.md

SCRATCH <- "C:/Users/r1701707/AppData/Local/Temp/2/claude/33618e22a2702c6c/427a6eaf-071a-41dc-9168-5d59170fbe46/scratchpad"
.libPaths(c(file.path(SCRATCH, "rlib"), .libPaths()))   # enderecobr 0.6.1 para os dois lados

REPO     <- "L:/Proj_acess_oport/git_rafa/geocodebr"
GEOCEN   <- file.path(SCRATCH, "ext/geocen")            # clone em ffc01e3
GEOCEN_SHA <- "ffc01e3745fa67a034d97c25ee66ad5155dcd1b4"
OUT      <- file.path(SCRATCH, "out")
RAW      <- file.path(SCRATCH, "cnefe_raw")
CACHE    <- "C:/Users/r1701707/AppData/Local/geocodebr/geocodebr/Cache/geocodebr_data_release_v0.5.0"
SAMPLE   <- file.path(REPO, "r-package/inst/extdata/large_sample.parquet")
N_THREADS <- 2L   # = SET threads = 2 hardcoded no Geocenarios (app.R)

suppressPackageStartupMessages({
  library(DBI); library(duckdb); library(dplyr); library(stringr); library(stringi)
  library(sf); library(enderecobr); library(data.table)
})
stopifnot(packageVersion("enderecobr") >= "0.6.1")

carregar_geocodebr <- function() {
  suppressMessages(devtools::load_all(file.path(REPO, "r-package"), quiet = TRUE))
}

UF_COD <- c("12" = "AC", "27" = "AL", "33" = "RJ")
UF_NOME <- c("ACRE" = "AC", "ALAGOAS" = "AL", "RIO DE JANEIRO" = "RJ")

# Regex de pós-processamento que o Geocenarios aplica a address/address2/address3
# (app.R:2410-2418) — aplicada igual às strings de referência do CNEFE.
regex_geocen <- function(x) {
  x <- stringi::stri_trans_toupper(x)
  x <- gsub("[.-]", "", x)
  x <- gsub(";", "", x)
  x <- gsub("TRV", "TRAVESSA", x)
  x <- gsub("\u00ac", "", x)
  x <- gsub("'", "", x)
  x
}
