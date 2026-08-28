# Port das mudanças do `r-package/NEWS.md` (dev version) para o Python

**Status:** Em implementação. Etapas A–F concluídas e validadas (paridade R↔Python OK).
Etapa G (otimização Jaro redundante, fora do NEWS.md) adicionada ao escopo a pedido.

**Repo:** `geocodebr` (monorepo). Pacote Python em `python-package/geocodebr/`; pacote R em
`r-package/R/`.

## Contexto

O pacote R foi atualizado e a seção *geocodebr (development version)* do `r-package/NEWS.md`
traz 12 mudanças (major / minor / bug fixes). O port Python já existente em
`python-package/geocodebr/` foi gerado a partir de uma versão anterior; este plano reflete,
no código Python, apenas as mudanças do NEWS.md que fazem sentido portar (correção de bugs +
ganho de performance alinhado ao R), preservando **paridade de output** com o R.

A varredura completa cruzou cada item do NEWS.md com:
- o código R atual em `r-package/R/*.R` (fonte da verdade);
- o código Python atual em `python-package/geocodebr/*.py`;
- o teste de paridade `python-package/tests/test_r_python_parity.py`.

## Decisões confirmadas com o usuário

- **Escopo:** focar apenas nas 6 mudanças que ainda divergem do R. As outras 6 já estão
  alinhadas no Python (ver §"Resumo da varredura").
- **Validação:** rodar primeiro os testes unitários Python (rápidos) e, se passarem, rodar o
  teste de paridade R↔Python `test_r_python_parity.py -m r_parity` (instala o pacote R local
  em lib temporária — exige `Rscript` no PATH).
- **Regressão:** criar testes unitários novos que travem cada bug corrigido.

## Resumo da varredura (12 itens do NEWS.md)

| # | Item do NEWS.md | Estado Python | Ação |
|---|---|---|---|
| 1 | `geocode_reverso` usa tabela `municipio_logradouro_cep_localidade` | **Já alinhado** (`reverse.py:28,64`) | só ajustar `test_geocode_reverso.py:24` (ainda escreve parquet fake no nome velho `_numero_cep_localidade`) |
| 2 | colunas extras vêm do ponto com número mais próximo (reprodutível) | **PENDENTE** | reescrever `match_weighted_cases` + `_probabilistic` |
| 3 | pular etapas internas sem campo declarado | **PENDENTE** | propagar `campos_nao_declarados` para o laço |
| 4 | documentação de empates <300m | N/A (docs Roxygen) | — |
| 5 | baixar só tabelas necessárias | **PENDENTE** | `tabelas_necessarias()` + generalizar `download_cnefe` |
| 6 | fechar DuckDB mesmo com erro | **Já alinhado** (`try/finally` em `geocode.py:175`, `reverse.py:138`, `cep.py:63`) | — |
| 7 | `geocode_reverso` agrupa por `tempidgeocodebr` (não `id`) | **Já alinhado** (`reverse.py:44,119`) | — |
| 8 | bug `h3_res` em `busca_por_cep` | **Já alinhado** (`add_h3_columns` itera por resolução) | — |
| 9 | bug LEAD→LAG em empates <300m | **PENDENTE** | `matching.py:342` trocar LEAD por LAG + filtro `logradouro_encontrado IS NOT NULL` |
| 10 | `logradouro_encontrado` sempre preenchido | **PENDENTE** | helper `monta_colunas_encontradas` |
| 11 | limpeza de cache robusta (release fora do padrão) | **Já alinhado** (`cache.py:77-91`) | — |
| 12 | `cache=FALSE` lia do cache persistente em vez do dir temp | **PENDENTE** | propagar `pasta_dados` (retorno de `download_cnefe`) |

## Detalhe das 6 mudanças a implementar

### A. Ponto 10 — `logradouro_encontrado` sempre preenchido (base dos demais)

**Arquivos:** `python-package/geocodebr/matching.py`

Hoje `_complete_columns` (`matching.py:419-435`) retorna `"",""` quando
`resultado_completo=False`, deixando `logradouro_encontrado` NULL. O schema de `output_db`
(`matching.py:18-42`) **já declara** a coluna nos dois casos — só falta populá-la.

