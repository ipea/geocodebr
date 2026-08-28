# Plano — trata_empates_geocode_duckdb(): itens 2, 3 e 4 (split precoce, BOOL_OR, materialização)

**Status:** ACORDADO E IMPLEMENTADO — veredito adversarial: APROVAR COM MUDANÇAS; acordo = alternativa
simples do adversário (**itens 2+4 apenas, item 3/BOOL_OR descartado**).

**Registro do acordo (26/08):**
- Achado 1 do adversário (CRÍTICO): o ramo E da proposta original, `WHERE eh_perdido` sem o guarda
  `empate = TRUE`, duplicaria ids no output — um grupo de logradouro ambíguo que colapsa para 1
  sobrevivente entraria em D e em E. Aceito integralmente; tornou-se discutível ao descartar o BOOL_OR.
- Achado 2 (MAIOR): após o split, o `NOT EXISTS` atual opera sobre ≤~130 mil linhas (<0,1 s) — o BOOL_OR
  não compra ganho mensurável e foi a fonte do CRÍTICO. Acordo: manter o `NOT EXISTS` de hoje
  (lógica D/E/F textualmente preservada), implementar só o split (item 2) + materialização de
  `empates_classif` como TEMP TABLE real (item 4).
- Achado 3: a ordem de `output_db2` é irrelevante (`merge_results_to_input()` ordena por
  `tempidgeocodebr`) — risco bitwise menor que o previsto.
- Achados 4/6/7 (MENORES): comentários A)–F) transplantados; `ids_empatados` criada antes dos
  early-returns (documentado no código, prepara o item 5); harness ganhou o caso "colapso para 1 com
  logradouro ambíguo" + asserção de não-duplicação de ids.
**Arquivo alvo:** `r-package/R/trata_empates_geocode_duckdb.R` (única função tocada)
**Critério de aceite:** `identical()` bit a bit no benchmark oficial — `r-package/df_sample_empates.parquet`
(1M linhas, 84.238 empates), `n_cores = 1` — mais o harness sintético de todos os ramos
(`test_empates_all_branches.R`, sessão 329a63d2).

## Contexto

Item 1 (anti-join redundante contra `df_sem_empate`) já aplicado e validado. Baseline da etapa de
empates no benchmark oficial: **3,28 s** (pós item 1; HEAD era 3,61 s), de ~108 s totais.

Problemas restantes na query atual:

- (item 2) `base`/`distd`/`filtered` rodam ROW_NUMBER, LAG+haversine, COUNT() OVER e MAX() OVER sobre
  **`output_db` inteiro** (1M linhas), quando só ~168 mil linhas (84.238 grupos × ~2) são empatadas.
  E o passo 1 já paga um `GROUP BY ... HAVING COUNT(*) > 1` cujo resultado é descartado (só a contagem).
- (item 3) `empates_restantes` ainda usa `NOT EXISTS` contra `df_empates_perdidos`, que força reavaliar
  essa CTE (com seus dois regexes) uma segunda vez.
- (item 4) `filtered` é referenciada por 3 CTEs; dependendo da versão do DuckDB, CTE multi-referenciada
  pode ser inlined e o pipeline reexecutado.

## Proposta

Substituir a query única por **três statements**, mantendo semântica idêntica:

### (i) Materializar os ids empatados (reaproveita o passo 1)

```sql
CREATE OR REPLACE TEMP TABLE ids_empatados AS
  SELECT tempidgeocodebr
  FROM output_db
  GROUP BY tempidgeocodebr
  HAVING COUNT(*) > 1;
```

`n_casos_empate` passa a ser `SELECT COUNT(*) FROM ids_empatados` (mesmo valor de hoje). Os ramos
"zero empates" e `resolver_empates = FALSE` ficam **inalterados** (o item 5, fora de escopo aqui,
tratará o FALSE).

### (ii) Pipeline de classificação — só sobre os empatados, linear, materializado

