# Busca por CEP

O {geocodebr} está disponível em R e em Python, com funções e argumentos
equivalentes. Ao longo desta vignette, cada exemplo mostra o código em R
(à esquerda) e em Python (à direita).

## Busca por CEP: de CEPs para endereços e coordenadas

A função
[`busca_por_cep()`](https://ipea.github.io/geocodebr/reference/busca_por_cep.md)
permite fazer consultas de CEPs para encontrar os endereços associados a
cada CEP, junto com suas coordenadas geográficas. Essa funcionalidade
pode ser útil, por exemplo, para localizar registros administrativos que
contêm apenas o CEP, ou para verificar quais logradouros e bairros estão
cobertos por um determinado CEP.

A função recebe como *input* um vetor de CEPs (em Python, uma lista),
com ou sem hífen, e retorna uma tabela com os endereços encontrados em
cada CEP. No exemplo abaixo, buscamos dois CEPs existentes e um CEP
inexistente (`"99999-999"`).

    R

``` r

library(geocodebr)

# amostra de CEPs
ceps <- c("70390-025", "20071-001", "99999-999")

# busca por CEP
df_ceps <- busca_por_cep(
  cep = ceps,
  h3_res = 9,
  resultado_sf = FALSE,
  verboso = FALSE
)
```

    Python

``` python
from geocodebr import busca_por_cep

# amostra de CEPs
ceps = ["70390-025", "20071-001", "99999-999"]

# busca por CEP
df_ceps = busca_por_cep(
    cep=ceps,
    h3_res=9,
    resultado_gpd=False,
    verboso=False
)
```

O *output* fica como abaixo, e traz as colunas `cep`, `estado`,
`municipio`, `logradouro` e `localidade` de cada endereço encontrado,
além das coordenadas de latitude (`lat`) e longitude (`lon`).

``` r

head(df_ceps)
#>          cep estado      municipio                logradouro localidade
#>       <char> <char>         <char>                    <char>     <char>
#> 1: 20071-001     RJ RIO DE JANEIRO AVENIDA PRESIDENTE VARGAS     CENTRO
#> 2: 70390-025     DF       BRASILIA      SEPS 702 902 BLOCO A    ASA SUL
#> 3: 70390-025     DF       BRASILIA      SEPS 702 902 BLOCO B    ASA SUL
#> 4: 70390-025     DF       BRASILIA      SEPS 702 902 BLOCO C    ASA SUL
#> 5: 99999-999   <NA>           <NA>                      <NA>       <NA>
#>          lon       lat           h3_09
#>        <num>     <num>          <char>
#> 1: -43.18267 -22.90230 89a8a06a0a3ffff
#> 2: -47.89608 -15.79815 89a8c249d87ffff
#> 3: -47.89439 -15.79741 89a8c249d8fffff
#> 4: -47.89707 -15.79922 89a8c249d87ffff
#> 5:        NA        NA            <NA>
```

Cabe destacar alguns detalhes sobre o formato do *output*:

- **Um CEP pode retornar várias linhas.** Um mesmo CEP costuma cobrir
  mais de um logradouro ou localidade, e cada combinação encontrada no
  CNEFE vira uma linha do resultado. No exemplo acima, o CEP
  `"70390-025"` retorna três linhas, uma para cada bloco do mesmo
  logradouro;
- **CEPs não encontrados são mantidos no resultado.** Os CEPs sem
  correspondência no CNEFE são retornados com a coluna `cep` preenchida
  e todas as demais colunas `NA`, para que o usuário possa identificar
  quais CEPs não foram encontrados. Caso nenhum dos CEPs de *input* seja
  encontrado, a função retorna um erro;
- **CEPs duplicados são removidos.** Antes da busca, os CEPs são
  padronizados e os valores repetidos ou vazios são descartados. Por
  isso, o número de linhas do resultado não guarda relação direta com o
  número de CEPs de *input*.

Assim como na função
[`geocode()`](https://ipea.github.io/geocodebr/reference/geocode.md),
cabe destacar aqui outros dois argumentos da função
[`busca_por_cep()`](https://ipea.github.io/geocodebr/reference/busca_por_cep.md):

- `h3_res`: que permite o usuário inserir uma coluna no output indicando
  o id da célula H3 na resolução espacial desejada. Detalhes sobre as
  resoluções disponíveis na [documentação do
  H3](https://h3geo.org/docs/core-library/restable/);
- `resultado_sf`: quando `TRUE`, o output é retornado como um objeto
  espacial de classe `sf` simple feature. Em Python, o argumento
  equivalente é `resultado_gpd`, que retorna um `geopandas.GeoDataFrame`
  (requer `pip install geocodebr[geo]`). Sem ele, o Python retorna um
  `pyarrow.Table`.

As coordenadas espaciais do resultado usam o sistema de referência
SIRGAS2000 (EPSG 4674), padrão adotado pelo IBGE em todo o Brasil.

> **Nota**
>
> A função
> [`busca_por_cep()`](https://ipea.github.io/geocodebr/reference/busca_por_cep.md)
> requer que os dados do CNEFE estejam armazenados localmente. A
> primeira vez que a função é executada, ela baixa os dados do CNEFE e
> salva em um cache local na sua máquina. A
> [`busca_por_cep()`](https://ipea.github.io/geocodebr/reference/busca_por_cep.md)
> utiliza uma única tabela do CNEFE, com cerca de 100 MB, a mesma
> utilizada pela
> [`geocode_reverso()`](https://ipea.github.io/geocodebr/reference/geocode_reverso.md).
> Esses dados são salvos de forma persistente, logo eles são baixados
> uma única vez. Mais informações sobre o cache de dados
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
