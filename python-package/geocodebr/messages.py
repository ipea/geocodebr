from datetime import datetime

def inform(message: str, verboso: bool = True) -> None:
    if verboso:
        print(f"{datetime.now().strftime('%H:%M:%S')}: {message}")


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


def message_add_precision(verboso: bool = True) -> None:
    inform("Adicionando coluna de precisão", verboso)


def message_merge_input(verboso: bool = True) -> None:
    inform("Juntando com colunas do input", verboso)

def message_as_arrow(verboso: bool = True) -> None:
    inform("Materializando tabela final em arrow", verboso)

def message_fim(verboso: bool = True) -> None:
    inform("Finalizado", verboso)