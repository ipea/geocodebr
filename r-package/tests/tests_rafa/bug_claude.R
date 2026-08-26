library(geocodebr)

# ler amostra de dados
data_path <- system.file("extdata/small_sample.csv", package = "geocodebr")
input_df <- read.csv(data_path)

campos <- geocodebr::definir_campos(
  logradouro = "nm_logradouro",
  numero = "Numero",
  cep = "Cep",
  localidade = "Bairro",
  municipio = "nm_municipio",
  estado = "nm_uf"
)

dfF <- geocodebr::geocode(
  enderecos = input_df,
  campos_endereco = campos,
  resolver_empates = TRUE,
  resultado_completo = F
  )


dfT <- geocodebr::geocode(
  enderecos = input_df,
  campos_endereco = campos,
  resolver_empates = TRUE,
  resultado_completo = T
)

dplyr::glimpse(dfF)
dplyr::glimpse(dfT)




# ----------------------------------------------------------------------------------


library(geocodebr)

data_path <- system.file("extdata/large_sample.parquet", package = "geocodebr")
input_df <- arrow::read_parquet(data_path)

campos <- geocodebr::definir_campos(
  logradouro = 'logradouro',
  numero = 'numero',
  cep = 'cep',
  localidade = 'bairro',
  municipio = 'municipio',
  estado = 'uf'
)


dfT <- geocodebr::geocode(
  enderecos = input_df,
  campos_endereco = campos,
  resolver_empates = T,
  resultado_completo = T,
)

dplyr::glimpse(dfT)


table(dfT$logradouro_encontrado, useNA = "always")





df1 <- geocodebr::geocode(
  enderecos = input_df,
  campos_endereco = campos,
  resolver_empates = T,
  resultado_completo = T,
)

df2 <- geocodebr::geocode(
  enderecos = input_df,
  campos_endereco = campos,
  resolver_empates = T,
  resultado_completo = F,
)

df3 <- geocodebr::geocode(
  enderecos = input_df,
  campos_endereco = campos,
  resolver_empates = F,
  resultado_completo = T,
)


df4 <- geocodebr::geocode(
  enderecos = input_df,
  campos_endereco = campos,
  resolver_empates = F,
  resultado_completo = F,
)

