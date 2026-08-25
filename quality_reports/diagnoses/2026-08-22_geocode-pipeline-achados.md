# Achados da revisão do pipeline de `geocode()` — 2026-08-22

Revisão de código de `R/geocode.R` e dependências (`match_*.R`, `string_dist.R`,
`register_cnefe_tables.R`, `trata_empates_geocode_duckdb.R`, `utils.R`).

O pipeline em si está documentado em [`CLAUDE.md`](../../CLAUDE.md) — "Notas sobre pipeline de cada função".
Este arquivo registra apenas o que parece **defeito ou divergência**, não o funcionamento normal.
Nada aqui foi corrigido; são achados para decisão do mantenedor.

Todos os itens marcados como *verificado* foram reproduzidos empiricamente contra o DuckDB, não inferidos
por leitura.

---

## 1. CRÍTICO — `resultado_completo = TRUE` + zero empates gera erro de SQL

**Verificado.** Reproduzido com o schema exato de `output_db`.

`merge_results_to_input()` (`R/utils.R:161-173`) inclui `'empate'` nas colunas selecionadas quando
`resultado_completo = TRUE`. Mas a coluna `empate` **não existe** em nenhum dos dois schemas de `output_db`
(`R/geocode.R:343-378`) — ela só é criada dentro de `output_db2`, em
`trata_empates_geocode_duckdb()`.

Quando não há nenhum empate, `trata_empates_geocode_duckdb()` retorna cedo (linha 21-23), `output_db2`
nunca é criada, e `geocode.R:482-486` seleciona `output_table_to_use <- 'output_db'`. O `LEFT JOIN`
seguinte então pede `output_db.empate`:

```
Binder Error: Table "output_db" does not have a column named "empate"
```

**Por que passa despercebido:** o teste que usa `resultado_completo = TRUE`
(`tests/testthat/test-geocode.R:52`) roda sobre o `small_sample.csv` **inteiro**, que produz empates.

**Atualização 2026-08-23 — o bug é mais fácil de atingir do que se estimou inicialmente.** Reproduzido ao
vivo, com dados reais do CNEFE, usando apenas **as 3 primeiras linhas** do próprio `small_sample.csv` do
pacote:

```r
df <- read.csv(system.file("extdata/small_sample.csv", package = "geocodebr"))[1:3, ]
geocode(df, campos, resultado_completo = TRUE)
#> Binder Error: Table "output_db" does not have a column named "empate"
```

Ou seja, não é preciso um input artificial: qualquer tabela pequena o bastante para não gerar empate
derruba a função. A avaliação original de que "dados reais quase sempre têm pelo menos um empate" estava
errada.

**Correção possível:** incluir `empate BOOLEAN` nos schemas de `output_db` com default `false`, ou tratar
o caso `empates_resolvidos == 0` em `merge_results_to_input()`.

---

## 2. CRÍTICO — o ramo "empates perdidos" nunca dispara com `resultado_completo = FALSE`

**Verificado.** Semântica de três valores do SQL reproduzida no DuckDB.

Em `trata_empates_geocode_duckdb.R:167`, a CTE `df_empates_perdidos` termina com:

```sql
AND NOT REGEXP_MATCHES(logradouro_encontrado, '\bDE (JANEIRO|...|DEZEMBRO)\b')
```

Mas `logradouro_encontrado` só é **populado** quando `resultado_completo = TRUE` — é injetado via
`colunas_encontradas`, que é a string vazia no caso contrário (`match_cases.R:34-66` e equivalentes nas
outras três funções de match). Com `resultado_completo = FALSE` a coluna existe no schema mas fica sempre
`NULL`, e `NOT REGEXP_MATCHES(NULL, ...)` avalia para `NULL`, que não é `TRUE` — a linha é descartada.

**Consequência:** com `resultado_completo = FALSE` (o padrão), `df_empates_perdidos` é **sempre vazia**.
Todos os empates que deveriam ser resolvidos pelo maior `contagem_cnefe` (distância > 1 km, logradouro
ambíguo) caem em `empates_restantes` e recebem **média ponderada de coordenadas** — exatamente o
tratamento que a documentação diz ser reservado a ruas próximas e não ambíguas.

Ou seja: **`geocode()` pode devolver coordenadas diferentes para o mesmo endereço dependendo apenas do
valor de `resultado_completo`**, que deveria controlar só quais colunas aparecem no output.

O mesmo vale, mesmo com `resultado_completo = TRUE`, para os `match_type` sem logradouro
(`dc01`, `dc02`, `db01`, `dm01`), em que `logradouro_encontrado` também fica `NULL`.

**Correção possível:** `COALESCE(logradouro_encontrado, '')` no regex, ou usar `endereco_encontrado`
(sempre populado) como já é feito duas linhas acima.

---

## 3. MÉDIO — `max_dist` mede saltos consecutivos, não a dispersão real

**Verificado.**

Em `trata_empates_geocode_duckdb.R:110-116` a distância entre candidatos empatados usa
`LEAD(...) OVER (PARTITION BY tempidgeocodebr ORDER BY id)` — ou seja, cada linha é comparada apenas com a
**seguinte**. `max_dist` é o maior salto consecutivo, não a maior distância entre pares.

