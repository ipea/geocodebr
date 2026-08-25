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
- `2026-08-24_geocode-revisao-critica.md` — rodada de acompanhamento do relatório de 22/08: status de cada
  item antigo + achado novo (não-determinismo em `da0x`/`pa0x`, ver `[LEARN:duckdb]` abaixo)

Cada relatório tem uma tabela-resumo no final marcando o que já foi corrigido. **Um item crítico segue
aberto no `geocode()`:** `FIRST()` sem `ORDER BY` em `match_weighted_cases.R`/`match_weighted_cases_probabilistic.R`
faz `da0x`/`pa0x` devolverem coordenadas diferentes em execuções idênticas quando há candidatos empatados
(ver `[LEARN:duckdb]` abaixo). O item 1 do relatório de 22/08 (erro de SQL quando `resultado_completo = TRUE`
e não há empates) **foi corrigido** em 2026-08-24. O item 2 do mesmo relatório (`resultado_completo` alterando
coordenadas) teve sua causa original corrigida, mas foi **substituído** por este novo item — mesmo sintoma,
causa-raiz diferente e mais séria (não é sobre `resultado_completo`, é não-determinismo entre quaisquer duas
chamadas).

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

- `[LEARN:duckdb]` Pré-declarar no schema de `output_db` (em `geocode.R`) uma coluna que outra parte do
  pipeline também cria dinamicamente (ex.: `empate`, via `SELECT d.*, (...) AS empate`) causa **duas
  colunas com o mesmo nome** no resultado da CTE. O DuckDB aceita a query sem erro, mas toda referência
  não-qualificada a essa coluna mais adiante (`WHERE empate = FALSE`) resolve para a coluna errada (a
  original, `NULL`), fazendo os filtros descartarem silenciosamente todas as linhas — sem erro, sem
  warning. **Corrigido** em `trata_empates_geocode_duckdb.R`: a coluna `empate` deixou de ser pré-declarada
  no schema; no ramo de zero-empates agora é criada via `ALTER TABLE output_db ADD COLUMN IF NOT EXISTS
  empate BOOLEAN DEFAULT FALSE` (resolve o bug original de `resultado_completo = TRUE` + zero empates —
  `output_db` sem `output_db2` não tinha a coluna que `merge_results_to_input()` sempre seleciona quando
  `resultado_completo = TRUE`), e nos outros dois ramos ela nasce direto no `SELECT` (`AS empate`, sem
  `REPLACE`, já que nesses pontos a coluna nunca existe previamente). **Por quê:** o padrão "pré-declarar
  no schema pra evitar erro de coluna inexistente" parece a correção óbvia quando o sintoma é um `Binder
  Error: column does not exist`, mas se qualquer CTE downstream recria essa mesma coluna por nome, o fix
  vira uma colisão silenciosa — o sintoma muda de "erro barulhento" pra "todo o output sai `NA`", o que é
  bem mais difícil de depurar. Checar sempre se o nome já existe a montante antes de adicionar ao schema.

- `[LEARN:duckdb]` `FIRST(coluna)` **sem `ORDER BY`** dentro de um `GROUP BY` não é determinístico — o
  DuckDB pode devolver um valor diferente em execuções idênticas (mesma query, mesmo input), porque a
  ordem física de scan dentro do grupo varia com o plano de execução paralelo. Confirmado ao vivo em
  `match_weighted_cases.R`/`match_weighted_cases_probabilistic.R` (tipos `da0x`/`pa0x`, que agregam vários
  candidatos do CNEFE via `GROUP BY tempidgeocodebr, endereco_encontrado` e escolhem `contagem_cnefe`,
  `cod_setor`, `endereco_encontrado` etc. via `FIRST()`): 4 chamadas idênticas a `geocode()` devolveram 3
  valores diferentes de `lat`/`lon` (~1,5 km de diferença) para o mesmo endereço, com `n_cores` no default
  (paralelo). Com `n_cores = 1` as mesmas 4 chamadas foram estáveis. **Por quê:** `contagem_cnefe` escolhido
  por esse `FIRST()` alimenta o critério de desempate em `trata_empates_geocode_duckdb.R`
  (`ORDER BY contagem_cnefe DESC`), então a arbitrariedade se propaga até qual candidato de rua o usuário
  recebe. Ainda **não corrigido** — ver item 1 de
  `quality_reports/diagnoses/2026-08-24_geocode-revisao-critica.md`. Ao adicionar qualquer `FIRST()`/`LAST()`
  novo no pipeline, sempre com `ORDER BY` explícito.

- `[LEARN:duckdb]` A não-determinismo de `FIRST()` sem `ORDER BY` (entrada acima) **não depende só de
  paralelismo** — `n_cores = 1` não é garantia de estabilidade se a *ordem física de scan* mudar por outro
  motivo, como trocar a fonte de uma `TEMP TABLE` materializada por uma `TEMP VIEW` sobre o mesmo parquet.
  Medido: com `n_cores = 1` fixo dos dois lados, 4 de 20.028 linhas (`da02`/`da04`) mudaram de candidato
  (516 m–4.915 m de diferença) só por causa da troca TABLE→VIEW em `register_cnefe_table()` — ver
  `quality_reports/diagnoses/2026-08-24_temp-view-benchmark.md`. **Por quê:** ao comparar dois builds/branches
  para achar regressão de corretude, rodar em `n_cores = 1` reduz o ruído mas não elimina o `FIRST()`/`LAST()`
  como fonte de falso positivo — checar se a linha divergente é justamente `da0x`/`pa0x` antes de investigar
  mais fundo.

- `[LEARN:duckdb]` Trocar `CREATE TEMP TABLE` por `CREATE TEMP VIEW` em `register_cnefe_table()`
  (`R/register_cnefe_tables.R`) **piora** o tempo total do `geocode_core()` em ~42% (medido: 4,18 s → 5,92 s
  de mediana, 20.028 endereços, `n_cores = 7`), apesar da função em si ficar 3,5× mais rápida isoladamente
  (1,51 s → 0,43 s). **Já tentado e revertido** — não retentar sem mudar a abordagem. **Por quê:** um
  benchmark isolado com joins sintéticos (`quality_reports/diagnoses/2026-08-23_geocode-diagnostico-performance.md`
  §3) previu ganho até ~12 usos da mesma tabela porque testava joins de uma coluna; os joins reais do laço
  de matching (múltiplas colunas-chave, CTEs `unique_munis`/`unique_states`, interpolação por número,
  `GROUP BY ... FIRST()`) são caros o bastante por consulta para que reabrir/refiltrar o parquet a cada uma
  das ~10 etapas que usam a tabela mais compartilhada custe mais que materializar uma vez. Um benchmark
  isolado de custo-por-join não é proxy confiável para o custo real de uma query complexa do pacote — sempre
  validar ponta a ponta com `geocode_core()` antes de aplicar uma mudança dessa família.

- `[LEARN:geocode]` O laço de matching em `geocode_core()` (`R/geocode.R`) pulava etapas só quando a
  coluna-chave estava **ausente**, nunca quando ela existia mas era inteiramente `NA` (o caso normal de um
  campo de endereço não declarado, que vira coluna-fantasma `NA_character_`). **Corrigido** em 25/08: nova
  variável `campos_nao_declarados <- names(missing_cols)`, calculada a partir da lista `campos_endereco` já
  existente (não dos dados), e usada no guarda do laço junto com o teste de presença. Medido: 20.028
  endereços só com CEP/bairro/município/UF, 3,28s → 0,78s (4,2×), output `identical()` bit-a-bit antes/depois
  — ver `quality_reports/diagnoses/2026-08-25_geocode-guard-fix-benchmark.md`. **Por quê:** a primeira versão
  cogitada usava `all(is.na(input_padrao[[cc]]))`, um scan O(n) por coluna sobre a tabela padronizada
  inteira — funcionalmente equivalente para o caso comum (campo não declarado), mas com custo proporcional
  ao tamanho do input a cada chamada de `geocode()`. Preferir sempre reaproveitar informação já computada a
  partir da *declaração* do usuário (`campos_endereco`/`missing_cols`, um objeto pequeno e fixo) a escanear
  os *dados* (`input_padrao`, que cresce com o input), quando as duas fontes respondem a mesma pergunta.
