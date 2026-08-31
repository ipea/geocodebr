# Port das mudanças do `r-package/NEWS.md` (dev version) para o Python — Rodada 2

**Status:** PLANO. Pendente de implementação.

**Repo:** `geocodebr` (monorepo). Pacote Python em `python-package/geocodebr/`; pacote R em
`r-package/R/` (fonte da verdade). Plano da rodada 1 em
[`python-port-news-dev-version.md`](python-port-news-dev-version.md) (CONCLUÍDO em 28/08).

## Contexto

A rodada 1 portou 12 itens do `r-package/NEWS.md` (seção *development version*) + 1 otimização
fora do NEWS (Etapa G, Jaro redundante), finalizada no commit `8b46620` (28/08, 15:24). Logo
após, o merge `1d8b214` (28/08, 15:30) trouxe do `main` **5 novos itens do NEWS.md**, adicionados
em 3 commits R posteriores à rodada 1:

| commit R | data | resumo |
|---|---|---|
| `28b0365` | 26/08 | performance dos empates (itens 1–5 da lista interna) + `empate` no ramo FALSE |
| `2cb0034` | 26/08 | fix regex `\\b` em ruas-data + "RUA QUATRO" na lista de ambíguos |
| `fd2e6e3` | 27/08 | guarda de nomes reservados em `check_clean_colnames` (a parte não-performance do plano de merge, que foi revertido) |

Este plano reflete, no código Python, essas 5 mudanças, preservando **paridade de output** com o
R. A varredura cruzou: (a) o diff `git diff 8b46620 HEAD -- r-package/NEWS.md` (isola só o que
entrou após a rodada 1), (b) o código R atual em `r-package/R/*.R` (fonte da verdade), (c) o
código Python atual em `python-package/geocodebr/*.py`, (d) os planos R
`quality_reports/plans/2026-08-26_empates-*.md`, `2026-08-27_*.md` e as entradas `[LEARN]` em
`MEMORY.md`.

## Decisões de escopo (a confirmar com o usuário, mas recomendadas)

- **Portar os 5 novos itens do NEWS.md** (Etapas A–E abaixo). Todos são correções de
  bugs/comportamento ou mudanças de output que afetam paridade.
- **NÃO portar** as otimizações de performance R que não têm contraparte útil no Python (ver
  §"Fora do NEWS.md — sem contraparte Python"). Justificado item a item.
- **Validação:** rodar primeiro os testes unitários Python (rápidos), depois os de regressão
  novos, depois a paridade R↔Python `test_r_python_parity.py -m r_parity` (exige `Rscript`).
- **Regressão:** criar testes novos que travem cada mudança (§"Testes novos").

## Resumo da varredura (5 novos itens do NEWS.md)

| # | Item do NEWS.md (novo) | Estado Python | Commit R | Ação | Etapa |
|---|---|---|---|---|---|
| 1 | etapa de empates mais eficiente (janelas só sobre empatados) | **PENDENTE** | `28b0365` | reescrever `trata_empates_geocode_duckdb` | **A** |
| 2 | `empate` no output com `resolver_empates=FALSE` mesmo sem `resultado_completo` | **PENDENTE** | `28b0365` | param `incluir_empate` em `merge_results_to_input` + chamada em `geocode.py` | **C** |
| 3 | rejeitar colunas de nomes reservados no input | **PENDENTE** | `fd2e6e3` | lista `reserved` em `check_clean_colnames` | **D** |
| 4 | fix regex `\\b` em ruas-data (era código morto) + exceção movida para dentro do braço do regex de números | **PENDENTE** | `2cb0034` | dentro da reescrita da Etapa A | **B** |
| 5 | "RUA QUATRO" na lista de logradouros ambíguos | **PENDENTE** | `2cb0034` | adicionar `QUATRO` em `cria_col_logradouro_confusao` | **E** |

## Fora do NEWS.md — sem contraparte Python (NÃO portar)

Duas mudanças R do commit `fd2e6e3` foram avaliadas e deliberadamente excluídas do escopo:

