# `geocode()` em 43,9M — benchmark instrumentado e rodada de otimizações — 2026-09-19

**Plano:** `quality_reports/plans/lazy-bouncing-spark.md` · **Log:** `quality_reports/session_logs/2026-09-19_geocode-benchmark-43M.md`
**Patches e scripts:** `quality_reports/diagnoses/2026-09-19_patches/` (`p01.patch` … `p12.patch`, `cumulativo.patch`,
harness `prof_geocode.R`, `compare_results.R`, `bench_queue.sh`)

## Resultado em uma linha

`geocode()` em `df_full_data.parquet` (43.882.020 endereços, `n_cores` default = 16, 256 GB RAM):
**880 s → 465 s (−47 %)** e pico de memória do subprocesso **80 GB → 45 GB (−44 %)**, com output
**idêntico** (checksums de `lat`/`lon`/`desvio_metros`/`endereco_encontrado` iguais em todas as 16
corridas de 43,9M; `identical()` bit a bit no 1M com `n_cores = 1` em todos os modos). Doze
mudanças pequenas, nenhuma nova dependência, nenhuma alteração de comportamento documentado.

## 1. Como foi medido

- **Harness** (`prof_geocode.R`): espelha `geocode()` — um filho `callr` carrega o pacote
  **instalado** de uma biblioteca privada (`R CMD INSTALL -l`, um `lib_<patch>` por patch) e roda
  `geocode_core()`; dentro do filho, cada função interna é envolvida por um wrapper com timer,
  `ps::ps_memory_info()` e `duckdb_memory()`. O modo `geocode` chama a função exportada como um
  usuário (sem instrumentação por etapa; memória do filho por um poller externo a cada 1 s). Nenhum
  fonte do pacote é alterado para medir. Um `Rscript` por corrida; nada mais rodando na máquina.
- **Corretude:** cada patch em cópia isolada do pacote; `devtools::test()` verde em todas;
  `geocode()` no 1M (`df_sample_empates.parquet`, `n_cores = 1`) comparado por `identical()` com a
  referência do baseline — modo padrão em todos os patches; `resultado_completo = TRUE` em P6, P8,
  bundle de memória e cumulativo; `resolver_empates = FALSE` no bundle e cumulativo; P7 com matriz
  de tipos de colunas de input (factor, factor ordenado, Date, POSIXct em 3 fusos, difftime,
  integer64, lógico com NA, "" vs NA, UTF-8 acentuado) e com `h3_res`, `resultado_sf` e campo não
  declarado. No 43,9M: checksums + parquet do resultado salvo por corrida.
- **Ruído:** duas corridas do mesmo código variam até 20 % no total (primeira corrida da noite, a
  frio: 1112 s; quentes: 877/894/910 s) e mais ainda por etapa (Jaro em `pn02`: 57-130 s). Por
  isso a fila intercalou 4 baselines (início, meio, fim, e um em modo `geocode`), a referência é a
  **mediana dos quentes**, e a evidência primária de cada patch é o **Δ da etapa que ele toca**;
  diferenças de total abaixo de ~10 % são inconclusivas.

## 2. Mapa de custo do baseline (mediana dos 3 baselines quentes, modo core)

| Bloco | s | % |
|---|---:|---:|
| **Total (parede, do chamador)** | **894** | 100 |
| Transporte `callr` (input 43,9M×7 p/ o filho + resultado 6,9 GB de volta) | 244 | 27 |
| Padronização (`enderecobr::padronizar_enderecos`) | 118 | 13 |
| `dbWriteTable(input_padrao_db)` + schema | 20 | 2 |
| **Laço de matching** | **338** | 38 |
| ↳ Jaro (`calculate_string_dist`) — pn02 e pl02 = 80 % disso | 229 | 26 |
| ↳ queries `INSERT` — ponderadas `da01`/`da02` dominam | 72 | 8 |
| ↳ `register_cnefe_table` | 27 | 3 |
| ↳ `update_input_db` (DELETE) | 18 | 2 |
| Empates | 14 | 2 |
| `dbWriteTable(input_db)` | 19 | 2 |
| Merge (JOIN + ORDER BY + `dbGetQuery`) | 96 | 11 |

Memória: filho 80,6 GB de pico (no merge); DuckDB 50,2 GB, crescendo monotonicamente e sem
nunca liberar (nada era dropado); pai 9,1 GB. `temporary_storage_bytes = 0` (nada foi p/ disco).

(A primeira corrida, a frio, deu 1112 s com Jaro 337 s e merge 102 s — a seção 2 do plano tem esse
mapa; os números acima são os quentes, usados como referência dos deltas.)

