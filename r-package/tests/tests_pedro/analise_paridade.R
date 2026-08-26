# ===================================================================
# SCRIPT 1: ANÁLISE DE PARIDADE (LÓGICA E VISUAL)
#
# Objetivo: Comparar os resultados das funções de geocodificação
# original e em DuckDB para garantir que a lógica é a mesma.
# ===================================================================

# --- 1. SETUP E CONFIGURAÇÃO ---
library(devtools)
library(dplyr)
library(sf)
library(cli)
library(waldo)
library(ggplot2)
library(geobr)
library(arrow)
library(writexl)

devtools::load_all()
source("R/geocode_duckdb.R")
source("R/trata_empates_geocode_duckdb.R")

# --- 2. DEFINIÇÃO DE PARÂMETROS E DIRETÓRIOS ---

# Diretório de output para os mapas
output_dir <- "tests/tests_pedro"
cli_alert_info("Os mapas serão salvos em: '{.path {output_dir}}'")

# Parâmetros para salvar as figuras
img_width <- 40
img_height <- 20
img_dpi <- 300

# Carrega os dados de entrada
input_df <- read.csv(system.file("extdata/small_sample.csv", package = "geocodebr"))

# Definição dos campos de endereço
campos <- geocodebr::definir_campos(
  logradouro = "nm_logradouro", numero = "Numero", cep = "Cep",
  localidade = "Bairro", municipio = "nm_municipio", estado = "nm_uf"
)

# --- 3. EXECUÇÃO E COMPARAÇÃO LÓGICA ---
cli::cli_h1("Análise de paridade dos resultados")
cli_alert_info("Geocodificando com ambas as funções para análise de paridade (pode demorar)...")

# Executa as 4 combinações
df_orig_trat <- geocodebr::geocode(input_df, campos, resolver_empates = TRUE, resultado_sf = TRUE, cache = TRUE, n_cores = 4)
df_orig_nao_trat <- geocodebr::geocode(input_df, campos, resolver_empates = FALSE, resultado_sf = TRUE, cache = TRUE, n_cores = 4)
df_duckdb_trat <- geocode_duckdb(input_df, campos, resolver_empates = TRUE, resultado_sf = TRUE, cache = TRUE, n_cores = 4)
df_duckdb_nao_trat <- geocode_duckdb(input_df, campos, resolver_empates = FALSE, resultado_sf = TRUE, cache = TRUE, n_cores = 4)
cli_alert_success("Geocodificação para paridade concluída.")

# Comparação Lógica com Waldo
#cli_alert_info("Comparando resultados lógicos com waldo::compare()")
#waldo::compare(df_orig_nao_trat, df_duckdb_nao_trat)
#waldo::compare(df_orig_trat, df_duckdb_trat)

# --- 4. COMPARAÇÃO VISUAL (MAPAS) ---
cli::cli_h2("Geração de mapas para comparação visual")

# Preparação dos dados para o mapa
df_orig_trat$funcao <- "Original"
df_orig_nao_trat$funcao <- "Original"
df_duckdb_trat$funcao <- "DuckDB"
df_duckdb_nao_trat$funcao <- "DuckDB"
mapa_df_tratado <- rbind(df_orig_trat, df_duckdb_trat) %>% filter(!sf::st_is_empty(geometry))
mapa_df_nao_tratado <- rbind(df_orig_nao_trat, df_duckdb_nao_trat) %>% filter(!sf::st_is_empty(geometry))

# Baixar a camada de fundo
cli_alert_info("Baixando a malha de estados do Brasil com 'geobr'...")
estados_br <- geobr::read_state(year = 2020)
cli_alert_success("Malha de estados carregada.")

# --- Figura 1: Comparação COM Resolução de Empates ---
cli_alert_info("Gerando e exportando mapa para resultados COM resolução...")
plot_tratado <- ggplot() +
  geom_sf(data = estados_br, fill = "gray95", color = "gray80", size = 0.1) +
  geom_sf(data = mapa_df_tratado, size = 2.5, shape = 21, aes(fill = funcao), color = 'black', alpha = 0.8) +
  facet_wrap(~ funcao) +
  scale_fill_manual(values = c("Original" = "#F8766D", "DuckDB" = "#00BFC4"), name = "Função") +
  labs(title = "Comparação de geocodificação com resolução de empates",
       subtitle = "Distribuição dos pontos geocodificados sobre a malha de estados (amostra pequena)") +
  theme_minimal(base_size = 16) +
  theme(axis.title = element_blank(), axis.text = element_blank(), axis.ticks = element_blank(),
        panel.grid = element_line(color = "#f0f0f0"),
        plot.title = element_text(hjust = 0.5, size = rel(1.5), face = "bold"),
        plot.subtitle = element_text(hjust = 0.5, size = rel(1.1)),
        legend.position = "none")
plot_tratado
ggsave(file.path(output_dir, "mapa_comparacao_tratado.png"), plot = plot_tratado, width = img_width, height = img_height, units = "cm", dpi = img_dpi, bg = "white")
ggsave(file.path(output_dir, "mapa_comparacao_tratado.pdf"), plot = plot_tratado, width = img_width, height = img_height, units = "cm")


# --- Figura 2: Comparação SEM Resolução de Empates ---
cli_alert_info("Gerando e exportando mapa para resultados SEM resolução...")
plot_nao_tratado <- ggplot() +
  geom_sf(data = estados_br, fill = "gray95", color = "gray80", size = 0.1) +
  geom_sf(data = mapa_df_nao_tratado, size = 2.5, shape = 21, aes(fill = funcao), color = 'black', alpha = 0.8) +
  facet_wrap(~ funcao) +
  scale_fill_manual(values = c("Original" = "#F8766D", "DuckDB" = "#00BFC4"), name = "Função") +
  labs(title = "Comparação de geocodificação sem resolução de empates",
       subtitle = "Distribuição dos pontos geocodificados sobre a malha de estados (amostra pequena)") +
  theme_minimal(base_size = 16) +
  theme(axis.title = element_blank(), axis.text = element_blank(), axis.ticks = element_blank(),
        panel.grid = element_line(color = "#f0f0f0"),
        plot.title = element_text(hjust = 0.5, size = rel(1.5), face = "bold"),
        plot.subtitle = element_text(hjust = 0.5, size = rel(1.1)),
        legend.position = "none")
plot_nao_tratado
ggsave(file.path(output_dir, "mapa_comparacao_nao_tratado.png"), plot = plot_nao_tratado, width = img_width, height = img_height, units = "cm", dpi = img_dpi, bg = "white")
ggsave(file.path(output_dir, "mapa_comparacao_nao_tratado.pdf"), plot = plot_nao_tratado, width = img_width, height = img_height, units = "cm")

cli_alert_success("Análise de paridade e geração de mapas concluída.")
