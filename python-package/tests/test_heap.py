import sys
from pathlib import Path

import pytest

from geocodebr import _heap, _heap_patch


# manifesto real embutido no python.exe (CPython 3.10, uv) — o patch exige
# folga de whitespace para o insert size-preserving
MANIFESTO = b"""<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
  <trustInfo xmlns="urn:schemas-microsoft-com:asm.v3">
    <security>
      <requestedPrivileges>
        <requestedExecutionLevel level="asInvoker" uiAccess="false"/>
      </requestedPrivileges>
    </security>
  </trustInfo>
  <compatibility xmlns="urn:schemas-microsoft-com:compatibility.v1">
    <application>
      <supportedOS Id="{e2011457-1546-43c5-a5fe-008deee3d3f0}"/>
      <supportedOS Id="{35138b9a-5d96-4fbd-8e2d-a2440225f93a}"/>
      <supportedOS Id="{4a2f28e3-53b9-4441-ba9c-d69d4a4a6e38}"/>
      <supportedOS Id="{1f676c76-80e1-4239-95bb-83d0f6d0da78}"/>
      <supportedOS Id="{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}"/>
    </application>
  </compatibility>
  <application xmlns="urn:schemas-microsoft-com:asm.v3">
    <windowsSettings>
      <longPathAware xmlns="http://schemas.microsoft.com/SMI/2016/WindowsSettings">true</longPathAware>
    </windowsSettings>
  </application>
  <dependency>
    <dependentAssembly>
      <assemblyIdentity type="win32" name="Microsoft.Windows.Common-Controls"
                        version="6.0.0.0" processorArchitecture="*" publicKeyToken="6595b64144ccf1df" language="*" />
    </dependentAssembly>
  </dependency>
</assembly>
"""

MANIFESTO_WITHOUT_WINDOWS_SETTINGS = (
    b'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    b'<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">'
    b'</assembly>'
)
# folga para o insert do bloco <application><windowsSettings> completo
MANIFESTO_WITHOUT_WINDOWS_SETTINGS = MANIFESTO_WITHOUT_WINDOWS_SETTINGS.replace(
    b"</assembly>", b" " * 300 + b"</assembly>"
)


def manifest_body() -> bytes:
    """Regiao que encontrar_manifesto() devolve: sem prologo e sem cauda."""
    return MANIFESTO[MANIFESTO.index(b"<assembly"):].rstrip()


def write_exe(tmp_path, data: bytes) -> Path:
    exe = tmp_path / "python.exe"
    exe.write_bytes(b"MZ" + data)
    return exe


@pytest.fixture(autouse=True)
def reset_warning():
    _heap._aviso_emitido = False
    yield
    _heap._aviso_emitido = False


@pytest.fixture
def win32(monkeypatch):
    monkeypatch.setattr(sys, "platform", "win32")


@pytest.fixture
def exe_legacy(tmp_path, monkeypatch, win32):
    exe = write_exe(tmp_path, MANIFESTO)
    monkeypatch.setattr(_heap, "cores_disponiveis", lambda: 24)
    monkeypatch.setattr(_heap, "resolve_exe_base", lambda: str(exe))
    return exe


# ---------------------------------------------------------------------------
# deteccao de segment heap e limite de cores
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("patched", "esperado"),
    [(False, False), (True, True), (None, None)],
    ids=["legacy", "patched", "exe_ausente"],
)
def test_tem_segment_heap(tmp_path, win32, patched, esperado):
    exe = tmp_path / "python.exe"
    if patched is not None:
        data = _heap_patch.patch_manifesto(MANIFESTO) if patched else MANIFESTO
        exe.write_bytes(b"MZ" + data)
    assert _heap.tem_segment_heap(str(exe)) is esperado


def test_no_op_outside_windows(monkeypatch, tmp_path, capsys):
    monkeypatch.setattr(sys, "platform", "linux")
    assert _heap.tem_segment_heap(str(tmp_path / "python.exe")) is None
    assert _heap.n_cores_efetivo(None) is None
    assert capsys.readouterr().err == ""
    assert _heap_patch.main() == 1
    assert "exclusivo do Windows" in capsys.readouterr().err


