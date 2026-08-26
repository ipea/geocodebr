# skip tests because they take too much time
skip_if(Sys.getenv("TEST_ONE") != "")
testthat::skip_on_cran()
testthat::skip_if_not_installed("arrow")


# amostra de pontos espaciais
points <- readRDS(
  system.file("extdata/pontos.rds", package = "geocodebr")
)

points <- points[1:10,]


tester <- function(pontos = points,
                   dist_max = 1000,
                   verboso = FALSE,
                   cache = TRUE,
                   n_cores = 1) {
  geocode_reverso(
    pontos = pontos,
    dist_max = dist_max,
    verboso = verboso,
    cache = cache,
    n_cores = n_cores
  )
}

test_that("expected output", {

  # radio de busca de 1 Km
  testthat::succeed(std_output <- tester())
  testthat::expect_true(nrow(std_output) == 4)

  # radio de busca de 5 Km
  testthat::succeed(std_output_5K <- tester(dist_max = 5000))
  testthat::expect_true(nrow(std_output_5K) == 9)

  # output in sf format
  testthat::expect_true(is(std_output , 'sf'))
})





test_that("errors with incorrect input", {

  # input nao eh sf
  testthat::expect_error(tester(unclass(points)))

  # input tem geometry diferente de POINT
  testthat::expect_error( tester(pontos = sf::st_cast(points, "LINESTRING")) )

  # input na projecao espacial errada
  testthat::expect_error(tester(sf::st_transform(points, 4326)))

  # input fora do bbox do Brazil
  p <- sf::st_sfc(sf::st_point(c(53.12682, 25.61657)))
  p <- sf::st_sf(p)
  sf::st_crs(p) <- 4674
  testthat::expect_error(tester(p))



  testthat::expect_error(tester(dist_max = 'A'))
  testthat::expect_error(tester(dist_max = NA))
  testthat::expect_error(tester(dist_max = TRUE))

  testthat::expect_error(tester(n_cores = "a"))
  testthat::expect_error(tester(n_cores = 0))
  testthat::expect_error(tester(n_cores = Inf))

  testthat::expect_error(tester(verboso = 1))
  testthat::expect_error(tester(verboso = NA))
  testthat::expect_error(tester(verboso = c(TRUE, TRUE)))

  testthat::expect_error(tester(cache = 1))
  testthat::expect_error(tester(cache = NA))
  testthat::expect_error(tester(cache = c(TRUE, TRUE)))
})

