import pytest

from geocodebr.constants import ALL_CNEFE_FILES, DATA_RELEASE
from geocodebr.db import create_geocodebr_db
from geocodebr.tables import register_cnefe_table
from geocodebr.utils import (
    check_clean_colnames,
    find_cached_parquet,
    get_key_cols,
    get_prob_match_cutoff,
    get_reference_table,
    merge_results_to_input,
    normalize_h3_res,
    quote_ident,
    sql_string,
    tabelas_necessarias,
)


def test_normalize_h3_res_none():
    assert normalize_h3_res(None) == []


def test_normalize_h3_res_scalar_and_list():
    assert normalize_h3_res(3) == [3]
    assert normalize_h3_res((1, 2)) == [1, 2]


def test_normalize_h3_res_rejects_invalid_values():
    with pytest.raises(ValueError, match="h3_res"):
        normalize_h3_res(16)
    with pytest.raises(ValueError, match="h3_res"):
        normalize_h3_res([3, -1])


def test_sql_string_escapes_quotes():
    assert sql_string("OLHO D'AGUA") == "'OLHO D''AGUA'"


def test_get_key_cols_rejects_unknown_match_type():
    with pytest.raises(ValueError, match="desconhecido"):
        get_key_cols("zz99")


def test_get_prob_match_cutoff():
    assert get_prob_match_cutoff("pn01") == 0.85
    assert get_prob_match_cutoff("dn01") == 0.9


def test_find_cached_parquet_finds_release_file():
    files = [
        f"c/cache/geocodebr_data_release_{DATA_RELEASE}/municipio.parquet",
        f"c/cache/geocodebr_data_release_{DATA_RELEASE}/municipio_logradouro.parquet",
    ]
    found = find_cached_parquet(files, "municipio")
    assert found.endswith("municipio.parquet")


def test_find_cached_parquet_ignores_old_release():
    files = ["c/cache/geocodebr_data_release_v8/municipio.parquet"]
    with pytest.raises(FileNotFoundError, match="download_cnefe"):
        find_cached_parquet(files, "municipio")


def test_add_h3_columns_no_resolutions_keeps_table():
    con = create_geocodebr_db(db_path="memory")
    try:
        con.execute("CREATE TABLE t (lat DOUBLE, lon DOUBLE)")
        from geocodebr.utils import add_h3_columns

        add_h3_columns(con, "t", [])
        cols = [row[1] for row in con.execute("PRAGMA table_info('t')").fetchall()]
        assert cols == ["lat", "lon"]
    finally:
        con.close()


def test_quote_ident_rejects_invalid_sql_name():
    with pytest.raises(ValueError, match="invalido"):
        quote_ident("drop table")


def test_check_clean_colnames_rejects_special_chars():
    with pytest.raises(ValueError, match="rename"):
        check_clean_colnames(["ok", "coluna com espaco"])


def test_add_h3_columns_with_null_coordinate():
    con = create_geocodebr_db(db_path="memory")
    try:
        con.execute("CREATE TABLE t (lat DOUBLE, lon DOUBLE)")
        con.execute("INSERT INTO t VALUES (-15.8, NULL)")

        from geocodebr.utils import add_h3_columns

        add_h3_columns(con, "t", [3])
        value = con.execute("SELECT h3_03 FROM t").fetchone()[0]
        assert value is None
    finally:
        con.close()


# ---------------------------------------------------------------------------
# get_reference_table / tabelas_necessarias
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    ("match_type", "esperado"),
    [
        ("dn01", "municipio_logradouro_numero_cep_localidade"),
        ("da01", "municipio_logradouro_numero_cep_localidade"),
        ("pn01", "municipio_logradouro_numero_cep_localidade"),
        ("da02", "municipio_logradouro_numero_cep_localidade"),
        ("dn03", "municipio_logradouro_numero_cep_localidade"),
        ("pn03", "municipio_logradouro_numero_cep_localidade"),
        ("da03", "municipio_logradouro_numero_localidade"),
        ("dn04", "municipio_logradouro_numero_localidade"),
        ("da04", "municipio_logradouro_numero_localidade"),
        ("dl01", "municipio_logradouro_cep_localidade"),
        ("dl02", "municipio_logradouro_cep_localidade"),
        ("dl04", "municipio_logradouro_localidade"),
        ("dc01", "municipio_cep_localidade"),
        ("dc02", "municipio_cep"),
        ("db01", "municipio_localidade"),
        ("dm01", "municipio"),
    ],
)
def test_get_reference_table_mapping(match_type, esperado):
    assert get_reference_table(match_type) == esperado


