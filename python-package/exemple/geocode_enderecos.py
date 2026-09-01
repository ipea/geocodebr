from pathlib import Path

from geocodebr import definir_campos, geocode


ROOT = Path(__file__).resolve().parent


def main() -> None:
    campos = definir_campos(
        logradouro="logradouro",
        numero="numero",
        cep="cep",
        localidade="localidade",
        municipio="municipio",
        estado="estado",
    )

    resultado = geocode(
        enderecos=ROOT / "enderecos.csv",
        campos_endereco=campos,
        resultado_completo=True,
        resolver_empates=True,
        h3_res=10,
        verboso=True,
    )

    cols = [
        "id",
        "logradouro",
        "numero",
        "cep",
        "localidade",
        "municipio",
        "estado",
        "lat",
        "lon",
        "precisao",
        "tipo_resultado",
        "cep_encontrado",
        "endereco_encontrado",
    ]
    print(resultado.select([col for col in cols if col in resultado.schema.names]))


if __name__ == "__main__":
    main()


# import geocodebr
# import time

# # consolidado
# campos = geocodebr.definir_campos(
#   estado = "uf_dom",
#   municipio = "codmun_dom",
#   logradouro = "logradouro_completo",
#   numero = "nroLogradouro",
#   cep = "cep",
#   localidade = "bairro"
# )

# # cadunico
# campos = geocodebr.definir_campos(
#   logradouro = 'logradouro',
#   numero = 'numero',
#   cep = 'cep',
#   localidade = 'bairro',
#   municipio = 'code_muni',
#   estado = 'abbrev_state'
# )

# inicio = time.perf_counter()
# resultado = geocodebr.geocode(
#         enderecos=r"",
#         campos_endereco=campos,
#         resultado_completo=True,
#         resolver_empates=True,
#         verboso=True,
#     )
# fim = time.perf_counter()