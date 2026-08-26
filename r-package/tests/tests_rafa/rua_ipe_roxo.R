# # open input data
# data_path <- system.file("extdata/small_sample.csv", package = "geocodebr")
# input_df <- read.csv(data_path, encoding = 'Latin-1')
#
# campos <- geocodebr::definir_campos(
#   logradouro = 'nm_logradouro',
#   numero = 'Numero',
#   cep = 'Cep',
#   localidade = 'Bairro',
#   municipio = 'nm_municipio',
#   estado = 'nm_uf'
# )
#
# df_geo <- geocodebr::geocode(
#     enderecos = input_df,
#     campos_endereco = campos,
#     n_cores = 7,
#     resultado_completo = T,
#     verboso = T
#   )
#
#
# df_rafaF$lat |> nchar() |> summary()
#
# lapply(X=df_rafaF$lat, FUN=decimalplaces) |>  unlist() |> summary()
#
# a <- subset(df_rafaF, nchar(lat) <= 6 )
#
#
#   filtered_cnefedf$lat |> nchar() |> summary()
#   lapply(X=filtered_cnefedf$lat, FUN=decimalplaces) |>  unlist() |> as.numeric() |> summary()
#
#
#
#
#
library(dplyr)
library(mapview)
library(sfheaders)
library(data.table)
mapviewOptions(platform = 'leafgl')

sp_muni <- geobr::read_municipality(code_muni = 3550308)


filtered_cnefe_sp <- arrow::open_dataset( geocodebr::listar_dados_cache()[11] ) |>
    dplyr::filter(estado == 'SP') |>
    dplyr::filter(municipio == "SAO PAULO") |>
    dplyr::filter(logradouro_sem_numero == "RUA IPE ROXO") |>
    dplyr::collect()

a <- subset(filtered_cnefe_sp, cep == "04896-360")
a <- subset(filtered_cnefe_sp, cep == "04896-360")

table(a$localidade)
#> RUA IPE ROXO
#>          243

a <- sfheaders::sf_point(
  obj = a,
  x = 'lon',
  y = 'lat',
  keep = TRUE
)
sf::st_crs(a) <- 4674

mapview::mapview(a, zcol='localidade') + sp_muni

#   table(a$localidade)
#   table(a$logradouro_sem_numero)
#   table(a$cep)
#
#     a <- subset(filtered_cnefe_sp, localidade %like% "COLONIA")
#

library(geocodebr)
library(mapview)

df <- data.frame(
  estado = 'sp',
  municipio = 'sao paulo',
  logradouro = 'rua ipe roxo',
  numero = 1:5000,
  bairro = NA, #'vargem grande',
  cep = "04896-360"
  )

sp_muni <- geobr::read_municipality(code_muni = 3550308)

campos <- geocodebr::definir_campos(
  logradouro = 'logradouro',
  numero = 'numero',
  cep = 'cep',
  localidade = 'bairro',
  municipio = 'municipio',
  estado = 'estado'
)

df_geo <- geocodebr::geocode(
  enderecos = df,
  campos_endereco = campos,
  resultado_completo = T,
  verboso = T,
  resultado_sf = T
)
# nchar(df_geo$lat) # -23.85401
# df_geo

mapview::mapview(df_geo, zcol='numero') + sp_muni

df_geo$lat



# teste TSE ---------------


df <- data.table::fread("teste_geocodebr_1km.csv")
head(df)
i <- 7
dfi <- df[i,]
dfi$tipo_resultado

bairroi <- df[i, 'NM_BAIRRO']$NM_BAIRRO
logr <- df[i, 'LOGRADOURO']$LOGRADOURO |> enderecobr::padronizar_logradouros()
num <- df[i, 'NUMERO']$NUMERO
cepi <- df[i, 'NR_CEP']$NR_CEP |> enderecobr::padronizar_ceps()
muni <- df[i, 'nm_municipio']$nm_municipio
uf <- df[i, 'nm_uf']$nm_uf

tudo <- geocodebr::listar_dados_cache()[11]
tudo <- geocodebr::listar_dados_cache()[11]


