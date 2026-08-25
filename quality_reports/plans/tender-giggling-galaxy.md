# TEMP VIEW em `register_cnefe_table()` — implementação + benchmark end-to-end

**Status:** COMPLETED — mudança testada ponta a ponta e revertida (piorou 42% o tempo total, apesar de
melhorar a função-alvo isoladamente). Ver `quality_reports/diagnoses/2026-08-24_temp-view-benchmark.md`.

## Contexto

O diagnóstico `quality_reports/diagnoses/2026-08-23_geocode-diagnostico-performance.md` (§3) mediu que
`register_cnefe_table()` (`R/register_cnefe_tables.R`), que faz `CREATE TEMP TABLE ... AS SELECT * FROM
read_parquet(...) WHERE estado IN (...) AND municipio IN (...)`, é responsável por ~50% do tempo de
`geocode_core()` nos 20.028 endereços de `inst/extdata/large_sample.parquet` — é a etapa de materializar as
tabelas de referência do CNEFE, não os joins em si. Um benchmark isolado (joins sintéticos) mostrou que
trocar `TEMP TABLE` por `TEMP VIEW` (deixando o DuckDB empurrar o filtro para dentro de cada join, sem
nunca materializar) ganha até ~12 usos da mesma tabela, com ganho de 1,5×–7× na fase que mede metade do
tempo total. Mapeando `reference_table_by_match_type` (`R/utils.R`) contra `all_possible_match_types`,
nenhuma das 8 tabelas de referência é usada mais de 10 vezes — todas ficam do lado vantajoso.

O relatório é explícito que o número vem de um benchmark isolado, não ponta a ponta no `geocode()` real.
Esta tarefa aplica a mudança e mede de verdade, com o pipeline completo e a amostra real de 20 mil
endereços, contra o cache local existente do CNEFE (release `v0.4.1`, já baixado — sem downloads).

**Escopo confirmado com o usuário:** só `register_cnefe_table()`. `register_unique_logradouros_table()`
fica como está — ela reduz a tabela-mãe a logradouros únicos e o resultado é varrido por inteiro pelo Jaro
em `calculate_string_dist()` (memoizado), um padrão de *scan* completo, não de *join filtrado repetido*;
virar view forçaria recomputar o `DISTINCT` a cada chamada do Jaro.

## Levantamento já feito nesta sessão (não repetir)

- `duckdb::dbExistsTable()` não tem override específico do pacote `duckdb`; usa o método default do `DBI`
  (`name %in% dbListTables(conn)`), e `dbListTables()` do `duckdb` consulta
  `sqlite_master WHERE type='table' OR type='view'` — confirmado lendo o método via `getMethod()`. Ou seja,
  tanto o guarda de memoização em `register_cnefe_table()` (linha ~52, `dbExistsTable(con,
  cnefe_table_name)`) quanto o branch "filtra da raiz se ela já existe" em
  `register_unique_logradouros_table()` (linha ~186) continuam funcionando sem alteração quando a raiz
  virar view.
- `grep` em `R/` por `ALTER TABLE` / `INSERT INTO` / `CREATE INDEX` / `dbWriteTable` contra os nomes das 8
  tabelas de referência: nenhuma ocorrência. Elas só são lidas (`SELECT`/`JOIN`) em todo o pipeline —
  seguro virar view.
- `geocode()` roda o corpo em `callr::r(..., package = TRUE)`, que carrega a versão **instalada** do
  pacote, não o source em desenvolvimento (`[LEARN:testes]` em `MEMORY.md`). O benchmark deste plano chama
  `geocode_core()` diretamente após `devtools::load_all('.')`, nunca `geocode()`.
