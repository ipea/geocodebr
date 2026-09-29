# Diagnóstico — paridade do `geocode()` R vs Python sobre o CadÚnico (43,9 M de endereços)

**Data:** 2026-09-21 (rodada 1) · **2026-09-22 (rodada 2, após correção do Python — ver §6)**
**Status: PARIDADE CONFIRMADA na rodada 2.** As seções 1–5 abaixo descrevem a rodada 1 e ficam como
registro das causas encontradas; o resultado vigente é o da §6.

**Arquivos comparados (rodada 1):**
- R: `sample_data/cadunico_43M_202312_R.parquet` (2,46 GB, 21/09 14:29)
- Python: `sample_data/cad_unico_pyhton.parquet` (2,22 GB, 21/09 14:24)

**Escopo:** só o output. Comparação de código R ↔ Python fica para uma rodada futura.
**Ferramenta:** DuckDB via R, sem materializar nada na memória; tabela comparativa em
`scratchpad/cmp.duckdb` (43.882.020 linhas pareadas por `co_familiar_fam`). Scripts `01_schema.R` a
`05_final.R` no scratchpad da sessão.

---

## 1. Veredito

**A paridade está quase perfeita em coordenadas e categorias, e quebrada numa coluna.**

| Dimensão | Resultado |
|---|---|
| Linhas | 43.882.020 nos dois lados; 0 `NA` em `lat`/`lon` nos dois lados |
| Schema | Idêntico, exceto coluna `id` extra no output do R (veio do input) |
| `tipo_resultado` | Igual em 43.881.940 linhas; **80 divergem (0,00018 %)** |
| `precisao` | Idem (80 linhas) |
| Coordenadas (mesmo `tipo_resultado`) | 43.854.179 bit-a-bit iguais; 27.763 diferem em ≤ 1,4e-13 grau; **0 acima de 1e-6** |
| `endereco_encontrado`, `cod_setor`, `desvio_metros`, `contagem_cnefe`, `*_encontrado` (mesmo tipo) | **100 % iguais** |
| `empate` | 5 linhas divergem, todas dentro das 80 |
| `similaridade_logradouro` | **Divergente em 4.987.296 linhas** — todo match probabilístico. R traz o Jaro real (0,851–0,99); Python traz 1,0 em todas |

Duas causas-raiz, uma de cada lado, mais uma diferença de input:

1. **Python — `similaridade_logradouro` sempre 1,0** (bug do porte, coluna inteira inútil).
2. **Números acima do limite de inteiro de 32 bits** — R descarta (`NA`), Python mantém (`Int64`).
   Explica 78 das 80 divergências de categoria.
3. **Os inputs não eram idênticos**: 43 linhas com `numero` diferente e ordem de linhas diferente.
   Explica as 2 divergências restantes. Não é problema dos pacotes.

---

## 2. Método

1. Schema e contagem via `parquet_schema()` / `parquet_metadata()`.
2. Chave de pareamento: `co_familiar_fam` é única nos dois arquivos (43.882.020 distintos). O pareamento
   posicional **não** serve — só 10.543 linhas coincidem na mesma posição (os dois pacotes preservam a
   ordem do input, logo os inputs estavam em ordens diferentes).
3. Tabela `cmp` com as duas saídas lado a lado + flags `IS NOT DISTINCT FROM` por coluna.
4. Coordenadas comparadas por diferença absoluta em graus e por haversine em metros.
5. Causas confirmadas no código e por reprodução mínima (seção 4).

---

## 3. Achados

### 3.1 Colunas de input

Pareando por `co_familiar_fam`: `abbrev_state`, `code_muni`, `logradouro`, `cep`, `bairro` idênticos
em 100 % das linhas. **`numero` difere em 43 linhas**: o arquivo do R traz o valor original
(`SN`, `S/N`, `51`, `133`, `1511`…) e o do Python traz `0`. Como `geocode()` devolve as colunas de
input intocadas, isso significa que **os dois lados receberam inputs ligeiramente diferentes** — não
é transformação do pacote. Em 41 dessas 43 linhas o resultado coincide mesmo assim (caíram em
`dc02`/`dm01`, sem uso do número); em 2 diverge:

| `co_familiar_fam` | `numero` R | `numero` Py | tipo R | tipo Py |
|---|---|---|---|---|
| 1968851321 | 21 | 0 | `pn02` | `pl02` |
| 496186361 | 1511 | 0 | `pa02` | `pl02` |

Ou seja: com o número, R achou o número; sem ele, Python caiu para logradouro. Comportamento correto
dos dois lados dado o input de cada um.

