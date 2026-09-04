"""Testes de regressão para o port das mudanças do NEWS.md (dev version).

Cada teste trava um bug específico corrigido nas Etapas A-G:
  1. test_geocode_empates_lag_under_300m        -> Etapa C (ponto 9): LEAD->LAG
  2. test_geocode_lograd_encontrado_sem_completo -> Etapa A (ponto 10)
  3. test_geocode_cache_false_uses_temp_dir      -> Etapa D (ponto 12)
  4. test_match_weighted_reproducible            -> Etapa B (ponto 2)
  5. test_geocode_pula_etapas_sem_logradouro     -> Etapa E (ponto 3)
  6. test_download_cnefe_lista_tabelas           -> Etapa E (ponto 5)
  7. test_jaro_redundant_skipped                 -> Etapa G (Jaro redundante)
"""
from __future__ import annotations

from pathlib import Path
from unittest.mock import patch

import pyarrow as pa
import pyarrow.parquet as pq

from geocodebr import definir_campos, definir_pasta_cache, geocode
from geocodebr.cache import caminho_parquet
from geocodebr.constants import (
    ALL_CNEFE_FILES,
    DATA_RELEASE,
    MATCH_TYPES_JARO_REDUNDANTE,
)


def _write_all_cnefe(data_dir: Path, table: pa.Table) -> None:
    """Escreve o mesmo parquet fake em todas as 8 tabelas do CNEFE."""
    for file in ALL_CNEFE_FILES:
        pq.write_table(table, data_dir / file)


def _base_cnefe_table(**overrides) -> pa.Table:
    """Cria uma tabela CNEFE fake mínima com defaults sobrescrevíveis."""
    cols = {
        "estado": ["DF"],
        "municipio": ["BRASILIA"],
        "logradouro": ["RUA TESTE"],
        "numero": [100],
        "cep": ["70000000"],
        "localidade": ["CENTRO"],
        "lon": [-47.9],
        "lat": [-15.8],
        "endereco_completo": ["RUA TESTE, 100 - CENTRO, BRASILIA - DF, 70000000"],
        "desvio_metros": [10],
        "n_casos": [1],
        "cod_setor": ["530010005000001"],
    }
    cols.update(overrides)
    return pa.table(cols)


# --------------------------------------------------------------------------- #
# Teste 1 — Etapa C (ponto 9): LEAD->LAG em empates <300m
# --------------------------------------------------------------------------- #
def test_geocode_empates_lag_under_300m(tmp_path):
    """2 candidatos a <300m entre si, com contagem_cnefe diferente.

    Antes do fix (LEAD), sobrevivia o de MENOR contagem (bug). Após o fix
    (LAG), sobrevive o de MAIOR contagem -- a linha de maior contagem tem
    id=1 e dist_geocodebr_metros=NULL, passando pelo filtro.
    """
    definir_pasta_cache(str(tmp_path), verboso=False)
    data_dir = tmp_path / f"geocodebr_data_release_{DATA_RELEASE}"
    data_dir.mkdir()

    # Dois candidatos proximos (<300m) mesmo logradouro/numero, bairros diferentes
    # contagem_cnefe diferente para que o LAG vs LEAD faça diferença
    cnefe = pa.table(
        {
            "estado": ["DF", "DF"],
            "municipio": ["BRASILIA", "BRASILIA"],
            "logradouro": ["RUA X", "RUA X"],
            "numero": [50, 50],
            "cep": ["70000000", "70000000"],
            "localidade": ["CENTRO", "ASA NORTE"],
            "lon": [-47.9000, -47.9010],
            "lat": [-15.8000, -15.8010],
            "endereco_completo": [
                "RUA X, 50 - CENTRO, BRASILIA - DF, 70000000",
                "RUA X, 50 - ASA NORTE, BRASILIA - DF, 70000000",
            ],
            "desvio_metros": [5, 5],
            "n_casos": [10, 1],
            "cod_setor": ["530010005000001", "530010005000002"],
        }
    )
    _write_all_cnefe(data_dir, cnefe)

    enderecos = pa.table(
        {
            "uf": ["DF"],
            "cidade": ["Brasilia"],
            "rua": ["Rua X"],
            "num": ["50"],
            "cep_in": ["70000-000"],
            "bairro": ["Centro"],
        }
    )
    campos = definir_campos(
        estado="uf", municipio="cidade", logradouro="rua",
        numero="num", cep="cep_in", localidade="bairro",
    )

    out = geocode(
        enderecos, campos, resultado_completo=True,
        resolver_empates=True, verboso=False,
    )

    assert out.num_rows == 1
    localidade = out.column("localidade_encontrada")[0].as_py()
    contagem = out.column("contagem_cnefe")[0].as_py()
    # LAG preserva o de MAIOR contagem (id=1, dist=NULL)
    assert contagem == 10, f"Expected contagem 10 (maior), got {contagem}"
    assert localidade == "CENTRO", f"Expected CENTRO, got {localidade}"


