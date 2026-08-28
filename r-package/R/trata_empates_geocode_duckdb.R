trata_empates_geocode_duckdb <- function(
  con,
  resultado_completo,
  resolver_empates,
  verboso
) {
  # 1) identifica e materializa os casos de empate --------------------------------
  # a tabela ids_empatados fica criada mesmo nos ramos de retorno antecipado
  # abaixo: o custo e trivial (so os ids com mais de um resultado) e o caminho
  # resolver_empates = TRUE a reaproveita para separar empatados de
  # nao-empatados antes das window functions

  DBI::dbExecute(
    con,
    "CREATE OR REPLACE TEMP TABLE ids_empatados AS
      SELECT tempidgeocodebr
      FROM output_db
      GROUP BY tempidgeocodebr
      HAVING COUNT(*) > 1;"
  )

  n_casos_empate <- DBI::dbGetQuery(
    conn = con,
    statement = "SELECT COUNT(*) AS n_casos_empate FROM ids_empatados;"
  )[[1]]

  # 2) se nao tiver mais empates, termina aqui --------------------------------------
  # mas adiciona uma coluna de empate vazia caso o usuario peça endereco_completo = TRUE
  if (n_casos_empate == 0) {

    query <- glue::glue(
    "ALTER TABLE output_db
     ADD COLUMN IF NOT EXISTS empate BOOLEAN DEFAULT FALSE;"
    )

    DBI::dbExecute(con, query)

    return(n_casos_empate)
  }

  # 3) se nao for para resolver empates: ------------------------------------------
  # - calcula / identifica casos de empate
  # - gera warning
  # - retorna resultado assim mesmo

  if (isFALSE(resolver_empates)) {
    # marca o flag de empate in-place e renomeia, em vez de copiar output_db
    # inteira: o resto do pipeline (merge_results_to_input) usa o nome
    # 'output_db2' sempre que n_casos_empate > 0, e nada mais referencia
    # 'output_db' depois deste ponto.
    # tempidgeocodebr nunca e NULL (id sequencial criado na padronizacao); se
    # um dia for, o IN () abaixo deixaria o flag FALSE onde a window function
    # antiga (COUNT(*) OVER) agrupava os NULLs juntos.
    DBI::dbExecute(
      conn = con,
      statement = "ALTER TABLE output_db
                    ADD COLUMN IF NOT EXISTS empate BOOLEAN DEFAULT FALSE;"
    )
    DBI::dbExecute(
      conn = con,
      statement = "UPDATE output_db SET empate = TRUE
                    WHERE tempidgeocodebr IN (SELECT tempidgeocodebr FROM ids_empatados);"
    )
    DBI::dbExecute(
      conn = con,
      statement = "ALTER TABLE output_db RENAME TO output_db2;"
    )

    cli::cli_warn(
      "Foram encontrados {n_casos_empate} casos de empate. Estes casos foram
      marcados com valor `TRUE` na coluna 'empate', e podem ser inspecionados na
      coluna 'endereco_encontrado'. Alternativamente, use `resolver_empates = TRUE`
      para que o pacote lide com os empates automaticamente. Ver
      documenta\u00e7\u00e3o da fun\u00e7\u00e3o."
    )

    return(n_casos_empate)
  }

  # Haversine macro (kept for speed; consider spatial extension later)
  DBI::dbExecute(
    con,
    "
    CREATE MACRO IF NOT EXISTS haversine(lat1, lon1, lat2, lon2) AS (
      6378137 * 2 * ASIN(
        SQRT(
          POWER(SIN(RADIANS(lat2 - lat1) / 2), 2) +
          COS(RADIANS(lat1)) * COS(RADIANS(lat2)) *
          POWER(SIN(RADIANS(lon2 - lon1) / 2), 2)
        )
      )
    );
  "
  )

  # 4) se for para resolver empates, trata de 3 casos separados -----------------
  # D) nao empatados
  # E) empatados perdidos (dist > 1Km e lograoduros ambiguos)
  #    solucao: usa caso com maior contagem_cnefe
  # F) empatados mas que da pra salvar (dist < 1km e logradouros nao ambiguos)
  #    solucao: agrega casos provaveis de serem na mesma rua com media ponderada
  #    das coordenadas, mas retorna  endereco_encontrado do caso com maior
  #    contagem_cnefe
  # questao documentada no issue 37

  additional_cols_final <- ""
  cols_encontradas <- ""
  cols_passthrough <- ""

  if (isTRUE(resultado_completo)) {
    additional_cols_final <- glue::glue(
      ", logradouro_encontrado, numero_encontrado, cep_encontrado,
        localidade_encontrada, municipio_encontrado, estado_encontrado,
        similaridade_logradouro, contagem_cnefe, empate, cod_setor"
    )

    cols_encontradas <- glue::glue(
      ", logradouro_encontrado, numero_encontrado, cep_encontrado,
        localidade_encontrada, municipio_encontrado, estado_encontrado,
        similaridade_logradouro, cod_setor"
    )

    # o passthrough dos nao-empatados le direto de output_db, que nao tem a
    # coluna 'empate' -- ela nasce aqui como literal FALSE, na mesma posicao
    # em que additional_cols_final a coloca nos demais ramos do UNION ALL
    cols_passthrough <- glue::glue(
      ", logradouro_encontrado, numero_encontrado, cep_encontrado,
        localidade_encontrada, municipio_encontrado, estado_encontrado,
        similaridade_logradouro, contagem_cnefe, FALSE AS empate, cod_setor"
    )
  }

  # 4a) pipeline de classificacao, SOMENTE sobre os grupos empatados ------------
  # As window functions abaixo (ROW_NUMBER, LAG + haversine, COUNT/MAX OVER)
  # custavam O(output_db inteiro); com o recorte por ids_empatados custam
  # O(linhas empatadas). Materializar como TEMP TABLE (e nao CTE referenciada
  # varias vezes) garante que o pipeline roda uma unica vez e permite
  # inspecionar o resultado intermediario ao depurar.

  sql_classif <- glue::glue(
    "CREATE OR REPLACE TEMP TABLE empates_classif AS
      WITH
      -- A) tabela *base* ranqueia os candidatos de cada grupo empatado
      -- (inclui mesmo aqueles a menos de 300 metros)
        base AS (
          SELECT
            o.*,
            ROW_NUMBER() OVER (PARTITION BY tempidgeocodebr ORDER BY contagem_cnefe DESC, desvio_metros, endereco_encontrado) AS id
          FROM output_db o
          WHERE EXISTS (SELECT 1 FROM ids_empatados i WHERE i.tempidgeocodebr = o.tempidgeocodebr)
        ),

      -- B) tabela *distd* calculate distancia entre os casos empatados
      -- Usa LAG (e nao LEAD) de proposito: a distancia de cada linha eh medida
      -- contra a linha ANTERIOR, que por construcao do 'id' tem contagem_cnefe
      -- maior ou igual. Assim, quando o filtro (C) descarta um par a menos de
      -- 300 metros, quem sai eh sempre a linha de MENOR contagem_cnefe.
      -- Na primeira linha de cada grupo o LAG e NULL e a haversine propaga NULL.
      distd AS (
          SELECT
            b.*,
            haversine(
              lat, lon,
              LAG(lat) OVER (PARTITION BY tempidgeocodebr ORDER BY id),
              LAG(lon) OVER (PARTITION BY tempidgeocodebr ORDER BY id)
            ) AS dist_geocodebr_metros
          FROM base b
        )

      -- C) mantem apenas casos de empate que estao a mais de 300 metros e
      -- recalcula a coluna de empate sobre os sobreviventes
      -- A linha com dist NULL eh a primeira da particao (id = 1), i.e. a de maior
      -- contagem_cnefe, que por isso eh sempre preservada.
      SELECT
        d.*,
        (COUNT(*) OVER (PARTITION BY tempidgeocodebr) > 1) AS empate,
        MAX(dist_geocodebr_metros) OVER (PARTITION BY tempidgeocodebr) AS max_dist
      FROM distd d
      WHERE dist_geocodebr_metros IS NULL
         OR dist_geocodebr_metros > 300;"
  )

  DBI::dbExecute(con, sql_classif)

  # 4b) monta output_db2: nao-empatados passam direto de output_db (sem nenhuma
  # window function); D/E/F sao derivados de empates_classif

  sql_resolve <- glue::glue(
    "CREATE OR REPLACE TEMP TABLE output_db2 AS
      WITH
      -- D) tabela *df_sem_empate* com os casos que deixaram de ser empate
      -- apos o colapso de 300 metros
      df_sem_empate AS (
          SELECT
            tempidgeocodebr,
            lat,
            lon,
            endereco_encontrado,
            tipo_resultado,
            contagem_cnefe,
            desvio_metros,
            empate {cols_encontradas}
          FROM empates_classif
          WHERE empate = FALSE
        ),

        -- E) empatados perdidos (exemplo: max_dist > 1000; acrescente demais regras aqui)
        df_empates_perdidos AS (
          SELECT
            tempidgeocodebr,
            lat,
            lon,
            endereco_encontrado,
            tipo_resultado,
            contagem_cnefe,
            desvio_metros,
            TRUE AS empate {cols_encontradas}
          FROM empates_classif
          WHERE empate = TRUE
            -- so match com logradouro pode ser 'perdido': nas categorias sem
            -- logradouro (dc01, dc02, db01, dm01) o empate e entre enderecos do
            -- mesmo CEP/bairro/municipio, e a media ponderada e o centroide que
            -- a precisao correspondente promete
            AND logradouro_encontrado IS NOT NULL
            AND (
              max_dist > 1000
              OR log_causa_confusao
              -- o regex de numeros por extenso casa por substring (pega 'RUA
              -- QUINZE' dentro de 'RUA QUINZE DE NOVEMBRO'), entao a excecao
              -- de ruas-data neutraliza APENAS este braco: nomes-data seguem
              -- podendo ser 'perdidos' pela distancia (max_dist) acima
              OR (
                REGEXP_MATCHES(endereco_encontrado,
                    '(RUA (QUATRO|QUATORZE|QUINZE|DEZESSEIS|DEZESSETE|DEZOITO|DEZENOVE|VINTE|TRINTA|QUARENTA|CINQUENTA|SESSENTA|SETENTA|OITENTA|NOVENTA))'
                )
                AND NOT REGEXP_MATCHES(logradouro_encontrado, '\\bDE (JANEIRO|FEVEREIRO|MARCO|ABRIL|MAIO|JUNHO|JULHO|AGOSTO|SETEMBRO|OUTUBRO|NOVEMBRO|DEZEMBRO)\\b')
              )
            )
          QUALIFY ROW_NUMBER()
            OVER (PARTITION BY tempidgeocodebr ORDER BY contagem_cnefe DESC, desvio_metros, endereco_encontrado) = 1
        ),

        -- F) empatados salvaveis = restantes (empatados que nao cairam em E)
        -- 'empate' e constante por tempidgeocodebr, entao empate = TRUE ja
        -- exclui os grupos de df_sem_empate (D) sem precisar de anti-join
        empates_restantes AS (
          SELECT f.*
          FROM empates_classif f
          WHERE f.empate = TRUE
            AND NOT EXISTS (SELECT 1 FROM df_empates_perdidos p WHERE p.tempidgeocodebr = f.tempidgeocodebr)
        ),
        empates_wavg AS (
          SELECT
            e.*,
            (SUM(lat * contagem_cnefe) OVER (PARTITION BY tempidgeocodebr)
              / NULLIF(SUM(contagem_cnefe) OVER (PARTITION BY tempidgeocodebr), 0)) AS lat_wavg,
            (SUM(lon * contagem_cnefe) OVER (PARTITION BY tempidgeocodebr)
              / NULLIF(SUM(contagem_cnefe) OVER (PARTITION BY tempidgeocodebr), 0)) AS lon_wavg
          FROM empates_restantes e
        ),
        df_empates_salve AS (
          SELECT
            tempidgeocodebr,
            lat_wavg AS lat,
            lon_wavg AS lon,
            endereco_encontrado,
            tipo_resultado,
            contagem_cnefe,
            desvio_metros,
            TRUE AS empate {cols_encontradas}
          FROM empates_wavg
          QUALIFY ROW_NUMBER()
            OVER (PARTITION BY tempidgeocodebr ORDER BY contagem_cnefe DESC, desvio_metros, endereco_encontrado) = 1
        )

      -- junta as 3 tabelas (df_sem_empate, df_empates_perdidos, df_empates_salve)
      -- e o passthrough dos casos que nunca tiveram empate
      SELECT
        tempidgeocodebr, lat, lon, tipo_resultado, desvio_metros,
        endereco_encontrado {additional_cols_final}
      FROM df_sem_empate
      UNION ALL
      SELECT
        tempidgeocodebr, lat, lon, tipo_resultado, desvio_metros,
        endereco_encontrado {additional_cols_final}
      FROM df_empates_perdidos
      UNION ALL
      SELECT
        tempidgeocodebr, lat, lon, tipo_resultado, desvio_metros,
        endereco_encontrado {additional_cols_final}
      FROM df_empates_salve
      UNION ALL
      SELECT
        tempidgeocodebr, lat, lon, tipo_resultado, desvio_metros,
        endereco_encontrado {cols_passthrough}
      FROM output_db o
      WHERE NOT EXISTS (SELECT 1 FROM ids_empatados i WHERE i.tempidgeocodebr = o.tempidgeocodebr);"
  )

  DBI::dbExecute(con, sql_resolve)

  if (verboso) {
    plural <- ifelse(n_casos_empate == 1, 'caso', 'casos')
    message(glue::glue(
      "Foram encontrados e resolvidos {n_casos_empate} {plural} de empate."
    ))
  }

  return(n_casos_empate)
}
