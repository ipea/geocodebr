# Plano — `callr` condicional ao heap do processo em `geocode()`

**Status:** IMPLEMENTADO em 2026-09-27, sem commit (v3 aprovada). Desvio: `usar_callr()` ficou em `R/geocode.R`, ao lado de `caminho_pacote_dev()`, e não em `R/utils.R`, que tinha trabalho alheio não commitado
**Data:** 2026-09-24
**Base:** `quality_reports/diagnoses/2026-09-24_geocode-callr-deterioracao-heap.md`

## Objetivo

Rodar `geocode_core()` em processo sempre que não houver risco de deterioração: Linux, macOS, e Windows quando
o exe que hospeda a sessão declara Segment Heap (Rterm, Rgui, Rscript). O `callr` fica só no Windows com heap
legado (RStudio `rsession.exe`, hosts embutidos). Ganho medido por chamada: ~3,3 s no Windows, ~2 s no Linux e
~2–3 s no macOS, todos planos em processo (adendos do diagnóstico de 24/09).

**Regra de desenho:** mexer o mínimo. Só muda *quem chama* o `geocode_core()`; o transporte via parquet e o
pós-processamento são os mesmos nos dois ramos, então o output é idêntico por construção.

## Mudanças (~45–55 linhas no total)

1. **`R/utils.R`: um helper só, com a política inteira** (~10 linhas)
   ```r
   # TRUE quando geocode() precisa rodar o motor num subprocesso callr: so no
   # Windows com o heap NT legado, onde o DuckDB multithread degrada a cada
   # chamada no mesmo processo. O heap e decidido pelo manifesto do exe que
   # hospeda a sessao (Rterm/Rgui/Rscript declaram Segment Heap; o rsession.exe
   # do RStudio nao). Linux/macOS: sem o problema (medido). Na duvida: callr. Ver
   # quality_reports/diagnoses/2026-09-24_geocode-callr-deterioracao-heap.md
   usar_callr <- function() {
     if (.Platform$OS.type != "windows") return(FALSE)
     exe <- tryCatch(ps::ps_exe(), error = function(e) "")
     if (!isTRUE(file.exists(exe))) return(TRUE)
     bytes <- readBin(exe, what = "raw", n = file.size(exe))
     length(grepRaw("SegmentHeap</heapType>", bytes, fixed = TRUE)) == 0
   }
   ```
   Um helper só, com a decisão completa, dá um ponto único de mock que força qualquer um dos ramos em
   qualquer SO.

2. **`R/geocode.R` (~linha 111): envolver a chamada existente** (~18 linhas; o bloco `callr::r()` fica
   intacto)
   ```r
   if (!usar_callr()) {
     # em processo: sem heap legado nao ha deterioracao, e poupa 2-3 s/chamada.
     # copy(): o motor faz setDT()/:= e alteraria o objeto do usuario
     resumo_filho <- geocode_core(
       enderecos = data.table::copy(enderecos),
       campos_endereco = campos_endereco,
       resultado_completo = resultado_completo,
       resolver_empates = resolver_empates,
       resultado_sf = resultado_sf,
       h3_res = h3_res,
       padronizar_enderecos = padronizar_enderecos,
       verboso = verboso,
       cache = cache,
       n_cores = n_cores,
       arquivo_saida = arquivo_saida
     )
   } else {
     resumo_filho <- callr::r(...)   # exatamente como hoje
   }
   ```
   - A chamada fica explícita. **Não** usar `do.call()`, que embutiria o data.frame inteiro na call; um erro
     que faça deparse dela travaria com 43 M de linhas.
   - `restaura_classes_input(output_df, enderecos)` continua recebendo o original intacto.
   - Reescrever o comentário de `geocode.R:89-95`.

3. **`DESCRIPTION`:** `ps` em Imports (+1 linha; já é instalado via callr → processx → ps).

4. **`NEWS.md`** (pt-BR, ~3 linhas): `geocode()` passa a rodar na própria sessão no Linux, no macOS e no
   Windows fora do RStudio (Rterm/Rgui/Rscript), 2–3 s mais rápido por chamada; mensagens e avisos passam a ser
   capturáveis por `suppressMessages()`/`suppressWarnings()`. Só o RStudio no Windows segue com subprocesso.

