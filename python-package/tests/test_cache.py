from pathlib import Path

from geocodebr import definir_pasta_cache, listar_dados_cache, listar_pasta_cache


def test_cache_roundtrip(tmp_path):
    assert definir_pasta_cache(str(tmp_path), verboso=False) == str(tmp_path)
    assert listar_pasta_cache() == str(tmp_path)

    (tmp_path / "a.parquet").write_text("", encoding="utf-8")
    (tmp_path / "b.parquet").write_text("", encoding="utf-8")
    assert [Path(path).name for path in listar_dados_cache()] == ["a.parquet", "b.parquet"]

