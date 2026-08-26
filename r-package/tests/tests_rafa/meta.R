# possibilidade de usar dados da meta e overtura para compelemtar enderecos
# mas pelo visto os dados deles vem do cnefe ?
library(arrow)
# install_arrow()
library(sf)
library(dplyr)
library(geobr)
library(duckdb)



# install extension

con <- duckdb::dbConnect(duckdb::duckdb(), dbdir=":memory:")  # run on memory
DBI::dbExecute(con, "FORCE INSTALL httpfs")
DBI::dbExecute(con, "LOAD httpfs")


ext <- DBI::dbGetQuery(con, "FROM duckdb_extensions()")




muni <- geobr::lookup_muni(name_muni = 'Guarulhos')
muni <- geobr::read_municipality(code_muni = muni$code_muni)

bb <- sf::st_bbox(muni)

# https://cran.r-project.org/web/packages/overturemapsr/index.html

# https://walker-data.com/posts/overture-buildings/
# https://data.humdata.org/organization/meta

buildings <- open_dataset('s3://overturemaps-us-west-2/release/2024-05-16-beta.0/theme=buildings?region=us-west-2')

nrow(buildings)


df <- arrow::open_dataset('s3://overturemaps-us-west-2/release/2024-09-18.0')
names(df)


library(overturemapsr)

t <- overturemapsr::get_all_overture_types()

d <- overturemapsr::dataset_path(overture_type = 'locality')

df <- overturemapsr::record_batch_reader(overture_type = 'place', bbox = bb)

df$bbox <- NULL
df$sources <- NULL
df$names <- NULL
sapply(df, class)






