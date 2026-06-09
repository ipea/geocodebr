def inform(message: str, verboso: bool = True) -> None:
    if verboso:
        print(message)


def message_standardizing_addresses(verboso: bool = True) -> None:
    inform("Padronizando enderecos de entrada", verboso)


def message_baixando_cnefe(verboso: bool = True) -> None:
    inform("Baixando dados do CNEFE", verboso)


def message_usando_cnefe_local(verboso: bool = True) -> None:
    inform("Utilizando dados do CNEFE armazenados localmente", verboso)


def message_looking_for_matches(verboso: bool = True) -> None:
    inform("Geolocalizando enderecos", verboso)


def message_preparando_output(verboso: bool = True) -> None:
    inform("Preparando resultados", verboso)


def message_cache(verboso: bool = True) -> None:
    inform("Nenhum dado em cache local", verboso)