def test_n_cores_on_legacy_heap(exe_legacy, capsys):
    assert _heap.n_cores_efetivo(None) == _heap.N_CORES_HEAP_LEGACY
    assert "heap NT legacy" in capsys.readouterr().err
    # aviso emitido uma unica vez por sessao
    assert _heap.n_cores_efetivo(None) == _heap.N_CORES_HEAP_LEGACY
    assert capsys.readouterr().err == ""
    # n_cores explicito e respeitado; o aviso (primeira chamada) nao anuncia
    # mitigacao porque o valor explicito nao foi alterado
    _heap._aviso_emitido = False
    assert _heap.n_cores_efetivo(8) == 8
    saida = capsys.readouterr().err
    assert "heap NT legacy" in saida
    assert "Mitig" not in saida


@pytest.mark.parametrize(
    ("cores", "esperado"),
    [(2, 2), (1, 1), (4, 4), (8, 4), (24, 4)],
)
def test_n_cores_capped_to_machine_cores(
    exe_legacy, monkeypatch, capsys, cores, esperado
):
    monkeypatch.setattr(_heap, "cores_disponiveis", lambda: cores)
    assert _heap.n_cores_efetivo(None) == esperado
    assert f"limitadas a {esperado}" in capsys.readouterr().err


def test_n_cores_no_warning_with_segment_heap(tmp_path, monkeypatch, win32, capsys):
    exe = write_exe(tmp_path, _heap_patch.patch_manifesto(MANIFESTO))
    monkeypatch.setattr(_heap, "resolve_exe_base", lambda: str(exe))
    assert _heap.n_cores_efetivo(None) is None
    assert capsys.readouterr().err == ""
    assert _heap.n_cores_efetivo(16) == 16
    assert capsys.readouterr().err == ""


def test_cores_disponiveis_fallback_when_winapi_fails(monkeypatch):
    import ctypes

    class WindllQuebrada:
        class kernel32:
            @staticmethod
            def GetCurrentProcess():
                raise RuntimeError("boom")

    monkeypatch.setattr(ctypes, "windll", WindllQuebrada, raising=False)
    cores = _heap.cores_disponiveis()
    assert isinstance(cores, int)
    assert cores >= 1


# ---------------------------------------------------------------------------
# patch_manifesto / encontrar_manifesto
# ---------------------------------------------------------------------------


def test_patch_manifesto_preserves_size_and_inserts_heap_type():
    patcheado = _heap_patch.patch_manifesto(MANIFESTO)
    assert len(patcheado) == len(MANIFESTO)
    assert b"SegmentHeap</heapType>" in patcheado
    assert patcheado.count(b"</assembly>") == 1


def test_patch_manifesto_without_windows_settings():
    patcheado = _heap_patch.patch_manifesto(MANIFESTO_WITHOUT_WINDOWS_SETTINGS)
    assert len(patcheado) == len(MANIFESTO_WITHOUT_WINDOWS_SETTINGS)
    assert b"SegmentHeap</heapType>" in patcheado


def test_patch_manifesto_on_already_patched_manifest():
    with pytest.raises(ValueError):
        _heap_patch.patch_manifesto(_heap_patch.patch_manifesto(MANIFESTO))


def test_patch_manifesto_without_slack():
    apertado = b'<assembly><windowsSettings></windowsSettings></assembly>'
    with pytest.raises(ValueError, match="sem folga"):
        _heap_patch.patch_manifesto(apertado)


def test_encontrar_manifesto_ignores_region_without_namespace():
    falso = b"<assembly>outra coisa</assembly>"
    exe = falso + MANIFESTO + b"trailing"
    ini, fim = _heap_patch.encontrar_manifesto(exe)
    assert exe[ini:fim] == manifest_body()


def test_encontrar_manifesto_missing():
    with pytest.raises(ValueError):
        _heap_patch.encontrar_manifesto(b"sem manifesto aqui")


# ---------------------------------------------------------------------------
# main()
# ---------------------------------------------------------------------------


def test_main_nothing_to_do_with_segment_heap(tmp_path, monkeypatch, win32, capsys):
    exe = write_exe(tmp_path, _heap_patch.patch_manifesto(MANIFESTO))
    monkeypatch.setattr(_heap_patch, "resolve_exe_base", lambda: str(exe))

    assert _heap_patch.main() == 0
    assert "nada a fazer" in capsys.readouterr().out


