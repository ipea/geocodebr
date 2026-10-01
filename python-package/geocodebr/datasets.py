from __future__ import annotations

from contextlib import ExitStack
from importlib import resources

import pyarrow as pa
import pyarrow.csv
import pyarrow.parquet

from .errors import GeocodeBRError

ARQUIVOS_EXEMPLO = [
    "small_sample.csv",
    "large_sample.parquet",
]

# `as_file` só extrai o arquivo para um temporário quando o pacote está
# compactado (zipimport); em instalação normal devolve o próprio caminho em
# site-packages. O ExitStack mantém vivos os temporários extraídos até o fim
# do processo, porque o caminho continua sendo usado após o retorno.
_recursos = ExitStack()


def caminho_dados_exemplo(nome: str) -> str:
    """Obtém o caminho de um arquivo de dados de exemplo embutido no pacote.

    São as mesmas amostras de endereços distribuídas com o pacote R em
    `inst/extdata`, úteis para testar o pacote sem precisar de uma base de
    endereços própria. Equivale ao `system.file("extdata", ..., package =
    "geocodebr")` do pacote R.

    Parameters
    ----------
    nome : str
        Nome do arquivo de exemplo. Disponíveis: `"small_sample.csv"` e
        `"large_sample.parquet"`.

    Returns
    -------
    str
        O caminho absoluto do arquivo embutido no pacote.

    Examples
    --------
    >>> import geocodebr
    >>> caminho = geocodebr.caminho_dados_exemplo("small_sample.csv")
    """
    _validar_nome(nome)
    alvo = resources.files("geocodebr").joinpath("extdata").joinpath(nome)
    return str(_recursos.enter_context(resources.as_file(alvo)))


def carregar_dados_exemplo(nome: str = "small_sample.csv") -> pa.Table:
    """Carrega um arquivo de dados de exemplo embutido no pacote.

    Parameters
    ----------
    nome : str, opcional
        Nome do arquivo de exemplo a carregar. O padrão é
        `"small_sample.csv"`.

    Returns
    -------
    pyarrow.Table
        O conteúdo do arquivo de exemplo, pronto para ser usado como input
        de `geocode()` com auxílio de `definir_campos()`.

    Examples
    --------
    >>> import geocodebr
    >>> enderecos = geocodebr.carregar_dados_exemplo("small_sample.csv")
    >>> campos = geocodebr.definir_campos(
    ...     estado="nm_uf",
    ...     municipio="nm_municipio",
    ...     logradouro="nm_logradouro",
    ...     numero="Numero",
    ...     cep="Cep",
    ...     localidade="Bairro",
    ... )
    """
    _validar_nome(nome)
    caminho = caminho_dados_exemplo(nome)
    if nome.endswith(".csv"):
        return pyarrow.csv.read_csv(caminho)
    return pyarrow.parquet.read_table(caminho)


def _validar_nome(nome: str) -> None:
    if nome not in ARQUIVOS_EXEMPLO:
        disponiveis = ", ".join(ARQUIVOS_EXEMPLO)
        raise GeocodeBRError(
            f"Arquivo de dados de exemplo desconhecido: '{nome}'. "
            f"Arquivos disponíveis: {disponiveis}."
        )
