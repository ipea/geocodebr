# Memória do projeto — geocodebr

Correções e fatos aprendidos que persistem entre sessões.

Quando um erro é corrigido, ou quando uma abordagem não óbvia é confirmada, acrescente uma entrada
`[LEARN:categoria]` abaixo, no formato `errado → certo`, com uma linha explicando **por quê**.

Categorias em uso: `cnefe` (quirks da fonte de dados do IBGE), `duckdb`, `cran`, `testes`, `workflow`.

Não registre aqui o que o próprio repositório já documenta (estrutura do código, histórico do git,
conteúdo do [CLAUDE.md](CLAUDE.md)) — registre o que não é derivável lendo o código.

## Revisão de código em andamento

Os achados da revisão das três funções exportadas principais estão em
[`quality_reports/diagnoses/`](quality_reports/diagnoses/), com evidência e reprodução de cada item:

- `2026-08-22_geocode-pipeline-achados.md` — `geocode()`
- `2026-08-23_geocode-reverso-e-busca-por-cep-achados.md` — `geocode_reverso()` e `busca_por_cep()`

Cada relatório tem uma tabela-resumo no final marcando o que já foi corrigido. **Dois itens críticos
seguem abertos, ambos no `geocode()`:** o erro de SQL quando `resultado_completo = TRUE` e não há empates,
e o fato de `resultado_completo` alterar as coordenadas retornadas. Os dois são erros de SQL de correção
barata.

---

<!-- Novas entradas abaixo. Mais recentes no final. -->

- `[LEARN:duckdb]` Chamar `dbDisconnect()` duas vezes na mesma conexão → aviso `"Connection already
  closed."`. Ao acrescentar `on.exit()` numa função que já desconecta explicitamente, guardar com
  `if (DBI::dbIsValid(con))`. **Por quê:** sem o guarda, o aviso apareceria em toda chamada bem-sucedida.

- `[LEARN:duckdb]` `arrow::float16()` no schema de `lat`/`lon` **não** causa perda de precisão — o DuckDB
  mapeia para `DOUBLE`, e o round-trip volta exato. **Por quê:** o tipo assusta (float16 teria erro de
  ~1,5 km em latitude) e o comentário no código diz "Equivalent to NUMERIC(8,6)", que está errado. Não
  "corrigir" o tipo achando que é bug.

- `[LEARN:testes]` `inst/extdata/pontos.rds` é um fixture ruim para testar cardinalidade em
  `geocode_reverso()`: com `dist_max = 1000`, 3 dos 4 pontos não têm endereço próximo e somem em silêncio
  pelo `INNER JOIN`. Derivar pontos de endereços reais do CNEFE. **Por quê:** um teste com esse fixture dá
  o mesmo resultado para código certo e errado.

- `[LEARN:testes]` "O arquivo `.duckdb` pode ser apagado?" **não** é proxy válido para "a conexão fechou?"
  — o arquivo é apagável nos dois casos. Usar `DBI::dbIsValid()` sobre a conexão. **Por quê:** esse proxy
  levou a uma conclusão errada que precisou ser corrigida.

- `[LEARN:testes]` O bloco que adiciona colunas H3 está **duplicado** entre `geocode()` e
  `busca_por_cep()`, e o mesmo bug (usar o vetor `h3_res` no lugar da variável do laço) apareceu nos dois,
  corrigido em cada um numa versão diferente. **Por quê:** ao corrigir algo nesse bloco, checar o outro
  arquivo. Um helper interno único eliminaria a classe do problema.

- `[LEARN:testes]` `devtools::test()` sozinho **nao testa** mudancas em nada que passe por `geocode()`.
  O corpo roda em `callr::r(..., package = TRUE)`, que faz o subprocesso carregar a versao **instalada**
  do geocodebr (aqui, a 0.6.4 do CRAN), ignorando o `pkgload::load_all()` do devtools. Para validar de
  verdade: ou chamar `geocode_core()` direto (em processo, com todos os argumentos explicitos), ou
  instalar o dev numa biblioteca temporaria e apontar `R_LIBS` para ela antes de rodar os testes.
  **Por que:** uma rodada de teste passou verde depois de um patch que o subprocesso nunca chegou a
  executar; sem isso, a suite valida o codigo errado.

- `[LEARN:testes]` Rodar `devtools::test()` mexe em `tests/testthat/_snaps/` (reescreve com CRLF e apaga
  snapshots nao exercitados, p.ex. `download_cnefe.md`). Conferir `git status` e restaurar com
  `git checkout -- tests/` antes de commitar. **Por que:** entra ruido de snapshot num diff que deveria
  ser so de `R/`.

- `[LEARN:geocode]` As categorias sem logradouro (`dc01`, `dc02`, `db01`, `dm01` — municipio + cep ou
  bairro) **nao devem** entrar no ramo de "empates perdidos": ali o empate e entre enderecos diferentes
  dentro do mesmo CEP/bairro/municipio, e a media ponderada e o centroide que a `precisao` (`cep`,
  `localidade`, `municipio`) promete. O ramo "perdidos" existe para o problema oposto — logradouros
  homonimos espalhados pela cidade, onde a media cai num ponto que nao e nenhum dos candidatos.
  **Por que:** hoje essas categorias ficam de fora por propagacao de `NULL` em
  `NOT REGEXP_MATCHES(logradouro_encontrado, ...)`, o que parece bug e convida a um `COALESCE`
  "corretivo" que seria regressao.

- `[LEARN:duckdb]` `shared_home` (e os demais argumentos de configuracao do driver) pertence ao construtor
  `duckdb::duckdb()`, **nao** ao `DBI::dbConnect()`. Passado ao `dbConnect()` ele e engolido pelo `...` sem
  erro e sem efeito. Verificado em sessoes limpas: so com o argumento no construtor a mensagem
  "duckdb is storing downloaded extensions and secrets under ~/.duckdb" para de aparecer.
  **Por que:** a versao errada foi commitada acreditando-se que funcionava, e nada no R avisa.

- `[LEARN:duckdb]` `shared_home = FALSE` isola o diretorio de extensoes por conexao, e por isso obriga a
  reinstalar a extensao espacial a cada chamada de `geocode_reverso()`: medido **6,96 s** contra **0,05-1,23 s**
  com `shared_home = TRUE`. **Por que:** a recomendacao inicial de usar `FALSE` para evitar concorrencia entre
  processos tinha esse custo escondido; o pacote usa `TRUE`, que preserva o cache de extensoes e silencia a
  mensagem do mesmo jeito.
