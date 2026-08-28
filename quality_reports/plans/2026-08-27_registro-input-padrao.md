# Otimização da etapa "Register standardized input" (`input_padrao_db`)

**Status:** IMPLEMENTADO E CONFIRMADO EM 43M (27/08/2026)
**Arquivo alterado:** `r-package/R/geocode.R` (uma chamada)
**Ganho:** a etapa cai ~80% (43M: 88,5 s → 17,6 s, média de 2 corridas por braço)

## O que mudou

```r
# antes
input_padrao_arrw <- arrow::as_arrow_table(input_padrao)
DBI::dbWriteTableArrow(con, name = "input_padrao_db", input_padrao_arrw,
                       overwrite = TRUE, temporary = TRUE)

# depois
duckdb::dbWriteTable(con, "input_padrao_db", input_padrao,
                     overwrite = TRUE, temporary = TRUE)
```

O custo estava na **conversão** para Arrow, não na escrita. A conversão não traz benefício aqui: a
tabela precisa ser materializada e **mutável** de todo modo, porque o pipeline depois faz
`ALTER TABLE` + `UPDATE` (`cria_col_logradouro_confusao()`, match probabilístico) e `DELETE FROM`
(`update_input_db()`, a cada etapa do laço).

## Triagem: 5 variantes, 1M, 3 repetições com ordem invertida

| variante | mediana | min–max |
|---|---|---|
| `duckdb_register()` (view sobre objeto R) + `CTAS` | 0,39 s | 0,36–0,40 |
| **`duckdb::dbWriteTable()` (escolhida)** | **0,41 s** | 0,39–0,43 |
| `duckdb_register_arrow()` + `CTAS` | 0,76 s | 0,72–0,78 |
| `nanoarrow` stream + `dbWriteTableArrow` | 1,66 s | 1,56–1,76 |
| **atual: `as_arrow_table` + `dbWriteTableArrow`** | **1,86 s** | 1,86–1,89 |

Todas passaram no teste de mutabilidade (aceitam `DELETE`/`ALTER`) e produziram tabela equivalente.
Escolhida a `dbWriteTable` por estar empatada com a mais rápida dentro da dispersão e ser uma única
chamada — a variante `duckdb_register` exigiria `register`/`CTAS`/`unregister` com limpeza em caso de
erro. A ordenação se manteve idêntica nas 3 repetições mesmo com a ordem invertida (a variante atual
deu 1,86/1,86/1,89 s rodando em primeiro, último e primeiro), o que descarta contaminação de ordem.

## Verificação e medição pela `geocode()` COMPLETA (com `callr`)

A partir desta rodada, todo benchmark com DuckDB usa a função exportada, com um braço por processo e
uma biblioteca instalada por braço (`R CMD INSTALL -l`), conforme regra do mantenedor.

**Corretude:** `identical()` bit a bit TRUE no 1M com `n_cores = 1`. Com `n_cores` default, os outputs
divergem em ~250 linhas na 15ª casa decimal — mas o **controle** (duas corridas do próprio HEAD)
diverge na mesma magnitude e contagem, ou seja, é o não-determinismo de ponto flutuante do paralelismo,
não efeito da mudança. Checksums de `lat`/`lon` iguais em todas as corridas de 43M.

**Desempenho — 43M, 4 corridas em ordem espelhada (HEAD → novo → novo → HEAD):**

| corrida | etapa de registro | % do pipeline | total |
|---|---|---|---|
| HEAD | 90,90 s | 14,7% | 935,4 s |
| HEAD (rep. 2) | 86,02 s | 15,7% | 822,6 s |
| **novo** | **17,14 s** | **3,2%** | 825,3 s |
| **novo (rep. 2)** | **18,14 s** | **3,5%** | 799,3 s |

Média: 88,5 s → 17,6 s, **economia de ~71 s por corrida de 43M**. A diferença entre braços (71 s) é
uma ordem de grandeza maior que a dispersão dentro de cada braço (5 s no HEAD, 1 s no novo), e o
resultado se manteve com a ordem espelhada. A etapa deixa de ser a terceira mais cara do pipeline
(~15%) e cai para ~3%.

**1M, para referência:** 3,74 s → 0,50 s (`n_cores` default); 3,00 s → 0,56 s (`n_cores = 1`).

## Contraste com a tentativa anterior (merge)

Esta é a primeira otimização da sessão que entrega em escala. A diferença metodológica que importa: aqui
o sinal é grande (5×), estável (dispersão de 1-5 s contra diferença de 71 s) e com mecanismo claro
(elimina uma cópia integral do input). No caso do merge, o sinal do 1M era grande mas o mecanismo era
duvidoso, e em 43M inverteu. **Regra derivada: só confiar em ganho de 1M quando o mecanismo explicar o
número e a dispersão for pequena em relação ao efeito — e ainda assim confirmar em 43M.**
