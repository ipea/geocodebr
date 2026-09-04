# Memória do projeto — geocodebr

Correções e fatos aprendidos que persistem entre sessões.

Quando um erro é corrigido, ou quando uma abordagem não óbvia é confirmada, acrescente uma entrada
`[LEARN:categoria]` abaixo, no formato `errado → certo`, com uma linha explicando **por quê**.

Categorias em uso: `cnefe` (quirks da fonte de dados do IBGE), `duckdb`, `cran`, `testes`, `workflow`.

Não registre aqui o que o próprio repositório já documenta (estrutura do código, histórico do git,
conteúdo do [CLAUDE.md](CLAUDE.md)) — registre o que não é derivável lendo o código.

## Revisão de código em andamento

Os achados da revisão das três funções exportadas principais estão em
[`quality_reports/diagnoses/`](quality_reports/diagnoses/), com evidência e reprodução de cada item.
A lista priorizada de eficiência do `geocode()` — a referência viva para retomar o trabalho — é
`2026-08-24_geocode-eficiencia-consolidado.md`; ela é atualizada a cada item concluído e é o primeiro
lugar a checar no início de uma sessão nova. Status em 25/08 (ver essa lista para detalhes de cada um):

| # | item | status |
|---|---|---|
| 1 | Laço pula etapas com campo não declarado | ✅ commitado (`d27b722`) |
| 2 | Jaro redundante em `pa01-03` | ✅ commitado (`282c302`) |
| 3 | `FIRST()`/`QUALIFY` sem `ORDER BY` (não-determinismo) | ✅ commitado (`0592c83`) |
| 4 | `TEMP VIEW` em vez de `TEMP TABLE` | ❌ testado e **refutado** — não retentar |
| 5 | Baixar só as tabelas de referência necessárias | ⏳ aberto |
| 6 | Dedup dos quatro `match_*()` | ✅ commitado (`889e331`) — `R/match_helpers.R` |
| 7 | Código morto em `register_cnefe_tables.R` | ⏳ aberto |

Relatórios de diagnóstico mais antigos, ainda com contexto útil:

- `2026-08-22_geocode-pipeline-achados.md` — `geocode()`
- `2026-08-23_geocode-reverso-e-busca-por-cep-achados.md` — `geocode_reverso()` e `busca_por_cep()`
- `2026-08-24_geocode-revisao-critica.md` — rodada de acompanhamento do relatório de 22/08

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
  recebe. **Corrigido em 25/08** — `FIRST(col ORDER BY ABS(numero - numero_cnefe), numero_cnefe, lat, lon)`
  em `match_weighted_cases.R`/`match_weighted_cases_probabilistic.R`; ver
  `quality_reports/diagnoses/2026-08-25_first-order-fix-benchmark.md`. Ao adicionar qualquer `FIRST()`/`LAST()`
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

- `[LEARN:duckdb]` O `FIRST()` sem `ORDER BY` (entrada acima) **não era a única fonte** de não-determinismo
  no laço de empates. `R/trata_empates_geocode_duckdb.R` tem dois `QUALIFY ROW_NUMBER() OVER (PARTITION BY
  tempidgeocodebr ORDER BY contagem_cnefe DESC) = 1` (ramos "perdidos" e "salváveis") que também escolhiam
  arbitrariamente entre candidatos empatados em `contagem_cnefe` — achado só depois de corrigir o `FIRST()`
  e ver que a reprodutibilidade não fechou 100%. **Corrigido em 25/08, em duas rodadas**: primeiro `ORDER BY
  contagem_cnefe DESC, desvio_metros` (reduziu de 5 para 2-3 linhas divergentes em 20.028, mas não fechou —
  `desvio_metros` é atributo do registro CNEFE, não distância calculada, e ainda empatava às vezes); depois
  `..., endereco_encontrado` como terceiro critério, que fechou o não-determinismo por completo (0/20.028 em
  3 rodadas consecutivas de "duas chamadas idênticas"). Ver
  `quality_reports/diagnoses/2026-08-25_first-order-fix-benchmark.md`. **Por quê:** ao investigar
  não-determinismo em `geocode()`, não presumir que corrigir um `FIRST()`/`QUALIFY` sem `ORDER BY` fecha o
  problema — rodar duas chamadas idênticas de ponta a ponta e comparar de novo depois de cada fix, porque
  pode haver mais de uma fonte no mesmo caminho de código, e um desempate parcial (poucas colunas) pode
  reduzir sem zerar a divergência.