### (i) Registro do input: `dbWriteTable` em vez de `as_arrow_table` + `dbWriteTableArrow`

**R** (`geocode.R:346-358`): trocou `arrow::as_arrow_table(input_padrao)` +
`DBI::dbWriteTableArrow(...)` por `duckdb::dbWriteTable(con, "input_padrao_db", input_padrao)`.
Ganho medido em 43M: 88,5 s → 17,6 s (a conversão Arrow dominava o custo). Plano em
`2026-08-27_registro-input-padrao.md`.

**Python atual** (`geocode.py:123-126`): faz `con.register("input_padrao_view", df_padrao)` (polars)
+ `con.execute("CREATE TEMP TABLE input_padrao_db AS SELECT * FROM input_padrao_view")`. O caminho
polars→DuckDB **já é nativo e eficiente**, sem a conversão `as_arrow_table` que era o gargalo no
R. **Não há contraparte útil**: a otimização R resolve um custo que não existe no Python.

### (ii) Excluir `tempidgeocodebr` do `select_x` no merge + remover o drop explícito

**R** (`utils.R:191-200`, `geocode.R:531-532`): `merge_results_to_input` passou a fazer
`setdiff(select_columns, key_column)` no `select_x` (a chave fica de fora do SELECT mas segue
válida no JOIN/ORDER BY), e a linha `output_df[, tempidgeocodebr := NULL]` foi removida do
`geocode.R`. Micro-otimização para não materializar a coluna inteira que seria descartada.

**Python atual** (`utils.py:204`, `geocode.py:177-184`): resolve o mesmo problema (não vazar
`tempidgeocodebr` ao output) de outra forma — `merge_results_to_input` cria `geocodebr_result`
com a chave no SELECT, e um segundo passo faz `SELECT * EXCLUDE (tempidgeocodebr) FROM
geocodebr_result ORDER BY tempidgeocodebr`. Portar a versão R exigiria reestruturar os passos de
output (a chave precisa estar disponível para o `ORDER BY` final mesmo não estando no SELECT da
tabela intermediária), **sem ganho real** no caminho polars/arrow (não há o custo de
materialização do R). **Não portar** — o Python já não vaza a coluna e o custo é desprezível.

> Nota: o hack em `geocode.py:167-168` (`if resultado_completo and "empate" not in
> db_table_columns(...)`) **será removido** como parte da Etapa C — ele é substituído pelo ramo
> `n_casos==0` do `trata_empates` adicionando a coluna `empate` em `output_db`, alinhando ao R.

---

## Detalhe das mudanças a implementar

### A. Item 1 — Reescrever `trata_empates_geocode_duckdb` (split + `ids_empatados` + `empates_classif` + passthrough)

**Arquivos:** `python-package/geocodebr/matching.py` (`trata_empates_geocode_duckdb`)

Esta é a mudança mais ALFA: reescreve a função inteira. Inclui naturalmente a Etapa B (fix do
regex), já que o predicado do ramo "perdidos" é reconstruído.

**R** (`r-package/R/trata_empates_geocode_duckdb.R`, HEAD): a função agora tem 3 fases:
1. Cria `ids_empatados` (TEMP TABLE com os `tempidgeocodebr` que têm >1 resultado) **antes** dos
   early-returns. `n_casos_empate` lê de `ids_empatados`.
2. Ramo `n_casos==0`: `ALTER TABLE output_db ADD COLUMN IF NOT EXISTS empate BOOLEAN DEFAULT
   FALSE` e retorna 0. (Pré-existente no R desde antes da rodada 1; no Python hoje falta.)
3. Ramo `resolver_empates=FALSE`: em vez de `CREATE output_db2 AS SELECT *, (COUNT(*) OVER >
   1) AS empate FROM output_db` (cópia integral + window function sobre 1M linhas), faz
   `ALTER output_db ADD COLUMN empate DEFAULT FALSE` + `UPDATE ... SET empate=TRUE WHERE
   tempidgeocodebr IN (SELECT ... FROM ids_empatados)` + `ALTER TABLE output_db RENAME TO
   output_db2` (variante C do plano `2026-08-26_empates-item-5.md` — zero cópia).
