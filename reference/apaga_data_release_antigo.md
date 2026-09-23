# Apaga do cache os dados de releases antigos

Detecta se a pasta de cache contem dados de releases anteriores ao
utilizado pela versao atual do pacote. Se sim, apaga **apenas** as
pastas desses releases antigos, preservando a pasta do release corrente.

## Uso

``` r
apaga_data_release_antigo()
```

## Valor

Retorna de forma invisível o caminho do diretório de cache.
