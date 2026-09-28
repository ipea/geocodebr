# Plano — Python: deduplicação no cálculo de Jaro (lição 2)

**Status:** APPROVED (27/09) — implementado; ver "Resultado" no fim
**Data:** 27/09/2026
**Origem:** lição B2 de `quality_reports/diagnoses/2026-09-23_licoes-cruzadas-geocode-R-Python.md`
**Princípio:** portar a query do R, com o mínimo de código, sem mudar nenhum resultado.

---

## Como o R faz (`r-package/R/string_dist.R`)

Uma única query, com três otimizações que o Python não tem:

1. **`usa_dedup`:** quando a chave de lookup **não** tem `cep` e `localidade` juntos (pn02, pn03, pl02,
   pl03), o Jaro é calculado uma vez por combinação distinta `(chave, logradouro)`
   (`SELECT DISTINCT {chave}, logradouro AS logradouro_input`). O resultado volta ao input por join em
   chave + logradouro. Com cep + localidade (pn01, pl01) quase não há repetição, então calcula por
   `tempidgeocodebr`, como hoje. O comentário do R mede: Jaro 178 → ~60 s em 43,9 M; e pn01 6 → 29 s se
   deduplicasse, daí a exceção.
2. **Candidatos distintos (`cand_src`):** na forma com dedup, os candidatos vêm de
   `(SELECT DISTINCT {chave}, logradouro FROM unique_logr_*)`. A tabela `unique_logr_*` é criada pela
   primeira etapa que a usa, com a chave mais longa. Numa chave mais curta (pn02/pl02), o mesmo logradouro
   aparece uma vez por localidade, e cada repetição custaria um `jaro_similarity`.
3. **`filtro_sem_numero`:** nas etapas `pl0k`, só entram linhas com `numero IS NULL`. As que têm número já
   foram testadas no `pn0k` correspondente (mesma chave de lookup, mesma tabela `unique_logr_*`, mesmo
   corte) e não passaram. Recalcular é um no-op garantido.

Além disso, o R escolhe o melhor candidato com `FIRST(logradouro_cnefe ORDER BY similarity DESC,
logradouro_cnefe)` + `MAX(similarity)` num `GROUP BY`, em vez de `RANK() = 1`. É o mesmo resultado (a
ordem é total) e mais barato. O agente 2 não viu diferença de tempo entre as duas formas, então não é
isso que dá o ganho. Mas portar a query inteira mantém os dois pacotes com o mesmo SQL, o que facilita a
manutenção da paridade.

## Como o Python faz hoje (`python-package/geocodebr/string_dist.py`)

- Uma forma só: cada `tempidgeocodebr` elegível × todos os candidatos da chave, com
  `RANK() OVER (PARTITION BY tempidgeocodebr ...)`.
- Candidatos direto da `unique_logr_*`, com as repetições.
- Sem filtro de número nos `pl0k`.

**Medido pelo agente 2 (20k, mesmo estado, mín. de 5):** as 6 etapas probabilísticas somam 1.432 ms (forma
Python) vs 921 ms (forma R), −0,5 s por chamada. Em 1M replicado, pn02/pl02/pl03/pn03 levaram 10–21 s cada
no Python vs 0,3–1 s no R. A replicação exagera, mas a direção é clara.

---

## Mudança (1 arquivo: `python-package/geocodebr/string_dist.py`)

Reescrever o corpo de `calculate_string_dist()` como **porte linha a linha** da query do R. A assinatura
não muda e os chamadores (`matching.py:162, 216`) não mudam. São ~45 linhas de SQL/montagem no lugar das
~40 atuais.

