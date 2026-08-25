# Introdução ao geocodebr

Geolocalização refere-se ao ato de encontrar um ponto no espaço,
geralmente representado por um par de coordenadas, a partir de um
determinado endereço. O **geocodebr** permite geolocalizar endereços
brasileiros de forma simples e eficiente e sem limite de número de
consultas, a partir de dados públicos de endereços do Brasil. A
principal base de referência é o Cadastro Nacional de Endereços para
Fins Estatísticos (CNEFE), um conjunto de dados coletado e
[publicado](https://www.ibge.gov.br/estatisticas/sociais/populacao/38734-cadastro-nacional-de-enderecos-para-fins-estatisticos.html)
pelo Instituto Brasileiro de Geografia e Estatística (IBGE) que contém
os endereços de mais de 110 milhões de domicílios e estabelecimentos do
país.

## Instalação

A versão estável do pacote pode ser baixada do CRAN com o comando a
seguir:

``` r

install.packages("geocodebr")
```

Caso prefira, a versão em desenvolvimento:

``` r

# install.packages("remotes")
remotes::install_github("ipea/geocodebr")
```

## Utilização

O **{geocodebr}** possui três funções principais para geolocalização de
dados:

1.  [`geocode()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode.md)
2.  [`geocode_reverso()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode_reverso.md)
3.  [`busca_por_cep()`](https://ipeagit.github.io/geocodebr/dev/reference/busca_por_cep.md)

### 1. Geolocalização: de endereços para coordenadas espaciais

Uma vez que você possui uma tabela de dados (`data.frame`) com endereços
no Brasil, a geolocalização desses dados pode ser feita em apenas dois
passos:

1.  O primeiro passo é usar a função
    [`definir_campos()`](https://ipeagit.github.io/geocodebr/dev/reference/definir_campos.md)
    para indicar os nomes das colunas no seu `data.frame` que
    correspondem a cada campo dos endereços.
2.  O segundo passo é usar a função
    [`geocode()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode.md)
    para encontrar as coordenadas geográficas dos endereços de input.

``` r

library(geocodebr)
library(sf)
#> Linking to GEOS 3.10.2, GDAL 3.4.1, PROJ 8.2.1; sf_use_s2() is TRUE

# carregando uma amostra de dados
input_df <- read.csv(system.file("extdata/small_sample.csv", package = "geocodebr"))

# Primeiro passo: inidicar o nome das colunas com cada campo dos enderecos
campos <- geocodebr::definir_campos(
  logradouro = "nm_logradouro",
  numero = "Numero",
  cep = "Cep",
  localidade = "Bairro",
  municipio = "nm_municipio",
  estado = "nm_uf"
)

# Segundo passo: geolocalizar
df <- geocodebr::geocode(
  enderecos = input_df,
  campos_endereco = campos,
  resultado_completo = FALSE,
  resolver_empates = FALSE,
  h3_res = NULL,
  resultado_sf = FALSE,
  verboso = FALSE,
  cache = TRUE,
  n_cores = 1
)
#> Warning message:
#> Foram encontrados 3 casos de empate. Estes casos foram marcados com valor
#> `TRUE` na coluna 'empate', e podem ser inspecionados na coluna
#> 'endereco_encontrado'. Alternativamente, use `resolver_empates = TRUE` para que
#> o pacote lide com os empates automaticamente. Ver documentação da função. 
#> 
```

**Nota:** A função
[`geocode()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode.md)
requer que os dados do CNEFE estejam armazenados localmente. A primeita
vez que a função é executada, ela baixa os dados do CNEFE e salva em um
cache local na sua máquina. No total, esses dados somam cerca de 1.4 GB,
o que pode fazer com que a primeira execução da função demore. Esses
dados, no entanto, são salvos de forma persistente, logo eles são
baixados uma única vez. Ver abaixo mais informações sobre o cache de
dados.

Os resultados do **{geocodebr}** são classificados em seis categorias
gerais de `precisao`, dependendo do nível de exatidão com que cada
endereço de input foi encontrado nos dados do CNEFE. s resultados trazem
ainda uma estimativa da incerteza da localização encontrado como um
`desvio_metros`. Para mais informações, consulte a documentação da
função ou a [**vignette
“geocode”**](https://ipea.github.io/geocodebr/articles/geocode.html).

### 2. Geolocalização reversa: de coordenadas espaciais para endereços

A função
[`geocode_reverso()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode_reverso.md),
por sua vez, permite a geolocalização reversa, ou seja, a busca de
endereços próximos a um conjunto de coordenadas geográficas. Mais
detalhes na [**vignette
“geocode”**](https://ipea.github.io/geocodebr/articles/geocode_reverso.html).

``` r

# amostra de pontos espaciais
pontos <- readRDS(
  system.file("extdata/pontos.rds", package = "geocodebr")
)

# seleciona somente os primeiros 20 pontos
pontos <- pontos[1:20,]

# geocode reverso
df_enderecos <- geocodebr::geocode_reverso(
  pontos = pontos,
  dist_max = 1000,
  verboso = FALSE,
  n_cores = 1
)
```

### 3. Busca por CEPs

Por fim, a função
[`busca_por_cep()`](https://ipeagit.github.io/geocodebr/dev/reference/busca_por_cep.md)
permite fazer consultas de CEPs para encontrar endereços associados a
cada CEP. A função recebe um vetor de CEPs e retorna um `data.frame` com
os endereços e as coordenadas geográficas de cada CEP. O parâmetro
`h3_res` pode ser utilizado para incluir no output o id das células H3
na resolução espacial desejada.

``` r

# amostra de CEPs
ceps <- c("70390-025", "20071-001")

df_ceps <- geocodebr::busca_por_cep(
  cep = ceps,
  h3_res = 9,
  resultado_sf = FALSE,
  verboso = FALSE
)
```

## Cache de dados

Como comentado anteriormente, os dados do CNEFE são baixados na primeira
vez que a
[`geocode()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode.md)
é executada. Esses dados ficam salvos no *cache* do pacote e não
precisam ser baixados novamente. O pacote inclui algumas funções que
ajudam a gerenciar o *cache*:

- [`listar_pasta_cache()`](https://ipeagit.github.io/geocodebr/dev/reference/listar_pasta_cache.md) -
  retorna o endereço do *cache* na sua máquina, onde os dados do CNEFE
  estão salvos;
- [`definir_pasta_cache()`](https://ipeagit.github.io/geocodebr/dev/reference/definir_pasta_cache.md) -
  define uma pasta personalizada para ser usada como *cache*. Essa
  configuração é persistente entre diferentes sessões do R;
- [`listar_dados_cache()`](https://ipeagit.github.io/geocodebr/dev/reference/listar_dados_cache.md) -
  lista todos os arquivos armazenados no *cache*;
- [`deletar_pasta_cache()`](https://ipeagit.github.io/geocodebr/dev/reference/deletar_pasta_cache.md) -
  exclui a pasta de *cache*, bem como todos os arquivos que estavam
  armazenados dentro dela.

Após rodar o código desta *vignette*, é provável que o seu *cache*
esteja configurado como a seguir:

``` r

geocodebr::listar_pasta_cache()
#> [1] "/home/runner/.cache/R/geocodebr"

geocodebr::listar_dados_cache()
#> [1] "/home/runner/.cache/R/geocodebr/geocodebr_data_release_v0.4.1/municipio_cep_localidade.parquet"                  
#> [2] "/home/runner/.cache/R/geocodebr/geocodebr_data_release_v0.4.1/municipio_cep.parquet"                             
#> [3] "/home/runner/.cache/R/geocodebr/geocodebr_data_release_v0.4.1/municipio_localidade.parquet"                      
#> [4] "/home/runner/.cache/R/geocodebr/geocodebr_data_release_v0.4.1/municipio_logradouro_cep_localidade.parquet"       
#> [5] "/home/runner/.cache/R/geocodebr/geocodebr_data_release_v0.4.1/municipio_logradouro_localidade.parquet"           
#> [6] "/home/runner/.cache/R/geocodebr/geocodebr_data_release_v0.4.1/municipio_logradouro_numero_cep_localidade.parquet"
#> [7] "/home/runner/.cache/R/geocodebr/geocodebr_data_release_v0.4.1/municipio_logradouro_numero_localidade.parquet"    
#> [8] "/home/runner/.cache/R/geocodebr/geocodebr_data_release_v0.4.1/municipio.parquet"
```
