
<!-- README.md is generated from README.Rmd. Please edit that file -->

# geocodebr: Geolocalização de Endereços Brasileiros <img align="right" src="man/figures/logo.svg" alt="" width="180">

O **{geocodebr}** é um pacote computacional para geolocalização de
endereços Brasileiros. O pacote oferece uma maneira simples e eficiente
de geolocalizar dados sem limite de número de consultas. O pacote é
baseado em conjuntos de dados espaciais abertos de endereços
brasileiros, utilizando como fonte principal o Cadastro Nacional de
Endereços para Fins Estatísticos (CNEFE). O CNEFE é
[publicado](https://www.ibge.gov.br/estatisticas/sociais/populacao/38734-cadastro-nacional-de-enderecos-para-fins-estatisticos.html)
pelo Instituto Brasileiro de Geografia e Estatística (IBGE). Atualmente,
o pacote está disponível em **R** e em **Python**.

| R | Python | Repo |
|----|----|----|
| [![CRAN status](https://www.r-pkg.org/badges/version/geocodebr)](https://CRAN.R-project.org/package=geocodebr) <br /> [![CRAN/METACRAN Total downloads](https://cranlogs.r-pkg.org/badges/grand-total/geocodebr?color=blue)](https://CRAN.R-project.org/package=geocodebr) <br /> [![r-check](https://github.com/ipea/geocodebr/workflows/check/badge.svg)](https://github.com/ipea/geocodebr/actions) <br /> [![Codecov test coverage](https://codecov.io/gh/ipea/geocodebr/branch/main/graph/badge.svg?flag=r)](https://app.codecov.io/gh/ipea/geocodebr/tree/main?flags%5B0%5D=r) <br /> [![Lifecycle: experimental](https://lifecycle.r-lib.org/articles/figures/lifecycle-experimental.svg)](https://lifecycle.r-lib.org/articles/stages.html) | [![PyPI version](https://badge.fury.io/py/geocodebr.svg)](https://badge.fury.io/py/geocodebr) <br /> [![Downloads](https://static.pepy.tech/badge/geocodebr)](https://pepy.tech/project/geocodebr) <br /> [![python-check](https://github.com/ipea/geocodebr/actions/workflows/python-check.yaml/badge.svg)](https://github.com/ipea/geocodebr/actions/workflows/python-check.yaml) <br /> [![python-r-parity](https://github.com/ipea/geocodebr/actions/workflows/python-parity.yaml/badge.svg)](https://github.com/ipea/geocodebr/actions/workflows/python-parity.yaml) <br /> [![Codecov test coverage](https://codecov.io/gh/ipea/geocodebr/branch/main/graph/badge.svg?flag=python)](https://app.codecov.io/gh/ipea/geocodebr/tree/main?flags%5B0%5D=python) <br /> [![Lifecycle: experimental](https://lifecycle.r-lib.org/articles/figures/lifecycle-experimental.svg)](https://lifecycle.r-lib.org/articles/stages.html) | <img alt="GitHub stars" src="https://img.shields.io/github/stars/ipea/geocodebr.svg?color=orange"> <br /> [![Project Status: Active](https://www.repostatus.org/badges/latest/active.svg)](https://www.repostatus.org/#active) |

## Instalação

### R

A última versão estável pode ser baixada do CRAN com o comando:

``` r
# from CRAN
install.packages("geocodebr")
```

### Python

A versão Python do **{geocodebr}** usa o mesmo conjunto de dados e os
mesmos nomes de funções do pacote R, com DuckDB como motor tabular
principal. O pacote está disponível no PyPI:

``` bash
python -m pip install geocodebr
```

Para usar `geocode_reverso()` ou receber o resultado como
`geopandas.GeoDataFrame` (`resultado_gpd=True`), instale o extra `geo`:

``` bash
python -m pip install "geocodebr[geo]"
```

## Funcionalidades

O **{geocodebr}** possui três funções principais para geolocalização de
dados:

1.  `geocode()`
    - Faz geolocalização de uma tabela de endereços para coordenadas
      espaciais. Mais detalhes e exemplos de uso na [**vignette
      “geocode”**](https://ipea.github.io/geocodebr/articles/geocode.html).
2.  `geocode_reverso()`
    - Permite a geolocalização reversa, ou seja, a busca de endereços
      próximos a um conjunto de coordenadas geográficas. Mais detalhes
      na [**vignette “geocode
      reverso”**](https://ipea.github.io/geocodebr/articles/geocode_reverso.html).
3.  `busca_por_cep()`
    - Permite fazer consultas de CEPs para encontrar endereços
      associados a cada CEP e suas coordenadas espaciais. Mais detalhes
      na [**vignette sobre “busca por
      cep”**](https://ipea.github.io/geocodebr/articles/busca_por_cep.html).

## Cache de dados

Na primeira vez que se utiliza uma das funções acima, o **{geocodebr}**
baixa e salva os dados do CNEFE em um cache local na sua máquina. No
total, esses dados somam cerca de 1.2 GB, o que pode fazer com que a
primeira execução da função demore. No entanto, estes dados são baixados
uma única vez, e salvos de forma  
persistente num *cache* local. Mais informações e funções de apoio para
gerenciar o *cache*
[**aqui**](https://ipea.github.io/geocodebr/articles/cache_dados.html).

## Nota <a href="https://www.ipea.gov.br"><img src="man/figures/ipea_logo.png" alt="IPEA" align="right" width="300"/></a>

Os dados originais do CNEFE são coletados pelo Instituto Brasileiro de
Geografia e Estatística (IBGE). O **{geocodebr}** foi desenvolvido por
uma equipe do Instituto de Pesquisa Econômica Aplicada (Ipea), e contou
com apoio do Instituto Todos pela Saúde (ITpS).

## Instituições utilizando o {geocodebr}

Além de diversos pesquisadores e empresas que utilizam o
**{geocodebr}**, o pacote também tem sido utilizado por algumas
instituições públicas no planejamento e avaliação de políticas públicas.
Entre elas:

- Instituto Brasileiro de Geografia e Estatistica (IBGE)
- Banco Central do Brasil (BCB)
- Ministério do Desenvolvimento Social e Combate à Fome (MDS)
- Receita Federal do Brasil (RFB)

## Projetos relacionados

Existem diversos pacotes de geolocalização disponíveis, muitos dos quais
podem ser utilizados em R e em Python (listados abaixo). A maioria
dessas alternativas depende de softwares e conjuntos de dados
comerciais, geralmente impondo limites de número de consultas gratuitas.
Em contraste, as principais vantagens do **{geocodebr}** são que o
pacote: (a) é completamente gratuito, permitindo consultas ilimitadas
sem nenhum custo; (b) opera com alta velocidade e escalabilidade
eficiente, permitindo geocodificar milhões de endereços em apenas alguns
minutos, sem a necessidade de grande infraestrutura computacional.

Pacotes em R:

- [{arcgisgeocode}](https://cran.r-project.org/package=arcgisgeocode)
  and [{arcgeocoder}](https://cran.r-project.org/package=arcgeocoder):
  utiliza serviço de geocode do ArcGIS
- [{nominatimlite}](https://cran.r-project.org/package=nominatimlite):
  baseado dados do OSM
- [{photon}](https://cran.r-project.org/package=photon): baseado dados
  do OSM
- [{tidygeocoder}](https://cran.r-project.org/package=tidygeocoder): API
  para diversos servicos de geolocalização
- [{googleway}](https://cran.r-project.org/package=googleway) and
  [{mapsapi}](https://cran.r-project.org/package=mapsapi): interface
  para API do Google Maps

Pacotes em Python:

- [geopy](https://pypi.org/project/geopy/): cliente para diversos
  serviços de geocodificação (Nominatim/OSM, Google, ArcGIS, Photon
  etc.)
- [googlemaps](https://pypi.org/project/googlemaps/): interface para a
  API do Google Maps
- [ArcGIS API for Python](https://pypi.org/project/arcgis/): utiliza o
  serviço de geocodificação do ArcGIS
- [opencage](https://pypi.org/project/opencage/): cliente do serviço
  OpenCage