4. Ramo `resolver_empates=TRUE`: cria `empates_classif` (TEMP TABLE) rodando `ROW_NUMBER`,
   `LAG+haversine`, `COUNT/MAX OVER` **só sobre os empatados** (`WHERE EXISTS (SELECT 1 FROM
   ids_empatados i WHERE i.tempidgeocodebr = o.tempidgeocodebr)`). Sem `empate_inicial`, sem
   `CASE WHEN empate_inicial THEN haversine` (haversine direto — o `LAG` da 1ª linha é NULL e
   propaga). Depois monta `output_db2` como `UNION ALL` de D/E/F (de `empates_classif`) + um
   **passthrough** dos não-empatados (`SELECT ... FROM output_db o WHERE NOT EXISTS (SELECT 1
   FROM ids_empatados i WHERE i.tempidgeocodebr = o.tempidgeocodebr)`). O `empates_restantes`
   perdeu o `NOT EXISTS` contra `df_sem_empate` (porque agora `empate` é constante por grupo e
   `empate=TRUE` já exclui D).

**Python atual** (`matching.py:282-436`): é a versão ANTIGA — roda window functions sobre
`output_db` inteiro, com `empate_inicial`, `CASE WHEN empate_inicial THEN haversine`, filtro
`(empate_inicial IS FALSE) OR (empate_inicial AND dist IS NULL) OR (empate_inicial AND
dist>300)`, `empates_restantes` com `NOT EXISTS` contra `df_sem_empate`, sem `ids_empatados`,
sem `empates_classif`, sem passthrough.

**Mudança:** reescrever `trata_empates_geocode_duckdb` espelhando o R (HEAD) —
`r-package/R/trata_empates_geocode_duckdb.R:1-310`. Pontos exatos:
- Criar `ids_empatados` no início (`R:13-20`).
- `n_casos_empate = SELECT COUNT(*) FROM ids_empatados` (`R:22-25`).
- Ramo `n_casos==0`: `ALTER TABLE output_db ADD COLUMN IF NOT EXISTS empate BOOLEAN DEFAULT
  FALSE` (`R:29-39`). **Isto substitui o hack de `geocode.py:167-168`** (ver Etapa C).
- Ramo FALSE: ALTER + UPDATE + RENAME (`R:46-67`), mantendo o `cli_warn` (no Python, equivalente
  — hoje a função apenas retorna; verificar se há warning a emitir; o R emite `cli_warn`
  instruindo a inspecionar a coluna `empate`).
- Ramo TRUE: `empates_classif` (`R:140-183`) + `output_db2` com D/E/F + passthrough
  (`R:188-300`). Preservar: macro `haversine`, ordenação `contagem_cnefe DESC, desvio_metros,
  endereco_encontrado`, filtro `logradouro_encontrado IS NOT NULL` no ramo E, `QUALIFY
  ROW_NUMBER() ... = 1` em E e F.
- `cols_passthrough` (`R:108,126-130`): quando `resultado_completo=TRUE`, o passthrough dos
  não-empatados vem de `output_db` (que não tem `empate`), então `FALSE AS empate` entra como
  literal na posição esperada pelo `UNION ALL`.

**Atenção — `empate_inicial` removido:** a versão nova não tem `empate_inicial` nem o `CASE WHEN`
na haversine. A haversine roda direta; na 1ª linha de cada grupo o `LAG` é NULL → haversine é NULL
→ passa pelo filtro `dist IS NULL`. Comportamento idêntico ao anterior, mas sem o branch.

**Atenção — `NOT EXISTS` contra `df_sem_empate` removido de `empates_restantes`:** na versão nova,
`empate` é constante por `tempidgeocodebr` (todos os membros de um grupo vêm do mesmo filtro de
300 m). Então `WHERE empate=TRUE` em `empates_restantes` já exclui os grupos de D sem anti-join.
Mantém-se apenas o `NOT EXISTS` contra `df_empates_perdidos` (E).

