# Achados da revisão de `geocode_reverso()` e `busca_por_cep()` — 2026-08-23

Revisão de `R/geocode_reverso.R` e `R/busca_por_cep.R`. Companion de
[`2026-08-22_geocode-pipeline-achados.md`](2026-08-22_geocode-pipeline-achados.md).

O funcionamento normal das duas funções está documentado em [`CLAUDE.md`](../../CLAUDE.md) — "Notas sobre
pipeline de cada função". Aqui só o que parece defeito. Nada foi corrigido; são achados para decisão.

Itens marcados *verificado* foram reproduzidos empiricamente, não inferidos por leitura.

---

## 1. CRÍTICO — `busca_por_cep()` repetia o bug de `h3_res` já corrigido em `geocode()`

**Verificado. CORRIGIDO em 2026-08-23.** Falha silenciosa, sem erro — o pior modo de falha.

`R/busca_por_cep.R:116-128` usa a **variável do vetor** dentro do laço em vez da variável de iteração:

```r
for (i in h3_res) {
  colname <- paste0('h3_', formatC(h3_res, width = 2, flag = "0"))   # h3_res, não i
  output_df[!is.na(lat), {{ colname }} := h3r::latLngToCell(..., resolution = i)]
}
```

`R/geocode.R:531-535` faz o certo (`formatC(i, ...)`). Este é exatamente o bug descrito no `NEWS.md` da
v0.6.4 — *"A função estava sobre-escrevendo as colunas quando se passava um vetor de várias resoluções de
`h3_res`"* — corrigido lá e **não replicado aqui**.

Com `h3_res = c(7, 10)`, `colname` é o vetor `c("h3_07","h3_10")` em toda iteração, então cada passagem
grava **as duas colunas** com a resolução corrente. A última iteração vence:

```
h3_07             h3_10
8aa8100c066ffff   8aa8100c066ffff      <- ambas são resolução 10
```

A coluna `h3_07` contém um índice H3 de **resolução 10**. Não há erro nem aviso; o usuário recebe dados
errados com o rótulo certo. Com `h3_res` escalar o resultado é correto, o que explica a passagem
despercebida (o exemplo da documentação usa `h3_res = 10`).

**Correção aplicada:** `formatC(h3_res, ...)` → `formatC(i, ...)`, igual ao `geocode()`.

Verificado extraindo o bloco H3 do próprio arquivo e comparando com `h3r::latLngToCell()` chamado
diretamente: com `h3_res = c(7, 10)` as duas colunas passam a conter os índices corretos e distintos;
o caso escalar (`h3_res = 10`) não regrediu; e as resoluções-limite `c(0, 5, 15)` saem corretas, com o
zero-padding esperado (`h3_00`, `h3_05`, `h3_15`). Ver entrada em `NEWS.md`.

---

## 2. CRÍTICO — `geocode_reverso()` quebrava se o `sf` de input não tivesse coluna `id`

**Verificado. CORRIGIDO em 2026-08-23.** Reproduzido o erro exato do binder.

`R/geocode_reverso.R:228-231` particiona por `a.id`:

```sql
ROW_NUMBER() OVER (PARTITION BY a.id ORDER BY distancia_metros) AS rn
```

Mas `id` **não é uma coluna que a função cria ou exige** — o identificador que ela própria gera é
`tempidgeocodebr` (linha 73). O `PARTITION BY` deveria ser por ele.

```
Binder Error: Table "a" does not have a column named "id"
```

Dois modos de falha, conforme o input do usuário:

- **Sem coluna `id`** → erro de SQL, a função não roda. É o caso de qualquer `sf` comum.
- **Com coluna `id` não única** → sem erro, mas o `ROW_NUMBER()` particiona pelo grupo errado e a função
  devolve **um único endereço por grupo de `id`**, em vez de um por ponto de input.

**Por que passa despercebido:** o arquivo de exemplo `inst/extdata/pontos.rds` tem exatamente as colunas
`id` e `geometry`, e o `id` é único. Todos os exemplos e testes usam esse arquivo.

**Correção aplicada:** `PARTITION BY a.id` → `PARTITION BY a.tempidgeocodebr`.

A substituição é suficiente: `a.id` era a **única** referência a `id` na função. Todo o resto já usava
`tempidgeocodebr` — o join (linha 241), o `ORDER BY` final (244) e o descarte da coluna auxiliar (268).
Era resíduo de uma versão anterior em que o identificador se chamava `id`.

Verificado com a função real e dados reais do CNEFE, usando pontos derivados de endereços do próprio CNEFE
para garantir correspondência (os 4 pontos de `inst/extdata/pontos.rds` não servem: com `dist_max = 1000`,
3 deles não têm endereço próximo e são descartados pelo achado 4, mascarando o teste):

