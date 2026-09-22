## Simula a função `padronizar_enderecos` do pacote enderecobr do R
## específica para o caso de uso do geocode

import warnings
import polars as pl
import enderecobr


# ---------------------------------------------------------------------------
# Helpers de pré-processamento por campo
#
# Cada helper recebe o DataFrame (quendo é necessário inspecionar o dtype)
# e o nome da coluna original, e retorna uma *expressão* Polars (pl.Expr) 
# pronta para uso em ``with_columns``.
# ---------------------------------------------------------------------------

def _col_to_str(col_name: str) -> pl.Expr:
    """Expressão que faz cast para Utf8 (preserva nulls)."""
    return pl.col(col_name).cast(pl.Utf8, strict=False)


def _padronizar_cep_expr(
    col_orig: str,
    enderecos: pl.DataFrame,
) -> pl.Expr:
    """Padroniza CEPs para o formato `xxxxx-xxx`.

    Binding Python do enderecobr:
    - ``padronizar_cep_numerico`` aceita int;
    - ``padronizar_cep`` aceita str (dá erro quando há caracteres inválidos e dígitos demais).
    """
    col = enderecos.get_column(col_orig)

    if col.dtype.is_integer():
        return pl.col(col_orig).map_elements(
            enderecobr.padronizar_cep_numerico,
            return_dtype=pl.Utf8,
        )

    return _col_to_str(col_orig).map_elements(
        enderecobr.padronizar_cep,
        return_dtype=pl.Utf8,
    )


def _padronizar_numero_expr(
    col_orig: str,
    enderecos: pl.DataFrame,
    formato: str,
) -> pl.Expr:
    """Padroniza números de logradouro e retorna no formato em `formato`.

    Binding Python:
    - ``padronizar_numeros_para_int`` (str -> int|None);
    - ``padronizar_numeros`` (str -> str; "S/N" para vazios/None);
    - ``padronizar_numeros_para_string`` (int -> str; 0 -> "S/N").
    """
    col = enderecos.get_column(col_orig)

    # Input numérico
    if col.dtype.is_integer():
        # Transforma 0 em nulo
        expr_sem_zero = pl.when(pl.col(col_orig) == 0).then(
            None
        ).otherwise(pl.col(col_orig))

        if formato == "integer":
            return expr_sem_zero.cast(pl.Int32, strict=False)

        # Para formato character: Null deve virar "S/N" e o fill_null(0) garante isso,
        # já que padronizar_numeros_para_string(0) -> "S/N".
        return expr_sem_zero.fill_null(0).map_elements(
            enderecobr.padronizar_numeros_para_string,
            return_dtype=pl.Utf8,
        )

    # Input em string
    if formato == "integer":
        # padronizar_numeros_para_int retorna None para 'S/N', vazio,
        # múltiplos números, etc. O bind pode devolver ints acima de Int32
        # (ex.: "0000003000524637"); o cast strict=False os converte em null,
        # emulando o NA do as.integer() do R (report de paridade 2026-09-21, §3.2).
        return _col_to_str(col_orig).map_elements(
            enderecobr.padronizar_numeros_para_int,
            return_dtype=pl.Int64,
        ).cast(pl.Int32, strict=False)

    # Para formato character: Nulo e vazio devem virar "S/N".
    # fill_null("") garante que null -> "" -> "S/N" via padronizar_numeros.
    return _col_to_str(col_orig).fill_null("").map_elements(
        enderecobr.padronizar_numeros,
        return_dtype=pl.Utf8,
    )


def _padronizar_estado_expr(
    col_orig: str,
    formato: str,
) -> pl.Expr:
    """Padroniza estados e retorna no formato em `formato`.

    Binding Python:
    - ``padronizar_estados_para_sigla`` (str -> sigla, ex: 'RJ');
    - ``padronizar_estados_para_nome`` (str -> nome, ex: 'RIO DE JANEIRO').

    Pré-processamento: cast para str (a coluna pode ser int, ex: código UF).
    """
    if formato == "sigla":
        func = enderecobr.padronizar_estados_para_sigla
    elif formato == "por_extenso":
        func = enderecobr.padronizar_estados_para_nome
    else:  # pragma: no cover -- validado na funcao publica antes de chegar aqui
        raise ValueError(
            f"formato_estados deve ser 'sigla' ou 'por_extenso', recebeu '{formato}'."
        )

    return _col_to_str(col_orig).map_elements(func, return_dtype=pl.Utf8)


