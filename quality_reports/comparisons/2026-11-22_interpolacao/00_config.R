# Configuração — benchmark de interpolação de número ausente (lição 3)
# Plano: quality_reports/plans/2026-11-22_interpolacao-numero-ausente.md

source("L:/Proj_acess_oport/git_rafa/geocodebr/quality_reports/comparisons/2026-11-21_geocenarios/00_config.R")
# herda SCRATCH, REPO, CACHE, SAMPLE, carregar_geocodebr(); lib temporária com duckdb 2.0.0

DIR   <- file.path(REPO, "quality_reports/comparisons/2026-11-22_interpolacao")
SAI   <- file.path(DIR, "saidas")                 # saídas pequenas, versionáveis
OUT2  <- file.path(SCRATCH, "interp")             # saídas grandes
dir.create(OUT2, showWarnings = FALSE, recursive = TRUE)
dir.create(SAI, showWarnings = FALSE, recursive = TRUE)

PQ_NUM   <- file.path(CACHE, "municipio_logradouro_numero_cep_localidade.parquet")
DB_FILE  <- Sys.getenv("INTERP_DB", file.path(OUT2, "interp.duckdb"))   # confirmação: outra base/semente
MUNIS_FORA <- c(2704302L, 4106902L)               # Maceió e Curitiba: usadas no pré-teste
SEED     <- Sys.getenv("INTERP_SEED", "lição3")
SUF      <- if (SEED == "lição3") "" else "_conf"   # saídas da amostra de confirmação não sobrescrevem as principais

# parâmetros congelados antes do teste (plano, "Congelamento")
K_M2        <- 4L
TRAVA_A     <- 3      # trava de salto: dist(L,U) > TRAVA_A*(U-L) + TRAVA_B
TRAVA_B     <- 50
CORTE_CURVA <- 0.15   # curvatura = flecha p90 / extensão (e flecha > 25 m)
CORTE_RETA  <- 0.05

con_interp <- function(threads = N_THREADS, file = DB_FILE) {
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = file)
  DBI::dbExecute(con, sprintf("SET threads = %d", threads))
  DBI::dbExecute(con, "SET memory_limit = '32GB'")
  DBI::dbExecute(con, "SET preserve_insertion_order = false")
  DBI::dbExecute(con, "
    CREATE OR REPLACE MACRO hav(la1, lo1, la2, lo2) AS
      2 * 6371008.8 * asin(sqrt(pow(sin(radians(la2 - la1) / 2), 2) +
        cos(radians(la1)) * cos(radians(la2)) * pow(sin(radians(lo2 - lo1) / 2), 2)))")
  con
}

REGIAO <- c(RO="N",AC="N",AM="N",RR="N",PA="N",AP="N",TO="N",
            MA="NE",PI="NE",CE="NE",RN="NE",PB="NE",PE="NE",AL="NE",SE="NE",BA="NE",
            MG="SE",ES="SE",RJ="SE",SP="SE",PR="S",SC="S",RS="S",
            MS="CO",MT="CO",GO="CO",DF="DF")
