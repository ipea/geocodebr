devtools::load_all('.')

# open input data
data_path <- system.file("extdata/large_sample.parquet", package = "geocodebr")
input_df <- arrow::read_parquet(data_path)


ncores <- 7


campos <- geocodebr::definir_campos(
  # logradouro = 'logradouro',
  # numero = 'numero',
  cep = 'cep',
  localidade = 'bairro',
  municipio = 'municipio',
  estado = 'uf'
)

input_df$logradouro <- NULL
input_df$numero <- NULL

bench::mark(iterations = 3,
  a <- geocodebr::geocode(
    enderecos = input_df,
    campos_endereco = campos,
    n_cores = 7,
    resultado_completo = F,
    verboso = T,
    resultado_sf = F,
    resolver_empates = T,
    cache = T
  )
)

#          expression    min median `itr/sec` mem_alloc `gc/sec` n_itr  n_gc total_time result memory
# streetmap 0.6.0 dev  7.10s  7.26s     0.136    5.47MB        0     5     0      36.7s <df>   <Rprofmem>
# laptop    0.6.0 CRAN  5.2s  5.53s     0.174    7.46MB        0     5     0      28.8s <df>
#1              ""    8.67s  8.86s     0.113    2.04MB   0.0565     2     1      17.7s <df>
#1              ""    8.35s  8.82s     0.115    5.43MB        0     3     0      26.1s <df>
#1        "NA_int"    6.52s  6.58s     0.152    4.18MB   0.0760     2     1      13.2s <df>
#1        "NA_int"    6.54s  6.81s     0.147    1.73MB   0.0734     2     1      13.6s <df>
1 a <- geocodebr::ge… 7.58s  7.72s     0.124    4.18MB        0     3     0      24.1s <df>
