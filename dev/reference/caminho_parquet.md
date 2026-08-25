# Caminho de um parquet do CNEFE dentro da pasta de cache

Monta o caminho do arquivo `.parquet` de uma tabela de referência do
CNEFE dentro da pasta do release corrente. Centraliza a construção desse
caminho.

## Uso

``` r
caminho_parquet(nome_tabela, pasta_dados = listar_pasta_cache())
```

## Argumentos

- nome_tabela:

  Uma string. O nome da tabela de referência, sem a extensão, e.g.
  `"municipio_logradouro_cep_localidade"`.

- pasta_dados:

  Uma string. A pasta onde os dados do CNEFE foram baixados, tal como
  devolvida por
  [`download_cnefe()`](https://ipeagit.github.io/geocodebr/dev/reference/download_cnefe.md).
  Com `cache = FALSE` essa pasta é um diretório temporário, e não a
  pasta de cache — por isso ela precisa ser informada, e não
  redescoberta aqui.

## Valor

Uma string com o caminho do arquivo. O arquivo não precisa existir.
