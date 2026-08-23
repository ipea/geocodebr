# Análise do geocodebr — desempenho e manutenção — 2026-08-23

**Escopo:** os 19 arquivos de `R/` na íntegra — as quatro funções exportadas principais (`geocode()`, `geocode_reverso()`, `busca_por_cep()`, `download_cnefe()`), as funções de cache e as internas de apoio (`match_*`, `register_*`, `string_dist`, `trata_empates_*`, `create_geocodebr_db`, `utils`).

**Base de código:** `a4b8036`. **Nada foi alterado** fora de uma worktree descartável — este documento é diagnóstico e proposta.

**Método:** leitura integral, seguida de medição. Tudo que é numérico aqui foi medido nesta máquina contra o cache real do CNEFE (release `v0.4.1`, 1,46 GB, 8 parquets), com `inst/extdata/large_sample.parquet` (20.028 endereços, 215 municípios, 3 UFs), chamando `geocode_core()` direto — `geocode()` roda em `callr::r(package = TRUE)` e carregaria a versão *instalada*, não a do branch. Os protótipos foram medidos numa `git worktree` em `a4b8036`, com 2 a 4 repetições e ordem invertida entre condições.

Complementa (não repete) `2026-08-23_geocode-diagnostico-performance.md`, que perfilou o caminho feliz de `geocode()`. Os itens de lá que continuam abertos são referenciados na §3.

------------------------------------------------------------------------

## 1. Achado principal: o laço não pula etapas cujo campo-chave está vazio

`geocode()` completa os campos não declarados pelo usuário com **colunas-fantasma** (`<campo>tempgeocodebr`, todas `NA_character_`), para manter o SQL do matching uniforme. Depois da padronização, essas colunas chegam ao laço com o nome definitivo (`logradouro`, `numero`, ...). O laço tem um guarda para pular etapas impossíveis:

``` r
# R/geocode.R:415-417
# somente busca essa categoria match_type se todas colunas estiverem na base
if (all(key_cols %in% names(input_padrao))) {
```

**Esse guarda nunca dispara.** Ele testa a *presença da coluna*, e a coluna-fantasma sempre está presente. O resultado é que as 25 etapas rodam sempre, e cada uma chama `register_cnefe_table()` **antes** de montar a query — materializando a tabela de referência inteira para um join que o filtro `IS NOT NULL` vai zerar.

Medido com o mesmo input, variando apenas quais campos são declarados em `definir_campos()`:

| campos declarados | tabelas materializadas | chamadas a `register_cnefe_table` | chamadas a `calculate_string_dist` |
|----|----|----|----|
| todos os 6 | 8 de 8 | 25 | 9 |
| `estado` + `municipio` + `cep` | **8 de 8** | **25** | **9** |

No cenário só-CEP, as 8 tabelas incluem as quatro de logradouro (as duas maiores somam 1,19 GB), e as 9 chamadas ao Jaro comparam contra uma coluna que é `NA` de ponta a ponta. **Nenhuma dessas linhas pode produzir um único match.** Só `municipio_cep` e `municipio` têm utilidade.

### Proposta

Calcular uma vez quais campos não têm nenhum valor utilizável e usar isso no guarda:

``` r
# antes do laço
campos_possiveis <- c("estado","municipio","logradouro","numero","cep","localidade")
campos_presentes <- intersect(campos_possiveis, names(input_padrao))
campos_vazios <- campos_presentes[vapply(
  campos_presentes, function(cc) all(is.na(input_padrao[[cc]])), logical(1)
)]

# no laço
if (all(key_cols %in% names(input_padrao)) && !any(key_cols %in% campos_vazios)) {
```

Testar o dado em vez da presença da coluna cobre também o caso de o usuário declarar uma coluna que por acaso está inteiramente vazia. O custo é uma passada por 6 vetores, uma vez.

### Ganho medido (worktree, mediana de repetições, ordem invertida)

| cenário | `a4b8036` | protótipo | ganho |
|----|----|----|----|
| todos os campos | 9,23 s | 9,06 s | **sem diferença** (dentro do ruído; é no-op por construção) |
| `logradouro` + `cep` + `localidade`, sem `numero` | 9,04 s | **2,72 s** | **3,3×** |
| `estado` + `municipio` + `cep` | 6,36 s | **0,71 s** | **9,0×** |

Nos três cenários o número de endereços geocodificados é idêntico (20.028) — a mudança não altera resultado, só evita trabalho que não podia gerar match.

> **Ressalva.** As quatro repetições do cenário completo (7,3 s a 10,6 s) mostram variância de máquina maior que qualquer efeito ali; a afirmação é de ausência de regressão, não de ganho. Nos outros dois cenários a diferença é de ordem de grandeza e não depende da variância.

### Corolário: o download também não precisa ser de tudo

