"""Metadados da escada de matching: etapas, chaves e tabelas de referência.

Módulo puro (sem DuckDB, sem I/O) que descreve as 25 etapas do laço de
matching e mapeia cada ``match_type`` às suas colunas-chave e à tabela do
CNEFE correspondente. Consumido por ``matching``, ``tables``,
``string_dist`` e ``geocode``.
"""

from __future__ import annotations

import re

__all__ = [
    "ALL_POSSIBLE_MATCH_TYPES",
    "EXACT_TYPES_NO_NUMBER",
    "MATCH_TYPES_JARO_REDUNDANTE",
    "NUMBER_EXACT_TYPES",
    "NUMBER_INTERPOLATION_TYPES",
    "PROBABILISTIC_EXACT_TYPES",
    "PROBABILISTIC_INTERPOLATION_TYPES",
    "PROBABILISTIC_TYPES_NO_NUMBER",
    "get_key_cols",
    "get_prob_match_cutoff",
    "get_reference_table",
    "tabelas_necessarias",
]

# 25 etapas em ordem fixa, da mais precisa para a menos precisa. Toda etapa
# da* (interpolação) precisa ser precedida pela dn* correspondente: a
# interpolação divide por ABS(numero - numero_cnefe) e assume que os casos
# de número exato já foram consumidos.
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


def get_key_cols(match_type: str) -> list[str]:
    if match_type in {"dn01", "da01", "pn01", "pa01"}:
        return ["estado", "municipio", "logradouro", "numero", "cep", "localidade"]
    if match_type in {"dn02", "da02", "pn02", "pa02"}:
        return ["estado", "municipio", "logradouro", "numero", "cep"]
    if match_type in {"dn03", "da03", "pn03", "pa03"}:
        return ["estado", "municipio", "logradouro", "numero", "localidade"]
    if match_type in {"dn04", "da04", "pn04", "pa04"}:
        return ["estado", "municipio", "logradouro", "numero"]
    if match_type in {"dl01", "pl01"}:
        return ["estado", "municipio", "logradouro", "cep", "localidade"]
    if match_type in {"dl02", "pl02"}:
        return ["estado", "municipio", "logradouro", "cep"]
    if match_type in {"dl03", "pl03"}:
        return ["estado", "municipio", "logradouro", "localidade"]
    if match_type in {"dl04", "pl04"}:
        return ["estado", "municipio", "logradouro"]
    if match_type == "dc01":
        return ["estado", "municipio", "cep", "localidade"]
    if match_type == "dc02":
        return ["estado", "municipio", "cep"]
    if match_type == "db01":
        return ["estado", "municipio", "localidade"]
    if match_type == "dm01":
        return ["estado", "municipio"]
    raise ValueError(f"match_type desconhecido: {match_type}")


def get_reference_table(match_type: str) -> str:
    key_cols = get_key_cols(match_type)
    table_name = "_".join(key_cols).replace("estado_municipio", "municipio")

    if re.search(r"dn02|pn02|da02|pa02|dn03|pn03", match_type):
        table_name = "municipio_logradouro_numero_cep_localidade"
    if re.search(r"da03|pa03|dn04|da04", match_type):
        table_name = "municipio_logradouro_numero_localidade"
    if re.search(r"dl02|pl02|dl03|pl03", match_type):
        table_name = "municipio_logradouro_cep_localidade"
    if re.search(r"dl04", match_type):
        table_name = "municipio_logradouro_localidade"

    return table_name


def tabelas_necessarias(campos_nao_declarados: list[str]) -> list[str]:
    """Subconjunto de tabelas do CNEFE que o laço de matching vai usar.

    Espelha ``tabelas_necessarias()`` em ``r-package/R/utils.R:496-504``:
    filtra ``ALL_POSSIBLE_MATCH_TYPES`` excluindo os match_types cujas
    ``key_cols`` incluam algum campo em ``campos_nao_declarados``, mapeia
    via ``get_reference_table`` e dedup.
    """
    ativos = [
        mt
        for mt in ALL_POSSIBLE_MATCH_TYPES
        if not any(col in campos_nao_declarados for col in get_key_cols(mt))
    ]
    return list(dict.fromkeys(get_reference_table(mt) for mt in ativos))


def get_prob_match_cutoff(match_type: str) -> float:
    return 0.85 if match_type in {"pn01", "pa01", "pl01"} else 0.9