5. **Docs internas:** `CLAUDE.md` (4 trechos que dizem "roda dentro de `callr::r()`", incluindo a tabela das
   três funções); `MEMORY.md` (uma linha na entrada do custo de `load_all`: sob Rterm ele some).

6. **Python:** nenhuma mudança. O resultado não muda, então a paridade não é afetada.

### Descartado na revisão

| Item da v1 | Por quê |
|---|---|
| Dois helpers (`tem_segment_heap()` + `precisa_subprocesso()`) | Um só, `usar_callr()`, com a política inteira: é também o único ponto de mock (v3) |
| Checagem do build do Windows (< 19041) | Builds sem suporte desde 2021–22; 6 linhas de peso morto |
| ~~Manter `callr` no Linux/macOS~~ (v2) | Revertido na v3: medido em 25/09, os dois são planos em processo (Linux 5,4–5,6 s; macOS 20 rodadas sem tendência). Custo aceito: a CI só passa pelo ramo `callr` via mock |
| Pular o parquet (`arquivo_saida = NULL`) | Muda tipos (factor/ENUM, tzone, difftime, int64) entre os ramos: divergência do tipo que a regra de paridade proíbe |
| `Sys.getenv("RSTUDIO")` no lugar do `ps` | Erra com Positron, reticulate/`python.exe` e R embutido; e herda `RSTUDIO=1` em processos filhos |
| Teste "`tem_segment_heap()` é TRUE sob Rterm" | Testa o manifesto do R, não o pacote |

## Testes (`tests/testthat/test-geocode.R`)

1. **Teste existente (linha 254, "subprocesso do callr enxerga as funcoes internas"):** acrescentar
   `local_mocked_bindings(usar_callr = function() TRUE)`. Sem isso, sob Rterm ele deixaria de passar
   pelo `callr` sem que ninguém notasse.
2. **Um teste novo**, cobrindo os dois ramos e a não-mutação:
   ```r
   test_that("geocode() em processo = via callr, sem alterar o input", {
     entrada <- input_df[1:50, ]
     antes <- data.table::copy(entrada)   # copia PROFUNDA; `antes <- entrada` seria vacuo
     local_mocked_bindings(usar_callr = function() FALSE)
     em_processo <- tester(enderecos = entrada, resolver_empates = TRUE)
     expect_identical(entrada, antes)
     local_mocked_bindings(usar_callr = function() TRUE)
     via_callr <- tester(enderecos = entrada, resolver_empates = TRUE)
     expect_identical(em_processo, via_callr)
   })
   ```
   O `tester()` já fixa `n_cores = 1`, então o `expect_identical` não sofre com o ruído de ~1e-14 do desempate.

## Efeitos colaterais aceitos

- No ramo em processo, os erros voltam sem o invólucro `callr_status_error`; nenhum `expect_error()` usa classe
  e nenhum snapshot envolve `geocode()`.
- O `.duckdb` temporário (`create_geocodebr_db.R:15`) fica no tempdir da sessão, um por chamada. Hoje ele some
  com o tempdir do filho. `geocode_reverso()`/`busca_por_cep()` já deixam o arquivo do mesmo jeito; limpar isso
  é opcional e fica fora do escopo.
- Memória: o pico total é o mesmo do `callr` (input + cópia + DuckDB), menos a serialização RDS. Mas a memória
  que o DuckDB usou fica retida na sessão depois da chamada; com o `callr` ela era devolvida ao fim do filho.
  Medido com `large_sample`: ~1,9 GB no macOS (platô, não cresce), ~360 MB no Linux e ~390 MB no Windows.

## Verificação

1. Benchmark de 4 braços (`quality_reports/diagnoses/2026-09-24_bench_callr.R`, no modo `callr`, que chama
   `geocode()`): sob Rterm, ~8 s e plano; sob Rterm-NT, pelo `callr`, ~12 s e plano.
2. `devtools::test()` e `/r-package-check r-package` (sem erros nem warnings).
3. `pytest -m r_parity` pelo CI.
