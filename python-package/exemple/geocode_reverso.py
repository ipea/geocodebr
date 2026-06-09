import pyarrow as pa

from geocodebr import geocode_reverso


def main() -> None:
    pontos = pa.table(
        {
            "id": [1, 2, 3],
            "lon": [-43.3523, -43.1763, -47.8825],
            "lat": [-22.8327, -22.9046, -15.7942],
        }
    )

    resultado = geocode_reverso(
        pontos=pontos,
        dist_max=1000,
        verboso=True,
    )

    print(resultado)


if __name__ == "__main__":
    main()

