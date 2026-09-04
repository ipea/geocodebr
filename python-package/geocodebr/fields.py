from __future__ import annotations

import polars as pl

ADDRESS_FIELDS = ("logradouro", "numero", "cep", "localidade", "municipio", "estado")


def definir_campos(
    estado: str,
    municipio: str,
    logradouro: str | None = None,
    numero: str | None = None,
    cep: str | None = None,
    localidade: str | None = None,
) -> dict[str, str | None]:
    values = {
        "logradouro": logradouro,
        "numero": numero,
        "cep": cep,
        "localidade": localidade,
        "municipio": municipio,
        "estado": estado,
    }
    for name, value in values.items():
        if value is not None and not isinstance(value, str):
            raise TypeError(f"{name} deve ser uma string ou None.")
    if all(value is None for value in values.values()):
        raise ValueError("Pelo menos um campo nao pode ser nulo.")
    return values


def assert_and_assign_address_fields(
    address_fields: dict[str, str | None],
    addresses_columns: list[str],
) -> dict[str, str | None]:
    if not isinstance(address_fields, dict):
        raise TypeError("campos_endereco deve ser um dict.")

    unknown = set(address_fields) - set(ADDRESS_FIELDS)
    if unknown:
        raise ValueError(f"Campos desconhecidos: {sorted(unknown)}.")

    missing_columns = [
        column
        for column in address_fields.values()
        if column is not None and column not in addresses_columns
    ]
    if missing_columns:
        raise ValueError(f"Colunas ausentes em enderecos: {missing_columns}.")

    complete = {field: address_fields.get(field) for field in ADDRESS_FIELDS}
    return complete


def fill_missing_fields(
    df_input: pl.DataFrame,
    campos_endereco: dict[str, str | None],
) -> tuple[pl.DataFrame, dict[str, str], list[str]]:
    """Preenche campos nao declarados com colunas-fantasma NA.

    Espelha ``r-package/R/geocode.R:224-243``: para cada campo em
    ``ADDRESS_FIELDS`` cujo valor em ``campos_endereco`` e ``None``, cria uma
    coluna ``<campo>_tempgeocodebr`` preenchida com ``NA``. Retorna tambem a
    lista de ``campos_nao_declarados`` -- usada no laço de matching para pular
    etapas cujas key_cols incluam um desses campos, e em
    ``tabelas_necessarias()`` para baixar apenas as tabelas de referencia
    relevantes.
    """
    campos = dict(campos_endereco)  # cópia
    campos_nao_declarados: list[str] = []
    for campo in ADDRESS_FIELDS:
        if campos.get(campo) is None:
            campos_nao_declarados.append(campo)
            placeholder = f"_{campo}_tempgeocodebr"
            df_input = df_input.with_columns(
                pl.lit(None, dtype=pl.Utf8).alias(placeholder)
            )
            campos[campo] = placeholder
    return df_input, campos, campos_nao_declarados