```sql
CREATE OR REPLACE TEMP TABLE empates_classif AS
  WITH
    base AS (
      SELECT o.*,
        ROW_NUMBER() OVER (PARTITION BY tempidgeocodebr
                           ORDER BY contagem_cnefe DESC, desvio_metros, endereco_encontrado) AS id
      FROM output_db o
      WHERE EXISTS (SELECT 1 FROM ids_empatados i WHERE i.tempidgeocodebr = o.tempidgeocodebr)
    ),
    distd AS (
      SELECT b.*,
        haversine(lat, lon,
          LAG(lat) OVER (PARTITION BY tempidgeocodebr ORDER BY id),
          LAG(lon) OVER (PARTITION BY tempidgeocodebr ORDER BY id)) AS dist_geocodebr_metros
      FROM base b
    ),
    filtered AS (
      SELECT d.*,
        (COUNT(*) OVER (PARTITION BY tempidgeocodebr) > 1) AS empate,
        MAX(dist_geocodebr_metros) OVER (PARTITION BY tempidgeocodebr) AS max_dist
      FROM distd d
      WHERE dist_geocodebr_metros IS NULL OR dist_geocodebr_metros > 300
    )
  SELECT f.*,
    (logradouro_encontrado IS NOT NULL
      AND (max_dist > 1000 OR log_causa_confusao
           OR REGEXP_MATCHES(endereco_encontrado, '<regex números por extenso, inalterado>'))
      AND NOT REGEXP_MATCHES(logradouro_encontrado, '<regex datas, inalterado — bug \\b intocado aqui>'))
      AS eh_perdido,
    BOOL_OR(<mesma expressão acima>) OVER (PARTITION BY tempidgeocodebr) AS grupo_perdido
  FROM filtered f;
```

Simplificações válidas porque **todo mundo aqui é empatado por construção**:
- `empate_inicial` e seu `COUNT(*) OVER` somem;
- o `CASE WHEN empate_inicial THEN haversine(...)` vira `haversine(...)` direto (o `LAG` da primeira
  linha é NULL e propaga NULL, exatamente como hoje);
- o WHERE de `filtered` reduz para `dist IS NULL OR dist > 300`.

A cadeia `base → distd → filtered` é linear (cada CTE referenciada uma vez) e o resultado final é uma
**TEMP TABLE real** — resolve o item 4 sem depender do comportamento de `AS MATERIALIZED` da versão
do DuckDB.

Item 3: `eh_perdido` (predicado por linha, idêntico ao WHERE atual de `df_empates_perdidos`) +
`grupo_perdido = BOOL_OR(...)` por janela substituem o `NOT EXISTS`. Semântica preservada:
- E = linhas com `eh_perdido` (o QUALIFY continua ranqueando só entre as linhas que passam, como hoje);
- F = `empate AND NOT grupo_perdido` (um grupo entra em E se *qualquer* linha passa — exatamente o que
  o `NOT EXISTS` contra E expressava).

A expressão aparece duas vezes (coluna + dentro do BOOL_OR) porque SQL não permite referenciar alias
na mesma SELECT; ambas montadas do mesmo fragmento glue no R, então não há risco de divergirem.

### (iii) Montagem final