| Input | Antes | Depois |
|---|---|---|
| `sf` com `id` único | 4 linhas → 4 | 4 linhas → 4 (inalterado) |
| `sf` sem coluna `id` | `Binder Error` | 4 linhas → 4 |
| `sf` com `id` duplicado | silenciosamente 1 linha por *grupo de id* | 4 linhas → 4 |

Endereços e distâncias saem idênticos com e sem a coluna `id`, confirmando que o caso que já funcionava não
regrediu. O modo silencioso, isolado em SQL: com `id = (A,A,B,B)` para 4 pontos, o `PARTITION BY a.id`
devolvia **2 linhas** — os pontos 2 e 4 desapareciam sem aviso. Ver entrada em `NEWS.md`.

---

## 3. MÉDIO — `geocode_reverso()` usa uma única zona UTM para o Brasil inteiro

**Verificado.**

`R/geocode_reverso.R:170-185` reprojeta CNEFE e pontos para **EPSG:31983** (SIRGAS 2000 / UTM 23S) para
medir distâncias em metros. A zona 23S é centrada em -45° de longitude; a distorção de escala cresce com o
afastamento do meridiano central. Medido, comparando 1000 m geodésicos com a distância projetada:

| Local | Geodésico | EPSG:31983 | Erro |
|---|---|---|---|
| São Paulo (-46,6) | 998,9 m | 1000,5 m | +0,2% |
| Salvador (-38,5) | 998,9 m | 1006,0 m | +0,7% |
| Manaus (-60,0) | 998,9 m | 1035,0 m | +3,6% |
| Rio Branco (-67,8) | 998,9 m | 1082,2 m | **+8,3%** |

Afeta duas coisas ao mesmo tempo: a coluna `distancia_metros` devolvida ao usuário, e o raio efetivo do
buffer de busca. No Acre, `dist_max = 1000` corresponde a ~920 m reais.

**Correções possíveis:** usar `ST_Distance_Sphere` / distância geodésica em vez de projetar; escolher a
zona UTM por município; ou projetar para um CRS equidistante adequado. Alternativa mínima: documentar a
limitação.

---

## 4. MÉDIO — `geocode_reverso()` descarta silenciosamente pontos sem endereço próximo

`R/geocode_reverso.R:232-234` usa `JOIN` (inner) entre `pontos_utm` e `join_result`. Pontos sem nenhum
endereço do CNEFE dentro de `dist_max` simplesmente **não aparecem no output**, sem aviso. A função só
falha se *nenhum* ponto encontrar endereço (linha 255-257).

Consequência: `nrow(output)` pode ser menor que `nrow(pontos)`, e como `tempidgeocodebr` é removido no
final (linha 261), **o usuário não tem como saber quais pontos foram perdidos**. Isso diverge do contrato
de `geocode()`, que preserva todas as linhas e devolve `NA`.

O `@return` da documentação diz "Retorna o `sf data.frame` de input adicionado das colunas do endereço
encontrado", o que sugere preservação de todas as linhas.

---

## 5. MÉDIO — `busca_por_cep()` nunca desconectava do DuckDB

**CORRIGIDO em 2026-08-23.**

`R/busca_por_cep.R` abria a conexão na linha 68 e **não chamava `duckdb::dbDisconnect()` em lugar nenhum**.
`geocode()` (linha 527) e `geocode_reverso()` (linha 264) desconectam.

Cada chamada deixava uma conexão aberta e um arquivo `.duckdb` no `tempdir()`. Em uso interativo repetido
ou em laço, acumula descritores e arquivos temporários.

**Correção aplicada:** `on.exit(duckdb::dbDisconnect(con), add = TRUE)` logo após a criação da conexão.
Optou-se por `on.exit` em vez de uma chamada no fim da função porque `busca_por_cep()` tem um
`cli_abort()` no meio (linha ~105, "Nenhum CEP foi encontrado") — um `dbDisconnect()` no fim nunca seria
alcançado nesse caminho.

Verificado com a função real e dados reais do CNEFE, instrumentando `create_geocodebr_db()` para capturar
a conexão e checando `DBI::dbIsValid()` após o retorno: `FALSE` (fechada) tanto no caminho de sucesso
quanto no de abort. O contraste com a estrutura anterior, medido da mesma forma, dá conexão **ainda aberta**
no caminho de abort. Ver entrada em `NEWS.md`.

