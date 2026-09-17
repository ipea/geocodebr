import geopandas as gpd

from geocodebr import geocode_reverso


def main() -> None:
    pontos = gpd.GeoDataFrame(
        {"id": [1, 2, 3]},
        geometry=gpd.points_from_xy(
            [-43.3523, -43.1763, -47.8825],
            [-22.8327, -22.9046, -15.7942],
        ),
        crs="EPSG:4674",
    )

    resultado = geocode_reverso(
        pontos=pontos,
        dist_max=1000,
        verboso=True,
    )

    print(resultado)


if __name__ == "__main__":
    main()
