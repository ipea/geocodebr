# Define um diretório de cache para o geocodebr

Define um diretório de cache para os dados do geocodebr. Essa
configuração é persistente entre sessões do R.

## Uso

``` r
definir_pasta_cache(path, verboso = TRUE)
```

## Argumentos

- path:

  Uma string. O caminho para o diretório usado para armazenar os dados
  em cache. Se `NULL`, o pacote usará um diretório versionado salvo
  dentro do diretório retornado por
  [`tools::R_user_dir()`](https://rdrr.io/r/tools/userdir.html).

- verboso:

  Um valor lógico. Indica se barras de progresso e mensagens devem ser
  exibidas durante o download dos dados do CNEFE e a geocodificação dos
  endereços. O padrão é `TRUE`.

## Valor

Retorna de forma invisível o caminho do diretório de cache.

## Exemplos

``` r
definir_pasta_cache(tempdir())
#> ℹ Definido como pasta de cache /tmp/Rtmp9Ov1Gp.

# retoma pasta padrão do pacote
definir_pasta_cache( path = NULL)
#> ℹ Definido como pasta de cache /home/runner/.cache/R/geocodebr.
```