### B. Item 4 — Fix do regex `\\b` em ruas-data + reestruturação do predicado (dentro da Etapa A)

**Arquivo:** `python-package/geocodebr/matching.py` (ramo E de `trata_empates`)

**R** (`trata_empates_geocode_duckdb.R:228-237`): dois defeitos corrigidos:
1. **Escape `\\b`:** o fonte R era `'\\\\bDE (JANEIRO|...)\\\\b'` → RE2 recebia `\\b` (backslash
   literal + "b") = **código morto**. Agora é `'\\bDE (...)\\b'` → RE2 recebe `\b` = fronteira de
   palavra. Entrada `[LEARN:duckdb]` em `MEMORY.md:196-206`.
2. **Estrutura do predicado:** a exceção de datas estava no nível superior do `AND` (`AND NOT
   REGEXP_MATCHES(...)` junto com `max_dist > 1000 OR log_causa_confusao OR REGEXP(...)`), o que
   anularia o critério `max_dist > 1000` para ruas-data (uma "RUA QUINZE DE NOVEMBRO" a 5 km
   cairia na média ponderada em vez de "perdido"). Agora a exceção está **dentro do braço do
   regex de números por extenso**: `OR (REGEXP_MATCHES(endereco_encontrado, '(RUA
   (QUATRO|...))') AND NOT REGEXP_MATCHES(logradouro_encontrado, '\\bDE (...)\\b'))`. Assim a
   exceção neutraliza APENAS o braço do regex; ruas-data a >1 km continuam "perdidos" via
   `max_dist`.

**Python atual** (`matching.py:390-394`): tem **os dois bugs** — (a) usa `'\\\\b'` (4 barras na
f-string → RE2 recebe `\\b` literal = código morto, idêntico ao bug R); (b) a exceção de datas
está no nível superior do predicado, mesma estrutura incorreta.

**Mudança:** dentro da reescrita da Etapa A, reproduzir o predicado do R (HEAD):
```sql
AND logradouro_encontrado IS NOT NULL
AND (
  max_dist > 1000
  OR log_causa_confusao
  OR (
    REGEXP_MATCHES(endereco_encontrado,
        '(RUA (QUATRO|QUATORZE|QUINZE|DEZESSEIS|DEZESSETE|DEZOITO|DEZENOVE|VINTE|TRINTA|QUARENTA|CINQUENTA|SESSENTA|SETENTA|OITENTA|NOVENTA))'
    )
    AND NOT REGEXP_MATCHES(logradouro_encontrado, '\\bDE (JANEIRO|FEVEREIRO|MARCO|ABRIL|MAIO|JUNHO|JULHO|AGOSTO|SETEMBRO|OUTUBRO|NOVEMBRO|DEZEMBRO)\\b')
  )
)
```
Sobre o escape no Python: a query está numa f-string comum (`f"""..."""`); usar `'\\b'` (2 barras
na fonte → Python emite `\b` → RE2 interpreta como word boundary). **Não** usar raw string aqui
porque a f-string tem interpolações (`{cols_encontradas}`); o padrão `'\\b'` equivale ao `'\\b'`
do R. (Comparar com `cria_col_logradouro_confusao` em `utils.py:225-233`, que usa `rf"""..."""` e
`\b` direto — funciona porque é raw; os dois estilos chegam ao mesmo RE2.)

> **Depende da Etapa A:** o predicado vive no ramo E da função reescrita. Fazê-lo junto evita
> tocar a mesma string duas vezes.

### C. Item 2 — Coluna `empate` no output com `resolver_empates=FALSE` mesmo sem `resultado_completo`

**Arquivos:** `python-package/geocodebr/utils.py` (`merge_results_to_input`),
`python-package/geocodebr/geocode.py`