**Mudança:**
- Criar helper `monta_colunas_encontradas(y, key_cols, resultado_completo, agregado=False,
  ordem_first="")` em `matching.py`, espelhando `r-package/R/match_helpers.R:48-114`.
- Lógica: se `'logradouro'` em `key_cols`, sempre adiciona `logradouro_encontrado`
  (seleção `{y}.logradouro` ou `FIRST(logradouro_encontrado {ordem_first})` no agregado).
  As demais `*_encontrado` e `cod_setor` só entram se `resultado_completo=True`.
- Reescrever `_complete_columns` e `_complete_weighted_columns` para delegar a esse helper.
  Sutileza no agregado: o `FIRST(...)` referencia `{demais_key_cols}_encontrado` — nome já
  no `temp_db`, não `{y}.{col}`.
- Nome `localidade_encontrada` (não `localidade_encontrado`), como em `match_helpers.R:81`.

> Este é o **ponto de entrada** dos demais: o ponto 2 (reprodutibilidade) e o ponto 9
> (filtro `logradouro_encontrado IS NOT NULL` em empates) dependem desta coluna populada.

### B. Ponto 2 — colunas extras do ponto mais próximo (reprodutível)

**Arquivos:** `matching.py` (`match_weighted_cases`, `match_weighted_cases_probabilistic`,
`_complete_weighted_columns`)

**R** (`r-package/R/match_weighted_cases.R:38-43,91-95`): define
`ordem_first <- "ORDER BY ABS(numero - numero_cnefe), numero_cnefe, lat, lon"` e aplica
`FIRST(... {ordem_first})` **incondicionalmente** a `endereco_encontrado`,
`log_causa_confusao`, `contagem_cnefe` e demais colunas extras. Resultado determinístico
entre execuções; o comentário em `match_weighted_cases.R:42` referencia
`[LEARN:duckdb]` em `MEMORY.md`.

**Python atual** (`matching.py:125-135, 231-243`): usa
`CASE WHEN BOOL_OR(log_causa_confusao) THEN FIRST(... ORDER BY complexo) ELSE FIRST(...) END`
— divergente (não garante reprodutibilidade e dependência do flag).

**Mudança:**
- Substituir o `CASE/BOOL_OR` por `FIRST(... {ordem_first})` simples em todas as colunas
  agregadas (para `endereco_encontrado`, `log_causa_confusao`, `contagem_cnefe`, e
  demais `*_encontrado`/`cod_setor`).
- Simplificar `_complete_weighted_columns` para produzir
  `FIRST(col_encontrado {ordem_first}) AS col_encontrado` para cada coluna extra.
- Idem em `match_weighted_cases_probabilistic` (`matching.py:232-243`).

### C. Ponto 9 — bug LEAD→LAG em empates <300m

**Arquivos:** `matching.py` (`trata_empates_geocode_duckdb`)

**R** (`r-package/R/trata_empates_geocode_duckdb.R:120-131`): usa
`LAG(lat/lon) OVER (PARTITION BY tempidgeocodebr ORDER BY id)`. Com `id` ordenado por
`contagem_cnefe DESC, desvio_metros, endereco_encontrado`, o `LAG` mede a distância contra
a linha **anterior** (maior `contagem_cnefe`). O filtro `dist > 300` descarta a linha de
**menor** `contagem_cnefe`. Comentário em `trata_empates_geocode_duckdb.R:117-119` é
explícito sobre a semântica pretendida.

**Python atual** (`matching.py:341-342`): usa `LEAD` — descarta a de **maior**
`contagem_cnefe` (contrariando a regra documentada). É exatamente o bug descrito no
NEWS.md.

**Mudança:**
- Trocar `LEAD` por `LAG` em `matching.py:341-343`.
- Em `df_empates_perdidos` (`matching.py:362-376`): adicionar
  `AND logradouro_encontrado IS NOT NULL` (R:179) — empate sem logradouro (dc01/dc02/db01/
  dm01) não é "perdido", é salvo pela média ponderada.
