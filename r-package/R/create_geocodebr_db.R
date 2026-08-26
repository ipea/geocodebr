create_geocodebr_db <- function(
  # nocov start
  db_path = "tempdir",
  n_cores = NULL,
  load_spatial = FALSE
) {
  # check input
  checkmate::assert_number(n_cores, lower = 1, finite = TRUE, null.ok = TRUE)

  # checkmate::assert_string(db_path, pattern = "tempdir|memory")

  # this creates a local database which allows DuckDB to
  # perform **larger-than-memory** workloads
  if (db_path == 'tempdir') {
    db_path <- tempfile(pattern = 'geocodebr', fileext = '.duckdb')
  }

  # create db connection
  # `shared_home` pertence ao construtor duckdb(), nao ao dbConnect(): passado ao
  # dbConnect() ele e engolido pelo `...` sem erro nem efeito. Declarado aqui, o
  # cache de extensoes em ~/.duckdb segue sendo reaproveitado -- o que importa
  # para a extensao espacial usada por geocode_reverso() -- e a mensagem
  # informativa do duckdb sobre esse diretorio deixa de ser emitida a cada chamada
  con <- duckdb::dbConnect(
    duckdb::duckdb(bigint = "integer64", shared_home = TRUE),
    dbdir = db_path
  ) # db_path ":memory:"

  # Set Number of cores for parallel operation
  if (is.null(n_cores)) {
    n_cores <- min(
      parallelly::availableCores(),
      parallelly::freeConnections()
    )
  }

  # Set threads
  DBI::dbExecute(con, sprintf("SET threads = %s;", n_cores))

  # Silence progress bar from duckdb
  DBI::dbExecute(con, "SET enable_progress_bar = false")

  # load spatial extension
  if (isTRUE(load_spatial)) {
    duckspatial::ddbs_install(conn = con, upgrade = FALSE, quiet = TRUE)
    duckspatial::ddbs_load(conn = con, quiet = TRUE)
  }


  # load parquet extension
  # DBI::dbExecute(con, "INSTALL parquet; LOAD parquet;")


  # Set Memory limit
  # DBI::dbExecute(con, "SET memory_limit = '8GB'")

  # DBI::dbExecute(con, "INSTALL arrow FROM community; LOAD arrow;")
  # DBI::dbExecute(con, "LOAD arrow;")

  return(con)
} # nocov end
