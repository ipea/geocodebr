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
  # O Jaro depende so de (chave de lookup, logradouro), nao do tempidgeocodebr.
  # Quando a chave e curta, muitas linhas do input repetem a mesma combinacao e
  # compensa calcular a similaridade uma vez por combinacao distinta e devolver
  # o resultado por join (forma com dedup; medido em 43,9M: Jaro 178 -> ~60 s).
  # Quando a chave inclui cep E localidade (pn01/pl01) quase nao ha repeticao e
  # o join-back por 4 colunas de texto custa mais que o Jaro linha a linha
  # (pn01 6 -> 29 s): nesses casos calcula-se direto por tempidgeocodebr.
  # As duas formas usam a mesma query; so mudam o que entra no primeiro CTE, o
  # GROUP BY e a condicao do UPDATE.
  key_cols_sql <- paste(key_cols_string_dist, collapse = ', ')
  usa_dedup <- !all(c("cep", "localidade") %in% key_cols_string_dist)

  if (usa_dedup) {
    sel_cols <- glue::glue("DISTINCT {key_cols_sql}, logradouro AS logradouro_input")
    grp_cols <- glue::glue("{key_cols_sql}, logradouro_input")
    upd_join <- paste(
      c(
        glue::glue("input_padrao_db.{key_cols_string_dist} = computed.{key_cols_string_dist}"),
        "input_padrao_db.logradouro = computed.logradouro_input"
      ),
      collapse = ' AND '
    )
    # a tabela unique_logr_* e criada pela primeira etapa que a usa, com a chave
    # mais longa (cep + localidade); numa chave mais curta o mesmo logradouro
    # aparece repetido e cada repeticao custaria um jaro_similarity
    cand_src <- glue::glue(
      "(SELECT DISTINCT {key_cols_sql}, logradouro FROM {unique_logradouros_tbl})"
    )
  } else {
    sel_cols <- glue::glue("tempidgeocodebr, {key_cols_sql}, logradouro AS logradouro_input")
    grp_cols <- "tempidgeocodebr"
    upd_join <- "input_padrao_db.tempidgeocodebr = computed.tempidgeocodebr"
    cand_src <- unique_logradouros_tbl
  }

  join_condition_pairs <- paste(
    glue::glue("t.{key_cols_string_dist} = c.{key_cols_string_dist}"),
    collapse = ' AND '
  )

  query_calc_dist <- glue::glue(
    "
    -- STEP 1: linhas (ou combinacoes distintas de chave + logradouro) que ainda
    -- nao tem similaridade
    WITH to_compute AS (
      SELECT {sel_cols}
      FROM input_padrao_db
      WHERE input_padrao_db.similaridade_logradouro IS NULL
        AND input_padrao_db.log_causa_confusao = FALSE
        AND {cols_not_null}
        {filtro_sem_numero}
      ),

    -- STEP 2: Jaro contra os logradouros candidatos da mesma chave
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

    -- STEP 3: melhor candidato por grupo. Equivale a RANK() = 1: o desempate
    -- por logradouro_cnefe torna a ordem total, e agregacao e mais barata que
    -- window function
    computed AS (
      SELECT
          {grp_cols},
          FIRST(logradouro_cnefe ORDER BY similarity DESC, logradouro_cnefe) AS logradouro_cnefe,
          MAX(similarity) AS similarity
      FROM pairs
      GROUP BY {grp_cols}
      )

    -- STEP 4: devolve ao input. O filtro de elegibilidade e repetido porque na
    -- forma com dedup o join por chave + logradouro alcancaria linhas ja
    -- resolvidas ou com logradouro ambiguo; na forma direta e redundante
    UPDATE input_padrao_db
      SET temp_lograd_determ = computed.logradouro_cnefe,
          similaridade_logradouro = computed.similarity
      FROM computed
      WHERE {upd_join}
        AND input_padrao_db.similaridade_logradouro IS NULL
        AND input_padrao_db.log_causa_confusao = FALSE
        AND {cols_not_null};"
  )

  DBI::dbExecute(con, query_calc_dist)
}