- Ordenar o `QUALIFY` por `contagem_cnefe DESC, desvio_metros, endereco_encontrado`
  (R:188-189) — hoje é só `contagem_cnefe DESC`.
- **Depende do ponto 10** (precisa de `logradouro_encontrado` populado para o filtro
  `IS NOT NULL`).

### D. Ponto 12 — `cache=FALSE` lia do cache persistente

**Arquivos:** `tables.py`, `reverse.py`, `cep.py`, `cache.py` (criar helper),
`matching.py` (passar `pasta_dados` adiante), `geocode.py`

**R**: `download_cnefe()` retorna `cache_dir`; `caminho_parquet(nome_tabela, cnefe_dir)`
(`r-package/R/cache.R:175-186`) monta o path; `register_cnefe_table(con, match_type,
pasta_dados)` (`r-package/R/register_cnefe_tables.R:1`) recebe o dir.

**Python atual**: tudo constrói path via `Path(listar_pasta_cache()) / ...`
(`reverse.py:62-65`, `cep.py:37-40`) ou `find_cached_parquet(listar_dados_cache(), ...)`
(`tables.py:18`) — sempre cache persistente, ignorando o retorno de `download_cnefe`. Com
`cache=False` (dir temp), a leitura posterior procura no cache persistente → erro
`IO Error: No files found that match the pattern ...` (exatamente o bug do NEWS.md).

**Mudança:**
- Criar helper `caminho_parquet(nome_tabela, pasta_dados)` em `cache.py`
  (espelhar `r-package/R/cache.R:175-186`).
- `download_cnefe()` já retorna o dir (`download_cnefe.py:46`); OK.
- `register_cnefe_table(con, match_type, pasta_dados=None)` e
  `register_unique_logradouros_table(con, match_type, pasta_dados=None)` (em `tables.py`):
  adicionar param `pasta_dados`. Se `None` → fallback para cache persistente (mantém
  compatibilidade com os testes atuais que não passam esse arg). Senão, usar
  `caminho_parquet(...)`.
- `matching.py`: as 4 funções `match_cases`/`match_cases_probabilistic`/
  `match_weighted_cases`/`match_weighted_cases_probabilistic` recebem `pasta_dados` (param
  novo, default `None`) e repassam a `register_cnefe_table`/`register_unique_logradouros_table`.
- `geocode.py`: capturar `cnefe_dir = download_cnefe(...)` e passar para cada
  `match_fun(..., pasta_dados=cnefe_dir)`.
- `reverse.py` e `cep.py`: usar `caminho_parquet("municipio_logradouro_cep_localidade",
  cnefe_dir)` em vez de `Path(listar_pasta_cache()) / ...`.

### E. Pontos 3 + 5 — pular etapas sem campo + baixar só tabelas necessárias

**Arquivos:** `geocode.py`, `fields.py`, `download_cnefe.py`, `utils.py` (nova
`tabelas_necessarias`)

**R**: `campos_nao_declarados` calculado em `r-package/R/geocode.R:232`; laço em
`r-package/R/geocode.R:428` pula `if (all(key_cols %in% names(input_padrao)) &&
!any(key_cols %in% campos_nao_declarados))`;
`download_cnefe(tabela = tabelas_necessarias(campos_nao_declarados), ...)`.

**Python atual:**
- `fields.fill_missing_fields` (`fields.py:55-67`) cria placeholders
  `_{campo}_tempgeocodebr`, mas não retorna a lista de campos não declarados.
- Laço (`geocode.py:137`) só checa `if all(col in input_padrao_columns for col in
  key_cols)` — nunca pula (as colunas-fantasma sempre existem).
- `download_cnefe.py:14,49-57` (`_select_files`) só aceita `str` única ou `"todas"`.
- `geocode.py:73` sempre chama `download_cnefe("todas", ...)`.

**Mudança:**
- `fields.fill_missing_fields` (ou helper novo `calc_campos_nao_declarados(campos)`)
  retorna também `list[str]` de `campos_nao_declarados`.