**Ação:** conferir a proveniência dos dois inputs (o do R tem também uma coluna `id` que o do Python não
tem). Para a próxima rodada de paridade, gerar os dois outputs a partir do **mesmo arquivo parquet**.

### 3.2 `tipo_resultado`: 80 divergências, 78 com a mesma causa

Matriz das divergências:

| R | Python | n |
|---|---|---|
| `dl02` | `da02` | 31 |
| `dl01` | `da01` | 19 |
| `pl01` | `pa01` | 10 |
| `pl02` | `pa02` | 8 |
| `dl04` | `da04` | 5 |
| `dl03` | `da03` | 3 |
| `dl01` | `da04` | 1 |
| `pl03` | `pa03` | 1 |
| `pn02` | `pl02` | 1 (input, §3.1) |
| `pa02` | `pl02` | 1 (input, §3.1) |

Padrão: **R devolve "logradouro sem número" (`dl`/`pl`), Python devolve "número aproximado"
(`da`/`pa`)**. Nas 78 linhas, o `numero` de input é um valor absurdo acima de 2.147.483.647 — ex.:
`0000003000524637`, `0000002875524304`, `0000999999999999`.

- **R:** `enderecobr::padronizar_numeros(formato = "integer")` faz `as.integer()`, que devolve `NA`
  (com aviso) acima de `.Machine$integer.max`. Reproduzido:
  `padronizar_numeros(c("0000003000524637","2147483647","2147483648"), formato="integer")` →
  `NA 2147483647 NA`. O endereço segue o laço sem número e cai em `dl`/`pl`.
- **Python:** `standardize.py::_padronizar_numero_expr()` usa `padronizar_numeros_para_int` com
  `return_dtype=pl.Int64` (ou `cast(pl.Int64)` para input numérico). O número sobrevive, o laço entra
  em `da`/`pa` e a interpolação `1/ABS(numero - numero_cnefe)` escolhe o maior número da rua. O output
  fica assim:

  > `AVENIDA PRIMEIRO DE JANEIRO, 3000524637 (aprox) - CENTRO, JOAO COSTA - PI, 64765-000`,
  > `precisao = numero_aproximado`, `desvio_metros = 6`, `contagem_cnefe = 1`

  Isto é, o Python **promete 6 m de desvio para um número que não existe**, enquanto o R devolve o
  centróide do logradouro com `desvio_metros` honesto (84–8.733 m). O R está certo por acidente (o
  overflow vira `NA`), mas o resultado é o desejável.

No input inteiro há **3.294 linhas** com `numero > 2^31−1`. Em 3.216 delas os dois lados coincidem
(caíram em `dc`/`dl`/`pl`/`db`/`dm` nos dois, porque a rua não tem números no CNEFE ou nem foi
encontrada); as 78 restantes são as ruas numeradas, onde a diferença aparece.

As **5 divergências de `empate`** e as **27 linhas com coordenada a mais de 100 m** (máx. 23,6 km) estão
todas dentro dessas 78 — são consequência, não causa separada.

**Ação:** decidir o contrato para números fora de faixa e aplicar nos dois pacotes. Opções, da mais
simples à mais correta:
1. Python emula o R: `numero > 2_147_483_647 → null` na padronização. Fecha a paridade hoje.
2. Os dois pacotes tratam como `NA` qualquer número acima de um teto plausível (ex.: 6 dígitos).
   Muda comportamento do R (hoje 2.147.483.647 é aceito) — precisa de NEWS e de teste. Melhor para o
   usuário, porque `0000999999999999` e `2147483647` são igualmente lixo.
   Fica para a rodada de comparação de código.

### 3.3 `similaridade_logradouro`: Python grava 1,0 em todo match probabilístico

| Família | Lado | Valores |
|---|---|---|
| `d*` (38.894.665) | R e Python | 1,00 em todas (preenchido por `COALESCE(…, 1)`, igual nos dois) |
| `p*` (4.987.296) | R | 0,851 a 0,99 — distribuição contínua, moda em 0,98 |
| `p*` (4.987.296) | Python | **1,00 em 100 % das linhas**; mínimo 1,00 |

O SQL de `calculate_string_dist()` é o mesmo nos dois pacotes (`CAST(jaro_similarity(...) AS
NUMERIC(5,3))` → `UPDATE input_padrao_db SET similaridade_logradouro = similarity`). A diferença está
no **tipo da coluna de trabalho**:

- R (`geocode.R:452`): `input_padrao[, similaridade_logradouro := NA_real_]` → coluna `DOUBLE`.
- Python (`geocode.py:250`): `pl.lit(None).alias("similaridade_logradouro")` → dtype polars `Null` →
  Arrow `null` → **DuckDB materializa como `INTEGER`** em `CREATE TEMP TABLE input_padrao_db AS SELECT *`.
  O `UPDATE` grava `0.956` numa coluna inteira e o valor vira `1`.