`geocode()` chama `download_cnefe(tabela = 'todas')` — as 8 tabelas, 1,46 GB, sempre. Com a informação de quais campos existem, dá para baixar só o que as etapas viáveis vão usar:

| campos declarados              | tabelas necessárias | download         |
|--------------------------------|---------------------|------------------|
| todos os 6                     | 8                   | 1.492 MB         |
| sem `numero`                   | 6                   | 299 MB (20%)     |
| `estado` + `municipio` + `cep` | 2                   | **20 MB (1,3%)** |

Isso muda a experiência de primeiro uso de quem só tem CEP — de um download de 1,46 GB para um de 20 MB. Custo: `download_cnefe()` precisa aceitar um vetor de tabelas (hoje aceita `"todas"` ou uma só), e o cache passa a poder estar parcialmente populado, o que o `setdiff` de `download_cnefe()` já trata naturalmente.

------------------------------------------------------------------------

## 2. Robustez: dois defeitos na limpeza de cache

`apaga_data_release_antigo()` (`R/cache.R:169-213`) roda no início de todo `download_cnefe(cache = TRUE)`. Testado de forma isolada, com `R_USER_CACHE_DIR`/`R_USER_CONFIG_DIR` apontando para um diretório temporário (o cache real não foi tocado):

| caso | conteúdo antes | resultado |
|----|----|----|
| release antigo + atual convivendo | `v0.4.0`, `v0.4.1` | **a pasta de cache inteira é apagada**, o `v0.4.1` válido junto |
| pasta com nome sem dígitos | `dev`, `v0.4.1` | **erro:** `missing value where TRUE/FALSE needed` |
| só o release atual | `v0.4.1` | ok, preservado |

**Caso 1** — o ramo final chama `deletar_pasta_cache()`, que faz `unlink(cache_dir, recursive = TRUE)` na pasta toda. Quem tinha o release corrente já baixado paga 1,46 GB de download de novo, sem necessidade. A correção é apagar só os diretórios cujo release difere do corrente:

``` r
antigos <- local_release_path[basename(local_release_path) !=
                              glue::glue("geocodebr_data_release_{data_release}")]
unlink(antigos, recursive = TRUE)
```

**Caso 2** — a causa é a lógica de três linhas:

``` r
check1 <- is.na(local_release)
check2 <- local_release == pkg_release
if (all(check1, check2)) { ... }
```

Se `local_release` é `NA`, `check2` é `NA` e `all(TRUE, NA)` é `NA` — `if (NA)` é erro. Note que o ramo é inalcançável mesmo quando funciona: `check1` e `check2` não podem ser ambos `TRUE`. O `if (any(local_release != pkg_release))` logo abaixo tem o mesmo problema com `NA`. Trocar por `local_release <- suppressWarnings(as.numeric(...)); antigos <- is.na(local_release) | local_release != pkg_release` resolve os dois de uma vez.

Menor, no mesmo arquivo: `list.dirs(cache_dir, recursive = T)` — `T` é uma variável reatribuível, não uma constante (idem `overwrite = T` em `R/geocode_reverso.R:190,210`).

------------------------------------------------------------------------

## 3. Desempenho: o que já estava medido e segue aberto

Do relatório anterior, sem alteração no código desde então:

| \# | item | ganho medido | onde |
|----|----|----|----|
| a | `CREATE TEMP VIEW` em vez de `TEMP TABLE` em `register_cnefe_table()` | 1,5–7× na fase que é \~50% do tempo | §3 do relatório anterior |
| b | `pa01`/`pa02`/`pa03` chamam `calculate_string_dist()` sem poder resolver nada | −30% do tempo de Jaro | §6 |
| c | `callr` custa 1,73 s fixos por chamada de `geocode()` (21%) | até 1,73 s | §5 |

O item (b) foi reconfirmado nesta rodada: no cenário completo, `pa01`+`pa02`+`pa03` custaram 0,55 s dos 1,85 s de Jaro, e a razão de serem no-op continua valendo (mesma tabela de logradouros e mesmo corte que a etapa `pn*` anterior, e `calculate_string_dist()` só olha linhas com similaridade `NULL`).

Os itens (a) e (1) desta análise **se compõem bem**: (1) reduz *quantas* tabelas são materializadas, (a) reduz o custo de materializar *cada* uma. Nenhum dos dois torna o outro desnecessário.

**Um item novo, pequeno:** `register_unique_logradouros_table()` filtra por `estado` e `municipio` quando lê da tabela raiz já materializada, mas **só por `municipio`** quando lê do parquet (`R/register_cnefe_tables.R:216-225`). Materializa mais linhas do que precisa; não afeta resultado, porque o join em `calculate_string_dist()` inclui `estado`.

------------------------------------------------------------------------

## 4. Não-determinismo entre execuções

