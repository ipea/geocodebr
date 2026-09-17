# Plano — otimização de merge_results_to_input() (etapa final do geocode)

**Status:** **REVERTIDO (27/08)** — nenhuma otimização de performance sobreviveu. Proposta A rejeitada
por restrição de arquitetura (memória); variante SQL implementada e depois **refutada em 43M**.
Mantida apenas a guarda de nomes reservados em `check_clean_colnames()` (correção de bug, não
performance). `merge_results_to_input()` e `add_precision_col()` voltaram ao HEAD.

**Achado final que redireciona qualquer trabalho futuro nesta etapa:** o teste isolado das variantes de
SQL (4 formas de produzir `precisao`/`similaridade`, 43M sintéticos) mostrou que **toda a parte SQL do
merge — join + ORDER BY + expressões, escrevendo o resultado dentro do DuckDB — custa ~22 s**, contra
~84 s do merge completo na corrida real. Ou seja, **~3/4 do custo é a materialização das 43M linhas
para dentro do R (`dbGetQuery`)**, não o join nem as expressões. Mexer no `CASE`/`COALESCE` é otimizar
o quarto errado do problema — o que explica por que todas as variantes deram diferenças pequenas e
instáveis. O teste isolado também se mostrou inútil para ordenar variantes (a mesma variante
`AS MATERIALIZED` deu 80,18 s e 21,75 s em duas repetições idênticas).

**Frente futura, se a etapa voltar a incomodar:** atacar a materialização — `dbGetQueryArrow()` no
fetch, ou uma saída opcional direto para parquet sem passar pelo R. Desenho próprio, medição em 43M.

**Decisão do mantenedor (27/08):** o join **tem que rodar dentro do DuckDB**. O banco é em disco
justamente para suportar bases maiores que a RAM (o usuário roda 43M de endereços); um join em
`data.table` no R fica mais rápido em benchmark pequeno mas desloca o pico de memória para o R e
quebra a garantia principal do desenho. O adversário havia levantado exatamente isso (achado 6) e a
proposta A tratou como não-bloqueante — era bloqueante. Registrado como restrição permanente.

**Implementado (variante SQL):** JOIN e ORDER BY seguem no DuckDB; o que foi aproveitado da análise é
o que cabe dentro dessa restrição:
- `precisao` derivada no `SELECT` do merge → elimina o `ALTER + UPDATE` de tabela inteira do
  `add_precision_col()` (função removida, era seu único chamador);
- `COALESCE(similaridade_logradouro, 1)` no `SELECT` → elimina o segundo `UPDATE` de tabela inteira
  (só ocorria em `resultado_completo = TRUE`);
- `tempidgeocodebr` fora do `SELECT` (sugestão do usuário) — segue válido no JOIN e no ORDER BY, mas
  não é materializado para ser descartado depois;
- guarda de **nomes reservados** em `check_clean_colnames()` (achado 3 do adversário).
**Motivação:** medido pelo usuário em 43M de endereços: a etapa de merge é **12% do tempo total** do
`geocode()`. No benchmark oficial (1M, `n_cores = 1`): merge = 2,48 s (`resultado_completo = FALSE`,
2,3% de 107 s) / 4,33 s (`TRUE`, 3,9%); `add_precision_col()` = 0,13-0,17 s; escrita do `input_db` =
0,49 s. A participação cresce com a escala porque sort O(n log n) e materialização R de dezenas de
milhões de linhas degradam mais que o resto do pipeline — o ganho no 1M é piso, não teto.
**Arquivos alvo:** `r-package/R/utils.R` (`merge_results_to_input()`), `r-package/R/geocode.R`
(chamada + escrita do `input_db`).
**Critério de aceite:** `identical()` no 1M (`n_cores = 1`) nas 4 combinações
`resolver_empates × resultado_completo` — com a ressalva já documentada (item 5) de que no ramo
`resolver_empates = FALSE` a ordem intra-id das linhas duplicadas não é contratual (comparação por
ordenação canônica se a posicional falhar).

## O custo atual (por componente)

1. `duckdb::dbWriteTable(con, "input_db", enderecos)` — serializa 1M × (colunas originais + id) R→DuckDB
   só para o join devolvê-las intactas.
2. (`resultado_completo = TRUE`) `UPDATE {y} SET similaridade_logradouro = COALESCE(..., 1)` — reescreve
   a tabela de resultados inteira para normalizar NULLs.
3. `LEFT JOIN` + `ORDER BY tempidgeocodebr` — sort de 1M+ linhas no DuckDB.
4. `dbGetQuery` — materializa 1M × (originais + resultado + `tempidgeocodebr`) DuckDB→R; o id é
   descartado logo depois no R (`output_df[, tempidgeocodebr := NULL]`).

