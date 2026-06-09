from __future__ import annotations

import duckdb

from .utils import get_key_cols, get_prob_match_cutoff, quote_ident


def calculate_string_dist(
    con: duckdb.DuckDBPyConnection,
    match_type: str,
    unique_logradouros_tbl: str,
) -> None:
    key_cols = get_key_cols(match_type)
    cols_not_null = " AND ".join(f"input_padrao_db.{col} IS NOT NULL" for col in key_cols)
    lookup_cols = [col for col in key_cols if col not in {"numero", "logradouro"}]
    join_condition_lookup = " AND ".join(
        f"{quote_ident(unique_logradouros_tbl)}.{col} = input_padrao_db.{col}"
        for col in lookup_cols
    )
    min_cutoff = get_prob_match_cutoff(match_type)

    con.execute(
        f"""
        WITH to_compute AS (
          SELECT
              input_padrao_db.tempidgeocodebr,
              input_padrao_db.logradouro AS logradouro_input,
              {quote_ident(unique_logradouros_tbl)}.logradouro AS logradouro_cnefe
          FROM input_padrao_db
          JOIN {quote_ident(unique_logradouros_tbl)}
            ON {join_condition_lookup}
          WHERE input_padrao_db.similaridade_logradouro IS NULL
            AND input_padrao_db.log_causa_confusao = FALSE
            AND {cols_not_null}
        ),
        computed AS (
          SELECT
              tempidgeocodebr,
              logradouro_cnefe,
              CAST(jaro_similarity(logradouro_input, logradouro_cnefe) AS NUMERIC(5,3)) AS similarity,
              RANK() OVER (PARTITION BY tempidgeocodebr ORDER BY similarity DESC, logradouro_cnefe) AS rank
          FROM to_compute
          WHERE similarity > {min_cutoff}
        )
        UPDATE input_padrao_db
          SET temp_lograd_determ = computed.logradouro_cnefe,
              similaridade_logradouro = similarity
        FROM computed
        WHERE input_padrao_db.tempidgeocodebr = computed.tempidgeocodebr
          AND computed.rank = 1
        """
    )