- `[LEARN:geocode]` Os quatro `match_*()` (`match_cases`, `match_cases_probabilistic`,
  `match_weighted_cases`, `match_weighted_cases_probabilistic`) tinham ~80% de código idêntico na montagem
  das colunas `*_encontrado`/`cod_setor`/`logradouro_encontrado`. **Deduplicado em 25/08** em
  `R/match_helpers.R`, função única `monta_colunas_encontradas(y, key_cols, resultado_completo,
  colunas_encontradas, additional_cols, agregado, ordem_first)` — `agregado = TRUE` embrulha cada coluna
  (inclusive `logradouro_encontrado` e `cod_setor`) em `FIRST(... ordem_first)`, para a segunda parte
  (agregada por `GROUP BY`) das queries ponderadas. Duas armadilhas que só apareceram ao estender a função
  para os quatro arquivos, não só o mais simples: (1) o tratamento de `cod_setor` **não era**
  `agregado`-consciente na primeira versão — só `demais_key_cols` tinha o `if (agregado)`; sem o teste teria
  saído `{y}.cod_setor` em vez de `FIRST(cod_setor {ordem_first})` na parte agregada, um bug silencioso.
  (2) o `FIRST(logradouro_encontrado {ordem_first})` da parte 2 nunca passava pelo helper nas duas primeiras
  rodadas — era reconstruído à mão em cada um dos dois arquivos ponderados, e um tinha `AS
  logradouro_encontrado` e o outro não (inconsistência que só a fusão final eliminou). **Por quê:** ao
  estender um helper de 1 caso de uso para 4, testar `identical()` em TODOS os `match_type` (as 25
  categorias), não só no cenário que motivou a extração — o bug do `cod_setor` só existe nas etapas `da0x`/
  `pa0x`, que `match_cases.R` (o primeiro arquivo migrado) nunca exercita.

- `[LEARN:duckdb]` Num regex passado ao DuckDB via string R comum, `\\\\b` no fonte chega ao RE2 como
  *backslash literal + "b"*, não como fronteira de palavra — a forma certa no fonte R é `\\b` (ou raw
  string `r"{...\b...}"`, como `cria_col_logradouro_confusao()` em `utils.R` já faz). Consequência real
  encontrada em 26/08: a exceção de ruas-data (`NOT REGEXP_MATCHES(logradouro_encontrado, '\\bDE
  (JANEIRO|...)\\b')`) em `trata_empates_geocode_duckdb.R` é **código morto** — nunca casa — então uma
  "RUA QUINZE DE NOVEMBRO" empatada a <1 km cai no ramo "perdidos" (fica o candidato top) em vez de
  "salváveis" (média ponderada), contra a intenção documentada no próprio comentário. Repro mínimo:
  `REGEXP_MATCHES('RUA QUINZE DE NOVEMBRO', <padrão>)` → `FALSE` com `\\b` duplo no fonte, `TRUE` com
  simples. Fix pendente (é mudança de comportamento; tratar junto com a unificação das listas de
  logradouro ambíguo). **Por quê:** o mesmo padrão visual (`\\\\b`) funciona em outras engines que
  processam escapes na string SQL, e o erro é silencioso — a cláusula simplesmente nunca filtra.

- `[LEARN:testes]` Em bases grandes com `n_cores` default, `identical()` bit-a-bit é critério
  **inatingível** para o caminho de empates: a média ponderada (`SUM(lat*contagem_cnefe) OVER (...)`)
  acumula em ordem dependente do paralelismo do DuckDB, e duas execuções do MESMO código sobre
  `df_sample_empates.parquet` (1M linhas, 84.238 empates) diferiram em ~500 valores de `lat`/`lon` com
  diferença máxima de ~4e-14 grau (nanômetros). Verificado em 26/08 antes de atribuir a divergência a uma
  edição — a mesma divergência existe entre run1 e run2 da versão intocada. **Por quê:** para A/B nesse
  caminho, ou rodar pequeno/single-thread (bitwise estável, como o harness sintético de todos os ramos),
  ou comparar com `all.equal()` e inspecionar que as diferenças são só `lat`/`lon` em nível de ulp;
  `identical() == FALSE` sozinho não é evidência de regressão.

