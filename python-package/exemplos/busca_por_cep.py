from geocodebr import busca_por_cep


def main() -> None:
    ceps = [
        "70390-025",
        "20071-001",
        "21530-015",
        "99999-999",
    ]

    resultado = busca_por_cep(
        cep=ceps,
        h3_res=10,
        verboso=True,
    )

    print(resultado)


if __name__ == "__main__":
    main()

