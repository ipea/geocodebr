"""Testes de regressao para o port das mudanças do NEWS.md (dev version) - rodada 2.

Cada teste trava uma mudanca das Etapas A-E do plano
``quality_reports/plans/python-port-news-dev-version-2.md``:

  1. test_empates_resolver_false_inclui_coluna_empate   -> Etapa C (item 2):
     coluna ``empate`` no output com ``resolver_empates=False`` mesmo sem
     ``resultado_completo``.
  2. test_empates_zero_empates_resolver_false           -> Etapa C (item 2):
     ramo sem empates tambem devolve ``empate=False`` com ``resolver_empates=False``.
  3. test_geocode_rejeita_colunas_reservadas            -> Etapa D (item 3):
     input com coluna de nome reservado aborta com mensagem util.
  4. test_empates_rua_data_media_ponderada              -> Etapa B (item 4):
     rua com nome de data empatada a <1km e resolvida pela media ponderada
     (ramo F), nao pelo topo do ranking (ramo E/perdidos).
  5. test_rua_quatro_flagrada_como_confusao             -> Etapa E (item 5):
     "RUA QUATRO" seta ``log_causa_confusao`` (unitario sobre o DuckDB).
  6. test_geocode_rua_quatro_nao_casa_probabilistico    -> Etapa E (item 5):
     "RUA QUATRO" sem match exato nao casa por similaridade com
     "RUA QUATORZE"; cai para categoria de menor precisao (dc01/cep).
  7. test_empates_passthrough_mixed                     -> Etapa A (item 1):
     nao-empatados passam direto (``empate=FALSE``) e empatados proximos
     recebem media ponderada (``empate=TRUE``), uma linha por input.
"""
from __future__ import annotations

import duckdb
import pyarrow as pa
import pyarrow.parquet as pq
import pytest

from geocodebr import definir_campos, definir_pasta_cache, geocode
from geocodebr.constants import ALL_CNEFE_FILES, DATA_RELEASE
from geocodebr.utils import cria_col_logradouro_confusao


def _write_all_cnefe(data_dir, table: pa.Table) -> None:
    """Escreve o mesmo parquet fake em todas as 8 tabelas do CNEFE."""
    for file in ALL_CNEFE_FILES:
        pq.write_table(table, data_dir / file)


def _base_cnefe_table(**overrides) -> pa.Table:
    """Cria uma tabela CNEFE fake minima com defaults sobrescreveis."""
    cols = {
        "estado": ["DF"],
        "municipio": ["BRASILIA"],
        "logradouro": ["RUA TESTE"],
        "numero": [100],
        "cep": ["70000-000"],
        "localidade": ["CENTRO"],
        "lon": [-47.9],
        "lat": [-15.8],
        "endereco_completo": ["RUA TESTE, 100 - CENTRO, BRASILIA - DF, 70000-000"],
        "desvio_metros": [10],
        "n_casos": [1],
        "cod_setor": ["530010005000001"],
    }
    cols.update(overrides)
    return pa.table(cols)


def _prepare_cache(tmp_path):
    definir_pasta_cache(str(tmp_path), verboso=False)
    data_dir = tmp_path / f"geocodebr_data_release_{DATA_RELEASE}"
    data_dir.mkdir(exist_ok=True)
    return data_dir


