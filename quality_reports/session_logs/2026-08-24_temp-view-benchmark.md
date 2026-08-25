# Log de sessão — 2026-08-24 — TEMP VIEW em register_cnefe_table()

**Objetivo:** validar ponta a ponta (não mais isolado) a hipótese do relatório de 23/08 de que trocar
`CREATE TEMP TABLE` por `CREATE TEMP VIEW` em `register_cnefe_table()` reduz o tempo de `geocode_core()`,
usando a amostra real de 20.028 endereços (`inst/extdata/large_sample.parquet`) contra o cache local do
CNEFE (release v0.4.1, já presente).

## Abordagem

- Mudança escopada só em `register_cnefe_table()` (`R/register_cnefe_tables.R`); `register_unique_logradouros_table()`
  fica intacta — padrão de uso diferente (scan completo pelo Jaro, não join filtrado repetido).
- Benchmark chama `geocode_core()` direto após `devtools::load_all('.')`, nunca `geocode()` (que roda via
  `callr::r(..., package = TRUE)` e carregaria a versão instalada, não o source modificado — `[LEARN:testes]`).
- Corretude checada com `n_cores = 1` para evitar o não-determinismo já documentado de `FIRST()` sem
  `ORDER BY` nas etapas `da*`/`pa*` (`[LEARN:duckdb]`).

## Arquivos tocados

- `R/register_cnefe_tables.R` — `CREATE TEMP TABLE` → `CREATE TEMP VIEW` em `register_cnefe_table()`.
- `tests/tests_rafa/benchmark_temp_view.R` — script ad hoc de benchmark (não é teste do pacote).
- `quality_reports/diagnoses/2026-08-24_temp-view-benchmark.md` — resultados e decisão.

## Decisões / correções

- **Mudança revertida.** O benchmark ponta a ponta (não o isolado de 23/08) mostrou que `TEMP VIEW` piora
  o tempo total do `geocode_core()` em ~42% (4,18s → 5,92s), apesar de `register_cnefe_table()` isolada
  ficar 3,5× mais rápida (1,51s → 0,43s) — o custo economizado na materialização reaparece multiplicado em
  `rapi_execute`, porque cada uma das ~10 etapas que usam a tabela mais compartilhada reabre/refiltra o
  parquet a cada consulta em vez de uma vez só. Ver `[LEARN:duckdb]` em MEMORY.md e o relatório completo em
  `quality_reports/diagnoses/2026-08-24_temp-view-benchmark.md`.
- Achado colateral: a checagem de corretude (`n_cores = 1` dos dois lados) ainda divergiu em 4/20.028
  linhas, todas `da02`/`da04` — o `FIRST()` sem `ORDER BY` já documentado (`[LEARN:duckdb]` anterior), só
  que exposto por mudança na ordem física de scan (tabela vs. view), não por paralelismo. Registrado como
  refinamento da entrada existente em MEMORY.md — `n_cores = 1` não é garantia total de estabilidade nessa
  família de comparação.

## Questões em aberto / bloqueios

- Nenhum bloqueio. Se a materialização em `register_cnefe_table()` voltar a ser alvo de otimização, a
  direção sugerida no relatório é reduzir o volume materializado (menos colunas/linhas, escopo mais
  restrito por match_type), não trocar TABLE por VIEW.
- O não-determinismo de `FIRST()`/`LAST()` sem `ORDER BY` em `da0x`/`pa0x` (item já conhecido, não
  corrigido nesta sessão) segue aberto — ver `quality_reports/diagnoses/2026-08-24_geocode-revisao-critica.md`.

## Status

**Concluído.** `R/register_cnefe_tables.R` de volta ao estado original (`CREATE TEMP TABLE`, diff vazio
contra HEAD). Artefatos desta sessão: `tests/tests_rafa/benchmark_temp_view.R` (script reutilizável),
`quality_reports/diagnoses/2026-08-24_temp-view-benchmark.md` (relatório), duas entradas novas em
MEMORY.md. Nada para commitar em `R/` — só os arquivos de `quality_reports/` e o script de teste, se o
usuário quiser versioná-los.

### Addendum — análise consolidada de eficiência do geocode() (mesmo dia)

Na sequência, o usuário pediu uma análise rigorosa de eficiência de `geocode()` como um todo. Em vez de
repetir os três relatórios anteriores, fiz uma auditoria de status de cada achado contra o `HEAD` atual e
remedi o item de maior impacto ainda aberto (o laço que não pula etapas com campo-chave vazio) num cenário
"só CEP" fresco: `register_cnefe_table()` consome 58% do tempo total nesse cenário (contra 37% no cenário
completo) — confirma que a causa segue intacta. Relatório consolidado:
`quality_reports/diagnoses/2026-08-24_geocode-eficiencia-consolidado.md`. Novo script:
`tests/tests_rafa/benchmark_empty_field_guard.R`. Nenhuma mudança de código nesta parte — só análise e
proposta priorizada, aguardando o usuário escolher o próximo item a implementar.
