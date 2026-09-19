# Plano — eficiência de `geocode()` em escala real (43,9M) — 2026-09-19

**Status:** APROVADO 19/09 → IMPLEMENTADO E MEDIDO (resultados em `quality_reports/diagnoses/2026-09-19_geocode-benchmark-43M.md`)
**Pedido do usuário:** benchmark completo de `geocode()` com `df_full_data.parquet` para achar as
etapas mais caras; 5 agentes independentes propõem estratégias de baixo esforço/alto ganho; consolidar,
ranquear por ganho ÷ intervenção; depois testar cada ação com o mesmo benchmark e resumir numa tabela
(tempo e memória).

## 1. Contexto

`geocode()` já passou por várias rodadas de otimização (ver `MEMORY.md` e
`quality_reports/diagnoses/2026-08-24_geocode-eficiencia-consolidado.md`). O mapa de custo anterior
(27/08) era: matching ~50%, padronização ~19%, merge ~19%. Esta rodada re-mediu com instrumentação
por função **dentro do subprocesso do `callr`** (harness `prof_geocode.R`, no scratchpad da sessão:
envolve cada função interna com timer + `ps::ps_memory_info()` + `duckdb_memory()`; usa o pacote
instalado da working tree numa biblioteca privada, exatamente como `geocode()` faz) e, pela primeira
vez, mediu também o custo do **transporte entre processos** e a **memória** ponta a ponta.

## 2. Benchmark base — 43.882.020 endereços, `n_cores` default (16), 256 GB RAM, 18/09/2026

| Bloco | s | % do total |
|---|---:|---:|
| **Total `geocode()` (parede, do chamador)** | **1112** | 100 |
| Transporte `callr` (serializar input 43,9M×7 p/ o filho + resultado 6,9 GB de volta) | **246** | 22 |
| Padronização (`enderecobr::padronizar_enderecos`) | 126 | 11 |
| ↳ logradouros 44 · números 20 · CEPs 16,5 · municípios 14,6 · bairros 12 · estados 9 · cópia `as.data.table` ~9 | | |
| Preparação R pós-padronização (`.SD`, renames, ids) | 7 | 1 |
| `dbWriteTable(input_padrao_db)` + schema `output_db` | 21 | 2 |
| **Laço de matching (25 etapas)** | **557** | 50 |
| ↳ `calculate_string_dist` (Jaro) | 337 | 30 |
| ↳ queries `INSERT` de match | 133 | 12 |
| ↳ `register_cnefe_table` | 53 | 5 |
| ↳ `update_input_db` (DELETE) | 32 | 3 |
| `trata_empates_geocode_duckdb` | 14 | 1 |
| `dbWriteTable(input_db)` (input original de volta p/ o join) | 20 | 2 |
| `add_precision_col` | 2 | 0 |
| `merge_results_to_input` (JOIN + ORDER BY + `dbGetQuery` p/ o R) | 102 | 9 |
| Pós-processamento R (setDT/setDF) | 3 | 0 |

Jaro por etapa: pn01 13 s · **pn02 130 s** · pn03 17 s · pl01 8 s · **pl02 133 s** · pl03 36 s.
INSERT por etapa: **da01 41 s** · **da02 29 s** · da04 8,5 s · da03 7,7 s · pa01 7 s · demais < 5 s
(dn01 casa 7,7M linhas em 4,4 s — o join exato é barato; o ponderado é ~10× mais caro por linha).
`register_cnefe_table`: dn01 15,7 s e da03 26,7 s (as duas tabelas de 50M linhas; com 5.570
municípios no input o filtro não corta nada — medido: filtro é grátis, 19,7 vs 20,7 s).

**Memória.** Processo filho: pico de **82 GB** de working set (durante o merge). DuckDB cresce
monotonicamente e nunca libera: 5,7 GB (input) → 17,9 (após dn01) → 32,6 (após da03) → 38,7 (fim do
laço) → 45,4 (empates: `output_db2` é cópia integral) → 51,4 GB (após `input_db`). Nada é dropado.
No pico do merge só `output_db2` (~5 GB) e `input_db` (~6 GB) são necessários — ~40 GB é peso morto.
Processo pai: pico 9,3 GB. Nesta máquina nada foi para disco (`temporary_storage_bytes = 0`); num
laptop de 16-32 GB a mesma corrida faria spill pesado — reduzir memória do DuckDB também é tempo
para o usuário típico.

## 3. Sugestões consolidadas (5 agentes: A Jaro · B fronteira de processo · C SQL/DuckDB · D padronização · E memória)

Ordenadas por **ganho ÷ intervenção**. Ganhos são estimativas dos agentes (várias com
micro-medição em DuckDB 1.5.5 / amostra de 1M); a medição real em 43,9M é a Fase 2.