Reprodução mínima (Arrow `null` → DuckDB, mesmo caminho que o polars usa):

```
DESCRIBE t                       →  similaridade_logradouro  INTEGER
UPDATE t SET similaridade_logradouro = CAST(0.956 AS NUMERIC(5,3))
SELECT …                         →  1
```

Como todo Jaro aceito é > 0,85, tudo arredonda para 1 e a coluna fica indistinguível de um match
determinístico. Nada mais é afetado: o corte `> 0.85`/`> 0.90` é aplicado sobre `similarity` na CTE,
antes do `UPDATE`, e a escolha do logradouro (`temp_lograd_determ`) não passa pela coluna inteira —
por isso `logradouro_encontrado` e coordenadas coincidem com o R.

**Ação (1 linha):** `pl.lit(None, dtype=pl.Float64).alias("similaridade_logradouro")` em
`python-package/geocodebr/geocode.py:250`. Adicionar ao teste de paridade uma checagem de que
`similaridade_logradouro < 1` para `tipo_resultado LIKE 'p%'`.

**Por que o teste de paridade não pegou:** `test_r_python_parity.py::run_all_comparisons()` compara
schema, linhas, `tipo_resultado`, coordenadas (`lat`/`lon`/`distancia_metros`, `atol=1e-6`) e células
**não numéricas**. `similaridade_logradouro`, `contagem_cnefe` e `desvio_metros` são numéricas e ficam
fora das duas listas — nunca são comparadas. Ver §5.

### 3.4 Coordenadas: ruído de ponto flutuante, dentro do esperado

Entre linhas com o mesmo `tipo_resultado`, nenhuma diferença de coordenada supera 1e-6 grau. As
27.763 linhas com diferença não nula (máx. 1,35e-13 grau ≈ 15 nm) são **todas** `da*`/`pa*` — as
categorias que calculam média ponderada por `contagem_cnefe`, cuja ordem de acumulação depende do
paralelismo do DuckDB. É o mesmo fenômeno já registrado em `MEMORY.md` (`[LEARN:testes]`, 26/08) entre
duas execuções do **mesmo** pacote R. Não é divergência de lógica.

### 3.5 Distribuição de `tipo_resultado`

Com exceção das 80 linhas, as 25 categorias têm contagens idênticas (`dn*`, `dc*`, `db01`, `dm01`,
`pn01`, `pn03` batem exatamente; `da*`/`dl*`/`pa*`/`pl*` diferem só pelos deslocamentos de §3.2). Em
`precisao`: `numero_aproximado` +77 no Python, `logradouro` −76, `numero` −1.

### 3.6 Ordem das linhas

O Python devolve as linhas em ordem quase crescente de `co_familiar_fam` (265 mil inversões em 43,9 M);
o R, não (21,4 M inversões). Os dois códigos preservam a ordem do input (`ORDER BY tempidgeocodebr` no
Python; `merge_results_to_input()` no R), então a diferença vem dos inputs, coerente com §3.1.

---

## 4. Evidência reproduzível

| Achado | Como reproduzir |
|---|---|
| int32 no R | `enderecobr::padronizar_numeros("0000003000524637", formato = "integer")` → `NA` + warning (enderecobr 0.6.1) |
| Int64 no Python | `standardize.py:68` e `:82-83` (`pl.Int64`) |
| `Null` → `INTEGER` | Arrow `null` registrada no DuckDB + `CREATE TABLE AS` → `DESCRIBE` mostra `INTEGER`; `UPDATE` com 0,956 lê 1 |
| Números | tabela `cmp` em `scratchpad/cmp.duckdb`; queries em `03_analysis.R`, `04_followup.R`, `05_final.R` |

---

## 5. Recomendações, em ordem

1. **Corrigir o dtype em `geocode.py:250`** (`pl.Float64`). Bug isolado, fix de uma linha, sem efeito
   colateral. Rodar `pytest -m "not r_parity"` e conferir que `test_geocode` cobre `resultado_completo=True`.
2. **Estender `run_all_comparisons()`** para comparar também as colunas numéricas de saída
   (`similaridade_logradouro` com `atol=1e-3`, `desvio_metros`, `contagem_cnefe`, `numero_encontrado`
   exatos). Hoje o teste é cego para esse tipo de bug.