# --------------------------------------------------------------------------- #
# Teste 2 — Etapa A (ponto 10): logradouro_encontrado presente sem completo
# --------------------------------------------------------------------------- #
def test_geocode_lograd_encontrado_sem_completo(tmp_path):
    """logradouro_encontrado populado internamente mesmo com resultado_completo=False.

    logradouro_encontrado e coluna de trabalho interna (nao chega ao output
    final quando resultado_completo=False), usada por trata_empates para
    classificar empates em "perdidos" vs "salvaveis". Prova indireta: em um
    empate com max_dist > 1000 e logradouro NAO de data, o empate deve ir para
    "perdidos" (vence maior contagem_cnefe), nao para "salvaveis" (media
    ponderada). Se logradouro_encontrado estivesse NULL, o filtro
    `IS NOT NULL` em df_empates_perdidos falharia, mandando o caso para
    "salvaveis" -- resultado diferente.
    """
    definir_pasta_cache(str(tmp_path), verboso=False)
    data_dir = tmp_path / f"geocodebr_data_release_{DATA_RELEASE}"
    data_dir.mkdir()

    # 2 candidatos mesmo logradouro/numero/cep, bairros diferentes, >1000m entre si
    # 0.02 graus lat ~ 2.2km -> max_dist > 1000
    cnefe = pa.table(
        {
            "estado": ["DF", "DF"],
            "municipio": ["BRASILIA", "BRASILIA"],
            "logradouro": ["RUA X", "RUA X"],
            "numero": [50, 50],
            "cep": ["70000000", "70000000"],
            "localidade": ["CENTRO", "TAGUATINGA"],
            "lon": [-47.9000, -47.9200],
            "lat": [-15.8000, -15.8200],
            "endereco_completo": [
                "RUA X, 50 - CENTRO, BRASILIA - DF, 70000000",
                "RUA X, 50 - TAGUATINGA, BRASILIA - DF, 70000000",
            ],
            "desvio_metros": [5, 5],
            "n_casos": [10, 1],
            "cod_setor": ["530010005000001", "530010005000002"],
        }
    )
    _write_all_cnefe(data_dir, cnefe)

    enderecos = pa.table(
        {
            "uf": ["DF"], "cidade": ["Brasilia"],
            "rua": ["Rua X"], "num": ["50"],
            "cep_in": ["70000-000"], "bairro": ["Centro"],
        }
    )
    campos = definir_campos(
        estado="uf", municipio="cidade", logradouro="rua",
        numero="num", cep="cep_in", localidade="bairro",
    )

    out = geocode(
        enderecos, campos, resultado_completo=False,
        resolver_empates=True, verboso=False,
    )

    assert out.num_rows == 1
    # logradouro_encontrado e interno: NAO deve estar no output final
    assert "logradouro_encontrado" not in out.schema.names
    # Prova indireta: empate foi para "perdidos" (maior contagem vence),
    # nao "salvaveis" (media). lat/lon devem ser do candidato de contagem 10.
    lat = out.column("lat")[0].as_py()
    lon = out.column("lon")[0].as_py()
    assert lat == -15.8, f"Expected lat -15.8 (maior contagem), got {lat}"
    assert lon == -47.9, f"Expected lon -47.9 (maior contagem), got {lon}"