**R** (`utils.R:137-228`, `geocode.R:513-521`): `merge_results_to_input` ganhou param
`incluir_empate = FALSE`. Se `incluir_empate=TRUE && resultado_completo=FALSE`, adiciona `'empate'`
a `select_columns_y` (`utils.R:161-163`). `geocode.R:520` chama com
`incluir_empate = isFALSE(resolver_empates)`. Com `resultado_completo=TRUE`, `empate` já entra na
lista maior e `incluir_empate` é ignorado.

**Python atual:**
- `merge_results_to_input` (`utils.py:167-215`) **não tem** `incluir_empate`. `select_columns_y`
  inclui `empate` só quando `resultado_completo=True`.
- `geocode.py:165-175`: não passa `incluir_empate`. Há um hack em `geocode.py:167-168`
  (`if resultado_completo and "empate" not in db_table_columns(...): ALTER ... ADD COLUMN empate`)
  que cobre só o caso `resultado_completo=True` com zero empates. Com
  `resolver_empates=False, resultado_completo=False`, a coluna `empate` seria selecionada pelo
  merge (depois desta etapa) mas não existe em `output_db2` → erro.

**Mudança:**
- `merge_results_to_input(..., incluir_empate: bool = False)`: adicionar param. Se
  `incluir_empate and not resultado_completo`, estender `select_columns_y` com `"empate"` (antes
  do bloco `if resultado_completo`, espelhando `R:161-163`).
- `geocode.py`: passar `incluir_empate=not resolver_empates` na chamada do merge (`geocode.py:169-175`).
- **Remover** o hack `geocode.py:167-168`: com a Etapa A, o ramo `n_casos==0` do `trata_empates`
  já adiciona `empate` (DEFAULT FALSE) a `output_db`, e o ramo FALSE adiciona via
  ALTER+UPDATE+RENAME a `output_db2`. A coluna sempre existe quando o merge a seleciona.

### D. Item 3 — Rejeitar colunas de nomes reservados no input

**Arquivo:** `python-package/geocodebr/utils.py` (`check_clean_colnames`)

**R** (`utils.R:651-672`): `check_clean_colnames` tem uma lista `reserved` (17 nomes) e aborta com
`cli_abort` se alguma coluna do input bate. Lista: `tempidgeocodebr, lat, lon, precisao,
tipo_resultado, desvio_metros, endereco_encontrado, logradouro_encontrado, numero_encontrado,
cep_encontrado, localidade_encontrada, municipio_encontrado, estado_encontrado,
similaridade_logradouro, contagem_cnefe, empate, cod_setor`.

**Python atual** (`utils.py:36-42`): só checa caracteres inválidos (`^[A-Za-z0-9_]+$`), sem
checar nomes reservados.

**Mudança:** adicionar a mesma lista `RESERVED_COLUMN_NAMES` (preferivelmente como constante em
`constants.py` para reuso/teste) e abortar com `ValueError` listando as colunas ofensoras, no
mesmo espírito da mensagem R ("renomeie estas colunas antes de chamar a função"). Manter a
verificação de caracteres inválidos existente.

**Atenção:** nenhum teste Python atual usa nomes reservados no **input** (confirmado por grep —
`lat`/`lon`/`cod_setor`/etc. aparecem só nos parquets fake do **CNEFE**, não no input). Logo a
guarda nova não quebra testes existentes. (`enderecos` de teste usa `uf`, `cidade`, `rua`, `num`,
`cep_in`, `bairro`.)

### E. Item 5 — "RUA QUATRO" na lista de logradouros ambíguos

**Arquivo:** `python-package/geocodebr/utils.py` (`cria_col_logradouro_confusao`)

**R** (`utils.R:588-608`): `ruas_num_ext` agora inclui `'QUATRO'` entre `TRES` e `CINCO`. Antes a
enumeração era `UM, DOIS, TRES, CINCO, ..., TREZE` — pulava o 4. Consequência (medida no 1M):
"RUA QUATRO" sem match exato casava por similaridade com "RUA QUATORZE" (Jaro 0,911, acima de
todos os cutoffs); agora cai para categorias de menor precisão.

