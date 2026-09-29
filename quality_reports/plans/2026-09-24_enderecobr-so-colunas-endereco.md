# Plano — passar ao `enderecobr` só as colunas de endereço em `geocode()`

**Status:** DRAFT (aguardando aprovação)
**Data:** 24/09/2026
**Origem:** lição A3 de `quality_reports/diagnoses/2026-09-23_licoes-cruzadas-geocode-R-Python.md`
**Relacionado:** `quality_reports/plans/2026-09-24_geocode-callr-condicional.md` (ver "Interação" abaixo)

## Objetivo

Hoje `geocode_core()` entrega o input **inteiro** ao `enderecobr::padronizar_enderecos()`, que faz
`data.table::as.data.table(enderecos)` sobre todas as colunas. Em seguida `geocode_core()` joga fora tudo
o que não é `*_padr` (`R/geocode.R:413`). O objetivo é que só as colunas de endereço declaradas entrem
na padronização, sem mudar nenhum resultado.

## Estado atual (onde o input é copiado)

| Linha (`R/geocode.R`) | O que acontece | Custo por coluna extra |
|---|---|---|
| 373-386 | `padronizar_enderecos(enderecos = enderecos, ...)`, com `manter_cols_extras = TRUE` (padrão) | `as.data.table()` copia o vetor de cada coluna (8 B/linha em character, porque as strings são compartilhadas; cópia completa em numeric) |
| 388-390 | `padronizar_enderecos = FALSE` → `data.table::copy(enderecos)` | cópia **profunda** de todas as colunas |
| 409-413 | `input_padrao[, setdiff(names, cols_to_keep) := NULL]` | só descarta, depois de pagar a cópia |

Colunas que o motor realmente usa daqui para frente: as 6 `*_padr` (e as colunas-fantasma
`<campo>tempgeocodebr` quando algum campo não foi declarado). As colunas do usuário só voltam a ser usadas
no `duckdb_register(con, "input_db", enderecos)` do merge (`geocode.R:621`), que lê do próprio
`enderecos`, não de `input_padrao`.

## Mudanças

### 1. Subconjunto raso das colunas de endereço (P, `R/geocode.R`)
Logo depois do bloco das colunas-fantasma (≈ linha 360):

```r
# so as colunas de endereco entram na padronizacao: as demais colunas do
# usuario so voltam no merge final (input_db), lidas de `enderecos`
cols_endereco <- unique(unlist(campos_endereco, use.names = FALSE))
enderecos_campos <- as.list(enderecos)[cols_endereco]   # raso: nao copia os vetores
data.table::setDT(enderecos_campos)
```

`campos_endereco` já tem as colunas-fantasma nesse ponto (`geocode.R:360`), então elas entram no
subconjunto. O `unique()` cobre o caso de um usuário que aponta dois campos para a mesma coluna.

### 2. Chamada ao `enderecobr` (P)
```r
input_padrao <- enderecobr::padronizar_enderecos(
  enderecos = enderecos_campos,
  ...,
  manter_cols_extras = FALSE
)
```
`manter_cols_extras = FALSE` fica redundante (não há mais extras), mas deixa a intenção explícita e
protege contra mudança de padrão no `enderecobr`.

### 3. Caminho `padronizar_enderecos = FALSE` (P)
Trocar `data.table::copy(enderecos)` por uma cópia **só das 6 colunas `*_padr`**. A cópia continua
necessária, porque o bloco seguinte faz `:=` e `names<-` por referência.
```r
cols_padr_presentes <- intersect(all_cols_padr, names(enderecos))
input_padrao <- data.table::copy(data.table::setDT(as.list(enderecos)[cols_padr_presentes]))
```
A checagem `check_padr` e o `error_input_nao_padronizado()` seguem valendo sem mudança, porque um
`*_padr` ausente continua ausente.

### 4. Limpeza (P)
- O `input_padrao[, setdiff(...) := NULL]` (`geocode.R:409-413`) vira quase sempre no-op. **Manter**
  como defesa: o `enderecobr` devolve as colunas originais de endereço junto com as `*_padr`.
- `rm(enderecos_campos)` logo após a padronização.

### 5. Python — espelhamento opcional (P)
`geocode.py:230` também chama `enderecobr_padronizar_enderecos(..., manter_cols_extras=True)` com o
`df_input` inteiro. Lá o custo é desprezível (`clone()` do polars é raso), então **não é necessário**. Se
quisermos simetria de código, trocar por `df_input.select(cols_endereco)` + `manter_cols_extras=False`.
O resultado não muda nos dois casos, então a paridade não é afetada.

