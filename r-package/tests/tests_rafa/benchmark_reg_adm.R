devtools::load_all('.')

library(ipeadatalake)
library(dplyr)
library(data.table)
library(enderecobr)
# library(geocodebr)
# library(mapview)
# library(sfheaders)
# library(sf)
# options(scipen = 999)
# mapview::mapviewOptions(platform = 'leafgl')
set.seed(42)

#' take-away
#' 1) a performance do geocodebr fica muito proxima do arcgis
#' 2) o que precisa fazer eh checar os casos em q a gente encontra com baixa
#' precisao e arcgis com alta. O que a gente pode fazer para melhorar o match?
#' Usar o LIKE logradouro na join ja melhorou muito, mas ainda daria pra melhorar?
#'
#' t <- subset(rais_like, match_type=='case_09' & Addr_type==	'PointAddress')

2+2
# stop()




# cad unico --------------------------------------------------------------------
sample_size <- 10000000

cad_con <- ipeadatalake::ler_cadunico(
  data = 202312,
  base = 'familia',
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
df <- cad_con |>
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
  dplyr::compute() |>
  # dplyr::slice_sample(n = sample_size) |> # sample 20K
  dplyr::collect()

df$id <- 1:nrow(df)

campos <- geocodebr::definir_campos(
  logradouro = 'logradouro',
  numero = 'numero',
  cep = 'cep',
  localidade = 'bairro',
  municipio = 'code_muni',
  estado = 'abbrev_state'
)

stop()


gc(T,T,T)
#bench::system_time(
bench::mark(iterations = 1,
  cadgeo <- geocodebr::geocode(
    enderecos  = df,
    campos_endereco = campos,
    n_cores = 7, # 7
    verboso = T,
    resultado_completo = F,
    resolver_empates = T,
    padronizar_enderecos = T
    )
)

# process    real
#    2.8m   18.1m

# 10 milhoes
# args: n_cores = 7, resultado_completo = F resolver_empates = T
# expression        min median `itr/sec` mem_alloc `gc/sec` n_itr  n_gc total_time result memory
# v0.3.0 CRAN     29.7m  29.7m  0.000562    18.3GB   0.0725     1   129      29.7m <NULL> <Rprofmem>
# v0.4.0 CRAN     33.5m  33.5m  0.000497    8.06GB  0.00746     1    15      33.5m <NULL> <Rprofmem>
# v0.5.0 CRAN     6.04m  6.04m   0.00276     916MB  0.00276     1     1      6.04m <df>   <Rprofmem> <bench_tm> <tibble>
# v0.6.4 CRAN     5.04m  5.04m   0.00331    1016MB        0     1     0      5.04m <df>   <Rprofmem> <bench_tm> <tibble>
# v0.7.0  dev     4.36m  4.36m   0.00382    1016MB  0.00764     1     2      4.36m <df>   <Rprofmem> <bench_tm> <tibble>
# v0.7.0 dev+ties 4.07m  4.07m   0.00410    1012MB  0.00820     1     2      4.07m <df>   <Rprofmem>


# v0.5.0 CRAN     2.39m !!!! em paralelo
# v0.6.0 dev      2.16m !!!! em paralelo



# 43 milhoes
# args: n_cores = 7, resultado_completo = F resolver_empates = T
# expression        min median `itr/sec` mem_alloc `gc/sec` n_itr  n_gc total_time result memory
# v0.3.0 CRAN        2h     2h  0.000139    79.3GB   0.0176     1   127         2h <dt>
# v0.4.0 CRAN      3.3h   3.3h 0.0000843    34.5GB  0.00244     1    29       3.3h <dt>   <Rprofmem> <bench_tm> <tibble>
# v0.5.0 CRAN     24.9m  24.9m  0.000670    4.12GB  0.00134     1     2      24.9m <df>
# v0.6.4 CRAN     18.7m  18.7m  0.000891    3.92GB  0.00178     1     2      18.7m <df>   <Rprofmem> <bench_tm> <tibble>
# v0.7.0  dev     17.0m    17m  0.000979    4.12GB 0.000979     1     1        17m <df>   <Rprofmem> <bench_tm> <tibble>
# v0.7.0 dev+ties


 # v0.5.0  8.99m  !!!! em paralelo por uf
 # v0.6.0  7.24m  !!!! em paralelo por uf

# encontra setor censitario para % do cad unico
1- sum(is.na(cadgeo$cod_setor)) / nrow(cadgeo)
# v0.6.0: 0.6438606


# nao era para ser empate
# 5 "da02" "da02"   mesmo rua e cep
# [1] "RUA PAULO SIMOES DA COSTA, 32 (aprox) - JARDIM ANGELA, SAO PAULO - SP, 04929-140"
# [2] "RUA PAULO SIMOES DA COSTA, 32 (aprox) - ALTO DO RIVIERA, SAO PAULO - SP, 04929-140"



## cadunico cada passo ----------------

gc(T,T,T)
bench::bench_time(
 #bench::mark(
 callr::r(function(df, campos) {
   rfiles <- list.files("R", full.names = TRUE)
   invisible(lapply(rfiles, source))
   library("data.table")
   # library("geocodebr")
   cadgeo <- geocode_core(
     enderecos = df,
     campos_endereco = campos,
     n_cores = 7,
     resultado_completo = F,
     verboso = T,
     resolver_empates = T,
     resultado_sf = F,
     padronizar_enderecos = T,
     h3_res = NULL,
     cache = T
   )
 },
 args = list(df = df, campos = campos),
 show = TRUE
 )
)

# 10 milhoes
# v0.6.0 dev
#                             step_sec total_sec step_relative
#                       Start     0.00      0.00           0.0
#                Padronizacao    29.00     29.00          11.9
# Register standardized input    22.14     51.14           9.1
#                    Matching   159.42    210.56          65.2
#             Resolve empates     7.39    217.95           3.0
#   Write original input back     3.82    221.77           1.6
#               Add precision     0.36    222.13           0.1
#               Merge results    22.40    244.53           9.2
#                                          4.07m


# 43 milhoes
# v0.6.0 dev
#                             step_sec total_sec step_relative
#                       Start     0.02      0.02           0.0
#                Padronizacao   102.76    102.78          12.5
# Register standardized input    85.88    188.66          10.5
#                    Matching   499.81    688.47          60.9
#             Resolve empates    31.94    720.41           3.9
#   Write original input back    17.32    737.73           2.1
#               Add precision     1.94    739.67           0.2
#               Merge results    80.92    820.59           9.9
#                                         17.27m


## cadunico parallel callr ----------------

# library(future.callr)
library(future)
library(furrr)

df$abbrev_state <- enderecobr::padronizar_estados(df$abbrev_state)
df$code_muni <- enderecobr::padronizar_municipios(df$code_muni)

future::plan(future::multisession)


gc(T,T,T)
bench::bench_time(
 a <-   split(df, f = df$abbrev_state) |>
   furrr::future_map(
     .progress = TRUE,
     .f = function(x){
       geocode(
         enderecos = x,
         campos_endereco = campos,
         resultado_completo = F,
         resolver_empates = T
       )
     }
   )

)

bench::bench_time(

a <- data.table::rbindlist(a)
)

quantile(a$desvio_metros, na.rm = T, probs = c(0.5, 0.7, 0.75, 0.8, 0.85, 0.9))
  # 50%   70%   75%   80%   85%   90%
  #   7   228   451   864  2418 10763


# rais --------------------------------------------------------------------

rais <- ipeadatalake::ler_rais(
  ano = 2019,
  tipo = 'estabelecimento',
  as_data_frame = F,
  geoloc = T) |>
  select("id_estab", "logradouro", "bairro", "codemun", "uf", "cep",
         'lat', 'lon', 'Addr_type', 'Match_addr') |>
  compute() |>
  dplyr::slice_sample(n = 1000000) |> # sample 10 million
  filter(uf != "IG") |>
  filter(uf != "") |>
  collect()


# rais <- head(rais, n = 1000) |> collect() |> dput()
data.table::setDT(rais)

# create column number
rais[, numero := gsub("[^0-9]", "", logradouro)]

# remove numbers from logradouro
rais[, logradouro_no_numbers := gsub("//d+", "", logradouro)]
rais[, logradouro_no_numbers := gsub(",", "", logradouro_no_numbers)]

rais[, id := 1:nrow(rais)]

data.table::setnames(
  rais,
  old = c('lat', 'lon'),
  new = c('lat_arcgis', 'lon_arcgis')
)


head(rais)


fields <- geocodebr::definir_campos(
  logradouro = 'logradouro_no_numbers',
  numero = 'numero',
  cep = 'cep',
  bairro = 'bairro',
  municipio = 'codemun',
  estado = 'uf'
)



rais_geo <- geocodebr::geocode(
    addresses_table = rais,
    address_fields = fields,
    n_cores = 7,
    full_results =  T,
    progress = T
  )



# censo escolar ---------------------------------

censo_escolar <- ipeadatalake::ler_censo_escolar(
  ano = 2022,
  base = 'basica'
  )  |>
  select(
    c("NU_ANO_CENSO",                "NO_REGIAO",
      "CO_REGIAO",                   "NO_UF",
      "SG_UF",                       "CO_UF",
      "NO_MUNICIPIO",                "CO_MUNICIPIO",
      "NO_MESORREGIAO",              "CO_MESORREGIAO",
      "NO_MICRORREGIAO",             "CO_MICRORREGIAO",
      "CO_DISTRITO",                 "NO_ENTIDADE",
      "CO_ENTIDADE",                 "TP_DEPENDENCIA",
      "TP_CATEGORIA_ESCOLA_PRIVADA", "TP_LOCALIZACAO",
      "TP_LOCALIZACAO_DIFERENCIADA", "DS_ENDERECO",
      "NU_ENDERECO",                 "DS_COMPLEMENTO",
      "NO_BAIRRO",                   "CO_CEP",
      "NU_DDD")
    ) |>
  dplyr::collect()


censo_escolar$id <- 1:nrow(censo_escolar)

fields_cad <- geocodebr::definir_campos(
  logradouro = 'DS_ENDERECO',
  numero = 'NU_ENDERECO',
  cep = 'CO_CEP',
  localidade = 'NO_BAIRRO',
  municipio = 'NO_MUNICIPIO',
  estado = 'NO_UF'
)

# bench::mark( iterations = 1,
bench::system_time(
  geo <- geocodebr::geocode(
    enderecos  = censo_escolar,
    campos_endereco = fields_cad,
    resultado_completo = T,
    n_cores = 25, # 7
    verboso = T,
    resultado_sf = F,
    resolver_empates = F
  )
)



