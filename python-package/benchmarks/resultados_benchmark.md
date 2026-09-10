# Benchmark — port Python, sample CadÚnico 10M

Protocolo: rodar antes e depois de cada alteração (`--label`) e comparar tempos por fase.
Sample: `data/sample_cad_unico.parquet` · args fixos: `resolver_empates=True`, `cache=True`, `n_cores=None` (24 threads).
`fechamento_conexao` = tempo de `con.close()` (marco "Conexão fechada" no `finally`); `-1` = marco ausente.

---

## Comparação: baseline vs patch_merge vs patch_heap (2026-09-02)

Cada coluna é cumulativa: `patch_merge` = otimização do merge (`COALESCE` na projeção
em vez de UPDATE + sem re-sort com `EXCLUDE`; `utils.py` + `geocode.py`).
`patch_heap` = `patch_merge` **+ interpretador com Segment Heap** (`python-sh.exe`,
cópia do CPython com manifest patcheado via `patch_segment_heap.py` da reprodução de
[duckdb/duckdb#24027](https://github.com/duckdb/duckdb/issues/24027) — heap NT legacy
serializa a alocação multithread do DuckDB no Windows; o `Rscript.exe` já opta pelo
Segment Heap, o `python.exe` não).

| fase | baseline | patch_merge | patch_heap | ganho vs baseline |
|---|---|---|---|---|
| cnefe | 0:05 | 0:01 | 0:01 | — |
| padronizacao | 0:54 | 0:44 | 0:54 | — (polars, sem duckdb) |
| matching | 5:05 | 4:47 | **1:53** | 2.7× |
| **empates** | 1:51 | 1:26 | **0:05** | **~21×** |
| precisao | 0:07 | 0:07 | 0:00 | — |
| merge | 0:41 | 0:21 | **0:04** | ~10× |
| materializacao | 0:07 | 0:07 | 0:05 | 1.4× |
| **fechamento_conexao** | **2:56** | 2:18 | **0:05** | **~35×** |
| pos_finalizado | 0:01 | 0:01 | 0:01 | = |
| **TOTAL (wall)** | **11:47** | **9:52** | **3:08** | **3.75×** |

Notas:
- Resultado idêntico nas três versões: 9.999.355/10.000.000 encontradas.
- **heap resolve os dois mistérios abertos**: (1) a inflação ~10× dos empates em dados
  reais vs sintético era a contenção do heap amplificada pelo volume de strings reais
  com 24 threads (escala negativa: legacy fica *pior* com mais threads); (2) o
  `con.close()` de ~3 min eram os frees massivos das 24 threads na mesma fila do heap —
  com SegmentHeap cai para segundos.
- Probes pareados (workload canônico da issue, 8M×6 joins): threads=8 → 23.8s legacy
  vs 8.9-9.7s SegmentHeap (~2.6×); threads=24 → **32s legacy vs 7-7.7s (~4.5×)**.
  Harness de empates 48M sintético: 98.7s → 25.0s (3.9×); s4/s5 (CTAS dos empates)
  caem 4.8×.
- `patch_merge` continua válido e complementar: reduz o trabalho de sort/materialização
  independente do heap (0:41 → 0:21 no legacy; os 0:04 finais combinam ambos).
- Extrapolação p/ 43M (rc=False): ~71 min observados → ~20-25 min esperados com
  `patch_merge` + SegmentHeap — paridade com a referência do R (17–18,7 min no
  `benchmark_reg_adm.R`, que sempre rodou no heap rápido do `Rscript.exe`).
- Como usar: rodar com o interpretador patcheado (`python-sh.exe`, criado ao lado do
  CPython do uv com `patch_segment_heap.py` — não altera o `python.exe` original).
  Releases novas do DuckDB **não** resolvem o lado Python (manifest pertence ao exe
  hospedeiro; o fix do duckdb#24036 é só do CLI). Mitigação sem patch: `n_cores≈4`.

---

## Probe `__COMPAT_LAYER=SEGMENTHEAP`: sem efeito (2026-09-08)

Teste da estratégia zero-custo do
[plano de ação](../../quality_reports/plans/2026-09-08_python_deterioracao-e-nivel-heap-windows.md)
(Fase 0): ativar o Segment Heap no processo filho via variável de ambiente
`__COMPAT_LAYER=SEGMENTHEAP` — sem criar arquivo algum no diretório do interpretador.
Harness: `verifica_segment_heap_compat.py` (workload canônico da issue, 8M × 6 joins,
rodadas NT/SH intercaladas, 3 repetições por config; CPython 3.13.7, duckdb 1.5.3,
Windows Server 2022).

| threads | NT (mediana) | SH via layer (mediana) | gap | referência do exe patcheado |
|---|---|---|---|---|
| 8 | 37,19 s | 32,52 s | 1,14× | ~8,9–9,7 s |
| 24 | 38,85 s | 33,60 s | 1,16× | ~7–7,7 s |

- **Veredito: sem efeito** (critério do plano: gap ≥ 2×). Ambos os braços ficam no
  patamar legacy, com a assinatura de sempre (joins cada vez mais lentos, ~1 s → ~11 s;
  mais threads não ajuda). Startup com e sem layer indistinguível (~2,1–2,2 s).
- **O shim é aplicado ao heap default, mas não muda o wall.** Com o layer no env,
  `HeapQueryInformation(HeapCompatibilityInformation)` sobre o heap default retorna
  2 (Segment Heap) — ou seja, a env não é ignorada. Hipótese mecânica mais consistente:
  o shim não alcança o heap criado pelo UCRT no startup (`HeapCreate`), por onde passam
  as alocações do duckdb (`_malloc_base` → `HeapAlloc(_crtheap)`); o opt-in via
  manifest (E4) é process-wide e por isso funciona.
- **Consequência para o plano**: estratégia `__COMPAT_LAYER` descartada; a primária
  passa a ser o exe cópia com manifest patcheado (`python-geocodebr-sh.exe`, técnica
  E4), com fallback NT puro + `n_cores` guardado.

---

## Probe IPC do subprocesso: Arrow (em lotes) × pickle (2026-09-09)

Teste da **Fase 0b** do [plano de ação](../../quality_reports/plans/2026-09-08_python_deterioracao-e-nivel-heap-windows.md):
antes de o desenho do isolamento assumir um mecanismo de transferência pai→filho→pai,
medir o custo de ida e volta da tabela de entrada + do resultado. Executado **sem** o
patch de Segment Heap (`python.exe` base, heap NT legacy — o default da maioria; o banner
do harness registra `SegmentHeap=False` para auditoria). Harness: `verifica_arrow_ipc.py`,
self-contained: dados sintéticos CadÚnico-like (8 colunas, 4 de strings), resultado =
input + 5 colunas (`resultado_completo=False`); o filho espelha os imports do worker real
(duckdb+polars+pandas+pyarrow) e **apaga o input do disco após a leitura** (desenho da
arquitetura). Rodadas por formato acumulam em `resultados_probe_ipc.csv`.

Cenário: Windows Server 2022, 24 núcleos, CPython 3.10.20 (venv em compartilhamento UNC),
polars 1.44.0, pandas 2.3.3, pyarrow 24.0.0, duckdb 1.5.3; staging em SSD local (`C:`).

`TOTAL` = escrever input (pai) + subprocesso inteiro (startup + ler + simular resultado +
escrever resultado) + ler resultado (pai). Medianas de 2–3 rodadas em 10M/100k/1M; 43M
com 1–2 rodadas (indicativo; servidor compartilhado):

| linhas | formato | esc_in | ler_in | esc_res | ler_res | startup | TOTAL | MB (in/out) |
|---|---|---|---|---|---|---|---|---|
| 100k | arrow_ipc | 0,0 s | 0,0 s | 0,0 s | 0,0 s | 5,3 s | 5,3 s | 12/17 |
| 1M | arrow_ipc | 0,1 s | 0,2 s | 0,2 s | 0,1 s | 5,9 s | 6,5 s | 123/166 |
| 10M | arrow_ipc | 0,6 s | 2,0 s | 7,7 s | 1,2 s | 5,7 s | 17,5 s | 1233/1660 |
| 10M | arrow_ipc_lotes | 1,5 s | 3,6 s | 2,0 s | 3,3 s | 8,6 s | **19,1 s** | 1070/1660 |
| 10M | pickle_pandas | 6,3 s | 6,0 s | 7,5 s | 0,9 s | 5,6 s | 26,5 s | 517/1660 |
| 10M | pickle_polars | 11,2 s | 2,7 s | 7,8 s | 0,9 s | 6,0 s | 28,7 s | 1233/1660 |
| 43M | arrow_ipc (batch gigante) | 6,2 s | **60,5 s** | **64,8 s** | 6,2 s | 8,8 s | 147,9 s | 5302/7139 |
| 43M | arrow_ipc_lotes | 5,1 s | 7,0 s | 7,7 s | 5,5 s | 9,9 s | **36,4 s** | 4602/7139 |
| 43M | pickle_pandas | 29,4 s | 34,1 s | 44,0 s | 4,4 s | 19,9 s | 132,6 s | 2188/7139 |

Notas:

- `arrow_ipc_lotes` escreve em lotes de 1M de linhas (`max_chunksize=1_000_000`) em vez
  de um record batch único; as pernas de escrita incluem a conversão `to_arrow` — no
  worker real o resultado já nasce em lotes do próprio DuckDB (`fetch_record_batch`),
  que é mais barato que o desenho simulado aqui.
- `arrow_ipc_lotes` 10M rod. 1 teve surto de startup (69,6 s — servidor compartilhado);
  a linha acima é a rodada limpa. Demais células de 10M são medianas estáveis entre
  rodadas.
- Arrow sem compressão gera arquivo maior que o pickle de pandas (2,4× no input a 10M;
  5,3 GB vs 2,2 GB a 43M) — irrelevante em SSD local; compressão (lz4) é o escape se o
  disco for restrição.
- Startup (~5–10 s) inclui importar as libs do venv em compartilhamento UNC; instalação
  local tende ao patamar de ~2 s medido no probe da Fase 0 (`probe_compat_layer.log`).

Leituras:

1. **Arrow IPC em lotes vence em todas as escalas** e cresce plano: TOTAL ≈ 19 s a 10M
   (~10% do alvo de 3:08 do modo isolado+heap, sendo ~10 s só de I/O) e **36,4 s a 43M**
   (~5,5% dos ~11 min do 43M+heap). Dentro do orçamento do plano.
2. **Record batch gigante é um penhasco**: o mesmo Arrow num batch único de >4 GB fica
   4× mais lento a 43M (ler 5,3 GB: 60,5 s vs 7,0 s em lotes). O worker **deve** escrever
   IPC em lotes de ~1M de linhas, sem exceção.
3. **pickle perde sempre** e por três motivos somados: wall maior nas escalas do plano
   (26,5–28,7 s a 10M ≈ 14%, acima do orçamento; 132,6 s a 43M), superfície de execução
   arbitrária (`unpickle` roda código) e acoplamento de versão/ABI entre pai e filho.
   Nota honesta: a 10M/43M o pickle de pandas não é o desastre que a revisão do plano
   pressupunha — é linear — mas continua estritamente inferior; o que descarta mesmo o
   pickle é somar wall + segurança + acoplamento, com Arrow igualmente simples.
4. **Input por caminho de arquivo não paga nada**: atravessa como string (sem staging);
   o caso real de 43M (`parquet`) custa só startup + resultado (~15–20 s estimado).
5. **Startup domina chamadas pequenas** (~5–6 s medidos aqui) — reforça o isolamento
   Windows-only e o escape `GEOCODEBR_ISOLAR=0` para loops de chamadas pequenas.
6. **Fato operacional**: o `%TEMP%` padrão da máquina de referência (D:, 2,1 GB livres)
   **falhou com "no space left"** no staging de 10M — o handoff pede ~1,2–1,7 GB por
   chamada a 10M e ~5–7 GB a 43M. O worker precisa tratar ENOSPC com erro claro, e o
   README deve declarar o requisito de disco.

**Veredito**: protocolo do worker confirmado — `args.json` (controle) + `input.arrow` /
`result.arrow` (dados, IPC em lotes) + `result.json` (status/erro tipado). Pickle
eliminado da fronteira.

---

## baseline — 2026-09-02 10:17 (sha `6c1a090+dirty`)

- args: `resultado_completo=False`, `resolver_empates=True`, `n_cores=None`
- início: 10:05:46 · fim (return do geocode): 10:17:32
- linhas: 10,000,000 · encontradas: 9,999,355 (100.0%)

| fase | tempo |
|---|---|
| cnefe | 0:05 |
| padronizacao | 0:54 |
| matching | 5:05 |
| empates | 1:51 |
| precisao | 0:07 |
| merge | 0:41 |
| materializacao | 0:07 |
| fechamento_conexao | 2:56 |
| pos_finalizado | 0:01 |
| **TOTAL (wall)** | **11:47** |

```
10:05:51: Utilizando dados do CNEFE armazenados localmente
10:05:51: Padronizando enderecos de entrada
10:06:45: Geolocalizando enderecos
10:11:50: Preparando resultados
Foram encontrados e resolvidos 665832 casos de empate.
10:13:41: Adicionando coluna de precisão
10:13:48: Juntando com colunas do input
10:14:29: Materializando tabela final em arrow
10:14:36: Finalizado
10:17:32: Conexão fechada
```

---

## patch_merge — 2026-09-02 10:33 (sha `6c1a090+dirty`)

- args: `resultado_completo=False`, `resolver_empates=True`, `n_cores=None`
- início: 10:23:14 · fim (return do geocode): 10:33:06
- linhas: 10,000,000 · encontradas: 9,999,355 (100.0%)

| fase | tempo |
|---|---|
| cnefe | 0:01 |
| padronizacao | 0:44 |
| matching | 4:47 |
| empates | 1:26 |
| precisao | 0:07 |
| merge | 0:21 |
| materializacao | 0:07 |
| fechamento_conexao | 2:18 |
| pos_finalizado | 0:01 |
| **TOTAL (wall)** | **9:52** |

```
10:23:16: Utilizando dados do CNEFE armazenados localmente
10:23:16: Padronizando enderecos de entrada
10:24:00: Geolocalizando enderecos
10:28:47: Preparando resultados
Foram encontrados e resolvidos 665832 casos de empate.
10:30:13: Adicionando coluna de precisão
10:30:20: Juntando com colunas do input
10:30:41: Materializando tabela final em arrow
10:30:48: Finalizado
10:33:06: Conexão fechada
```

---

## patch_heap — 2026-09-02 15:43 (sha `56254d4+dirty`)

- args: `resultado_completo=False`, `resolver_empates=True`, `n_cores=None`
- início: 15:40:48 · fim (return do geocode): 15:43:56
- linhas: 10,000,000 · encontradas: 9,999,355 (100.0%)

| fase | tempo |
|---|---|
| cnefe | 0:01 |
| padronizacao | 0:54 |
| matching | 1:53 |
| empates | 0:05 |
| precisao | 0:00 |
| merge | 0:04 |
| materializacao | 0:05 |
| fechamento_conexao | 0:05 |
| pos_finalizado | 0:01 |
| **TOTAL (wall)** | **3:08** |

```
15:40:50: Utilizando dados do CNEFE armazenados localmente
15:40:50: Padronizando enderecos de entrada
15:41:44: Geolocalizando enderecos
15:43:37: Preparando resultados
Foram encontrados e resolvidos 665832 casos de empate.
15:43:42: Adicionando coluna de precisão
15:43:42: Juntando com colunas do input
15:43:46: Materializando tabela final em arrow
15:43:51: Finalizado
15:43:56: Conexão fechada
```

---


---

## Sweep tempo x threads no heap legacy: minimo em 4 threads (2026-09-10)

Teste da premissa do cap de `n_cores` do `geocode()` (`N_CORES_HEAP_LEGACY = 4`).
Harness: `verifica_sweep_threads.py` — workload canonico do duckdb#24027 (8M x 12
strings + 2M dicionario + 6 LEFT JOINs re-materializando + close), filho fresco por
medicao (heap novo a cada ponto, sem contaminacao da deterioracao acumulada), 3
rodadas intercaladas com ordem alternada, interpretador da venv (heap legacy, duckdb
1.5.3). Maquina de referencia idle.

| threads | joins (s) | close (s) | total (s) | vs minimo |
|---|---|---|---|---|
| 1  | 49,07 | 0,43 | 49,50 | +162% |
| 2  | 27,10 | 0,53 | 27,63 | +46% |
| 3  | 20,38 | 0,55 | 20,93 | +11% |
| **4**  | **18,25** | **0,63** | **18,88** | **minimo** |
| 6  | 18,95 | 0,74 | 19,69 | +4% |
| 8  | 19,88 | 0,85 | 20,73 | +10% |
| 12 | 22,87 | 0,94 | 23,81 | +26% |
| 16 | 22,38 | 1,04 | 23,42 | +24% |
| 24 | 23,51 | 1,24 | 24,75 | +31% |

- **Minimo confirmado em 4 threads**, com bacia plana entre 3 e 6 (±11%/4%) —
  a politica do cap (`N_CORES_HEAP_LEGACY = 4`) esta correta.
- Escala negativa a partir de ~8 threads (+10% em 8, +31% em 24), coerente com o
  lock convoy do heap legacy.
- Assinatura de deterioracao presente em todos os pontos (ex.: 24t: 1º join 0,9 s ->
  ultimo 7,8 s), incluindo close crescente com threads (0,43 s em 1t -> 1,24 s em 24t).
