# Changelog

## geocodebr v0.6.3

Lançamento CRAN: 2026-05-24

### Correção de bugs (Bug fixes)

- Bug corrigido que agora permite usuários passarem como input tabelas
  de endereços com apenas alguns campos. Os campos de municio e unidade
  da federação continuam sendo obrigatórios. Encerra
  [\#89](https://github.com/ipea/geocodebr/issues/89) e
  [\#94](https://github.com/ipea/geocodebr/issues/94)

### Mudanças pequenas (Minor changes)

- A função
  [`geocode_reverso()`](https://ipeagit.github.io/geocodebr/reference/geocode_reverso.md)
  teve pequeno ganho de velocidade, com drástica redução no consumo de
  memória. Na amostra de 1000 pontos, o uso de memória caiu de 161MB
  para 95MB.

## geocodebr v0.6.2

Lançamento CRAN: 2026-04-14

### Correção de bugs (Bug fixes)

- Bug corrigido para garantir que o pacote utiliza apenas os dados em
  cache do data release corrente, e ignora eventuais dados de releases
  antigos que estejam na pasta.
  [Encerra](https://github.com/ipea/geocodebr/issues/90)
  [\#90](https://github.com/ipea/geocodebr/issues/90)
- A função
  [`geocode()`](https://ipeagit.github.io/geocodebr/reference/geocode.md)
  agora retorna erro informativo quando alguma coluna na tabela de input
  tem nome com algum caractere não alfanumérico, como . , ? ^ - ! ~. Não
  há problema com o barra baixa \_, como em “name_muni”. Fecha
  [issue](https://github.com/ipea/geocodebr/issues/92)
  [\#92](https://github.com/ipea/geocodebr/issues/92)
- Corrigido erro na função de
  [`geocode_reverso()`](https://ipeagit.github.io/geocodebr/reference/geocode_reverso.md)
  que impedia usar valores muito altos de `dist_max`.
  [Encerra](https://github.com/ipea/geocodebr/issues/88)
  [\#88](https://github.com/ipea/geocodebr/issues/88)
- Incluido ‘Language: pt’ na DESCRIPTION

## geocodebr v0.6.1

Lançamento CRAN: 2026-01-27

### Correção de bugs (Bug fixes)

- Essa versão corrige um erro que havia nas coordenadas co CNEFE
  utilizadas na v0.6.0.

## geocodebr v0.6.0

Lançamento CRAN: 2026-01-23

### Mudanças grandes (Major changes)

- A função
  [`geocode()`](https://ipeagit.github.io/geocodebr/reference/geocode.md)
  agora retorna o codigo do setor censitário do endereço encontrado
  quando `resultado_completo = TRUE`. Essa alteração atende parcialmente
  ao [issue](https://github.com/ipea/geocodebr/issues/66)
  [\#66](https://github.com/ipea/geocodebr/issues/66) porque ela somente
  retorna o código do setor dos casos em que o endeço encontrado está
  100% dentro de um único setor censitário. Quanto os dados do CNEFE
  correspondentes ao endereço buscado estão em mais de um setor, o
  resultado da coluna `cod_setor` é `NA`.
- Dependência do pacote agora usa enderecobr (\>= 0.5.0), que foi
  reescrito em Rust. Isso traz grandes ganhos de performance para
  processamento de bases acima de 10 milhões
- Nova atualização da da base de referência (CNEFE padronizado v0.4.0)

### Outras novidades (Other news)

- Novo co-autor do pacote: Gabriel Garcia de Almeida

## geocodebr v0.5.0

Lançamento CRAN: 2025-12-09

### Mudanças grandes (Major changes)

- Novas versões da funções
  [`geocode()`](https://ipeagit.github.io/geocodebr/reference/geocode.md),
  [`geocode_reverso()`](https://ipeagit.github.io/geocodebr/reference/geocode_reverso.md)
  e
  [`busca_por_cep()`](https://ipeagit.github.io/geocodebr/reference/busca_por_cep.md)
  são significamente mais rápidas e usam menos memória RAM. O ganho de
  eficiência é relativamente maior em consultas pequenas. Ver ganhos de
  performance no issues encerrados:
  [\#82](https://github.com/ipea/geocodebr/issues/82),
  [\#81](https://github.com/ipea/geocodebr/issues/81) e
  [\#83](https://github.com/ipea/geocodebr/issues/83)
- Por padrão, as funções agora recebem `n_cores = NULL`, e o pacote
  utiliza o número máximo de cores físicos disponíveis.
- Agora o argumento `resolver_empates` passa a ser `TRUE` como padrão.

### Mudanças pequenas (Minor changes)

- As tabelas do cnefe agora são registradas na db uma única vez.
  [Encerra issue](https://github.com/ipea/geocodebr/issues/79)
  [\#79](https://github.com/ipea/geocodebr/issues/79).
- O output da função
  [`geocode()`](https://ipeagit.github.io/geocodebr/reference/geocode.md)
  agora é apenas um `"data.frame"`, e não mais um
  `"data.table" "data.frame"`.
- A função
  [`geocode()`](https://ipeagit.github.io/geocodebr/reference/geocode.md)
  passa a ter um novo argumento `padronizar_enderecos` que indica se os
  dados de endereço de entrada devem ser padronizados. Por padrão, é
  `TRUE`. Essa padronização é essencial para uma geolocalizaçao correta.
  Alerta! Apenas utilize `padronizar_enderecos = FALSE` caso os dados de
  input já tenham sido padronizados anteriormente com
  `enderecobr::padronizar_enderecos(..., formato_estados = 'sigla', formato_numeros = 'integer')`.
  [Encerra issue](https://github.com/ipea/geocodebr/issues/68)
  [\#68](https://github.com/ipea/geocodebr/issues/68).
- Incluído o apoio do Instituto Todos pela Saúde (ITpS) no `README` e no
  arquivo `DESCRIPTION`. [Encerra
  issue](https://github.com/ipea/geocodebr/issues/71)
  [\#71](https://github.com/ipea/geocodebr/issues/71).

### Correção de bugs (Bug fixes)

- A função
  [`geocode()`](https://ipeagit.github.io/geocodebr/reference/geocode.md)
  agora é envolta com {callr}, e por isso usa muito menos memória RAM e
  não tem vazamento de memória.
  [\#48](https://github.com/ipea/geocodebr/issues/48)

## geocodebr v0.4.0

Lançamento CRAN: 2025-11-18

### Mudanças grandes (Major changes)

- A função
  [`geocode()`](https://ipeagit.github.io/geocodebr/reference/geocode.md)
  agora não aplica match probabilístico em lograouros cujo nome são só
  uma letra (e.g. RUA A, RUA B, RUA C) ou compostos só por dígitos (RUA
  1, RUA 10, RUA 20). [Encerra
  issue](https://github.com/ipea/geocodebr/issues/67)
  [\#67](https://github.com/ipea/geocodebr/issues/67). Isso diminui
  muito os casos de falso positivo no match probabilístico.
- O parâmetro `h3_res` utilizado nas funções
  [`geocode()`](https://ipeagit.github.io/geocodebr/reference/geocode.md)
  e
  [`busca_por_cep()`](https://ipeagit.github.io/geocodebr/reference/busca_por_cep.md)
  agora aceita um vetor de números indicando diferentes resoluções de
  H3. [Encerra issue](https://github.com/ipea/geocodebr/issues/72)
  [\#72](https://github.com/ipea/geocodebr/issues/72).

### Mudanças pequenas (Minor changes)

- Definição de número de `n_cores` para paralelização mais segura usando
  [parallelly](https://parallelly.futureverse.org).
- Ganhos de performance em algumas funções de match (issues
  [\#73](https://github.com/ipea/geocodebr/issues/73),
  [\#74](https://github.com/ipea/geocodebr/issues/74) e
  [\#75](https://github.com/ipea/geocodebr/issues/75)).
- Tratamento de casos de empate agora é feito interamente dentro do
  DuckDB. [Encerra issue](https://github.com/ipea/geocodebr/issues/57)
  [\#57](https://github.com/ipea/geocodebr/issues/57)
- O geocodebr não depende mais do pacote Rcpp, que antes era utilizado
  para calcular distâncias entre coordendas. Esses cálculo agora é feito
  inteiramente dentro do DuckDB.

### Novos contribuidores (New contributions)

- Pedro Milreu Cunha

## geocodebr v0.3.0

Lançamento CRAN: 2025-10-08

### Mudanças grandes (Major changes)

- Novo parâmetro `h3_res` nas funções
  [`geocode()`](https://ipeagit.github.io/geocodebr/reference/geocode.md)
  e
  [`busca_por_cep()`](https://ipeagit.github.io/geocodebr/reference/busca_por_cep.md),
  que permite o usuário inserir uma coluna no output indicando o id da
  célula H3 na resolução espacial desejada. [Encerra
  issue](https://github.com/ipea/geocodebr/issues/43)
  [\#43](https://github.com/ipea/geocodebr/issues/43).
- O output da função
  [`geocode()`](https://ipeagit.github.io/geocodebr/reference/geocode.md)
  agora inclui uma nova coluna `desvio_metros` que apresenta de forma
  intuitiva o grau de incerteza do resultado encontrado. [Encerra
  issue](https://github.com/ipea/geocodebr/issues/11)
  [\#11](https://github.com/ipea/geocodebr/issues/11).
- Nova base de dados (release `v0.3.0`). A principal mudança aqui foi a
  estratégia de agregação de coordenadas. Na versão anterior, a base
  consistia numa média simples das coordenadas dos pontos que pertenciam
  ao mesmo grupo de colunas. Na atual versão, esse cálculo é feito em
  duas etapas. Primeiro encontramos o ponto médio e calculamos sua
  distância até todos os pontos. Em seguida, descartamos aqueles pontos
  que estão acima do percentil 95% de distância, e recalculamos então
  novo ponto médio. Isso evita eventuais distorções quando há poucos
  pontos muito isolados.
- A nova base de dados (release `v0.3.0`) utiliza arquivos em formato
  `.parquet` compactados, o que diminuiu pela metade o tamanho dos
  arquivos (de `2.98` GB para `1.17` GB) e acelera o processo de
  download dos dados (embora deixa o processamento em si ligeiramente
  mais devagar).
- Os dados de cache agora são armazenados na sub-pasta
  `"geocodebr_data_release_{data_release}"`, dentro da pasta de cache
  definida pelo usuário. De agora em diante, os dados de releases
  antigos passam a ser deletados automaticamente quando há atualização
  do data release. [Encerra
  issue](https://github.com/ipea/geocodebr/issues/64)
  [\#64](https://github.com/ipea/geocodebr/issues/64). Mas os dados das
  versões anteriores `v0.2.0` devem ser apagados manualmente com a
  função
  [`deletar_pasta_cache()`](https://ipeagit.github.io/geocodebr/reference/deletar_pasta_cache.md).

## geocodebr v0.2.1

Lançamento CRAN: 2025-07-07

### Correção de bugs (Bug fixes)

- Resolvido bug que retornava erro se o input to usuario comecava o
  geocode direto a partir do match case `"pl01"`. [Encerra
  issue](https://github.com/ipea/geocodebr/issues/56)
  [\#56](https://github.com/ipea/geocodebr/issues/56).

## geocodebr v0.2.0

Lançamento CRAN: 2025-05-07

### Mudanças grandes (Major changes)

- A função
  [`geocode()`](https://ipeagit.github.io/geocodebr/reference/geocode.md)
  agora inclui busca com match probabilistico. [Encerra
  issue](https://github.com/ipea/geocodebr/issues/34)
  [\#34](https://github.com/ipea/geocodebr/issues/34).
- Nova função `buscapor_cep()`. [Encerra
  issue](https://github.com/ipea/geocodebr/issues/8)
  [\#8](https://github.com/ipea/geocodebr/issues/8).
- Nova função
  [`geocode_reverso()`](https://ipeagit.github.io/geocodebr/reference/geocode_reverso.md).
  [Encerra issue](https://github.com/ipea/geocodebr/issues/35)
  [\#35](https://github.com/ipea/geocodebr/issues/35).
- A função
  [`download_cnefe()`](https://ipeagit.github.io/geocodebr/reference/download_cnefe.md)
  agora aceita o argumento `tabela` para baixar tabelas específicas.

### Mudanças pequenas (Minor changes)

- Ajuste na solução de casos de empate mais refinada e agora detalhada
  na documentação da função
  [`geocode()`](https://ipeagit.github.io/geocodebr/reference/geocode.md).
  [Encerra issue](https://github.com/ipea/geocodebr/issues/37)
  [\#37](https://github.com/ipea/geocodebr/issues/37). O método adotado
  na solução de empates agora fica transparente na documentação da
  função
  [`geocode()`](https://ipeagit.github.io/geocodebr/reference/geocode.md).
- Nova vignette sobre a função
  [`geocode_reverso()`](https://ipeagit.github.io/geocodebr/reference/geocode_reverso.md)
- Vignette sobre *Get Started* e da função
  [`geocode()`](https://ipeagit.github.io/geocodebr/reference/geocode.md)
  reorganizadas

### Correção de bugs (Bug fixes)

- Resolvido bug que decaracterizava colunas de classe `integer64` na
  tabela de input de endereços. [Encerra
  issue](https://github.com/ipea/geocodebr/issues/40)
  [\#40](https://github.com/ipea/geocodebr/issues/40).

### Novos contribuidores (New contributions)

- Arthur Bazzolli

## geocodebr v0.1.1

Lançamento CRAN: 2025-02-17

### Correção de bugs

- Corrigido bug na organização de pastas do cache de dados. Fecha o
  [issue 29](https://github.com/ipea/geocodebr/issues/29).

## geocodebr v0.1.0

Lançamento CRAN: 2025-02-12

- Primeira versão.
