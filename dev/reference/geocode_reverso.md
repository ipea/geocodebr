# Geocode reverso de coordenadas espaciais no Brasil

Geocode reverso de coordenadas geográficas para endereços. A função
recebe um `sf data frame` com pontos e retorna o endereço mais próximo
dando uma distância máxima de busca.

## Uso

``` r
geocode_reverso(
  pontos,
  dist_max = 1000,
  verboso = TRUE,
  cache = TRUE,
  n_cores = NULL
)
```

## Argumentos

- pontos:

  Uma tabela de dados com classe espacial `sf data frame` no sistema de
  coordenadas geográficas SIRGAS 2000, EPSG 4674.

- dist_max:

  Integer. Distancia máxima aceitável (em metros) entre os pontos de
  input e o endereço Por padrão, a distância é de 1000 metros.

- verboso:

  Um valor lógico. Indica se barras de progresso e mensagens devem ser
  exibidas durante o download dos dados do CNEFE e a geocodificação dos
  endereços. O padrão é `TRUE`.

- cache:

  Um valor lógico. Indica se os dados do CNEFE devem ser salvos ou lidos
  do cache, reduzindo o tempo de processamento em chamadas futuras. O
  padrão é `TRUE`. Quando `FALSE`, os dados do CNEFE são baixados para
  um diretório temporário.

- n_cores:

  Um número. O número de núcleos de CPU a serem utilizados no
  processamento dos dados. Por padrão, `n_cores = NULL` e o pacote
  utiliza o número máximo de cores físicos disponíveis.

## Valor

Retorna o `sf data.frame` de input adicionado das colunas do endereço
encontrado. O output inclui uma coluna "distancia_metros" que indica a
distância entre o ponto de input e o endereço mais próximo encontrado.

## Exemplos

``` r
library(geocodebr)

# ler amostra de dados
pontos <- readRDS(
    system.file("extdata/pontos.rds", package = "geocodebr")
    )

pontos <- pontos[1:3,]

# geocode reverso
df_enderecos <- geocodebr::geocode_reverso(
  pontos = pontos,
  dist_max = 800,
  verboso = TRUE
  )
#> ℹ Utilizando dados do CNEFE armazenados localmente

head(df_enderecos)
#> Simple feature collection with 1 feature and 7 fields
#> Geometry type: POINT
#> Dimension:     XY
#> Bounding box:  xmin: -40.7334 ymin: -19.29416 xmax: -40.7334 ymax: -19.29416
#> Geodetic CRS:  SIRGAS 2000
#> # A tibble: 1 × 8
#>      id estado municipio logradouro        cep       localidade distancia_metros
#>   <int> <chr>  <chr>     <chr>             <chr>     <chr>                 <dbl>
#> 1     1 ES     COLATINA  CORREGO BOA VISTA 29700-005 SAO JOAO …             50.2
#> # ℹ 1 more variable: geometry <POINT [°]>
```