- Criar `tabelas_necessarias(campos_nao_declarados)` em `utils.py` (espelhar
  `r-package/R/utils.R:496-504`): filtra `ALL_POSSIBLE_MATCH_TYPES` excluindo os que têm
  key_col em `campos_nao_declarados`, mapeia via `get_reference_table`, dedup.
- `_select_files` em `download_cnefe.py`: aceitar `str | list[str]`. Se `"todas"` → todas;
  senão valida cada item contra `ALL_CNEFE_FILES` e devolve a lista correspondente (permite
  lista vazia — R:46 trata `character(0)` sem derrubar).
- `geocode.py`: chamar
  `download_cnefe(tabelas_necessarias(campos_nao_declarados), ...)`. No laço, adicionar
  `and not any(col in campos_nao_declarados for col in key_cols)`.

### F. Ajuste de teste — ponto 1 (`test_geocode_reverso.py:24`)

**Status:** Concluído pelo usuário. Corrigido o nome do parquet fake de
`municipio_logradouro_numero_cep_localidade.parquet` para
`municipio_logradouro_cep_localidade.parquet` (tabela nova adotada pelo ponto 1
do NEWS.md) e removida a coluna `numero` das colunas selecionadas.

### G. Otimização — pular `calculate_string_dist` redundante em `pa01/pa02/pa03`

**Fora do NEWS.md** — identificada durante a varredura do código R. O R já
aplica esta otimização; o Python não. Por paridade de comportamento (não de
output — o output é idêntico, é puramente performance), vale portar.

**Arquivos:** `python-package/geocodebr/matching.py` (`match_weighted_cases_probabilistic`)

**R** (`r-package/R/match_weighted_cases_probabilistic.R:28-38`): antes de chamar
`register_unique_logradouros_table()` + `calculate_string_dist()`, verifica
`if (!match_type %in% match_types_jaro_redundante)`. A constante
`match_types_jaro_redundante` (`r-package/R/utils.R:345-357`) é
`c("pa01", "pa02", "pa03")` — **não inclui `pa04`** (ver comentário R:354-356:
`pn04` está desativado, então não há etapa anterior que preencha
`similaridade_logradouro` para `pa04` reaproveitar).

**Justificativa** (comentário R:345-353 e
`quality_reports/diagnoses/2026-08-23_geocode-diagnostico-performance.md §6`):
`pa0k` tem exatamente os mesmos `key_cols`, mesma tabela de referência e mesmo
corte de similaridade que `pn0k` (a etapa imediatamente anterior em
`ALL_POSSIBLE_MATCH_TYPES`). `calculate_string_dist()` só calcula Jaro para
linhas com `similaridade_logradouro IS NULL` — ou seja, as linhas que sobram
para `pa0k` são exatamente as que `pn0k` já testou contra o mesmo candidato com
o mesmo corte e não passou. Recalcular em `pa0k` é um **no-op garantido**
(medido: 0 matches em `pa01`/`pa02`/`pa03` em 20.028 endereços).

**Python atual** (`matching.py`, `match_weighted_cases_probabilistic`): chama
`register_unique_logradouros_table()` + `calculate_string_dist()`
incondicionalmente.

**Mudança:**
- Adicionar constante `MATCH_TYPES_JARO_REDUNDANTE = {"pa01", "pa02", "pa03"}`
  em `constants.py` (espelho de `utils.R:357`).
- Em `match_weighted_cases_probabilistic` (`matching.py`), envolver as chamadas
  de `register_unique_logradouros_table()` + `calculate_string_dist()` em
  `if match_type not in MATCH_TYPES_JARO_REDUNDANTE:`.
- **Atenção:** `register_cnefe_table(con, match_type, pasta_dados)` (a criação
  da tabela de referência) **não** entra no guard — continua incondicional, como
  no R (`match_weighted_cases_probabilistic.R:24` está fora do `if`).

**Validação:** paridade R↔Python deve permanecer idêntica (a otimização é um
no-op por construção). Criar teste `test_jaro_redundant_skipped` que verifica
que `calculate_string_dist` não é chamado para `pa01`/`pa02`/`pa03` (via
monkeypatch/spy).

