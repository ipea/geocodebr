# Item #1 implementado: laço pula match_types cujo campo não foi declarado — 2026-08-25

**Resultado: mudança aplicada e mantida.** `identical()` bit-a-bit entre antes/depois nos dois cenários
testados; ganho de **4,2×** no cenário que a mudança visa (endereços sem `logradouro`/`numero`), sem custo
no cenário completo (dentro do ruído de medição).

---

## A mudança

`R/geocode.R` — `geocode_core()`:

1. Logo depois de `missing_cols` (linha ~225), nova variável `campos_nao_declarados <- names(missing_cols)`
   — os nomes dos campos que o usuário não passou em `campos_endereco`, direto da lista já computada para
   criar as colunas-fantasma. Nenhum dado é lido; é uma lista de até 6 elementos.
2. No laço de matching (linha ~423), o guarda passou de
   `if (all(key_cols %in% names(input_padrao)))` para
   `if (all(key_cols %in% names(input_padrao)) && !any(key_cols %in% campos_nao_declarados))`.

Isso substitui um design anterior (descartado antes de implementar) que escanearia `input_padrao` inteira
(`all(is.na(input_padrao[[cc]]))`) para descobrir campos vazios — custo O(n) por até 6 colunas, repetido a
cada chamada de `geocode()`. A versão implementada é O(1) em relação ao tamanho do input: `missing_cols` já
existe, calculada a partir da declaração do usuário (`campos_endereco`), não dos dados.

## Por que preserva o invariante de ordem do laço

`get_key_cols()` devolve exatamente o mesmo `key_cols` para `dn0k`/`da0k`/`pn0k`/`pa0k` (mesmo índice `k`) —
é a mesma família. Como `campos_nao_declarados` é fixo e global, a família inteira é pulada junto ou roda
junta; nunca pula `dn01` e deixa `da01` rodar sozinha (o que violaria a regra documentada no `CLAUDE.md`:
"Toda etapa `da*`/`pa*` precisa ser precedida pela `dn*`/`pn*` correspondente"). Isso sai da estrutura de
`get_key_cols()`, não precisou de proteção extra.

## Benchmark

Metodologia igual à dos testes anteriores desta semana: `geocodebr:::geocode_core()` direto (não
`geocode()`, que roda em `callr::r(package = TRUE)` e carregaria a versão instalada —
`[LEARN:testes]`), 20.028 endereços (`large_sample.parquet`), cache local do CNEFE (v0.4.1). Dois cenários:
**completo** (6 campos) e **só CEP** (`cep`, `bairro`→`localidade`, `município`, `uf` — sem `logradouro`/
`numero`). Script: `tests/tests_rafa/benchmark_empty_field_guard.R`.

| cenário | código | `geocode_core()` mediana (5 iter., n_cores=7) | `register_cnefe_table` (Rprof) |
|---|---|---|---|
| completo | antes | 4,45 s | 1,49 s / 37,5% |
| completo | depois | 4,58 s | 1,63 s / 38,7% |
| só CEP | antes | 3,28 s | 2,07 s / 62,2% |
| só CEP | **depois** | **0,78 s** | **0,26 s / 34,7%** |

**Cenário completo: sem diferença** (dentro do ruído — é no-op por construção, `campos_nao_declarados` fica
vazio). **Cenário só CEP: 3,28 s → 0,78 s, ganho de 4,2×.** Consistente com a faixa 3,3×–9× estimada em
`2026-08-23_analise-pacote-desempenho-manutencao.md` §1 (o extremo de 9× daquele relatório usava um
cenário ainda mais restrito, só `estado`+`município`+`cep`, sem `bairro`).

## Corretude

`identical()` bit-a-bit entre os `data.table`s de antes/depois, nos dois cenários (`n_cores = 1`):

```
=== full ===
identical(): TRUE

=== cep_only ===
identical(): TRUE
```

Sem nenhuma divergência de linha — diferente do teste do `TEMP VIEW` (24/08), que expôs 4 linhas afetadas
pelo `FIRST()` sem `ORDER BY` já conhecido. Essa mudança não altera ordem de scan nem toca nos caminhos
`da*`/`pa*` de forma que interaja com aquele bug: só remove chamadas a `match_fun()` que já devolveriam
zero linhas.

`tipo_resultado` no cenário só-CEP, antes e depois: `db01=1195, dc01=12680, dc02=5915, dm01=238` — idêntico,
confirma que as etapas com `logradouro`/`numero` na chave (`dn*`, `da*`, `pn*`, `pa*`, `dl*`, `pl*`) foram
puladas sem perder nenhum match que a versão anterior encontrava.

## Decisão

**Mantida.** Diff final em `R/geocode.R` (~13 linhas). Nenhum teste de regressão dedicado adicionado nesta
sessão — ver "Próximos passos".

## Próximos passos sugeridos

- Adicionar teste de regressão em `tests/testthat/test-geocode.R`: `local_mocked_bindings()` em
  `register_cnefe_table` contando chamadas, cenário completo (8 chamadas esperadas) vs. só-CEP (2 chamadas
  esperadas — só `municipio_cep_localidade` e `municipio`/`municipio_cep`, conforme `get_reference_table()`).
- Item #3 do relatório consolidado (`FIRST()` sem `ORDER BY`) continua a maior lacuna de corretude aberta —
  não é afetado por esta mudança, mas segue bloqueando comparação por igualdade exata em qualquer input que
  passe por `da*`/`pa*` com candidatos empatados.
- Item #5 (baixar só as tabelas necessárias) agora tem exatamente o sinal que precisa:
  `campos_nao_declarados` já diz quais campos-chave nunca vão gerar match; falta mapear isso para quais das
  8 tabelas de referência podem ser puladas no `download_cnefe()`.

## Referências

- `quality_reports/diagnoses/2026-08-24_geocode-eficiencia-consolidado.md` — item #1 na lista priorizada.
- `quality_reports/diagnoses/2026-08-23_analise-pacote-desempenho-manutencao.md` §1 — medição original (commit `a4b8036`).
- `tests/tests_rafa/benchmark_empty_field_guard.R` — script de benchmark.
