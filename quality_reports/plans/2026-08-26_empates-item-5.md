# Plano — item 5: caminho `resolver_empates = FALSE` sem cópia integral de output_db

**Status:** ACORDADO E IMPLEMENTADO — veredito adversarial: APROVAR COM MUDANÇAS; acordo =
**variante C do adversário** (flag in-place + `ALTER TABLE output_db RENAME TO output_db2`), que domina
a proposta A: mesmo ganho (zero cópia), contrato "n>0 → existe output_db2" preservado, `geocode.R`
intocado.

**Registro do acordo (26/08):**
- Achado 1 (MAIOR, corrige premissa deste plano): o default de `geocode()` é `resolver_empates = TRUE`
  (`geocode.R:78`) — o ramo FALSE é minoritário, o que derrubou a justificativa de acoplamento extra da
  proposta A.
- Achado 2 (MAIOR): variante C = ALTER ADD COLUMN + UPDATE via `ids_empatados` + RENAME. Verificado pelo
  adversário: nenhum outro consumidor de `output_db2`/`empates_resolvidos` no pacote (achado 3); sem
  colisão de `ADD COLUMN` entre ramos (achado 6); conexão nova por chamada, sem `output_db2` pré-existente.
- Achados menores acatados: comentário com a ressalva de NULL em `tempidgeocodebr` (achado 5); risco de
  ordem das linhas duplicadas tratado com protocolo de ordenação canônica no benchmark (achado 8).
- Fora de escopo, registrado: inconsistência de UX pré-existente — com `resultado_completo = FALSE` o
  `cli_warn` manda inspecionar a coluna `empate`, que não chega ao output nesse fluxo (achado 7);
  `tests_pedro/benchmark_performance.R` chama a função com assinatura defasada (script morto).
**Arquivos alvo:** `r-package/R/trata_empates_geocode_duckdb.R` (ramo FALSE) e — na proposta A —
`r-package/R/geocode.R:488-492` (escolha `output_db` vs `output_db2`)
**Critério de aceite:** `identical()` no benchmark oficial (1M, `n_cores = 1`) rodando com
`resolver_empates = FALSE`, mais o harness sintético estendido para esse ramo.

## Contexto

Hoje o ramo `resolver_empates = FALSE` (linhas 45-64) faz:

```sql
CREATE OR REPLACE TEMP TABLE output_db2 AS
  SELECT *, (COUNT(*) OVER (PARTITION BY tempidgeocodebr) > 1) AS empate
  FROM output_db;
```

Ou seja: **cópia integral** de `output_db` (1M linhas no benchmark) + uma window function sobre a
tabela inteira — só para acrescentar um flag booleano que é TRUE em ~168 mil linhas. E desde os itens
2+4, `ids_empatados` **já está materializada** quando esse ramo executa.

Nota de semântica (inalterada): nesse ramo as linhas empatadas são deliberadamente devolvidas em
duplicidade ao usuário (o output tem mais linhas que o input), para inspeção manual.

## Proposta A (preferida — elimina a cópia)

No ramo FALSE de `trata_empates_geocode_duckdb.R`:

```sql
ALTER TABLE output_db ADD COLUMN IF NOT EXISTS empate BOOLEAN DEFAULT FALSE;
UPDATE output_db SET empate = TRUE
  WHERE tempidgeocodebr IN (SELECT tempidgeocodebr FROM ids_empatados);
```

Nenhuma `output_db2` é criada. Em `geocode.R:488-492`, a escolha da tabela muda de

```r
output_table_to_use <- ifelse(empates_resolvidos == 0, 'output_db', 'output_db2')
```

para usar `output_db2` **somente** quando houve empates E `resolver_empates = TRUE` (única situação em
que ela passa a existir):

```r
output_table_to_use <- ifelse(
  empates_resolvidos > 0 && resolver_empates, 'output_db2', 'output_db'
)
```

Viabilidade verificada: `add_precision_col()` (`utils.R:103`, ALTER+UPDATE) e
`merge_results_to_input()` (`utils.R:137`, SELECT) já operam sobre `output_db` no caminho de zero
empates — nada downstream exige que a tabela se chame `output_db2`.

