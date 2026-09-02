# Benchmark — port Python, sample CadÚnico 10M

Protocolo: rodar antes e depois de cada alteração (`--label`) e comparar tempos por fase.
Sample: `data/sample_cad_unico.parquet` · args fixos: `resolver_empates=True`, `cache=True`, `n_cores=None` (24 threads).
`fechamento_conexao` = tempo de `con.close()` (marco "Conexão fechada" no `finally`); `-1` = marco ausente.

---

## Comparação: baseline vs patch_merge (2026-09-02)

Patch: `merge_results_to_input` sem UPDATE de tabela inteira (COALESCE na projeção) + sem
re-sort com `EXCLUDE` no fim do `geocode()` (`utils.py` + `geocode.py`).

| fase | baseline | patch_merge | variação |
|---|---|---|---|
| cnefe | 0:05 | 0:01 | ruído |
| padronizacao | 0:54 | 0:44 | ruído |
| matching | 5:05 | 4:47 | ruído (±20% entre rodadas) |
| empates | 1:51 | 1:26 | ruído (±15% entre rodadas) |
| precisao | 0:07 | 0:07 | = |
| **merge** | **0:41** | **0:21** | **−49%** |
| materializacao | 0:07 | 0:07 | = |
| fechamento_conexao | 2:56 | 2:18 | ruído (ver abaixo) |
| pos_finalizado | 0:01 | 0:01 | = |
| **TOTAL (wall)** | **11:47** | **9:52** | **−16%** |

Notas:
- **merge é a única fase alterada pelo patch** e é altamente reprodutível: 0:41 na baseline,
  0:41 também numa rodada prévia descartada (bug do parser, deltas válidos), 0:21 com patch.
  O sinal não é ruído.
- Resultado idêntico nas duas versões: 9.999.355/10.000.000 encontradas.
- `con.close()` domina o restante do wall time (~2:18–2:56; ~20–25% do total) — escala
  linearmente com o volume (≈10–12 min no CadÚnico de 43M). Candidato à próxima otimização.
- As demais fases variam ±15–20% entre rodadas; totais de rodada única devem ser lidos com
  essa margem.
- Extrapolação p/ 43M (rc=False): merge 10:32 → ~5 min esperados (o custo é superlinear
  nesse volume, provável spill; o patch remove 1 de 2 sorts completos). Com rc=True, o
  patch também elimina o UPDATE de tabela inteira.

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