def test_main_creates_copy(tmp_path, monkeypatch, win32, capsys):
    exe = write_exe(tmp_path, MANIFESTO)
    monkeypatch.setattr(_heap_patch, "resolve_exe_base", lambda: str(exe))

    assert _heap_patch.main() == 0

    copia = Path(exe).with_name(_heap.NOME_COPIA_PATCH)
    assert copia.exists()
    assert _heap.tem_segment_heap(str(copia)) is True
    assert "copia criada" in capsys.readouterr().out


def _setup_exe_ilegivel(monkeypatch, tmp_path):
    monkeypatch.setattr(
        _heap_patch, "resolve_exe_base", lambda: str(tmp_path / "python.exe")
    )


def _setup_erro_valor_na_copia(monkeypatch, tmp_path):
    exe = write_exe(tmp_path, MANIFESTO)
    monkeypatch.setattr(_heap_patch, "resolve_exe_base", lambda: str(exe))

    def explode(exe, destino):
        raise ValueError("boom")

    monkeypatch.setattr(_heap_patch, "criar_copia", explode)


def _setup_erro_io_na_copia(monkeypatch, tmp_path):
    exe = write_exe(tmp_path, MANIFESTO)
    monkeypatch.setattr(_heap_patch, "resolve_exe_base", lambda: str(exe))

    def explode(exe, destino):
        raise OSError("sem permissao")

    monkeypatch.setattr(_heap_patch, "criar_copia", explode)


def _setup_copia_sem_segment_heap(monkeypatch, tmp_path):
    exe = write_exe(tmp_path, MANIFESTO)
    monkeypatch.setattr(_heap_patch, "resolve_exe_base", lambda: str(exe))
    monkeypatch.setattr(_heap_patch, "tem_segment_heap", lambda path: False)


@pytest.mark.parametrize(
    ("preparar", "codigo", "trecho_erro"),
    [
        (None, 2, "uso"),
        (_setup_exe_ilegivel, 1, "nao foi possivel"),
        (_setup_erro_valor_na_copia, 1, "boom"),
        (_setup_erro_io_na_copia, 1, "falha ao escrever"),
        (_setup_copia_sem_segment_heap, 1, "abortado"),
    ],
    ids=[
        "argumento_invalido",
        "exe_ilegivel",
        "erro_valor_na_copia",
        "erro_io_na_copia",
        "copia_sem_segment_heap",
    ],
)
def test_main_error_paths(monkeypatch, win32, tmp_path, capsys, preparar, codigo, trecho_erro):
    if preparar is not None:
        preparar(monkeypatch, tmp_path)
    assert _heap_patch.main([] if preparar else ["x"]) == codigo
    assert trecho_erro in capsys.readouterr().err


@pytest.mark.parametrize(
    ("cria_base", "esperado"),
    [(True, "base"), (False, "venv")],
    ids=["base_venv_existe", "base_ausente"],
)
def test_resolve_exe_base(tmp_path, monkeypatch, win32, cria_base, esperado):
    base_exe = tmp_path / "base" / "python.exe"
    if cria_base:
        base_exe.parent.mkdir()
        base_exe.write_bytes(b"MZ")
    monkeypatch.setattr(sys, "prefix", str(tmp_path / "venv"))
    monkeypatch.setattr(sys, "base_prefix", str(tmp_path / "base"))
    monkeypatch.setattr(sys, "executable", str(tmp_path / "venv" / "python.exe"))

    assert _heap.resolve_exe_base() == str(tmp_path / esperado / "python.exe")


# ---------------------------------------------------------------------------
# fim a fim
# ---------------------------------------------------------------------------


def test_criar_copia_end_to_end(tmp_path, win32):
    exe = write_exe(tmp_path, MANIFESTO + b"\x00\x01")
    destino = tmp_path / _heap.NOME_COPIA_PATCH
    _heap_patch.criar_copia(str(exe), str(destino))
    originais = exe.read_bytes()
    copia = destino.read_bytes()
    assert len(copia) == len(originais)
    assert _heap.tem_segment_heap(str(destino)) is True
    ini, fim = _heap_patch.encontrar_manifesto(copia)
    assert copia[ini:fim] == _heap_patch.patch_manifesto(manifest_body())
