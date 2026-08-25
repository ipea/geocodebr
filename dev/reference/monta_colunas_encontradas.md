# Monta as colunas `*_encontrado` da query de match

Monta `logradouro_encontrado` (sempre presente quando `key_cols` inclui
`'logradouro'`, independente de `resultado_completo`) e, quando
`resultado_completo = TRUE`, as demais colunas de `key_cols` e
`cod_setor`. Usada pelas quatro funcoes de match (`match_cases()`,
`match_cases_probabilistic()`, `match_weighted_cases()`,
`match_weighted_cases_probabilistic()`) para nao repetir a mesma logica
de `glue()`/[`gsub()`](https://rdrr.io/r/base/grep.html) quatro vezes.

## Uso

``` r
monta_colunas_encontradas(
  y,
  key_cols,
  resultado_completo,
  colunas_encontradas = "",
  additional_cols = "",
  agregado = FALSE,
  ordem_first = NULL
)
```

## Argumentos

- y:

  String. Nome da tabela de referencia do CNEFE (`cnefe_table_name` em
  cada `match_*()`), usada para qualificar as colunas nas expressoes do
  `SELECT` (ex.: `"municipio_cep.cep"`).

- key_cols:

  Vetor de caracteres com as colunas-chave do `match_type` corrente
  (retorno de `get_key_cols()`), ja sem `'numero'`.

- resultado_completo:

  Logico. Se `FALSE`, so `logradouro_encontrado` (quando `'logradouro'`
  esta em `key_cols`) e acrescentada; as demais colunas ficam de fora.

- colunas_encontradas:

  String. Fragmento inicial da lista de nomes de coluna (para o
  `INSERT INTO ... (...)`), ao qual esta funcao acrescenta os seus
  proprios nomes. Permite ao chamador injetar uma coluna extra antes de
  entrar aqui – ex.: `similaridade_logradouro` em
  `match_cases_probabilistic()`, que e condicional a
  `resultado_completo` mas nao faz parte de `key_cols`. Por padrao `""`.

- additional_cols:

  String. Fragmento inicial da lista de expressoes do `SELECT`,
  equivalente a `colunas_encontradas` mas do lado das expressoes (ex.:
  `"y.cep AS cep_encontrado"`). Por padrao `""`.

- agregado:

  Logico. Se `TRUE`, cada coluna (inclusive `logradouro_encontrado` e
  `cod_setor`) e embrulhada em `FIRST(... ordem_first)` em vez do
  `SELECT` direto – usado na segunda parte da query (agregada por
  `GROUP BY`) de `match_weighted_cases()` e
  `match_weighted_cases_probabilistic()`. Por padrao `FALSE`.

- ordem_first:

  String com a clausula `ORDER BY` usada dentro de cada `FIRST(...)`
  quando `agregado = TRUE` (ver `ordem_first` definido em
  `match_weighted_cases()`/`match_weighted_cases_probabilistic()`).
  Obrigatorio se `agregado = TRUE`; ignorado caso contrario. Por padrao
  `NULL`.

## Valor

Uma lista com tres elementos:

- `colunas_encontradas`: string com a lista de nomes de coluna completa,
  pronta para o `INSERT INTO output_db (...)`.

- `additional_cols`: string com a lista de expressoes completa, pronta
  para o `SELECT` da query de match.

- `tem_logradouro`: logico, se `'logradouro'` estava em `key_cols`.
