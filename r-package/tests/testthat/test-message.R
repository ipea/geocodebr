parent_function <- function() message_test()

message_test <- function() geocodebr_message(c("*" = "info"))

test_that("message_works_correctly", {
  expect_message(parent_function(), class = "geocodebr_message_test")
  expect_message(parent_function(), class = "geocodebr_message")

  expect_snapshot(parent_function(), cnd_class = TRUE)

  expect_message(message_standardizing_addresses())
  expect_message(message_baixando_cnefe())
  expect_message(message_looking_for_matches())
  expect_message(message_preparando_output())
})


# error
test_that("message_does_NOT_work_correctly", {
  expect_error(message_test("banana"))
})