3. **Fixar o contrato de `numero` fora de faixa** nos dois pacotes (§3.2). Enquanto não decidir, o
   Python deveria pelo menos emular o `NA` do R acima de 2^31−1, porque o output atual (`(aprox)` com
   `desvio_metros = 6`) é enganoso. Adicionar um caso com `numero = "3000524637"` a
   `small_sample.csv` ou ao teste de paridade.
4. **Refazer a comparação com o mesmo input** nos dois lados (§3.1) — os 43 números divergentes e a
   coluna `id` indicam que os arquivos de entrada não eram o mesmo objeto.
5. Registrar em `NEWS`/docstring do Python que `similaridade_logradouro` era inválida na `0.1.0`.

Fora isso, **o motor de matching está em paridade**: mesmas categorias, mesmos endereços, mesmos
setores, mesmas coordenadas, mesmos desempates, em 43,9 milhões de linhas.

---

## 6. Rodada 2 (2026-09-22) — após correção do pacote Python

**Arquivo novo do Python:** `sample_data/cad_unico_pyhton.parquet` regenerado em 22/09 09:55 (2,45 GB).
O arquivo do R é o mesmo da rodada 1. Mesmo método (§2), mesmos scripts, tabela `cmp` reconstruída.

### 6.1 Resultado

| Dimensão | Rodada 1 | Rodada 2 |
|---|---|---|
| Linhas / `NA` em `lat`/`lon` | 43.882.020 / 0 | 43.882.020 / 0 |
| Schema | `id` só no R | **Idêntico** (`id` nos dois) |
| Colunas de input iguais | 43 linhas com `numero` diferente; ordem diferente | **100 % iguais, mesma ordem** (pareamento posicional e por chave coincidem) |
| `tipo_resultado` / `precisao` | 80 linhas divergem | **0 divergências**; 25 categorias com contagens idênticas |
| `endereco_encontrado`, `*_encontrado`, `cod_setor`, `desvio_metros`, `contagem_cnefe`, `empate` | iguais fora das 80 | **100 % iguais** |
| `similaridade_logradouro` | Python = 1,0 em 4.987.296 linhas | **100 % igual**, distribuição do Jaro (0,851–0,99) idêntica valor a valor |
| Coordenadas bit-a-bit iguais | 43.854.179 | 43.856.267 |
| Coordenadas com diferença não nula | 27.763 + 78 acima de 1e-6 | 25.753, **todas ≤ 1,8e-13 grau** |
| Coordenadas acima de 1e-6 grau | 78 | **0** |
| `empate` divergente | 5 | **0** |

### 6.2 O que a correção resolveu

- **§3.3 (`similaridade_logradouro`)**: resolvido. A coluna do Python agora reproduz exatamente a do R —
  `py_eq_1 = 0`, `py_lt_1 = 4.987.296`, mínimo 0,851 nos dois lados, e cada faixa de 0,01 tem a mesma
  contagem (ex.: 0,98 → 578.933 nos dois).
- **§3.2 (`numero` > 2^31−1)**: as 78 divergências desapareceram. Os dois lados agora classificam esses
  3.294 endereços da mesma forma. Não foi verificado neste relatório *como* o Python passou a tratar o
  overflow (se emulando o `NA` do R ou de outra forma); só que o output coincide.
- **§3.1 (inputs diferentes)**: não se aplica — desta vez os dois outputs vieram do mesmo input, o que
  eliminou as 2 divergências restantes, a coluna `id` faltante e a diferença de ordem.

### 6.3 O que resta

Somente as 25.753 linhas com diferença de coordenada na ordem de 1e-13 grau (< 0,02 mm), todas em
`da*`/`pa*`, distribuídas como em §3.4: `da01` 8.056, `da02` 9.950, `da03` 1.507, `da04` 2.932,
`pa01` 1.117, `pa02` 1.737, `pa03` 454. É a ordem de acumulação da média ponderada no DuckDB, não lógica.
Está quatro ordens de grandeza abaixo do `atol = 1e-6` do teste de paridade.

### 6.4 Recomendações que continuam válidas

Das cinco de §5, as três de teste permanecem, porque o teste automatizado ainda não teria pego a rodada 1:

- Estender `run_all_comparisons()` para comparar `similaridade_logradouro`, `desvio_metros`,
  `contagem_cnefe` e `numero_encontrado` (§5, item 2).
- Adicionar um caso com `numero > 2^31−1` a um fixture de paridade (§5, item 3).
- Registrar no NEWS/docstring do Python que `similaridade_logradouro` era inválida na `0.1.0` (§5, item 5).

**Conclusão: com o input idêntico, `geocode()` em R e em Python produzem o mesmo resultado em
43.882.020 endereços do CadÚnico, em todas as colunas, com diferença máxima de 1,8e-13 grau nas
coordenadas.**
