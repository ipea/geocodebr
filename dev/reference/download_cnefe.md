# Faz download dos dados do CNEFE

Faz o download de uma versão pre-processada e enriquecida do CNEFE
(Cadastro Nacional de Endereços para Fins Estatísticos) que foi criada
para o uso deste pacote.

## Uso

``` r
download_cnefe(tabela = "todas", verboso = TRUE, cache = TRUE)
```

## Argumentos

- tabela:

  Nome de uma ou mais tabelas a serem baixadas. Pode ser uma única
  string ou um vetor de caracteres. Por padrão, baixa `"todas"` as
  tabelas de referência do CNEFE (não pode ser combinado com outros
  nomes). Os nomes válidos são os mesmos nomes-base dos arquivos
  `.parquet` distribuídos pelo pacote (e.g. `"municipio_cep"`,
  `"municipio_logradouro_numero_cep_localidade"`).

- verboso:

  Um valor lógico. Indica se barras de progresso e mensagens devem ser
  exibidas durante o download dos dados do CNEFE e a geocodificação dos
  endereços. O padrão é `TRUE`.

- cache:

  Um valor lógico. Indica se os dados do CNEFE devem ser salvos ou lidos
  do cache, reduzindo o tempo de processamento em chamadas futuras. O
  padrão é `TRUE`. Quando `FALSE`, os dados do CNEFE são baixados para
  um diretório temporário.

## Valor

Retorna o caminho para o diretório onde os dados foram salvos.

## Exemplos

``` r
download_cnefe(verboso = FALSE)
download_cnefe(tabela = c("municipio", "municipio_cep"), verboso = FALSE)
```
