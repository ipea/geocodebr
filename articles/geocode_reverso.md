# Geocode reverso

O {geocodebr} está disponível em R e em Python, com funções e argumentos
equivalentes. Ao longo desta vignette, cada exemplo mostra o código em R
(à esquerda) e em Python (à direita).

## Geolocalização reversa: de coordenadas espaciais para endereços

A função
[`geocode_reverso()`](https://ipea.github.io/geocodebr/reference/geocode_reverso.md)
permite fazer geolocalização reversa, isto é, a partir de um conjunto de
coordenadas geográficas, encontrar os endereços correspondentes ou
próximos. Essa funcionalidade pode ser útil, por exemplo, para
identificar endereços próximos a pontos de interesse, como escolas,
hospitais, ou locais de acidentes.

A função recebe como *input* um objeto espacial com geometria do tipo
`POINT` no sistema de referência SIRGAS 2000 (EPSG 4674): um objeto `sf`
em R, ou um `geopandas.GeoDataFrame` em Python (requer
`pip install geocodebr[geo]`). O resultado é uma tabela com o endereço
encontrado mais próximo de cada ponto de *input*, onde a coluna
`"distancia_metros"` indica a distância entre coordenadas originais e os
endereços encontrados.

    R

``` r

library(geocodebr)
library(sf)

# amostra de pontos espaciais
pontos <- st_as_sf(
  data.frame(
    id = 1:3,
    lon = c(-43.3523, -43.1763, -47.8825),
    lat = c(-22.8327, -22.9046, -15.7942)
  ),
  coords = c("lon", "lat"),
  crs = 4674
)

# geocode reverso
df_enderecos <- geocode_reverso(
  pontos = pontos,
  dist_max = 1000,
  verboso = FALSE
)
```

    Python

``` python
import geopandas as gpd
from geocodebr import geocode_reverso

# amostra de pontos espaciais
pontos = gpd.GeoDataFrame(
    {"id": [1, 2, 3]},
    geometry=gpd.points_from_xy(
        x=[-43.3523, -43.1763, -47.8825],
        y=[-22.8327, -22.9046, -15.7942],
    ),
    crs="EPSG:4674",
)

# geocode reverso
df_enderecos = geocode_reverso(
    pontos=pontos,
    dist_max=1000,
    verboso=False
)
```

Assim fica o output no R como `sf`. No Python fica parecido como
`GeoDataFrame`.

``` r

head(df_enderecos)
#> Simple feature collection with 3 features and 7 fields
#> Geometry type: POINT
#> Dimension:     XY
#> Bounding box:  xmin: -47.8825 ymin: -22.9046 xmax: -43.1763 ymax: -15.7942
#> Geodetic CRS:  SIRGAS 2000
#> # A tibble: 3 × 8
#>      id estado municipio      logradouro       cep   localidade distancia_metros
#>   <int> <chr>  <chr>          <chr>            <chr> <chr>                 <dbl>
#> 1     1 RJ     RIO DE JANEIRO RUA PROFESSOR V… 2151… COELHO NE…            164. 
#> 2     2 RJ     RIO DE JANEIRO RUA SETE DE SET… 2005… CENTRO                 38.0
#> 3     3 DF     BRASILIA       SCN RODOVIARIA … 7008… ZONA CIVI…             55.7
#> # ℹ 1 more variable: geometry <POINT [°]>
```

Por padrão, a função busca pelo endereço mais próximo num raio
aproximado de 1000 metros. No entanto, o usuário pode ajustar esse valor
usando o parâmetro `dist_max` para definir a distância máxima (em
metros) de busca. Se um ponto de *input* não tiver nenhum endereço
próximo dentro do raio de busca, o ponto não é incluído no *output*.

> **Nota**
>
> A função
> [`geocode_reverso()`](https://ipea.github.io/geocodebr/reference/geocode_reverso.md)
> requer que os dados do CNEFE estejam armazenados localmente. A
> primeira vez que a função é executada, ela baixa os dados do CNEFE e
> salva em um cache local na sua máquina. A
> [`geocode_reverso()`](https://ipea.github.io/geocodebr/reference/geocode_reverso.md)
> utiliza uma única tabela do CNEFE, com cerca de 100 MB. Esses dados
> são salvos de forma persistente, logo eles são baixados uma única vez.
> Mais informações sobre o cache de dados
> [aqui](https://ipea.github.io/geocodebr/articles/geocodebr.html#cache-de-dados).

## Utilização em Python

A versão Python do {geocodebr} segue a mesma dinâmica de uso do pacote
R, com os mesmos nomes de funções em português. As funções retornam, por
padrão, um `pyarrow.Table` (convertível para `pandas` com
`.to_pandas()`), ou um `geopandas.GeoDataFrame` no CRS SIRGAS 2000 (EPSG
4674) com `resultado_gpd = TRUE`:

Mais detalhes e exemplos na documentação completa da versão
[Python](https://github.com/ipea/geocodebr/blob/main/python-package/README.md).

> **Nota**
>
> Mais detalhes e exemplos na documentação completa da versão
> [Python](https://github.com/ipea/geocodebr/blob/main/python-package/README.md).