- `[LEARN:geocode]` Antes de "corrigir" um valor que parece vazar indevidamente para o output, checar se
  ele já é filtrado a jusante. `match_weighted_cases_probabilistic.R` sempre calculava/agregava
  `similaridade_logradouro` mesmo com `resultado_completo = FALSE`, o que parecia um bug (a regra do
  pacote é: colunas extra só aparecem com `resultado_completo = TRUE`). Mas `merge_results_to_input()`
  (`R/utils.R:147-170`) **já exclui** `similaridade_logradouro` da lista de colunas selecionadas quando
  `resultado_completo = FALSE`, então o valor nunca chegava ao usuário — confirmado com `identical()`
  antes/depois da "correção" (0 diferença nos dois casos). A mudança foi revertida por não ter efeito
  observável e adicionar complexidade sem necessidade. **Por quê:** um sintoma "essa coluna deveria ser
  condicional e não é" pode já estar coberto por um filtro mais a jusante no pipeline — ler até o fim do
  caminho do dado (aqui, `merge_results_to_input()`) antes de assumir que a origem precisa mudar.

- `[LEARN:duckdb]` "Python é mais lento que R com o mesmo DuckDB no Windows" → **a variável não é a
  toolchain (MSVC vs MinGW), é o heap do processo hospedeiro**. O `Rscript.exe`/`Rterm.exe` optam pelo
  **Segment Heap** no manifest embutido; o `python.exe` (python.org) e o CLI usam o heap NT legacy, cujo
  lock global serializa alocação/free multithread — e o DuckDB no Windows não tem jemalloc pra bypassar
  isso. Piora com MAIS threads (24 threads é pior que 8 no legacy; escala negativa). Causa raiz
  documentada em [duckdb/duckdb#24027](https://github.com/duckdb/duckdb/issues/24027) (autor: Douglas
  Braga, Ipea, máquina 24 cores/512GB igual à nossa); fix upstream [duckdb#24036](https://github.com/duckdb/duckdb/pull/24036)
  conserta **só o CLI** — o wheel Python nunca vai se auto-consertar (manifest pertence ao exe
  hospedeiro). Medido no port Python (10M CadÚnico, 24 threads): total 11:47 → **3:08** rodando com uma
  cópia do interpretador com manifest SegmentHeap (`python-sh.exe`, criada com o
  `patch_segment_heap.py` da reprodução da issue; o `python.exe` original fica intocado).
  Esse mesmo mecanismo explicou dois mistérios: a inflação ~10× dos empates em dados reais (strings
  reais ampliam o tráfego de alocação; 1:51 → 0:05) e o `con.close()` de ~3 min (frees na mesma fila;
  2:56 → 0:05). Mitigação sem patch: `n_cores≈4`. Ver tabela completa em
  `python-package/benchmarks/resultados_benchmark.md`. **Por quê:** a hipótese inicial (toolchain) veio
  da pesquisa de docs e estava errada — a issue nasceu exatamente com essa hipótese errada e o próprio
  autor a refutou com cross-hosting da DLL do R dentro do python.exe (fica lenta) e do MSVC CLI
  patcheado (fica rápido). Ao comparar clientes DuckDB no Windows, parear SEMPRE o processo hospedeiro.

- `[LEARN:testes]` Nesta máquina compartilhada, benchmarks de tempos curtos variam ±15-20% entre
  rodadas (carga da máquina), então comparações antes/depois precisam ser **pareadas e intercaladas na
  mesma janela** (run A, run B, run A, run B) — foi o que fechou o sinal do heap (o primeiro A/B da
  investigação, em janelas separadas, mediu "1,4× de toolchain"; pareado e em escala maior, o fator
  real era ~4×). Fases determinísticas de sort/materialização são reprodutíveis (merge deu 0:41 três
  vezes seguidas) e podem ser lidas de rodada única; fases de matching/empates não. Protocolo fixo no
  `python-package/benchmarks/benchmark_sample.py` (sample 10M em `data/sample_cad_unico.parquet`).
  **Por quê:** direção de melhoria medida em janelas separadas numa máquina compartilhada não é
  evidência — pode ser só a carga do momento.
