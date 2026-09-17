"""Verificação rápida do efeito do Segment Heap (duckdb/duckdb#24027).

Workload canônico da issue: tabela larga na memória (8M x 12 strings) +
6 LEFT JOINs re-materializando a cada round. Rode com o python normal e
com a cópia `python-sh.exe` e compare; intervele as rodadas (máquina
compartilhada varia ±15-20% entre janelas).

    python verifica_segment_heap.py 24
    python-sh.exe verifica_segment_heap.py 24

Assinatura do heap legacy: cada join fica mais lento que o anterior (a
tabela alarga a cada round) e MAIS threads piora em vez de ajudar. Com
SegmentHeap os joins ficam planos e escalam.
"""

import sys
import time

import duckdb

threads = sys.argv[1] if len(sys.argv) > 1 else "8"

con = duckdb.connect(":memory:")
con.execute(f"SET threads TO {threads}")

payload = ", ".join(
    f"'p{k}_' || CAST(hash(i * {k * 7 + 13}) % 100000 AS VARCHAR) AS p{k}"
    for k in range(10)
)
con.execute(
    f"CREATE TABLE t AS SELECT i AS id, "
    f"'k' || CAST(hash(i) % 2000000 AS VARCHAR) AS key, {payload} "
    f"FROM range(8000000) t(i)"
)
con.execute(
    "CREATE TABLE d AS SELECT 'k' || CAST(i AS VARCHAR) AS key, "
    "'v' || CAST(i AS VARCHAR) AS value FROM range(2000000) t(i)"
)

tempos = []
for k in range(1, 7):
    t0 = time.perf_counter()
    con.execute(
        f"CREATE OR REPLACE TABLE t AS "
        f"SELECT t.*, d.value AS v{k} FROM t LEFT JOIN d ON t.key = d.key"
    )
    tempos.append(time.perf_counter() - t0)
    print(f"join {k}: {tempos[-1]:.2f}s")

t2 = time.perf_counter()
con.close()
print(f"threads={threads} | joins={sum(tempos):.2f}s | close={time.perf_counter() - t2:.2f}s")
