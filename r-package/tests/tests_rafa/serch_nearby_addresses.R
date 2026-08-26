
# Find cases nearby

serch_nearby_addresses <- function(con, dist){

  # update coordinates range
  margin_lat <- round(dist / 111320, digits = 8)
  # AND lon_max = lon + ({dist} * COS( lat * 0.017453 ))

  query_update_coords_range <- glue::glue(
    "UPDATE input_table_db
      SET lat_min = lat - {margin_lat},
          lat_max = lat + {margin_lat},
          lon_min = lon - (({dist} / 111320) * COS(lat)),
          lon_max = lon + (({dist} / 111320) * COS(lat));"
    )

  DBI::dbExecute(con, query_update_coords_range)
  # a <- DBI::dbReadTable(con, 'input_table_db')

  # spatial search
  query_filter_cases_nearby <- glue::glue(
    "INSERT INTO output_db (tempidgeocodebr, lat_cnefe, lon_cnefe, endereco_completo,
                            estado, municipio, logradouro, numero, cep, localidade)
      SELECT
          input_table_db.tempidgeocodebr,
          filtered_cnefe.lat AS lat_cnefe,
          filtered_cnefe.lon AS lon_cnefe,
          filtered_cnefe.endereco_completo,
          filtered_cnefe.estado,
          filtered_cnefe.municipio,
          filtered_cnefe.logradouro,
          filtered_cnefe.numero,
          filtered_cnefe.cep,
          filtered_cnefe.localidade
      FROM
        input_table_db, filtered_cnefe
      WHERE
            filtered_cnefe.lat BETWEEN input_table_db.lat_min AND input_table_db.lat_max
        AND filtered_cnefe.lon BETWEEN input_table_db.lon_min AND input_table_db.lon_max
        AND filtered_cnefe.lon IS NOT NULL;"
    )

      # FROM input_table_db
      # LEFT JOIN filtered_cnefe
      #     ON filtered_cnefe.lon BETWEEN input_table_db.lon_min AND input_table_db.lon_max
      #     AND filtered_cnefe.lat BETWEEN input_table_db.lat_min AND input_table_db.lat_max
      # WHERE filtered_cnefe.lon IS NOT NULL;"

  DBI::dbExecute(con, query_filter_cases_nearby)
  # b <- DBI::dbReadTable(con, 'output_db')

          # a <- DBI::dbGetQuery(con, query_filter_cases_nearby)
          # data.table::setDT(a)
          # a[, distancia_metros := dt_haversine(lat,lon , lat_cnefe, lon_cnefe)]
          # summary(a$distancia_metros)


  # UPDATE input_padrao_db: Remove observations found in previous step
  temp_n <- update_input_db(
    con,
    update_tb = 'input_table_db',
    reference_tb = 'output_db'
  )

  return(temp_n)
}
