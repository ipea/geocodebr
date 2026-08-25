# Geocode reverso

## Geolocalização reversa: de coordenadas espaciais para endereços

A função
[`geocode_reverso()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode_reverso.md)
permite fazer geolocalização reversa, isto é, a partir de um conjunto de
coordenadas geográficas, encontrar os endereços correspondentes ou
próximos. Essa funcionalidade pode ser útil, por exemplo, para
identificar endereços próximos a pontos de interesse, como escolas,
hospitais, ou locais de acidentes.

A função recebe como *input* um objeto espacial `sf` com geometria do
tipo `POINT`. O resultado é um *data frame* com o endereço encontrado
mais próximo de cada ponto de *input*, onde a coluna
`"distancia_metros"` indica a distância entre coordenadas originais e os
endereços encontrados.

``` r

library(geocodebr)
library(sf)
#> Linking to GEOS 3.10.2, GDAL 3.4.1, PROJ 8.2.1; sf_use_s2() is TRUE

# amostra de pontos espaciais
pontos <- readRDS(
  system.file("extdata/pontos.rds", package = "geocodebr")
)

pontos <- pontos[1:20,]

# geocode reverso
df_enderecos <- geocodebr::geocode_reverso(
  pontos = pontos,
  dist_max = 1000,
  verboso = FALSE,
  n_cores = 1
)

head(df_enderecos)
#> Simple feature collection with 6 features and 7 fields
#> Geometry type: POINT
#> Dimension:     XY
#> Bounding box:  xmin: -40.7334 ymin: -20.44142 xmax: -39.92601 ymax: -18.69095
#> Geodetic CRS:  SIRGAS 2000
#> # A tibble: 6 × 8
#>      id estado municipio  logradouro           cep   localidade distancia_metros
#>   <int> <chr>  <chr>      <chr>                <chr> <chr>                 <dbl>
#> 1     1 ES     COLATINA   CORREGO BOA VISTA    2970… SAO JOAO …             50.2
#> 2     6 ES     VIANA      ESTRADA BOM JESUS    2913… BOM JESUS…            606. 
#> 3     7 ES     COLATINA   FAZENDA SANTA LUCIA… 2970… FAZENDA S…            483. 
#> 4     8 ES     SAO MATEUS FAZENDA ESCADINHA    2994… ESCADINHA             540. 
#> 5    11 ES     SAO MATEUS RODOVIA ES 381       2994… KM 13                 239. 
#> 6    12 ES     SAO MATEUS LADEIRA DE DONA ANA  2994… KM 28                 773. 
#> # ℹ 1 more variable: geometry <POINT [°]>
```

Por padrão, a função busca pelo endereço mais próximo num raio
aproximado de 1000 metros. No entanto, o usuário pode ajustar esse valor
usando o parâmetro `dist_max` para definir a distância máxima (em
metros) de busca. Se um ponto de *input* não tiver nenhum endereço
próximo dentro do raio de busca, o ponto não é incluído no *output*.

**Nota:** A função
[`geocode_reverso()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode_reverso.md)
requer que os dados do CNEFE estejam armazenados localmente. A primeita
vez que a função é executada, ela baixa os dados do CNEFE e salva em um
cache local na sua máquina. No total, esses dados somam cerca de 3 GB, o
que pode fazer com que a primeira execução da função demore. Esses
dados, no entanto, são salvos de forma persistente, logo eles são
baixados uma única vez. Mais informações sobre o cache de dados
[aqui](https://ipea.github.io/geocodebr/articles/geocodebr.html#cache-de-dados).
