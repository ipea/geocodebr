DATA_RELEASE = "v0.4.1"

ALL_CNEFE_FILES = [
    "municipio_logradouro_numero_localidade.parquet",
    "municipio_logradouro_numero_cep_localidade.parquet",
    "municipio.parquet",
    "municipio_cep.parquet",
    "municipio_cep_localidade.parquet",
    "municipio_localidade.parquet",
    "municipio_logradouro_cep_localidade.parquet",
    "municipio_logradouro_localidade.parquet",
]

RESERVED_COLUMN_NAMES = [
    "tempidgeocodebr", "lat", "lon", "precisao", "tipo_resultado",
    "desvio_metros", "endereco_encontrado", "logradouro_encontrado",
    "numero_encontrado", "cep_encontrado", "localidade_encontrada",
    "municipio_encontrado", "estado_encontrado", "similaridade_logradouro",
    "contagem_cnefe", "empate", "cod_setor"
]