## Proposta A (principal): join final em R, sem ida e volta das colunas originais

1. **Eliminar a escrita do `input_db`** (`geocode.R:473-479`): as colunas originais nunca mudam e já
   estão no R.
2. **Buscar do banco só o resultado**:
   `SELECT tempidgeocodebr, lat, lon, precisao, tipo_resultado, desvio_metros, endereco_encontrado
   [, colunas extras se resultado_completo] FROM {y}` — sem JOIN, sem ORDER BY. Com
   `resultado_completo = TRUE`, o COALESCE entra **no próprio SELECT**
   (`COALESCE(similaridade_logradouro, 1) AS similaridade_logradouro`), eliminando o UPDATE (2).
3. **Join no R com data.table**, por `tempidgeocodebr` (chave inteira): left join ancorado em
   `enderecos` (todas as linhas do input preservadas; `NA` onde não geocodificado; expansão 1:N no ramo
   `resolver_empates = FALSE` via `allow.cartesian`). A ordem original do input vem de graça (ancorada
   no lado `enderecos`); `setcolorder` põe as colunas originais primeiro; o id é dropado por referência
   no final (custo ~zero — atende a observação do usuário: o id só existe em memória como chave do
   join, nunca é materializado à toa numa passada extra).
4. `add_precision_col()` fica como está nesta rodada (0,13-0,17 s no 1M; ver "Extensão opcional").

Ganho esperado no 1M: elimina (1) 0,49 s + (2) ~parte dos 1,85 s do modo completo + (3) o sort + reduz
(4) ao mínimo (só colunas de resultado). Estimativa honesta: merge 2,48 → ~1,0-1,5 s no modo simples;
4,33 → ~1,5-2,0 s no completo. Em 43M, proporcionalmente mais (é a materialização que explode lá).

## Proposta B (fallback conservador, sem reestruturar): três micro-fixes no SQL atual

- COALESCE no SELECT em vez do UPDATE (2);
- não selecionar `input_db.tempidgeocodebr` no SELECT (sugestão do usuário — o id hoje é materializado
  e descartado no R; a chave do join não precisa aparecer no resultado);
- manter escrita do input, JOIN e ORDER BY como estão.

Captura talvez 1/3 do ganho da A, com diff mínimo e zero risco estrutural.

## Proposta C (experimento barato, combinável com A ou B): fetch via Arrow

`DBI::dbGetQueryArrow()` (ou `duckdb::duckdb_fetch_arrow`) + `as.data.table()` no lugar do
`dbGetQuery` — A/B de meia dúzia de linhas. **Investigar antes**: o `dbWriteTableArrow` do `input_db`
está *comentado* em `geocode.R` (linhas ~480-482), sinal de experimento anterior descartado — entender
o motivo (performance? bug? tipos?) antes de apostar no caminho Arrow do lado do fetch.

## Riscos conhecidos

1. **Colisão de nomes**: input do usuário pode ter colunas chamadas `lat`/`lon`/`precisao` etc. O SQL
   atual produziria nomes duplicados no resultado (comportamento atual obscuro); o join data.table
   sufixa (`i.lat`). Caracterizar o comportamento atual e decidir conscientemente (possivelmente
   documentar/errar cedo em vez de herdar o obscuro).
2. **Ordem intra-id no ramo `resolver_empates = FALSE`** (duplicatas 1:N): pode mudar com o join em R —
   precedente do item 5 (não contratual; comparação canônica).
3. **Tipos na fronteira DuckDB→R**: com menos colunas trafegando, os tipos das colunas de resultado
   devem permanecer idênticos (double/int/character/logical) — `identical()` pega qualquer desvio.
4. **`merge_results_to_input()` tem outros chamadores?** Verificar (grep) — se `busca_por_cep()` ou
   `geocode_reverso()` a usarem, o escopo muda.
5. **Memória em 43M**: o join data.table aloca o resultado no R de uma vez — mas o `dbGetQuery` atual
   também; a A troca uma alocação maior (originais + resultado via DB) por uma equivalente montada no
   R. Não deve piorar; atenção do adversário bem-vinda.

## Extensão opcional (avaliar no acordo, não implementar por default)

`add_precision_col()` também é um `ALTER + UPDATE` de tabela inteira; o `CASE` dela poderia entrar no
mesmo SELECT do fetch. 0,15 s no 1M — mas em 43M um UPDATE de tabela inteira pode escalar mal como o
COALESCE. Decidir com o adversário se entra agora ou fica para depois com medição própria.

## Resultado em ESCALA REAL (43M, `df_full_data.parquet`) — REFUTA a otimização

O mantenedor reportou degradação em 43M. Medido com worktree limpo no HEAD vs working tree, corridas
sequenciais, `n_cores` default, mesma máquina:

