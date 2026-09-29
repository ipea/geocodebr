import math

import pytest

from geocodebr.matching import (
    create_output_db,
    match_cases,
    match_cases_probabilistic,
    match_weighted_cases,
    select_match_function,
)


def test_select_match_function_dispatches_each_family():
    assert select_match_function("dn01").__name__ == "match_cases"
    assert select_match_function("dm01").__name__ == "match_cases"
    assert select_match_function("da02").__name__ == "match_weighted_cases"
    assert select_match_function("pn03").__name__ == "match_cases_probabilistic"
    assert (
        select_match_function("pa01").__name__ == "match_weighted_cases_probabilistic"
    )


def test_select_match_function_rejects_unknown_match_type():
    with pytest.raises(ValueError, match="sem funcao"):
        select_match_function("zz99")


# ---------------------------------------------------------------------------
# match_cases (join deterministico)
# ---------------------------------------------------------------------------


def test_match_cases_inserts_output_and_removes_from_input(
    match_env, cnefe_cache, cnefe_table
):
    cnefe_cache(cnefe_table(), "municipio_logradouro_numero_cep_localidade")
    con = match_env.con
    match_env.insert_input([
        {
            "estado": "DF",
            "municipio": "BRASILIA",
            "logradouro": "RUA TESTE",
            "numero": 100,
            "cep": "70000-000",
            "localidade": "CENTRO",
        },
        {
            "estado": "DF",
            "municipio": "BRASILIA",
            "logradouro": "RUA INEXISTENTE",
            "numero": 200,
            "cep": "70000-000",
            "localidade": "CENTRO",
        },
    ])

    n = match_cases(con, match_type="dn01", pasta_dados=match_env.pasta_dados)

    assert n == 1
    rows = con.execute(
        "SELECT tempidgeocodebr, lat, tipo_resultado FROM output_db"
    ).fetchall()
    assert rows == [(1, -15.8, "dn01")]
    # o nao-casado permanece no input para as etapas seguintes do laco
    restantes = con.execute(
        "SELECT tempidgeocodebr FROM input_padrao_db"
    ).fetchall()
    assert restantes == [(2,)]


def test_match_cases_excludes_null_key_column(match_env, cnefe_cache, cnefe_table):
    # key col nula (coluna-fantasma do geocode) exclui a linha do match,
    # mesmo com candidato identico no CNEFE
    cnefe_cache(cnefe_table(), "municipio_logradouro_numero_cep_localidade")
    con = match_env.con
    match_env.insert_input([
        {
            "estado": "DF",
            "municipio": "BRASILIA",
            "logradouro": "RUA TESTE",
            "numero": 100,
            "cep": "70000-000",
            "localidade": None,
        },
    ])

    n = match_cases(con, match_type="dn01", pasta_dados=match_env.pasta_dados)

    assert n == 0
    assert con.execute("SELECT COUNT(*) FROM output_db").fetchone()[0] == 0


def test_match_cases_multiple_candidates_produce_multiple_rows(
    match_env, cnefe_cache, cnefe_table
):
    # 2 candidatos para o mesmo input (diferem no cep): e o insumo do
    # trata_empates, que recebe mais de uma linha por tempidgeocodebr
    cnefe_cache(
        cnefe_table(cep=["70000-000", "70000-001"], lon=[-47.9, -47.95], n_casos=[10, 1]),
        "municipio_logradouro_numero_localidade",
    )
    con = match_env.con
    match_env.insert_input([
        {"estado": "DF", "municipio": "BRASILIA", "logradouro": "RUA TESTE", "numero": 100},
    ])

    n = match_cases(con, match_type="dn04", pasta_dados=match_env.pasta_dados)

    assert n == 1  # 1 input casou (as 2 linhas de output serao resolvidas pelo empates)
    rows = con.execute("SELECT tempidgeocodebr, lon FROM output_db").fetchall()
    assert sorted(rows) == [(1, -47.95), (1, -47.9)]


# ---------------------------------------------------------------------------
# match_weighted_cases (interpolação 1/ABS(numero - numero_cnefe))
# ---------------------------------------------------------------------------


