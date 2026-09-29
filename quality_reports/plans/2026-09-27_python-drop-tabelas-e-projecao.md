# Plano — Python: descartar tabelas obsoletas (lição 1) e projetar só as colunas usadas (lição 5)

**Status:** APPROVED (27/09) — implementado; ver "Resultado" no fim
**Data:** 27/09/2026
**Origem:** lições B1 e B5 de `quality_reports/diagnoses/2026-09-23_licoes-cruzadas-geocode-R-Python.md`
**Princípio:** portar o que o R já faz, com o mínimo de código, sem mudar nenhum resultado.

---

## Como o R faz

### Lição 1 — ciclo de vida das tabelas
| Momento | R | Python hoje |
|---|---|---|
| Depois de **cada** etapa do laço | `dropa_tabelas_obsoletas(con, restantes, campos_nao_declarados)` (`geocode.R:579-583`). Derruba toda tabela de referência / `unique_logr_*` que nenhuma etapa **restante e ativa** vai usar (`tabelas_ainda_necessarias()`, `utils.R:828-874`) | nada |
| Depois do laço | `dropa_tabelas_obsoletas(con, character(0), ...)` + `DROP TABLE input_padrao_db` (`geocode.R:597-598`) | nada |
| Depois dos empates | `DROP` de `output_db`, `empates_classif`, `ids_empatados` (`trata_empates_geocode_duckdb.R:68, 306-308`) | nada |

Não há **nenhum** `DROP` em `python-package/geocodebr/`: as 8 tabelas de referência, os 2 `unique_logr_*`,
`input_padrao_db`, `output_db`, `ids_empatados` e `empates_classif` ficam vivos até `close_geocodebr_db()`.

### Lição 5 — projeção ao materializar as tabelas de referência
O R usa `SELECT * EXCLUDE (code_muni, n_setor[, cod_setor])` (`register_cnefe_tables.R:60-76`), com
`cod_setor` excluído só quando `resultado_completo = FALSE`. O Python usa `SELECT *` (`tables.py:33`).
Os 8 parquets do release v0.5.0 têm as três colunas (conferido).

---

## Mudanças

### Lição 5 (~8 linhas, `tables.py` + 4 chamadas em `matching.py`)

1. `register_cnefe_table(con, match_type, pasta_dados=None, resultado_completo=True)`. Antes do
   `CREATE`, monta a lista de exclusão **a partir do schema do parquet**:
   ```python
   # colunas que nenhuma query le: code_muni e n_setor nunca; cod_setor so com
   # resultado_completo. Espelha register_cnefe_table() do R (~10% menos memoria)
   excluir = ["code_muni", "n_setor"] + ([] if resultado_completo else ["cod_setor"])
   presentes = {r[0] for r in con.execute(
       f"DESCRIBE SELECT * FROM read_parquet('{path_to_parquet}')").fetchall()}
   excluir = [c for c in excluir if c in presentes]
   projecao = f"* EXCLUDE ({', '.join(excluir)})" if excluir else "*"
   ```
   e `SELECT *` vira `SELECT {projecao}`.
   - **Por que ler o schema em vez de fixar o `EXCLUDE` como no R:** os parquets sintéticos dos testes
     unitários não têm `code_muni`/`n_setor`, e `EXCLUDE` de coluna inexistente dá `BinderException`
     (conferido). O `DESCRIBE` lê só metadados. `COLUMNS(lambda c: ...)` resolveria em uma linha, mas
     exige DuckDB ≥ 1.3, e o `pyproject.toml` aceita `duckdb>=1.0.0`. A sintaxe antiga (`c -> ...`) está
     depreciada.
2. As quatro chamadas em `matching.py` (linhas 63, 103, 160, 213) passam
   `resultado_completo=resultado_completo`. Todas as `match_*()` já recebem esse argumento.

### Lição 1 (~30 linhas, `match_types.py` + `tables.py` + `geocode.py`)

3. **`match_types.py`:** `tabelas_ainda_necessarias(restantes, campos_nao_declarados)`, porte direto do R
   (~15 linhas, módulo puro):
   - filtra `restantes` pelos ativos (nenhuma `key_col` em `campos_nao_declarados`);
   - mapeia com `get_reference_table()`;
   - acrescenta `unique_logr_municipio_logradouro_localidade` se algum probabilístico restante for
     `pn03`/`pa03`/`pl03`, e `unique_logr_municipio_logradouro_cep_localidade` se algum outro
     probabilístico restar. Mesmo critério de `register_unique_logradouros_table()`.
4. **`tables.py`:** `dropa_tabelas_obsoletas(con, restantes, campos_nao_declarados)` (~10 linhas):
   candidatas = tabelas de referência de `ALL_POSSIBLE_MATCH_TYPES` + os 2 `unique_logr_*`. Faz
   `DROP TABLE IF EXISTS` das candidatas que existem e não estão em `tabelas_ainda_necessarias()`.
5. **`geocode.py`, no laço:** trocar `for match_type in ALL_POSSIBLE_MATCH_TYPES` por
   `for i, match_type in enumerate(...)` e, logo após `matched_rows += affected`, chamar
   `dropa_tabelas_obsoletas(con, ALL_POSSIBLE_MATCH_TYPES[i + 1:], campos_nao_declarados)`. Isso vem antes
   do `break`, como no R.
6. **`geocode.py`, depois do laço** (fora do `with tqdm`):
   `dropa_tabelas_obsoletas(con, [], campos_nao_declarados)` + `DROP TABLE IF EXISTS input_padrao_db`.