## Testes novos a criar (em `python-package/tests/`)

Pendentes, seguindo o padrão de `test_geocode.py` (parquet fake no `tmp_path` e
`definir_pasta_cache(str(tmp_path), verboso=False)`):

1. `test_geocode_empates_lag_under_300m` — 2 candidatos a <300 m entre si, com
   `contagem_cnefe` diferente; assert que sobrevive o de **maior** contagem (regressão do
   bug LEAD→LAG). **Trava o ponto 9.**
2. `test_geocode_lograd_encontrado_present_sem_completo` — caso de empate com logradouro de
   data (ex. `"RUA 15 DE NOVEMBRO"`); com `resultado_completo=False` e
   `resolver_empates=True`, assert que lat/lon vêm do candidato de maior `contagem_cnefe`
   (não média ponderada). **Trava o ponto 10.**
3. `test_geocode_cache_false_uses_temp_dir` — cache persistente vazio; `cache=False` deve
   funcionar (sem `IO Error: No files found`). **Trava o ponto 12.**
4. `test_match_weighted_reproducible` — rodar `geocode()` duas vezes com mesmo input e
   `n_cores=1`; assert lat/lon idênticos (incl. em casos `da02`/`da04`/`pa02`). **Trava o
   ponto 2.**
5. `test_geocode_pula_etapas_sem_logradouro` — input só `estado/municipio/cep`; assert que
   `tipo_resultado` ∈ {`dc01`,`dc02`,`db01`,`dm01`} (etapas com logradouro puladas). **Trava
   o ponto 3.**
6. `test_download_cnefe_lista_tabelas` — monkeypatch `_download_file` e verificar que
   `download_cnefe(["municipio","municipio_cep"], ...)` baixa só essas 2 tabelas (e não as
   8). **Trava o ponto 5.**
7. `test_jaro_redundant_skipped` — monkeypatch/spy `calculate_string_dist` e verificar que
   não é chamado para `pa01`/`pa02`/`pa03`, mas **é** chamado para `pa04` e `pn01`/`pn02`/
   `pn03`. **Trava a Etapa G.**

## Ordem de execução recomendada

1. **A** (ponto 10): helper `monta_colunas_encontradas` + refatorar
   `_complete_columns`/`_complete_weighted_columns`.
2. **B** (ponto 2): `ordem_first` + `FIRST(...)` incondicional em
   `match_weighted_cases`/`_probabilistic`.
3. **C** (ponto 9): LEAD→LAG + filtro `logradouro_encontrado IS NOT NULL` + QUALIFY com
   ordenação completa.
4. **D** (ponto 12): `caminho_parquet` + propagar `pasta_dados` por `tables.py`/
   `matching.py`/`reverse.py`/`cep.py`.
5. **E** (pontos 3+5): `tabelas_necessarias` + generalizar `download_cnefe` +
   `campos_nao_declarados` no laço.
6. **F** (teste reverso): ajustar nome da tabela no `test_geocode_reverso.py:24`.
7. **Novos testes:** os 6 testes listados acima.
8. **Rodar testes unitários** (rápidos, sem R):
   ```
   cd python-package && python -m pytest tests/test_geocode.py tests/test_busca_por_cep.py tests/test_geocode_reverso.py -v
   ```
9. **Rodar paridade R↔Python** (gate de fidelidade; exige R instalado):
   ```
   cd python-package && python -m pytest tests/test_r_python_parity.py -m r_parity -v
   ```

## Pontos de atenção / riscos

- **Invariante 1 do `CLAUDE.md`** (ordem `da*` depois de `dn*`, evita divisão por zero no
  IDW): **não** tocada por este port — a ordem de `ALL_POSSIBLE_MATCH_TYPES` é a mesma.
- **`tempidgeocodebr`** não é tocado em nenhuma etapa.
- **`data_release`** é `v0.4.1` em ambos os pacotes (R: `r-package/R/cache.R:1`;
  Python: `python-package/geocodebr/constants.py:1`) — sem mudança.