def test_match_weighted_interpolates_by_distance(
    match_env, cnefe_cache, cnefe_table
):
    # candidatos a distancia 1 e 2 do numero inputado: pesos 1 e 0.5
    lat1, lat2 = -15.8, -15.9
    cnefe_cache(
        cnefe_table(
            numero=[49, 52],
            lat=[lat1, lat2],
            lon=[-47.9, -47.9],
            localidade=["CENTRO", "CENTRO"],
        ),
        "municipio_logradouro_numero_localidade",
    )
    con = match_env.con
    match_env.insert_input([
        {"estado": "DF", "municipio": "BRASILIA", "logradouro": "RUA TESTE", "numero": 50},
    ])

    n = match_weighted_cases(con, match_type="da04", pasta_dados=match_env.pasta_dados)

    assert n == 1
    lat, endereco = con.execute(
        "SELECT lat, endereco_encontrado FROM output_db"
    ).fetchone()
    assert lat == pytest.approx((lat1 * 1 + lat2 * 0.5) / 1.5)
    assert "50 (aprox)" in endereco


def test_match_weighted_equal_distances_yield_midpoint(
    match_env, cnefe_cache, cnefe_table
):
    lat1, lat2 = -15.8, -15.9
    cnefe_cache(
        cnefe_table(
            numero=[48, 52],
            lat=[lat1, lat2],
            lon=[-47.9, -47.9],
            localidade=["CENTRO", "CENTRO"],
        ),
        "municipio_logradouro_numero_localidade",
    )
    con = match_env.con
    match_env.insert_input([
        {"estado": "DF", "municipio": "BRASILIA", "logradouro": "RUA TESTE", "numero": 50},
    ])

    match_weighted_cases(con, match_type="da04", pasta_dados=match_env.pasta_dados)

    lat = con.execute("SELECT lat FROM output_db").fetchone()[0]
    assert lat == pytest.approx((lat1 + lat2) / 2)


def test_match_weighted_exact_number_yields_nan(match_env, cnefe_cache, cnefe_table):
    # numero exato no CNEFE: peso 1/0 = Inf -> lat NaN. E exatamente por isso
    # que todo da*/pa* so roda DEPOIS do dn*/pn* correspondente ter consumido
    # os matches exatos (invariante 1 da ordem do laco em all_possible_match_types)
    cnefe_cache(
        cnefe_table(numero=[50], localidade=["CENTRO"]),
        "municipio_logradouro_numero_localidade",
    )
    con = match_env.con
    match_env.insert_input([
        {"estado": "DF", "municipio": "BRASILIA", "logradouro": "RUA TESTE", "numero": 50},
    ])

    match_weighted_cases(con, match_type="da04", pasta_dados=match_env.pasta_dados)

    lat = con.execute("SELECT lat FROM output_db").fetchone()[0]
    assert math.isnan(lat)


# ---------------------------------------------------------------------------
# match_cases_probabilistic / calculate_string_dist
# ---------------------------------------------------------------------------


def _cnefe_rua_marco(cnefe_cache, cnefe_table, **overrides):
    """RUA MARCO no par de tabelas que pn01/pn02 consultam."""
    tabelas = [
        "municipio_logradouro_numero_cep_localidade",
        "municipio_logradouro_cep_localidade",
    ]
    cnefe_cache(cnefe_table(logradouro=["RUA MARCO"], **overrides), tabelas)


def test_match_probabilistic_matches_above_cutoff(match_env, cnefe_cache, cnefe_table):
    # Jaro('RUA CARLO', 'RUA MARCO') = 0.884: passa no corte 0.85 (pn01)
    cnefe_cache(
        cnefe_table(logradouro=["RUA MARCO"]),
        ["municipio_logradouro_numero_cep_localidade", "municipio_logradouro_cep_localidade"],
    )
    con = match_env.con
    create_output_db(con, resultado_completo=True)
    match_env.insert_input([
        {
            "estado": "DF",
            "municipio": "BRASILIA",
            "logradouro": "RUA CARLO",
            "numero": 100,
            "cep": "70000-000",
            "localidade": "CENTRO",
        },
    ])

    n = match_cases_probabilistic(
        con, match_type="pn01", resultado_completo=True, pasta_dados=match_env.pasta_dados
    )

    assert n == 1
    tipo, similaridade = con.execute(
        "SELECT tipo_resultado, similaridade_logradouro FROM output_db"
    ).fetchone()
    assert tipo == "pn01"
    assert similaridade == pytest.approx(0.884, abs=1e-3)


