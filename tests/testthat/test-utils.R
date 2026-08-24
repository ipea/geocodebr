# get_reference_table ---------------------------------------------------------

# todos os match_types que get_key_cols() conhece
match_types_conhecidos <- c(
  "dn01", "dn02", "dn03", "dn04",
  "da01", "da02", "da03", "da04",
  "pn01", "pn02", "pn03", "pn04",
  "pa01", "pa02", "pa03", "pa04",
  "dl01", "dl02", "dl03", "dl04",
  "pl01", "pl02", "pl03", "pl04",
  "dc01", "dc02", "db01", "dm01"
)

test_that("get_reference_table cobre todos os match_types", {
  lookup <- geocodebr:::reference_table_by_match_type

  expect_setequal(names(lookup), match_types_conhecidos)
  expect_false(any(duplicated(names(lookup))))

  # nenhuma etapa do laco pode ficar sem tabela de referencia
  expect_true(all(geocodebr:::all_possible_match_types %in% names(lookup)))

  # todo match_type conhecido devolve uma unica string, sem nome
  for (mt in match_types_conhecidos) {
    tb <- geocodebr:::get_reference_table(mt)
    expect_type(tb, "character")
    expect_length(tb, 1)
    expect_null(names(tb))
  }

  # match_type desconhecido falha de forma explicita
  expect_error(geocodebr:::get_reference_table("zz99"))
})

test_that("get_reference_table mantem o mapeamento historico", {
  # mapeamento congelado: mexer aqui muda quais dados do CNEFE cada etapa do
  # matching le, e portanto as coordenadas devolvidas ao usuario
  esperado <- c(
    dn01 = "municipio_logradouro_numero_cep_localidade",
    dn02 = "municipio_logradouro_numero_cep_localidade",
    dn03 = "municipio_logradouro_numero_cep_localidade",
    dn04 = "municipio_logradouro_numero_localidade",
    da01 = "municipio_logradouro_numero_cep_localidade",
    da02 = "municipio_logradouro_numero_cep_localidade",
    da03 = "municipio_logradouro_numero_localidade",
    da04 = "municipio_logradouro_numero_localidade",
    pn01 = "municipio_logradouro_numero_cep_localidade",
    pn02 = "municipio_logradouro_numero_cep_localidade",
    pn03 = "municipio_logradouro_numero_cep_localidade",
    pn04 = "municipio_logradouro_numero",
    pa01 = "municipio_logradouro_numero_cep_localidade",
    pa02 = "municipio_logradouro_numero_cep_localidade",
    pa03 = "municipio_logradouro_numero_localidade",
    pa04 = "municipio_logradouro_numero",
    dl01 = "municipio_logradouro_cep_localidade",
    dl02 = "municipio_logradouro_cep_localidade",
    dl03 = "municipio_logradouro_cep_localidade",
    dl04 = "municipio_logradouro_localidade",
    pl01 = "municipio_logradouro_cep_localidade",
    pl02 = "municipio_logradouro_cep_localidade",
    pl03 = "municipio_logradouro_cep_localidade",
    pl04 = "municipio_logradouro",
    dc01 = "municipio_cep_localidade",
    dc02 = "municipio_cep",
    db01 = "municipio_localidade",
    dm01 = "municipio"
  )

  obtido <- vapply(
    names(esperado),
    geocodebr:::get_reference_table,
    character(1)
  )

  expect_identical(obtido, esperado)
})

test_that("as etapas ativas so leem tabelas que o pacote baixa", {
  # as 8 tabelas listadas em `all_files`, dentro de download_cnefe()
  tabelas_distribuidas <- c(
    "municipio",
    "municipio_cep",
    "municipio_cep_localidade",
    "municipio_localidade",
    "municipio_logradouro_cep_localidade",
    "municipio_logradouro_localidade",
    "municipio_logradouro_numero_cep_localidade",
    "municipio_logradouro_numero_localidade"
  )

  usadas <- unique(vapply(
    geocodebr:::all_possible_match_types,
    geocodebr:::get_reference_table,
    character(1)
  ))

  # pn04, pa04 e pl04 apontam para tabelas que nao sao distribuidas, e por isso
  # estao fora de all_possible_match_types. Reativar uma delas exige acrescentar
  # a tabela correspondente ao download
  expect_true(all(usadas %in% tabelas_distribuidas))
})
