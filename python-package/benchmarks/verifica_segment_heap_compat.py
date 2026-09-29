"""Probe P0 — `__COMPAT_LAYER=SEGMENTHEAP` ativa o Segment Heap no Windows?

Fase 0 do plano
`quality_reports/plans/2026-09-08_python_deterioracao-e-nivel-heap-windows.md`.
O shim de compatibilidade do Windows lê a variável de ambiente `__COMPAT_LAYER`
na inicialização do processo; se `SEGMENTHEAP` for honrado, o filho nasce com
Segment Heap sem criar arquivo algum no diretório do interpretador — eliminando
os riscos de permissão/AV do exe cópia patcheado (técnica E4 do diagnóstico).

Método: workload canônico de duckdb/duckdb#24027 (8M × 12 strings + 6 LEFT
JOINs re-materializando) em filhos recém-criados, com (arm `sh`) e sem (arm
`nt`) o layer no env, intercalados (máquina compartilhada varia ±15-20% entre
janelas). Assinatura do legacy NT: joins ficam mais lentos a cada round e mais
threads piora; com SegmentHeap, joins planos e escalando. Referência histórica
do exe patcheado (E4): threads=8 → ~23,8 s (NT) vs ~8,9-9,7 s (SH); threads=24
→ ~32 s (NT) vs ~7-7,7 s (SH).

Uso:

    python verifica_segment_heap_compat.py             # probe completo (8 e 24 threads, 3 rodadas)
    python verifica_segment_heap_compat.py --smoke     # validação rápida (1M linhas, 1 rodada)
    python verifica_segment_heap_compat.py --threads 24 --repeticoes 5

Critério do plano: gap pareado >= 2× (mediana NT / mediana SH) → estratégia 1
(`__COMPAT_LAYER`) vira primária; caso contrário, prevalece o exe cópia
patcheado.
"""

from __future__ import annotations

import argparse
import os
import statistics
import subprocess
import sys
import time

LAYER_ENV = "__COMPAT_LAYER"
RESULT_PREFIX = "RESULT|"


def tem_segment_heap_no_manifest(exe: str) -> bool:
    """Detecta `<heapType>SegmentHeap</heapType>` nos bytes do exe (Windows)."""
    try:
        with open(exe, "rb") as f:
            return b"SegmentHeap" in f.read()
    except OSError:
        return False


def rodar_filho(arm: str, threads: int, linhas: int) -> None:
    """Workload canônico da issue; imprime linha `RESULT|` parseável pelo pai."""
    import duckdb
    import pandas as pd
    import polars as pl

    # sanidade: o layer não pode quebrar o runtime que o geocodebr usa
    df = pl.DataFrame({"a": [1, 2, 3]})
    assert duckdb.sql("SELECT sum(a) FROM df").fetchone()[0] == 6
    assert pl.from_pandas(pd.DataFrame({"a": [1.0]}))["a"].sum() == 1.0

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

    commit_gb = -1.0
    try:
        import psutil

        commit_gb = psutil.Process().memory_full_info().private / 1e9
    except Exception:
        pass

    times_csv = ",".join(f"{t:.2f}" for t in tempos)
    print(
        f"{RESULT_PREFIX}{arm}|{threads}|{linhas}|{times_csv}"
        f"|{fechamento:.2f}|{commit_gb:.2f}",
        flush=True,
    )


def _env_do_filho(arm: str, layer_valor: str) -> dict[str, str]:
    env = os.environ.copy()
    if arm == "sh":
        env[LAYER_ENV] = layer_valor
    else:
        env.pop(LAYER_ENV, None)
    return env