| # | Ação | Origem | Mecanismo (resumo) | Ganho estimado @43,9M | Linhas | Risco p/ identidade do output |
|---|---|---|---|---|---:|---|
| **1** | **Pular Jaro em `pl01/pl02/pl03` para linhas com `numero IS NOT NULL`** | A3 | Essas linhas já foram testadas em `pn0k` contra a mesma `unique_logr_*`, mesma chave e mesmo corte; `similaridade` só é setada, nunca limpa → recalcular é no-op provado (0 acertos em 20k; essas linhas são 56-90% dos pares) — mesmo princípio de `match_types_jaro_redundante` | **−100 a −130 s** | ~4 (`string_dist.R`) | nenhum |
| **2** | **`SELECT DISTINCT` na chave realmente usada ao juntar `unique_logr_*`** | A2 | A tabela `unique_logr_..._cep_localidade` é criada em pn01 com `localidade`; pn02/pl02 juntam sem `localidade`, então cada logradouro-candidato aparece uma vez **por localidade** do CEP → 2,1× pares a mais e rank-1 duplicado (o `UPDATE … FROM` engole em silêncio) | −45 a −100 s | 1-4 (`string_dist.R` ou `register_cnefe_tables.R`) | nenhum |
| **3** | **`duckdb_register()` (zero-cópia) para `input_db`** | B3 / E4 | `input_db` só é lido uma vez pelo join final; `dbWriteTable` é `register + CTAS`, então tipos são idênticos por construção | −14 a −20 s; **−6 GB DuckDB** | 1-3 (`geocode.R`) | nenhum (verificado `identical()` em 5M com tipos mistos) |
| **4** | **`DELETE` só dos ids da etapa corrente** (`WHERE tipo_resultado = '{match_type}'`) | C2 | Hoje o `IN (SELECT … FROM output_db)` varre a `output_db` inteira 25×; invariante `input ∩ output = ∅` garante contagem idêntica | −15 s | ~8 (`utils.R` + 4 `match_*.R`) | nenhum |
| **5** | **Padronizar por campo sobre `unique()` e expandir com `chmatch()`** (em vez de `padronizar_enderecos()` na tabela inteira) | D1 | Funções `padronizar_*` são puras/elemento a elemento (verificado); campos de baixa cardinalidade (estado 27, município 5.570, número, CEP) ganham quase tudo; elimina a cópia `as.data.table` do enderecobr e o `.SD` | **−65 a −80 s; −3,5 GB** | ~25 (`geocode.R` + helper em `utils.R`) | nenhum no output (1M `identical()`); muda rótulo `call` de warnings; índice de erro de CEP preservado via rerun no vetor cheio |
| **6** | **Chave estreita no `GROUP BY` das queries ponderadas** (`da*`/`pa*`): regex uma vez por grupo | C1 | Hoje `REGEXP_REPLACE` roda por linha-candidata (fan-out médio 17-21 números por logradouro) e a chave de grupo é uma string de ~70 bytes; agrupar por `tempidgeocodebr, numero [, cep, localidade livres]` e aplicar o regex sobre `FIRST(endereco_completo …)`. Prova de equivalência feita sobre o CNEFE v0.5.0 (0 violações) | **−60 s**; menos memória transitória | ~24 (2 arquivos) | baixo — depende de invariantes dos dados (regex casa exatamente 1×, string constante por grupo); diferenças em `lat/lon` ≤ 9e-14 (= ruído entre corridas). Adicionar as 3 queries-prova como teste |
| **7** | **Resultado sai do filho como parquet (`COPY … TO`), pai lê com `arrow::read_parquet`** | B1 | Elimina o `dbGetQuery` de 43,9M linhas no filho **e** a serialização RDS de 6,9 GB de volta (~160 s dos 246 s de transporte); DuckDB escreve parquet multi-thread | **−185 s**; filho −7 GB | ~60 (`geocode.R`, `utils.R`: pós-processamento H3/sf/ghost cols migra para o pai) | médio: `factor` e `POSIXct` do input precisam de restauração no pai (4 linhas, verificado); `arrow.use_altrep = FALSE`; ordem preservada (verificado) |
| **8** | **Dedup do lado do input por chave + `FIRST/MAX` no lugar de `RANK()`** no Jaro | A1+A4 | rank-1 é função pura de (chave, logradouro_input); `DISTINCT` antes do Jaro, join-back depois (sem tabela extra, sem `ON CONFLICT` — diferente do item #9 refutado em agosto); agregado 1,4× mais barato que window | −40 a −120 s (razão de dedup real em 43,9M desconhecida: 1,1 em 20k, 5,2 sintético) | ~25 (`string_dist.R`) | nenhum se o filtro de elegibilidade for repetido no `WHERE` do `UPDATE` |
| **9** | **Dropar tabelas de referência após o último uso + `input_padrao_db` após o laço + `output_db`/`ids_empatados`/`empates_classif` quando `output_db2` existe** | E1/E2/E3 · C3 | `DROP` libera memória imediatamente (medido; sem `CHECKPOINT`); as duas tabelas de 50M morrem em pa02/pn03 e da04 | **−27 GB no laço, ~−40 GB no pico do merge**; ~0 s aqui, grande em máquinas com pouca RAM | ~20 (`geocode.R`, `utils.R`, `trata_empates…R`) | nenhum |
| **10** | **Liberar objetos R no filho**: `rm(input_padrao)` após o `dbWriteTable`; `:= NULL` em vez da cópia `.SD` | E5 / B5 / D2 | Só `nrow()`/`names()` são usados depois | −5 GB no pico; ~−5 s | ~10 | nenhum |
| **11** | **Projeção de colunas em `register_cnefe_table`** (`EXCLUDE code_muni, n_setor`, `cod_setor` só com `resultado_completo`) | E7 / C4 | Colunas nunca lidas; −10 % por tabela grande | −2,5 GB; 0 a −10 s | ~6 | nenhum |
| **12** | **Tirar `similaridade_logradouro` do schema de `output_db` quando `resultado_completo = FALSE`** | E6 | Coluna nunca preenchida nesse caminho, mas segmentos DOUBLE alocados | −350 MB | 1 | nenhum |
| 13 | Input cruza como parquet (`col_select` só das colunas de endereço) | B4 | Substitui `saveRDS/readRDS` do input (~85 s) | −40 a −60 s | ~40 | médio (tipos do input) — só faz sentido depois do 7 |
| 14 | Só colunas novas saem do filho; `cbind` raso no pai (`resolver_empates = TRUE`) | B2 | Join `range(1,n+1) ⟕ output_db2` no DuckDB; pai só anexa vetores | −45 s além do 7; −20 s do `input_db` | +25 | **decisão do mantenedor**: o join continua no DuckDB, mas o `cbind` no pai pode ser lido como "juntar no R" |
| 15 | Empates sem cópia integral (`DELETE` empatados + `INSERT` resolvidos + `RENAME`) | E3b / C6 | Evita o passthrough de 92 % das linhas | ~−8 s; −5 GB | ~30 | médio (alinhamento de colunas) |

**Refutado pelos agentes nesta rodada (não testar):** `SET preserve_insertion_order = false`
(CTAS do parquet fica 50 % mais lento; INSERT igual); pré-filtro por razão de comprimento no Jaro
(bound provado, mas o predicado custa mais que o `jaro_similarity`); `arg_min` por coluna no lugar de
`FIRST(… ORDER BY)` (2× mais lento e **não idêntico** — pula NULLs); compactação periódica de
`input_padrao_db` (vetores totalmente deletados já são pulados; rebuild custa 3-5 s cada); pular o
filtro de municípios em `register_cnefe_table` (é grátis); `dbGetQueryArrow` no fetch (não robusto,
mais lento em 5M); remover o `CAST(… AS NUMERIC(5,3))` (é o que define o arredondamento do corte).

## 4. Fase 2 — protocolo de teste (o que vai acontecer após a aprovação)

**Nota sobre o modelo:** o pedido diz "change to model opus" antes de testar. Eu não consigo trocar
o meu próprio modelo; o usuário pode fazê-lo com `/model opus` ao aprovar este plano. Se não trocar,
sigo no modelo atual e delego a implementação de cada patch a subagentes Opus, mantendo a
orquestração dos benchmarks comigo.

1. **Um patch por ação, isolado**, aplicado à working tree e instalado em biblioteca própria
   (`R CMD INSTALL -l lib_<id>`), começando pela ordem da tabela (1 → 12). Antes de cada
   instalação, a working tree é restaurada ao estado atual (patches ficam guardados como `.patch`
   em `quality_reports/diagnoses/2026-09-19_patches/`).
2. **Corretude primeiro**: `devtools::test()` + `geocode()` no 1M (`df_sample_empates.parquet`,
   `n_cores = 1`) comparado por `identical()` com o baseline 1M (rodado uma vez no início). Falhou →
   ação marcada como reprovada, sem benchmark.
3. **Benchmark 43,9M** com o mesmo harness (`geocode()` completa via `callr`, um `Rscript` por
   braço): 1 corrida por ação, mais um **segundo baseline** no meio da sequência e outro no fim,
   para medir a dispersão entre corridas do mesmo código (~19 min por corrida; ~14 corridas
   ≈ 4,5 h). As ações de memória (9-12) são medidas juntas numa corrida "bundle", com o efeito
   individual lido da trajetória de `duckdb_memory()` por etapa.
4. **Cumulativo**: as ações aprovadas são acumuladas numa única working tree e medidas juntas no
   final (tempo + memória), com `identical()` no 1M.
5. **Entrega**: tabela final (ação · descrição · Δ tempo s/% · Δ pico de memória filho/pai/DuckDB ·
   veredito), relatório em `quality_reports/diagnoses/2026-09-19_geocode-benchmark-43M.md`, log de
   sessão, entradas `[LEARN]` no `MEMORY.md`. **Nada é commitado** sem pedido explícito; a working
   tree fica com o cumulativo aprovado aplicado (ou limpa, se o usuário preferir).

## 5. Arquivos-alvo

`r-package/R/string_dist.R` (1, 2, 8) · `r-package/R/geocode.R` (3, 5, 7, 9, 10, 12) ·
`r-package/R/utils.R` (4, 5, 7, 9) · `r-package/R/match_weighted_cases.R` e
`match_weighted_cases_probabilistic.R` (6) · `r-package/R/match_*.R` (4) ·
`r-package/R/register_cnefe_tables.R` (2, 11) · `r-package/R/trata_empates_geocode_duckdb.R` (9).
