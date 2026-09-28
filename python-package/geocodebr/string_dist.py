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

    # nas etapas sem numero (pl0k), as linhas com numero preenchido ja foram
    # testadas na etapa pn0k correspondente -- mesma chave de lookup, mesma
    # tabela unique_logr_* e mesmo corte -- e nao passaram: recalcular Jaro para
    # elas e um no-op garantido. Se numero nao foi declarado, a coluna-fantasma
    # e toda NULL e o filtro nao exclui nada
    filtro_sem_numero = (
        "AND input_padrao_db.numero IS NULL"
        if match_type in PROBABILISTIC_TYPES_NO_NUMBER
        else ""
    )

    # O Jaro depende so de (chave de lookup, logradouro), nao do
    # tempidgeocodebr. Com chave curta, muitas linhas repetem a combinacao e
    # compensa calcular uma vez por combinacao distinta e devolver por join.
    # Com cep E localidade (pn01/pl01) quase nao ha repeticao e o join-back
    # custa mais que o Jaro linha a linha: calcula direto por tempidgeocodebr.
    # Espelha calculate_string_dist() de r-package/R/string_dist.R
    if not {"cep", "localidade"} <= set(lookup_cols):
        sel_cols = f"DISTINCT {key_cols_sql}, logradouro AS logradouro_input"
        grp_cols = f"{key_cols_sql}, logradouro_input"
        upd_join = " AND ".join(
            [f"input_padrao_db.{col} = computed.{col}" for col in lookup_cols]
            + ["input_padrao_db.logradouro = computed.logradouro_input"]
        )
        # a unique_logr_* e criada com a chave mais longa; numa chave mais curta
        # o mesmo logradouro se repete e cada repeticao custaria um Jaro
        cand_src = f"(SELECT DISTINCT {key_cols_sql}, logradouro FROM {tbl})"
    else:
        sel_cols = f"tempidgeocodebr, {key_cols_sql}, logradouro AS logradouro_input"
        grp_cols = "tempidgeocodebr"
        upd_join = "input_padrao_db.tempidgeocodebr = computed.tempidgeocodebr"
        cand_src = tbl

    join_condition_pairs = " AND ".join(f"t.{col} = c.{col}" for col in lookup_cols)

    con.execute(
        f"""
        -- linhas (ou combinacoes distintas de chave + logradouro) que ainda
        -- nao tem similaridade
        WITH to_compute AS (
          SELECT {sel_cols}
          FROM input_padrao_db
          WHERE input_padrao_db.similaridade_logradouro IS NULL
            AND input_padrao_db.log_causa_confusao = FALSE
            AND {cols_not_null}
            {filtro_sem_numero}
        ),
        -- Jaro contra os logradouros candidatos da mesma chave
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
        -- melhor candidato por grupo: equivale a RANK() = 1 (o desempate por
        -- logradouro_cnefe torna a ordem total), e agregar e mais barato
        computed AS (
          SELECT
              {grp_cols},
              FIRST(logradouro_cnefe ORDER BY similarity DESC, logradouro_cnefe) AS logradouro_cnefe,
              MAX(similarity) AS similarity
          FROM pairs
          GROUP BY {grp_cols}
        )
        -- devolve ao input. O filtro de elegibilidade e repetido porque na forma
        -- com dedup o join por chave + logradouro alcancaria linhas ja
        -- resolvidas ou com logradouro ambiguo
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
