# Diagnóstico — Deterioração de tempo entre chamadas sucessivas de `geocode()` (Python)

**Data:** 2026-09-04
**Status:** FECHADO — causa identificada por experimento controlado. Este documento cobre
sintoma, evidências e diagnóstico; a proposta de implementação segue separada em
[`quality_reports/plans/2026-09-02_python_isolamento-subprocesso-geocode.md`](../plans/2026-09-02_python_isolamento-subprocesso-geocode.md).

## Sintoma

Chamadas sucessivas de `geocode()` no mesmo processo Python degradam de forma ~linear e
acumulativa. Benchmark original (10 rodadas, `data/consolidado_info.parquet`,
`resultado_completo=True`, `resolver_empates=True`, `verboso=False`): 2,86 min na rodada 1
até 30,75 min na rodada 10. Cada chamada fecha a própria conexão DuckDB no `finally`.

Descartado por inspeção antes dos experimentos: não há cache global em nível de módulo
(tabelas CNEFE são `TEMP TABLE` por conexão; `cache.py` só gerencia config/pasta de cache
em disco; sem `lru_cache`/singleton crescente) e as conexões são fechadas corretamente
(`geocode.py:189-191`).

## Metodologia

- Plataforma de referência: Windows. O protocolo é portátil e está implementado em
  `python-package/benchmarks/verifica_deterioracao.py` (in-process vs `--isolado`,
  wall/CPU, RSS/USS, threads, veredito automático) para os testes em Linux/macOS.
- Dois interpretadores: CPython 3.13.7 (console, `Program Files\Python313`) e CPython
  3.10.20 (`.venv` do repositório, uv); duckdb 1.5.3 e polars ~1.43–1.44 em ambos.
- Métricas: tempo wall e CPU; RSS (`memory_info().rss`); commit charge privado
  (`memory_full_info().private`); medições pós-`gc.collect()` para separar memória
  devolvível de memória retida; memória do sistema (para descartar pressão externa).
- Cache CNEFE aquecido antes das medições (a 1ª chamada pode incluir download).
- **Bases não comparáveis entre si**: `consolidado_info.parquet` (7.829.746 linhas, só
  Pernambuco) e `sample_cad_unico.parquet` (10.000.000 linhas, amostra aleatória do
  Brasil) produzem patamares absolutos diferentes — a abrangência geográfica muda o mix
  de fases do matching. Toda comparação de nível é feita dentro da mesma base.
- Experimentos executados entre 02 e 04/09/2026.

## Evidências

### E1 — Degradação in-process sem crescimento de memória

5 rodadas no mesmo processo (3.13.7, heap NT, `consolidado_info`):

| rodada | tempo (min) | RSS antes (GB) | RSS pico (GB) | RSS pós-gc (GB) |
|---|---|---|---|---|
| 1 | 3,11 | 0,42 | 11,13 | 6,98 |
| 2 | 5,67 | 6,98 | 8,45 | 4,30 |
| 3 | 8,09 | 4,30 | 7,50 | 3,34 |
| 4 | 10,31 | 3,34 | 7,42 | 3,26 |
| 5 | 12,13 | 3,26 | 8,41 | 4,26 |

Degradação 3,9× na rodada 5; o RSS retido **decresce** após a rodada 1 e estabiliza
(3,3–4,3 GB). A hipótese de "memória acumulada entre chamadas" é refutada pela própria
métrica que a redação original do plano elegera como critério de validação
(RSS crescente).

### E2 — Processo recém-criado por rodada: tempos planos, sem patch de heap

Mesmo input de E1; cada rodada em interpretador novo (tempo medido dentro do filho,
excluindo o startup):

| rodada | in-process (min) | subprocesso novo (min) |
|---|---|---|
| 1 | 3,11 | 3,07 |
| 2 | 5,67 | 3,03 |
| 3 | 8,09 | 2,87 |
| 4 | 10,31 | 2,81 |
| 5 | 12,13 | 2,88 |

Razão rodada 5/1: 3,90× (in-process) vs **0,94×** (subprocesso). Recriar o processo
elimina a deterioração — o estado degradado vive no processo. Nos filhos, commit privado
basal constante (0,86 GB) e pico plano (7,1–7,6 GB).

### E3 — Commit privado estável entre rodadas no mesmo processo

3 rodadas in-process em sessão recém-criada (3.13.7, `consolidado_info`); sistema com
~409 GB de RAM disponíveis e commit estável (9,6/40,2 GB) em todas as rodadas:

| rodada | tempo (min) | commit antes (GB) | commit pico (GB) | commit pós-gc (GB) |
|---|---|---|---|---|
| 1 | 3,00 | 0,95 | 11,39 | 6,43 |
| 2 | 4,90 | 6,43 | 12,95 | 8,01 |
| 3 | 7,66 | 8,01 | 11,78 | 6,78 |

Nem retenção acumulativa (6,43 → 8,01 → 6,78 GB) nem pico crescente (11,4–13,0 GB):
a degradação não acompanha **nenhuma** métrica de memória, nem do processo nem do SO.

### E4 — A/B do heap do exe hospedeiro (mesma base, mesmo venv, só o exe muda)

Com o `.venv` 3.10, `sample_cad_unico.parquet` (10M), 5 rodadas in-process, mesmo script
(`verifica_segment_heap_geocode.py`), variando apenas o executável:

| rodada | `python.exe` (heap NT) (min) | `python-sh.exe` (SegmentHeap) (min) |
|---|---|---|
| 1 | 13,11 | 2,88 |
| 2 | 55,91 | 2,90 |
| 3 | 105,18 | 2,88 |
| 4 | 147,89 | 2,79 |
| 5 | 167,77 | 2,83 |

Razão rodada 5/1: **12,8×** (NT) vs **0,98×** (SegmentHeap). O heap do exe hospedeiro
governa dois efeitos distintos: a **deterioração entre chamadas** (plana com
SegmentHeap, 12,8× sem) e o **nível absoluto de cada chamada** (rodada 1: 2,88 vs
13,11 min — 4,6×). Dado de campo adicional na base completa `cad_unico.parquet` (43M):
1,6 h no 3.13 sem patch vs 11 min no 3.10 com patch.

Verificação de integridade do A/B: inspeção binária confirmou
`<heapType>SegmentHeap</heapType>` (UTF-8, dentro de `windowsSettings` do RT_MANIFEST)
**apenas** no `python-sh.exe`; os `python.exe` 3.10 e 3.13 não têm. A edição é
size-preserving (0,09 MB nos dois) e o patch é o único diferencial entre os braços.

### Esclarecimento de confundidores (checados, não assumidos)

- **Versão do CPython não explica o nível**: 1 rodada do `sample_cad_unico` no 3.13.7
  sem patch, processo recém-criado, levou **11,49 min** — patamar compatível com os
  13,11 min do 3.10 sem patch na mesma base. A diferença de patamar entre
  `consolidado_info` (~3 min/rodada) e `sample_cad_unico` (~13 min/rodada) é da
  **natureza da base**, não do interpretador.

## O problema do Segment Heap no Windows (duckdb/duckdb#24027)

Esta é a causa-raiz do fenômeno e merece documentação própria, porque a degradação
medida em `geocode()` é uma manifestação dela.

**O mecanismo do SO.** O Windows tem dois gerenciadores de heap para o processo:
o **heap NT legacy** (padrão histórico) e o **Segment Heap** (Windows 10 2004+), mais
escala-friendly. A escolha é **por processo, fixada no image load**: o loader lê o
elemento `<heapType>SegmentHeap</heapType>` do manifest embutido (resource RT_MANIFEST)
do executável. Não existe API para trocar o heap em runtime — um processo só tem
Segment Heap se **nasce** de um exe que o declara. O `Rscript.exe` já declara (por isso o
R nunca exibiu o problema); o `python.exe` não.

**Por que o DuckDB é o atingido.** O DuckDB operando com N threads (o default do
`geocode()` usa o total de cores; 24 na máquina de referência) faz grande volume de
alocações/liberações concorrentes de strings e blocos. O heap NT legacy serializa essas
operações em estruturas com contenção global e ainda sofre degradalção progressiva com
fragmentação — o resultado é **escala negativa**: mais threads deixam o workload *lento*
em vez de mais rápido. Assinatura clássica medida no workload canônico da issue
(`verifica_segment_heap.py`, 8M × 12 strings + 6 LEFT JOINs): cada join fica mais lento
que o anterior e mais threads pioram o resultado; com Segment Heap os tempos são planos
e escalam. Probes pareados: threads=8 → 23,8 s (NT) vs 8,9–9,7 s (SegmentHeap, ~2,6×);
threads=24 → 32 s vs 7–7,7 s (**~4,5×**).

