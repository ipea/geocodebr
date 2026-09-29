# Diagnóstico — Por que `geocode()` (R) precisa do `callr`: deterioração do DuckDB e o heap do Windows

**Data:** 2026-09-24
**Status:** causa identificada por experimento controlado (A/B com a mesma versão de R e o mesmo `R_HOME`; só muda o manifesto do exe).
**Artefatos:** `2026-09-24_bench_callr.R` (script), `2026-09-24_callr-heap-benchmark.csv` (dados brutos, 40 rodadas).
**Relacionado:** `2026-09-04_geocode-deterioracao-python-diagnostico.md`, que descreve o mesmo fenômeno no porte Python.

## Pergunta

`geocode()` roda o motor (`geocode_core()`) num subprocesso `callr` porque, sem isso, o desempenho do DuckDB
cai a cada chamada. Qual é a causa, e que soluções existem?

## Achado central: o `callr` não resolve "o DuckDB"; ele troca o heap do processo

Leitura do recurso RT_MANIFEST dos executáveis instalados nesta máquina (R 4.5.1, RStudio):

| Executável | `<heapType>SegmentHeap</heapType>` |
|---|---|
| `R/bin/x64/Rterm.exe`, `Rgui.exe`, `Rscript.exe`, `bin/R.exe` | **sim** |
| RStudio `rsession.exe` / `rsession-utf8.exe` | **não** (heap NT legado) |

