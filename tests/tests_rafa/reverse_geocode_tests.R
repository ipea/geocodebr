devtools::load_all('.')
# library(geocodebr)
library(dplyr)
library(sf)


# input data

pontos <- readRDS(
   system.file("extdata/pontos.rds", package = "geocodebr")
   )

pontos <- pontos[1:500,]



# reverse geocode
bench::system_time(
 out <-  geocode_reverso(
   pontos = pontos,
   dist_max = 1000
   )
)

View(out)


# ttt <- data.frame(id=1, lat=-15.814192047159876, lon=-47.90534614672923)
# ttt <- sf::st_as_sf(
#   ttt,
#   coords = c("lon", "lat"),
#   crs = 4674
# )
#
# geocode_reverso(pontos = ttt)


b5 <- bench::mark(
  current = geocode_reverso(pontos = pontos, dist_max = 1000),
  iterations = 5,
  check = F
)

b5

## 500 pontos
#    expression      min   median `itr/sec` mem_alloc `gc/sec` n_itr  n_gc total_time result memory
#  v0.6.2           2.9s    3.02s     0.330     153MB     1.39     5    21      15.1s <NULL>
#  v0.6.2.9000      2.4s    2.49s     0.393    4.72MB    0.708     5     9      12.7s <NULL

## 1000 pontos
#   expression       min   median `itr/sec` mem_alloc `gc/sec` n_itr  n_gc total_time result
#       v0.6.2     4.05s    4.66s     0.217     161MB     1.04     5    24        23s <NULL>
#  v0.6.2.9000     3.15s    4.11s     0.236      95MB    0.378     5     8      21.2s <NULL>
