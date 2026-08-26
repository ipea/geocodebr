library(geocodebr)
library(ipeadatalake)
library(dplyr)
library(data.table)
library(bench)
library(janitor)





# cad unico --------------------------------------------------------------------

get_cad_year <- function(yyyymm){

  # yyyymm = 201912
  # data de atualizacao do cadastro
  dat <- lubridate::ym(yyyymm)
  dat_limite <- dat - (24*30) # 24 meses

  cad_con <- ipeadatalake::ler_cadunico(
    data = yyyymm,
    base = 'familia',
    as_data_frame = F,
    colunas = c("co_familiar_fam", "dt_atualizacao_fam", "co_uf", "cd_ibge_cadastro",
                "no_localidade_fam", "no_tip_logradouro_fam",
                "no_tit_logradouro_fam", "no_logradouro_fam",
                "nu_logradouro_fam", "ds_complemento_fam",
                "ds_complemento_adic_fam",
                "nu_cep_logradouro_fam", "co_unidade_territorial_fam",
                "no_unidade_territorial_fam", "co_local_domic_fam")
  ) |>
    filter(cd_ibge_cadastro %in% c(2927408, 2919207)) |>  # salvador e lauro de freitas |>
    filter(dt_atualizacao_fam > dat_limite)


  # a <- tail(cad, n = 100) |> collect()

  # compose address fields
  cad <- cad_con |>
    mutate(ano = yyyymm,
          no_tip_logradouro_fam = ifelse(is.na(no_tip_logradouro_fam), '', no_tip_logradouro_fam),
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
           ano,
           abbrev_state,
           code_muni,
           logradouro,
           numero,
           cep,
           bairro) |>
    dplyr::compute() |>
    dplyr::collect()

  return(cad)
  }


todos_anos <- paste0(2012:2019, 12) |> as.numeric()



cad <- pbapply::pblapply(
  X = todos_anos,
  FUN = get_cad_year
  ) |>
  data.table::rbindlist()


cad$id <- 1:nrow(cad)

fields_cad <- geocodebr::definir_campos(
  logradouro = 'logradouro',
  numero = 'numero',
  cep = 'cep',
  localidade = 'bairro',
  municipio = 'code_muni',
  estado = 'abbrev_state'
)


bench::system_time(
  cadgeo <- geocode(
    enderecos  = cad,
    campos_endereco = fields_cad,
    n_cores = 7,
    verboso = T,
    resultado_completo = T,
    resolver_empates = T,
    resultado_sf = FALSE,
    h3_res = 9
  )
)

# 121.043 empates

nrow(cadgeo)
janitor::tabyl(cadgeo$precisao)
quantile(cadgeo$desvio_metros, probs = c(.5, .75, .8, .9, .92))
