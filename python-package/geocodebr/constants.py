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

RESERVED_COLUMN_NAMES = [
    "tempidgeocodebr", "lat", "lon", "precisao", "tipo_resultado",
    "desvio_metros", "endereco_encontrado", "logradouro_encontrado",
    "numero_encontrado", "cep_encontrado", "localidade_encontrada",
    "municipio_encontrado", "estado_encontrado", "similaridade_logradouro",
    "contagem_cnefe", "empate", "cod_setor"
]

NUMBER_EXACT_TYPES = {"dn01", "dn02", "dn03", "dn04"}
NUMBER_INTERPOLATION_TYPES = {"da01", "da02", "da03", "da04"}
PROBABILISTIC_EXACT_TYPES = {"pn01", "pn02", "pn03", "pn04"}
PROBABILISTIC_INTERPOLATION_TYPES = {"pa01", "pa02", "pa03", "pa04"}
EXACT_TYPES_NO_NUMBER = {"dl01", "dl02", "dl03", "dl04", "dc01", "dc02", "db01", "dm01"}
PROBABILISTIC_TYPES_NO_NUMBER = {"pl01", "pl02", "pl03", "pl04"}

# match_types cujos calculos de Jaro em calculate_string_dist() são redundantes: 
# a etapa "pn0k" imediatamente anterior em ALL_POSSIBLE_MATCH_TYPES ja testou os
# mesmos candidatos (mesmas key_cols, mesma tabela de referencia, mesmo corte)
# contra as linhas que sobraram, e preencheu similaridade_logradouro. Como
# calculate_string_dist() só recalcula onde similaridade_logradouro IS NULL,
# reexecutar em pa0k e um no-op garantido (ver
# quality_reports/diagnoses/2026-08-23_geocode-diagnostico-performance.md §6).
# NÃO inclui "pa04": pn04 está desativado, então não há etapa anterior que
# preencha similaridade_logradouro para pa04 reaproveitar.
MATCH_TYPES_JARO_REDUNDANTE = {"pa01", "pa02", "pa03"}

