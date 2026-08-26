# Nova rodada de revisão crítica de `geocode()` — 2026-08-24

Revisão de acompanhamento sobre [`2026-08-22_geocode-pipeline-achados.md`](2026-08-22_geocode-pipeline-achados.md),
depois das correções feitas nesta sessão (item 1 daquele relatório) e do commit `282c302`
("reduz redundancia no calculo de jaro para etapas pa0x"). Verifica o status de cada item antigo e
levanta achados novos em `R/geocode.R` e dependências (`match_*.R`, `trata_empates_geocode_duckdb.R`,
`utils.R`, `create_geocodebr_db.R`).

Todos os itens marcados **Verificado** foram reproduzidos empiricamente (DuckDB real, dados do CNEFE via
cache local), não inferidos por leitura.

---

## 1. CRÍTICO (novo) — `FIRST()` sem `ORDER BY` torna `da0x`/`pa0x` não-determinísticos entre execuções

**Verificado — reprodução ao vivo, mesmos parâmetros, mesmo input.**

`match_weighted_cases.R` (tipos `da01`-`da04`) e `match_weighted_cases_probabilistic.R` (`pa01`-`pa03`)
agregam múltiplos candidatos do CNEFE por `GROUP BY tempidgeocodebr, endereco_encontrado` (a interpolação
de número junta vários `numero_cnefe` da mesma rua). Dentro desse agrupamento, várias colunas são
escolhidas com `FIRST(...)` **sem `ORDER BY` interno**:

```sql
-- match_weighted_cases.R:126-135 (e equivalente em match_weighted_cases_probabilistic.R)
SELECT tempidgeocodebr,
  SUM((1/ABS(numero - numero_cnefe) * lat)) / SUM(1/ABS(numero - numero_cnefe)) AS lat,
  SUM((1/ABS(numero - numero_cnefe) * lon)) / SUM(1/ABS(numero - numero_cnefe)) AS lon,
  FIRST(endereco_encontrado) AS endereco_encontrado,
  ...
  FIRST(log_causa_confusao) AS log_causa_confusao,
  FIRST(contagem_cnefe) AS contagem_cnefe {additional_cols_second}  -- inclui FIRST(cod_setor), FIRST(*_encontrado)
FROM temp_db
GROUP BY tempidgeocodebr, endereco_encontrado;
```

`lat`/`lon` são agregados corretamente (`SUM`/`AVG`, associativos e estáveis). Mas `FIRST()` sem `ORDER BY`
é **não-determinístico por especificação** no DuckDB — o valor devolvido depende da ordem física de scan
dentro do grupo, que muda com o plano de execução paralelo.

**Por que isso importa mais do que parece:** `contagem_cnefe` escolhido por esse `FIRST()` alimenta
diretamente o critério de desempate em `trata_empates_geocode_duckdb.R`
(`ORDER BY contagem_cnefe DESC` decide quem "ganha" no ramo de empates perdidos, e a mesma coluna ordena o
`id` que define os pares comparados no filtro de 300 m e no cálculo de `max_dist`). Um `FIRST()` arbitrário
nessa coluna propaga a arbitrariedade para **qual candidato de rua o usuário recebe como resultado final**
— não é só metadado cosmético.

**Reprodução (endereço real, `large_sample.parquet`, id 11098, `ESTRADA JOAO EVANGELISTA DE CARVALHO`,
3 candidatos de rua homônima em bairros diferentes, `tipo_resultado = da04`):**

```r
# mesmos parâmetros, mesmo input, 4 chamadas seguidas — n_cores default (paralelo)
for (i in 1:4) geocode(..., resolver_empates = TRUE, resultado_completo = FALSE)
#> run 1: lat=-22.82104  lon=-43.41880
#> run 2: lat=-22.82104  lon=-43.41880
#> run 3: lat=-22.80602  lon=-43.42956   <-- mesma chamada, resultado diferente
#> run 4: lat=-22.82104  lon=-43.41880
```

Diferença de **~1,5 km** entre os dois valores possíveis — não é ruído de ponto flutuante, é a função
escolhendo um candidato de rua diferente. Com `n_cores = 1` (execução single-thread), as mesmas 4 chamadas
foram estáveis (`-22.82104` nas 4). **`n_cores` default não é 1** (`min(availableCores(), freeConnections())`
em `create_geocodebr_db()`), então o bug está ativo por padrão em qualquer máquina multi-core.