filtered_cnefe_sp <- arrow::open_dataset( tudo ) |>
  dplyr::filter(estado == 'SP') |>
  dplyr::filter(municipio == "SAO PAULO") |>
   dplyr::filter(logradouro_sem_numero == logr) |>
  # dplyr::filter(cep == cepi) |>
  #  dplyr::filter(localidade == bairroi) |>
  # dplyr::filter(lat > -23.574453 & lat < -23.567316 &    # parque sao domingos
  #               lon > -46.719479 & lon < -46.704553) |> # parque sao domingos
  dplyr::collect()


# cnefe_original <- ipeadatalake::ler_cnefe(ano = 2022, as_data_frame = F) |> dplyr::compute()
#
# filtered_cnefe_sp <- cnefe_original |>
#   dplyr::compute() |>
#   dplyr::filter(cep == 08461620) |>
#   dplyr::collect()


# -23.566701, -46.717479       -23.567316, -46.704360
#
# -23.574453, -46.719479      -23.574429, -46.704553

unique(filtered_cnefe_sp$logradouro_sem_numero)
unique(filtered_cnefe_sp$cep)
unique(filtered_cnefe_sp$localidade)
unique(filtered_cnefe_sp$numero)

a <- subset(filtered_cnefe_sp, cep == "04896-360")


campos <- geocodebr::definir_campos(
  logradouro = 'LOGRADOURO',
  numero = 'NUMERO',
  cep = 'NR_CEP',
  localidade = 'NM_BAIRRO',
  municipio = 'nm_municipio',
  estado = 'nm_uf'
)

df_geo <- geocodebr::geocode(
  enderecos = select( df, -c("lat", "lon", "tipo_resultado",'precisao')),
  campos_endereco = campos,
  resultado_completo = T,
  verboso = T,
  resultado_sf = F
)


a <- sfheaders::sf_point(
  obj = filtered_cnefe_sp,
  x = 'lon',
  y = 'lat',
  keep = TRUE
)
sf::st_crs(a) <- 4674

mapview::mapview(a, zcol='localidade') + df_geo



#' notas internas:
#' casos (1) e (5) criar o probabilistico e ver se corrige
#'
#' 2) se tem dois lograd com mesmo cep, pq o left join só retorna um e nao os dois?
#'  porque na hora de gerar os parquets, a gente tira a media sem a coluna de localidade
#'  e dai a media dá um resultado bizarro no meio do caminho.
#'  SE alternativamente a gente fizer pra categoria er02 o merge com o parquet
#'  que inclui o bairro, daí o left join retorna mais de um resultado. E dai
#'  poderiamos indicar caso de empate
#'

