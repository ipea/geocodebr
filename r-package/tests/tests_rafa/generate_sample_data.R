devtools::load_all('.')
library(tictoc)
library(dplyr)
library(data.table)
library(ipeadatalake)
set.seed(42)

sample_size <- 10000

data_path <- system.file("extdata/small_sample.csv", package = "geocodebr")
input_df <- read.csv(data_path)

# select and reorder columns
input_df <- input_df |>
  select(
    id = id,
    logradouro = nm_logradouro,
    numero = Numero,
    bairro = Bairro,
    cep = Cep,
    municipio = nm_municipio,
    uf = nm_uf
  )

head(input_df)

# rais --------------------------------------------------------------------

rais <- ipeadatalake::ler_rais(
  ano = 2019,
  tipo = 'estabelecimento',
  as_data_frame = T,
  colunas = c("id_estab", "logradouro",
              "bairro", "codemun", "uf", "cep")) |>
  filter(uf %in% c(12, 27, 33)) |> # only states of Acre, Alagoas and RJ
  compute() |>
  dplyr::slice_sample(n = sample_size) |> # sample 50K
  filter(uf != "IG") |>
  filter(uf != "") |>
  collect()

data.table::setDT(rais)

# create column number
rais[, numero := gsub("[^0-9]", "", logradouro)]

# remove numbers from logradouro
rais[, logradouro := gsub("\\d+", "", logradouro)]
rais[, logradouro := gsub(",", "", logradouro)]


# select and reorder columns
rais <- rais |>
  select(
    id = id_estab,
    logradouro = logradouro,
    numero = numero,
    bairro = bairro,
    cep = cep,
    municipio = codemun,
    uf = uf
  )

head(rais)






# cad unico --------------------------------------------------------------------

cad <- ipeadatalake::ler_cadunico(
  data = 201912,
  tipo = 'familia',
  as_data_frame = F,
  colunas = c("co_familiar_fam", "co_uf", "cd_ibge_cadastro",
              "no_localidade_fam", "no_tip_logradouro_fam",
              "no_tit_logradouro_fam", "no_logradouro_fam",
              "nu_logradouro_fam", "ds_complemento_fam",
              "ds_complemento_adic_fam",
              "nu_cep_logradouro_fam", "co_unidade_territorial_fam",
              "no_unidade_territorial_fam", "co_local_domic_fam")
)

# a <- tail(cad, n = 100) |> collect()

# compose address fields
cad <- cad |>
  filter(co_uf %in% c(12, 27, 33)) |> # only states of Acre, Alagoas and RJ
  compute() |>
  dplyr::slice_sample(n = sample_size) |> # sample 20K
  mutate(no_tip_logradouro_fam = ifelse(is.na(no_tip_logradouro_fam), '', no_tip_logradouro_fam),
         no_tit_logradouro_fam = ifelse(is.na(no_tit_logradouro_fam), '', no_tit_logradouro_fam),
         no_logradouro_fam = ifelse(is.na(no_logradouro_fam), '', no_logradouro_fam)
  ) |>
  mutate(abbrev_state = co_uf,
         code_muni = cd_ibge_cadastro,
         logradouro = paste(no_tip_logradouro_fam, no_tit_logradouro_fam, no_logradouro_fam),
         numero = nu_logradouro_fam,
         cep = nu_cep_logradouro_fam,
         bairro = no_localidade_fam) |>
  select(co_familiar_fam,
         abbrev_state,
         code_muni,
         logradouro,
         numero,
         cep,
         bairro) |>
  dplyr::collect()



cad <- cad |>
  select(
    id = co_familiar_fam,
    logradouro = logradouro,
    numero = numero,
    bairro = bairro,
    cep = cep,
    municipio = code_muni,
    uf = abbrev_state
  )



df <- rbind(input_df, cad, rais)

setDT(df)
df[, id := 1:nrow(df)]
head(df)

data.table::setindex(df, NULL)
data.table::setDF(df)

arrow::write_parquet(df, './inst/extdata/large_sample.parquet')




