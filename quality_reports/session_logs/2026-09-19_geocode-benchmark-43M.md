# Log de sessão — 2026-09-19 — benchmark 43,9M + rodada de eficiência de `geocode()`

**Plano:** `quality_reports/plans/lazy-bouncing-spark.md` (aprovado 19/09)
**Objetivo:** medir `geocode()` em `df_full_data.parquet` (43.882.020 linhas) com instrumentação por
etapa, dentro do subprocesso do `callr`; 5 agentes independentes propõem melhorias; testar cada uma
com o mesmo benchmark; tabela final com Δ tempo e Δ memória.

## Decisões e contexto

- **Harness** (`prof_geocode.R`, scratchpad da sessão): espelha `geocode()` — filho `callr` carrega o
  pacote INSTALADO de uma biblioteca privada (`R CMD INSTALL -l`) e roda `geocode_core()`; dentro do
  filho, cada função interna é envolvida por um wrapper com timer + `ps::ps_memory_info()` +
  `duckdb_memory()`. Nenhum fonte do pacote é alterado para medir. Modo `geocode` chama a função
  exportada de verdade (sem instrumentação por etapa), com um poller externo de memória.
- **Baseline 43,9M (`base43M_r1`, 18/09 23:55):** 1112 s total; 246 s de transporte `callr`
  (nunca medido antes); Jaro 337 s (pn02 130, pl02 133); padronização 126 s; merge 102 s; pico de
  memória do filho 82 GB, DuckDB 51 GB sem nunca liberar.
- **Achado novo que redireciona a lista:** o custo do Jaro está em pn02/pl02 (chave sem localidade →
  10× mais pares) e não distribuído; e o transporte entre processos é o 2º maior bloco.
- **Sugestões refutadas pelos agentes antes de testar:** `preserve_insertion_order = false` (CTAS
  50 % mais lento), pré-filtro por comprimento no Jaro (predicado custa mais que o Jaro), `arg_min`
  por coluna (não idêntico: pula NULL), compactação de `input_padrao_db`, pular filtro de municípios.
- **Modelo:** o pedido pedia trocar para Opus na fase de testes; não é possível trocar o próprio
  modelo — os 4 patches médios (P5-P8) foram delegados a subagentes Opus em cópias isoladas
  (`scratchpad/pkg_p05..p08`); os pequenos (P1-P4, P9-P12) foram escritos diretamente.
- **Isolamento:** cada patch vive numa cópia de `r-package/` no scratchpad, instalada em `lib_<id>`;
  a working tree do repo não foi tocada até a fase cumulativa.
- **Corretude:** referência 1M (`df_sample_empates.parquet`, `n_cores = 1`) gerada com o baseline;
  cada patch precisa de `identical()` contra ela. Para 43,9M, checksums (soma de lat/lon/desvio,
  NAs, nchar de `endereco_encontrado`) + parquet salvo para comparação exata se preciso.

## Andamento

- 08:47 referência 1M gerada (120,6 s de parede; 112 s no filho).
- 08:57 fila de checagem 1M dos patches pequenos (p01-p04, p09-p12, bundle `mem`) iniciada.
- Agentes Opus P5 (padronização dedup), P6 (GROUP BY estreito), P7 (parquet de saída), P8 (dedup
  do input no Jaro) em andamento.
- 09:22-09:47 todos os 12 patches passaram: `devtools::test()` verde em cada cópia; `identical()` no 1M
  (`n_cores = 1`) contra a referência em todos; P6/P8 também com `resultado_completo = TRUE`; P7 em
  modo `geocode` com matriz de tipos (factor, Date, POSIXct, difftime, integer64, lógico com NA...);
  bundle de memória também com `resolver_empates = FALSE` e `resultado_completo = TRUE`.
- **Achado do P5 (Opus):** os construtores de aviso/erro do enderecobr olham a pilha por deslocamento
  fixo (`sys.call(-15)` / `sys.call(-10)`); chamar `padronizar_logradouros()` etc. direto quebra
  ("cannot coerce type 'closure'") e transforma um aviso benigno em erro fatal. O helper
  `padronizar_dedup()` por isso chama `padronizar_enderecos()` sobre uma tabela de 1 coluna com os
  valores únicos.
- **Achado do P7 (Opus):** difftime vira INTERVAL → FIXED_SIZE_BINARY no parquet (blob no arrow);
  resolvido com `epoch()` no SELECT + `as.difftime()` no pai. POSIXct sempre volta com `tzone = "UTC"`
  no caminho antigo (driver), replicado.
- 09:35 cumulativo montado via git (branches por patch, merge sequencial, arquivos normalizados p/ LF
  porque os agentes reescreveram alguns com LF e o repo usa CRLF). Conflitos: P1×P8 (filtro
  `numero IS NULL` inserido nas duas cláusulas do novo SQL do P8) e P5×P10 (`:= NULL` aplicado dentro
  do ramo FALSE reestruturado pelo P5). P2 é subsumido pelo P8. 288 testes verdes; 1M `identical()`
  em modo core, `geocode`, completo; em `resolver_empates = FALSE` só muda a ordem intra-id das
  linhas duplicadas (idêntico após ordenação canônica — não contratual, já documentado). 1M: 120,6 s
  → 76,1 s.
- 09:51 fila de 43,9M lançada (processo destacado, pid 8732): base r2 · p01 · p02 · p08 · p05 · p06 ·
  base r3 · p03 · p04 · mem · base (modo geocode) · p07 (geocode) · cum (geocode) · cum (core) ·
  base r4. Um tropeço antes: o `TaskStop` da primeira fila matou só o Rscript, o bash sobreviveu e
  pulou para o item seguinte — duas filas concorrentes por ~2 min; tudo morto e relançado limpo.
- Patches e scripts salvos em `quality_reports/diagnoses/2026-09-19_patches/`.
- 09:51-14:08 fila de 43,9M (15 corridas) concluída; 14:16-14:43 híbrido `cum2` verificado (1M, 4
  modos `identical()`) e medido (modo `geocode` + core).
- **Resultado:** `geocode()` 880 → 465 s (−47 %) em modo real; pico do filho 80 → 45 GB (39 GB no
  híbrido); DuckDB 50 → 30 GB; checksums idênticos em todas as 18 corridas de 43,9M. Tabela por ação
  em `quality_reports/diagnoses/2026-09-19_geocode-benchmark-43M.md`.
- **Ruído medido:** baselines quentes 877/894/910 s (frio 1112 s); `p04`, `p06` e as duas corridas do
  `cum2` caíram em fases lentas com todas as etapas inflacionadas → Δ por etapa como evidência
  primária. P2 isolado é neutro (subsumido pelo P8).
- **Decisão:** aplicada à working tree a variante híbrida (`cum2`: P8 com forma direta em
  `pn01`/`pl01`, −22 s locais). `devtools::document()` + `devtools::test()` rodados na working tree;
  snapshots restaurados. **Nada commitado.** `r-package/tests/tests_rafa/test_rafa.R` aparece
  modificado no `git status` — não foi tocado nesta sessão (edição paralela do usuário).
- Memória entre sessões atualizada (`geocodebr_perf_initiative.md`); 8 entradas `[LEARN]` no
  `MEMORY.md` do repo.
