import pytest
import requests
from pathlib import Path

from geocodebr import download_cnefe
from geocodebr.constants import ALL_CNEFE_FILES, DATA_RELEASE
from geocodebr.download_cnefe import _download_file
from geocodebr.errors import GeocodeBRError


class FakeResponse:
    def __init__(self, chunks, status_ok=True):
        self._chunks = chunks
        self._status_ok = status_ok

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return None

    def raise_for_status(self):
        if not self._status_ok:
            raise requests.HTTPError("404 Client Error")

    def iter_content(self, chunk_size):
        return iter(self._chunks)


def test_download_file_writes_and_renames(tmp_path, monkeypatch):
    monkeypatch.setattr(
        requests, "get",
        lambda *args, **kwargs: FakeResponse([b"abc", b"", b"def"]),
    )
    dest = tmp_path / "tabela.parquet"

    _download_file("http://fake/tabela.parquet", dest)

    assert dest.read_bytes() == b"abcdef"
    assert not dest.with_suffix(".parquet.part").exists()


def test_download_file_propagates_http_error(tmp_path, monkeypatch):
    monkeypatch.setattr(
        requests, "get",
        lambda *args, **kwargs: FakeResponse([], status_ok=False),
    )
    dest = tmp_path / "tabela.parquet"

    with pytest.raises(requests.HTTPError):
        _download_file("http://fake/tabela.parquet", dest)

    assert not dest.exists()


def test_download_cnefe_rejects_non_iterable(cache_tmp):
    with pytest.raises(TypeError, match="tabela"):
        download_cnefe(123, verboso=False)


def test_select_files_rejects_unknown_table():
    from geocodebr.download_cnefe import _select_files

    with pytest.raises(ValueError, match="municipio"):
        _select_files("nao_existe")


def test_select_files_accepts_empty_list():
    from geocodebr.download_cnefe import _select_files

    assert _select_files([]) == []


def test_select_files_all():
    from geocodebr.constants import ALL_CNEFE_FILES
    from geocodebr.download_cnefe import _select_files

    assert _select_files("todas") == ALL_CNEFE_FILES


def test_download_cnefe_with_and_without_cache(cache_tmp, monkeypatch):
    import sys

    monkeypatch.setattr(
        sys.modules["geocodebr.download_cnefe"], "_download_file",
        lambda url, dest: dest.write_bytes(b"fake"),
    )

    dir_with_cache = download_cnefe("municipio", verboso=False, cache=True)
    assert (
        Path(dir_with_cache) / f"geocodebr_data_release_{DATA_RELEASE}" / "municipio.parquet"
    ).exists()

    dir_without_cache = download_cnefe("municipio", verboso=False, cache=False)
    assert dir_without_cache != dir_with_cache
    assert (
        Path(dir_without_cache) / f"geocodebr_data_release_{DATA_RELEASE}" / "municipio.parquet"
    ).exists()


def test_download_cnefe_parallel_downloads_all_files(cache_tmp, monkeypatch):
    import sys

    monkeypatch.setattr(
        sys.modules["geocodebr.download_cnefe"], "_download_file",
        lambda url, dest: dest.write_bytes(b"fake"),
    )

    cache_dir = download_cnefe("todas", verboso=False, cache=True)
    data_dir = Path(cache_dir) / f"geocodebr_data_release_{DATA_RELEASE}"

    baixados = sorted(path.name for path in data_dir.iterdir())
    assert baixados == sorted(ALL_CNEFE_FILES)


def test_download_cnefe_wraps_download_errors(cache_tmp, monkeypatch):
    import sys

    def falha(url, dest):
        raise requests.HTTPError("500 Server Error")

    monkeypatch.setattr(
        sys.modules["geocodebr.download_cnefe"], "_download_file", falha
    )

    with pytest.raises(GeocodeBRError, match="CNEFE"):
        download_cnefe("municipio", verboso=False, cache=True)