- Cache já local: `C:\Users\r1701707\AppData\Local\R\cache\R\geocodebr\geocodebr_data_release_v0.4.1\` tem
  os 8 parquets (~1,46 GB) — mesmo release (`v0.4.1`) hardcoded em `R/cache.R:1`. Sem download.
- `inst/extdata/large_sample.parquet`: 20.028 linhas, colunas `id, logradouro, numero, bairro, cep,
  municipio, uf` — exatamente o arquivo usado no diagnóstico de 23/08.
- Sintaxe `CREATE TEMP VIEW IF NOT EXISTS nome AS <select>` é válida no DuckDB (espelha `CREATE TEMP TABLE
  IF NOT EXISTS`).

## Passo 1 — Mudança de código

Em `R/register_cnefe_tables.R`, função `register_cnefe_table()` (linha ~57): trocar

```sql
CREATE TEMP TABLE IF NOT EXISTS {cnefe_table_name} AS
```

por

```sql
CREATE TEMP VIEW IF NOT EXISTS {cnefe_table_name} AS
```

Nenhuma outra linha da função muda. `register_unique_logradouros_table()` não é tocada.

## Passo 2 — Script de benchmark

Criar `tests/tests_rafa/benchmark_temp_view.R` (segue o padrão dos scripts ad hoc já existentes nessa
pasta, como `benchmark_20k.R`), reaproveitável para rodar "antes" e "depois" do Passo 1:

1. `devtools::load_all('.')`.
2. Ler `large_sample.parquet`; montar `campos_endereco` com os 6 campos (`definir_campos()`), igual ao
   dataset real (não o subset sem logradouro/número usado em `benchmark_20k.R` — aqui queremos exercitar o
   máximo de etapas/tabelas do laço, como no diagnóstico original).
3. **Rodada de corretude** (`n_cores = 1`, para evitar o não-determinismo já documentado de `FIRST()` sem
   `ORDER BY` nas etapas `da*`/`pa*` — `[LEARN:duckdb]` em `MEMORY.md` — que confundiria a comparação):
   chamar `geocode_core()` uma vez, salvar o `data.table` de output completo (`resultado_completo = TRUE`,
   `resolver_empates = TRUE`).
4. **Rodada de tempo**: `bench::mark(iterations = 5, ...)` chamando `geocode_core()` com `n_cores = 7`
   (mesmo valor usado em `benchmark_20k.R`), capturando mediana/mínimo.
5. **Tempo por fase**: `Rprof()`/`summaryRprof()` em torno de uma chamada a `geocode_core()`, para isolar o
   tempo (self + total) atribuído a `register_cnefe_table()` especificamente — sem precisar descomentar o
   timer interno de `R/geocode.R`.

Rodar o script assim (baseline, `TEMP TABLE`), guardar os três resultados. Aplicar o Passo 1. Rodar de novo
o mesmo script (`TEMP VIEW`), guardar os três resultados equivalentes.

## Passo 3 — Comparação e decisão

- **Corretude**: `identical()`/`all.equal()` entre os `data.table`s de antes/depois — mesmo `nrow`, mesmas
  `lat`/`lon`/`tipo_resultado`/`precisao` linha a linha. Qualquer divergência bloqueia a mudança e exige
  investigar a causa (não só reverter).
- **Desempenho**: reportar tempo total mediano (`bench::mark`) e tempo específico de
  `register_cnefe_table()` (`Rprof`) antes/depois.
- Manter a mudança só se for ganho líquido **e** a corretude bater. Caso contrário, reverter
  `register_cnefe_table()` e documentar por que o benchmark isolado não se sustentou ponta a ponta.

## Passo 4 — Registro

- Novo arquivo `quality_reports/diagnoses/2026-08-24_temp-view-benchmark.md`: metodologia, números antes/
  depois, resultado da checagem de corretude, decisão final — referenciando o §3 do relatório de 23/08.
- Se a mudança for mantida: uma linha no `NEWS.md` (versão dev `0.6.4.900`) sobre a melhoria de desempenho
  interna (sem mudança de comportamento visível ao usuário).
- `[LEARN:duckdb]` em `MEMORY.md` só se surgir algo não óbvio (ex.: o multiplicador ponta a ponta divergir
  bastante da estimativa isolada, ou alguma interação com o branch "filtra da raiz" de
  `register_unique_logradouros_table()`).

## Verificação

- A checagem de corretude do Passo 3 é o principal critério — precisa passar antes de manter a mudança.
- `register_cnefe_tables.R` é `# nocov start/end` (sem cobertura, sem teste dedicado hoje) — não se espera
  que `devtools::test()` toque esse caminho diretamente. Ainda assim, rodar `devtools::test()` uma vez ao
  final como smoke check, ciente de que qualquer teste que passe por `geocode()` testa a versão **instalada**
  via `callr`, não o source modificado (`[LEARN:testes]`) — um `devtools::test()` verde aqui é sinal fraco,
  não prova.
- `tests/tests_rafa/benchmark_temp_view.R` fica na pasta de scripts ad hoc (mesmo padrão dos outros
  arquivos ali), não vira teste do pacote.
