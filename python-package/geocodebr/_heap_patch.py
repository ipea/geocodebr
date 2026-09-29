"""Cria cópia do interpretador Python base com Segment Heap habilitado.

Uso (Windows):

    python -m geocodebr._heap_patch

Cria `python-geocodebr-sh.exe` ao lado do interpretador base, patcheando o
recurso RT_MANIFEST com <heapType>SegmentHeap</heapType> — o original nunca é
alterado. O ganho de performance do DuckDB vale apenas para sessões iniciadas
pela cópia: o heap é fixado no image load, não muda em runtime.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

from ._heap import NOME_COPIA_PATCH, resolve_exe_base, tem_segment_heap

_ELEMENTO_HEAP = (
    b'<heapType xmlns="http://schemas.microsoft.com/SMI/2020/WindowsSettings">'
    b"SegmentHeap</heapType>"
)
_ABRE_ASSEMBLY = b"<assembly"
_FECHA_ASSEMBLY = b"</assembly>"
_NS_ASSEMBLY = b"urn:schemas-microsoft-com:asm.v1"
_BLOCO_APPLICATION = (
    b'<application xmlns="urn:schemas-microsoft-com:asm.v3">'
    b"<windowsSettings>" + _ELEMENTO_HEAP + b"</windowsSettings></application>"
)
_COMPIME_ENTRE_TAGS = re.compile(rb">\s+<")


def main(argv: list[str] | None = None) -> int:
    if argv:
        print("[geocodebr] uso: python -m geocodebr._heap_patch (sem argumentos).", file=sys.stderr)
        return 2
    if sys.platform != "win32":
        print("[geocodebr] o patch de Segment Heap e exclusivo do Windows.", file=sys.stderr)
        return 1

    exe = resolve_exe_base()
    print(f"[geocodebr] interpretador base: {exe}")

    heap = tem_segment_heap(exe)
    if heap is True:
        print("[geocodebr] o interpretador base ja declara SegmentHeap; nada a fazer.")
        return 0
    if heap is None:
        print("[geocodebr] nao foi possivel ler o interpretador base.", file=sys.stderr)
        return 1

    destino = str(Path(exe).with_name(NOME_COPIA_PATCH))
    try:
        criar_copia(exe, destino)
    except ValueError as e:
        print(f"[geocodebr] {e}", file=sys.stderr)
        return 1
    except OSError as e:
        print(
            f"[geocodebr] falha ao escrever a copia ({e}). Se o interpretador estiver "
            "em pasta protegida (ex.: Program Files), use um terminal como "
            "administrador ou uma instalacao por usuario.",
            file=sys.stderr,
        )
        return 1

    print(f"[geocodebr] copia criada: {destino}")
    print(
        "[geocodebr] para acelerar o geocode(), inicie a sessao pela copia "
        "(ex.: \"" + destino + "\" script.py). A copia usa os pacotes do ambiente "
        "base; veja a secao \"Windows e performance\" do README."
    )
    return 0


def criar_copia(exe: str, destino: str) -> None:
    """Lê o exe, patcheia o manifesto e grava a cópia; lança ValueError/OSError."""
    dados = Path(exe).read_bytes()
    ini, fim = encontrar_manifesto(dados)
    novo = patch_manifesto(dados[ini:fim])
    patcheado = dados[:ini] + novo + dados[fim:]
    Path(destino).write_bytes(patcheado)
    if tem_segment_heap(destino) is not True:
        raise ValueError(
            "a copia gerada nao declara SegmentHeap; o patch foi abortado "
            "(o arquivo original nao foi alterado)."
        )


def encontrar_manifesto(dados: bytes) -> tuple[int, int]:
    """Localiza a região XML do RT_MANIFEST (start, end) no exe."""
    ini = dados.find(_ABRE_ASSEMBLY)
    while ini != -1:
        fim = dados.find(_FECHA_ASSEMBLY, ini)
        if fim != -1 and _NS_ASSEMBLY in dados[ini:fim]:
            return ini, fim + len(_FECHA_ASSEMBLY)
        ini = dados.find(_ABRE_ASSEMBLY, ini + 1)
    raise ValueError(
        "manifesto de aplicacao nao encontrado no interpretador; "
        "exe nao suportado pelo patch."
    )


def patch_manifesto(manifesto: bytes) -> bytes:
    """Insere <heapType>SegmentHeap</heapType> devolvendo EXATAMENTE o mesmo
    tamanho em bytes — o recurso RT_MANIFEST tem tamanho fixo no PE. O espaço
    entre tags é insignificante no XML: comprime a indentação e preenche o
    resto com espaços antes de </assembly>."""
    if b"<heapType" in manifesto:
        raise ValueError("o manifesto ja declara heapType; nada a fazer.")
    if b"</windowsSettings>" in manifesto:
        novo = manifesto.replace(b"</windowsSettings>", _ELEMENTO_HEAP + b"</windowsSettings>", 1)
    else:
        novo = manifesto.replace(_FECHA_ASSEMBLY, _BLOCO_APPLICATION + _FECHA_ASSEMBLY, 1)
    novo = _COMPIME_ENTRE_TAGS.sub(b"><", novo)
    faltam = len(manifesto) - len(novo)
    if faltam < 0:
        raise ValueError(
            "manifesto sem folga para o patch size-preserving; "
            "reporte em https://github.com/ipeaGIT/geocodebr/issues"
        )
    if faltam > 0:
        novo = novo.replace(_FECHA_ASSEMBLY, b" " * faltam + _FECHA_ASSEMBLY, 1)
    return novo


if __name__ == "__main__":  # pragma: no cover
    sys.exit(main(sys.argv[1:]))
