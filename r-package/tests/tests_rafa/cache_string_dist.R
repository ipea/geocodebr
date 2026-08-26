calculate_string_dist <- function(con, match_type, unique_logradouros_tbl){

  # match_type = "pn01"

  key_cols <- get_key_cols(match_type)

  # cols that cannot be null
  cols_not_null <-  paste(
    glue::glue("input_padrao_db.{key_cols} IS NOT NULL"),
    collapse = ' AND '
  )

  # remove numero and logradouro from key cols to allow for the matching
  key_cols_string_dist <- key_cols[!key_cols %in%  c("numero", "logradouro")]

  # # name of cache table
  # cache_tbl <- paste0("similarity_cache_", paste0(key_cols_string_dist, collapse = "_"))

  join_condition_lookup <- paste(
    glue::glue("{unique_logradouros_tbl}.{key_cols_string_dist} = input_padrao_db.{key_cols_string_dist}"),
    collapse = ' AND '
  )

  # min cutoff for string match
  min_cutoff <- get_prob_match_cutoff(match_type)


  # query create NEW cache for logradouro distances
  query_create_dist_cache <- glue::glue(
    "
    -- STEP 1: pick only rows that do NOT have similarity in temp table
   CREATE OR REPLACE TEMP TABLE similarity_cache AS
   -- CREATE TEMP TABLE IF NOT EXISTS similarity_cache AS
      SELECT
          input_padrao_db.tempidgeocodebr,
          input_padrao_db.logradouro AS logradouro_input,
          {unique_logradouros_tbl}.logradouro AS logradouro_cnefe,
          NULL AS logr_similarity
      FROM input_padrao_db
      JOIN {unique_logradouros_tbl}
        ON {join_condition_lookup}
      WHERE {cols_not_null}
        AND input_padrao_db.log_causa_confusao = FALSE
        AND input_padrao_db.similaridade_logradouro IS NULL;"
    )

  query_calc_dist_cache <- glue::glue(
      "UPDATE similarity_cache
        SET logr_similarity =
         CAST(jaro_similarity(logradouro_input, logradouro_cnefe) AS NUMERIC(5,3))
      WHERE logr_similarity IS NULL;"
  )

  DBI::dbExecute(con, query_create_dist_cache)
  similarity_cache0 <- DBI::dbReadTable(con, 'similarity_cache')

  DBI::dbExecute(con, query_calc_dist_cache)
  similarity_cache0 <- DBI::dbReadTable(con, 'similarity_cache')

  # check if there are  create NEW cache for logradouro distances
  query_add_rows_to_dist_cache <- glue::glue(
    "
    -- STEP 2: check if there are more distance pairs to calculate and add them to cache
   WITH to_compute AS (
      SELECT
          input_padrao_db.tempidgeocodebr,
          input_padrao_db.logradouro AS logradouro_input,
          {unique_logradouros_tbl}.logradouro AS logradouro_cnefe,
          input_padrao_db.similaridade_logradouro AS logr_similarity,
      FROM input_padrao_db
      JOIN {unique_logradouros_tbl}
        ON {join_condition_lookup}
      WHERE input_padrao_db.log_causa_confusao = FALSE
        AND input_padrao_db.similaridade_logradouro IS NULL
        AND input_padrao_db.tempidgeocodebr NOT IN (SELECT DISTINCT(tempidgeocodebr) FROM similarity_cache)
        )

  INSERT INTO similarity_cache (tempidgeocodebr, logradouro_input, logradouro_cnefe, logr_similarity)
      SELECT tempidgeocodebr, logradouro_input, logradouro_cnefe, logr_similarity
      FROM to_compute;"
  )

  DBI::dbExecute(con, query_add_rows_to_dist_cache)
  similarity_cache1 <- DBI::dbReadTable(con, 'similarity_cache')

   # compute similarity and update the cache
    query_calc_dist <- glue::glue(
    "
    -- STEP 2: calculate similarity only for missing pairs
    WITH computed AS (
      SELECT
          tempidgeocodebr,
          logradouro_input,
          logradouro_cnefe,
          CAST(jaro_similarity(logradouro_input, logradouro_cnefe) AS NUMERIC(5,3)) AS similarity,
          RANK() OVER (PARTITION BY tempidgeocodebr ORDER BY similarity DESC, logradouro_cnefe) AS rank
      FROM similarity_cache
      WHERE logr_similarity IS NULL
      )

    -- STEP 3: update cache
    UPDATE similarity_cache
      SET logr_similarity = computed.similarity
      FROM computed
      WHERE similarity_cache.tempidgeocodebr = computed.tempidgeocodebr
            AND similarity_cache.logradouro_cnefe = computed.logradouro_cnefe
            AND computed.rank = 1
          --  AND computed.similarity > {min_cutoff};"
    )

    query_dist_to_inputdb <- glue::glue(
    "
    -- STEP 4: pass distances to input db
    UPDATE input_padrao_db
      SET temp_lograd_determ =similarity_cache.logradouro_cnefe,
          similaridade_logradouro = logr_similarity
      FROM similarity_cache
      WHERE input_padrao_db.tempidgeocodebr = similarity_cache.tempidgeocodebr
            -- AND similarity_cache.rank = 1
            AND similarity_cache.logr_similarity > {min_cutoff}

     ;"
  )


  DBI::dbExecute(con, query_create_dist_cache)
  similarity_cache0 <- DBI::dbReadTable(con, 'similarity_cache')

  DBI::dbExecute(con, query_calc_dist)
  similarity_cache2 <- DBI::dbReadTable(con, 'similarity_cache')

  DBI::dbExecute(con, query_dist_to_inputdb)
  input_padrao_db1 <- DBI::dbReadTable(con, 'input_padrao_db')
  # sum(is.na(a$similaridade_logradouro))
}

