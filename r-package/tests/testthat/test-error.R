parent_function <- function() error_test()

error_test <- function() {
  geocodebr_error(c("test", "*" = "info"), call = rlang::caller_env())
}

test_that("erro funciona corretamente", {
  expect_error(parent_function(), class = "geocodebr_error_test")
  expect_error(parent_function(), class = "geocodebr_error")

  expect_snapshot(parent_function(), error = TRUE, cnd_class = TRUE)
})