def test_tabelas_necessarias_excludes_types_with_undeclared_field():
    # sem logradouro declarado, sobram so as etapas cep/localidade/municipio
    tabelas = tabelas_necessarias(["logradouro"])
    assert set(tabelas) == {
        "municipio_cep_localidade",
        "municipio_cep",
        "municipio_localidade",
        "municipio",
    }


def test_tabelas_necessarias_all_fields_cover_all_tables():
    tabelas = tabelas_necessarias([])
    assert len(tabelas) == len(set(tabelas))
    assert set(tabelas) <= {f.removesuffix(".parquet") for f in ALL_CNEFE_FILES}
    assert "municipio_logradouro_numero_localidade" in tabelas


# ---------------------------------------------------------------------------
# register_cnefe_table
# ---------------------------------------------------------------------------


def test_register_cnefe_table_filters_and_is_idempotent(
    match_env, cnefe_cache, cnefe_table
):
    cnefe_cache(
        cnefe_table(estado=["DF", "RJ"], municipio=["BRASILIA", "RIO DE JANEIRO"]),
        "municipio_logradouro_numero_localidade",
    )
    con = match_env.con
    match_env.insert_input([
        {"estado": "DF", "municipio": "BRASILIA", "logradouro": "RUA TESTE", "numero": 100},
    ])

    assert register_cnefe_table(con, "dn04", pasta_dados=match_env.pasta_dados) is True

    estados = [
        row[0] for row in con.execute(
            "SELECT estado FROM municipio_logradouro_numero_localidade"
        ).fetchall()
    ]
    assert estados == ["DF"]

    # segunda chamada nao recria nem duplica a tabela
    assert register_cnefe_table(con, "dn04", pasta_dados=match_env.pasta_dados) is True
    assert con.execute(
        "SELECT COUNT(*) FROM municipio_logradouro_numero_localidade"
    ).fetchone()[0] == 1


# ---------------------------------------------------------------------------
# merge_results_to_input
# ---------------------------------------------------------------------------


def _create_merge_tables(con):
    con.execute("""
        CREATE TEMP TABLE input_db (tempidgeocodebr INTEGER, nome TEXT)
    """)
    con.execute("INSERT INTO input_db VALUES (3, 'c'), (1, 'a'), (2, 'b')")
    con.execute("""
        CREATE TEMP TABLE output_db (
            tempidgeocodebr INTEGER, lat DOUBLE, lon DOUBLE, precisao TEXT,
            tipo_resultado TEXT, desvio_metros INTEGER, endereco_encontrado TEXT
        )
    """)
    con.execute(
        "INSERT INTO output_db VALUES "
        "(1, -15.8, -47.9, 'numero', 'dn01', 10, 'a'), "
        "(3, -15.9, -47.95, 'numero', 'dn01', 10, 'c')"
    )


def test_merge_results_to_input_preserves_input_order():
    # invariante 2: a ordem do output e a do input (por tempidgeocodebr,
    # usado no ORDER BY interno), independente da ordem de insercao.
    # tempidgeocodebr sai da projecao — 'nome' identifica as linhas
    con = create_geocodebr_db(db_path="memory")
    try:
        _create_merge_tables(con)
        merge_results_to_input(
            con,
            x="input_db",
            y="output_db",
            select_columns=["nome"],
            resultado_completo=False,
        )
        rows = con.execute("SELECT nome, lat FROM geocodebr_result").fetchall()
        assert rows == [("a", -15.8), ("b", None), ("c", -15.9)]
    finally:
        con.close()


def test_merge_results_to_input_keeps_unmatched_rows():
    # LEFT JOIN: input sem correspondencia vira linha com NA, nao e descartado
    con = create_geocodebr_db(db_path="memory")
    try:
        _create_merge_tables(con)
        merge_results_to_input(
            con,
            x="input_db",
            y="output_db",
            select_columns=["nome"],
            resultado_completo=False,
        )
        rows = con.execute("SELECT nome, lat FROM geocodebr_result").fetchall()
        assert len(rows) == 3
        assert rows[1] == ("b", None)
    finally:
        con.close()
