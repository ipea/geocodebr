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

ALL_POSSIBLE_MATCH_TYPES = [
    "dn01",
    "da01",
    "pn01",
    "pa01",
    "dn02",
    "da02",
    "pn02",
    "pa02",
    "dn03",
    "da03",
    "pn03",
    "pa03",
    "dn04",
    "da04",
    "dl01",
    "pl01",
    "dl02",
    "pl02",
    "dl03",
    "pl03",
    "dl04",
    "dc01",
    "dc02",
    "db01",
    "dm01",
]

NUMBER_EXACT_TYPES = {"dn01", "dn02", "dn03", "dn04"}
NUMBER_INTERPOLATION_TYPES = {"da01", "da02", "da03", "da04"}
PROBABILISTIC_EXACT_TYPES = {"pn01", "pn02", "pn03", "pn04"}
PROBABILISTIC_INTERPOLATION_TYPES = {"pa01", "pa02", "pa03", "pa04"}
EXACT_TYPES_NO_NUMBER = {"dl01", "dl02", "dl03", "dl04", "dc01", "dc02", "db01", "dm01"}
PROBABILISTIC_TYPES_NO_NUMBER = {"pl01", "pl02", "pl03", "pl04"}

