"""Mede deterioração de `geocode()` entre chamadas sucessivas no mesmo processo.

Uso:
    python verifica_deterioracao.py <arquivo.parquet> [--rodadas 5]
        [--campos-json '{"logradouro": "logradouro", ...}'] [--isolado]

Sem `--isolado`, todas as rodadas rodam no mesmo processo (teste de deterioração).
Com `--isolado`, cada rodada roda em um interpretador recém-criado (controle).
A comparação entre os dois modos é o experimento decisivo do plano
(quality_reports/plans/2026-09-02_python_isolamento-subprocesso-geocode.md):
mesmo input; o que muda é só o escopo do processo.

Portátil (Windows/Linux/macOS). Métricas por rodada: tempo wall e CPU, RSS,
USS (quando o SO provê), nº de threads. Aqueça o cache CNEFE antes de medir
(a 1ª chamada pode incluir download e inflar a rodada 1).

Veredito pela razão última/primeira rodada (limiares heurísticos calibrados
com os benchmarks de 2026-09-03): <1,15 plano; 1,15–1,5 inconclusivo (rodar
mais rodadas/repetições); >1,5 deterioração.
"""

from __future__ import annotations

import argparse
import gc
import json
import os
import platform
import subprocess
import sys
import time

import duckdb
import geocodebr
import polars
import psutil

CAMPOS_PADRAO = {
    "logradouro": "logradouro",
    "numero": "numero",
    "cep": "cep",
    "localidade": "bairro",
    "municipio": "code_muni",
    "estado": "abbrev_state",
}


def has_segment_heap_manifest(exe: str) -> bool | None:
    """True se o exe embute <heapType>SegmentHeap</heapType> (Windows-only)."""
    if sys.platform != "win32":
        return None
    try:
        with open(exe, "rb") as fh:
            data = fh.read()
    except OSError:
        return None
    return b"SegmentHeap" in data


def banner() -> None:
    p = psutil.Process()
    print(f"plataforma   : {platform.platform()}", flush=True)
    print(f"python       : {platform.python_version()} ({sys.executable})", flush=True)
    print(f"duckdb/polars: {duckdb.__version__} / {polars.__version__}", flush=True)
    if sys.platform == "win32":
        print(f"manifest     : SegmentHeap={has_segment_heap_manifest(sys.executable)}", flush=True)
    else:
        print(
            "alocador     : "
            f"LD_PRELOAD={os.environ.get('LD_PRELOAD', '-')} "
            f"MALLOC_ARENA_MAX={os.environ.get('MALLOC_ARENA_MAX', '-')} "
            f"PYTHONMALLOC={os.environ.get('PYTHONMALLOC', '-')} "
            f"DYLD_INSERT_LIBRARIES={'sim' if os.environ.get('DYLD_INSERT_LIBRARIES') else '-'}",
            flush=True,
        )
    print(f"processo     : threads={p.num_threads()}", flush=True)


def mem() -> tuple[float, float | None]:
    """(RSS, USS) em GB; USS é None onde o SO não provê."""
    p = psutil.Process()
    rss = p.memory_info().rss / 1e9
    try:
        return rss, p.memory_full_info().uss / 1e9
    except (AttributeError, psutil.AccessDenied):
        return rss, None


def _gb(x: float | None) -> str:
    return "  n/d" if x is None else f"{x:5.2f}"


def rodar_uma_rodada(caminho: str, campos: dict) -> dict:
    """Executa geocode() 1x e devolve métricas."""
    proc = psutil.Process()
    gc.collect()
    rss0, uss0 = mem()
    t0 = time.perf_counter()
    c0 = time.process_time()
    res = geocodebr.geocode(
        enderecos=caminho,
        campos_endereco=campos,
        resultado_completo=True,
        resolver_empates=True,
        verboso=False,
    )
    dt = time.perf_counter() - t0
    cpu = time.process_time() - c0
    n = res.num_rows
    del res
    gc.collect()
    rss1, uss1 = mem()
    return {
        "dt": dt,
        "cpu": cpu,
        "rss0": rss0,
        "rss1": rss1,
        "uss0": uss0,
        "uss1": uss1,
        "threads": proc.num_threads(),
        "n": n,
    }


