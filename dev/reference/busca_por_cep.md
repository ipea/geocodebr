# Busca por CEP

Busca endereços e suas coordenadas geográficas a partir de um CEP. As
coordenadas de output utilizam o sistema de coordenadas geográficas
SIRGAS 2000, EPSG 4674.

## Uso

``` r
busca_por_cep(
  cep,
  h3_res = NULL,
  resultado_sf = FALSE,
  verboso = TRUE,
  cache = TRUE
)
```

## Argumentos

- cep:

  Vetor. Um CEP ou um vetor de CEPs com 8 dígitos.

- h3_res:

  Um número que indica a resolução espacial da célula hexagonal H3 da
  localização dos pontos retornados. Também aceita um vetor de números,
  e.g. `c(8, 9)` Por padrão, é `NULL`. Detalhes sobre as resoluções
  disponíveis em <https://h3geo.org/docs/core-library/restable/>

- resultado_sf:

  Lógico. Indica se o resultado deve ser um objeto espacial da classe
  `sf`. Por padrão, é `FALSE`, e o resultado é um `data.frame` com as
  colunas `lat` e `lon`.

- verboso:

  Um valor lógico. Indica se barras de progresso e mensagens devem ser
  exibidas durante o download dos dados do CNEFE e a geocodificação dos
  endereços. O padrão é `TRUE`.

- cache:

  Um valor lógico. Indica se os dados do CNEFE devem ser salvos ou lidos
  do cache, reduzindo o tempo de processamento em chamadas futuras. O
  padrão é `TRUE`. Quando `FALSE`, os dados do CNEFE são baixados para
  um diretório temporário.

## Valor

Retorna um `data.frame` com os CEPs de input e os endereços presentes
naquele CEP com suas coordenadas geográficas de latitude (`lat`) e
longitude (`lon`). Alternativamente, o resultado pode ser um objeto
`sf`.

## Exemplos

``` r
library(geocodebr)

# amostra de CEPs
ceps <- c("70390-025", "20071-001", "99999-999")

df <- geocodebr::busca_por_cep(
  cep = ceps,
  h3_res = 10,
  verboso = TRUE
  )
#> ℹ Baixando dados do CNEFE

head(df)
#>          cep estado      municipio                logradouro localidade
#>       <char> <char>         <char>                    <char>     <char>
#> 1: 20071-001     RJ RIO DE JANEIRO AVENIDA PRESIDENTE VARGAS     CENTRO
#> 2: 70390-025     DF       BRASILIA  EDF SEPS 702 902 BLOCO A    ASA SUL
#> 3: 70390-025     DF       BRASILIA  EDF SEPS 702 902 BLOCO B    ASA SUL
#> 4: 70390-025     DF       BRASILIA  EDF SEPS 702 902 BLOCO C    ASA SUL
#> 5: 99999-999   <NA>           <NA>                      <NA>       <NA>
#>          lon       lat           h3_10
#>        <num>     <num>          <char>
#> 1: -43.18265 -22.90234 8aa8a06a0a1ffff
#> 2: -47.89608 -15.79815 8aa8c249d857fff
#> 3: -47.89439 -15.79742 8aa8c249d8e7fff
#> 4: -47.89707 -15.79922 8aa8c249d867fff
#> 5:        NA        NA            <NA>
```
