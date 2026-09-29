import sys

import pytest
import pyarrow as pa


def test_arrow_to_geodataframe_requer_geopandas(monkeypatch):
    from geocodebr import geo

    monkeypatch.setitem(sys.modules, "geopandas", None)

    with pytest.raises(ImportError, match="geocodebr\\[geo\\]"):
        geo.arrow_to_geodataframe(pa.table({"lon": [-47.9], "lat": [-15.8]}))


def test_table_coords_to_geodataframe_requer_geopandas(monkeypatch):
    from geocodebr import geo

    monkeypatch.setitem(sys.modules, "geopandas", None)

    with pytest.raises(ImportError, match="geocodebr\\[geo\\]"):
        geo.table_coords_to_geodataframe(
            pa.table({"lon": [-47.9], "lat": [-15.8]}), "lon", "lat"
        )