## Efeito colateral a verificar (possível bug latente)

`cols_to_keep <- names(input_padrao)[names(input_padrao) %like% '_padr']` (`geocode.R:408`) hoje também
pega **colunas do usuário** cujo nome contenha `_padr` (ex.: `renda_padr`). Elas são renomeadas
(`renda`) e vão para `input_padrao_db`. Se o nome coincidir com um campo (ex.: uma coluna extra
`cep_padr`), pode haver colisão com o `cep_padr` gerado pelo `enderecobr`. Com o subconjunto do passo 1
isso deixa de acontecer, mas é preciso **confirmar com um teste** qual é o comportamento hoje antes de
anunciar como correção.

## Interação com o plano do `callr` condicional

O plano `2026-09-24_geocode-callr-condicional.md` propõe rodar `geocode_core()` no próprio processo e,
para proteger o objeto do usuário, passar `data.table::copy(enderecos)`, uma cópia profunda do input
inteiro. Depois desta mudança, `geocode_core()` só escreve em `enderecos` em dois lugares:

1. Colunas-fantasma (`geocode.R:355-357`), que **podem ir só para `enderecos_campos`**. Mas o merge
   final lê `names(enderecos)` e remove as fantasmas pelo nome (`geocode.R:650-654`), então esse trecho
   precisa ser ajustado junto.
2. `tempidgeocodebr` (`geocode.R:428`), necessária no `input_db` do merge.

Se os dois forem feitos numa cópia **rasa** (`as.list(enderecos)` + coluna nova + `setDT`), o caminho em
processo deixa de precisar do `data.table::copy()` completo. **Recomendação:** fazer este plano primeiro
(fases 1-4, isolado e de baixo risco) e tratar a remoção do `copy()` como fase 2 dentro do plano do
`callr`, coordenando com quem está nele.

## Ganho esperado

- **Memória:** um vetor de 8 B/linha por coluna extra do usuário (character), ou a coluna inteira
  (numeric), durante a padronização. Exemplo: CadÚnico com 43 M linhas × ~10 colunas extras ≈ 3,4 GB a
  menos de pico nessa etapa. Com `padronizar_enderecos = FALSE`, o mesmo ganho sobre a cópia profunda.
- **Tempo:** desprezível (`as.data.table()` de 1 M × 17 colunas: 0,03-0,17 s). Não é o motivo da mudança.
- **Com o plano do `callr`:** elimina a cópia profunda do input inteiro no caminho em processo (fase 2).

## Verificação

1. **`identical()` antes/depois** (critério do projeto para otimizações do R), com `geocode_core()` em
   lib temporária, sobre:
   - `large_sample.parquet`, com `resultado_completo = TRUE` e `FALSE`;
   - o mesmo input acrescido de ~10 colunas extras de tipos variados (character, integer, double, factor,
     Date, POSIXct);
   - um input com campo não declarado (colunas-fantasma), por exemplo sem `cep`;
   - `padronizar_enderecos = FALSE`, com input pré-padronizado.

   Só `lat`/`lon` podem diferir, e dentro do ruído conhecido de ~1e-14 dos empates (`[LEARN:testes]`).
2. **Teste novo em `tests/testthat/test-geocode.R`:** input com uma coluna extra chamada `algo_padr` (e
   uma `cep_padr` não declarada). O output tem que preservá-las intactas e o geocode não pode mudar.
   Rodar antes da mudança para registrar o comportamento atual.
3. **Memória:** `bench::mark(memory = TRUE)` do trecho de padronização, 1 M linhas × 20 colunas, antes e
   depois.
4. **Snapshots de mensagens:** os avisos do `enderecobr` (ex.: "Alguns números não puderam ser
   convertidos...") têm que continuar iguais, porque as mesmas colunas são padronizadas.
5. `/r-package-check r-package` (R CMD check --as-cran) e `pytest -m r_parity` pelo CI.

## Arquivos

- `r-package/R/geocode.R` (passos 1-4, ~15 linhas)
- `r-package/tests/testthat/test-geocode.R` (teste da seção "Efeito colateral")
- `r-package/NEWS.md`: só se o teste confirmar o bug das colunas `*_padr`. Caso contrário, é uma mudança
  interna sem efeito visível.
- (opcional) `python-package/geocodebr/geocode.py` (passo 5)

## Tamanho estimado

P: ~15 linhas de código + ~30 de teste. Sem mudança de resultado e sem impacto na paridade.