# --------------------------------------------------------------------------- #
# Teste 1 - Etapa C (item 2): coluna empate com resolver_empates=False
# --------------------------------------------------------------------------- #
def test_empates_resolver_false_inclui_coluna_empate(tmp_path):
    """resolver_empates=False + resultado_completo=False inclui 'empate' no output.

    Antes da Etapa C, a coluna 'empate' era criada em output_db2 mas o
    merge_results_to_input so a selecionava quando resultado_completo=True --
    os casos empatados voltavam como linhas duplicadas sem identificacao (o
    aviso instruia a inspecionar uma coluna que nao chegava ao output).
    """
    data_dir = _prepare_cache(tmp_path)

    # 2 candidatos mesmo logradouro/numero (input 1); 1 candidato (input 2)
    cnefe = pa.table(
        {
            "estado": ["DF", "DF", "DF"],
            "municipio": ["BRASILIA", "BRASILIA", "BRASILIA"],
            "logradouro": ["RUA X", "RUA X", "RUA Z"],
            "numero": [50, 50, 10],
            "cep": ["70000-000", "70000-001", "70000-002"],
            "localidade": ["CENTRO", "TAGUATINGA", "CENTRO"],
            "lon": [-47.9, -47.92, -47.95],
            "lat": [-15.8, -15.82, -15.85],
            "endereco_completo": [
                "RUA X, 50 - CENTRO, BRASILIA - DF, 70000-000",
                "RUA X, 50 - TAGUATINGA, BRASILIA - DF, 70000-001",
                "RUA Z, 10 - CENTRO, BRASILIA - DF, 70000-002",
            ],
            "desvio_metros": [5, 5, 5],
            "n_casos": [10, 1, 3],
            "cod_setor": ["530010005000001", "530010005000002", "530010005000003"],
        }
    )
    _write_all_cnefe(data_dir, cnefe)

    # sem cep/localidade declarados -> dn04 casa os 2 candidatos de "RUA X"
    enderecos = pa.table(
        {
            "uf": ["DF", "DF"],
            "cidade": ["Brasilia", "Brasilia"],
            "rua": ["Rua X", "Rua Z"],
            "num": ["50", "10"],
        }
    )
    campos = definir_campos(estado="uf", municipio="cidade", logradouro="rua", numero="num")

    out = geocode(
        enderecos, campos,
        resultado_completo=False, resolver_empates=False, verboso=False,
    )

    # input 1 empatou: output tem 3 linhas (2 do empatado + 1 do nao empatado)
    assert out.num_rows == 3
    # coluna empate DEVE estar no output mesmo sem resultado_completo
    assert "empate" in out.schema.names
    empates = out.column("empate").to_pylist()
    # ordenado por tempidgeocodebr: input 1 (empatado) primeiro
    assert empates == [True, True, False], f"Expected [True, True, False], got {empates}"


# --------------------------------------------------------------------------- #
# Teste 2 - Etapa C (item 2): zero empates tambem devolve empate=False
# --------------------------------------------------------------------------- #
def test_empates_zero_empates_resolver_false(tmp_path):
    """Sem empates e resolver_empates=False: coluna empate=False no output.

    Trava o ramo n_casos==0 do trata_empates (ALTER output_db ADD empate
    DEFAULT FALSE) + incluir_empate no merge. Antes da reescrita, a coluna nem
    existia nesse caminho e o merge a selecionava de uma tabela sem ela.
    """
    data_dir = _prepare_cache(tmp_path)
    _write_all_cnefe(data_dir, _base_cnefe_table())

    enderecos = pa.table(
        {"uf": ["DF"], "cidade": ["Brasilia"], "rua": ["Rua Teste"], "num": ["100"]}
    )
    campos = definir_campos(estado="uf", municipio="cidade", logradouro="rua", numero="num")

    out = geocode(
        enderecos, campos,
        resultado_completo=False, resolver_empates=False, verboso=False,
    )

    assert out.num_rows == 1
    assert "empate" in out.schema.names
    assert out.column("empate").to_pylist() == [False]


# --------------------------------------------------------------------------- #
# Teste 3 - Etapa D (item 3): rejeita colunas de nomes reservados
# --------------------------------------------------------------------------- #
def test_geocode_rejeita_colunas_reservadas(tmp_path):
    """Input com coluna de nome reservado (ex.: 'lat') aborta cedo.

    Antes da guarda, o merge final produzia colunas duplicadas de mesmo nome e
    o pos-processamento (H3, sf) lia a coluna errada em silencio.
    """
    _prepare_cache(tmp_path)

    enderecos = pa.table(
        {
            "uf": ["DF"],
            "cidade": ["Brasilia"],
            "lat": [1.5],  # reservado: colide com o output do geocode()
        }
    )
    campos = definir_campos(estado="uf", municipio="cidade")

    with pytest.raises(ValueError, match="Reserved column names"):
        geocode(enderecos, campos, verboso=False)