O `callr::r()` sempre sobe `file.path(R.home("bin"), "Rterm")` (`callr:::setup_r_binary_and_args`). Ou seja:
dentro do RStudio, o `geocode()` sai de um processo com heap NT legado (`rsession`) e roda o DuckDB num
processo com Segment Heap (`Rterm`). No porte Python, esse mecanismo (duckdb/duckdb#24027) já tinha sido
isolado: o heap NT serializa as alocações/liberações concorrentes das threads do DuckDB, fica mais lento que
o Segment Heap e degrada a cada chamada. No Linux e no macOS isso não acontece.

## Experimento

- `large_sample.parquet` (20.028 endereços), pacote da `main` (0.7.0) instalado numa lib temporária, CNEFE
  `v0.5.0`, `resolver_empates = TRUE`, `verboso = FALSE`, `n_cores` padrão (12), 8 rodadas por braço, cada
  braço num processo novo, braços em sequência (sem concorrência entre eles).
- **Controle NT:** cópia do R 4.5.1 com o `Rterm.exe` alterado só numa linha, a `<heapType>…</heapType>`,
  trocada por espaços (patch que preserva o tamanho). R, pacotes e dados são os mesmos; só muda o heap. É um
  substituto do `rsession.exe`, que também não declara Segment Heap.
- Cache e config isolados via `R_USER_CACHE_DIR`/`R_USER_CONFIG_DIR`. Os 40 outputs deram o mesmo checksum
  (`sum(round(lat, 6))`).

## Resultados (wall, segundos)

| rodada | NT, em processo | NT, em processo, 4 threads | **SegmentHeap, em processo** | NT + callr | SegmentHeap + callr |
|---|---|---|---|---|---|
| 1 | 11,62 | 11,85 | 10,32 | 15,05 | 14,20 |
| 2 | 14,78 | 11,44 | 8,89 | 12,07 | 11,56 |
| 3 | 16,48 | 11,66 | 8,08 | 11,94 | 11,27 |
| 4 | 13,33 | 12,10 | 8,12 | 11,99 | 11,30 |
| 5 | 14,61 | 12,88 | 8,51 | 12,57 | 10,93 |
| 6 | 16,45 | 13,09 | 7,61 | 12,24 | 11,31 |
| 7 | 17,13 | 14,10 | 7,96 | 12,12 | 11,39 |
| 8 | 18,07 | 14,32 | 7,94 | 11,87 | 11,76 |
| **8ª ÷ 1ª** | **1,55× (degrada)** | 1,21× (degrada) | 0,77× (plano) | 0,79× (plano) | 0,83× (plano) |

O RSS do processo fica estável em todos os braços (NT em processo: 275 → 326 MB). Como no Python, a
deterioração **não acompanha memória**.

## Leitura

1. **A causa é o heap do processo que hospeda o DuckDB, não o geocodebr nem o DuckDB em si.** Com o mesmo
   R, os mesmos dados e o mesmo código, só a linha do manifesto separa um braço que degrada (1,55×) de outro
   que fica plano (0,77×).
2. **Sem `callr`, num processo com Segment Heap, não há deterioração, e esse é o braço mais rápido**
   (~8 s em regime, contra ~11,3 s com `callr`). O `callr` custa **~3,3 s por chamada** nesta máquina: sobe
   o R, carrega os pacotes, serializa o input e começa com o DuckDB e o cache de parquet frios.
3. **O `callr` resolve por dois caminhos:** (a) processo novo a cada chamada, o que zera o estado degradado
   (NT + callr fica plano), e (b) `Rterm.exe` com Segment Heap (SH + callr é ~5% mais rápido que NT + callr).
   Com a amostra de 20 mil linhas, o efeito (b) é pequeno. No Python, com 10 M de linhas e 24 threads, a
   diferença de patamar entre NT e SegmentHeap chegou a 4,6×.
4. **Limitar as threads atenua a deterioração, mas não a elimina** (4 threads: 1,21× contra 1,55×).
5. A magnitude cresce com o volume e com o número de threads: com 20 mil linhas e 12 núcleos foram +56% em
   8 chamadas. No Python, a mesma assinatura chegou a 12,8× em 5 chamadas com 10 M de linhas.

**Ressalva:** o braço NT usa um `Rterm` alterado, não o `rsession.exe` real. O vínculo com o RStudio vem da
leitura do manifesto (acima), não de uma medição dentro do RStudio. Para confirmar no RStudio, basta rodar o
laço em processo do script (`geocodebr:::geocode_core(...)` 8×) e ver se os tempos sobem.

## Soluções

| # | Opção | Efeito | Custo / risco |
|---|---|---|---|
| A | **Manter o `callr` sempre** (situação atual) | Resolve em qualquer host | ~3,3 s de overhead fixo por chamada (relevante para lotes pequenos, desprezível com milhões de linhas); perde o `browser()` |
| B | **`callr` condicional ao heap do host**: rodar `geocode_core()` em processo quando `.Platform$OS.type != "windows"` ou quando o exe do processo (`ps::ps_exe()`) declara `SegmentHeap</heapType>`; usar `callr` só no Windows com heap legado (RStudio) | Tira o overhead no Rterm/Rgui/Rscript, no Linux e no macOS; mantém a proteção no RStudio | É preciso reproduzir em processo o que o `callr` dá de graça: **cópia do `enderecos`** (o motor usa `setDT`/`:=` por referência) e o isolamento de memória. Mesma lógica de detecção do `python-package/geocodebr/_heap.py`. Falta medir se o R no Linux fica plano (o Python fica) |
| C | **Upstream no Posit:** pedir `<heapType>SegmentHeap</heapType>` no manifesto do `rsession.exe` (e conferir o `ark.exe` do Positron) | Corrige na origem para todo pacote que usa DuckDB/Arrow/data.table multithread no RStudio | Fora do nosso controle; não ajuda versões antigas do RStudio |
| D | Upstream no DuckDB (#24027): alocador próprio no Windows (ex.: mimalloc) em vez do heap do CRT | Corrigiria em qualquer host | Fora do nosso controle; o fix atual (#24036) só cobre o CLI |
| E | Limitar threads no heap NT (o que o porte Python faz, `min(4, núcleos)`) | Só atenua (1,55× → 1,21×) | Perde paralelismo; **não substitui o `callr`** |
| F | Mandar o usuário corrigir o `rsession.exe` (patch do manifesto) | Resolve | Mexe em `Program Files`, exige admin e se perde a cada atualização do RStudio; não é viável como recomendação do pacote |

**Recomendação:** manter o `callr` como proteção padrão (A) e evoluir para (B): `callr` só onde o heap do host
é o legado, execução em processo nos demais casos. Em paralelo, abrir a issue (C) no `rstudio/rstudio` citando
duckdb/duckdb#24027, porque ela resolve o problema na raiz para todo o ecossistema. Antes de implementar (B):
(1) medir o R no Linux com o mesmo script; (2) confirmar a deterioração dentro do RStudio real; (3) garantir que
o caminho em processo não modifique o objeto do usuário.

## Adendo 2026-09-25 — Linux e macOS (GitHub Actions)

Workflow `bench-callr.yaml` na branch `bench-callr-linux` (não mesclar), run
https://github.com/ipea/geocodebr/actions/runs/36088473953. Mesmo protocolo (`large_sample`, 8 rodadas por
braço, processo novo por braço, CNEFE baixado antes da medição), R release, duckdb 1.5.5, runners de 4 vCPU
(ubuntu x64, macOS arm64). Os 32 outputs deram o mesmo checksum que no Windows.

| rodada | Linux, em processo | Linux, callr | macOS, em processo | macOS, callr |
|---|---|---|---|---|
| 1 | 6,00 | 7,52 | 5,78 | 8,06 |
| 2 | 5,49 | 7,37 | 4,22 | 8,36 |
| 3 | 5,42 | 7,38 | 3,80 | 7,66 |
| 4 | 5,47 | 7,39 | 3,83 | 6,49 |
| 5 | 5,49 | 7,37 | 4,27 | 7,65 |
| 6 | 5,48 | 7,46 | 4,15 | 9,53 |
| 7 | 5,59 | 7,45 | 4,33 | 6,17 |
| 8 | 5,41 | 7,41 | 4,64 | 6,54 |
| RSS do processo depois | ~360 MB estável | ~275 MB | **~1,78 GB** (estável a partir da 2ª) | ~225 MB |

- **Linux: plano e sem ambiguidade.** Em processo fica em 5,4–5,6 s (CV < 1%) e o `callr` custa ~2 s por
  chamada sem proteger contra nada.
- **macOS: mais rápido em processo (~4,2 s contra ~7,5 s), mas não perfeitamente plano.** Da 3ª à 8ª rodada
  sobe 3,80 → 4,64 s (+22%). O braço `callr`, que por construção não deteriora, oscila 6,2–9,5 s no mesmo
  runner, então o ruído desse ambiente é maior que a tendência. Não é a assinatura do Windows, mas 8 rodadas
  não bastam para descartar uma deriva leve.
- **macOS retém ~1,8 GB de RSS** depois da 1ª chamada em processo (Linux: ~360 MB). O valor não cresce
  depois, então não é vazamento: é memória que o alocador do macOS não devolve ao SO. Com o `callr` ela é
  devolvida quando o filho termina.

### Rerodada macOS com 20 chamadas (2026-09-25)

Run https://github.com/ipea/geocodebr/actions/runs/36126192503; os 40 outputs com o mesmo checksum.

| | 1ª | 2ª–10ª (mediana) | 11ª–20ª (mediana) | faixa 2ª–20ª | 20ª | RSS depois |
|---|---|---|---|---|---|---|
| em processo | 5,81 | 4,72 | 4,47 | 3,96–5,44 | 4,16 | 1,72 → 1,86 GB, platô de 1,86 GB a partir da 13ª |
| callr | 8,26 | 8,23 | 6,43 | 5,30–12,29 | 6,71 | ~0,2 GB |

**Conclusão: o macOS em processo é plano.** A deriva vista com 8 rodadas era ruído: a segunda metade é até
um pouco mais rápida que a primeira. Em processo é ~2–3 s mais rápido que o `callr`. O único custo real é a
memória retida pelo processo, que estabiliza em ~1,9 GB com esta amostra e não cresce depois.

**Decisão técnica resultante:** o `callr` só se justifica no Windows com heap legado. Linux e macOS podem rodar
em processo.