```sql
CREATE OR REPLACE TEMP TABLE output_db2 AS
  -- não-empatados: passthrough, zero window functions (~83% das linhas do 1M)
  SELECT tempidgeocodebr, lat, lon, tipo_resultado, desvio_metros, endereco_encontrado {cols_passthrough}
  FROM output_db o
  WHERE NOT EXISTS (SELECT 1 FROM ids_empatados i WHERE i.tempidgeocodebr = o.tempidgeocodebr)
  UNION ALL
  -- D: viraram únicos após o colapso de 300 m
  SELECT ... FROM empates_classif WHERE empate = FALSE
  UNION ALL
  -- E: perdidos — fica o top do ranking
  SELECT ... FROM empates_classif WHERE eh_perdido
  QUALIFY ROW_NUMBER() OVER (PARTITION BY tempidgeocodebr
                             ORDER BY contagem_cnefe DESC, desvio_metros, endereco_encontrado) = 1
  UNION ALL
  -- F: salváveis — média ponderada por contagem_cnefe
  SELECT tempidgeocodebr, lat_wavg AS lat, lon_wavg AS lon, ... FROM (
    SELECT c.*,
      SUM(lat * contagem_cnefe) OVER (PARTITION BY tempidgeocodebr)
        / NULLIF(SUM(contagem_cnefe) OVER (PARTITION BY tempidgeocodebr), 0) AS lat_wavg,
      SUM(lon * contagem_cnefe) OVER (PARTITION BY tempidgeocodebr)
        / NULLIF(SUM(contagem_cnefe) OVER (PARTITION BY tempidgeocodebr), 0) AS lon_wavg
    FROM empates_classif c
    WHERE empate AND NOT grupo_perdido
  ) QUALIFY ROW_NUMBER() OVER (...) = 1;
```

Detalhe de colunas com `resultado_completo = TRUE`: o passthrough precisa de `FALSE AS empate` na
posição em que `additional_cols_final` hoje põe `empate` — vira um fragmento glue próprio
(`cols_passthrough`); D/E/F seguem usando os fragmentos atuais.

## O que NÃO muda

- Ordem de ranqueamento (`contagem_cnefe DESC, desvio_metros, endereco_encontrado`) — determinismo
  conquistado em 25/08 intocado.
- Os dois regexes (números por extenso e datas) — o bug do `\\b` fica para o item 6, senão o
  `identical()` deixa de ser critério.
- Ramos zero-empates e `resolver_empates = FALSE`.
- Macro `haversine`, colunas e schema do output.

## Riscos conhecidos

1. **Ulp em F (wavg):** a reestruturação muda o plano que alimenta o `SUM() OVER` da média ponderada;
   mesmo com `n_cores = 1`, se a ordem física das linhas na partição mudar, a soma FP pode divergir no
   último bit. O item 1 (que também mudou o plano) passou bitwise com `n_cores = 1`, mas não é garantia.
   Mitigação se ocorrer: diagnosticar se as diferenças são só ulp em `lat`/`lon` de linhas F e decidir
   conscientemente (aceitar com `all.equal` + documentar, ou forçar ordem de acumulação).
2. **Custo do EXISTS/NOT EXISTS contra `ids_empatados`:** dois hash semi/anti-joins de 1M × 84k. Deve
   ser muito mais barato que as window functions que substitui, mas o benchmark decide.
3. **`SELECT f.*` carrega colunas de trabalho** (`id`, `dist_geocodebr_metros`, `max_dist`, `eh_perdido`,
   `grupo_perdido`) para `empates_classif` — tabela pequena (~130k linhas pós-colapso), irrelevante.

## Resultado (26/08, pós-implementação)

Benchmark oficial (1M, `n_cores = 1`, baseline = pós item 1 vs itens 2+4):

| | baseline (item 1) | itens 2+4 |
|---|---|---|
| Total | 102,9 s | 100,0 s |
| Etapa de empates | 3,34 s | **1,47 s** (−56%) |
| `n_casos_empate` | 84.238 | 84.238 |
| `identical()` | — | **TRUE** (bit a bit) |

Harness sintético (10 grupos, todos os ramos + caso do achado 7 + asserção de não-duplicação):
`identical() = TRUE`; id6 (exceção rua-data) falha igualmente nas duas versões — bug conhecido do
`\\b`, intocado de propósito nesta rodada.

Série da etapa de empates no benchmark oficial: HEAD 3,61 s → item 1: 3,28-3,34 s → itens 2+4: 1,47 s.

## Verificação

1. Harness sintético de todos os ramos (old vs new) — bitwise.
2. `small_sample.csv` via `geocode_core()` — bitwise.
3. Benchmark oficial: 1M, `n_cores = 1`, HEAD-do-working-tree (pós item 1) vs nova versão —
   `identical()` + tempos (total e etapa de empates).