# --------------------------------------------------------------------------- #
# Teste 4 - Etapa B (item 4): rua-data empatada a <1km -> media ponderada
# --------------------------------------------------------------------------- #
def test_empates_rua_data_media_ponderada(tmp_path):
    """"RUA QUINZE DE NOVEMBRO" empatada a <1 km resolve pela media ponderada.

    O nome bate no regex de numeros por extenso do ramo E ('RUA QUINZE'), mas a
    excecao de ruas-data impede o caso de ser classificado como 'perdido'.
    Antes do fix do escape \b, a excecao era codigo morto (nunca casava) e o
    empate ia para o ramo E (ficava so o topo do ranking); com a excecao viva
    no lugar certo (dentro do braco do regex de extenso), o caso cai no ramo F
    (media ponderada por contagem_cnefe).
    """
    data_dir = _prepare_cache(tmp_path)

    # 2 candidatos mesmo logradouro/numero, ~555m entre si (<1km, >300m)
    lat1, lat2 = -15.800, -15.805
    cnefe = pa.table(
        {
            "estado": ["DF", "DF"],
            "municipio": ["BRASILIA", "BRASILIA"],
            "logradouro": ["RUA QUINZE DE NOVEMBRO", "RUA QUINZE DE NOVEMBRO"],
            "numero": [50, 50],
            "cep": ["70000-000", "70000-001"],
            "localidade": ["CENTRO", "TAGUATINGA"],
            "lon": [-47.9, -47.9],
            "lat": [lat1, lat2],
            "endereco_completo": [
                "RUA QUINZE DE NOVEMBRO, 50 - CENTRO, BRASILIA - DF, 70000-000",
                "RUA QUINZE DE NOVEMBRO, 50 - TAGUATINGA, BRASILIA - DF, 70000-001",
            ],
            "desvio_metros": [5, 5],
            "n_casos": [10, 90],
            "cod_setor": ["530010005000001", "530010005000002"],
        }
    )
    _write_all_cnefe(data_dir, cnefe)

    # sem cep/localidade -> dn04 casa os 2 candidatos -> empate
    enderecos = pa.table(
        {
            "uf": ["DF"],
            "cidade": ["Brasilia"],
            "rua": ["Rua Quinze de Novembro"],
            "num": ["50"],
        }
    )
    campos = definir_campos(estado="uf", municipio="cidade", logradouro="rua", numero="num")

    out = geocode(enderecos, campos, resultado_completo=False, verboso=False)

    assert out.num_rows == 1
    # media ponderada por contagem_cnefe (10 e 90) -- NAO o topo do ranking
    lat_expected = (10 * lat1 + 90 * lat2) / 100
    lat_out = out.column("lat")[0].as_py()
    assert lat_out == pytest.approx(lat_expected), (
        f"lat deveria ser a media ponderada ({lat_expected}), veio {lat_out}"
    )


# --------------------------------------------------------------------------- #
# Teste 5 - Etapa E (item 5): "RUA QUATRO" flagrada como confusao (unitario)
# --------------------------------------------------------------------------- #
def test_rua_quatro_flagrada_como_confusao():
    """"RUA QUATRO" seta log_causa_confusao=TRUE (antes era lacuna da lista).

    'RUA DEZ' e o controle positivo (sempre esteve na lista) e 'RUA TESTE' o
    negativo. A excecao de datas segue valendo: 'RUA QUINZE DE NOVEMBRO' NAO e
    flagrada.
    """
    con = duckdb.connect()
    logradouros = pa.table(
        {
            "logradouro": [
                "RUA QUATRO",           # antes: lacuna -> nao flagrava
                "RUA DEZ",              # controle positivo
                "RUA TESTE",            # controle negativo
                "RUA QUINZE DE NOVEMBRO",  # excecao de rua-data
            ]
        }
    )
    con.register("input_view", logradouros)
    con.execute("CREATE TEMP TABLE input_padrao_db AS SELECT * FROM input_view")

    cria_col_logradouro_confusao(con)

    flags = {
        row[0]: row[1]
        for row in con.execute(
            "SELECT logradouro, log_causa_confusao FROM input_padrao_db"
        ).fetchall()
    }
    assert flags["RUA QUATRO"] is True, "'RUA QUATRO' deveria ser flagrada como confusao"
    assert flags["RUA DEZ"] is True
    assert flags["RUA TESTE"] is False
    assert flags["RUA QUINZE DE NOVEMBRO"] is False, (
        "rua com nome de data deve continuar escapando da flag"
    )
    con.close()