**Python atual** (`utils.py:220-222`): a lista é `["UM", "DOIS", "TRES", "CINCO", "SETE", ...]`
— **sem `QUATRO`** (e observa-se que também falta `SEIS` entre `CINCO` e `SETE`!). Bug duplo em
relação ao R.

**Mudança:** alinhar a lista exatamente ao R — `["UM", "DOIS", "TRES", "QUATRO", "CINCO", "SEIS",
"SETE", "OITO", "NOVE", "DEZ", "ONZE", "DOZE", "TREZE"]`. (O R segue esta ordem exata em
`utils.R:591-604`.)

> **Atenção ao `SEIS`:** o Python atual também omite `SEIS` (pula de `CINCO` para `SETE`). Isto
> não está citado no NEWS.md (o R só documentou a lacuna do `QUATRO`), mas é uma divergência
> adicional do Python em relação ao R. **Corrigir os dois** na mesma edição para alinhar
> completamente a lista ao R.

---

## Testes novos a criar

Arquivo: `python-package/tests/test_regression_news_port_2.py` (novo), seguindo o padrão de
`test_regression_news_port.py` (parquet fake no `tmp_path` +
`definir_pasta_cache(str(tmp_path), verboso=False)`, helper `_write_all_cnefe`,
`_base_cnefe_table`). O `conftest.py` (autouse `restore_cache_config`) já cuida do side-effect de
`definir_pasta_cache`.

1. **`test_empates_resolver_false_inclui_coluna_empate`** — Etapa C. Input que produz empate;
   `resolver_empates=False, resultado_completo=False`; assert que a coluna `empate` está no
   output, com `TRUE` nas linhas empatadas e `FALSE` nas não empatadas. **Trava item 2.**
2. **`test_geocode_rejeita_colunas_reservadas`** — Etapa D. Input com coluna `lat` (ou
   `tipo_resultado`); assert que `geocode()` levanta `ValueError` mencionando a coluna. **Trava
   item 3.**
3. **`test_empates_rua_data_media_ponderada`** — Etapa B. Empate entre candidatos de uma
   "RUA QUINZE DE NOVEMBRO" a <1 km (max_dist <= 1000); assert que o resultado é a **média
   ponderada** (ramo F/salváveis), não o top do ranking (ramo E/perdidos). Antes do fix, a exceção
   de datas era código morto e o caso ia para "perdidos". **Trava item 4.**
4. **`test_rua_quatro_excluida_match_probabilistico`** — Etapa E. Input "RUA QUATRO" sem match
   exato; CNEFE tem "RUA QUATORZE" (Jaro alto); assert que **não** casa via probabilístico
   (`tipo_resultado` não é `pn*`/`pa*`/`pl*`), caindo para categoria de menor precisão ou `NA`.
   Pode ser feito também como teste unitário direto sobre `cria_col_logradouro_confusao`
   (verificar que "RUA QUATRO" seta `log_causa_confusao=TRUE`). **Trava item 5.**
5. *(opcional)* **`test_empates_passthrough_preserva_nao_empatados`** — Etapa A. Mix de
   endereços: alguns sem empate (match único), outros com empate a <300 m; assert que o output
   tem uma linha por input e que os não-empatados vêm com `empate=FALSE` e coordenadas iguais às
   do CNEFE. **Trava a estrutura do passthrough (item 1).**

Os testes 1 e 2 da rodada 1 (`test_geocode_empates_lag_under_300m`,
`test_geocode_lograd_encontrado_sem_completo` em `test_regression_news_port.py`) **devem
continuar passando** — a reescrita da Etapa A preserva a semântica do LAG e do
`logradouro_encontrado` populado. Rodá-los como gate de regressão da Etapa A.

## Ordem de execução recomendada

1. **E** (item 5): adicionar `QUATRO` (e `SEIS`) em `cria_col_logradouro_confusao`. Isolado, sem
   dependências.
2. **D** (item 3): guarda de nomes reservados em `check_clean_colnames`. Isolado.
3. **A + B** (itens 1 + 4): reescrever `trata_empates_geocode_duckdb` (inclui o fix do regex e a
   reestruturação do predicado do ramo E). Feitas juntas porque o predicado vive dentro da função
   reescrita.