#' 1) COLÉGIO EQUIPE
#' ok: google e TSE
#' O logradouro está com uma letra errada no dado de input. O nome correto da é
#' 'Sao Vicente de PaulO', mas o input é de PaulA. TSE e Google maps concordam.
#' geocodebr erra feio porque ainda nao tem match probabilistico por string.
#' Se corrigir o nome da rua no input, o geocodebr acerta. Mas uma proxima etapa
#' é implementar o match probabilistico mesmo.
#'
#' 2) E.E. JOSÉ DE SAN MARTIN
#' ok: google e TSE
#' Caso parecido com o da  'RUA IPE ROXO'. O CNEFE aponta que existem endereços
#' no logradouro "RUA DELTA" e com o mesmo CEP "08071-060" em áreas completamente
#' distantes entre si. Nos bairros "JABAQUARA" e "UNIAO VILA NOVA". Como nessa
#' categoria o geocodebr tira a media das coordenadas de todos enderecos com mesmo
#' lograouro e cep, o resultado sai num lugar no meio do caminho e sem sentido.
#' To pensando uma solucao aqui q recupera a info do bairro, mesmo quando ele nao
#' bate com o input do usuario.
#'
#' 3) EMEF. AMADEU MENDES
#' O dado de input parece correto e o cnefe errado.
#' CNEFE: localidade "SAO DOMINGOS" mas deveria ser "PARQUE SAO DOMINGOS". E o cenfe
#' tem uns pontos soltos mais perto do centro com esse mesmo bairro. estranho
#' CNEFE: logradouro "RUA JOAO FERREIRA" mas deveria ser "RUA TOMAS LOPES FERREIRA"
#'
# dplyr::filter(lat > -23.547470 & lat < -23.476933 &    # parque sao domingos
#               lon > -46.780367 & lon < -46.710332 ) |> # parque sao domingos
#'
#'
#' 4) ESCOLA ESTADUAL ALBERTO TORRES
#' input correto. Erro no cnefe onde a avenida muda de nome de "AVENIDA VITAL BRASIL" (correto)
#' para "AVENIDA DOUTOR VITAL"
#'
#  dplyr::filter(lat > -23.574453 & lat < -23.567316 &    # parque sao domingos
#                  lon > -46.719479 & lon < -46.704553) |> # parque sao domingos
#
#'
#'5) EE  AQUILINO RIBEIRO
#' ok: TSE e geocodebr
#' As coordenadas do Google map estao erradas. Mas as coordenadas do TSE e
#' geocodebr sao bem proximas! E isso acontece apesar de ter um erro no input.
#' No input esta "RUA ONOFRE LEITE MEIRELES" e deveria ser 'MEIRELLES' com dois 'L'
#' geocodebr: deve pegar quando tiver match probabilistico, mas mesmo assim acerta
#' pelo cep
#'
#'
#'
#' 6) EE PROF. MARIO ARMINANTE
#' ok: TSE e geocodebr
#' as coordenadas do TSE e o geocodebr estao bem proximas (170 metros). Parece
#' correto mesmo olhando o google street view. As coordenadas do google maps
#' levam para uma outra instituição chamada 'CEU EMEF MANOEL VIEIRA DE QUEIROZ
#' FILHO'
#'
#'
#' 7) EE AYRTON SENNA DA SILVA
#' caso da RUA IPE ROXO. Dado de input parece q tem alguns erros:
#'  - input tem bairro "COLONIA (ZONA SUL)" q nao condiz com google maps
#'  - input tem cep "04896-260" q é "errado" e que joga na "RUA DAS ARARAS", que
#'  é 4 ruas pro lado da 'R IPE ROXO'. O CEP correto da escola seria '04896-360',
#'  MAS o CNEFE aponta q tem RUA IPE ROXO com esse cep "04896-360" em regioes muito
#'  diferentes de SP.
#'



# rua ipe roxo ---------------

tudo <- geocodebr::listar_dados_cache()[11]
log_e_cep <- geocodebr::listar_dados_cache()[6]
log_e_cep_e_localidade <- geocodebr::listar_dados_cache()[7]


filtered_cnefe_sp <- arrow::open_dataset( tudo  ) |> # tudo
  dplyr::filter(estado == 'SP') |>
  dplyr::filter(municipio == "SAO PAULO") |>
 dplyr::filter(logradouro_sem_numero == "RUA IPE ROXO") |>
 # dplyr::filter(cep == "04896-360") |>   # ESSE EH O CEP PROBLEMATICO
  dplyr::collect()

setDT(filtered_cnefe_sp)[, . (lat=mean(lat), lon=mean(lon)), by= c("logradouro_sem_numero", "cep",'localidade')]


a <- sfheaders::sf_point(
  obj = filtered_cnefe_sp,
  x = 'lon',
  y = 'lat',
  keep = TRUE
)
sf::st_crs(a) <- 4674

mapview::mapview(a, zcol='localidade')



filtered_cnefe_sp <- arrow::open_dataset( log_e_cep ) |>
  dplyr::filter(estado == 'SP') |>
  dplyr::filter(municipio == "SAO PAULO") |>
  dplyr::filter(logradouro_sem_numero == "RUA IPE ROXO") |>
  dplyr::filter(cep == "04896-360") |>
  dplyr::collect()


setDT(filtered_cnefe_sp)[, . (lat=mean(lat), lon=mean(lon)), by= c("logradouro_sem_numero", "cep")]



# rua delta ---------------

tudo <- geocodebr::listar_dados_cache()[11]
log_e_cep <- geocodebr::listar_dados_cache()[6]
log_e_cep <- geocodebr::listar_dados_cache()[7]