Custo esperado: UPDATE de ~168 mil linhas + semi-join hash contra 84 mil ids, contra cópia de 1M
linhas + window function. O `ALTER ... DEFAULT FALSE` não reescreve linhas existentes no DuckDB.

## Proposta B (fallback mais conservador — mantém a cópia, troca a window function)

Manter `output_db2`, trocando só o cálculo do flag:

```sql
CREATE OR REPLACE TEMP TABLE output_db2 AS
  SELECT o.*, EXISTS (SELECT 1 FROM ids_empatados i
                      WHERE i.tempidgeocodebr = o.tempidgeocodebr) AS empate
  FROM output_db o;
```

Zero mudança em `geocode.R`, zero mudança de contrato. Ganho menor (a cópia de 1M linhas permanece),
mas elimina o particionamento/sort da window function.

## Riscos conhecidos

1. **Ordem relativa das linhas duplicadas.** O output final é ordenado por `tempidgeocodebr` apenas
   (`merge_results_to_input()`, `utils.R:203-204`); para um id empatado, a ordem relativa das suas 2+
   linhas vem do plano de execução. Mudar o plano (A ou B) pode trocar essa ordem e quebrar o
   `identical()` mesmo com o mesmo conjunto de linhas. Se ocorrer: comparar após ordenação canônica
   (todas as colunas) e decidir conscientemente — a ordem dentro de um id empatado nunca foi
   contratual.
2. **Custo de UPDATE esparso no DuckDB (proposta A):** atualizar 168 mil linhas espalhadas pode
   reescrever muitos row groups da temp table. O benchmark decide entre A e B.
3. **Proposta A acopla `geocode.R` à semântica interna** ("output_db2 só existe se resolveu empates").
   Mitigável com comentário no ponto de escolha.

## Resultado (26/08, pós-implementação)

Benchmark oficial (1M, `n_cores = 1`, `resolver_empates = FALSE`, baseline = itens 1+2+4 vs variante C):

| | baseline | item 5 (var. C) |
|---|---|---|
| Total | 106,8 s | 96,4 s |
| Etapa de empates | 0,63 s | **0,12 s** (−81%) |
| Linhas out (com duplicatas de empate) | 1.292.514 | 1.292.514 |
| `identical()` posicional | — | FALSE |
| `identical()` após ordenação canônica (todas as colunas) | — | **TRUE** |

O `identical()` posicional falhou exatamente pelo risco 1 previsto (e achado 8 do adversário): a ordem
relativa das linhas duplicadas *dentro de um mesmo* `tempidgeocodebr` mudou com o plano — o conteúdo é
o mesmo multiconjunto, bit a bit (`identical` TRUE após `setorder` em todas as colunas; as colunas
"divergentes" — lat/lon/desvio/endereco — são as trocas posicionais entre as linhas do mesmo id).
**Decisão: aceito** — a ordem intra-id das linhas empatadas nunca foi contratual (o output desse ramo é
para inspeção manual dos empates), conforme protocolo acordado. A diferença de tempo total
(106,8→96,4 s) excede o ganho da etapa (~0,5 s); o restante é ruído/aquecimento entre execuções — o
número honesto do item 5 é o da etapa.

Harness sintético: ramo FALSE `identical()` TRUE (posicional, dados pequenos), flag e duplicatas
corretos; ramo TRUE re-verificado intacto.

## Verificação

1. Harness sintético estendido: rodar também com `resolver_empates = FALSE` e comparar `output_db2`
   (ou `output_db` na proposta A) entre baseline (itens 2+4) e novo — mesmo conjunto de linhas.
2. Benchmark oficial: 1M, `n_cores = 1`, `resolver_empates = FALSE`, baseline vs novo — `identical()`
   no output final de `geocode_core()` + tempos (total e etapa).
3. Sanidade: rodar também `resolver_empates = TRUE` no 1M para confirmar que o caminho TRUE não foi
   afetado (na proposta A, `geocode.R` mudou).
