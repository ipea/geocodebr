# Análise do geocodebr — desempenho e manutenção — 2026-08-23

**Escopo:** os 19 arquivos de `R/` na íntegra — as quatro funções exportadas principais (`geocode()`, `geocode_reverso()`, `busca_por_cep()`, `download_cnefe()`), as funções de cache e as internas de apoio (`match_*`, `register_*`, `string_dist`, `trata_empates_*`, `create_geocodebr_db`, `utils`).

**Base de código:** escrito contra `a4b8036`; **atualizado em 2026-08-23** para remover os itens resolvidos na mesma sessão (ver "Resolvido" abaixo). As subseções de manutenção mantiveram seus números originais (§5.1, §5.5, §5.6) — daí os buracos na numeração; as seções de topo foram renumeradas. A tabela abaixo se refere à **numeração anterior**.

**Método:** leitura integral, seguida de medição. Tudo que é numérico aqui foi medido nesta máquina contra o cache real do CNEFE (release `v0.4.1`, 1,46 GB, 8 parquets), com `inst/extdata/large_sample.parquet` (20.028 endereços, 215 municípios, 3 UFs), chamando `geocode_core()` direto — `geocode()` roda em `callr::r(package = TRUE)` e carregaria a versão *instalada*, não a do branch. Os protótipos foram medidos numa `git worktree` em `a4b8036`, com 2 a 4 repetições e ordem invertida entre condições.

Complementa (não repete) `2026-08-23_geocode-diagnostico-performance.md`, que perfilou o caminho feliz de `geocode()`. Os itens de lá que continuam abertos estão na §3.

------------------------------------------------------------------------

## Resolvido (removido deste relatório)

| item (numeração anterior) | o que era | onde foi resolvido |
|----|----|----|
| §2 | `apaga_data_release_antigo()` apagava a pasta de cache inteira quando um release antigo convivia com o corrente, e quebrava com `missing value where TRUE/FALSE needed` diante de pasta com nome fora do padrão | `d49e53f` — passa a apagar só os releases antigos, comparando pelo nome da pasta; teste de regressão em `test-cache.R` |
| §5.2 | `parent.frame()$x` como valor padrão de argumento em `geocode_core()`, `create_geocodebr_db()`, `trata_empates_geocode_duckdb()` e `cache_message()` | 17 defaults removidos; argumentos passados explicitamente. Os `.envir = parent.frame()` de `error.R`/`message.R`/`progress_bar.R` foram mantidos — são outro idioma, legítimo |
| §5.3 | três maneiras diferentes de montar o caminho do mesmo parquet | `2b4bc59` — `caminho_parquet(nome_tabela)` em `R/cache.R`, usada nos quatro pontos de leitura; teste em `test-cache.R` |
| §5.4 | `get_reference_table()` montava o nome pelas `key_cols` e o sobrescrevia em quatro `%like%` | substituída por `reference_table_by_match_type`, vetor nomeado com os 28 `match_type`; mapeamento verificado idêntico ao anterior e congelado em `test-utils.R` |
| §5.6, 1º item | `create_geocodebr_db(db_path = 'memory')` criava uma conexão e a descartava | ramo removido |
| §5.6, último item | `geocode_reverso()` falhava com `attr(obj, "sf_column") does not point to a geometry column` quando o namespace do `sf` não estava carregado: sem `[.sfc` registrado, um simples `pontos[1:10, ]` no código do usuário destruía a classe da coluna de geometria em silêncio | `@importFrom sf st_crs st_geometry_type st_bbox` em `geocodebr-package.R` — o `sf` passa a ser carregado junto com o pacote. Verificado: `[.sfc` registrado após `library(geocodebr)`, subconjunto preserva `sfc_POINT/sfc`, e o caso que falhava retorna normalmente |
| §4, metade | não-determinismo entre execuções: duas chamadas idênticas divergiam em até 14 dos 20.028 endereços | **parcialmente resolvido.** Os dois `QUALIFY` de `trata_empates_geocode_duckdb.R` passaram a ordenar por `id`, e o próprio `id` ganhou `lat, lon` como critério final — isso reduziu a divergência de 3-9 para 1-2 linhas por rodada. A outra metade (os `FIRST()` dos matches ponderados) **não está na árvore**: ver §4 |
| §2 | `cache = FALSE` baixava para um diretório temporário e lia da pasta de cache persistente: erro `IO Error: No files found` para quem não tinha cache, e download descartado para quem tinha | opção A implementada — `caminho_parquet()` ganhou o argumento `pasta_dados`, propagado a partir do valor devolvido por `download_cnefe()` (`+1 argumento` nos dois `register_*` e nos quatro `match_*`). Teste de regressão em `test-busca_por_cep.R`, com `local_mocked_bindings()` e parquet sintético; verificado que ele falha no código anterior com o `IO Error` esperado |

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

