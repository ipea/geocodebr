# ===================================================================
# SCRIPT 2: BENCHMARK DE PERFORMANCE
#
# Objetivo: Comparar a velocidade de execução das funções de
# tratamento de empates em amostras de dados de diferentes tamanhos.
# ===================================================================

# --- 1. SETUP E CONFIGURAÇÃO ---
library(devtools)
library(dplyr)
library(data.table)
library(cli)
library(bench)
library(readr)

devtools::load_all()
source("R/trata_empates_geocode_duckdb.R")
# --- 2. DEFINIÇÃO DE PARÂMETROS E DIRETÓRIOS ---

output_dir <- "tests/tests_pedro"

# --- 3. PREPARAÇÃO DOS DADOS DE BENCHMARK ---
cli::cli_h1("Preparação dos dados")

cli_alert_info("Carregando e preparando amostras de dados...")

output_df <- readRDS(paste0(output_dir, "/output_df_large_sample.rds"))
output_df_pequeno <- readRDS(paste0(output_dir, "/output_df_small_sample.rds"))
set.seed(123)
output_df_grande <- output_df |> slice_sample(n = 500000, replace = TRUE)
con <- geocodebr:::create_geocodebr_db(n_cores = 4)

cli_alert_success("Amostras de dados prontas.")

# --- 4. EXECUÇÃO DO BENCHMARK ---
cli::cli_h1("Execução do benchmark de performance")

suppressWarnings(benchmark_grid_trat <- bench::press(
  nome = c("Amostra pequena (27 obs)", "Amostra média (22k obs)", "Amostra grande (500k obs)"),
  resolver = TRUE,
  {
    data_atual <- if (nome == "Amostra pequena (27 obs)") {
      output_df_pequeno
    } else if (nome == "Amostra média (22k obs)") {
      output_df
    } else output_df_grande
    status_txt <- if(resolver) "COM resolução" else "SEM resolução"
    cli::cli_progress_step("Benchmarking: {nome} / {status_txt}")

    bench::mark(
      Original = geocodebr:::trata_empates_geocode(data_atual, resolver_empates = resolver, verboso = FALSE),
      DuckDB = trata_empates_geocode_duckdb(data_atual, resolver_empates = resolver, verboso = FALSE, con = con),
      min_iterations = 10,
      check = FALSE
    )
  }
)
)

print(benchmark_grid_trat)

suppressWarnings(benchmark_grid_sem_trat <- bench::press(
  nome = c("Amostra pequena (27 obs)", "Amostra média (22k obs)", "Amostra grande (500k obs)"),
  resolver = FALSE,
  {
    data_atual <- if (nome == "Amostra pequena (27 obs)") {
      output_df_pequeno
    } else if (nome == "Amostra média (22k obs)") {
      output_df
    } else output_df_grande
    status_txt <- if(resolver) "COM resolução" else "SEM resolução"
    cli::cli_progress_step("Benchmarking: {nome} / {status_txt}")

    bench::mark(
      Original = geocodebr:::trata_empates_geocode(data_atual, resolver_empates = resolver, verboso = FALSE),
      DuckDB = trata_empates_geocode_duckdb(data_atual, resolver_empates = resolver, verboso = FALSE, con = con),
      min_iterations = 10,
      check = FALSE
    )
  }
)
)

print(benchmark_grid_sem_trat)

cli_alert_success("Benchmark concluído!")

# --- 5. ANÁLISE E EXPORTAÇÃO DOS RESULTADOS ---
cli::cli_h1("Exportando resultados dos benchmarks")

# Exporta a tabela de resultados para um arquivo CSV
output_csv_path <- file.path(output_dir, "benchmark_resultados.csv")
readr::write_csv(benchmark_grid, output_csv_path)
cli_alert_success("Resultados numéricos do benchmark salvos em: '{.path {output_csv_path}}'")


