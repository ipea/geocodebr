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

  # min cutoff for string match
  min_cutoff <- get_prob_match_cutoff(match_type)

  # nas etapas sem numero (pl0k), as linhas com numero preenchido ja foram
  # testadas na etapa pn0k correspondente -- mesma chave de lookup, mesma
  # tabela unique_logr_* e mesmo corte -- e nao passaram. similaridade_logradouro
  # so e preenchida, nunca limpa, entao recalcular Jaro para elas aqui e um
  # no-op garantido (mesmo principio de match_types_jaro_redundante em utils.R).
  # So as linhas com numero NULL (que pn0k exclui via cols_not_null) restam.
  # Se numero nao foi declarado, a coluna-fantasma e toda NULL e o filtro nao
  # exclui nada.
  filtro_sem_numero <- if (match_type %in% probabilistic_types_no_number) {
    "AND input_padrao_db.numero IS NULL"
  } else {
    ""
  }

  #-----------------------------------------------------------------------------
  # Jaro depende apenas de (key_cols_string_dist, logradouro) -- nao do
  # tempidgeocodebr. Como muitas linhas do input compartilham essa combinacao,
  # deduplicamos o input ANTES de calcular a similaridade e devolvemos o
  # resultado por join. Dentro de cada grupo o candidato vencedor eh unico
  # (a tabela de candidatos entra DISTINCT, e o desempate por logradouro_cnefe
  # torna a ordenacao total), logo RANK() = 1 equivale a
  # FIRST(... ORDER BY ...) + MAX(similarity) -- e agregacao eh mais barata que
  # window function.

  # colunas-chave qualificadas para cada lado do join
  cols_to_compute <- paste(
    glue::glue("t.{key_cols_string_dist}"),
    collapse = ', '
  )
  join_condition_lookup <- paste(
    glue::glue("t.{key_cols_string_dist} = c.{key_cols_string_dist}"),
    collapse = ' AND '
  )
  join_condition_update <- paste(
    glue::glue(
      "input_padrao_db.{key_cols_string_dist} = computed.{key_cols_string_dist}"
    ),
    collapse = ' AND '
  )
  key_cols_sql <- paste(key_cols_string_dist, collapse = ', ')

  # Nas etapas cuja chave de lookup inclui cep E localidade (pn01/pl01) a
  # combinacao (chave, logradouro) quase nao se repete no input e a tabela
  # unique_logr_* ja e unica nessa chave: o caminho com dedup + join-back custa
  # mais do que o Jaro linha a linha (medido em 43,9M: pn01 6 s -> 29 s). Nesses
  # casos usa-se a forma direta, por tempidgeocodebr.
  usa_dedup <- !all(c("cep", "localidade") %in% key_cols_string_dist)

  if (!usa_dedup) {
    join_condition_direto <- paste(
      glue::glue(
        "{unique_logradouros_tbl}.{key_cols_string_dist} = input_padrao_db.{key_cols_string_dist}"
      ),
      collapse = ' AND '
    )

    query_calc_dist <- glue::glue(
      "
      WITH to_compute AS (
        SELECT
            input_padrao_db.tempidgeocodebr,
            input_padrao_db.logradouro AS logradouro_input,
            {unique_logradouros_tbl}.logradouro AS logradouro_cnefe
        FROM input_padrao_db
        JOIN {unique_logradouros_tbl}
          ON {join_condition_direto}
        WHERE input_padrao_db.similaridade_logradouro IS NULL
          AND input_padrao_db.log_causa_confusao = FALSE
          AND {cols_not_null}
          {filtro_sem_numero}
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
              AND computed.rank = 1;"
    )

    DBI::dbExecute(con, query_calc_dist)
    return(invisible(NULL))
  }

  query_calc_dist <- glue::glue(
    "
    -- STEP 1: combinacoes distintas de chave + logradouro que ainda nao tem similaridade
    WITH to_compute AS (
      SELECT DISTINCT
          {key_cols_sql},
          input_padrao_db.logradouro AS logradouro_input
      FROM input_padrao_db
      WHERE input_padrao_db.similaridade_logradouro IS NULL
        AND input_padrao_db.log_causa_confusao = FALSE
        AND {cols_not_null}
        {filtro_sem_numero}
        ),

    -- STEP 2: calcula Jaro apenas para os pares distintos
    pairs AS (
      SELECT
          {cols_to_compute},
          t.logradouro_input,
          c.logradouro AS logradouro_cnefe,
          CAST(jaro_similarity(t.logradouro_input, c.logradouro) AS NUMERIC(5,3)) AS similarity
      FROM to_compute t
      JOIN (SELECT DISTINCT {key_cols_sql}, logradouro FROM {unique_logradouros_tbl}) c
        ON {join_condition_lookup}
      ),

    -- STEP 3: melhor candidato por combinacao (equivalente a RANK() = 1)
    computed AS (
      SELECT
          {key_cols_sql},
          logradouro_input,
          FIRST(logradouro_cnefe ORDER BY similarity DESC, logradouro_cnefe) AS logradouro_cnefe,
          MAX(similarity) AS similarity
      FROM pairs
      WHERE similarity > {min_cutoff}
      GROUP BY ALL
      )

    -- STEP 4: devolve o resultado ao input (o filtro de elegibilidade tem de
    -- ser repetido aqui, senao linhas ja resolvidas ou com confusao seriam
    -- sobrescritas)
    UPDATE input_padrao_db
      SET temp_lograd_determ = computed.logradouro_cnefe,
          similaridade_logradouro = computed.similarity
      FROM computed
      WHERE {join_condition_update}
            AND input_padrao_db.logradouro = computed.logradouro_input
            AND input_padrao_db.similaridade_logradouro IS NULL
            AND input_padrao_db.log_causa_confusao = FALSE
            AND {cols_not_null}
            {filtro_sem_numero};"
  )

  DBI::dbExecute(con, query_calc_dist)
}
