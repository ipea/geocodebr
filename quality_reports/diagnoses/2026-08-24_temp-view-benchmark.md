# TEMP VIEW em `register_cnefe_table()` — benchmark ponta a ponta e reversão — 2026-08-24

**Resultado: mudança testada e revertida.** O benchmark isolado do relatório de 23/08 (§3) não se sustentou
ponta a ponta — o pipeline real ficou **mais lento**, não mais rápido, apesar da função-alvo em si ter
ficado 3,5× mais rápida. `R/register_cnefe_tables.R` está de volta ao `CREATE TEMP TABLE` original.

---

## Metodologia

- Amostra: `inst/extdata/large_sample.parquet` (20.028 endereços, mesma amostra do relatório de 23/08).
- Cache local do CNEFE já presente (release `v0.4.1`, 8 parquets, ~1,46 GB) — sem download.
- Benchmark chamou `geocodebr:::geocode_core()` diretamente após `devtools::load_all('.')` — **não**
  `geocode()`, que roda via `callr::r(..., package = TRUE)` e carregaria a versão instalada do pacote, não
  o source modificado (`[LEARN:testes]` em MEMORY.md).
- Rodadas por versão do código (antes = `TEMP TABLE`, depois = `TEMP VIEW`):
  1. Corretude: uma chamada com `n_cores = 1`, `resultado_completo = TRUE`, `resolver_empates = TRUE`.
  2. Tempo total: `bench::mark(iterations = 5)` com `n_cores = 7`.
  3. Tempo por fase: `Rprof()`/`summaryRprof()` em uma chamada com `n_cores = 7`.
- Script: `tests/tests_rafa/benchmark_temp_view.R` (mantido no repo para reprodução futura).

## Resultado — tempo total (`bench::mark`, n_cores = 7, mediana de 5 iterações)

| | `TEMP TABLE` (antes) | `TEMP VIEW` (depois) | Δ |
|---|---|---|---|
| `geocode_core()` — mediana | **4,18 s** | **5,92 s** | **+42% (pior)** |
| `geocode_core()` — mínimo | 4,14 s | 5,87 s | +42% |

## Resultado — tempo por fase (`Rprof`, uma chamada, n_cores = 7)

| Função | `TEMP TABLE` | `TEMP VIEW` | Δ |
|---|---|---|---|
| `register_cnefe_table` (total.time) | 1,51 s (39,2% do tempo amostrado) | **0,43 s (7,8%)** | **-72% (melhor, como previsto)** |
| `rapi_execute` (self.time — execução real das queries no DuckDB) | 3,02 s | **4,51 s** | **+49% (pior)** |
| `match_fun` (total.time — os joins de match propriamente ditos) | 3,28 s | 5,07 s | +55% |
| Tempo total amostrado (`sampling.time`) | 3,85 s | 5,51 s | +43% |

**A função que a mudança visava ficou de fato mais rápida — 3,5× mais rápida — exatamente como previsto pelo
benchmark isolado.** Mas o tempo que ela deixou de gastar reaparece, multiplicado, dentro de `rapi_execute`:
cada uma das ~25 etapas do laço de matching que faz `JOIN`/`INSERT` contra uma dessas 8 tabelas agora
força o DuckDB a reabrir e refiltrar o parquet subjacente **a cada consulta**, em vez de uma vez só. A
tabela mais usada serve ~10 etapas; a hipótese do benchmark isolado (ponto de virada em ~12 usos, joins
sintéticos de uma coluna) não previu que os joins reais do pacote (múltiplas colunas-chave, CTEs
`unique_munis`/`unique_states`, interpolação por `1/ABS(numero-numero_cnefe)`, `GROUP BY ... FIRST()`) são
caros o bastante por consulta para que o custo de reabrir a view **10 vezes** supere de longe o custo de
materializar a tabela **1 vez**. O benchmark isolado testava o padrão errado de consulta.

## Corretude — achado colateral não trivial

Com `n_cores = 1` em ambas as rodadas (para eliminar o não-determinismo já documentado de `FIRST()` sem
`ORDER BY` — `[LEARN:duckdb]`), o output **ainda assim divergiu em 4 de 20.028 linhas** (`lat`/`lon`/
`desvio_metros`/`endereco_encontrado`/`contagem_cnefe`/`cod_setor`), todas em `da02`/`da04` — exatamente a
família já sinalizada como afetada pelo `FIRST()` sem `ORDER BY` em `match_weighted_cases.R`. Diferença de
posição entre 516 m e 4.915 m (mediana ~1,1 km).

Isso **não é um bug novo introduzido pela troca TABLE→VIEW** — é o mesmo bug pré-existente, só que exposto
por uma causa adicional: a entrada no MEMORY.md registrava a não-determinismo como dependente de
paralelismo (`n_cores > 1`), verificado estável em `n_cores = 1`. Aqui, com `n_cores = 1` fixo dos dois
lados, a *ordem física de scan* mudou porque a fonte mudou de tabela materializada para view sobre parquet
— e isso bastou para `FIRST()` escolher um candidato empatado diferente em 4 linhas. Ou seja: `n_cores = 1`
neutraliza o paralelismo, mas não é garantia de estabilidade se qualquer outra coisa que afete a ordem de
scan mudar (incluindo o formato de armazenamento da tabela de origem).

## Decisão

**Revertido.** `R/register_cnefe_tables.R` voltou a `CREATE TEMP TABLE IF NOT EXISTS` (diff confirmado
vazio contra o `HEAD` após a reversão). `register_unique_logradouros_table()` nunca foi alterada.

## O que isso ensina sobre a próxima tentativa nessa direção

Se a materialização ainda for alvo de otimização no futuro, a direção certa não é eliminar a tabela
temporária — é **reduzir o volume materializado antes das etapas de matching**, não trocar o mecanismo de
leitura por etapa. Ex.: já materializar só as colunas/linhas necessárias por família de `match_type`, ou
materializar uma única vez por (estado, município) num escopo mais restrito. Qualquer proposta futura nessa
linha precisa ser validada com o pipeline real (como aqui), não só com joins sintéticos — o benchmark
isolado do relatório de 23/08 tinha a ressalva explícita de não ter sido testado ponta a ponta, e a ressalva
se confirmou.

## Referências

- `quality_reports/diagnoses/2026-08-23_geocode-diagnostico-performance.md` §3 — hipótese original.
- `quality_reports/plans/tender-giggling-galaxy.md` — plano aprovado para este teste.
- `tests/tests_rafa/benchmark_temp_view.R` — script de benchmark reutilizável.
