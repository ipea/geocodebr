# Cache de dados

O {geocodebr} está disponível em R e em Python, com funções e argumentos
equivalentes. Ao longo desta vignette, cada exemplo mostra o código em R
(à esquerda) e em Python (à direita).

## Cache de dados: baixados uma única vez

As funções
[`geocode()`](https://ipea.github.io/geocodebr/reference/geocode.md),
[`geocode_reverso()`](https://ipea.github.io/geocodebr/reference/geocode_reverso.md)
e
[`busca_por_cep()`](https://ipea.github.io/geocodebr/reference/busca_por_cep.md)
usam uma versão pré-processada e enriquecida do CNEFE, organizada em um
conjunto de tabelas de referência no formato `.parquet`. Esses dados são
baixados na primeira vez que cada função é executada e ficam salvos no
*cache* do pacote, uma pasta local na sua máquina. Como esse *cache* é
persistente entre diferentes sessões, os dados não precisam ser baixados
novamente.

Cada função baixa apenas as tabelas de que precisa. A
[`geocode_reverso()`](https://ipea.github.io/geocodebr/reference/geocode_reverso.md)
e a
[`busca_por_cep()`](https://ipea.github.io/geocodebr/reference/busca_por_cep.md)
utilizam uma única tabela, com cerca de 100 MB. Já a
[`geocode()`](https://ipea.github.io/geocodebr/reference/geocode.md)
baixa somente as tabelas necessárias para os campos de endereço
informados pelo usuário. Com todas as tabelas, o *cache* soma cerca de
1.2 GB.

O pacote inclui algumas funções que ajudam a gerenciar o *cache*:

- [`listar_pasta_cache()`](https://ipea.github.io/geocodebr/reference/listar_pasta_cache.md) -
  retorna o endereço do *cache* na sua máquina, onde os dados do CNEFE
  estão salvos;
- [`listar_dados_cache()`](https://ipea.github.io/geocodebr/reference/listar_dados_cache.md) -
  lista todos os arquivos armazenados no *cache*;
- [`definir_pasta_cache()`](https://ipea.github.io/geocodebr/reference/definir_pasta_cache.md) -
  define uma pasta personalizada para ser usada como *cache*. Essa
  configuração é persistente entre diferentes sessões;
- [`deletar_pasta_cache()`](https://ipea.github.io/geocodebr/reference/deletar_pasta_cache.md) -
  exclui a pasta de *cache*, bem como todos os arquivos que estavam
  armazenados dentro dela.

## Onde os dados estão salvos

As funções
[`listar_pasta_cache()`](https://ipea.github.io/geocodebr/reference/listar_pasta_cache.md)
e
[`listar_dados_cache()`](https://ipea.github.io/geocodebr/reference/listar_dados_cache.md)
permitem inspecionar onde fica o *cache* e quais arquivos já foram
baixados.

    R

``` r

library(geocodebr)

# pasta do cache
listar_pasta_cache()
#> [1] "/home/runner/.cache/R/geocodebr"

# arquivos salvos no cache
listar_dados_cache()
#> [1] "/home/runner/.cache/R/geocodebr/geocodebr_data_release_v0.5.0/municipio_cep_localidade.parquet"                  
#> [2] "/home/runner/.cache/R/geocodebr/geocodebr_data_release_v0.5.0/municipio_cep.parquet"                             
#> [3] "/home/runner/.cache/R/geocodebr/geocodebr_data_release_v0.5.0/municipio_localidade.parquet"                      
#> [4] "/home/runner/.cache/R/geocodebr/geocodebr_data_release_v0.5.0/municipio_logradouro_cep_localidade.parquet"       
#> [5] "/home/runner/.cache/R/geocodebr/geocodebr_data_release_v0.5.0/municipio_logradouro_localidade.parquet"           
#> [6] "/home/runner/.cache/R/geocodebr/geocodebr_data_release_v0.5.0/municipio_logradouro_numero_cep_localidade.parquet"
#> [7] "/home/runner/.cache/R/geocodebr/geocodebr_data_release_v0.5.0/municipio_logradouro_numero_localidade.parquet"    
#> [8] "/home/runner/.cache/R/geocodebr/geocodebr_data_release_v0.5.0/municipio.parquet"
```

    Python

``` python
from geocodebr import listar_pasta_cache, listar_dados_cache

# pasta do cache
listar_pasta_cache()

# arquivos salvos no cache
listar_dados_cache()
```

Por padrão, o *cache* fica na pasta de dados de usuário do sistema
operacional: no R, a pasta indicada por
`tools::R_user_dir("geocodebr", which = "cache")`; no Python, a pasta
indicada por `platformdirs.user_cache_dir("geocodebr")`. Dentro dela, os
arquivos ficam numa subpasta `geocodebr_data_release_<versão>`, com o
nome da versão dos dados do CNEFE utilizada pelo pacote. O argumento
`print_tree = TRUE` da
[`listar_dados_cache()`](https://ipea.github.io/geocodebr/reference/listar_dados_cache.md)
exibe o conteúdo do *cache* em formato de árvore.

## Definindo uma pasta de cache personalizada

A função
[`definir_pasta_cache()`](https://ipea.github.io/geocodebr/reference/definir_pasta_cache.md)
permite salvar os dados numa pasta de sua escolha, por exemplo num disco
com mais espaço livre ou numa pasta de rede compartilhada. Essa
configuração é persistente, ou seja, continua valendo nas próximas
sessões. Para voltar a usar a pasta padrão do pacote, basta passar
`path = NULL`.

    R

``` r

# define uma pasta personalizada
definir_pasta_cache(path = "D:/dados/geocodebr")

# retoma a pasta padrão do pacote
definir_pasta_cache(path = NULL)
```

    Python

``` python
from geocodebr import definir_pasta_cache

# define uma pasta personalizada
definir_pasta_cache(path="D:/dados/geocodebr")

# retoma a pasta padrão do pacote
definir_pasta_cache(path=None)
```

## Baixando os dados com antecedência

Os dados são baixados automaticamente quando necessário, mas a função
[`download_cnefe()`](https://ipea.github.io/geocodebr/reference/download_cnefe.md)
permite baixá-los com antecedência, por exemplo antes de trabalhar sem
acesso à internet. Por padrão, a função baixa `"todas"` as tabelas de
referência, mas o argumento `tabela` permite escolher apenas algumas
delas. Com `cache = FALSE`, os dados são salvos numa pasta temporária,
fora do *cache*, e serão baixados novamente a cada nova chamada.

    R

``` r

# baixa todas as tabelas
download_cnefe(verboso = FALSE)

# baixa apenas algumas tabelas
download_cnefe(
  tabela = c("municipio", "municipio_cep"),
  verboso = FALSE
)
```

    Python

``` python
from geocodebr import download_cnefe

# baixa todas as tabelas
download_cnefe(verboso=False)

# baixa apenas algumas tabelas
download_cnefe(
    tabela=["municipio", "municipio_cep"],
    verboso=False
)
```

## Apagando o cache

A função
[`deletar_pasta_cache()`](https://ipea.github.io/geocodebr/reference/deletar_pasta_cache.md)
exclui a pasta de *cache* e todos os arquivos salvos nela. Os dados
serão baixados novamente na próxima vez que uma das funções do pacote
for executada.

    R

``` r

deletar_pasta_cache()
```

    Python

``` python
from geocodebr import deletar_pasta_cache

deletar_pasta_cache()
```

> **Nota**
>
> Os dados do CNEFE usados pelo pacote são versionados. Quando uma nova
> versão do {geocodebr} passa a usar uma nova versão dos dados, eles são
> baixados novamente numa nova subpasta do *cache*, e as versões antigas
> salvas na mesma pasta são apagadas automaticamente para liberar espaço
> em disco.
