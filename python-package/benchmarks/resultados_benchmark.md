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