def test_match_probabilistic_rejects_below_cutoff(match_env, cnefe_cache, cnefe_table):
    # mesmo par, agora no corte 0.90 (pn02): 0.884 nao passa
    cnefe_cache(
        cnefe_table(logradouro=["RUA MARCO"]),
        ["municipio_logradouro_numero_cep_localidade", "municipio_logradouro_cep_localidade"],
    )
    con = match_env.con
    match_env.insert_input([
        {
            "estado": "DF",
            "municipio": "BRASILIA",
            "logradouro": "RUA CARLO",
            "numero": 100,
            "cep": "70000-000",
        },
    ])

    n = match_cases_probabilistic(
        con, match_type="pn02", pasta_dados=match_env.pasta_dados
    )

    assert n == 0
    assert con.execute("SELECT COUNT(*) FROM output_db").fetchone()[0] == 0
    # similaridade nao chegou a ser gravada
    temp_lograd = con.execute(
        "SELECT temp_lograd_determ FROM input_padrao_db"
    ).fetchone()[0]
    assert temp_lograd is None


def test_calculate_string_dist_tie_breaks_alphabetically(
    match_env, cnefe_cache, cnefe_table
):
    # Jaro('RUA MARCA', X) = 0.926 para MARCO, MARTA e MARIA: empate triplo,
    # resolvido pelo ORDER BY similarity DESC, logradouro_cnefe (MARCO vence)
    cnefe_cache(
        cnefe_table(
            logradouro=["RUA MARCO", "RUA MARTA", "RUA MARIA"],
            lat=[-15.8, -15.85, -15.9],
        ),
        ["municipio_logradouro_numero_cep_localidade", "municipio_logradouro_cep_localidade"],
    )
    con = match_env.con
    create_output_db(con, resultado_completo=True)
    match_env.insert_input([
        {
            "estado": "DF",
            "municipio": "BRASILIA",
            "logradouro": "RUA MARCA",
            "numero": 100,
            "cep": "70000-000",
            "localidade": "CENTRO",
        },
    ])

    n = match_cases_probabilistic(
        con, match_type="pn01", resultado_completo=True, pasta_dados=match_env.pasta_dados
    )

    assert n == 1
    lat, similaridade = con.execute(
        "SELECT lat, similaridade_logradouro FROM output_db"
    ).fetchone()
    assert lat == -15.8  # RUA MARCO, o alfabeticamente primeiro
    assert similaridade == pytest.approx(0.926, abs=1e-3)


def test_match_probabilistic_skips_already_computed_similarity(
    match_env, cnefe_cache, cnefe_table
):
    # similaridade pre-populada nao e recalculada (memoizacao entre etapas):
    # o join usa temp_lograd_determ='RUA VELHA', que nao existe no CNEFE
    cnefe_cache(
        cnefe_table(logradouro=["RUA MARCO"]),
        ["municipio_logradouro_numero_cep_localidade", "municipio_logradouro_cep_localidade"],
    )
    con = match_env.con
    match_env.insert_input([
        {
            "estado": "DF",
            "municipio": "BRASILIA",
            "logradouro": "RUA CARLO",
            "numero": 100,
            "cep": "70000-000",
            "localidade": "CENTRO",
            "temp_lograd_determ": "RUA VELHA",
            "similaridade_logradouro": 0.5,
        },
    ])

    n = match_cases_probabilistic(
        con, match_type="pn01", pasta_dados=match_env.pasta_dados
    )

    assert n == 0
    similaridade, temp_lograd = con.execute(
        "SELECT similaridade_logradouro, temp_lograd_determ FROM input_padrao_db"
    ).fetchone()
    assert (similaridade, temp_lograd) == (0.5, "RUA VELHA")


def test_match_probabilistic_excludes_confusion_flags(
    match_env, cnefe_cache, cnefe_table
):
    # logradouro ambiguo (RUA QUATRO etc.) fica fora do probabilistico
    cnefe_cache(
        cnefe_table(logradouro=["RUA MARCO"]),
        ["municipio_logradouro_numero_cep_localidade", "municipio_logradouro_cep_localidade"],
    )
    con = match_env.con
    match_env.insert_input([
        {
            "estado": "DF",
            "municipio": "BRASILIA",
            "logradouro": "RUA CARLO",
            "numero": 100,
            "cep": "70000-000",
            "localidade": "CENTRO",
            "log_causa_confusao": True,
        },
    ])

    n = match_cases_probabilistic(
        con, match_type="pn01", pasta_dados=match_env.pasta_dados
    )

    assert n == 0
    assert con.execute("SELECT COUNT(*) FROM output_db").fetchone()[0] == 0
