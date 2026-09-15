from pathlib import Path

from geocodebr import (
    definir_pasta_cache,
    deletar_pasta_cache,
    listar_dados_cache,
    listar_pasta_cache,
)
from geocodebr.cache import (
    apaga_data_release_antigo,
    listar_pasta_cache_padrao,
)


def test_cache_roundtrip(tmp_path):
    assert definir_pasta_cache(str(tmp_path), verboso=False) == str(tmp_path)
    assert listar_pasta_cache() == str(tmp_path)

    (tmp_path / "a.parquet").write_text("", encoding="utf-8")
    (tmp_path / "b.parquet").write_text("", encoding="utf-8")
    assert [Path(path).name for path in listar_dados_cache()] == ["a.parquet", "b.parquet"]


def test_definir_pasta_cache_falls_back_to_default(restore_empty_config):
    assert listar_pasta_cache() == listar_pasta_cache_padrao()


def test_definir_pasta_cache_verboso_prints(tmp_path, capsys):
    definir_pasta_cache(str(tmp_path), verboso=True)
    assert "Definido como pasta de cache" in capsys.readouterr().out


def test_listar_dados_cache_missing_dir(restore_empty_config, capsys):
    definir_pasta_cache(str(Path(listar_pasta_cache_padrao()) / "nao_existe"), verboso=False)
    assert listar_dados_cache() == []
    assert "cache" in capsys.readouterr().out


def test_listar_dados_cache_print_tree(tmp_path, capsys):
    definir_pasta_cache(str(tmp_path), verboso=False)
    (tmp_path / "sub").mkdir()
    (tmp_path / "sub" / "a.parquet").write_text("", encoding="utf-8")

    listar_dados_cache(print_tree=True)

    out = capsys.readouterr().out
    assert "a.parquet" in out


def test_deletar_pasta_cache(tmp_path, capsys):
    definir_pasta_cache(str(tmp_path), verboso=False)
    (tmp_path / "a.parquet").write_text("", encoding="utf-8")

    deletar_pasta_cache()

    assert not tmp_path.exists()
    assert "Deletada" in capsys.readouterr().out


def test_apaga_data_release_antigo_removes_only_stale(tmp_path):
    definir_pasta_cache(str(tmp_path), verboso=False)
    (tmp_path / "geocodebr_data_release_v9").mkdir()
    (tmp_path / "geocodebr_data_release_v8").mkdir()
    (tmp_path / "outra_pasta").mkdir()

    apaga_data_release_antigo("v9")

    names = {path.name for path in tmp_path.iterdir()}
    assert names == {"geocodebr_data_release_v9", "outra_pasta"}


def test_apaga_data_release_antigo_missing_dir(tmp_path):
    definir_pasta_cache(str(tmp_path / "vazio"), verboso=False)
    result = apaga_data_release_antigo("v9")
    assert result == str(tmp_path / "vazio")

