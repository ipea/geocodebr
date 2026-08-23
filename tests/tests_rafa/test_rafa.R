# test
df_rp <- data.frame(
  estado = 'df',
  # cep=70355030,
  municipio='brasilia',
  logradouro = "sqs 308",
  bairro = 'asa sul'
  )

campos <- geocodebr::definir_campos(
  logradouro = 'logradouro',
  # numero = 'numero',
  # cep = 'cep',
  localidade = 'bairro',
  municipio = 'municipio',
  estado = 'estado'
)

test <- geocodebr::geocode(
  enderecos = df_rp,
  campos_endereco = campos,
  resultado_completo = T,
  verboso = T,
  resultado_sf = T
  )

mapview::mapview(test)



# NEXT CHANGES  ---------------------------
#
# #> using cache_dir and data_release as global variables
# https://stackoverflow.com/questions/12598242/global-variables-in-packages-in-r
#
# censobr_env <- new.env()
# censobr_env$data_release <- 'v0.1.0'
#


#> cache function delete data from previous package versions

# current cache
pkgv <- paste0('censobr_', 'v0.1.0' )
cache_dir <- tools::R_user_dir(pkgv, which = 'cache')

# determine old cache
dir_above <- dirname(cache_dir)
all_cache <- list.files(dir_above, pattern = 'censobr',full.names = TRUE)
old_cache <- all_cache[!grepl(pkgv, all_cache)]

# delete
unlink(old_cache, recursive = TRUE)


library(censobr)

censobr_cache(delete_file = 'all')

interview_manual(year = 2010)
interview_manual(year = 2000)
interview_manual(year = 1991) #
interview_manual(year = 1980) #
interview_manual(year = 1970)



# github actions ------------------------

usethis::use_github_action("test-coverage")
usethis::use_github_action("check-standard")
usethis::use_github_action("pkgdown")

# Coverage ------------------------
# usethis::use_coverage()
# usethis::use_github_action("test-coverage")

library(testthat)
library(covr)
Sys.setenv(NOT_CRAN = "true")



# each function separately
t1 <- covr::function_coverage(fun=geocode, test_file("tests/testthat/test-geocode.R"))
t1 <- covr::function_coverage(fun=definir_campos, test_file("tests/testthat/test-definir_campos.R"))
t1 <- covr::function_coverage(fun=download_cnefe, test_file("tests/testthat/test-download_cnefe.R"))
t1 <- covr::function_coverage(fun=listar_dados_cache, test_file("tests/testthat/test-cache.R"))
# t1 <- covr::function_coverage(fun=deletar_pasta_cache, test_file("tests/testthat/test-cache.R"))
t1 <- covr::function_coverage(fun=busca_por_cep, test_file("tests/testthat/test-busca_por_cep.R"))
t1 <- covr::function_coverage(fun=geocodebr_message, test_file("tests/testthat/test-message.R"))

t1

rep <- covr::report(t1)



# nocov start

# nocov end

# the whole package
Sys.setenv(NOT_CRAN = "true")
cov <- covr::package_coverage(path = ".", type = "tests", clean = FALSE)
cov

rep <- covr::report(t1)

x <- as.data.frame(cov)
covr::codecov( coverage = cov, token ='aaaaa' )






# checks spelling ----------------
library(spelling)
devtools::spell_check(pkg = ".", vignettes = TRUE, use_wordlist = TRUE)


### Check URL's ----------------

urlchecker::url_update()





# CMD Check --------------------------------
# Check package errors

# linux ubuntu-clang for CRAN
rhub::rhub_check(platforms = 'ubuntu-clang')

# run only the tests
Sys.setenv(NOT_CRAN = "true")
testthat::test_local()

# LOCAL
Sys.setenv(NOT_CRAN = "true")
devtools::check(pkg = ".",  cran = FALSE, env_vars = c(NOT_CRAN = "true"))


# Run all diagnostics on the current package
library(checktor)
results <- checktor::checktor()

# detecta problema de cpu < 2
devtools::check(remote = TRUE, manual = TRUE)

devtools::check(remote = TRUE, manual = TRUE, env_vars = c(NOT_CRAN = "false"))


# CRAN
Sys.setenv(NOT_CRAN = "false")
devtools::check(pkg = ".",  cran = TRUE, env_vars = c(NOT_CRAN = "false"))


# extrachecks -----------------
#' https://github.com/JosiahParry/extrachecks
#' remotes::install_github("JosiahParry/extrachecks")

library(extrachecks)
extrachecks::extrachecks()


# submit to CRAN -----------------
# usethis::use_cran_comments()


devtools::submit_cran()


# build binary -----------------
system("R CMD build . --resave-data") # build tar.gz




###
library(pkgdown)
library(usethis)
# usethis::use_pkgdown_github_pages() # only once
## coverage
usethis::use_coverage()
usethis::use_github_action("test-coverage")

pkgdown::build_site()
#
#
# ### cache
# tigris
# https://github.com/walkerke/tigris/blob/0f0d7992e0208b4c55a9fe8ac6c52f9e438a3b0c/R/helpers.R#L78
#
# https://github.com/walkerke/tigris/blob/0f0d7992e0208b4c55a9fe8ac6c52f9e438a3b0c/R/helpers.R#L78
#
# tidycensus
# https://github.com/walkerke/tidycensus/blob/master/R/search_variables.R



library(geobr)
library(censobr)
library(dplyr)
library(ggplot2)

fort_df <- geobr::lookup_muni(name_muni = 'Sao Paulo')
fort_code <- fort_df$code_muni
fort_wa <- read_weighting_area(code_weighting = fort_code,
                               year = 2010,
                               simplified = FALSE)



ggplot() +
  geom_sf(data=fort_wa)


# download household data
hs <- read_households(year = 2010,
                      showProgress = FALSE)


rent <- hs |>
  mutate( V0011 = as.character(V0011)) |>
  filter(V0011 %in% fort_wa$code_weighting) |>
  collect() |>
  group_by(V0011) |>                                                 # (a)
  summarize(avgrent=weighted.mean(x=V2011, w=V0010, na.rm=TRUE)) |>  # (b)
  collect()                                                          # (c)

head(rent)


for_sf <- left_join(fort_wa, rent, by = c('code_weighting'='V0011'))


ggplot() +
  geom_sf(data=for_sf, aes(fill = avgrent), color=NA)






# had CPU time 3 times elapsed time ----
# https://stackoverflow.com/questions/77323811/r-package-to-cran-had-cpu-time-5-times-elapsed-time

# Flavor: r-devel-linux-x86_64-debian-gcc
# Check: tests, Result: NOTE
# Running 'testthat.R' [161s/53s]
# Running R code in 'testthat.R' had CPU time 3 times elapsed time

library(testthat)
Sys.setenv(NOT_CRAN = "true")

files = list.files("tests/testthat", "test-", full.names = TRUE)

for (file in files[3]) {

  time = system.time(test_file(file))
  ratio = time[1] / time[3]
  if (ratio > 2) {
    print(time)
    stopf("Test file %s had CPU time %f times elapsed time", file, ratio)
  }
}
