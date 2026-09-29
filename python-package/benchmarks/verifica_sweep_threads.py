"""Sweep da curva tempo x threads do DuckDB no heap NT legacy (Windows).

Responde a pergunta: o minimo da curva esta de fato em ~4 threads, como
pressupoe o cap default `N_CORES_HEAP_LEGACY = 4` aplicado pelo `geocode()`
no Windows sem Segment Heap? (referencias: duckdb/duckdb#24027 — "peak
around 4 threads and then regress" — e o historico de escala negativa do
pipeline no legacy).

Metodo: workload canonico do duckdb#24027 (8M x 12 strings + 2M dicionario +
6 LEFT JOINs re-materializando + close) em filhos recem-criados — heap novo
a cada medicao, sem contaminacao da deterioracao acumulada entre pontos da
curva. As rodadas sao intercaladas com ordem alternada (crescente/decrescente)
para reduzir vies de deriva da maquina compartilhada (±15-20% entre janelas).

Uso:

    python benchmarks/verifica_sweep_threads.py                 # sweep completo
    python benchmarks/verifica_sweep_threads.py --smoke        # 2M linhas, 1 rodada
    python benchmarks/verifica_sweep_threads.py --threads 4 8 --repeticoes 2
"""

from __future__ import annotations

import argparse
import os
import statistics
import subprocess
import sys
import time

RESULT_PREFIX = "RESULT|"

DEFAULT_THREADS = [1, 2, 3, 4, 6, 8, 12, 16, 24]


def tem_segment_heap_no_manifest(exe: str) -> bool:
    try:
        with open(exe, "rb") as f:
            return b"SegmentHeap" in f.read()
    except OSError:
        return False


def rodar_filho(threads: int, linhas: int) -> None:
    """Workload canonico da issue; imprime linha `RESULT|` parseavel pelo pai."""
    import duckdb

    con = duckdb.connect(":memory:")
    con.execute(f"SET threads TO {threads}")

    payload = ", ".join(
        f"'p{k}_' || CAST(hash(i * {k * 7 + 13}) % 100000 AS VARCHAR) AS p{k}"
        for k in range(10)
    )
    con.execute(
        f"CREATE TABLE t AS SELECT i AS id, "
        f"'k' || CAST(hash(i) % 2000000 AS VARCHAR) AS key, {payload} "
        f"FROM range({linhas}) t(i)"
    )
    con.execute(
        "CREATE TABLE d AS SELECT 'k' || CAST(i AS VARCHAR) AS key, "
        "'v' || CAST(i AS VARCHAR) AS value FROM range(2000000) t(i)"
    )

    tempos = []
    for k in range(1, 7):
        t0 = time.perf_counter()
        con.execute(
            "CREATE OR REPLACE TABLE t AS "
            f"SELECT t.*, d.value AS v{k} FROM t LEFT JOIN d ON t.key = d.key"
        )
        tempos.append(time.perf_counter() - t0)

    t2 = time.perf_counter()
    con.close()
    fechamento = time.perf_counter() - t2

    times_csv = ",".join(f"{t:.2f}" for t in tempos)
    print(f"{RESULT_PREFIX}{threads}|{linhas}|{times_csv}|{fechamento:.2f}", flush=True)


def lancar_filho(args: argparse.Namespace, threads: int, linhas: int):
    cmd = [
        args.exe,
        os.path.abspath(__file__),
        "--filho",
        f"{threads}:{linhas}",
    ]
    t0 = time.perf_counter()
    proc = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        timeout=args.timeout,
        check=False,
    )
    wall = time.perf_counter() - t0

    resultado = None
    for line in proc.stdout.splitlines():
        if line.startswith(RESULT_PREFIX):
            resultado = line
    if proc.returncode != 0 or resultado is None:
        print(f"[ERRO] filho threads={threads} rc={proc.returncode}")
        print(proc.stdout[-2000:])
        print(proc.stderr[-2000:])
        return None

    campos = resultado[len(RESULT_PREFIX):].split("|")
    joins = [float(x) for x in campos[2].split(",")]
    res = {
        "threads": threads,
        "joins": joins,
        "total": sum(joins),
        "fechamento": float(campos[3]),
        "wall": wall,
    }
    print(
        f"  threads={threads:>2} | joins={res['total']:7.2f}s "
        f"(1º={joins[0]:.1f}, último={joins[-1]:.1f}) | "
        f"close={res['fechamento']:.2f}s | wall={wall:.1f}s",
        flush=True,
    )
    return res


def main() -> int:
    if sys.platform == "win32":
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--threads", nargs="+", type=int, default=DEFAULT_THREADS)
    parser.add_argument("--repeticoes", type=int, default=3)
    parser.add_argument("--linhas", type=int, default=8_000_000)
    parser.add_argument("--exe", default=sys.executable)
    parser.add_argument("--timeout", type=int, default=900)
    parser.add_argument("--smoke", action="store_true")
    parser.add_argument("--filho", metavar="THREADS:LINHAS")
    args = parser.parse_args()

    if args.filho:
        threads, linhas = args.filho.split(":")
        rodar_filho(int(threads), int(linhas))
        return 0

    if args.smoke:
        args.linhas = 2_000_000
        args.repeticoes = 1
        args.threads = [2, 4, 8]

    print(f"exe: {args.exe}")
    print(f"python: {sys.version.split()}")
    print(
        "manifest do exe declara SegmentHeap:",
        tem_segment_heap_no_manifest(args.exe) if sys.platform == "win32" else "n/a",
    )
    print(
        f"\n=== sweep · {args.repeticoes} rodadas intercaladas · "
        f"{args.linhas:,} linhas ===\n".replace(",", ".")
    )

    resultados: dict[int, list] = {t: [] for t in args.threads}
    for r in range(args.repeticoes):
        ordem = args.threads if r % 2 == 0 else list(reversed(args.threads))
        print(f"-- rodada {r + 1}/{args.repeticoes} (ordem: {ordem})")
        for threads in ordem:
            res = lancar_filho(args, threads, args.linhas)
            if res:
                resultados[threads].append(res)

    print("\n=== resumo (medianas) ===")
    print("threads | joins(s) | close(s) | total(s) | n")
    print("--------+----------+----------+----------+---")
    totais = {}
    for threads in args.threads:
        runs = resultados[threads]
        if not runs:
            print(f"{threads:>7} | (sem dados)")
            continue
        med_joins = statistics.median(r["total"] for r in runs)
        med_close = statistics.median(r["fechamento"] for r in runs)
        totais[threads] = med_joins + med_close
        print(
            f"{threads:>7} | {med_joins:8.2f} | {med_close:8.2f} | "
            f"{totais[threads]:8.2f} | {len(runs)}"
        )

    if len(totais) < 2:
        print("\nVEREDITO: dados insuficientes.")
        return 1

    melhor = min(totais, key=totais.get)
    print(f"\nVEREDITO: minimo da curva em threads={melhor} "
          f"({totais[melhor]:.2f}s).")
    for t in sorted(totais):
        if t != melhor:
            print(f"  threads={t}: +{(totais[t] / totais[melhor] - 1) * 100:.0f}% vs minimo")
    print("\nNota: curve shape no heap legacy; no SegmentHeap a curva decresce")
    print("monotonicamente (mais threads e sempre melhor) — o cap so se aplica ao legacy.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