def relatorio(rotulo: str, m: dict) -> None:
    print(
        f"{rotulo}: wall={m['dt'] / 60:6.2f} min | CPU {m['cpu'] / 60:6.2f} min | "
        f"RSS {_gb(m['rss0'])}->{_gb(m['rss1'])} GB | USS {_gb(m['uss0'])}->{_gb(m['uss1'])} GB | "
        f"threads={m['threads']} | {m['n']} linhas",
        flush=True,
    )


def veredito(tempos: list[float]) -> None:
    if len(tempos) < 2:
        return
    razao = tempos[-1] / tempos[0]
    print(f"\nrazao ultima/primeira rodada: {razao:.2f}x", flush=True)
    if razao < 1.15:
        print("veredito: plano (sem deterioracao detectada)", flush=True)
    elif razao < 1.5:
        print("veredito: inconclusivo — aumente --rodadas ou repita o teste", flush=True)
    else:
        print("veredito: DEGRADACAO intra-processo detectada", flush=True)
        print(
            "contraste com --isolado: plano aí tambem => estado de processo; "
            "degrada em ambos => investigar causa externa ao processo",
            flush=True,
        )


def modo_isolado(parquet: str, campos: dict, rodadas: int) -> list[float]:
    """Cada rodada em um interpretador recém-criado (controle)."""
    tempos: list[float] = []
    for i in range(rodadas):
        t0 = time.perf_counter()
        p = subprocess.run(
            [sys.executable, __file__, parquet, "--rodadas", "1",
             "--silencioso", "--campos-json", json.dumps(campos)],
            capture_output=True,
            text=True,
        )
        if p.returncode != 0:
            print(f"rodada {i + 1}: FALHOU\n{p.stderr[-1000:]}", flush=True)
            continue
        line = [ln for ln in p.stdout.splitlines() if ln.startswith("RESULT|")][-1]
        _, dt, cpu, rss1, uss1, n, thr = line.split("|")
        tempos.append(float(dt))
        print(
            f"rodada {i + 1}: wall={float(dt) / 60:6.2f} min | CPU {float(cpu) / 60:6.2f} min | "
            f"RSS pos={rss1} GB | USS pos={uss1} GB | threads={thr} | {n} linhas "
            f"(spawn pai: {time.perf_counter() - t0:.1f} s)",
            flush=True,
        )
    return tempos


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("parquet")
    ap.add_argument("--rodadas", type=int, default=5)
    ap.add_argument("--campos-json", default=None)
    ap.add_argument("--isolado", action="store_true",
                    help="cada rodada em um interpretador recem-criado (controle)")
    ap.add_argument("--silencioso", action="store_true", help="uso interno (modo isolado)")
    args = ap.parse_args()

    campos = json.loads(args.campos_json) if args.campos_json else CAMPOS_PADRAO

    if args.silencioso:
        m = rodar_uma_rodada(args.parquet, campos)
        uss1 = m["uss1"] if m["uss1"] is not None else float("nan")
        print(
            f"RESULT|{m['dt']:.1f}|{m['cpu']:.1f}|{m['rss1']:.2f}|{uss1:.2f}|{m['n']}|{m['threads']}",
            flush=True,
        )
        return

    modo = "subprocesso por rodada" if args.isolado else "mesmo processo"
    print(f"arquivo: {args.parquet} | rodadas: {args.rodadas} | modo: {modo}", flush=True)
    banner()

    if args.isolado:
        tempos = modo_isolado(args.parquet, campos, args.rodadas)
    else:
        tempos = []
        for i in range(args.rodadas):
            m = rodar_uma_rodada(args.parquet, campos)
            tempos.append(m["dt"])
            relatorio(f"rodada {i + 1}", m)

    veredito(tempos)


if __name__ == "__main__":
    main()
