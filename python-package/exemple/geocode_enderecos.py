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

# consolidado
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

# tempos = []
# for i in range(10):
#     print(f"\n------- Rodada {i+1} --------\n\n")
#     inicio = time.perf_counter()
    # resultado = geocodebr.geocode(
    #     enderecos="data/consolidado_info.parquet",
    #     campos_endereco=campos,
    #     resultado_completo=True,
    #     resolver_empates=True,
    #     verboso=False,
    # )
#     fim = time.perf_counter()
#     total = (fim-inicio)/60
#     print(f"Tempo total: {total} minutos")
#     tempos.append(total) 

# ------- Rodada 1 --------
# Tempo total: 2.859974075000112 minutos

# ------- Rodada 2 --------
# Tempo total: 3.956586754999686 minutos

# ------- Rodada 3 --------
# Tempo total: 5.841610134999792 minutos

# ------- Rodada 4 --------
# Tempo total: 7.3003787733333105 minutos

# ------- Rodada 5 --------
# Tempo total: 10.941198263333353 minutos

# ------- Rodada 6 --------
# Tempo total: 14.277864210000068 minutos

# ------- Rodada 7 --------
# Tempo total: 17.765512603333626 minutos

# ------- Rodada 8 --------
# Tempo total: 20.07117651000008 minutos

# ------- Rodada 9 --------
# Tempo total: 25.223338793333095 minutos

# ------- Rodada 10 --------
# Tempo total: 30.754200243333376 minutos