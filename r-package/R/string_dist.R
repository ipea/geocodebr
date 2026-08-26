calculate_string_dist <- function(con, match_type, unique_logradouros_tbl) {
  # message("calculate_string_dist")

  # match_type = "pl01"

  key_cols <- get_key_cols(match_type)

  # cols that cannot be null
  cols_not_null <- paste(
    glue::glue("input_padrao_db.{key_cols} IS NOT NULL"),
    collapse = ' AND '
  )

  # remove numero and logradouro from key cols to allow for the matching
  key_cols_string_dist <- key_cols[!key_cols %in% c("numero", "logradouro")]

  join_condition_lookup <- paste(
    glue::glue(
      "{unique_logradouros_tbl}.{key_cols_string_dist} = input_padrao_db.{key_cols_string_dist}"
    ),
    collapse = ' AND '
  )

  # min cutoff for string match
  min_cutoff <- get_prob_match_cutoff(match_type)

  #-----------------------------------------------------------------------------

  # query novo
  query_calc_dist <- glue::glue(
    "
    -- STEP 1: pick only rows that do NOT have similarity in temp table
    WITH to_compute AS (
      SELECT
          input_padrao_db.tempidgeocodebr,
          input_padrao_db.logradouro AS logradouro_input,
          {unique_logradouros_tbl}.logradouro AS logradouro_cnefe
      FROM input_padrao_db
      JOIN {unique_logradouros_tbl}
        ON {join_condition_lookup}
      WHERE input_padrao_db.similaridade_logradouro IS NULL
        AND input_padrao_db.log_causa_confusao = FALSE
        AND {cols_not_null}
        ),

    -- STEP 2: calculate similarity only for missing pairs
    computed AS (
      SELECT
          tempidgeocodebr,
          logradouro_cnefe,
          CAST(jaro_similarity(logradouro_input, logradouro_cnefe) AS NUMERIC(5,3)) AS similarity,
          RANK() OVER (PARTITION BY tempidgeocodebr ORDER BY similarity DESC, logradouro_cnefe) AS rank
      FROM to_compute
      WHERE similarity > {min_cutoff}
      )

    -- STEP 3: distances to input db
    UPDATE input_padrao_db
      SET temp_lograd_determ = computed.logradouro_cnefe,
          similaridade_logradouro = similarity
      FROM computed
      WHERE input_padrao_db.tempidgeocodebr = computed.tempidgeocodebr
            AND computed.rank = 1;"
  )

  DBI::dbExecute(con, query_calc_dist)
  #-----------------------------------------------------------------------------

  # # query antigo
  # query_lookup <- glue::glue(
  #   "WITH ranked_data AS (
  #       SELECT
  #         input_padrao_db.tempidgeocodebr,
  #         {unique_logradouros_tbl}.logradouro AS logradouro_cnefe,
  #         CAST(jaro_similarity(input_padrao_db.logradouro, {unique_logradouros_tbl}.logradouro) AS NUMERIC(5,3)) AS similarity,
  #         RANK() OVER (PARTITION BY input_padrao_db.tempidgeocodebr ORDER BY similarity DESC, logradouro_cnefe) AS rank
  #       FROM input_padrao_db
  #       JOIN {unique_logradouros_tbl}
  #         ON {join_condition_lookup}
  #      WHERE {cols_not_null}
  #            AND input_padrao_db.log_causa_confusao is false
  #            AND input_padrao_db.similaridade_logradouro IS NULL
  #            AND similarity > {min_cutoff}
  #     )
  #
  #     UPDATE input_padrao_db
  #        SET temp_lograd_determ = ranked_data.logradouro_cnefe,
  #            similaridade_logradouro = similarity
  #      FROM ranked_data
  #     WHERE input_padrao_db.tempidgeocodebr = ranked_data.tempidgeocodebr
  #           AND ranked_data.similarity > {min_cutoff}
  #           AND ranked_data.rank = 1;"
  #     )
  #
  # DBI::dbExecute(con, query_lookup)

  # a <- DBI::dbReadTable(con, 'input_padrao_db')
  # sum(is.na(a$similaridade_logradouro))
}