```python
from .match_types import PROBABILISTIC_TYPES_NO_NUMBER, get_key_cols, get_prob_match_cutoff

def calculate_string_dist(con, match_type, unique_logradouros_tbl):
    key_cols = get_key_cols(match_type)
    cols_not_null = " AND ".join(f"input_padrao_db.{c} IS NOT NULL" for c in key_cols)
    lookup_cols = [c for c in key_cols if c not in {"numero", "logradouro"}]
    key_cols_sql = ", ".join(lookup_cols)
    min_cutoff = get_prob_match_cutoff(match_type)
    tbl = quote_ident(unique_logradouros_tbl)

    # pl0k: linhas com numero ja foram testadas no pn0k correspondente (mesma
    # chave, tabela e corte) e nao passaram -- recalcular e no-op
    filtro_sem_numero = (
        "AND input_padrao_db.numero IS NULL"
        if match_type in PROBABILISTIC_TYPES_NO_NUMBER else ""
    )

    # Jaro depende so de (chave, logradouro): com chave curta, calcula uma vez
    # por combinacao distinta; com cep + localidade (pn01/pl01) quase nao ha
    # repeticao e o join-back custa mais -- calcula por tempidgeocodebr.
    # Espelha string_dist.R
    if not {"cep", "localidade"} <= set(lookup_cols):
        sel_cols = f"DISTINCT {key_cols_sql}, logradouro AS logradouro_input"
        grp_cols = f"{key_cols_sql}, logradouro_input"
        upd_join = " AND ".join(
            [f"input_padrao_db.{c} = computed.{c}" for c in lookup_cols]
            + ["input_padrao_db.logradouro = computed.logradouro_input"]
        )
        cand_src = f"(SELECT DISTINCT {key_cols_sql}, logradouro FROM {tbl})"
    else:
        sel_cols = f"tempidgeocodebr, {key_cols_sql}, logradouro AS logradouro_input"
        grp_cols = "tempidgeocodebr"
        upd_join = "input_padrao_db.tempidgeocodebr = computed.tempidgeocodebr"
        cand_src = tbl

    join_pairs = " AND ".join(f"t.{c} = c.{c}" for c in lookup_cols)

    con.execute(f"""
        WITH to_compute AS (
          SELECT {sel_cols}
          FROM input_padrao_db
          WHERE input_padrao_db.similaridade_logradouro IS NULL
            AND input_padrao_db.log_causa_confusao = FALSE
            AND {cols_not_null}
            {filtro_sem_numero}
        ),
        pairs AS (
          SELECT t.*, c.logradouro AS logradouro_cnefe,
                 CAST(jaro_similarity(t.logradouro_input, c.logradouro) AS NUMERIC(5,3)) AS similarity
          FROM to_compute t
          JOIN {cand_src} c ON {join_pairs}
          WHERE similarity > {min_cutoff}
        ),
        computed AS (
          SELECT {grp_cols},
                 FIRST(logradouro_cnefe ORDER BY similarity DESC, logradouro_cnefe) AS logradouro_cnefe,
                 MAX(similarity) AS similarity
          FROM pairs
          GROUP BY {grp_cols}
        )
        UPDATE input_padrao_db
          SET temp_lograd_determ = computed.logradouro_cnefe,
              similaridade_logradouro = computed.similarity
          FROM computed
          WHERE {upd_join}
            AND input_padrao_db.similaridade_logradouro IS NULL
            AND input_padrao_db.log_causa_confusao = FALSE
            AND {cols_not_null}
    """)
```

**Fora do escopo** (itens separados do relatório): o filtro por `estado` na criação de `unique_logr_*` a
partir do parquet e o `temp_lograd_determ` inicial `''`.

---

## Por que o resultado não muda

- **Dedup:** `jaro_similarity(logradouro_input, candidato)` e o conjunto de candidatos dependem só de
  `(chave de lookup, logradouro)`, não do `tempidgeocodebr`. Linhas com a mesma combinação teriam o mesmo
  melhor candidato e a mesma similaridade. Calcular uma vez e distribuir por join dá o mesmo valor por
  linha.
- **Join-back não alcança linhas inelegíveis:** o `UPDATE` repete os filtros de elegibilidade
  (`similaridade_logradouro IS NULL`, `log_causa_confusao = FALSE`, chaves não nulas). Uma linha já
  resolvida ou com logradouro ambíguo (`RUA A`), que compartilhe chave + logradouro com uma elegível,
  não é atualizada.
- **Candidatos distintos:** tirar repetições de `(chave, logradouro)` não muda o máximo nem o
  desempate. Só evita calcular o mesmo par duas vezes.
- **`filtro_sem_numero`:** no Python também vale, conferido:
  - todo `pl0k` roda depois do `pn0k` (`ALL_POSSIBLE_MATCH_TYPES`);
  - a chave de lookup é a mesma (`get_key_cols(pn0k)` menos `numero` = `get_key_cols(pl0k)`);
  - o corte é o mesmo (`get_prob_match_cutoff`: 0,85 em pn01/pl01, 0,90 no resto);
  - a tabela `unique_logr_*` é a mesma (`*03` → localidade, senão → cep_localidade).

  Uma linha com número ainda nula no `pl0k` já teve a mesma conta feita no `pn0k`, sem candidato acima do
  corte. Com `numero` não declarado, a coluna-fantasma é toda nula e o filtro não exclui nada.
- **`FIRST ... ORDER BY similarity DESC, logradouro_cnefe` + `MAX`** escolhe o mesmo candidato que
  `RANK() = 1` com a mesma ordenação, porque a ordem é total.
- **É a query que o R já usa**, e o R já passou `identical()` antes/depois com ela.