**Por que releases do DuckDB não resolvem o lado Python.** O fix upstream
(duckdb/duckdb#24036) cobre apenas o CLI — que controla o próprio exe. Em *embedding*
(R, Python), o manifest pertence ao **exe hospedeiro** (`Rscript.exe`, `python.exe`),
sobre o qual o DuckDB não tem controle. Portanto o problema persiste em qualquer versão
do duckdb-py enquanto o `python.exe` não optar pelo Segment Heap.

**Efeito em `geocode()`, fase a fase** (`resultados_benchmark.md`, sample 10M, 24
threads; `patch_merge` = otimização de merge já aplicada; `patch_heap` = idem +
interpretador com Segment Heap):

| fase | baseline | patch_merge | patch_heap | ganho do heap vs baseline |
|---|---|---|---|---|
| matching | 5:05 | 4:47 | **1:53** | 2,7× |
| empates | 1:51 | 1:26 | **0:05** | ~21× |
| merge | 0:41 | 0:21 | **0:04** | ~10× |
| fechamento_conexao | 2:56 | 2:18 | **0:05** | ~35× |
| **TOTAL (wall)** | **11:47** | **9:52** | **3:08** | **3,75×** |

O patch do heap resolveu, de quebra, dois "mistérios" anteriores do porte: a inflação
~10× da fase de empates em dados reais vs sintéticos (contenção do heap amplificada pelo
volume de strings reais com 24 threads) e o `con.close()` de ~3 min (frees massivos das
24 threads na mesma fila do heap). A piora com mais threads também explica a deterioração
entre chamadas sucessivas (E4: 12,8×), que é a mesma contenção agravada pelo estado
progressivo do heap ao longo da vida do processo.

**Mitigações conhecidas** (fato, não recomendação): lançar o processo com um exe que
declare Segment Heap (cópia do CPython com manifest editado — técnica size-preserving,
o `python.exe` original não é tocado); sem patch, reduzir `n_cores` (~4) mitiga a
contenção ao custo de throughput; recriar o processo entre chamadas elimina apenas a
deterioração, não o nível.

## Diagnóstico

**Causa**: o heap do processo hospedeiro no Windows. O heap NT legacy degrada sob
alocação/liberação multithread intensa (DuckDB com N threads + polars/pyarrow), e a
degradação se manifesta como tempo crescente entre chamadas sucessivas — não como
memória retida, que permanece estável. Atribuição causal por duas intervenções
independentes, ambas validadas:

1. recriar o processo entre chamadas elimina a deterioração (E2) — o estado degradado
   vive no processo;
2. trocar apenas o heap do processo (manifest SegmentHeap, mais nada) elimina a
   deterioração **e** melhora o nível de cada chamada (E4) — o estado degradado é o
   heap, especificamente.

**Refutado pelas evidências** (e que a redação original do plano afirmava ou insinuava):

- memória acumulada entre chamadas — RSS e commit estáveis/decrescentes (E1, E3);
- pressão de memória do SO / spill crescente — sistema com folga e estável (E3);
- efeito da versão do CPython no nível de performance (esclarecimento pós-E4);
- cache global, conexões não fechadas, artefatos de TEMP como causa de performance — o
  `.duckdb` vazio deixado por chamada é vazamento cosmético de `db.py` (0 bytes, sem
  efeito medido; corrigir por higiene em PR próprio).

**Em aberto**:

- O mecanismo fino *dentro* do alocador (contenção de locks, fragmentação de segmentos,
  comportamento do LFH) não foi traçado — a atribuição causal é experimental, não de
  código. Para rastrear: py-spy/WPA comparando rodada 1 vs rodada 5 in-process.
- Comportamento em Linux/macOS: não medido. Harness pronto em
  `verifica_deterioracao.py`. Se não houver deterioração sob jemalloc/libmalloc, o
  fenômeno é Windows-only.
- Estabilidade de longo prazo do Segment Heap em muitas rodadas (o A/B cobriu 5; a
  degradação do NT também só se manifestava progressivamente).

## Reprodutibilidade

- `python-package/benchmarks/verifica_deterioracao.py` — harness portátil: N rodadas
  in-process ou em subprocesso por rodada (`--isolado`), wall/CPU, RSS/USS, threads,
  veredito pela razão última/primeira rodada; detecção de SegmentHeap pelos bytes do
  manifest (não pelo nome do exe).
- `python-package/benchmarks/verifica_segment_heap.py` — workload canônico da issue
  (8M × 6 joins), para probes pareados NT vs SegmentHeap.
- `python-package/benchmarks/verifica_segment_heap_geocode.py` — loop de rodadas de
  `geocode()` usado no A/B de E4 (campos hard-coded; ver cabeçalho).
- `python-package/benchmarks/resultados_benchmark.md` — decomposição por fase e probes
  citados acima.
- Dados: `data/consolidado_info.parquet` (7,8M, PE), `data/sample_cad_unico.parquet`
  (10M, Brasil), `data/cad_unico.parquet` (43M, Brasil).
