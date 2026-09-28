# Plano — Python: não manter uma segunda cópia do resultado no DuckDB (lição 6)

**Status:** APPROVED (27/09) — implementado; ver "Resultado" no fim
**Data:** 27/09/2026
**Origem:** lição B6 de `quality_reports/diagnoses/2026-09-23_licoes-cruzadas-geocode-R-Python.md`
**Princípio:** o mínimo de código, sem mudar nenhum resultado.

---

## Como o R faz

`merge_results_to_input()` (`r-package/R/utils.R`) monta a query do `LEFT JOIN ... ORDER BY
tempidgeocodebr` e, no `geocode()`, a executa como `COPY ({query}) TO '<tmp>.parquet' (FORMAT PARQUET)`. O
processo pai lê com `arrow::read_parquet()`. O resultado **nunca** vira tabela no DuckDB. O H3 é calculado
depois, no R, sobre o data.frame (`pos_processa_output()`).

## Como o Python faz hoje

- `merge_results_to_input()` (`matching.py:391`) faz `CREATE OR REPLACE TEMP TABLE geocodebr_result AS
  SELECT ... ORDER BY`, materializando o resultado inteiro no DuckDB.
- `add_h3_columns()` faz `ALTER TABLE` + `UPDATE` nessa tabela, só quando `h3_res` é informado.
- `geocode.py:323`: `SELECT * FROM geocodebr_result` → `.to_arrow_table()`. A cópia do DuckDB e a do
  Arrow coexistem.

## Qual forma adotar — medido antes de planejar

Três variantes, aplicadas por monkeypatch sobre o código atual (com as lições 1–5), `resultado_completo=True`,
Segment Heap, 2 rodadas. "Fase final" vai do início do merge ao retorno do `geocode()`.

| Variante | Fase final 1M | Pico 1M | Fase final 5M | Pico 5M |
|---|---|---|---|---|
| (a) atual: TABLE + `SELECT *` → Arrow | 2,07 / 2,53 s | 2,68 / 2,63 GB | 9,8 / 11,6 s | 8,59 / 8,53 GB |
| **(b) VIEW + `SELECT *` → Arrow** | **1,63 / 1,70 s** | 2,64 / 2,71 GB | **9,0 / 9,3 s** | **8,30 / 8,30 GB** |
| (c) como o R: VIEW + `COPY` parquet + `pq.read_table` | 2,07 / 1,81 s | 2,67 / 2,70 GB | 9,9 / 9,0 s | 8,95 / 8,78 GB |

- **(b) ganha nos dois eixos:** ~−0,4 s em 1M, ~−1,5 s em 5M, pico ~−250 MB (−3%) em 5M. E é a menor
  mudança.
- **(c)**, o caminho do R, não compensa no Python. O pico foi maior e não houve ganho de tempo. No R o
  parquet existe para atravessar o `callr`, e o Python não tem subprocesso.
- Em 20k as três são indistinguíveis (fase final ~0,1 s).
- O **schema Arrow** do resultado é idêntico nas três, com e sem `resultado_completo`.
- **Ganho honesto: modesto.** Com as lições 1 e 5 já aplicadas, o pico não está mais dominado pela
  tabela duplicada. É uma limpeza barata, não um salto.

---

## Mudança (~5 linhas, `matching.py` + `geocode.py`)

1. **`merge_results_to_input(..., materializar: bool = False)`:** o `CREATE OR REPLACE TEMP TABLE
   geocodebr_result AS` passa a ser `CREATE OR REPLACE TEMP {'TABLE' if materializar else 'VIEW'}
   geocodebr_result AS`, com um comentário de 2 linhas. O resto da função não muda.
2. **`geocode.py`:** passar `materializar=bool(h3_values)`. O H3 precisa de tabela, porque
   `add_h3_columns()` faz `ALTER`/`UPDATE`. Sem `h3_res`, que é o caso padrão, vira `VIEW`, e o
   `SELECT * FROM geocodebr_result` da linha 323 continua igual, agora executando a query direto para o
   Arrow.

Nada muda em `add_h3_columns()`, no `SELECT *` final, em `close_geocodebr_db()` ou nas assinaturas
públicas. Os testes de `tests/test_utils.py` que leem `geocodebr_result` continuam valendo, porque uma
view se lê igual a uma tabela.

**Fora do escopo:** calcular H3 sobre o Arrow depois do fetch, sem tabela, o que eliminaria a cópia também
com `h3_res`. Exigiria uma lib H3 vetorizada ou um laço Python, e mudar `add_h3_columns()`.