# --------------------------------------------------------------------------- #
# Teste 3 — Etapa D (ponto 12): cache=False usa dir temp
# --------------------------------------------------------------------------- #
def test_geocode_cache_false_uses_temp_dir(tmp_path):
    """cache=False deve ler do dir temp (retorno de download_cnefe), nao do
    cache persistente.

    Antes do fix, geocode() lia do cache persistente via
    listar_pasta_cache(), ignorando o retorno de download_cnefe -- resultando
    em 'IO Error: No files found' quando o cache persistente estava vazio.
    """
    # Cache persistente vazio (aponta para tmp_path, sem parquets)
    definir_pasta_cache(str(tmp_path / "persistente"), verboso=False)

    # Simula o tempdir que download_cnefe criaria com cache=False
    fake_temp = tmp_path / "temp_download"
    fake_data = fake_temp / f"geocodebr_data_release_{DATA_RELEASE}"
    fake_data.mkdir(parents=True)
    cnefe = _base_cnefe_table()
    _write_all_cnefe(fake_data, cnefe)

    enderecos = pa.table(
        {
            "uf": ["DF"], "cidade": ["Brasilia"],
            "rua": ["Rua Teste"], "num": ["100"],
            "cep_in": ["70000-000"], "bairro": ["Centro"],
        }
    )
    campos = definir_campos(
        estado="uf", municipio="cidade", logradouro="rua",
        numero="num", cep="cep_in", localidade="bairro",
    )

    import importlib

    geocode_mod = importlib.import_module("geocodebr.geocode")

    with patch.object(geocode_mod, "download_cnefe", return_value=str(fake_temp)):
        # Antes do fix, isto lancaria IO Error: No files found
        out = geocode_mod.geocode(
            enderecos, campos, resultado_completo=False,
            verboso=False, cache=False, n_cores=1,
        )

    assert out.num_rows == 1
    lat = out.column("lat")[0].as_py()
    lon = out.column("lon")[0].as_py()
    assert lat == -15.8, f"lat mismatch: {lat}"
    assert lon == -47.9, f"lon mismatch: {lon}"


# --------------------------------------------------------------------------- #
# Teste 4 — Etapa B (ponto 2): reprodutibilidade do match_weighted
# --------------------------------------------------------------------------- #
def test_match_weighted_reproducible(tmp_path):
    """Rodar geocode() duas vezes com mesmo input deve gerar lat/lon idênticos.

    Antes do fix (CASE WHEN BOOL_OR com FIRST sem ORDER BY determinístico), o
    DuckDB podia devolver coordenadas diferentes entre execuções em casos de
    interpolação (da*/pa*).
    """
    definir_pasta_cache(str(tmp_path), verboso=False)
    data_dir = tmp_path / f"geocodebr_data_release_{DATA_RELEASE}"
    data_dir.mkdir()

    # Dois candidatos com numeros diferentes para forçar interpolação (da02)
    # Sem localidade para que o match seja da02 (empate por bairro)
    cnefe = pa.table(
        {
            "estado": ["DF", "DF"],
            "municipio": ["BRASILIA", "BRASILIA"],
            "logradouro": ["RUA Y", "RUA Y"],
            "numero": [48, 52],
            "cep": ["70000000", "70000000"],
            "localidade": ["CENTRO", "ASA NORTE"],
            "lon": [-47.9000, -47.9020],
            "lat": [-15.8000, -15.8020],
            "endereco_completo": [
                "RUA Y, 48 - CENTRO, BRASILIA - DF, 70000000",
                "RUA Y, 52 - ASA NORTE, BRASILIA - DF, 70000000",
            ],
            "desvio_metros": [5, 5],
            "n_casos": [3, 7],
            "cod_setor": ["530010005000001", "530010005000002"],
        }
    )
    _write_all_cnefe(data_dir, cnefe)

    enderecos = pa.table(
        {
            "uf": ["DF"], "cidade": ["Brasilia"],
            "rua": ["Rua Y"], "num": ["50"],
            "cep_in": ["70000-000"],
        }
    )
    # Sem localidade -> key_cols de da02 nao incluem localidade -> empate
    campos = definir_campos(
        estado="uf", municipio="cidade", logradouro="rua",
        numero="num", cep="cep_in",
    )

    out1 = geocode(enderecos, campos, resultado_completo=True, verboso=False)
    out2 = geocode(enderecos, campos, resultado_completo=True, verboso=False)

    assert out1.num_rows == out2.num_rows == 1
    lat1, lat2 = out1.column("lat")[0].as_py(), out2.column("lat")[0].as_py()
    lon1, lon2 = out1.column("lon")[0].as_py(), out2.column("lon")[0].as_py()
    assert lat1 == lat2, f"lat não reprodutível: {lat1} vs {lat2}"
    assert lon1 == lon2, f"lon não reprodutível: {lon1} vs {lon2}"