## 3. Desempenho: o que já estava medido e segue aberto

Do relatório anterior, sem alteração no código desde então:

| \# | item | ganho medido | onde |
|----|----|----|----|
| a | `CREATE TEMP VIEW` em vez de `TEMP TABLE` em `register_cnefe_table()` | 1,5–7× na fase que é \~50% do tempo | §3 do relatório anterior |
| b | `pa01`/`pa02`/`pa03` chamam `calculate_string_dist()` sem poder resolver nada | −30% do tempo de Jaro | §6 |
| c | `callr` custa 1,73 s fixos por chamada de `geocode()` (21%) | até 1,73 s | §5 |

O item (b) foi reconfirmado nesta rodada: no cenário completo, `pa01`+`pa02`+`pa03` custaram 0,55 s dos 1,85 s de Jaro, e a razão de serem no-op continua valendo (mesma tabela de logradouros e mesmo corte que a etapa `pn*` anterior, e `calculate_string_dist()` só olha linhas com similaridade `NULL`).

Os itens (a) e (1) desta análise **se compõem bem**: (1) reduz *quantas* tabelas são materializadas, (a) reduz o custo de materializar *cada* uma. Nenhum dos dois torna o outro desnecessário.

**Um item novo, pequeno:** `register_unique_logradouros_table()` filtra por `estado` e `municipio` quando lê da tabela raiz já materializada, mas **só por `municipio`** quando lê do parquet (`R/register_cnefe_tables.R:204-215`). Materializa mais linhas do que precisa; não afeta resultado, porque o join em `calculate_string_dist()` inclui `estado`.

------------------------------------------------------------------------

## 4. Em aberto: os `FIRST()` dos matches ponderados

Duas coisas moram no mesmo lugar do código e por isso não se separam: **um não-determinismo residual** e
**uma decisão de semântica** que o mantenedor optou por adiar em 2026-08-23.

### O que ainda varia entre execuções

Nos dois arquivos de match ponderado, a segunda parte da query agrega com `FIRST()` **sem `ORDER BY`**. O
`GROUP BY tempidgeocodebr, endereco_encontrado` colapsa vários registros do CNEFE numa linha só — o regexp
troca o número pelo do input, então todos os candidatos da mesma rua viram a mesma string — e `FIRST()`
escolhe um qualquer entre eles. Como `contagem_cnefe` alimenta o desempate, isso vaza para as coordenadas.

Medido: duas rodadas do mesmo código divergem em ~1-2 coordenadas e ~4-17 valores de `contagem_cnefe` /
`cod_setor`, em 20.028 endereços.

> **Consequência prática:** enquanto isso não fechar, **nenhum refactor pode ser verificado por igualdade
> exata** — foi exatamente o que impediu a verificação do item da §5.3 e do `cache = FALSE` de serem
> conclusivas por comparação de output. Isso pesa na hora de atacar a §5.1.

### O patch existe e foi medido, mas não está na árvore

A correção é dar ordem canônica a esses `FIRST()`:

``` sql
FIRST(contagem_cnefe ORDER BY ABS(numero - numero_cnefe), numero_cnefe, lat, lon)
```

Com ela aplicada, o resultado passou a ser **exatamente reproduzível** (0 divergências em 4 rodadas, e
independência exata entre `resultado_completo` FALSE e TRUE), **sem custo de tempo** (mediana 9,84 s → 9,62 s,
dentro da variância). O patch foi aplicado e medido em 2026-08-23, mas não sobreviveu na árvore.

### Por que ele não é uma correção neutra — a decisão pendente

Ordenar os `FIRST()` obriga a escolher **qual** registro descreve o grupo. Hoje é um registro arbitrário, o
que não é alternativa defensável; mas "o mais próximo" não é a única defensável.