**`resultado_completo = FALSE`** (2 corridas por braço — o espalhamento DENTRO de cada braço é maior
que a diferença ENTRE braços, logo **não há diferença detectável**):

| braço | merge+precision (corrida 1) | (corrida 2) | média |
|---|---|---|---|
| HEAD | 85,72 s | 83,31 s | 84,5 s |
| com alterações | 81,65 s | 83,94 s | 82,8 s |

**`resultado_completo = TRUE`** (1 corrida por braço) — **REGRESSÃO**:

| braço | merge+precision | pico de memória |
|---|---|---|
| HEAD | 115,42 s | 16.662 Mb |
| com alterações | **120,60 s (+4,5%)** | **18.344 Mb (+1,7 GB)** |

Ou seja: mover o `CASE` da `precisao` e o `COALESCE` da similaridade para o `SELECT` do join — que no
1M media −35% no modo completo — em 43M fica **mais lento e consome 1,7 GB a mais**. Mecanismo
provável: no HEAD as duas expressões rodam uma vez sobre a tabela compacta de resultados (`UPDATE`);
na versão nova são avaliadas na projeção do join, sobre o resultado já expandido, o que também parece
mudar a estratégia de materialização do DuckDB (daí o pico de memória maior).

Corretude não é o problema: nas 6 corridas, 43.882.020 linhas, checksums de `lat`/`lon` idênticos e
distribuição das 25 categorias de `tipo_resultado` igual.

**Conclusão: a otimização de performance deve ser revertida.** Sobrevive apenas o que não é
performance: a guarda de nomes reservados em `check_clean_colnames()`. O `tempidgeocodebr` fora do
`SELECT` (sugestão do mantenedor) é plausível mas não foi medido isoladamente — se mantido, precisa de
A/B próprio em 43M.

**Lição (mais uma vez neste repo):** benchmark de 1M não é proxy confiável para 43M em etapas cujo
custo depende de materialização e memória. O sinal do 1M foi de −35%; a realidade em escala foi +4,5%.

## Resultado (27/08, variante SQL) — medição em 1M, que se mostrou ENGANOSA

Benchmark oficial (1M, `n_cores = 1`). A nova função **absorveu** o trabalho do `add_precision_col()`,
que no baseline era medido à parte (0,13-0,17 s) — a coluna "base justa" soma os dois:

| combo | merge base | base justa | merge novo | variação |
|---|---|---|---|---|
| `TRUE` / completo=F | 2,47 s | ~2,60 s | 2,69 s | empate (dentro do ruído ±10%) |
| `TRUE` / completo=T | 3,82 s | ~3,99 s | **2,61 s** | **−35%** |
| `FALSE` / completo=F | 2,11 s | ~2,24 s | 2,03 s | −9% |
| `FALSE` / completo=T | 3,31 s | ~3,48 s | 3,14 s | −10% |

Corretude: `identical()` posicional em 3 combos; em `FALSE`/completo=F a única diferença é a coluna
`empate` a mais (esperada — o baseline foi capturado sem `incluir_empate`) e a ordem intra-id das
duplicatas, com `identical()` TRUE após ordenação canônica. Smoke no `small_sample`: 9/9 (4 combos,
`sf`, `h3`, tipos preservados, 0-match, guarda de nomes reservados).

**Leitura honesta:** o ganho concentra-se em `resultado_completo = TRUE` (eliminação do UPDATE de
tabela inteira do COALESCE); no modo padrão é empate dentro do ruído. **Os 12% medidos em 43M não
foram resolvidos** — o que atacaria isso é justamente a materialização, barrada pela restrição de
memória. Os dois `UPDATE`s de tabela inteira eliminados tendem a pesar mais em 43M do que os 0,15 s
medidos em 1M, mas isso só o teste do mantenedor em escala real confirma.

**Ideias remanescentes dentro da restrição (não implementadas, sem medição):** escrever o `input_db`
via `dbWriteTableArrow` (0,49 s no 1M; havia código comentado nesse sentido no `geocode.R`, sem motivo
registrado para o descarte); e avaliar se o `ORDER BY` do merge pode ser evitado sem perder a ordem do
input.

## Verificação

1. `identical()` no 1M, `n_cores = 1`, nas 4 combinações `resolver_empates × resultado_completo`
   (ramo FALSE: canônica se a posicional falhar, como no item 5).
2. Smoke no `small_sample`: `resultado_sf = TRUE` e `h3_res` (caminhos pós-merge intactos).
3. Teste dirigido de colisão de nomes (input com coluna `lat`) — caracterizar antes/depois.
4. Benchmark: tempos do merge (e total) nos dois modos, antes/depois.
