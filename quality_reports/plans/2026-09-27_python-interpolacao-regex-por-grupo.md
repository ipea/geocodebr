# Plano — Python: regex uma vez por grupo e `GROUP BY` curto na interpolação (lição 4)

**Status:** APPROVED (27/09) — implementado; ver "Resultado" no fim
**Data:** 27/09/2026
**Origem:** lição B3 de `quality_reports/diagnoses/2026-09-23_licoes-cruzadas-geocode-R-Python.md`
**Princípio:** portar o que o R já faz, com o mínimo de código, sem mudar nenhum resultado.

---

## Como o R faz (`match_weighted_cases.R:38-114`, `match_weighted_cases_probabilistic.R:70-168`)

Nas etapas de interpolação (`da01`–`da04`, `pa01`–`pa03`), cada endereço do input casa com ~17–21
candidatos do CNEFE, que são agrupados para a média ponderada. O R:

1. **não** aplica o regex no CTE: carrega `{y}.endereco_completo` cru, mais as "colunas livres";
2. aplica o regex **uma vez por grupo**, no `SELECT` agregado:
   `REGEXP_REPLACE(FIRST(endereco_completo {ordem_first}), ', \d+ -', CONCAT(', ', numero, ' (aprox) -'))`;
3. agrupa por colunas curtas, `GROUP BY tempidgeocodebr, numero {grp_livres}`, em vez da string
   `endereco_encontrado` (~70 bytes).

As **colunas livres** são as colunas de `y` que compõem `endereco_completo` e não estão fixadas pelo join:
```r
cols_livres <- setdiff(intersect(c("cep", "localidade"), strsplit(y, "_")[[1]]), key_cols)
```
| Etapa | Tabela `y` | Chave (sem número) | Colunas livres |
|---|---|---|---|
| da01, pa01 | `..._numero_cep_localidade` | cep, localidade | — |
| da02, pa02 | `..._numero_cep_localidade` | cep | localidade |
| da03, pa03 | `..._numero_localidade` | localidade | — |
| da04 | `..._numero_localidade` | — | localidade |

## Como o Python faz hoje (`matching.py:92-146` e `202-273`)

- No CTE, `REGEXP_REPLACE({y}.endereco_completo, ...) AS endereco_encontrado` roda **em cada linha
  candidata**.
- O agregado faz `GROUP BY tempidgeocodebr, endereco_encontrado`, com hash de uma string por candidato.
- Há ainda uma coluna `ABS(numero - numero_cnefe) AS distancia_numero` no CTE que **nenhuma** parte da
  query lê. O R não a tem.

**Medido pelo agente 2:** da01 em 1M, 1,94–2,25 s (Python) vs 1,00–1,33 s (forma R), com resultado
idêntico. É cerca de −45% por etapa, em 7 etapas. Sem diferença em 20k.

---

## A premissa de paridade — verificada nos dados nacionais

As duas formas só dão o mesmo resultado se a partição `(tempidgeocodebr, endereco_encontrado)` for igual a
`(tempidgeocodebr, numero, cols_livres)`. Isso depende do CNEFE, não do código. Conferi em **todas** as
linhas das duas tabelas usadas pela interpolação (release v0.5.0, ~100 M linhas), com o número trocado
por um marcador fixo:

| Teste | `..._numero_cep_localidade` (50,2 M) | `..._numero_localidade` (50,0 M) |
|---|---|---|
| Linhas em que o regex não acha `, <número> -` | 0 | 0 |
| (a) grupos da tabela com mais de uma string (a string é constante no grupo) | 0 | 0 |
| (b) chaves em que nº de localidades distintas ≠ nº de strings distintas (NULL contado como valor) | 0 | 0 |
| strings compartilhadas por mais de uma localidade | 0 | 0 |
| localidade literal `'NA'` (colidiria com NULL, que vira "NA" na string) | 0 | 0 |

Então a partição é a mesma nos dois jeitos, para os dados atuais. **Ressalva:** isso é uma propriedade do
release. O R depende da mesma premissa (comentário em `match_weighted_cases.R:38-46`), então um release
novo que a quebrasse afetaria os dois pacotes igualmente, e a paridade continuaria. Mesmo assim, vale
rodar essa checagem ao trocar o `DATA_RELEASE`.

---

## Mudança (~20 linhas, 1 arquivo: `python-package/geocodebr/matching.py`)

1. **Helper novo** (≈8 linhas), espelhando o R:
   ```python
   def _cols_livres(y: str, key_cols: list[str]) -> tuple[str, str]:
       """Colunas de y que compõem endereco_completo e não são fixadas pelo join
       (espelha cols_livres do R). A partição por (tempidgeocodebr, numero,
       cols_livres) é a mesma que por endereco_encontrado, mas com chave curta e
       o regex rodando 1x por grupo."""
       livres = [c for c in ("cep", "localidade") if c in y.split("_") and c not in key_cols]
       sel = "".join(f", {y}.{c} AS {c}_cnefe" for c in livres)
       grp = "".join(f", {c}_cnefe" for c in livres)
       return sel, grp
   ```