4. **C** (item 2): param `incluir_empate` em `merge_results_to_input` + chamada em `geocode.py` +
   remover o hack `geocode.py:167-168`. Depende de A (ramo `n_casos==0` agora adiciona `empate`).
5. **Novos testes:** os 4–5 testes listados acima.
6. **Rodar testes unitários** (rápidos, sem R):
   ```
   cd python-package && python -m pytest tests/test_geocode.py tests/test_busca_por_cep.py tests/test_geocode_reverso.py tests/test_regression_news_port.py tests/test_regression_news_port_2.py -v
   ```
7. **Rodar paridade R↔Python** (gate de fidelidade; exige R instalado):
   ```
   cd python-package && python -m pytest tests/test_r_python_parity.py -m r_parity -v
   ```

## Pontos de atenção / riscos

- **Invariante 1 do `CLAUDE.md`** (ordem `da*` depois de `dn*`, evita divisão por zero no IDW):
  **não tocada** — a ordem de `ALL_POSSIBLE_MATCH_TYPES` é a mesma.
- **`tempidgeocodebr`** não é tocada em nenhuma etapa.
- **`data_release`** é `v0.4.1` em ambos os pacotes (`r-package/R/cache.R:1`;
  `python-package/geocodebr/constants.py:1`) — sem mudança.
- **A reescrita do `trata_empates`** é a mudança mais delicada. Preservar exatamente: a macro
  `haversine`, a ordenação `contagem_cnefe DESC, desvio_metros, endereco_encontrado` (em
  `ROW_NUMBER`, `QUALIFY` de E e F), o filtro `logradouro_encontrado IS NOT NULL` no ramo E, o
  corte de 300 m, o corte de 1000 m, e o `GROUP BY tempidgeocodebr` na média ponderada de F.
- **`empate` como coluna dinâmica:** no ramo `n_casos==0` e no ramo FALSE, `empate` nasce via
  `ALTER ... DEFAULT FALSE` + `UPDATE`; no ramo TRUE, nasce como literal no `SELECT` de cada
  ramo do `UNION ALL` (D: `empate`, E: `TRUE AS empate`, F: `TRUE AS empate`, passthrough:
  `FALSE AS empate` quando `resultado_completo=TRUE`). Reproduzir fielmente — ver
  `[LEARN:duckdb]` em `MEMORY.md:98-112` sobre por que **não** pré-declarar `empate` no schema
  de `output_db` (colisão silenciosa com CTEs downstream).
- **Paridade R↔Python:** a Etapa A alinha o Python ao R atual (que é a fonte da verdade). O teste
  de paridade `test_r_python_parity.py` deve continuar passando; idealmente, a reescrita reduz
  divergências pré-existentes. Nota: em bases grandes com `n_cores` default, `identical()` bit a
  bit é inatingível no caminho de empates (média ponderada acumula em ordem dependente do
  paralelismo, divergência ~ulp — `[LEARN:testes]` em `MEMORY.md:208-216`); comparar com
  `n_cores=1` ou tolerância.
- **Aviso no ramo FALSE:** o R emite um `cli_warn` instruindo o usuário a inspecionar a coluna
  `empate`. O Python atual não emite warning nesse ramo — avaliar se vale alinhar (emitter um
  `warnings.warn` ou print). Não é estritamente parte do NEWS.md, mas acompanha a Etapa C (a
  mensagem faz sentido só se a coluna `empate` chega ao output, que é o que a Etapa C garante).
- **`SEIS` além de `QUATRO`:** o Python atual também omite `SEIS` da lista de ambíguos (pula de
  `CINCO` para `SETE`). Não está no NEWS.md, mas é divergência em relação ao R. Corrigir os dois
  na Etapa E.

## Verificações pós-implementação

- [ ] Testes unitários Python passam (`test_geocode`, `test_busca_por_cep`,
      `test_geocode_reverso`, `test_cache`, `test_fields`).