# --------------------------------------------------------------------------- #
# Teste 6 - Etapa E (item 5): "RUA QUATRO" nao casa via probabilistico
# --------------------------------------------------------------------------- #
def test_geocode_rua_quatro_nao_casa_probabilistico(tmp_path):
    """"RUA QUATRO" sem match exato nao casa por similaridade com "RUA QUATORZE".

    Jaro('RUA QUATRO', 'RUA QUATORZE') e alto (~0,94), acima de todos os
    cortes do pacote. Antes da Etapa E, o nome nao era flagrado como ambiguo e
    o match probabilistico aceitava o casamento (tipo pn01). Agora a linha e
    excluida do probabilistico e o caso cai para categoria de menor precisao
    (aqui dc01, casada por CEP).
    """
    data_dir = _prepare_cache(tmp_path)

    cnefe = _base_cnefe_table(
        logradouro=["RUA QUATORZE"],
        endereco_completo=["RUA QUATORZE, 100 - CENTRO, BRASILIA - DF, 70000-000"],
    )
    _write_all_cnefe(data_dir, cnefe)

    enderecos = pa.table(
        {
            "uf": ["DF"], "cidade": ["Brasilia"],
            "rua": ["Rua Quatro"], "num": ["100"],
            "cep_in": ["70000-000"], "bairro": ["Centro"],
        }
    )
    campos = definir_campos(
        estado="uf", municipio="cidade", logradouro="rua",
        numero="num", cep="cep_in", localidade="bairro",
    )

    out = geocode(enderecos, campos, resultado_completo=True, verboso=False)

    assert out.num_rows == 1
    tipo = out.column("tipo_resultado")[0].as_py()
    precisao = out.column("precisao")[0].as_py()
    assert tipo == "dc01", (
        f"'RUA QUATRO' nao deveria casar via probabilistico (pn01); veio {tipo}"
    )
    assert precisao == "cep"


# --------------------------------------------------------------------------- #
# Teste 7 - Etapa A (item 1): passthrough preserva nao-empatados
# --------------------------------------------------------------------------- #
def test_empates_passthrough_mixed(tmp_path):
    """Nao-empatados passam direto (empate=FALSE) e empatados proximos ->
    media ponderada (empate=TRUE), uma linha por input.

    Trava a estrutura do UNION ALL do output_db2 reescrito: D/E/F de
    empates_classif + passthrough dos que nunca empataram (FALSE AS empate na
    posicao correta quando resultado_completo=True).
    """
    data_dir = _prepare_cache(tmp_path)

    # input 1: "RUA PRINCIPAL" com candidato unico (passthrough)
    # input 2: "RUA DAS FLORES" com 2 candidatos a ~555m (nao ambiguo -> ramo F)
    # NAO usar logradouro de uma letra ("RUA X"): casa no regex de ambiguidade
    # de cria_col_logradouro_confusao ([A-Z]{1,2}) e o empate vai para o ramo E
    # (perdidos), nao para o F (media ponderada)
    lat1, lat2 = -15.800, -15.805
    cnefe = pa.table(
        {
            "estado": ["DF", "DF", "DF"],
            "municipio": ["BRASILIA", "BRASILIA", "BRASILIA"],
            "logradouro": ["RUA PRINCIPAL", "RUA DAS FLORES", "RUA DAS FLORES"],
            "numero": [10, 50, 50],
            "cep": ["70000-002", "70000-000", "70000-001"],
            "localidade": ["CENTRO", "CENTRO", "TAGUATINGA"],
            "lon": [-47.95, -47.9, -47.9],
            "lat": [-15.85, lat1, lat2],
            "endereco_completo": [
                "RUA PRINCIPAL, 10 - CENTRO, BRASILIA - DF, 70000-002",
                "RUA DAS FLORES, 50 - CENTRO, BRASILIA - DF, 70000-000",
                "RUA DAS FLORES, 50 - TAGUATINGA, BRASILIA - DF, 70000-001",
            ],
            "desvio_metros": [5, 5, 5],
            "n_casos": [3, 10, 90],
            "cod_setor": ["530010005000003", "530010005000001", "530010005000002"],
        }
    )
    _write_all_cnefe(data_dir, cnefe)

    enderecos = pa.table(
        {
            "uf": ["DF", "DF"],
            "cidade": ["Brasilia", "Brasilia"],
            "rua": ["Rua Principal", "Rua das Flores"],
            "num": ["10", "50"],
        }
    )
    campos = definir_campos(estado="uf", municipio="cidade", logradouro="rua", numero="num")

    out = geocode(enderecos, campos, resultado_completo=True, verboso=False)

    # uma linha por input (empate do input 2 resolvido pela media ponderada)
    assert out.num_rows == 2
    assert "empate" in out.schema.names
    empates = out.column("empate").to_pylist()
    assert empates == [False, True], f"Expected [False, True], got {empates}"

    # input 1: passthrough -- coordenada exata do CNEFE, sem window function
    assert out.column("lat")[0].as_py() == -15.85
    assert out.column("lon")[0].as_py() == -47.95

    # input 2: ramo F -- media ponderada por contagem_cnefe (10 e 90)
    lat_expected = (10 * lat1 + 90 * lat2) / 100
    assert out.column("lat")[1].as_py() == pytest.approx(lat_expected)
