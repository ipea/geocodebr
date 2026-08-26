
devtools::load_all('.')
library(data.table)
library(dplyr)

# open input data
data_path <- system.file("extdata/large_sample.parquet", package = "geocodebr")
input_df <- arrow::read_parquet(data_path)


input_df$municipio <- enderecobr::padronizar_municipios(input_df$municipio)
input_df$estado <- enderecobr::padronizar_estados(input_df$uf)

# df = input_df
# N_groups = 4

balanced_grouping_dt <- function(df, N_groups) {

  # Convert to data.table (without copying if already DT)
  dt <- as.data.table(df)
  #setDT(df)

  # 1. Count rows per municipality block
  # 2. Sort blocks by size (largest first for best balancing)
  muni_sizes <- df[, .(n_rows = .N), by = .(estado, municipio)][order(-n_rows)]


  # 3. Greedy assignment of blocks to groups
  group_loads <- integer(N_groups)
  muni_sizes[, group := NA_integer_]


  for (i in seq_len(nrow(muni_sizes))) {
    # choose group with fewest rows so far
    g <- which.min(group_loads)
    muni_sizes$group[i] <- g
    group_loads[g] <- group_loads[g] + muni_sizes$n_rows[i]
  }


  # 4. Join group assignment back to original data
  df[muni_sizes, on = .(estado, municipio), "group" := i.group]

  return(df)
}

balanced_grouping_dplyr <- function(df, N_groups) {
  stopifnot(all(c("estado", "municipio") %in% names(df)))

  # 1. Count rows per municipality block
  # 2. Sort blocks by size (descending)
  muni_sizes <- df %>%
    count(estado, municipio, name = "n_rows") %>%
    arrange(desc(n_rows))

  # 3. Balanced assignment of blocks to groups
  # Track group loads
  group_loads <- rep(0, N_groups)
  muni_sizes$group <- NA_integer_


  for (i in seq_len(nrow(muni_sizes))) {
    # choose group with fewest rows so far
    g <- which.min(group_loads)
    muni_sizes$group[i] <- g
    group_loads[g] <- group_loads[g] + muni_sizes$n_rows[i]
  }


  # 4. Join assignment back to original data
  df_out <- df %>%
    left_join(muni_sizes %>% select(estado, municipio, group),
              by = c("estado", "municipio"))

  return(df_out)
}




df_dplyr <- balanced_grouping_dplyr(df = input_df, N_groups = 4)
df_dt <- balanced_grouping_dt(df = input_df, N_groups = 4)

n = 10
bench::mark(check = F, relative = T,

  dpylr =  balanced_grouping_dplyr(df = input_df, N_groups = n),
  dt = balanced_grouping_dt(df = input_df, N_groups = n)
)


n <- parallelly::availableCores() /2
df <- balanced_grouping_dt(df = input_df, N_groups = n)


# parallel callr --------------------------------------


library(future)
library(furrr)

future::plan(future::multisession(workers = n))


bench::bench_time(
  a <-   split(df, f = "group") |>
    furrr::future_map(
      .f = function(x){
        geocode(
          enderecos = x,
          campos_endereco = campos,
          n_cores = 1,
          resultado_completo = F,
          resolver_empates = T
        )
      }
    )
)