- A otimização de **pular `calculate_string_dist`** para `pa01/pa02/pa03`
  (`match_types_jaro_redundante` em `r-package/R/utils.R:357`, comprovado no-op em
  `quality_reports/diagnoses/2026-08-23_geocode-diagnostico-performance.md §6`) **não está no
  NEWS.md** — incluída no escopo como **Etapa G** a pedido do usuário.
- `_keep_rename_padr_columns` (`geocode.py:209`) já mantém apenas `*_padr`; quando
  `padronizar_enderecos=False`, `_assert_standardized_columns` exige `*_padr`. Não precisa
  mexer.
- Helper `monta_colunas_encontradas` em Python deve preservar o nome
  `localidade_encontrada` (não `localidade_encontrado`), como em
  `r-package/R/match_helpers.R:81`.
- O teste de paridade `test_r_python_parity.py` instala o pacote R em lib temporária a cada
  execução (`R CMD INSTALL -l <tmp>`) — lento (~minutos). O pacote R precisa estar num estado
  consistente (passa `devtools::check`).

## Verificações pós-implementação

- [x] Testes unitários Python passam (`test_geocode`, `test_busca_por_cep`,
      `test_geocode_reverso`).
- [x] Paridade R↔Python: `test_geocode_matches_r_small_sample` passa (compara
      schema, row count, distribuição de `tipo_resultado`, lat/lon com
      `atol=1e-6`, e células não-numéricas). Validado via script ad-hoc
      reutilizando cache em disco (o pytest canonical precisa de download fresh
      de ~1.5GB, bloqueado por infraestrutura de rede).
- [x] Reprodutibilidade: `geocode()` duas vezes com mesmo input gera lat/lon
      idênticos (Etapa B ponto 2).
- [x] `cache=False` funciona sem `IO Error: No files found` (Etapa D).
- [x] Skip de etapas: input só `estado`/`municipio` → só `dm01` (Etapa E).
- [ ] Etapa G: paridade R↔Python permanece idêntica após pular Jaro redundante.
- [ ] Criar os 6 testes de regressão listados abaixo (+. teste Jaro da Etapa G).

## Referências de código (linha-de-arquivo)

| Assunto | R | Python |
|---|---|---|
| `monta_colunas_encontradas` (helper novo) | `r-package/R/match_helpers.R:48-114` | `python-package/geocodebr/matching.py` (a criar) |
| `ordem_first` + `FIRST(...)` incondicional | `r-package/R/match_weighted_cases.R:38-95` | `python-package/geocodebr/matching.py:84-140` |
| LEAD→LAG + filtro `logradouro_encontrado IS NOT NULL` | `r-package/R/trata_empates_geocode_duckdb.R:120-189` | `python-package/geocodebr/matching.py:341-376` |
| `caminho_parquet` helper | `r-package/R/cache.R:175-186` | `python-package/geocodebr/cache.py` (a criar) |
| `register_cnefe_table(..., pasta_dados)` | `r-package/R/register_cnefe_tables.R:1,12` | `python-package/geocodebr/tables.py:9` |
| `tabelas_necessarias` | `r-package/R/utils.R:496-504` | `python-package/geocodebr/utils.py` (a criar) |
| Laço pula `campos_nao_declarados` | `r-package/R/geocode.R:225-232,428` | `python-package/geocodebr/geocode.py:135-147` |
| `download_cnefe(tabela=<lista>)` | `r-package/R/download_cnefe.R:46-70` | `python-package/geocodebr/download_cnefe.py:14,49-57` |
| `match_types_jaro_redundante` + guard em `pa0k` | `r-package/R/utils.R:345-357`, `r-package/R/match_weighted_cases_probabilistic.R:28-38` | `python-package/geocodebr/matching.py` (`match_weighted_cases_probabilistic`) |

---

*Plano gerado a partir da varredura do `r-package/NEWS.md` (dev version) contra o código R
atualizado (`r-package/R/*.R`) e o port Python em `python-package/geocodebr/`. Adota as
convenções de `CLAUDE.md` (princípio `R/` autoritativo; paridade preservada; portões de
qualidade `R CMD check` no R e testes + paridade no Python).*
