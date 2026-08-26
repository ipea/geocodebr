# gera bbox de estados e municipios

library(sf)
library(geobr)
library(dplyr)
library(geoarrow)

# Load the state polygons
df <- geobr::read_municipality(year = 2022, simplified = T)

# # Calculate bounding boxes of states
# bounding_boxes <- df |>
#   st_as_sf() |>                           # Ensure df is an sf object
#   rowwise() |>                            # Process each polygon individually
#   mutate(
#     xmin = st_bbox(geometry)["xmin"],      # Extract xmin from the bounding box
#     ymin = st_bbox(geometry)["ymin"],      # Extract ymin from the bounding box
#     xmax = st_bbox(geometry)["xmax"],      # Extract xmax from the bounding box
#     ymax = st_bbox(geometry)["ymax"]       # Extract ymax from the bounding box
#   ) |>
#   ungroup() |>                            # Unrowwise after rowwise operations
#   select(code_muni, xmin, ymin, xmax, ymax) |> # Select desired columns
#   st_drop_geometry()
#
# # View the resulting bounding box data.frame
# head(bounding_boxes)
#
# data.table::fwrite(bounding_boxes, './inst/extdata/munis_bbox.csv')
#
#
# head(input_table)
#
# candidate_states <-
#   subset(x = bounding_boxes,
#          (xmin < bbox_lon_min | xmax > bbox_lon_max) &
#            (ymin < bbox_lat_min | ymax > bbox_lat_max)
#   )
#








# Calculate bounding boxes of municipalities
bounding_boxes <- df |>
  rowwise() |>                            # Process each polygon individually
  mutate(
    geometry = st_as_sfc(st_bbox(geometry))  # Create bbox geometry
  ) |>
  ungroup() |>                            # Unrowwise after rowwise operations
  select(code_muni, geometry) |>
  st_set_geometry("geometry")            # Set bbox_geom as the active geometry

# View the resulting bounding box sf object
head(bounding_boxes)

# mapview::mapview(bounding_boxes) + df
bounding_boxes <- bounding_boxes |>
  mutate(code_muni = as.integer(code_muni))
  # select(code_muni, geometry = bbox_geom, - geom) |>
  # st_set_geometry("geometry")            # Set bbox_geom as the active geometry

head(bounding_boxes)

# # arrow::write_parquet(bounding_boxes2, "munis_bbox_2022.parquet")
# arrow::write_parquet(bounding_boxes, "munis_bbox_2022.parquet",
#                      compression='zstd',
#                      compression_level = 7)
#

# remove the classes "tbl_df" "tbl" from an object
class(bounding_boxes) <- setdiff(class(bounding_boxes), c("tbl_df", "tbl"))

duckspatial::ddbs_write_dataset(
  data = bounding_boxes,
  path = './inst/extdata/munis_bbox_2022.parquet',
  crs = "EPSG:4674",
  overwrite = T,
  parquet_compression = "ZSTD",
  quiet = TRUE
)



