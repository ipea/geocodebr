trata_empates_geocode_duckdb <- function(
  con = parent.frame()$con,
  resultado_completo = parent.frame()$resultado_completo,
  resolver_empates = parent.frame()$resolver_empates,
  verboso = parent.frame()$verboso
) {
  # 1) checa se tem empates --------------------------------------

  n_casos_empate <- DBI::dbGetQuery(
    conn = con,
    statement = "SELECT COUNT(*) AS n_casos_empate
                    FROM (
                      SELECT tempidgeocodebr
                      FROM output_db
                      GROUP BY tempidgeocodebr
                      HAVING COUNT(*) > 1
                    ) AS repeated;"
  )[[1]]

  # 2) se nao tiver mais empates, termina aqui --------------------------------------
  if (n_casos_empate == 0) {
    return(n_casos_empate)
  }

  # 3) se nao for para resolver empates: ------------------------------------------
  # - calcula / identifica casos de empate
  # - gera warning
  # - retorna resultado assim mesmo
  if (isFALSE(resolver_empates)) {
    # adicionar coluna de empate
    DBI::dbExecute(
      conn = con,
      statement = "CREATE OR REPLACE TEMP TABLE output_db2 AS
                    SELECT *,
                    (COUNT(*) OVER (PARTITION BY tempidgeocodebr) > 1) AS empate
                    FROM output_db;"
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

  # 3 se for para resolver empates, trata de 3 casos separados -----------------
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
  }

  sql_resolve <- glue::glue(
    "CREATE OR REPLACE TEMP TABLE output_db2 AS

      -- A) tabela *base* calculate empates iniciais (inclui mesmo aqueles a menos de 300 metros)
      WITH
        base AS (
          SELECT
            *,
            (COUNT(*) OVER (PARTITION BY tempidgeocodebr) > 1) AS empate_inicial,
            ROW_NUMBER() OVER (PARTITION BY tempidgeocodebr ORDER BY contagem_cnefe DESC, desvio_metros, endereco_encontrado) AS id
          FROM output_db
        ),

      -- B) tabela *distd* calculate distancia entre os casos empatados
      -- Usa LAG (e nao LEAD) de proposito: a distancia de cada linha eh medida
      -- contra a linha ANTERIOR, que por construcao do 'id' tem contagem_cnefe
      -- maior ou igual. Assim, quando o filtro (C) descarta um par a menos de
      -- 300 metros, quem sai eh sempre a linha de MENOR contagem_cnefe.
      distd AS (
          SELECT
            b.*,
            CASE WHEN empate_inicial THEN
              haversine(
                lat, lon,
                LAG(lat) OVER (PARTITION BY tempidgeocodebr ORDER BY id),
                LAG(lon) OVER (PARTITION BY tempidgeocodebr ORDER BY id)
              )
            END AS dist_geocodebr_metros
          FROM base b
        ),

      -- C) tabela *filtered* pra manter apenas casos de empate que estao a mais de 300 metros e atualiza coluna de empate
      -- A linha com dist NULL eh a primeira da particao (id = 1), i.e. a de maior
      -- contagem_cnefe, que por isso eh sempre preservada.
      filtered AS (
          SELECT
            d.*,
            (COUNT(*) OVER (PARTITION BY tempidgeocodebr) > 1) AS empate,
            MAX(dist_geocodebr_metros) OVER (PARTITION BY tempidgeocodebr) AS max_dist
          FROM distd d
          WHERE (empate_inicial IS FALSE)
             OR (empate_inicial AND dist_geocodebr_metros IS NULL)
             OR (empate_inicial AND dist_geocodebr_metros > 300)
        ),

      -- D) tabela *df_sem_empate* com os casos sem empate
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
          FROM filtered
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
          FROM filtered
          WHERE empate = TRUE
            -- so match com logradouro pode ser 'perdido': nas categorias sem
            -- logradouro (dc01, dc02, db01, dm01) o empate e entre enderecos do
            -- mesmo CEP/bairro/municipio, e a media ponderada e o centroide que
            -- a precisao correspondente promete
            AND logradouro_encontrado IS NOT NULL
            AND (
              max_dist > 1000
              OR log_causa_confusao
              OR REGEXP_MATCHES(endereco_encontrado,
                  '(RUA (QUATRO|QUATORZE|QUINZE|DEZESSEIS|DEZESSETE|DEZOITO|DEZENOVE|VINTE|TRINTA|QUARENTA|CINQUENTA|SESSENTA|SETENTA|OITENTA|NOVENTA))'
              )
            )
            AND NOT REGEXP_MATCHES(logradouro_encontrado, '\\\\bDE (JANEIRO|FEVEREIRO|MARCO|ABRIL|MAIO|JUNHO|JULHO|AGOSTO|SETEMBRO|OUTUBRO|NOVEMBRO|DEZEMBRO)\\\\b')
          QUALIFY ROW_NUMBER()
            OVER (PARTITION BY tempidgeocodebr ORDER BY contagem_cnefe DESC) = 1
        ),

        -- F) empatados salvaveis = restantes (nao em a nem b)
        empates_restantes AS (
          SELECT f.*
          FROM filtered f
          WHERE f.empate = TRUE
            AND NOT EXISTS (SELECT 1 FROM df_sem_empate s WHERE s.tempidgeocodebr = f.tempidgeocodebr)
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
            OVER (PARTITION BY tempidgeocodebr ORDER BY contagem_cnefe DESC) = 1
        )

      -- junta as 3 tabelas numa soh (df_sem_empate, df_empates_perdidos, df_empates_salve)
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
      FROM df_empates_salve;"
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
