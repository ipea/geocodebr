# `geocode()` — análise consolidada de eficiência e proposta priorizada — 2026-08-24

> **Status final — 25/08.** Itens 1, 2, 3 e 6 (tabela §1) foram implementados, verificados
> (`identical()` ponta a ponta + `devtools::test()`) e commitados: `d27b722` (item 1), `282c302` (item 2,
> já estava feito em 24/08), `0592c83` (item 3 — inclui a correção adicional no `QUALIFY` de
> `trata_empates_geocode_duckdb.R`, achado durante a verificação, não previsto originalmente), `889e331`
> (item 6, ver também a fusão das duas funções de apoio numa só, `monta_colunas_encontradas()`, em
> `R/match_helpers.R`). Item 4 (`TEMP VIEW`) foi testado e **refutado** — não retentar. Itens 5 e 7
> continuam abertos. Detalhes de cada implementação: `2026-08-25_geocode-guard-fix-benchmark.md` (item 1)
> e `2026-08-25_first-order-fix-benchmark.md` (item 3). Ver também `[LEARN:geocode]`/`[LEARN:duckdb]` em
> `MEMORY.md` para as armadilhas encontradas em cada um.
>
> **Atualização — 26/08.** Medida (não implementada) a ideia de um cache cumulativo de `jaro_similarity()`
> entre etapas (`pn01`→`pn02`→`pn03`) — ver §5. Resultado: **refutado como item isolado** (ganho ~0,8% do
> tempo total de `geocode()`). A medição revelou uma redundância aparentemente maior e mais barata de
> resolver — dedup do lado do input dentro de cada `calculate_string_dist()` (item #9) — mas um processo
> planejador→revisor adversário sobre o design, seguido de medição isolada real (§5.5, mesma amostra de
> 20k), **também refutou o item #9**: a versão com dedup via tabela-cache foi **5×–18× mais lenta** que o
> código atual (não mais rápida como a estimativa inicial projetava), provavelmente pelo custo de criar
> `TEMP TABLE`/`INSERT`/`JOIN` extra superar em muito o custo de `jaro_similarity()`, que já é barato e
> vetorizado no DuckDB. **Nenhuma mudança em `calculate_string_dist()` — não implementar.**

**O que é este documento.** Não é um novo diagnóstico do zero — é uma auditoria de status: cada achado dos
três relatórios anteriores (`2026-08-23_geocode-diagnostico-performance.md`,
`2026-08-23_analise-pacote-desempenho-manutencao.md`, `2026-08-24_temp-view-benchmark.md`) foi verificado
contra o `HEAD` atual (código-fonte + `git log`), reclassificado em **feito / refutado / ainda aberto**, e
o item de maior impacto ainda aberto foi remedido nesta sessão para confirmar que a magnitude continua
válida. O resultado é uma lista única, priorizada, pronta para a próxima rodada de implementação.

**Metodologia da verificação:** leitura do código atual em `R/`, `git log --since="2026-08-23" -- R/` para
saber o que mudou, e duas rodadas de `Rprof()` frescas (HEAD atual, 20.028 endereços, cache local v0.4.1,
`n_cores = 7`) comparando cenário "todos os campos" vs. "só CEP/bairro/município/UF" — ver
`tests/tests_rafa/benchmark_empty_field_guard.R`.

---

## 1. Status de cada item conhecido

| # | item | status em 24/08 | evidência |
|---|---|---|---|
| 1 | Laço não pula etapas cujo campo-chave está **vazio** (só checa presença da coluna-fantasma) | **ainda aberto** | `geocode.R:417` inalterado; reconfirmado nesta sessão (§2 abaixo) |
| 2 | `pa01`/`pa02`/`pa03` recalculavam Jaro sem poder resolver nada | **corrigido** | commit `282c302` (24/08) — `match_types_jaro_redundante` em `utils.R:357`, guarda em `match_weighted_cases_probabilistic.R` |
| 3 | `FIRST()` sem `ORDER BY` em `da*`/`pa*` — não-determinismo | **ainda aberto** | `grep FIRST(` em `match_weighted_cases.R`/`match_weighted_cases_probabilistic.R`: nenhum tem `ORDER BY`; reconfirmado ao vivo em `2026-08-24_temp-view-benchmark.md` (4/20.028 linhas divergentes) |
| 4 | `CREATE TEMP VIEW` em vez de `TEMP TABLE` em `register_cnefe_table()` | **testado e refutado** | `2026-08-24_temp-view-benchmark.md` — piora 42% ponta a ponta apesar de melhorar a função isolada 3,5× |
| 5 | Baixar só as tabelas necessárias (corolário do #1) | **ainda aberto** | `geocode.R:312` chama `download_cnefe(tabela = 'todas')` sempre; `download_cnefe()` só aceita uma tabela por vez, não vetor |
| 6 | Os quatro `match_*` são ~80% código duplicado | **ainda aberto** | tamanhos inalterados: 116+152+148+187 linhas, nenhum commit de refactor desde 23/08 |
| 7 | Código morto em `register_cnefe_tables.R` (blocos comentados, funções sem chamador) | **ainda aberto** | 161 de 289 linhas (56%) são comentário, confirmado hoje; `cache_message()` e `register_geocodebr_tables()` continuam sem nenhum chamador |
| 7b | `T`/`F` em vez de `TRUE`/`FALSE` em `geocode_reverso.R` | **corrigido** | `grep \bT\b|\bF\b` não encontra mais ocorrência |
| 8 | Cache cumulativo de `jaro_similarity()` entre `pn01`→`pn02`→`pn03` (par `logradouro_input`×`logradouro_cnefe` já visto numa etapa anterior não é recalculado) | **medido e refutado** (26/08) | §5 — só 7% dos pares de `pn02`/`pn03` seriam cacheáveis das etapas anteriores; ganho ponta a ponta ≈0,8% do tempo total |
| 9 | Dedup do lado do input dentro de cada `calculate_string_dist()` (mesmo texto de logradouro em várias linhas → Jaro recalculado por linha, não por texto distinto) | **medido e refutado** (26/08) | §5.5 — dedup via tabela-cache foi 5×–18× **mais lento** que o código atual (`identical()` confirmado, só a velocidade piora); estimativa inicial de 5-6% de ganho era otimista na direção errada |

---

## 2. Reconfirmação do item #1 (maior impacto, ainda não aplicado)

O relatório de 23/08 mediu ganho de 3,3×–9× comparando código com bug vs. protótipo corrigido, numa
`git worktree` em outro commit (`a4b8036`). Para confirmar que o problema **continua com a mesma
magnitude no `HEAD` atual** (depois do fix do item #2, que também mexeu no mesmo laço), rodei duas
medições frescas com `Rprof()`, mesma amostra de 20.028 endereços, `n_cores = 7`:

| cenário | campos declarados | `geocode_core()` total | `register_cnefe_table` (tempo / % do total amostrado) |
|---|---|---|---|
| completo | logradouro, número, cep, localidade, município, estado | 5,05 s | 1,70 s / 37% |
| só CEP | cep, localidade, município, estado (sem logradouro/número) | 3,45 s | **1,82 s / 58%** |

**A materialização não cai quando os campos que a justificariam somem — ao contrário, sobe em proporção**
(37% → 58% do tempo total), porque o resto do trabalho (joins que não encontram nada) fica mais rápido
enquanto a materialização das 8 tabelas continua fixa, incluindo as duas maiores
(`municipio_logradouro_numero_*`, 1,19 GB juntas) que **não podem gerar nenhum match** quando não há
`logradouro`/`numero` no input. Isso confirma qualitativamente o achado de 23/08: o guarda em
`geocode.R:417` — `if (all(key_cols %in% names(input_padrao)))` — testa presença da coluna-fantasma, não
se ela tem algum valor utilizável, então nunca pula etapa nenhuma.

> A magnitude exata do ganho (3,3×–9×) não foi re-medida aqui porque isso exige aplicar o fix e comparar —
> o que é o próximo passo natural, não parte desta auditoria de status. O que esta rodada confirma é que a
> **causa continua intacta e o custo continua concentrado no mesmo lugar** no código atual.

---

## 3. Proposta priorizada (atualizada)

| # | mudança | ganho estimado | esforço | risco | depende de |
|---|---|---|---|---|---|
| **1** | Pular etapas de `match_type` cujo campo-chave está **vazio** (não só ausente) — `geocode.R:417` | 3,3×–9× quando faltam campos (reconfirmado §2); no-op quando não faltam | Muito baixo (~8 linhas) | Muito baixo | — |
| **2** | Fechar o não-determinismo: `ORDER BY` explícito nos `FIRST()` de `match_weighted_cases.R`/`match_weighted_cases_probabilistic.R` | reprodutibilidade exata; **pré-requisito para verificar qualquer refactor por igualdade de output** (inclusive #4 e #6 abaixo) | Muito baixo (patch já existe, medido em 23/08: sem custo de tempo) | Baixo — decisão pendente sobre semântica de `contagem_cnefe` (ver `analise-pacote-desempenho-manutencao.md` §4) | — |
| **3** | Baixar só as tabelas de referência necessárias (`download_cnefe()` aceitar vetor; `geocode()` calcular o subconjunto) | 1.492 MB → 20 MB no melhor caso (só CEP) | Médio (assinatura de `download_cnefe()` muda) | Baixo | Item 1 (mesmo cálculo de "quais campos têm valor") |
| **4** | Helper único para os quatro `match_*` (extrair montagem de `colunas_encontradas`) | manutenção — bugs already duplicados 2× no histórico (`logradouro_encontrado`, H3) | Médio | Médio — mexe no SQL dos quatro arquivos | Item 2 (para verificar que o refactor não muda resultado) |
| **5** | Remover código morto de `register_cnefe_tables.R` (161 linhas comentadas) + `cache_message()`/`register_geocodebr_tables()` sem chamador | manutenção | Muito baixo | Nenhum | — |
| — | Dedup do lado do input em `calculate_string_dist()` (cache `(logradouro_input, logradouro_cnefe) → similarity`) | ~~5-6%~~ | — | — | **Refutado** (26/08, §5.5) — medido 5×–18× **mais lento**, não mais rápido; `jaro_similarity()` já é barato o bastante no DuckDB que o overhead de tabela-cache/`INSERT`/`JOIN` extra perde de longe. Não retentar sem mudar de abordagem |
| — | Cache cumulativo de Jaro entre `pn01`→`pn02`→`pn03` | ~~ganho~~ | — | — | **Refutado** (26/08, §5) — só 7% dos pares de `pn02`/`pn03` são cacheáveis das etapas anteriores; ganho ponta a ponta ≈0,8% do tempo total, não compensa a complexidade de um cache vivendo entre etapas |
| — | `CREATE TEMP VIEW` em `register_cnefe_table()` | ~~1,5–7×~~ | — | — | **Refutado** (24/08) — piora 42% ponta a ponta; não retentar sem mudar de abordagem (ver nota em MEMORY.md) |

**Sequência sugerida:** 1 → 2 → 3, depois 4 e 5 numa passada de manutenção à parte. 1 é o maior ganho
absoluto e o mais barato; 2 não muda desempenho mas é o que destrava poder validar 3 e 4 por igualdade
exata de output (sem ele, qualquer comparação antes/depois tem ruído de ±1-4 linhas por `FIRST()`
arbitrário, como visto em §2 do relatório de hoje sobre TEMP VIEW). O item 9 (dedup de Jaro) foi medido e
refutado (§5.5) — `register_cnefe_table` (itens 1/3) continua sendo de longe o maior alvo ainda aberto, ~3×
mais caro que `calculate_string_dist` inteiro.

---

## 4. O que fica fora deste documento

- A decisão de semântica do item #2 (se `contagem_cnefe` agregado deve ser `FIRST(... ORDER BY distância)`
  ou `SUM(...)`) é do mantenedor — está detalhada em
  `quality_reports/diagnoses/2026-08-23_analise-pacote-desempenho-manutencao.md` §4, não repetida aqui.
- `geocode_reverso()` e `busca_por_cep()` não foram reauditados nesta rodada — o escopo desta análise é
  `geocode()`.
- Efeito de escala (milhões de endereços, poucos municípios) não foi remedido — a nota de 23/08 sobre isso
  (§8) continua valendo: o peso relativo da materialização cai com mais endereços por município, mas o
  item #1 não muda de sinal (nunca faz sentido materializar uma tabela que não pode gerar match).

---

## 5. Medição: cache de Jaro entre etapas — 26/08

**Pergunta original:** os cálculos de `jaro_similarity()` de etapas diferentes (`pn01`, `pn02`, `pn03`) são
independentes? Se `pn01` não encontra candidato acima do corte pra um endereço, `pn02` recalcula Jaro do
zero pra esse endereço — daria pra reaproveitar o que `pn01` já calculou?

**Por que a resposta não é óbvia:** `pn01` e `pn02` usam a *mesma* tabela física de candidatos
(`unique_logr_municipio_logradouro_cep_localidade`, `R/register_cnefe_tables.R:110-114`) — só muda a
condição de `JOIN` (`pn01` exige `estado+municipio+cep+localidade`; `pn02` solta a exigência de
`localidade`, `R/utils.R:243-272`). Como `jaro_similarity(a, b)` é função pura das duas strings, qualquer
par `(logradouro_input, logradouro_cnefe)` já testado em `pn01` vale pra sempre, independente da etapa.

**Metodologia:** script novo, mesmo padrão dos benchmarks anteriores (`Rprof()`, amostra de 20.028
endereços, cache local, `n_cores = 7`) — `tests/tests_rafa/benchmark_jaro_cache_opportunity.R`. Duas
partes: (1) `Rprof()` no pipeline real (`geocode_core()`) pra saber o peso de `calculate_string_dist` no
tempo total; (2) réplica manual do laço de matching, usando as mesmas funções internas na mesma ordem,
com queries de leitura (`SELECT`, sem alterar estado) inseridas *antes* de cada etapa `pn0k`/`pa0k` real,
contando quantos pares `(logradouro_input, logradouro_cnefe)` cada etapa computaria e quantos já apareceram
numa etapa anterior.

### 5.1 Peso de `calculate_string_dist` no tempo total

| função | % do tempo amostrado |
|---|---|
| `register_cnefe_table` | 37% |
| `calculate_string_dist` | 12% |
| `register_unique_logradouros_table` | 5% |

### 5.2 Overlap de pares entre etapas (cache cumulativo `pn01`→`pn02`→`pn03`)

| etapa | linhas no pool | pares `(input, candidato)` distintos | % já cacheável de etapas anteriores | strings de input distintas | fator de repetição (linhas / string) |
|---|---|---|---|---|---|
| `pn01` | 10.109 | 64.820 | 0% (primeira etapa) | 3.721 | 2,7× |
| `pn02` | 7.234 | 527.289 | **8,4%** | 4.707 | 1,5× |
| `pn03` | 5.456 | 623.027 | **6,5%** | 3.318 | 1,6× |
| `pa01`/`pa02`/`pa03` | — | — | 100% | — | — |

`pa01-03` darem 100% cacheável só confirma a otimização que **já existe** em produção
(`match_types_jaro_redundante`, item #2) — não é achado novo. O achado real é `pn02`/`pn03`: cada etapa
tem um universo de candidatos **~8× maior** que a anterior (soltar `localidade`/`cep` expande muito o
conjunto dentro do mesmo `cep`/`município`), então o que se sobrepõe com a etapa anterior é uma fatia
pequena desse universo bem maior.

**Conta ponta a ponta:** dos ~1,22 milhão de pares que `pn01+pn02+pn03` computam de fato em produção hoje,
um cache cumulativo evitaria 84.866 (≈7%). Aplicado aos ~12% do tempo total que `calculate_string_dist`
representa (§5.1): **≈0,8% do tempo total de `geocode()`**. **Veredito: refutado como item isolado** — não
compensa a complexidade de manter um cache vivo entre chamadas de `calculate_string_dist()` ao longo do
laço de 25 etapas.

### 5.3 Achado colateral: dedup do lado do input (item #9, novo)

A coluna "fator de repetição" (linhas do pool / strings de input distintas) mostra que **dentro de uma
única etapa** o mesmo texto de logradouro aparece em várias linhas — 2,7× em `pn01`, 1,5×-1,6× em
`pn02`/`pn03`. `calculate_string_dist()` hoje computa Jaro **por linha** (`to_compute` no
`R/string_dist.R:33-44` não deduplica o lado do input; só o lado CNEFE já é `DISTINCT`, via
`register_unique_logradouros_table()`).

Como a similaridade é uma função pura das duas strings, o mesmo mecanismo de cache (par → similaridade)
resolve isso — só que aplicado *dentro* de cada chamada, sem precisar viver entre etapas. Ver proposta de
design abaixo.

> **Nota de precisão:** a coluna "fator de repetição" é um indicador aproximado (linhas do pool / strings
> de input distintas), não uma contagem exata de chamadas de `jaro_similarity()` pouparia — isso dependeria
> também de quantos candidatos cada linha compara, que não foi medido diretamente. A estimativa de ganho do
> item #9 na tabela §3 (5-6% do tempo total) é derivada desse indicador, não medida ponta a ponta com o
> código alterado.

### 5.4 Proposta de design para o item #9 (dedup intra-etapa)

Ideia: uma tabela `TEMP TABLE` chave-valor, criada uma vez (`CREATE TEMP TABLE IF NOT EXISTS`, mesmo
padrão de `register_unique_logradouros_table()`), que sobrevive a todas as chamadas de
`calculate_string_dist()` dentro de um `geocode_core()`:

```sql
CREATE TEMP TABLE IF NOT EXISTS jaro_pair_cache (
  logradouro_input  VARCHAR,
  logradouro_cnefe  VARCHAR,
  similarity        NUMERIC(5,3),
  PRIMARY KEY (logradouro_input, logradouro_cnefe)
);
```

`calculate_string_dist()` passa a rodar em **dois `dbExecute()`** em vez de um (mais simples e mais seguro
que tentar encadear `INSERT ... RETURNING` dentro de uma CTE que a mesma query já lê depois — evita
depender de semântica de visibilidade de CTE gravável no meio de uma única declaração):

**1) Popula só os pares novos** (mesmo `to_compute` de hoje, só que `DISTINCT` no par, e filtrando o que já
está no cache):

```sql
INSERT INTO jaro_pair_cache
SELECT DISTINCT
    logradouro_input,
    logradouro_cnefe,
    CAST(jaro_similarity(logradouro_input, logradouro_cnefe) AS NUMERIC(5,3)) AS similarity
FROM (
    SELECT
        input_padrao_db.logradouro AS logradouro_input,
        {unique_logradouros_tbl}.logradouro AS logradouro_cnefe
    FROM input_padrao_db
    JOIN {unique_logradouros_tbl} ON {join_condition_lookup}
    WHERE input_padrao_db.similaridade_logradouro IS NULL
      AND input_padrao_db.log_causa_confusao = FALSE
      AND {cols_not_null}
) to_compute
WHERE NOT EXISTS (
    SELECT 1 FROM jaro_pair_cache jc
    WHERE jc.logradouro_input = to_compute.logradouro_input
      AND jc.logradouro_cnefe = to_compute.logradouro_cnefe
);
```

**2) `UPDATE` de hoje, trocando o cálculo inline por leitura do cache** (`to_compute` continua **sem**
`DISTINCT` aqui — cada linha de `input_padrao_db` ainda precisa ver todos os seus candidatos pra rankear):

```sql
WITH to_compute AS (
    SELECT
        input_padrao_db.tempidgeocodebr,
        input_padrao_db.logradouro AS logradouro_input,
        {unique_logradouros_tbl}.logradouro AS logradouro_cnefe
    FROM input_padrao_db
    JOIN {unique_logradouros_tbl} ON {join_condition_lookup}
    WHERE input_padrao_db.similaridade_logradouro IS NULL
      AND input_padrao_db.log_causa_confusao = FALSE
      AND {cols_not_null}
),
computed AS (
    SELECT
        to_compute.tempidgeocodebr,
        to_compute.logradouro_cnefe,
        jaro_pair_cache.similarity,
        RANK() OVER (
          PARTITION BY to_compute.tempidgeocodebr
          ORDER BY jaro_pair_cache.similarity DESC, to_compute.logradouro_cnefe
        ) AS rank
    FROM to_compute
    JOIN jaro_pair_cache
      ON jaro_pair_cache.logradouro_input = to_compute.logradouro_input
     AND jaro_pair_cache.logradouro_cnefe = to_compute.logradouro_cnefe
    WHERE jaro_pair_cache.similarity > {min_cutoff}
)
UPDATE input_padrao_db
   SET temp_lograd_determ = computed.logradouro_cnefe,
       similaridade_logradouro = computed.similarity
  FROM computed
 WHERE input_padrao_db.tempidgeocodebr = computed.tempidgeocodebr
       AND computed.rank = 1;
```

**Por que preserva o comportamento exato de hoje:**
- O cache guarda a similaridade **bruta**, não "passou do corte" — o corte (`min_cutoff`, diferente por
  `match_type` via `get_prob_match_cutoff()`) continua sendo aplicado na leitura (query 2), então o mesmo
  cache serve `pn0k` (corte 0,85/0,90) sem viés entre etapas.
- Critério de desempate (`RANK() ... ORDER BY similarity DESC, logradouro_cnefe`) idêntico, no mesmo lugar.
- `to_compute` da query 2 é byte-a-byte o `to_compute` de hoje — a única mudança é *de onde* vem
  `similarity` (cache em vez de `jaro_similarity()` inline).
- Efeito colateral gratuito: como a tabela sobrevive entre chamadas de `calculate_string_dist()`, o
  reaproveitamento entre etapas (§5.2, ~7%) também acontece — sem custo extra de implementação, já que é o
  mesmo mecanismo só não sendo descartado entre etapas.

**Onde criar a tabela:** dentro da própria `calculate_string_dist()` (`CREATE TEMP TABLE IF NOT EXISTS` no
topo da função), mesmo padrão de `register_unique_logradouros_table()` — não precisa mexer em
`create_geocodebr_db()` nem no laço em `geocode.R`.

**Verificação proposta** (padrão já estabelecido neste repo): capturar output "antes" e "depois" pro mesmo
dataset de 20k, comparar com `identical()` bit a bit, rodar `devtools::test()`, e então medir de novo com
`Rprof()` (mesmo script §5) pra confirmar a magnitude do ganho ponta a ponta — a estimativa de 5-6% em §3 é
uma projeção, não uma medição com o código já mudado.

**Risco a verificar antes de implementar:** confirmar que `INSERT ... SELECT ... WHERE NOT EXISTS` sem
transação explícita se comporta corretamente sob os `n_cores` threads internos do DuckDB (a query 1 é uma
única declaração `INSERT`, então deve ser atômica, mas vale um teste dedicado de concorrência/threads antes
de generalizar).

### 5.5 Processo planejador↔adversário e medição final — item #9 refutado (26/08)

Antes de implementar o design de §5.4, rodou-se o processo pedido pelo mantenedor: um agente **planejador**
(fresh context) refinou o design acima e testou ao vivo em DuckDB 1.5.5 (achou e corrigiu um bug real: PK
composta é implicitamente `NOT NULL` no DuckDB, quebraria se `logradouro_cnefe` fosse `NULL`). Um agente
**adversário** (fresh context, cético por padrão) revisou esse plano e **rejeitou, pedindo redesign**:

1. O design do planejador mantinha `jaro_pair_cache` viva por todo o laço de matching
   (`CREATE TEMP TABLE IF NOT EXISTS`, reaproveitada entre `pn01→pn02→pn03→...`) — o adversário apontou que
   isso reintroduz, sem perceber, exatamente o item #8 já medido e refutado nesta mesma sessão (§5.2). A
   correção: a tabela deveria ser escopada só à chamada atual (criada e dropada dentro da mesma
   `calculate_string_dist()`), não persistida entre etapas.
2. O adversário rodou três microbenchmarks sintéticos em DuckDB 1.5.5 (fatores de repetição 3×-10×, iguais
   ou acima do 1,5×-3,3× medido em produção) e achou o **dedup via join sistematicamente mais lento** que
   recalcular puro (10-33% mais lento nos cenários testados) — evidência de que a estimativa de "5-6% de
   ganho" podia estar errada, inclusive na direção. Recomendação: medir o ganho real, isolado (sem deixar o
   cache sobreviver entre etapas, pra não misturar com a pergunta já fechada do item #8), **antes** de
   escrever o diff de produção.
3. Sugeriu trocar `PRIMARY KEY` recusada + `WHERE NOT EXISTS` por `UNIQUE(...)` + `INSERT ... ON CONFLICT
   DO NOTHING` — mais simples, também evita o problema do `NOT NULL` implícito.

Os dois agentes **não convergiram** (o planejador não foi rechamado para uma segunda rodada — a medição
real, mais barata e mais definitiva que uma segunda rodada de debate, foi feita diretamente). Script:
`tests/tests_rafa/benchmark_jaro_dedup_isolated.R` — mede, isoladamente em cada `pn01`/`pn02`/`pn03` (com
snapshot/restore do estado de `input_padrao_db` entre repetições, cache **sem** sobreviver entre etapas,
seguindo a correção #1 do adversário), variante A (código atual) vs. variante B (dedup via `UNIQUE`+
`ON CONFLICT DO NOTHING`, tabela criada e dropada na mesma chamada), 5 repetições cada, mesma amostra de
20.028 endereços.

**Resultado — refuta o item #9 de forma decisiva, na direção oposta à esperada:**

| etapa | pool | mediana variante A (atual) | mediana variante B (dedup) | ganho | `identical()` |
|---|---|---|---|---|---|
| `pn01` | 13.536 | 0,04 s | 0,22 s | **-450%** | TRUE |
| `pn02` | 10.575 | 0,11 s | 2,14 s | **-1.846%** | TRUE |
| `pn03` | 8.728 | 0,13 s | 2,48 s | **-1.808%** | TRUE |

A lógica está correta (`identical()` confirmado nas três etapas) — só que **5×-18× mais lenta**, não mais
rápida. O adversário estava certo na direção (dedup via join perde para `jaro_similarity()` puro); a
magnitude real é ainda pior do que os microbenchmarks sintéticos sugeriram, provavelmente pelo custo de
criar/dropar `TEMP TABLE` + `INSERT` + `JOIN` extra, que numa etapa como `pn03` precisa lidar com até
~623 mil pares (§5.2) — overhead que supera de longe o custo de `jaro_similarity()`, já vetorizado e barato
no DuckDB.

**Veredito final: item #9 refutado. Nenhuma mudança em `R/string_dist.R`.** Lição geral (reforça o mesmo
padrão do item #4, `TEMP VIEW`, e do item #8): neste código, uma otimização que parece óbvia "no papel"
(evitar recálculo redundante) pode perder para o custo de infraestrutura SQL extra (tabela, join, DDL)
quando a operação que se está tentando evitar já é barata o bastante. Medir sempre antes de implementar.

## Referências

- `quality_reports/diagnoses/2026-08-23_geocode-diagnostico-performance.md`
- `quality_reports/diagnoses/2026-08-23_analise-pacote-desempenho-manutencao.md`
- `quality_reports/diagnoses/2026-08-24_temp-view-benchmark.md`
- `tests/tests_rafa/benchmark_empty_field_guard.R` — script usado na reconfirmação do §2
- `tests/tests_rafa/benchmark_jaro_cache_opportunity.R` — script usado na medição do §5 (overlap entre etapas)
- `tests/tests_rafa/benchmark_jaro_dedup_isolated.R` — script usado na medição do §5.5 (dedup isolado, item #9)
