"""Detecção do heap NT do interpretador Python no Windows.

O python.exe embute no recurso RT_MANIFEST a declaração de heap; sem
<heapType>SegmentHeap</heapType>, o processo roda no heap NT legacy, que
degrada sob alocação/liberação multithread intensa do DuckDB
(duckdb/duckdb#24027; diagnóstico em quality_reports/diagnoses/).
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

NOME_COPIA_PATCH = "python-geocodebr-sh.exe"
N_CORES_HEAP_LEGACY = 4

_aviso_emitido = False


def resolve_exe_base() -> str:
    """Venv: o exe real é o da base (pegadinha do launcher); demais casos, sys.executable."""
    if sys.platform == "win32" and sys.prefix != sys.base_prefix:
        base = Path(sys.base_prefix) / "python.exe"
        if base.is_file():
            return str(base)
    return sys.executable


def tem_segment_heap(exe: str) -> bool | None:
    """True/False no Windows; None fora dele ou se o exe não puder ser lido.

    Procura o elemento XML completo, não a palavra solta: a string
    "SegmentHeap" fora do manifesto daria falso positivo e silenciaria o aviso.
    """
    if sys.platform != "win32":
        return None
    try:
        with open(exe, "rb") as fh:
            return b"SegmentHeap</heapType>" in fh.read()
    except OSError:
        return None


def cores_disponiveis() -> int:
    """Núcleos disponíveis ao processo no Windows.

    Respeita a affinity mask via GetProcessAffinityMask: um processo pinado
    em menos núcleos (ou rodando em container/VM com restrição) não deve
    receber mais workers que ela permite. Chamado apenas pelo
    n_cores_efetivo(), que só ativa no Windows.
    """
    try:
        import ctypes

        kernel32 = ctypes.windll.kernel32
        kernel32.GetCurrentProcess.restype = ctypes.c_void_p
        kernel32.GetProcessAffinityMask.restype = ctypes.c_int
        kernel32.GetProcessAffinityMask.argtypes = [
            ctypes.c_void_p,
            ctypes.POINTER(ctypes.c_size_t),
            ctypes.POINTER(ctypes.c_size_t),
        ]
        mascara = ctypes.c_size_t()
        sistema = ctypes.c_size_t()
        if kernel32.GetProcessAffinityMask(
            kernel32.GetCurrentProcess(),
            ctypes.byref(mascara),
            ctypes.byref(sistema),
        ) and mascara.value:
            return bin(mascara.value).count("1")
    except Exception:
        pass
    return os.cpu_count() or 1


def n_cores_efetivo(n_cores: int | None) -> int | None:
    """Aplica a mitigação de threads no Windows sem Segment Heap.

    No heap legacy a contenção de alocação multithread faz a curva tempo x
    threads ter mínimo em ~4-6 threads. Quando o usuário não definiu
    n_cores, limita ao ótimo empírico sem exceder os núcleos disponíveis ao
    processo — `SET threads` acima dos núcleos não é clampeado pelo DuckDB
    e só gera oversubscription. Valor explícito é respeitado. O aviso é
    emitido uma vez por sessão, mesmo com n_cores explícito.
    """
    global _aviso_emitido
    if sys.platform != "win32":
        return n_cores
    exe = resolve_exe_base()
    if tem_segment_heap(exe) is not False:
        return n_cores
    original = n_cores
    if original is None:
        n_cores = min(N_CORES_HEAP_LEGACY, cores_disponiveis())
    if not _aviso_emitido:
        _aviso_emitido = True
        print(_mensagem_aviso(exe, original, n_cores), file=sys.stderr)
    return n_cores


def _mensagem_aviso(exe: str, n_cores_original: int | None, n_cores_efetivo: int | None) -> str:
    linhas = [
        "[geocodebr] interpretador Python com heap NT legacy detectado "
        f"({exe}): no Windows, o DuckDB pode ter queda de performance e "
        "deterioração entre chamadas sucessivas de geocode().",
    ]
    if n_cores_original is None and n_cores_efetivo is not None:
        linhas.append(
            f"Mitigação aplicada: threads do DuckDB limitadas a "
            f"{n_cores_efetivo} nesta sessão (n_cores não definido)."
        )
    linhas.append(
        "Aceleração real: gere um interpretador com Segment Heap com "
        "python -m geocodebr._heap_patch\n"
        "e inicie a sessão pela cópia gerada (python-geocodebr-sh.exe). "
        'Veja a seção "Windows e performance" do README.'
    )
    return "\n".join(linhas)
