# Obtém a pasta de cache usado no geocodebr

Obtém o caminho da pasta utilizada para armazenar em cache os dados do
geocodebr. Útil para inspecionar a pasta configurada com
[`definir_pasta_cache()`](https://ipea.github.io/geocodebr/dev/reference/definir_pasta_cache.md)
em uma sessão anterior do R. Retorna a pasta de cache padrão caso
nenhuma pasta personalizado tenha sido configurada anteriormente.

## Uso

``` r
listar_pasta_cache()
```

## Valor

O caminho da pasta de cache.

## Exemplos

``` r
listar_pasta_cache()
#> [1] "/home/runner/.cache/R/geocodebr"
```
