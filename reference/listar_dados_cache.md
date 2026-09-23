# Listar dados em cache

Lista os dados salvos localmente na pasta de cache

## Uso

``` r
listar_dados_cache(print_tree = FALSE)
```

## Argumentos

- print_tree:

  Um valor lógico. Indica se o conteúdo da pasta de cache deve ser
  exibido em um formato de árvore. O padrão é `FALSE`.

## Valor

O caminho para os arquivos em cache

## Exemplos

``` r
listar_dados_cache()
#> [1] "/home/runner/.cache/R/geocodebr/geocodebr_data_release_v0.5.0/municipio.parquet"                                 
#> [2] "/home/runner/.cache/R/geocodebr/geocodebr_data_release_v0.5.0/municipio_cep.parquet"                             
#> [3] "/home/runner/.cache/R/geocodebr/geocodebr_data_release_v0.5.0/municipio_cep_localidade.parquet"                  
#> [4] "/home/runner/.cache/R/geocodebr/geocodebr_data_release_v0.5.0/municipio_localidade.parquet"                      
#> [5] "/home/runner/.cache/R/geocodebr/geocodebr_data_release_v0.5.0/municipio_logradouro_cep_localidade.parquet"       
#> [6] "/home/runner/.cache/R/geocodebr/geocodebr_data_release_v0.5.0/municipio_logradouro_localidade.parquet"           
#> [7] "/home/runner/.cache/R/geocodebr/geocodebr_data_release_v0.5.0/municipio_logradouro_numero_cep_localidade.parquet"
#> [8] "/home/runner/.cache/R/geocodebr/geocodebr_data_release_v0.5.0/municipio_logradouro_numero_localidade.parquet"    

listar_dados_cache(print_tree = TRUE)
#> /home/runner/.cache/R/geocodebr
#> └── geocodebr_data_release_v0.5.0
#>     ├── municipio.parquet
#>     ├── municipio_cep.parquet
#>     ├── municipio_cep_localidade.parquet
#>     ├── municipio_localidade.parquet
#>     ├── municipio_logradouro_cep_localidade.parquet
#>     ├── municipio_logradouro_localidade.parquet
#>     ├── municipio_logradouro_numero_cep_localidade.parquet
#>     └── municipio_logradouro_numero_localidade.parquet
```