> Nota metodológica: a primeira tentativa de verificação usou "o arquivo `.duckdb` pode ser apagado?" como
> proxy para "a conexão fechou?". **Esse proxy é inválido** — o arquivo se mostrou apagável nos dois casos.
> `DBI::dbIsValid()` sobre a conexão capturada é a medida correta.

**Estendido a todo o pacote em 2026-08-23.** `geocode_core()` (`R/geocode.R`) e `geocode_reverso()`
também desconectavam apenas com uma chamada no fim do corpo — um erro no meio vazava a conexão. Ambas
receberam a mesma rede de segurança, mas em forma **guardada**, porque nelas o `dbDisconnect()` explícito
foi mantido:

```r
on.exit(if (DBI::dbIsValid(con)) duckdb::dbDisconnect(con), add = TRUE)
```

O teste `dbIsValid()` é obrigatório: verificado que uma segunda chamada a `dbDisconnect()` sobre a mesma
conexão emite o aviso `"Connection already closed."` — sem o guarda, esse aviso apareceria em toda chamada
bem-sucedida das duas funções.

Verificado com as funções reais e dados reais do CNEFE, em quatro caminhos, capturando a conexão via
instrumentação de `create_geocodebr_db()` e checando `DBI::dbIsValid()` após o retorno:

| Caminho | Saída | Conexão fechada | Aviso espúrio |
|---|---|---|---|
| `geocode_core()` normal | sucesso (3/3 geocodificados) | sim | não |
| `geocode_core()` com `resultado_completo = TRUE` | erro do achado 1 | **sim** | não |
| `geocode_reverso()` normal | sucesso | sim | não |
| `geocode_reverso()` com `sf` sem coluna `id` | erro do achado 2 | **sim** | não |

Os dois caminhos de erro são exatamente os achados 1 (do relatório de `geocode()`) e 2 (deste relatório) —
usá-los como gatilho testa o `on.exit` contra falhas reais em vez de simuladas.

---

## 6. BAIXO — `T`/`F` em vez de `TRUE`/`FALSE`

Red flag de política CRAN (`T` e `F` são variáveis reatribuíveis, não constantes):

- `R/geocode_reverso.R:183` — `overwrite = T`
- `R/geocode_reverso.R:203` — `overwrite = T`
- `R/cache.R:175` — `recursive = T`

---

## 7. BAIXO — `busca_por_cep()` não expõe `n_cores`, e depende de um default frágil

`busca_por_cep()` é a única das três funções sem parâmetro `n_cores` — o usuário não controla o
paralelismo do DuckDB ali.

Além disso, ela chama `create_geocodebr_db()` sem argumentos, e a assinatura dessa função é
`n_cores = parent.frame()$n_cores` (`R/create_geocodebr_db.R:4`). Funciona por acidente: como
`busca_por_cep()` não tem variável local `n_cores`, a expressão devolve `NULL` e o default
(`min(availableCores(), freeConnections())`) entra em ação. É um default que depende do frame do chamador
em vez de ser explícito — frágil a refatoração.

---

## 8. BAIXO — erro fora do padrão em `geocode_reverso()`

`R/geocode_reverso.R:254-257` está marcado `# TODO` e usa `stop()` cru:

```r
stop("Nenhum endereco proximo foi encontrados")
```

O padrão do pacote é `cli::cli_abort()` / `geocodebr_error()` (ver `R/error.R`). Além disso a frase tem
erro de concordância ("endereco proximo foi encontrados") e falta acentuação, ao contrário das demais
mensagens ao usuário.

---

## Resumo

| # | Severidade | Função | Item |
|---|---|---|---|
| 1 | ~~Crítico~~ | `busca_por_cep()` | ~~Bug de `h3_res` vetorial~~ — **corrigido** (`formatC(i, ...)`) |
| 2 | ~~Crítico~~ | `geocode_reverso()` | ~~`PARTITION BY a.id`~~ — **corrigido** (`a.tempidgeocodebr`) |
| 3 | Médio | `geocode_reverso()` | UTM 23S para o país inteiro — até +8,3% de erro na distância |
| 4 | Médio | `geocode_reverso()` | `INNER JOIN` descarta pontos sem match, sem aviso |
| 5 | ~~Médio~~ | `busca_por_cep()` | ~~Conexão DuckDB nunca fechada~~ — **corrigido** (`on.exit`) |
| 6 | Baixo | ambas + `cache.R` | `T`/`F` em vez de `TRUE`/`FALSE` |
| 7 | Baixo | `busca_por_cep()` | Sem `n_cores`; default via `parent.frame()` |
| 8 | Baixo | `geocode_reverso()` | `stop()` fora do padrão `cli`, com erro de português |
