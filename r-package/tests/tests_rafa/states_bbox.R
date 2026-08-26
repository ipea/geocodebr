# gera bbox de estados e municipios

library(sf)
library(dplyr)

# Load the state polygons
df <- geobr::read_state()

# Calculate bounding boxes of states
bounding_boxes <- df |>
  st_as_sf() |>                           # Ensure df is an sf object
  rowwise() |>                            # Process each polygon individually
  mutate(
    xmin = st_bbox(geom)["xmin"],      # Extract xmin from the bounding box
    ymin = st_bbox(geom)["ymin"],      # Extract ymin from the bounding box
    xmax = st_bbox(geom)["xmax"],      # Extract xmax from the bounding box
    ymax = st_bbox(geom)["ymax"]       # Extract ymax from the bounding box
  ) |>
  ungroup() |>                            # Unrowwise after rowwise operations
  select(abbrev_state, xmin, ymin, xmax, ymax) |> # Select desired columns
  st_drop_geometry()

# View the resulting bounding box data.frame
bounding_boxes

data.table::fwrite(bounding_boxes, './inst/extdata/states_bbox.csv')


head(input_table)

candidate_states <-
  subset(x = bounding_boxes,
         (xmin < bbox_lon_min | xmax > bbox_lon_max) &
         (ymin < bbox_lat_min | ymax > bbox_lat_max)
         )





# gerate states bbox -----------------------------------------------------------

states <- geobr::read_state(simplified = FALSE)

bbox_states2 <- states |>
  group_by(abbrev_state) |>
  mutate(xmin = sf::st_bbox(geom)[1] |> round(7),
         ymin = sf::st_bbox(geom)[2] |> round(7),
         xmax = sf::st_bbox(geom)[3] |> round(7),
         ymax = sf::st_bbox(geom)[4] |> round(7)
  ) |>
  sf::st_drop_geometry() |>
  select(abbrev_state, xmin, ymin, xmax, ymax)

data.table::setDT(bbox_states2)
bbox_states2$xmin |> nchar()

saveRDS(bbox_states2, './inst/extdata/states_bbox.rds')