A dúvida é sobre `contagem_cnefe`, porque ela **não é só descritiva**: a regra de desempate a usa como proxy
de "quanta evidência do CNEFE sustenta este candidato" (`man/roxygen/templates/empates_section.R`). Para um
candidato que é a agregação de N registros, o **total** talvez descreva a evidência melhor.

| opção | o que significa | efeito colateral |
|----|----|----|
| `FIRST(... ORDER BY ABS(numero - numero_cnefe), ...)` | "o endereço mais próximo tem N registros" | nenhum além do já medido |
| `SUM(contagem_cnefe)` | "esta interpolação se apoia em N registros no total" | muda a regra de desempate: candidatos interpolados passam a competir com peso maior contra os exatos |

Efeito medido da primeira opção, em relação ao comportamento arbitrário de hoje: **203 dos 20.028 endereços
(1,0%)** mudam de coordenada (`da02` 122, `da04` 70, `pa02` 11; 173 deles eram casos de empate),
`contagem_cnefe` muda em 1.959 linhas e `cod_setor` em 1.207. Se a escolha for `SUM`, o efeito precisa ser
medido nos mesmos moldes antes de adotar.

**Quem decide é quem escreveu a regra de desempate.**

------------------------------------------------------------------------

## 5. Manutenção

### 5.1 Os quatro `match_*` são a mesma função escrita quatro vezes

`match_cases`, `match_weighted_cases`, `match_cases_probabilistic` e `match_weighted_cases_probabilistic` têm \~80% de código idêntico: o bloco que monta `colunas_encontradas`/`additional_cols` a partir de `key_cols`, com o mesmo `gsub('localidade_encontrado', 'localidade_encontrada', ...)` e o mesmo apêndice de `cod_setor`. As diferenças reais são três: o join usa `temp_lograd_determ` (probabilístico), a segunda parte agrega com `FIRST()` (ponderado), e há uma coluna extra de `similaridade_logradouro`.

**A evidência de que isso custa caro é histórica, não teórica:** a correção de `logradouro_encontrado` (commit `a4b8036`) precisou ser aplicada em quatro lugares; o bug do `h3_res` vetorial apareceu duas vezes, em `geocode()` e `busca_por_cep()`, e foi corrigido em versões diferentes.

Proposta: extrair `monta_colunas_encontradas(y, key_cols, resultado_completo, agregado = FALSE)` devolvendo a lista `list(colunas, select_first, select_second)`, e deixar cada `match_*` só com sua query. Reduz os quatro arquivos em \~40% e faz correções futuras acontecerem uma vez.

### 5.5 Código morto

`register_cnefe_tables.R` tem 284 linhas, das quais **161 são comentários** — quase todos código desativado: o caminho de `duckdb_register_arrow` (dois blocos, linhas 20-53 e 143-182), o bloco de `CREATE INDEX` (78-97) e `write_all_cnefe_tables_to_db()` (227-268). Há também o cadáver comentado de `create_index()` em `utils.R:213`, a query antiga em `string_dist.R:69-95` e o toolkit de timer em `geocode.R:144-190`.

Isso tudo está no histórico do git. Manter no arquivo faz cada leitura futura reavaliar se aquilo é ativo. Em particular, o bloco de índice merece ou remoção ou um comentário de uma linha registrando o resultado já medido: **índice piora, não melhora** (§4 do relatório anterior).

Duas funções internas **sem nenhum chamador**, que também não deveriam continuar no pacote: `cache_message()` (`utils.R`, com `man/cache_message.Rd` gerado) e `register_geocodebr_tables()` (`register_cnefe_tables.R:271`).

### 5.6 Menores