## 3. Resultado por ação (43,9M)

Métrica-alvo = etapa que o patch toca, mediana dos baselines quentes → patch. Total e picos da
corrida do patch entre parênteses, contra mediana 894 s / 80,6 GB filho / 50,2 GB DuckDB.
Checksums do output idênticos ao baseline em **todas** as linhas.

| # | Ação (arquivo) | Métrica-alvo | Total | Pico filho | Pico DuckDB | Veredito |
|---|---|---|---:|---:|---:|---|
| **P1** | Jaro: pular linhas com `numero` preenchido em `pl01/pl02/pl03` (`string_dist.R`, 4 linhas) | Jaro **229 → 178 s (−22 %)**; `pl02` 140 → 55, `pl03` 30 → 22 | 820 | 80,1 | 50,2 | ✅ ganho; no-op provado (0 acertos perdidos) |
| P2 | Jaro: `SELECT DISTINCT` nos candidatos na chave usada (`string_dist.R`, 1 linha) | Jaro 229 → 239 s (+4 %); `pl02` 140 → 115 mas `pn01/pl01/pn03/pl03` +2-10 s cada | 1015¹ | 80,6 | 50,2 | ➖ neutro isolado; **subsumido pelo P8** |
| **P8** | Jaro: dedup do input por chave + `FIRST/MAX` no lugar de `RANK()` + join-back (`string_dist.R`, ~60 linhas; inclui P2) | Jaro **229 → 107 s (−53 %)**; `pl02` 140 → 23, `pn02` 57 → 28, `pl03` 30 → 7; **mas `pn01` 6 → 29, `pl01` 3 → 10** | 829 | 80,4 | 50,2 | ✅ maior ganho isolado; ver híbrido (§4) |
| **P5** | Padronizar por campo sobre `unique()` + `chmatch()` (`geocode.R`, `utils.R`) | Padronização **118 → 23 s (−80 %)**; números 20 → 0,2, municípios 15 → 0,05, logradouros 44 → 18 | 778 | 80,0 | 50,2 | ✅ ganho acima do estimado (65-80 s) |
| **P6** | `GROUP BY` estreito nas queries ponderadas, regex 1× por grupo (`match_weighted_cases*.R`) | INSERTs **72 → 57 s (−20 %)**; `da01` 21,6 → 7,6, `da02` 14,1 → 7,6 | 947¹ | 80,5 | 50,2 | ✅ ganho local claro; total mascarado por ruído |
| **P3** | `duckdb_register()` zero-cópia para `input_db` (`geocode.R`, 1 linha) | Escrita do `input_db` **19 → 3 s (−83 %)** | 893 | **76,2** | **45,9** | ✅ ganho + −4,4 GB |
| P4 | `DELETE` só dos ids da etapa corrente (`utils.R` + 4 `match_*.R`) | DELETE **18 → 12 s (−34 %)** | 1063¹ | 80,7 | 50,2 | ✅ ganho pequeno (−6 s; estimado −15) |
| **P9-12** | Bundle memória: `DROP` de tabelas após último uso + `input_padrao_db` após o laço + `output_db`/`ids_empatados`/`empates_classif` após `output_db2` (P9); `rm(input_padrao)` e `:= NULL` (P10); projeção de colunas em `register_cnefe_table` (P11); coluna morta fora do schema (P12) | Pico filho **80,6 → 46,8 GB (−42 %)**; DuckDB **50,2 → 29,7 GB**; após o laço 44 → 4,6 GB; drops custam 2,3 s; merge 96 → 72 s | 854 | **46,8** | **29,7** | ✅ ganho de memória grande; tempo neutro/positivo |
| **P7** | Resultado sai do filho como parquet (`COPY … TO`), pai lê com arrow (`geocode.R`, `utils.R`, `create_geocodebr_db.R`) — medido em modo `geocode` | Total **880 → 738 s (−16 %)** (transporte + `dbGetQuery`) | 738 | **71,6** | — | ✅ ganho grande; **pai 9 → 18 GB** (arrow materializa antes de converter) |
| **Cumulativo** (P1+P3-P12; P2 dentro do P8) — modo `geocode` | | **880 → 465 s (−47 %)** | **465** | **44,8** | 29,7 | ✅ |
| Cumulativo — modo core (por etapa) | Padronização 118 → 24 · laço 338 → 156 (Jaro 229 → 81, INSERTs 72 → 41, DELETE 18 → 8) · `input_db` 19 → 3 · merge 96 → 78 | 569² | 46,9 | 29,7 | |