filtered_cnefe_sp <- arrow::open_dataset( tudo ) |>
  dplyr::filter(estado == 'SP') |>
  dplyr::filter(municipio == "SAO PAULO") |>
  dplyr::filter(logradouro_sem_numero == "RUA DELTA") |>
  dplyr::filter(cep == "08071-060") |>
  dplyr::collect()


filtered_cnefe_sp <- arrow::open_dataset( log_e_cep ) |>
  dplyr::filter(estado == 'SP') |>
  dplyr::filter(municipio == "SAO PAULO") |>
  dplyr::filter(logradouro_sem_numero == "RUA DELTA") |>
  dplyr::filter(cep == "08071-060") |>
  dplyr::collect()


seDT(filtered_cnefe_sp)

filtered_cnefe_sp[, . (lat=mean(lat), lon=mean(lon)), by= c("logradouro_sem_numero", "cep",'localidade'  )]







# rua nove, mage sp ---------------


filtered_cnefe_sp <- arrow::open_dataset( geocodebr::listar_dados_cache()[11] ) |>
  dplyr::filter(estado == 'RJ') |>
  dplyr::filter(municipio == "MAGE") |>
  dplyr::filter(logradouro_sem_numero == "RUA NOVE") |>
  # dplyr::filter(localidade == "PRAIA DA ESPERANCA") |>
  dplyr::collect()

a <- subset(filtered_cnefe_sp, cep == "04896-360")
a <- subset(filtered_cnefe_sp, cep == "04896-360")

table(a$localidade)
#> RUA IPE ROXO
#>          243

a <- sfheaders::sf_point(
  obj = filtered_cnefe_sp,
  x = 'lon',
  y = 'lat',
  keep = TRUE
)
sf::st_crs(a) <- 4674

mapview::mapview(a, zcol='localidade')







# rua padre vieira em sao goncalo ---------------------------------------------------------------------------
# numero cresce e depois diminui
# mesmo numero em ceps diferentes em potas opostas da rua

cidade <- arrow::open_dataset( tudo ) |>
  dplyr::filter(estado == 'RJ') |>
  dplyr::filter(municipio == "SAO GONCALO") |>
  dplyr::collect()


cidade_case <- cidade |>
  dplyr::filter(logradouro_sem_numero == "AVENIDA PADRE VIEIRA") |>
  # dplyr::filter(cep == "23065-110")
  dplyr::filter(localidade =="JARDIM CATARINA")


unique(cidade_case$localidade)
unique(cidade_case$logradouro_sem_numero)
unique(cidade_case$cep)
'27253-360'

# direto via cnefe


cnef <- ipeadatalake::ler_cnefe(ano = 2022, as_data_frame = F) |>
  filter(code_muni==3304904) |> collect()


cnef_case <- cnef |>
  filter(desc_localidade == 'JARDIM CATARINA') |>
  filter( nom_tipo_seglogr == 'AVENIDA' &
            nom_titulo_seglogr == 'PADRE' &
            nom_seglogr =='VIEIRA' &
            num_adress %in% 1:5)


cidade_case_sf <- sfheaders::sf_point(
  obj = cnef_case,
  x = 'lon',
  y = 'lat',
  keep = TRUE
)
sf::st_crs(cidade_case_sf) <- 4674

mapview::mapview(cidade_case_sf, zcol='num_adress')






Existem 6 endereços de Avenida Brasil, número 7 no RJ. A MESMA AVENIDA!
cada um com cep diferente.


# cep estranho no rio de janeiro -----------------------------------------------

tudo <- geocodebr::listar_dados_cache()
tudo <- tudo[7]

dt <- arrow::open_dataset( tudo ) |>
  dplyr::filter(estado == 'RJ') |>
  dplyr::filter(municipio == "RIO DE JANEIRO") |>
  dplyr::filter(cep %in% c( "22440-035")) |>
  # dplyr::filter(cep %in% c("22620-110", "20521-470")) |>
  # dplyr::filter(localidade %in% c("LEBLON")) |>
  dplyr::collect()


dt_sf <- sfheaders::sf_point(
  obj = dt,
  x = 'lon',
  y = 'lat',
  keep = TRUE
)

sf::st_crs(dt_sf) <- 4674

mapview::mapview(dt_sf, zcol='cep')