- [ ] Testes de regressão da rodada 1 (`test_regression_news_port.py`, 8 testes) continuam
      passando — gate de não-regressão da Etapa A.
- [ ] Testes de regressão da rodada 2 (`test_regression_news_port_2.py`, 4–5 testes) passando.
- [ ] Paridade R↔Python: `test_geocode_matches_r_small_sample` passa.
- [ ] `resolver_empates=False, resultado_completo=False` inclui coluna `empate` no output.
- [ ] Input com coluna `lat` é rejeitado com mensagem útil.
- [ ] "RUA QUATRO" não casa via probabilístico com "RUA QUATORZE".

## Arquivos a modificar (resumo)

**Pacote (`python-package/geocodebr/`):**
- `matching.py` — reescrita de `trata_empates_geocode_duckdb` (Etapas A+B): `ids_empatados`,
  ramo `n_casos==0` com ALTER, ramo FALSE com ALTER+UPDATE+RENAME, ramo TRUE com
  `empates_classif` + passthrough; fix do regex `\\b` e reestruturação do predicado do ramo E.
- `utils.py` — `merge_results_to_input` com param `incluir_empate` (Etapa C); guarda de nomes
  reservados em `check_clean_colnames` (Etapa D); `cria_col_logradouro_confusao` com `QUATRO`
  e `SEIS` (Etapa E).
- `geocode.py` — passar `incluir_empate=not resolver_empates` ao merge; remover o hack
  `geocode.py:167-168` (Etapa C).
- `constants.py` — (opcional) constante `RESERVED_COLUMN_NAMES` (Etapa D).

**Testes (`python-package/tests/`):**
- `test_regression_news_port_2.py` — **novo**, 4–5 testes de regressão (Etapas A–E).

## Referências de código (linha-de-arquivo)

| Assunto | R (HEAD) | Python (atual → alvo) |
|---|---|---|
| `trata_empates` reescrita (ids_empatados, empates_classif, passthrough) | `r-package/R/trata_empates_geocode_duckdb.R:1-310` | `python-package/geocodebr/matching.py:282-436` (Etapa A) |
| Ramo `n_casos==0` adiciona `empate` | `r-package/R/trata_empates_geocode_duckdb.R:29-39` | `python-package/geocodebr/matching.py:300-301` (Etapa A) |
| Ramo FALSE: ALTER+UPDATE+RENAME | `r-package/R/trata_empates_geocode_duckdb.R:46-67` | `python-package/geocodebr/matching.py:303-312` (Etapa A) |
| Regex `\\b` + predicado ramo E | `r-package/R/trata_empates_geocode_duckdb.R:228-237` | `python-package/geocodebr/matching.py:390-394` (Etapa B) |
| `incluir_empate` em `merge_results_to_input` | `r-package/R/utils.R:137-228` (param 144, lógica 161-163) | `python-package/geocodebr/utils.py:167-215` (Etapa C) |
| Chamada com `incluir_empate = isFALSE(resolver_empates)` | `r-package/R/geocode.R:513-521` | `python-package/geocodebr/geocode.py:165-175` (Etapa C) |
| Nomes reservados em `check_clean_colnames` | `r-package/R/utils.R:651-672` | `python-package/geocodebr/utils.py:36-42` (Etapa D) |
| `cria_col_logradouro_confusao` com `QUATRO` (+ `SEIS`) | `r-package/R/utils.R:588-608` | `python-package/geocodebr/utils.py:218-235` (Etapa E) |

---

*Plano gerado a partir da varredura do diff `git diff 8b46620 HEAD -- r-package/NEWS.md` (5 novos
itens após a rodada 1) contra o código R atualizado (`r-package/R/*.R`) e o port Python em
`python-package/geocodebr/*.py`. Adota as convenções de `CLAUDE.md` (princípio `R/` autoritativo;
paridade preservada; portões de qualidade testes + paridade no Python). Otimizações R sem
contraparte Python (registro do input via Arrow→dbWriteTable; exclusão do `tempidgeocodebr` do
`select_x`) deliberadamente excluídas com justificativa.*