# --------------------------------------------------------------------------- #
# Teste 5 — Etapa E (ponto 3): pula etapas sem logradouro
# --------------------------------------------------------------------------- #
def test_geocode_pula_etapas_sem_logradouro(tmp_path):
    """Input só com estado/municipio deve pular todas as etapas com logradouro.

    tipo_resultado deve ser 'dm01' (match por estado+municipio only).
    """
    definir_pasta_cache(str(tmp_path), verboso=False)
    data_dir = tmp_path / f"geocodebr_data_release_{DATA_RELEASE}"
    data_dir.mkdir()

    cnefe = pa.table(
        {
            "estado": ["DF"],
            "municipio": ["BRASILIA"],
            "lon": [-47.9],
            "lat": [-15.8],
            "endereco_completo": ["BRASILIA - DF"],
            "desvio_metros": [100],
            "n_casos": [5],
            "cod_setor": ["530010005000001"],
        }
    )
    _write_all_cnefe(data_dir, cnefe)

    enderecos = pa.table(
        {"uf": ["DF"], "cidade": ["Brasilia"]}
    )
    campos = definir_campos(estado="uf", municipio="cidade")

    out = geocode(enderecos, campos, resultado_completo=True, verboso=False)

    assert out.num_rows == 1
    tipos = out.column("tipo_resultado").to_pylist()
    assert tipos == ["dm01"], f"Expected ['dm01'], got {tipos}"


# --------------------------------------------------------------------------- #
# Teste 6 — Etapa E (ponto 5): download_cnefe com lista de tabelas
# --------------------------------------------------------------------------- #
def test_download_cnefe_lista_tabelas(tmp_path):
    """download_cnefe(['municipio','municipio_cep']) baixa só essas 2 tabelas."""
    definir_pasta_cache(str(tmp_path), verboso=False)

    import importlib

    download_mod = importlib.import_module("geocodebr.download_cnefe")

    # Monkeypatch _download_file para registrar o que foi baixado
    baixados: list[str] = []

    def fake_download(url, dest):
        baixados.append(Path(url).name)
        # Cria arquivo fake para simular download
        dest.write_bytes(b"fake")

    with patch.object(download_mod, "_download_file", side_effect=fake_download):
        download_mod.download_cnefe(["municipio", "municipio_cep"], verboso=False, cache=True)

    # Deve ter baixado exatamente 2 arquivos
    assert len(baixados) == 2, f"Expected 2 downloads, got {len(baixados)}: {baixados}"
    assert "municipio.parquet" in baixados
    assert "municipio_cep.parquet" in baixados
    # NAO deve ter baixado as outras 6
    assert "municipio_logradouro_cep_localidade.parquet" not in baixados


# --------------------------------------------------------------------------- #
# Teste 7 — Etapa G: Jaro redundante pulado em pa01/pa02/pa03
# --------------------------------------------------------------------------- #
def test_jaro_redundant_skipped():
    """calculate_string_dist NAO deve ser chamado para pa01/pa02/pa03.

    pa04 e pn0k devem continuar chamando (pa04 porque pn04 está desativado,
    pn0k porque é a etapa que preenche similaridade_logradouro inicialmente).
    """
    # Valida a constante
    assert MATCH_TYPES_JARO_REDUNDANTE == {"pa01", "pa02", "pa03"}
    assert "pa04" not in MATCH_TYPES_JARO_REDUNDANTE

    # Valida via inspeção de código que o guard está no lugar certo
    import inspect
    from geocodebr.matching import (
        match_weighted_cases_probabilistic,
        match_cases_probabilistic,
    )

    src_pa = inspect.getsource(match_weighted_cases_probabilistic)
    assert "MATCH_TYPES_JARO_REDUNDANTE" in src_pa, (
        "match_weighted_cases_probabilistic deve ter guard de Jaro redundante"
    )
    assert "if match_type not in" in src_pa

    # pn0k (match_cases_probabilistic) NAO deve ter o guard
    src_pn = inspect.getsource(match_cases_probabilistic)
    assert "MATCH_TYPES_JARO_REDUNDANTE" not in src_pn, (
        "match_cases_probabilistic (pn0k) não deve ter guard de Jaro"
    )


# --------------------------------------------------------------------------- #
# Teste bonus — Etapa D: helper caminho_parquet
# --------------------------------------------------------------------------- #
def test_caminho_parquet_helper():
    """caminho_parquet monta o path corretamente com pasta_dados explícito."""
    p = caminho_parquet("municipio", "/fake/cache")
    expected = f"/fake/cache/geocodebr_data_release_{DATA_RELEASE}/municipio.parquet"
    assert p == expected, f"Got {p}, expected {expected}"

    # Com None, deve usar listar_pasta_cache() como fallback
    p2 = caminho_parquet("municipio_cep")
    assert p2.endswith(
        f"/geocodebr_data_release_{DATA_RELEASE}/municipio_cep.parquet"
    )
