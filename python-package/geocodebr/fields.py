from __future__ import annotations


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

