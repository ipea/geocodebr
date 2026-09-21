from datetime import datetime

def inform(message: str, verboso: bool = True) -> None:
    """Menssagem de progresso da pipeline: sujeito ao verboso, com timestamp."""
    if verboso:
        print(f"{datetime.now().strftime('%H:%M:%S')}: {message}")


def confirm(message: str) -> None:
    """Confirmação de ação explícita do usuário: sempre visível, sem timestamp."""
    print(message)


def message_standardizing_addresses(verboso: bool = True) -> None:
    inform("Padronizando endereços de entrada", verboso)


def message_downloading_cnefe(verboso: bool = True) -> None:
    inform("Baixando dados do CNEFE", verboso)


def message_using_local_cnefe(verboso: bool = True) -> None:
    inform("Utilizando dados do CNEFE armazenados localmente", verboso)


def message_looking_for_matches(verboso: bool = True) -> None:
    inform("Geolocalizando endereços", verboso)


def message_preparing_output(verboso: bool = True) -> None:
    inform("Preparando resultados", verboso)


def message_add_precision(verboso: bool = True) -> None:
    inform("Adicionando coluna de precisão", verboso)


def message_merge_input(verboso: bool = True) -> None:
    inform("Juntando com colunas do input", verboso)


def message_as_arrow(verboso: bool = True) -> None:
    inform("Materializando tabela final em arrow", verboso)


def message_closed_connection(verboso: bool = True) -> None:
    inform("Conexão fechada", verboso)