Rodando `geocode_core()` duas vezes sobre o mesmo input, com os mesmos argumentos: **1 coordenada e 10 valores de `endereco_encontrado` diferentes** em 20.028 linhas.

A causa está em `trata_empates_geocode_duckdb.R:174-175` e `206-207`:

``` sql
QUALIFY ROW_NUMBER() OVER (PARTITION BY tempidgeocodebr ORDER BY contagem_cnefe DESC) = 1
```

Sem critério de desempate, dois candidatos com a mesma `contagem_cnefe` são escolhidos pela ordem física das linhas, que varia com o plano de execução. A CTE `base` do mesmo arquivo já faz certo — `ORDER BY contagem_cnefe DESC, desvio_metros, endereco_encontrado`. Replicar essa ordenação nos dois `QUALIFY` torna o resultado reproduzível, sem mudar a regra.

Isso importa além da estética: hoje um teste de regressão sobre coordenadas de empates é intrinsecamente instável, e foi exatamente o ruído que precisei descontar para validar a correção de `logradouro_encontrado`.

------------------------------------------------------------------------

## 5. Manutenção

### 5.1 Os quatro `match_*` são a mesma função escrita quatro vezes

`match_cases`, `match_weighted_cases`, `match_cases_probabilistic` e `match_weighted_cases_probabilistic` têm \~80% de código idêntico: o bloco que monta `colunas_encontradas`/`additional_cols` a partir de `key_cols`, com o mesmo `gsub('localidade_encontrado', 'localidade_encontrada', ...)` e o mesmo apêndice de `cod_setor`. As diferenças reais são três: o join usa `temp_lograd_determ` (probabilístico), a segunda parte agrega com `FIRST()` (ponderado), e há uma coluna extra de `similaridade_logradouro`.

**A evidência de que isso custa caro é histórica, não teórica:** a correção de `logradouro_encontrado` (commit `a4b8036`) precisou ser aplicada em quatro lugares; o bug do `h3_res` vetorial apareceu duas vezes, em `geocode()` e `busca_por_cep()`, e foi corrigido em versões diferentes.

Proposta: extrair `monta_colunas_encontradas(y, key_cols, resultado_completo, agregado = FALSE)` devolvendo a lista `list(colunas, select_first, select_second)`, e deixar cada `match_*` só com sua query. Reduz os quatro arquivos em \~40% e faz correções futuras acontecerem uma vez.

### 5.2 `parent.frame()$x` como valor padrão de argumento

`geocode_core()`, `create_geocodebr_db()`, `trata_empates_geocode_duckdb()` e `cache_message()` declaram seus argumentos como `x = parent.frame()$x`. Consequências práticas:

- a função não é chamável isoladamente sem passar **todos** os argumentos — a verificação da correção do desempate precisou passar os 10 de `geocode_core()` na mão;
- ferramentas de análise estática e o próprio `R CMD check` não conseguem ver a dependência;
- um `rename` de variável no chamador quebra a callee silenciosamente.

Proposta: passar explicitamente. `trata_empates_geocode_duckdb(con, resultado_completo, resolver_empates, verboso)` já é chamada com todos os argumentos posicionalmente em `geocode.R:460-465` — os defaults ali são puro peso morto.

### 5.3 Três maneiras de achar o mesmo parquet

| local | como |
|----|----|
| `register_cnefe_tables.R:12-16` | `listar_dados_cache()` + `grepl(paste0(nome, ".parquet"))` + `grepl(data_release)` |
| `busca_por_cep.R:75-79` | `fs::path(listar_pasta_cache(), glue("geocodebr_data_release_{data_release}"), "....parquet")` |
| `geocode_reverso.R:141-145` | idêntico ao anterior, outra tabela |

Um helper `caminho_parquet(nome_tabela)` elimina a divergência. De quebra corrige a fragilidade do `grepl`: o `.` do `".parquet"` é um metacaractere de regex, não um ponto literal.

### 5.4 `get_reference_table()` monta o nome e depois o desmonta

`R/utils.R:410-439` constrói `table_name` colando `key_cols`, e em seguida sobrescreve o resultado em quatro `if (match_type %like% '...')`. Ou seja, a construção só vale para os casos que os `if` não pegam. Uma tabela de lookup nomeada (`c(dn01 = "municipio_logradouro_numero_cep_localidade", ...)`) diz a mesma coisa em 25 linhas legíveis e some com a interação entre as duas metades.

### 5.5 Código morto

`register_cnefe_tables.R` tem 293 linhas, das quais **\~136 são código comentado** (o caminho de `duckdb_register_arrow`, o bloco de índice, `write_all_cnefe_tables_to_db()`). Há também o cadáver comentado de `create_index()` em `utils.R:216-243` — a função foi removida em `746ea54`, mas o comentário ficou, e o bloco de índice em `register_cnefe_tables.R:78-97` ainda referencia a ideia. Some-se a query antiga em `string_dist.R:69-95` e o toolkit de timer em `geocode.R:143-190`.

