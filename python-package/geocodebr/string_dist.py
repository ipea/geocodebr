from __future__ import annotations

import duckdb

from .match_types import (
    PROBABILISTIC_TYPES_NO_NUMBER,
    get_key_cols,
    get_prob_match_cutoff,
)
from .utils import quote_ident


def calculate_string_dist(
    con: duckdb.DuckDBPyConnection,
    match_type: str,
    unique_logradouros_tbl: str,
) -> None:
    key_cols = get_key_cols(match_type)
    cols_not_null = " AND ".join(f"input_padrao_db.{col} IS NOT NULL" for col in key_cols)
    lookup_cols = [col for col in key_cols if col not in {"numero", "logradouro"}]
    key_cols_sql = ", ".join(lookup_cols)
    min_cutoff = get_prob_match_cutoff(match_type)
    tbl = quote_ident(unique_logradouros_tbl)

    # in the steps without number (pl0k), rows with a filled numero were
    # already tested in the matching pn0k step -- same lookup key, same
    # unique_logr_* table and same cutoff -- and did not pass: recomputing Jaro
    # for them is a guaranteed no-op. If numero was not declared, the ghost
    # column is all NULL and the filter excludes nothing
    no_number_filter = (
        "AND input_padrao_db.numero IS NULL"
        if match_type in PROBABILISTIC_TYPES_NO_NUMBER
        else ""
    )

    # Jaro depends only on (lookup key, logradouro), not on tempidgeocodebr.
    # With a short key, many rows repeat the combination and it pays off to
    # compute once per distinct combination and join the result back. With
    # cep AND localidade (pn01/pl01) there is almost no repetition and the
    # join-back costs more than row-by-row Jaro: compute per tempidgeocodebr.
    # Mirrors calculate_string_dist() in r-package/R/string_dist.R
    if not {"cep", "localidade"} <= set(lookup_cols):
        sel_cols = f"DISTINCT {key_cols_sql}, logradouro AS logradouro_input"
        grp_cols = f"{key_cols_sql}, logradouro_input"
        upd_join = " AND ".join(
            [f"input_padrao_db.{col} = computed.{col}" for col in lookup_cols]
            + ["input_padrao_db.logradouro = computed.logradouro_input"]
        )
        # unique_logr_* is built with the longest key; with a shorter key the
        # same logradouro repeats and each repetition would cost one Jaro
        cand_src = f"(SELECT DISTINCT {key_cols_sql}, logradouro FROM {tbl})"
    else:
        sel_cols = f"tempidgeocodebr, {key_cols_sql}, logradouro AS logradouro_input"
        grp_cols = "tempidgeocodebr"
        upd_join = "input_padrao_db.tempidgeocodebr = computed.tempidgeocodebr"
        cand_src = tbl

    join_condition_pairs = " AND ".join(f"t.{col} = c.{col}" for col in lookup_cols)

    con.execute(
        f"""
        -- rows (or distinct key + logradouro combinations) that do not
        -- have a similarity yet
        WITH to_compute AS (
          SELECT {sel_cols}
          FROM input_padrao_db
          WHERE input_padrao_db.similaridade_logradouro IS NULL
            AND input_padrao_db.log_causa_confusao = FALSE
            AND {cols_not_null}
            {no_number_filter}
        ),
        -- Jaro against the candidate logradouros with the same key
        pairs AS (
          SELECT
              t.*,
              c.logradouro AS logradouro_cnefe,
              CAST(jaro_similarity(t.logradouro_input, c.logradouro) AS NUMERIC(5,3)) AS similarity
          FROM to_compute t
          JOIN {cand_src} c
            ON {join_condition_pairs}
          WHERE similarity > {min_cutoff}
        ),
        -- best candidate per group: equivalent to RANK() = 1 (the tie-break
        -- on logradouro_cnefe makes the order total), and aggregating is cheaper
        computed AS (
          SELECT
              {grp_cols},
              FIRST(logradouro_cnefe ORDER BY similarity DESC, logradouro_cnefe) AS logradouro_cnefe,
              MAX(similarity) AS similarity
          FROM pairs
          GROUP BY {grp_cols}
        )
        -- write back to the input. The eligibility filter is repeated because
        -- in the dedup form the join on key + logradouro would reach rows
        -- already resolved or with an ambiguous logradouro
        UPDATE input_padrao_db
          SET temp_lograd_determ = computed.logradouro_cnefe,
              similaridade_logradouro = computed.similarity
          FROM computed
          WHERE {upd_join}
            AND input_padrao_db.similaridade_logradouro IS NULL
            AND input_padrao_db.log_causa_confusao = FALSE
            AND {cols_not_null}
        """
    )