7. **`geocode.py`, depois de `trata_empates_geocode_duckdb()`:** `DROP TABLE IF EXISTS` de `ids_empatados`
   e `empates_classif`, e de `output_db` quando `output_table_to_use == "output_db2"`. Fica num lugar só,
   em vez de nos três ramos de retorno da função, e o `IF EXISTS` cobre o ramo que renomeia `output_db`.

**Fora do escopo** (itens B6/B7 do relatório, para não misturar): o `geocodebr_result` duplicado e
liberar `df_padrao`/`input_padrao_view`.

---

## Por que o resultado não muda

- **Lição 5:**
  - `code_muni` e `n_setor` não aparecem em nenhuma query do pacote (grep).
  - `cod_setor` só é lido com `resultado_completo=True`: em `monta_colunas_encontradas`, que retorna antes
    de tocar nele (`matching.py:780`), e no SQL de empates, que lê de `output_db` e só dentro de
    `if resultado_completo` (`matching.py:550`). E com `resultado_completo=True` ele não é excluído.
  - A ordem das colunas restantes é a mesma do `SELECT *`.
- **Lição 1:**
  - Só se derruba uma tabela que nenhuma etapa **seguinte** usa. O critério é o do R, que já provou
    `identical()` antes/depois.
  - Se uma etapa futura precisasse de uma tabela derrubada, `register_cnefe_table()` a recriaria (checa
    existência) e o resultado seria o mesmo, só mais lento. Então um erro no critério custa tempo, não
    resultado.
  - `input_padrao_db` não é lido depois do laço (grep em `matching.py` a partir da linha 440).
  - `add_precision_col` e `merge_results_to_input` só leem `output_table_to_use`.

---

## Verificação (paridade com `large_sample`, ~20 mil linhas)

Reaproveitando os scripts do plano de 27/09 (`scratchpad/uid_check.py`, `uid_r.R`):

1. **Suíte unitária** `pytest -m "not r_parity"` verde. Dois testes novos em `tests/test_matching.py`:
   - `tabelas_ainda_necessarias`: com todos os campos, depois de `da03` restam só as tabelas das etapas
     seguintes; com `cep` não declarado, as tabelas de cep somem.
   - `register_cnefe_table(..., resultado_completo=False)` não materializa `cod_setor`, e o fixture sem
     `code_muni` continua funcionando.
2. **Antes × depois, mesmo pacote:** `geocode()` em `large_sample.parquet` nas 4 combinações de
   `resultado_completo` × `resolver_empates`. O multiconjunto de linhas tem que ser idêntico (lat/lon
   arredondados a 1e-9). A comparação é por multiconjunto porque, com `resolver_empates=False`, a ordem
   das linhas empatadas já varia entre execuções idênticas (achado de 27/09).
3. **R × Python:** as mesmas 4 combinações contra os outputs do R (`uid_R_large_*.parquet`). O
   multiconjunto tem que ser idêntico, como antes do patch.
4. **Tabelas vivas:** instrumentar `geocode()` e listar `duckdb_tables()` depois do laço e antes do
   merge. Esperado: só `output_db`/`output_db2` (e `input_db`, registrado). Hoje são ~13 tabelas.
5. **Memória (ganho, não paridade):** pico de working set e `duckdb_memory()` no fim do laço, 20k e 1M.
   Referência do agente 4: 1.887 → 1.650 MB (20k) e 3.743 → 2.495 MB (1M); fim do laço 1.656 → 23 MB.
6. `pytest -m r_parity` fica para o CI (`python-parity.yaml`).

## Arquivos

- `python-package/geocodebr/tables.py` (lição 5 + `dropa_tabelas_obsoletas`)
- `python-package/geocodebr/match_types.py` (`tabelas_ainda_necessarias`)
- `python-package/geocodebr/matching.py` (4 chamadas passam `resultado_completo`)
- `python-package/geocodebr/geocode.py` (3 pontos: no laço, após o laço, após empates)
- `python-package/tests/test_matching.py` (2 testes)
- `python-package/CHANGELOG.md` ("Modificado": menor uso de memória, resultado igual)
- R: nada.

**Total estimado:** ~40 linhas de código + ~40 de teste.

## Resultado (27/09/2026)

Implementado como planejado. `dropa_tabelas_obsoletas` ficou em `tables.py`, `tabelas_ainda_necessarias`
em `match_types.py`, e há 3 pontos de `DROP` em `geocode.py`. Foram 4 testes novos em
`tests/test_matching.py`.

- **Suíte unitária:** 172 passed.
- **Paridade de resultado (multiconjunto, lat/lon a 1e-9):**
  - antes × depois, `small_sample` e `large_sample` × `resultado_completo` × `resolver_empates`:
    **idêntico nas 8 combinações**;
  - R × Python, `large_sample`, 4 combinações: **idêntico nas 4**.
- **Tabelas vivas (20k e 1M):** fim do laço 12 → 1 (`output_db`); antes do merge 15 → 1 (`output_db2`).
- **Nenhuma tabela recriada:** cada uma das 8 tabelas de referência é criada exatamente 1 vez por chamada
  (instrumentado), então o critério de descarte não derruba nada que ainda seria usado.
- **Memória:**

  | | 20k antes | 20k depois | 1M antes | 1M depois |
  |---|---|---|---|---|
  | DuckDB no fim do laço | 1.661 MB | 15 MB | 2.004 MB | 179 MB |
  | Pico de working set | 1.901 MB | 1.665 MB (−12%) | 3.711–3.738 MB | 2.497–2.505 MB (−33%) |

- **Tempo:** sem mudança mensurável. Em 1M, intercalado: HEAD 60,8 / 56,7 s vs patch 66,7 / 46,5 s,
  dentro do ruído.
- `pytest -m r_parity` não foi rodado localmente; fica para o CI.