def _padronizar_municipio_expr(
    col_orig: str,
) -> pl.Expr:
    """Padroniza municípios e retorna o nome por extenso.

    Pode receber nome por extenso, sigla e código do IBGE como int ou str.

    Binding Python: ``padronizar_municipios`` (str -> str).

    Pré-processamento: cast para str (a coluna pode ser int, ex: código IBGE).
    """
    return _col_to_str(col_orig).map_elements(
        enderecobr.padronizar_municipios,
        return_dtype=pl.Utf8,
    )


def _padronizar_str_expr(
    col_orig: str,
    func,
) -> pl.Expr:
    """Padroniza campos de string simples (logradouro, localidade, etc.).

    Pré-processamento: apenas cast para str. Nulls são preservados pelo
    ``map_elements``.
    """
    return _col_to_str(col_orig).map_elements(func, return_dtype=pl.Utf8)


def enderecobr_padronizar_enderecos(
    enderecos: pl.DataFrame,
    campos_do_endereco: dict[str, str],
    formato_estados: str = "sigla",
    formato_numeros: str = "integer",
    manter_cols_extras: bool = True,
) -> pl.DataFrame:
    """
    Padroniza os campos de endereço em um DataFrame. Por padrão, 
    padroniza CEP para string no formato `xxxxx-xxx`, estado para 
    sigla e número para inteiro.
    
    Espelha ``enderecobr::padronizar_enderecos`` do R.

    Parameters
    ----------
    enderecos:
        DataFrame Polars com os endereços.
    campos_do_endereco:
        Dicionário mapeando nome do campo (``"logradouro"``, ``"numero"``,
        ``"cep"``, ``"localidade"``, ``"municipio"``, ``"estado"``, etc.) para
        o nome da coluna em ``enderecos``.
    formato_estados:
        ``"sigla"`` ou ``"por_extenso"``.
    formato_numeros:
        ``"character"`` ou ``"integer"``.
    manter_cols_extras:
        Se ``True``, mantém colunas não especificadas em
        ``campos_do_endereco``.

    Returns
    -------
    pl.DataFrame
        DataFrame com as colunas ``*_padr`` adicionadas.
    """

    if not isinstance(enderecos, pl.DataFrame):
        raise TypeError("enderecos deve ser um pl.DataFrame.")
    if formato_estados not in ("sigla", "por_extenso"):
        raise ValueError("formato_estados deve ser 'sigla' ou 'por_extenso'.")
    if formato_numeros not in ("character", "integer"):
        raise ValueError("formato_numeros deve ser 'character' ou 'integer'.")

    enderecos_padrao = enderecos.clone()

    # Construir lista de expressões para with_columns
    exprs: list[pl.Expr] = []
    campos_processados: list[str] = []

    # Lista de tuplas com (nome padrão do campo, helper function e  dicionário de argumentos extras)
    relacao_campos = [
        ("logradouro", _padronizar_str_expr, {"func": enderecobr.padronizar_logradouros}),
        ("numero", _padronizar_numero_expr, {"enderecos": enderecos_padrao, "formato": formato_numeros}),
        ("cep", _padronizar_cep_expr, {"enderecos": enderecos_padrao}),
        ("localidade", _padronizar_str_expr, {"func": enderecobr.padronizar_bairros}),
        ("municipio", _padronizar_municipio_expr, {}),
        ("estado", _padronizar_estado_expr, {"formato": formato_estados})
    ]

    for campo, funcao, args_extras in relacao_campos:
        coluna_original = campos_do_endereco.get(campo, "não encontrado")
        if coluna_original in enderecos_padrao.columns:
            exprs.append(
                funcao(coluna_original, **args_extras).alias(f"{campo}_padr")
            )
            campos_processados.append(f"{campo}_padr")

    enderecos_padrao = enderecos_padrao.with_columns(*exprs)

    # Warning para números não convertíveis (R: warning_conversao_invalida)
    # Apenas para string -> integer: se houver mais nulls no resultado
    # do que no input, alguns números não puderam ser convertidos.
    if "numero" in campos_do_endereco and formato_numeros == "integer":
        col = enderecos.get_column(campos_do_endereco["numero"])
        if not col.dtype.is_integer():
            result_nulls = enderecos_padrao.get_column("numero_padr").null_count()
            input_nulls = col.null_count()
            if result_nulls > input_nulls:
                warnings.warn(
                    "Alguns números não puderam ser convertidos para "
                    "integer, introduzindo NAs no resultado.",
                    stacklevel=2,
                )

    # Colunas extras
    if not manter_cols_extras:
        enderecos_padrao = enderecos_padrao.select(campos_processados)

    return enderecos_padrao