# solucao chat ----------------------------------------

  # match_type = "pn02"

  key_cols <- get_key_cols(match_type)

  # cols that cannot be null
  cols_not_null <-  paste(
    glue::glue("input_padrao_db.{key_cols} IS NOT NULL"),
    collapse = ' AND '
  )

  # remove numero and logradouro from key cols to allow for the matching
  key_cols_string_dist <- key_cols[!key_cols %in%  c("numero", "logradouro")]

  # # name of cache table
  # cache_tbl <- paste0("similarity_cache_", paste0(key_cols_string_dist, collapse = "_"))

  join_condition_lookup <- paste(
    glue::glue("{unique_logradouros_tbl}.{key_cols_string_dist} = input_padrao_db.{key_cols_string_dist}"),
    collapse = ' AND '
  )

  # min cutoff for string match
  min_cutoff <- get_prob_match_cutoff(match_type)


  # STEP 0 — TEMP similarity cache (created once per geocode() call)
  DBI::dbExecute(
    con,
    "
     CREATE TEMP TABLE IF NOT EXISTS similarity_cache (
      tempidgeocodebr     INTEGER,
      logradouro_input    TEXT,
      logradouro_cnefe    TEXT,
      logr_similarity     DOUBLE,
      PRIMARY KEY (tempidgeocodebr, logradouro_cnefe)
      );"
    )

  similarity_cache1 <-  DBI::dbReadTable(con, 'similarity_cache')

  # 6666666666666666666666666 o erro esta aqui na hora de roda pn02
  # STEP 1 — Insert NEW pairs that still need similarity
  query1_update_cache <- glue::glue(
    "
    WITH to_compute AS (
      SELECT
          input_padrao_db.tempidgeocodebr,
          input_padrao_db.logradouro AS logradouro_input,
          {unique_logradouros_tbl}.logradouro AS logradouro_cnefe,
          NULL AS logr_similarity
      FROM input_padrao_db
      JOIN {unique_logradouros_tbl}
        ON {join_condition_lookup}
      WHERE {cols_not_null}
        AND input_padrao_db.log_causa_confusao = FALSE
        AND input_padrao_db.similaridade_logradouro IS NULL
        AND input_padrao_db.tempidgeocodebr NOT IN (
              SELECT tempidgeocodebr FROM similarity_cache)
    )

      MERGE INTO similarity_cache AS sc
      USING to_compute AS tc
      ON sc.tempidgeocodebr = tc.tempidgeocodebr
         AND sc.logradouro_cnefe = tc.logradouro_cnefe
      WHEN NOT MATCHED THEN
          INSERT (tempidgeocodebr, logradouro_input, logradouro_cnefe, logr_similarity)
          VALUES (tc.tempidgeocodebr, tc.logradouro_input, tc.logradouro_cnefe, NULL);
    "
      )

  DBI::dbExecute(con, query1_update_cache)

  similarity_cache2 <-  DBI::dbReadTable(con, 'similarity_cache')


  # STEP 2 — Compute similarity only for rows where it's still NULL

  query2_calc_dist <- glue::glue(
    "
    WITH computed AS (
    SELECT
        tempidgeocodebr,
        logradouro_cnefe,
        CAST(jaro_similarity(logradouro_input, logradouro_cnefe) AS NUMERIC(5,3)) AS similarity,
    FROM similarity_cache
    WHERE logr_similarity IS NULL
    )

    UPDATE similarity_cache AS sc
      SET logr_similarity = c.similarity
      FROM computed AS c
      WHERE sc.tempidgeocodebr = c.tempidgeocodebr
            AND sc.logradouro_cnefe = c.logradouro_cnefe;
    ")

  DBI::dbExecute(con, query2_calc_dist)

  similarity_cache1 <-  DBI::dbReadTable(con, 'similarity_cache')

  # step 3 - keep best per input
  query3_dedup_cache <- glue::glue(
    "
    WITH ranked AS (
    SELECT
        tempidgeocodebr,
        logradouro_cnefe,
        ROW_NUMBER() OVER (PARTITION BY tempidgeocodebr ORDER BY logr_similarity DESC, logradouro_cnefe) AS rank
    FROM similarity_cache
    )

    DELETE FROM similarity_cache
    WHERE (tempidgeocodebr, logradouro_cnefe) NOT IN (
        SELECT tempidgeocodebr, logradouro_cnefe
        FROM ranked
        WHERE rank = 1);
    ")

  DBI::dbExecute(con, query3_dedup_cache)

  similarity_cache2 <-  DBI::dbReadTable(con, 'similarity_cache')
  nrow(similarity_cache2)


  # STEP 4 - Rank similarity matches & pick best candidate per input
  query4_dist_to_inputdb <- glue::glue(
  "
  UPDATE input_padrao_db AS x
    SET
        temp_lograd_determ = sc.logradouro_cnefe,
        similaridade_logradouro = sc.logr_similarity
    FROM similarity_cache AS sc
    WHERE sc.logr_similarity > {min_cutoff}
      AND x.tempidgeocodebr = sc.tempidgeocodebr
      AND x.similaridade_logradouro is NULL;
    ")

  DBI::dbExecute(con, query4_dist_to_inputdb)

  input_padrao_db1 <-  DBI::dbReadTable(con, 'input_padrao_db')