2. **Em `match_weighted_cases` e `match_weighted_cases_probabilistic`**, as mesmas 4 trocas:
   - `sel_livres, grp_livres = _cols_livres(y, key_cols)` (1 linha);
   - no CTE, **remover** `ABS(...) AS distancia_numero` e trocar a linha do `REGEXP_REPLACE(...) AS
     endereco_encontrado` por `{y}.endereco_completo{sel_livres},`;
   - no agregado, trocar `FIRST(endereco_encontrado {ordem_first}) AS endereco_encontrado` por
     `REGEXP_REPLACE(FIRST(endereco_completo {ordem_first}), ', \\d+ -', CONCAT(', ', numero, ' (aprox) -')) AS endereco_encontrado`;
   - `GROUP BY tempidgeocodebr, endereco_encontrado` → `GROUP BY tempidgeocodebr, numero {grp_livres}`.

Nada muda em assinaturas, chamadores, pesos, `ordem_first` ou nas colunas `*_encontrado`.

---

## Por que o resultado não muda

- **Mesmos grupos:** a partição é idêntica (tabela acima). `numero` é constante por `tempidgeocodebr`,
  então entrar no `GROUP BY` não divide grupo nenhum. É só o que permite usá-lo fora de agregação no
  `CONCAT`.
- **Mesma string:** dentro de um grupo, todas as linhas têm a mesma string depois do regex (teste (a)).
  Então `regex(FIRST(endereco_completo ORDER BY ...))` = `FIRST(regex(endereco_completo) ORDER BY ...)`.
- **Mesmas médias e `FIRST`s:** `lat`, `lon`, `desvio_metros`, `contagem_cnefe`, `log_causa_confusao`,
  `*_encontrado` e `similaridade_logradouro` são agregados sobre os mesmos grupos, com o mesmo
  `ordem_first`.
- **`distancia_numero`** não é lida em lugar nenhum. Removê-la não afeta nada.
- **É a query do R**, que já passou `identical()` antes/depois com essa mudança.

---

## Verificação (paridade com `large_sample`, ~20 mil linhas)

1. **Testes unitários existentes** de interpolação continuam verdes. **Um teste novo** em
   `tests/test_matching.py`: `da02` com um endereço cujos candidatos estão em duas localidades
   diferentes. Tem que dar 2 linhas em `output_db` (empate), cada uma com a média da sua localidade e o
   `endereco_encontrado` com `"<numero> (aprox)"`, como hoje.
2. **Checagem fina, direto no `output_db`:** instrumentar `match_weighted_cases*` e, depois de cada
   etapa `da*`/`pa*`, gravar as linhas inseridas em `output_db` (todas as colunas). Comparar antes × depois
   etapa a etapa, como multiconjunto, com lat/lon a 1e-9. Isso pega divergência antes do desempate, que
   poderia mascará-la.
3. **Antes × depois, mesmo pacote:** `geocode()` em `large_sample` (e `small_sample`) nas 4 combinações de
   `resultado_completo` × `resolver_empates`, com o multiconjunto de linhas idêntico. Baseline:
   `uid_l2_*`, o estado atual, com as lições 1, 2, 3 e 5.
4. **R × Python:** as 4 combinações de `large_sample` contra `uid_R_large_*`, com multiconjunto idêntico.
5. **Ganho:** tempo acumulado nas 7 etapas de interpolação, antes × depois, em 20k e 1M (intercalado,
   Segment Heap).
6. `pytest -m r_parity` fica para o CI.

## Arquivos

- `python-package/geocodebr/matching.py` (helper + 2 queries)
- `python-package/tests/test_matching.py` (1 teste)
- `python-package/CHANGELOG.md` ("Modificado": interpolação mais rápida, resultado igual)
- R: nada.

**Total estimado:** ~20 linhas de código + ~35 de teste.

## Resultado (27/09/2026)

Implementado como planejado: helper `_cols_livres()` e as 4 trocas nas duas queries de `matching.py`
(diff conferido contra o snapshot pré-mudança), 1 teste novo em `tests/test_matching.py`.

- **Suíte unitária:** 175 passed.
- **Linhas inseridas em `output_db` por etapa** (da01…da04, pa01…pa03, `large_sample`, com e sem
  `resultado_completo`): **idêntico nas 14**. Checado antes do desempate, então nenhuma divergência fica
  mascarada.
- **Paridade de resultado (multiconjunto, lat/lon a 1e-9):**
  - antes × depois, `small_sample` e `large_sample` × `resultado_completo` × `resolver_empates`:
    **idêntico nas 8**;
  - R × Python, `large_sample`, 4 combinações: **idêntico nas 4**.
- **Tempo (Segment Heap, intercalado, 2 rodadas):**

  | | antes | depois |
  |---|---|---|
  | 7 etapas de interpolação, 20k | 2,37 / 1,79 s | 1,79 / 1,78 s (ruído) |
  | 7 etapas de interpolação, 1M | 6,35 / 6,26 s | 3,06 / 3,92 s (~1,8×) |
  | Total, 1M | 21,4 / 24,8 s | 16,8 / 24,0 s (ruído) |

  O tempo de `da03` inclui a materialização da tabela `..._numero_localidade`, igual nos dois lados.
- `pytest -m r_parity` fica para o CI.