---

## Verificação (paridade com `large_sample`, ~20 mil linhas)

1. **Testes unitários existentes** de Jaro continuam verdes, sem mudança: corte, desempate alfabético,
   não recalcular similaridade já preenchida, excluir `log_causa_confusao` (`tests/test_matching.py:210-342`).
2. **Dois testes novos** em `tests/test_matching.py`:
   - **dedup:** duas linhas com a mesma chave + logradouro (pn02) recebem o mesmo candidato e a mesma
     similaridade; uma terceira com a mesma combinação mas `log_causa_confusao = TRUE` continua nula.
   - **pl sem número:** numa etapa `pl0k`, uma linha com `numero` preenchido e similaridade nula não é
     atualizada; uma com `numero` nulo é.
3. **Antes × depois, mesmo pacote:** `geocode()` em `large_sample` (e `small_sample`) nas 4 combinações
   de `resultado_completo` × `resolver_empates`, com o multiconjunto de linhas idêntico. Com
   `resultado_completo=True`, isso cobre `similaridade_logradouro` e `logradouro_encontrado`, o efeito
   direto do Jaro. O baseline é o estado atual (`uid_l15_*`, já com as lições 1, 3 e 5).
4. **R × Python:** as 4 combinações de `large_sample` contra `uid_R_large_*`, com multiconjunto idêntico.
5. **Checagem mais fina, direto no estado do Jaro:** instrumentar `calculate_string_dist` e, depois de
   cada etapa probabilística, gravar `(tempidgeocodebr, temp_lograd_determ, similaridade_logradouro)` de
   `input_padrao_db`. Comparar antes × depois etapa a etapa. Isso pega uma divergência mesmo que ela não
   chegue ao output final.
6. **Ganho:** tempo acumulado em `calculate_string_dist` antes × depois, em 20k e 1M (intercalado,
   Segment Heap), e tempo total.
7. `pytest -m r_parity` fica para o CI.

## Arquivos

- `python-package/geocodebr/string_dist.py` (corpo de `calculate_string_dist`)
- `python-package/tests/test_matching.py` (2 testes)
- `python-package/CHANGELOG.md` ("Modificado": Jaro mais rápido, resultado igual)
- R: nada.

**Total estimado:** ~45 linhas reescritas em 1 função + ~50 de teste.

## Resultado (27/09/2026)

Implementado como planejado: `calculate_string_dist()` reescrita como porte da query do R e 2 testes novos
em `tests/test_matching.py`.

- **Suíte unitária:** 174 passed. O teste de `pl0k` foi conferido contra o código antigo, que preenche a
  linha com número. O código novo não preenche, então o teste distingue as versões.
- **Nuance registrada no teste:** como no R, o join-back da forma com dedup **não** repete o filtro de
  número. Uma linha com número que compartilhe chave + logradouro com uma sem número seria atualizada. No
  laço isso é inócuo: essa combinação já passou pelo `pn0k` com a mesma chave, tabela e corte, e não teve
  candidato acima do corte, então `computed` não tem linha para ela.
- **Estado do Jaro, etapa a etapa** (`temp_lograd_determ` e `similaridade_logradouro` de todas as linhas
  após pn01…pl03, `large_sample`): **idêntico** nas 6 etapas.
- **Paridade de resultado (multiconjunto, lat/lon a 1e-9):**
  - antes × depois, `small_sample` e `large_sample` × `resultado_completo` × `resolver_empates`:
    **idêntico nas 8**;
  - R × Python, `large_sample`, 4 combinações: **idêntico nas 4**.
- **Tempo (Segment Heap, intercalado, 2 rodadas):**

  | | antes | depois |
  |---|---|---|
  | Jaro, 20k | 1,17 / 0,73 s | 0,45 / 0,54 s |
  | Total, 20k | 8,3 / 6,2 s | 6,1 / 6,6 s (ruído) |
  | Jaro, 1M | 27,1 / 25,3 s | 2,7 / 2,3 s (~10×) |
  | Total, 1M | 44,0 / 41,0 s | 18,9 / 18,9 s (~2,2×) |

  - O ganho em 1M está **inflado pela replicação**: cada combinação chave + logradouro aparece 50×, e o
    dedup colapsa isso. Em dados reais o ganho fica entre o de 20k e o de 1M.
  - **pn01 ficou mais lento** (0,6 → 1,2–1,5 s em 1M): na forma sem dedup, `GROUP BY` + `FIRST(... ORDER
    BY)` custou mais que o `RANK()` aqui. Foi mantido para o SQL ficar idêntico ao do R. O saldo é −23 s.
- `pytest -m r_parity` fica para o CI.
