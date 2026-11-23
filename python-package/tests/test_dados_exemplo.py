import hashlib
from pathlib import Path

import pyarrow as pa
import pytest

from geocodebr import caminho_dados_exemplo, carregar_dados_exemplo
from geocodebr.datasets import ARQUIVOS_EXEMPLO
from geocodebr.errors import GeocodeBRError

RAIZ_REPO = Path(__file__).resolve().parents[2]
EXTDATA_R = RAIZ_REPO / "r-package" / "inst" / "extdata"

SEM_CHECKOUT_R = not (EXTDATA_R / "small_sample.csv").exists()


def _md5(caminho: Path) -> str:
    return hashlib.md5(caminho.read_bytes()).hexdigest()


@pytest.mark.parametrize("nome", ARQUIVOS_EXEMPLO)
def test_caminho_dados_exemplo_aponta_para_o_arquivo(nome):
    caminho = Path(caminho_dados_exemplo(nome))
    assert caminho.is_file()
    assert caminho.name == nome
    assert caminho.parent.name == "extdata"


@pytest.mark.parametrize("nome", ARQUIVOS_EXEMPLO)
def test_carregar_dados_exemplo(nome):
    tabela = carregar_dados_exemplo(nome)
    assert isinstance(tabela, pa.Table)
    assert tabela.num_rows > 0


def test_carregar_dados_exemplo_padrao_e_small_sample():
    padrao = carregar_dados_exemplo()
    explicito = carregar_dados_exemplo("small_sample.csv")
    assert padrao.equals(explicito)


def test_carregar_dados_exemplo_rejeita_nome_desconhecido():
    with pytest.raises(GeocodeBRError, match="desconhecido"):
        carregar_dados_exemplo("nao_existe.csv")


@pytest.mark.skipif(
    SEM_CHECKOUT_R,
    reason="checkout não inclui r-package/ (ex.: pacote instalado do PyPI)",
)
@pytest.mark.parametrize("nome", ARQUIVOS_EXEMPLO)
def test_samples_embutidos_iguais_ao_pacote_r(nome):
    caminho_py = Path(caminho_dados_exemplo(nome))
    caminho_r = EXTDATA_R / nome
    assert _md5(caminho_py) == _md5(caminho_r), (
        f"'{nome}' divergiu entre python-package/geocodebr/extdata e "
        "r-package/inst/extdata; as duas cópias precisam ser atualizadas juntas"
    )