- `geocodebr::` para funções do próprio pacote, em `download_cnefe.R:66`, `geocode_reverso.R:99` e `register_cnefe_tables.R:274` — o resto do pacote chama direto.
- `T` em vez de `TRUE` em `geocode_reverso.R:186,206` (`T` é uma variável reatribuível, não uma constante).
- O bloco que adiciona colunas H3 é idêntico em `geocode.R:539-550` e `busca_por_cep.R:120-130` (já registrado como `[LEARN:testes]` no `MEMORY.md`).
- `stop()` cru em `geocode_reverso.R:259` e `utils.R:21`, fora do padrão `cli`/`geocodebr_error()` do resto do pacote.
- **Falha intermitente no `R CMD check`, não reproduzida.** Em 2026-08-23 o check falhou em
  `test-geocode.R:175` ("test empates") com `callr subprocess failed: could not start R, exited with
  non-zero status, has crashed or was killed` — morte do processo, não erro de R. Rodei o check duas vezes
  depois disso, na árvore com a mudança e no HEAD anterior: **as duas passaram**. As três chamadas do teste
  também passam isoladamente. Descartados `R_TESTS` (o `callr` já o neutraliza via `rcmd_safe_env()`) e
  memória (o input tem 27 endereços em poucos municípios). Mitigação aplicada: `shared_home = TRUE` no
  construtor `duckdb()`, que remove a concorrência entre processos pelo `~/.duckdb` — sem prova de que
  resolve, porque a falha não reproduz. Se voltar, capturar a saída do subprocesso com `callr::r(stderr = )`.

------------------------------------------------------------------------

## 6. Hipóteses testadas e **refutadas**

Registradas para não serem re-propostas:

- **`listar_dados_cache()` chamado 34× por execução seria um gargalo de I/O.** Medido: mediana abaixo da resolução do relógio (`0,0000 s`). Irrelevante. (O que valia mudar ali era a fragilidade do `grepl`, resolvida com `caminho_parquet()`.)
- **Indexar as tabelas de referência.** Medido no relatório anterior: pior em todos os cenários, porque o DuckDB resolve equi-join com hash join e nunca consulta o índice ART.
- **Trocar parquet por `.duckdb` permanente.** 4% de ganho por 3,7× de download.

------------------------------------------------------------------------

## 7. Prioridades

| \# | mudança | ganho | esforço | risco |
|----|----|----|----|----|
| 1 | Pular etapas cujo campo-chave está vazio (§1) | **3,3× a 9×** quando faltam campos; no-op quando não faltam | Muito baixo (8 linhas) | Muito baixo — medido, mesmo nº de achados |
| 2 | Não chamar Jaro nas etapas `pa*` (§3b) | −30% do Jaro | Muito baixo | Muito baixo — no-op comprovado |
| 3 | Fechar o não-determinismo residual: ordenar os `FIRST()` dos matches ponderados (§4) | reprodutibilidade; **habilita verificar refactors por igualdade exata** | Muito baixo (patch pronto) | Baixo — mas depende da decisão sobre `contagem_cnefe` |
| 4 | `TEMP VIEW` em vez de `TEMP TABLE` (§3a) | 1,5–7× na fase de 50% | Baixo | Médio — reperfilar ponta a ponta |
| 5 | Baixar só as tabelas necessárias (§1, corolário) | 1.492 MB → 20 MB no melhor caso | Médio | Baixo |
| 6 | Helper único para os quatro `match_*` (§5.1) | manutenção | Médio | Médio — mexe no SQL de todos |
| 7 | Remover código morto e as duas funções sem chamador (§5.5) | manutenção | Muito baixo | Nenhum |

**Sequência sugerida:** 1 → 2 (barato, baixo risco, e ambos são ganho direto), depois 3 — que é pré-requisito prático para 6, porque sem ele não dá para provar que um refactor não mudou o resultado. Depois 4, com reperfilagem. As de manutenção (6 e 7) numa passada própria.

------------------------------------------------------------------------

## 8. O que não foi medido

- **Escala.** Tudo aqui é com 20.028 endereços em 215 municípios de 3 UFs. O peso relativo da materialização depende do **número de municípios**; o dos joins, do **número de endereços**. Com milhões de endereços em poucos municípios, a prioridade #1 perde peso relativo (mas não muda de sinal: continua pulando trabalho impossível).
- **`geocode_reverso()` e `busca_por_cep()` não foram perfilados** nesta rodada — só lidos. `busca_por_cep()` faz uma varredura nacional do parquet sem recorte por UF, o que é viável porque o CEP é discriminante, mas não foi cronometrado. As distorções de UTM 23S de `geocode_reverso()` já estão medidas no relatório de 2026-08-23 sobre aquelas duas funções.
- **Efeito de `n_cores`** — todas as medições usaram `n_cores = 7`.
- **Ponta a ponta com o pacote instalado**, para as propostas 5, 6 e 7.
