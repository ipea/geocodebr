# Changelog

## geocodebr (development version)

### Mudanças grandes (Major changes)

- A função
  [`geocode_reverso()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode_reverso.md)
  agora usa como referência de busca a tabela
  `municipio_logradouro_cep_localidade`, o que pemite captar melhor
  casos onde não há número no logradouro.

- Nos casos de resultado encontrado com número aproximado (interpolação
  — tipos `da01` a `da04` e `pa01` a `pa03`), as colunas extras do
  output como `contagem_cnefe`, `cod_setor` e `endereco_encontrado`
  podiam vir de um ponto arbitrário entre os usados na interpolação, e
  podiam mudar entre chamadas idênticas de
  [`geocode()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode.md)
  — inclusive as coordenadas de casos de empate, que usam
  `contagem_cnefe` como critério de desempate. Agora essas colunas
  sempre vêm do ponto com número mais próximo do buscado, e o resultado
  é reprodutível entre chamadas. Como consequência, cerca de 1% dos
  endereços geocodificados a partir de `da02`/`da04`/`pa02` podem
  retornar coordenadas ligeiramente diferentes das versões anteriores do
  pacote.

### Mudanças pequenas (Minor changes)

- A função
  [`geocode()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode.md)
  agora pula, sem custo, as etapas internas de busca que dependem de um
  campo de endereço não declarado em `campos_endereco` (por exemplo, se
  input do usuário não possui as colunas `logradouro` e `numero`, o
  geocode agora faz a busca só por CEP/bairro/município). Antes, essas
  etapas eram sempre executadas e materializavam a tabela de referência
  do CNEFE correspondente mesmo sabendo de antemão que nenhum resultado
  seria encontrado. Isso traz enorme ganho de performance nesses casos.
  O resultado retornado não muda.

- A documentação da função
  [`geocode()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode.md)
  agora descreve a etapa de resolução de empates entre candidatos
  separados por menos de 300 metros, que antes não estava documentada.
  Ver a seção “Lidando com casos de empate” em
  [`?geocode`](https://ipeagit.github.io/geocodebr/dev/reference/geocode.md).

- A função
  [`geocode()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode.md)
  agora baixa só as tabelas de referência do CNEFE que as etapas ativas
  do algoritmo de fato vão usar, em vez de baixar sempre as 8 tabelas
  disponíveis. No melhor caso (geocodificação só por
  CEP/bairro/município, sem logradouro/número), o volume baixado cai de
  ~1,5 GB para ~20 MB.

- A etapa interna de tratamento de empates de
  [`geocode()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode.md)
  ficou mais eficiente: as janelas de cálculo agora rodam apenas sobre
  os casos efetivamente empatados, em vez de sobre o resultado inteiro
  (~2,4x mais rápida com `resolver_empates = TRUE`, ~5x com `FALSE`,
  medido em 1 milhão de endereços). O resultado retornado não muda.

- Com `resolver_empates = FALSE`, o output de
  [`geocode()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode.md)
  agora inclui a coluna `empate` mesmo quando
  `resultado_completo = FALSE`. Antes, os casos empatados voltavam como
  linhas duplicadas sem nenhuma coluna que permitisse identificá-los (a
  mensagem de aviso instruía a inspecionar uma coluna que não estava no
  output).

- Na resolução de empates (`resolver_empates = TRUE`), a exceção que
  protege ruas com nome de data (e.g. “Rua Quinze de Novembro”) de serem
  tratadas como logradouro ambíguo nunca era aplicada, por um erro de
  escape de regex (`\\b` chegava ao motor como barra literal). Com a
  correção, endereços dessas ruas com coordenadas candidatas a menos de
  1 km entre si passam a ser resolvidos pela média ponderada
  (comportamento documentado), em vez de descartar candidatos. A exceção
  vale apenas para o critério de nome ambíguo: candidatos a mais de 1 km
  continuam sendo desempatados pelo caso mais provável. Afeta ~14
  endereços por milhão (medido em amostra de 1M com alta incidência de
  empates).

- A lista interna de logradouros ambíguos (usada para excluir nomes
  genéricos do match probabilístico e para o desempate) enumerava “Rua
  Um” a “Rua Treze” mas pulava “Rua Quatro”. A lacuna permitia, por
  exemplo, que “Rua Quatro” casasse por similaridade com “Rua Quatorze”
  (Jaro 0,91, acima de todos os limiares do pacote). Endereços em “Rua
  Quatro” sem match exato agora caem para categorias de menor precisão
  (CEP, localidade ou município) em vez de arriscar um match
  probabilístico errado. Afeta ~26 endereços por milhão (medido na mesma
  amostra).

### Correção de bugs (Bug fixes)

- As funções
  [`geocode()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode.md),
  [`geocode_reverso()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode_reverso.md)
  e
  [`busca_por_cep()`](https://ipeagit.github.io/geocodebr/dev/reference/busca_por_cep.md)
  agora fecham a conexão com o banco DuckDB ao final da sua execução,
  inclusive quando são interrompidas por um erro no meio do caminho.
  Antes, uma interrupção deixava a conexão aberta e um arquivo
  temporário em disco, o que podia acumular recursos em usos repetidos
  ou dentro de laços.

- Bug corrigido na função
  [`geocode_reverso()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode_reverso.md),
  que agrupava os resultados por uma coluna `id` do input em vez de usar
  o seu identificador interno. Na prática, a função só funcionava quando
  a tabela de input tinha uma coluna chamada `id` com valores únicos.
  Agora o resultado independe das colunas presentes na tabela de input.

- Bug corrigido no argumento `h3_res` da função
  [`busca_por_cep()`](https://ipeagit.github.io/geocodebr/dev/reference/busca_por_cep.md).
  Quando se passava um vetor com várias resoluções, a função criava as
  colunas com os nomes corretos mas preenchia todas elas com os índices
  de uma única resolução — a última do vetor. Agora a função apresenta o
  comportamento esperado. Este é o mesmo bug que havia sido corrigido na
  função
  [`geocode()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode.md)
  na versão v0.6.4.

- Correção interna na etapa de resolução de empates da função
  [`geocode()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode.md)
  nos casos em que as coordenadas candidatas estão a menos de 300 metros
  entre si. Nessas situações, o pacote descartava o candidato com
  **maior** valor de `contagem_cnefe` e retornava o de menor,
  contrariando a regra de desempate documentada. Agora o candidato com
  maior `contagem_cnefe` é preservado.

- Correção interna na etapa de resolução de empates da função
  [`geocode()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode.md).
  A coluna `logradouro_encontrado`, usada internamente para decidir como
  cada empate é resolvido, só era preenchida quando o argumento
  `resultado_completo = TRUE`. Na prática, isso fazia com que
  `resultado_completo` — que deveria controlar apenas quais colunas
  aparecem no resultado — alterasse também as coordenadas devolvidas: no
  comportamento padrão, nenhum empate era classificado como “perdido”, e
  endereços com logradouros homônimos distantes entre si recebiam a
  média ponderada das coordenadas dos candidatos, em vez das coordenadas
  do candidato com maior `contagem_cnefe`. Agora a coluna é sempre
  repassada às etapas internas, e as coordenadas devolvidas não dependem
  mais de `resultado_completo`. Na amostra `large_sample.parquet`
  distribuída com o pacote, apenas 558 dos 20.028 (2.7%) endereços eram
  afetados, com diferenças de até 26 km.

- Bug corrigido em função interna de limpeza automática do cache de
  dados do CNEFE. Quando a pasta de cache continha dados de um release
  antigo convivendo com os do release corrente, o pacote apagava a pasta
  de cache inteira — inclusive os dados correntes, que estavam íntegros
  —, forçando um novo download de todo o conjunto de dados. Agora apenas
  as pastas dos releases antigos são apagadas. Além disso, uma pasta de
  release com nome fora do padrão esperado fazia a limpeza parar com o
  erro `missing value where TRUE/FALSE needed`, o que interrompia
  qualquer chamada a
  [`geocode()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode.md),
  [`geocode_reverso()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode_reverso.md)
  ou
  [`busca_por_cep()`](https://ipeagit.github.io/geocodebr/dev/reference/busca_por_cep.md)
  com `cache = TRUE`. Esse caso passa a ser tratado como release antigo.

- Bug corrigido no argumento `cache = FALSE` das funções
  [`geocode()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode.md),
  [`geocode_reverso()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode_reverso.md)
  e
  [`busca_por_cep()`](https://ipeagit.github.io/geocodebr/dev/reference/busca_por_cep.md).
  Nesse modo, os dados do CNEFE são baixados para um diretório
  temporário, mas as funções liam os dados da pasta de cache persistente
  — isto é, de um lugar diferente daquele em que os dados haviam acabado
  de ser gravados. Na prática, quem não tinha os dados em cache recebia
  o erro `IO Error: No files found that match the pattern ...` depois de
  esperar o download inteiro, e quem já tinha obtinha o resultado
  correto, mas lido do cache, com o download recém-feito descartado.
  Agora a leitura usa a pasta devolvida por
  [`download_cnefe()`](https://ipeagit.github.io/geocodebr/dev/reference/download_cnefe.md).

## geocodebr v0.6.4

Lançamento CRAN: 2026-07-22

### Correção de bugs (Bug fixes)

- Bug corrigido no argumento `h3_res` da fução
  [`geocode()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode.md).
  A função estava sobre-escrevendo as colunas quando se passava um vetor
  de várias resoluções de `h3_res`. Agora a função apresenta o
  comportamento esperado.

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
  [`geocode_reverso()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode_reverso.md)
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
  [`geocode()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode.md)
  agora retorna erro informativo quando alguma coluna na tabela de input
  tem nome com algum caractere não alfanumérico, como . , ? ^ - ! ~. Não
  há problema com o barra baixa \_, como em “name_muni”. Fecha
  [issue](https://github.com/ipea/geocodebr/issues/92)
  [\#92](https://github.com/ipea/geocodebr/issues/92)
- Corrigido erro na função de
  [`geocode_reverso()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode_reverso.md)
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
  [`geocode()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode.md)
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
  [`geocode()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode.md),
  [`geocode_reverso()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode_reverso.md)
  e
  [`busca_por_cep()`](https://ipeagit.github.io/geocodebr/dev/reference/busca_por_cep.md)
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
  [`geocode()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode.md)
  agora é apenas um `"data.frame"`, e não mais um
  `"data.table" "data.frame"`.
- A função
  [`geocode()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode.md)
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
  [`geocode()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode.md)
  agora é envolta com {callr}, e por isso usa muito menos memória RAM e
  não tem vazamento de memória.
  [\#48](https://github.com/ipea/geocodebr/issues/48)

## geocodebr v0.4.0

Lançamento CRAN: 2025-11-18

### Mudanças grandes (Major changes)

- A função
  [`geocode()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode.md)
  agora não aplica match probabilístico em lograouros cujo nome são só
  uma letra (e.g. RUA A, RUA B, RUA C) ou compostos só por dígitos (RUA
  1, RUA 10, RUA 20). [Encerra
  issue](https://github.com/ipea/geocodebr/issues/67)
  [\#67](https://github.com/ipea/geocodebr/issues/67). Isso diminui
  muito os casos de falso positivo no match probabilístico.
- O parâmetro `h3_res` utilizado nas funções
  [`geocode()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode.md)
  e
  [`busca_por_cep()`](https://ipeagit.github.io/geocodebr/dev/reference/busca_por_cep.md)
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
  [`geocode()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode.md)
  e
  [`busca_por_cep()`](https://ipeagit.github.io/geocodebr/dev/reference/busca_por_cep.md),
  que permite o usuário inserir uma coluna no output indicando o id da
  célula H3 na resolução espacial desejada. [Encerra
  issue](https://github.com/ipea/geocodebr/issues/43)
  [\#43](https://github.com/ipea/geocodebr/issues/43).
- O output da função
  [`geocode()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode.md)
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
  [`deletar_pasta_cache()`](https://ipeagit.github.io/geocodebr/dev/reference/deletar_pasta_cache.md).

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
  [`geocode()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode.md)
  agora inclui busca com match probabilistico. [Encerra
  issue](https://github.com/ipea/geocodebr/issues/34)
  [\#34](https://github.com/ipea/geocodebr/issues/34).
- Nova função `buscapor_cep()`. [Encerra
  issue](https://github.com/ipea/geocodebr/issues/8)
  [\#8](https://github.com/ipea/geocodebr/issues/8).
- Nova função
  [`geocode_reverso()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode_reverso.md).
  [Encerra issue](https://github.com/ipea/geocodebr/issues/35)
  [\#35](https://github.com/ipea/geocodebr/issues/35).
- A função
  [`download_cnefe()`](https://ipeagit.github.io/geocodebr/dev/reference/download_cnefe.md)
  agora aceita o argumento `tabela` para baixar tabelas específicas.

### Mudanças pequenas (Minor changes)

- Ajuste na solução de casos de empate mais refinada e agora detalhada
  na documentação da função
  [`geocode()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode.md).
  [Encerra issue](https://github.com/ipea/geocodebr/issues/37)
  [\#37](https://github.com/ipea/geocodebr/issues/37). O método adotado
  na solução de empates agora fica transparente na documentação da
  função
  [`geocode()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode.md).
- Nova vignette sobre a função
  [`geocode_reverso()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode_reverso.md)
- Vignette sobre *Get Started* e da função
  [`geocode()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode.md)
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
