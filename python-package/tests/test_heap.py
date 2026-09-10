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

MANIFESTO_SEM_WINDOWS_SETTINGS = (
    b'<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    b'<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">'
    b'</assembly>'
)
# folga para o insert do bloco <application><windowsSettings> completo
MANIFESTO_SEM_WINDOWS_SETTINGS = MANIFESTO_SEM_WINDOWS_SETTINGS.replace(
    b"</assembly>", b" " * 300 + b"</assembly>"
)


def corpo_manifesto() -> bytes:
    """Regiao que encontrar_manifesto() devolve: sem prologo e sem cauda."""
    return MANIFESTO[MANIFESTO.index(b"<assembly"):].rstrip()


@pytest.fixture(autouse=True)
def reseta_aviso():
    _heap._aviso_emitido = False
    yield
    _heap._aviso_emitido = False


@pytest.fixture
def win32(monkeypatch):
    monkeypatch.setattr(sys, "platform", "win32")


@pytest.fixture
def exe_legacy(tmp_path, monkeypatch, win32):
    exe = tmp_path / "python.exe"
    exe.write_bytes(b"MZ" + MANIFESTO)
    monkeypatch.setattr(_heap, "cores_disponiveis", lambda: 24)
    monkeypatch.setattr(_heap, "resolve_exe_base", lambda: str(exe))
    return exe


def test_tem_segment_heap_false_para_heap_legacy(exe_legacy):
    assert _heap.tem_segment_heap(str(exe_legacy)) is False


def test_tem_segment_heap_true_para_exe_patcheado(exe_legacy):
    exe_legacy.write_bytes(b"MZ" + _heap_patch.patch_manifesto(MANIFESTO))
    assert _heap.tem_segment_heap(str(exe_legacy)) is True


def test_tem_segment_heap_none_se_exe_ausente(win32):
    assert _heap.tem_segment_heap("nao-existe.exe") is None


def test_tem_segment_heap_none_fora_do_windows(monkeypatch, tmp_path):
    monkeypatch.setattr(sys, "platform", "linux")
    assert _heap.tem_segment_heap(str(tmp_path / "python.exe")) is None


def test_n_cores_limitado_no_heap_legacy(exe_legacy, capsys):
    assert _heap.n_cores_efetivo(None) == _heap.N_CORES_HEAP_LEGACY
    assert "heap NT legacy" in capsys.readouterr().err
    assert _heap.n_cores_efetivo(None) == _heap.N_CORES_HEAP_LEGACY
    assert capsys.readouterr().err == ""


def test_n_cores_explicito_respeitado(exe_legacy, capsys):
    assert _heap.n_cores_efetivo(8) == 8
    saida = capsys.readouterr().err
    assert "heap NT legacy" in saida
    assert "Mitig" not in saida


@pytest.mark.parametrize(
    ("cores", "esperado"),
    [(2, 2), (1, 1), (4, 4), (8, 4), (24, 4)],
)
def test_n_cores_nao_excede_cores_da_maquina(
    exe_legacy, monkeypatch, capsys, cores, esperado
):
    monkeypatch.setattr(_heap, "cores_disponiveis", lambda: cores)
    assert _heap.n_cores_efetivo(None) == esperado
    saida = capsys.readouterr().err
    assert f"limitadas a {esperado}" in saida


def test_cores_disponiveis_retorna_inteiro_positivo():
    cores = _heap.cores_disponiveis()
    assert isinstance(cores, int)
    assert cores >= 1


def test_n_cores_sem_aviso_com_segment_heap(tmp_path, monkeypatch, win32, capsys):
    exe = tmp_path / "python.exe"
    exe.write_bytes(b"MZ" + _heap_patch.patch_manifesto(MANIFESTO))
    monkeypatch.setattr(_heap, "resolve_exe_base", lambda: str(exe))
    assert _heap.n_cores_efetivo(None) is None
    assert capsys.readouterr().err == ""
    assert _heap.n_cores_efetivo(16) == 16
    assert capsys.readouterr().err == ""


def test_sem_aviso_fora_do_windows(monkeypatch, capsys):
    monkeypatch.setattr(sys, "platform", "linux")
    assert _heap.n_cores_efetivo(None) is None
    assert capsys.readouterr().err == ""


def test_patch_manifesto_mantem_tamanho_e_insere_heap_type():
    patcheado = _heap_patch.patch_manifesto(MANIFESTO)
    assert len(patcheado) == len(MANIFESTO)
    assert b"SegmentHeap</heapType>" in patcheado
    assert patcheado.count(b"</assembly>") == 1


def test_patch_manifesto_sem_windows_settings():
    patcheado = _heap_patch.patch_manifesto(MANIFESTO_SEM_WINDOWS_SETTINGS)
    assert len(patcheado) == len(MANIFESTO_SEM_WINDOWS_SETTINGS)
    assert b"SegmentHeap</heapType>" in patcheado


def test_patch_manifesto_ja_patcheado():
    with pytest.raises(ValueError):
        _heap_patch.patch_manifesto(_heap_patch.patch_manifesto(MANIFESTO))


def test_encontrar_manifesto_ignora_regiao_sem_namespace():
    falso = b"<assembly>outra coisa</assembly>"
    exe = falso + MANIFESTO + b"trailing"
    ini, fim = _heap_patch.encontrar_manifesto(exe)
    assert exe[ini:fim] == corpo_manifesto()


def test_encontrar_manifesto_ausente():
    with pytest.raises(ValueError):
        _heap_patch.encontrar_manifesto(b"sem manifesto aqui")


def test_criar_copia_fim_a_fim(tmp_path, win32):
    exe = tmp_path / "python.exe"
    exe.write_bytes(b"MZ" + MANIFESTO + b"\x00\x01")
    destino = tmp_path / _heap.NOME_COPIA_PATCH
    _heap_patch.criar_copia(str(exe), str(destino))
    originais = exe.read_bytes()
    copia = destino.read_bytes()
    assert len(copia) == len(originais)
    assert _heap.tem_segment_heap(str(destino)) is True
    ini, fim = _heap_patch.encontrar_manifesto(copia)
    assert copia[ini:fim] == _heap_patch.patch_manifesto(corpo_manifesto())