Com 3 candidatos colineares espaçados de ~600 m, o teste reproduziu `max_dist = 601` enquanto os extremos
estão a **1202 m**. Como o corte de "empate perdido" é `max_dist > 1000`, esse caso é classificado como
"salvável" e recebe média ponderada, embora os pontos estejam a mais de 1 km — a situação que a regra
pretendia excluir.

---

## 4. MÉDIO — filtro de 300 m não documentado, e mantinha o candidato de *menor* `contagem_cnefe`

**4a — candidato errado preservado: CORRIGIDO em 2026-08-22.**

As linhas são ordenadas por `contagem_cnefe DESC`, e a linha descartada era a que tinha o `LEAD` curto —
isto é, a **primeira**. Num empate de 2 candidatos a menos de 300 m, sobrevivia a linha de **menor**
`contagem_cnefe`, porque a última linha da partição sempre tem `LEAD = NULL` e era preservada pela
cláusula `dist_geocodebr_metros IS NULL`. Isso contrariava a intenção declarada na documentação
("retornar o ponto com maior número de estabelecimentos").

Correção aplicada: `LEAD` → `LAG` na CTE `distd`. Como `id` já ordena por `contagem_cnefe DESC`, medir a
distância contra a linha *anterior* faz com que o descartado seja sempre o de menor `contagem_cnefe`, e a
linha `id = 1` (maior `contagem_cnefe`) tenha `dist = NULL` e seja sempre preservada.

Verificado que a troca **não** altera `max_dist`, a contagem de linhas mantidas, nem a coluna `empate` —
todo *gap* > 300 m continua ancorado numa linha preservada, apenas em outra linha do mesmo par. Portanto a
classificação de "empate perdido" (> 1 km) permanece idêntica. Ver entrada em `NEWS.md`.

**4b — limiar de 300 m não documentado: CORRIGIDO em 2026-08-23.**

O limiar não aparecia em `man/roxygen/templates/empates_section.R`, que descrevia apenas a regra de 1 km.
A etapa de 300 m foi acrescentada como **item 1** da lista (é a primeira a rodar no código, antes da
classificação de 1 km), e os itens existentes foram renumerados para 2 e 3. `man/geocode.Rd` regenerado
via `devtools::document()` — `geocode()` é a única função que usa esse template.

---

## 5. MÉDIO — a documentação promete `pn04`, `pa04` e `pl04`, que o pacote nunca produz

`man/roxygen/templates/precision_section.R` lista `pn04`, `pa04` e `pl04` entre as categorias de
`tipo_resultado`. Mas em `R/utils.R:282-308` esses três estão **comentados** no vetor
`all_possible_match_types`, com a justificativa `# too costly`:

```r
"dn04", "da04", #"pn04", "pa04", # too costly
"dl04", # pl04",  # too costly
```

O laço percorre 25 etapas; essas 3 nunca rodam. `add_precision_col()` ainda as mapeia, o que é inofensivo,
mas a documentação do usuário descreve resultados impossíveis.

---

## 6. BAIXO — `create_geocodebr_db(db_path = 'memory')` cria um arquivo chamado `memory`

Em `R/create_geocodebr_db.R:18-26`, o ramo `db_path == 'memory'` abre uma conexão `:memory:` e a atribui a
`con` — mas as linhas seguintes **sobrescrevem `con`** com uma nova conexão usando `dbdir = db_path`, que
ainda vale a string `"memory"`. O resultado é um arquivo DuckDB em disco chamado `memory`, e a primeira
conexão fica órfã.

Latente: `geocode()` sempre usa o default `"tempdir"`. Só afeta quem chamar a função interna diretamente.

---

## 7. INFORMATIVO — `arrow::float16()` para `lat`/`lon` não causa perda de precisão

**Verificado — não é bug.** Investiguei porque `float16` teria ~3 dígitos significativos, o que seria
catastrófico para coordenadas (erro de ~1,5 km em latitude).

Na prática o DuckDB mapeia `arrow::float16()` para **`DOUBLE`**. Um round-trip de `-23.5505199` volta
exato, com erro 0. Não há perda.

Fica o registro apenas porque o comentário no código (`R/geocode.R:345`, "Equivalent to NUMERIC(8,6)")
está errado e pode induzir alguém a "corrigir" o tipo para algo pior. O `float16` é enganoso, não danoso.

---

## Resumo

| # | Severidade | Item |
|---|---|---|
| 1 | Crítico | `resultado_completo = TRUE` + zero empates → Binder Error |
| 2 | Crítico | `resultado_completo` altera as coordenadas retornadas, via `logradouro_encontrado` NULL |
| 3 | Médio | `max_dist` usa saltos consecutivos (`LEAD`), não dispersão entre pares |
| 4a | ~~Médio~~ | ~~Preservava o candidato de menor `contagem_cnefe`~~ — **corrigido** (`LEAD` → `LAG`) |
| 4b | ~~Médio~~ | ~~Limiar de 300 m não documentado~~ — **corrigido** (`empates_section.R`) |
| 5 | Médio | `pn04`/`pa04`/`pl04` documentados mas desativados |
| 6 | Baixo | `db_path = 'memory'` cria arquivo em disco |
| 7 | Informativo | `float16` → `DOUBLE`, sem perda (não é bug) |