---

## Por que o resultado não muda

- **Mesma query:** a view tem exatamente o mesmo `SELECT ... LEFT JOIN ... ORDER BY tempidgeocodebr` que
  a tabela. Muda só quando ela é executada: no `SELECT *` final, e não no merge.
- **Nada entre o merge e o fetch altera as tabelas que a view lê** (`input_db`, `output_db`/`output_db2`).
  Sem H3, o próximo comando é o próprio `SELECT *`. Com H3 continua sendo tabela.
- **Ordem das linhas:** o `ORDER BY` está dentro da view, e o DuckDB entrega o resultado nessa ordem
  (`preserve_insertion_order` padrão), como o `COPY` do R pressupõe. A ordem precisa ser conferida
  posicionalmente, e não só como multiconjunto (ver Verificação).
- **Tipos:** o schema Arrow saiu idêntico nas medições acima.

---

## Verificação (paridade com `large_sample`, ~20 mil linhas)

1. **Suíte unitária** verde, incluindo `test_geocode.py:50`, que cobre o caminho com `h3_res=3` (TABLE).
2. **Antes × depois, mesmo pacote,** `large_sample` e `small_sample` × `resultado_completo` ×
   `resolver_empates`, baseline `uid_l4_*`:
   - **schema Arrow idêntico**;
   - **multiconjunto idêntico** (lat/lon a 1e-9);
   - **ordem das linhas:** com `resolver_empates=True`, comparação **posicional** idêntica, exceto o
     ruído de ~1e-14 em lat/lon. Com `resolver_empates=False`, a sequência da coluna de id do input
     (`id`) é idêntica. A ordem **dentro** de um empate já variava antes (achado de 27/09).
3. **R × Python:** as 4 combinações de `large_sample` contra `uid_R_large_*`, com multiconjunto idêntico.
4. **Com H3:** `geocode(..., h3_res=[3, 4])` em `large_sample` antes × depois, com resultado idêntico
   (continua pelo caminho TABLE).
5. **Ganho:** repetir a medição acima (fase final e pico) com o código alterado, em 1M e 5M.
6. `pytest -m r_parity` fica para o CI.

## Arquivos

- `python-package/geocodebr/matching.py` (`merge_results_to_input`: 1 parâmetro + 1 linha)
- `python-package/geocodebr/geocode.py` (1 argumento na chamada)
- `python-package/CHANGELOG.md` ("Modificado")
- R: nada.

**Total estimado:** ~5 linhas de código. Nenhum teste novo é necessário: os existentes já cobrem os dois
caminhos (com e sem H3). Se preferir, dá para acrescentar um teste que confira que, sem H3,
`geocodebr_result` é uma view.

## Resultado (27/09/2026)

Implementado como planejado: `merge_results_to_input(..., materializar=False)` cria `VIEW` por padrão e
`TABLE` só com H3; `geocode.py` passa `materializar=bool(h3_values)`. Único chamador: `geocode.py`.

- **Suíte unitária:** 175 passed, incluindo o teste com `h3_res=3`.
- **Com H3** (`h3_res=[3, 4]`, `large_sample`): antes × depois idêntico **posicionalmente**, mesmo schema.
- **Antes × depois,** `small_sample` e `large_sample` × `resultado_completo` × `resolver_empates`
  (baseline `uid_l4_*`): nas 8 combinações, **schema Arrow idêntico**, **multiconjunto idêntico** e
  **ordem preservada** (posicional com `resolver_empates=True`; sequência de ids com `False`).
- **R × Python,** `large_sample`, 4 combinações: **idêntico nas 4**.
- **Ganho (intercalado, código real vs cópia com `TABLE` fixo, `resultado_completo=True`):**

  | | antes | depois |
  |---|---|---|
  | Fase final, 1M | 2,06 / 1,71 s | 1,31 / 1,90 s |
  | Pico, 1M | 2.648 / 2.718 MB | 2.637 / 2.666 MB |
  | Fase final, 5M | 10,14 / 8,20 s | 7,67 / 6,41 s (~−2 s) |
  | Pico, 5M | 8.583 / 8.574 MB | 8.414 / 8.359 MB (~−2%) |

  O tempo total em 5M saiu maior nas rodadas "depois" (70 / 68 s vs 60 / 61 s). Como a única fase que o
  patch toca ficou mais rápida, isso é ruído da máquina fora do trecho alterado.