¹ Total inflado por ruído em etapas que o patch não toca (ex.: P4 com Jaro 317 s e register 54 s
contra 207-250 / 27-29 nos baselines). ² Modo core mantém o `dbGetQuery` + RDS (P7 só atua via
`geocode()`), daí 569 s contra 465 s no modo real.

**Sugestões dos agentes refutadas antes de testar** (com micro-medição): `SET preserve_insertion_order = false`
(CTAS do parquet 50 % mais lento); pré-filtro do Jaro por razão de comprimento (bound provado, mas
o predicado custa mais que o `jaro_similarity`); `arg_min` por coluna no lugar de `FIRST(... ORDER BY)`
(2× mais lento e **não idêntico** — pula NULL); compactação periódica de `input_padrao_db`; pular o
filtro de municípios em `register_cnefe_table` (é grátis); `dbGetQueryArrow` (não robusto).
Não testados por prioridade (candidatos para uma próxima rodada): input cruzando como parquet
(B4, −40-60 s estimados), só colunas novas de volta + `cbind` no pai (B2, decisão do mantenedor),
empates sem cópia integral (E3b, ~−8 s / −5 GB).

## 4. Híbrido para o Jaro (`cum2`)

P8 perde nas etapas cuja chave de lookup já inclui `cep` **e** `localidade` (`pn01`/`pl01`): ali
quase não há repetição no input e o join-back por 4 colunas de texto custa mais que o Jaro linha a
linha (`pn01` 6 → 29 s). No cumulativo, `pn01` virou a maior etapa de Jaro (26 s). `cum2` =
cumulativo + escolha por etapa em `calculate_string_dist()` (`usa_dedup`): forma direta por
`tempidgeocodebr` (com o filtro do P1) quando a chave tem `cep` e `localidade`, forma com dedup nas
demais.

**Resultado (43,9M):** `identical()` TRUE no 1M nos 4 modos. Nas únicas etapas cujo código muda,
**`pn01` 25,8 → 4,8 s e `pl01` 5,2 → 4,2 s** (−22 s, de volta ao custo do baseline). As duas
corridas de `cum2` caíram em fases lentas da máquina — modo `geocode` 554 s (cum: 465 s) e modo core
685 s (cum: 569 s) — mas o atraso está todo em etapas **idênticas** entre as duas variantes
(`cum2` core: register 36 s, merge 121 s, INSERTs 60 s, empates 22 s contra 25/78/41/15 no `cum`
core), o que é a assinatura do ruído já visto em `p04` e `p06`. Com Δ por etapa como critério, o
híbrido é ~22 s mais rápido que o cumulativo simples e é a variante aplicada à working tree
(`cum2_hibrido_jaro.patch`). Pico do filho no modo `geocode`: 38,9 GB (cum: 44,8).

## 5. Achados colaterais

- **enderecobr:** os construtores de aviso/erro olham a pilha por deslocamento fixo
  (`sys.call(-15)`/`sys.call(-10)`); chamar `padronizar_*` de campo diretamente quebra com
  "cannot coerce type 'closure'" e transforma um aviso benigno em erro fatal. `padronizar_dedup()`
  contorna chamando `padronizar_enderecos()` sobre uma tabela de 1 coluna com os valores únicos.
  Vale reportar upstream (e propor o dedup interno lá, item D6 do agente).
- **Parquet e tipos:** `difftime` vira INTERVAL → FIXED_SIZE_BINARY → `blob` no arrow (e quebra
  `resultado_sf`); `factor` volta character; `POSIXct` perde `tzone` (o driver antigo rotulava
  sempre "UTC"). Tudo restaurado em `restaura_classes_input()`. `integer64` já era lido como
  DOUBLE no caminho antigo — bug pré-existente, preservado.
- **Ordem intra-id em `resolver_empates = FALSE`:** o cumulativo permuta a ordem das linhas
  duplicadas de um mesmo id (P6 muda a ordem de emissão das queries ponderadas); idêntico após
  ordenação canônica; nunca foi contratual (já documentado em 26/08).
- **Variância do DuckDB:** a mesma query (`pn02`) oscilou 57-130 s entre corridas de código
  idêntico, sem outra carga na máquina. Qualquer trabalho futuro precisa de baselines intercalados.

## 6. Estado da working tree

O cumulativo aprovado foi aplicado a `r-package/` (ver §4 para qual variante) e `devtools::test()`
rodado lá. **Nada foi commitado.** `NEWS.md` não foi tocado (decisão do mantenedor).
