# Update input_padrao_db to remove observations previously matched

Update input_padrao_db to remove observations previously matched

## Uso

``` r
update_input_db(
  con,
  update_tb = "input_padrao_db",
  reference_tb,
  match_type = NULL
)
```

## Argumentos

- con:

  A db connection

- update_tb:

  String. Name of a table to be updated in con

- reference_tb:

  A table written in con used as reference

- match_type:

  String. Se informado, apaga apenas os ids inseridos em `reference_tb`
  com esse `tipo_resultado` (os da etapa corrente)

## Valor

Drops observations from input_padrao_db