def lancar_filho(args: argparse.Namespace, arm: str, threads: int, linhas: int):
    cmd = [
        sys.executable,
        os.path.abspath(__file__),
        "--filho",
        f"{arm}:{threads}:{linhas}",
    ]
    t0 = time.perf_counter()
    proc = subprocess.run(
        cmd,
        env=_env_do_filho(arm, args.layer_valor),
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
        print(f"[ERRO] filho arm={arm} threads={threads} rc={proc.returncode}")
        print(proc.stdout[-2000:])
        print(proc.stderr[-2000:])
        return None

    campos = resultado[len(RESULT_PREFIX):].split("|")
    joins = [float(x) for x in campos[3].split(",")]
    res = {
        "arm": arm,
        "threads": threads,
        "joins": joins,
        "total": sum(joins),
        "fechamento": float(campos[4]),
        "commit_gb": float(campos[5]),
        "wall": wall,
    }
    print(
        f"  {arm:>2} threads={threads:>2} | joins={res['total']:7.2f}s "
        f"(1º={joins[0]:.1f}, último={joins[-1]:.1f}) | "
        f"close={res['fechamento']:.2f}s | commit={res['commit_gb']:.2f} GB",
        flush=True,
    )
    return res


def medir_startup(args: argparse.Namespace, arm: str, reps: int = 3) -> float:
    env = _env_do_filho(arm, args.layer_valor)
    tempos = []
    for _ in range(reps):
        t0 = time.perf_counter()
        subprocess.run(
            [sys.executable, "-c", "import duckdb, polars, pandas"],
            env=env,
            check=True,
        )
        tempos.append(time.perf_counter() - t0)
    return statistics.median(tempos)


def main() -> int:
    if sys.platform == "win32":
        # console cp1252: evita UnicodeEncodeError nos símbolos do resumo
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--threads", nargs="+", type=int, default=[8, 24])
    parser.add_argument("--repeticoes", type=int, default=3)
    parser.add_argument("--linhas", type=int, default=8_000_000)
    parser.add_argument("--layer-valor", default="SEGMENTHEAP")
    parser.add_argument("--timeout", type=int, default=900)
    parser.add_argument("--smoke", action="store_true")
    parser.add_argument("--filho", metavar="ARM:THREADS:LINHAS")
    args = parser.parse_args()

    if args.filho:
        arm, threads, linhas = args.filho.split(":")
        rodar_filho(arm, int(threads), int(linhas))
        return 0

    if args.smoke:
        args.linhas = 1_000_000
        args.repeticoes = 1
        args.threads = [8]

    print(f"exe: {sys.executable}")
    print(f"python: {sys.version.split()}")
    print(
        "manifest do exe declara SegmentHeap:",
        tem_segment_heap_no_manifest(sys.executable) if sys.platform == "win32" else "n/a",
    )
    print(f"{LAYER_ENV} no env do pai: {os.environ.get(LAYER_ENV, '<ausente>')}")

    resultados = {"nt": [], "sh": []}
    for threads in args.threads:
        print(
            f"\n=== threads={threads} · {args.repeticoes} rodadas intercaladas "
            f"· {args.linhas:,} linhas ===".replace(",", ".")
        )
        for r in range(args.repeticoes):
            ordem = ["nt", "sh"] if r % 2 == 0 else ["sh", "nt"]
            for arm in ordem:
                res = lancar_filho(args, arm, threads, args.linhas)
                if res:
                    resultados[arm].append(res)

    print("\n=== startup (mediana de 3 imports duckdb+polars+pandas) ===")
    for arm in ("nt", "sh"):
        print(f"  {arm:>2}: {medir_startup(args, arm):.2f}s")

    print("\n=== resumo ===")
    veredito_ok = True
    for threads in args.threads:
        nt = [r["total"] for r in resultados["nt"] if r["threads"] == threads]
        sh = [r["total"] for r in resultados["sh"] if r["threads"] == threads]
        if not nt or not sh:
            print(f"threads={threads}: rodada faltante (nt={nt}, sh={sh})")
            veredito_ok = False
            continue
        med_nt, med_sh = statistics.median(nt), statistics.median(sh)
        gap = med_nt / med_sh if med_sh > 0 else float("inf")
        ok = gap >= 2.0
        veredito_ok = veredito_ok and ok
        print(
            f"threads={threads}: NT mediana={med_nt:.2f}s (n={len(nt)}) | "
            f"SH mediana={med_sh:.2f}s (n={len(sh)}) | gap={gap:.2f}x -> "
            f"{'layer ATIVA SegmentHeap' if ok else 'sem efeito'}"
        )

    print(
        "\nVEREDITO: "
        + (
            f"__COMPAT_LAYER={args.layer_valor} ativa o Segment Heap — estratégia 1 "
            "vira primária (plano Fase 0)."
            if veredito_ok
            else "layer sem efeito — primária passa a ser o exe cópia patcheado "
            "(plano Fase 2)."
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