Isso também **substitui** a causa-raiz do item 2 do relatório de 2026-08-22 ("`resultado_completo` altera
as coordenadas retornadas"): aquele item atribuía o problema a `logradouro_encontrado` ficar `NULL` quando
`resultado_completo = FALSE` — isso **já foi corrigido** (a coluna agora é sempre populada, ver comentário
em `match_cases.R:34-39`). Testado no dataset de 20.028 linhas, a divergência `resultado_completo = TRUE`
vs `FALSE` caiu de "afeta o desempate em geral" para **2 linhas em 20.028**, ambas `da0x` — exatamente os
tipos afetados por este item 1, e a diferença observada entre T/F é apenas mais uma manifestação do mesmo
não-determinismo (plano de query muda com o conjunto de colunas selecionadas), não uma causa própria.

**Consequência adicional:** `cod_setor` (setor censitário) também é escolhido via `FIRST()` no mesmo grupo,
e pode não corresponder a nenhum setor do ponto `(lat, lon)` retornado (que é uma média ponderada entre
setores possivelmente diferentes).

**Correção possível:** adicionar `ORDER BY` explícito e determinístico a cada `FIRST()`. O candidato mais
defensável semanticamente é o de maior peso na interpolação: `FIRST(contagem_cnefe ORDER BY ABS(numero -
numero_cnefe) ASC, cod_setor)` (ou equivalente para as demais colunas do mesmo grupo) — assim o
"representante" do grupo é sempre o número CNEFE mais próximo do número de input, com um desempate final
estável (`cod_setor`) para o caso de distância igual.

---

## 2. Status dos itens do relatório de 2026-08-22

| # | Item | Status atual |
|---|---|---|
| 1 | `resultado_completo = TRUE` + zero empates → Binder Error | **CORRIGIDO** nesta sessão (`trata_empates_geocode_duckdb.R`: `ALTER TABLE ... ADD COLUMN IF NOT EXISTS empate BOOLEAN DEFAULT FALSE` no ramo de zero-empates; removida a pré-declaração de `empate` no schema, que colidia com a CTE `filtered`). Ver `[LEARN:duckdb]` em `MEMORY.md`. |
| 2 | `resultado_completo` altera as coordenadas retornadas | **Causa original corrigida** (`logradouro_encontrado` agora sempre populado), mas **substituída** pelo item 1 deste relatório — a divergência residual (2/20028 linhas no teste) vem do `FIRST()` não-determinístico, não mais do `NULL`-propagation original. |
| 3 | `max_dist` mede saltos consecutivos (`LEAD`/`LAG`), não a maior distância entre pares | **Ainda aberto.** Código inalterado desde 2026-08-22 (a troca `LEAD`→`LAG` do item 4a corrigiu *qual* linha sobrevive, não a limitação de só comparar pares consecutivos). Com 3+ candidatos colineares espaçados, `max_dist` pode subestimar a dispersão real. |
| 4a | Filtro de 300 m preservava o candidato de *menor* `contagem_cnefe` | Corrigido (2026-08-22). |
| 4b | Limiar de 300 m não documentado | Corrigido (2026-08-23). |
| 5 | Documentação promete `pn04`, `pa04`, `pl04`, que o pacote nunca produz | **Ainda aberto.** Confirmado em `man/roxygen/templates/precision_section.R:63,73,83` vs. `all_possible_match_types` em `R/utils.R` (os três seguem comentados, `# too costly`). |
| 6 | `create_geocodebr_db(db_path = 'memory')` cria um arquivo chamado `memory` | **Não reproduz mais.** `R/create_geocodebr_db.R` foi reescrito (commit `0ef697c`) — o ramo `db_path == 'tempdir'` é o único tratamento especial hoje; não há mais dupla conexão sobrescrevendo `con`. Item obsoleto, pode ser removido do backlog. |
| 7 | `float16` para `lat`/`lon` não perde precisão | Informativo, não é bug (mantido). |

---

## 3. Verificação da otimização do commit `282c302` (skip de Jaro em `pa01`-`pa03`)

**Verificado — não é regressão.** `match_types_jaro_redundante <- c("pa01", "pa02", "pa03")` pula
`calculate_string_dist()` nessas três etapas, reaproveitando `temp_lograd_determ`/`similaridade_logradouro`
já calculados por `pn01`-`pn03` (etapa imediatamente anterior em `all_possible_match_types`). A suposição
de que isso é sempre um no-op se sustenta porque:

- `get_key_cols()`, `get_reference_table()` e `get_prob_match_cutoff()` retornam **exatamente os mesmos
  valores** para `pa0k` e `pn0k` (cutoff 0.85 para o par 01, 0.90 para 02/03).
- `calculate_string_dist()` só recalcula linhas com `similaridade_logradouro IS NULL` — uma linha que
  chega em `pa0k` só está lá porque `pn0k` (mesma tabela, mesmo cutoff) não conseguiu um match
  determinístico exato (número incluído); se `pn0k` não achou candidato acima do cutoff, `temp_lograd_determ`
  segue `NULL` e `pa0k` também não encontra nada — mesmo resultado, sem custo de recálculo.
- **Corretamente excluído**: `pa04` não entra na lista, porque `pn04` está desativado (item 5 acima) — não
  há etapa anterior que preencha `similaridade_logradouro` para `pa04` reaproveitar.

Nenhuma inconsistência encontrada.

---

## Resumo

| # | Severidade | Item |
|---|---|---|
| 1 | **Crítico (novo)** | `FIRST()` sem `ORDER BY` em `da0x`/`pa0x` → resultado não-determinístico entre execuções idênticas (confirmado: 3 valores distintos em 4 chamadas repetidas, mesmos parâmetros, `n_cores` default) |
| 2 | Médio | `max_dist` usa saltos consecutivos (`LEAD`/`LAG`), não dispersão real entre todos os pares — ainda aberto |
| 3 | Médio | `pn04`/`pa04`/`pl04` documentados mas desativados — ainda aberto |
| — | — | Itens 1, 4a, 4b, 6 do relatório de 2026-08-22: corrigidos ou obsoletos |