Isso tudo está no histórico do git. Manter no arquivo faz cada leitura futura reavaliar se aquilo é ativo. Em particular, o bloco de índice merece ou remoção ou um comentário de uma linha registrando o resultado já medido: **índice piora, não melhora** (§4 do relatório anterior).

### 5.6 Menores

- `create_geocodebr_db(db_path = 'memory')` cria uma conexão em memória e imediatamente a **descarta**, sobrescrevendo `con` com uma conexão em disco (`R/create_geocodebr_db.R:18-26`). O pedido é ignorado em silêncio e a conexão vaza. Ou implementar, ou remover o ramo.
- `geocodebr::` para funções do próprio pacote (`cache.R:172,208`, `download_cnefe.R:66`, `register_cnefe_tables.R:12,128`, `geocode_reverso.R:99`) — o resto do pacote chama direto.
- O bloco que adiciona colunas H3 é idêntico em `geocode.R:535-550` e `busca_por_cep.R:120-132` (já registrado como `[LEARN:testes]` no `MEMORY.md`).
- `stop()` cru em `geocode_reverso.R:255`, fora do padrão `cli`/`geocodebr_error()` do resto do pacote.

------------------------------------------------------------------------

## 6. Hipóteses testadas e **refutadas**

Registradas para não serem re-propostas:

- **`listar_dados_cache()` chamado 34× por execução seria um gargalo de I/O.** Medido: mediana abaixo da resolução do relógio (`0,0000 s`). Irrelevante. O que vale mudar ali é a fragilidade do `grepl`, não o custo.
- **Indexar as tabelas de referência.** Medido no relatório anterior: pior em todos os cenários, porque o DuckDB resolve equi-join com hash join e nunca consulta o índice ART.
- **Trocar parquet por `.duckdb` permanente.** 4% de ganho por 3,7× de download.

------------------------------------------------------------------------

## 7. Prioridades

| \# | mudança | ganho | esforço | risco |
|----|----|----|----|----|
| 1 | Pular etapas cujo campo-chave está vazio (§1) | **3,3× a 9×** quando faltam campos; no-op quando não faltam | Muito baixo (8 linhas) | Muito baixo — medido, mesmo nº de achados |
| 2 | `TEMP VIEW` em vez de `TEMP TABLE` (§3a) | 1,5–7× na fase de 50% | Baixo | Médio — reperfilar ponta a ponta |
| 3 | Não chamar Jaro nas etapas `pa*` (§3b) | −30% do Jaro | Muito baixo | Muito baixo — no-op comprovado |
| 4 | Baixar só as tabelas necessárias (§1, corolário) | 1.492 MB → 20 MB no melhor caso | Médio | Baixo |
| 5 | Consertar `apaga_data_release_antigo()` (§2) | evita re-download de 1,46 GB; remove um erro | Baixo | Baixo |
| 6 | Ordenação determinística nos dois `QUALIFY` (§4) | reprodutibilidade | Muito baixo | Baixo |
| 7 | Helper único para os quatro `match_*` (§5.1) | manutenção | Médio | Médio — mexe no SQL de todos |
| 8 | Remover `parent.frame()` dos defaults (§5.2) | manutenção | Baixo | Baixo |
| 9 | `caminho_parquet()` único (§5.3) + lookup em `get_reference_table()` (§5.4) | manutenção | Baixo | Baixo |
| 10 | Remover código morto (§5.5) | manutenção | Muito baixo | Nenhum |

**Sequência sugerida:** 1 → 3 → 6 → 5 (tudo barato, baixo risco, e 1 e 3 são ganho direto), depois 2 com reperfilagem, e as de manutenção (7-10) numa passada própria, já que 7 mexe no SQL das quatro funções e merece a suíte rodando isolada.

------------------------------------------------------------------------

## 8. O que não foi medido

- **Escala.** Tudo aqui é com 20.028 endereços em 215 municípios de 3 UFs. O peso relativo da materialização depende do **número de municípios**; o dos joins, do **número de endereços**. Com milhões de endereços em poucos municípios, a prioridade #1 perde peso relativo (mas não muda de sinal: continua pulando trabalho impossível).
- **`geocode_reverso()` e `busca_por_cep()` não foram perfilados** nesta rodada — só lidos. `busca_por_cep()` faz uma varredura nacional do parquet sem recorte por UF, o que é viável porque o CEP é discriminante, mas não foi cronometrado. As distorções de UTM 23S de `geocode_reverso()` já estão medidas no relatório de 2026-08-23 sobre aquelas duas funções.
- **Efeito de `n_cores`** — todas as medições usaram `n_cores = 7`.
- **Ponta a ponta com o pacote instalado**, para as propostas 2, 4 e 7.
