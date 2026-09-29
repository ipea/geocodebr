from pathlib import Path
from types import SimpleNamespace

import pyarrow as pa
import pyarrow.parquet as pq
import pytest

from geocodebr.cache import definir_pasta_cache, listar_arquivo_config
from geocodebr.constants import ALL_CNEFE_FILES, DATA_RELEASE
from geocodebr.db import create_geocodebr_db
from geocodebr.matching import create_output_db


@pytest.fixture(autouse=True)
def restore_cache_config():
    config_file = Path(listar_arquivo_config())
    existed = config_file.exists()
    content = config_file.read_text(encoding="utf-8") if existed else None
    yield
    if existed:
        config_file.parent.mkdir(parents=True, exist_ok=True)
        config_file.write_text(content, encoding="utf-8")
    elif config_file.exists():
        config_file.unlink()


@pytest.fixture
def restore_empty_config():
    config_file = Path(listar_arquivo_config())
    existed = config_file.exists()
    previous = config_file.read_text(encoding="utf-8") if existed else None
    if existed:
        config_file.unlink()
    yield
    if existed:
        config_file.parent.mkdir(parents=True, exist_ok=True)
        config_file.write_text(previous, encoding="utf-8")


@pytest.fixture
def cache_tmp(tmp_path):
    """Pasta de cache do pacote apontada para tmp_path (isolada por teste)."""
    definir_pasta_cache(str(tmp_path), verboso=False)
    return tmp_path


@pytest.fixture
def cnefe_cache(cache_tmp):
    """Grava tabelas CNEFE fake na pasta de dados do release.

    Factory: ``cnefe_cache(tabela)`` grava em todas as 8 tabelas do release;
    ``cnefe_cache(tabela, "municipio")`` grava apenas nas indicadas (nomes
    sem o sufixo ``.parquet``). Devolve a pasta ``geocodebr_data_release_*``.
    """
    data_dir = cache_tmp / f"geocodebr_data_release_{DATA_RELEASE}"
    data_dir.mkdir()

    def _factory(table: pa.Table, tabelas: str | list[str] | None = None) -> Path:
        if tabelas is None:
            targets = [data_dir / nome for nome in ALL_CNEFE_FILES]
        else:
            names = [tabelas] if isinstance(tabelas, str) else list(tabelas)
            targets = [data_dir / f"{nome}.parquet" for nome in names]
        for target in targets:
            pq.write_table(table, target)
        return data_dir

    return _factory


@pytest.fixture
def cnefe_table():
    """Tabela CNEFE fake mínima, com defaults sobrescrevíveis via kwargs.

    Valores escalares (ou listas de 1 elemento) sao replicados para o
    comprimento do maior argumento, permitindo tables multi-linha sem
    repetir todos os defaults.
    """
    def _factory(**overrides) -> pa.Table:
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
        n = max(len(v) if isinstance(v, (list, tuple)) else 1 for v in cols.values())
        expanded = {}
        for key, value in cols.items():
            if not isinstance(value, (list, tuple)):
                value = [value]
            if len(value) == 1:
                value = value * n
            expanded[key] = value
        return pa.table(expanded)

    return _factory


@pytest.fixture
def match_env(cache_tmp):
    """DuckDB em memoria com output_db criado e input_padrao_db populavel.

    Devolve um namespace com `con`, `pasta_dados` (raiz do cache, onde
    register_cnefe_table procura os parquets) e `insert_input(rows)`, que
    cria input_padrao_db a partir de uma lista de dicts no schema padrao —
    as colunas de trabalho do pipeline recebem defaults e o
    tempidgeocodebr e sequencial (1, 2, ...).
    """
    con = create_geocodebr_db(db_path="memory")
    create_output_db(con, resultado_completo=False)

    schema = pa.schema([
        ("tempidgeocodebr", pa.int32()),
        ("estado", pa.string()),
        ("municipio", pa.string()),
        ("logradouro", pa.string()),
        ("numero", pa.int32()),
        ("cep", pa.string()),
        ("localidade", pa.string()),
        ("log_causa_confusao", pa.bool_()),
        ("temp_lograd_determ", pa.string()),
        ("similaridade_logradouro", pa.float64()),
    ])
    defaults = {
        "estado": None,
        "municipio": None,
        "logradouro": None,
        "numero": None,
        "cep": None,
        "localidade": None,
        "log_causa_confusao": False,
        "temp_lograd_determ": None,
        "similaridade_logradouro": None,
    }

    def _insert_input(rows: list[dict]) -> None:
        normalizadas = [
            {**defaults, **row, "tempidgeocodebr": i}
            for i, row in enumerate(rows, start=1)
        ]
        table = pa.Table.from_pylist(normalizadas, schema=schema)
        con.register("novo_input", table)
        con.execute(
            "CREATE OR REPLACE TEMP TABLE input_padrao_db AS SELECT * FROM novo_input"
        )
        con.unregister("novo_input")

    env = SimpleNamespace(
        con=con,
        pasta_dados=str(cache_tmp),
        insert_input=_insert_input,
    )
    yield env
    con.close()
