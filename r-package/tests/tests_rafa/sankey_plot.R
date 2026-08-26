library(ggalluvial)

temp <- temp_dfgeo |> select(id, tipo_resultado, precisao) |> unique()
# 37.9s
### viable sequence of match types for really large datasets
all_possible_match_types <- c(
  "dn01", "da01",
  "dn02", "da02",
  "dn03", "da03",
  "dn04", "da04",
  "pn01", "pa01", "pn02", "pa02", "pn03", "pa03", #"pn04", "pa04", # too costly
  "dl01",
  "dl02",
  "dl03",
  "dl04",         # pl04",  # too costly
  "pl01", "pl02", "pl03",
  "dc01", "dc02", "db01", "dm01"
)



temp2 <- temp_dfgeo2 |> select(id, tipo_resultado2 =tipo_resultado, precisao2 = precisao) |> unique()
# 30s
all_possible_match_types <- c(
  "dn01", "da01",
  "dn02", "da02",
  "dn03", "da03",
  "dn04", "da04",
  "pn01", "pa01", "pn02", "pa02", "pn03", "pa03", #"pn04", "pa04", # too costly
  "dl01",         "pl01",
  "dl02",         "pl02",
  "dl03",         "pl03",
  "dl04",         # pl04",  # too costly
  "dc01", "dc02", "db01", "dm01"
)


df <- left_join(temp, temp2)


table(df$precisao,df$precisao2 )

table(df$precisao )

table(df$precisao2 )

data.table::setDT(df)[, Freq := 1]

df_agreg <- df[, .(Freq = .N), by = .(tipo_resultado, tipo_resultado2, precisao, precisao2)]
df_agreg <- df_agreg[tipo_resultado != tipo_resultado2]
df_agreg <- df_agreg[precisao != precisao2]

library(ggplot2)
library(ggalluvial)
library(ggplotly)


gg <- ggplot(df_agreg,
             aes(y = Freq, axis1 = tipo_resultado, axis2 = tipo_resultado2)) +
  geom_alluvium(aes(fill = tipo_resultado2), width = 1/12) +
  geom_stratum(width = 1/12, fill = "white", color = "grey") +
  geom_label(stat = "stratum", aes(label = after_stat(stratum)), size=2) +
  scale_x_discrete(limits = c("antes", "depois"), expand = c(.05, .05)) +
  # scale_fill_brewer(type = "qual", palette = "Set1") +
  scale_fill_viridis_d()

gg
# plotly::ggplotly(gg)

ggsave(gg, filename = 'ggaluvia.png', width = 18, height = 12, units='cm')



# pn01            da04
#
# dfall <- left_join(dfgeo, dfgeo2, by='id') |>
#   filter(tipo_resultado.x=='pn01' &
#            tipo_resultado.y=='da04')
#
# dfall$id

filter(dfgeo,id %in% c(1371)  )
filter(dfgeo2,id %in% c(1371)  )
#' por que id '463' nao foi encontrado na cat da01 ? e sim no da02
#' em tese, nao deveria ter nenhuma transicao de p para d
#' outro exemplo: de pa01 para da03
#'  - ora, se foi pa01, encontrou bairro e cep
#'  - se depois achou com da03, entao achou com logradouro determ, e soh o bairro mas nao o cep
#'
#' outro caso pn01 e depois vira da04
#' pn03 e depois vira da04





############## sankey plot ----------------------------------------
library(ggplot2)
library(ggsankey)
library(dplyr)
library(data.table)

system.time(danid <- dani()) # 60.10
system.time(rafad <- rafa()) # 39.54


df <- left_join(select(danid, c('id', 'match_type')),
                select(rafad, c('id', 'match_type')), by='id')

data.table::setDT(df)
data.table::setnames(
  df,
  old = c('match_type.x', 'match_type.y'),
  new = c('case_dani', 'case_rafa') )


transition_mtrx <- round(table(df$case_dani, df$case_rafa) / nrow(df)*100, 1)


df[, case_dani := as.integer(gsub('case_', '', case_dani)) ]
df_count <- df[, .(count = round(.N / nrow(df)*100, 2)), by= .(case_dani, case_rafa)]

# df_long <- data.table::melt(data = df, id.vars='id')
# head(df_long)

# df_sankey <- ggsankey::make_long(df, case_dani, case_rafa)
df_sankey <- ggsankey::make_long(df_count, case_dani, case_rafa, value = count)
df_sankey$value <- round(df_sankey$value / nrow(df)*100, 2)
head(df_sankey)

#cats <- c(1:4, 44, 5:12)
cats <- c(12:5, 44, 4:1)
df_sankey$node <- factor(x = df_sankey$node,
                         levels = cats,
                         ordered = T)

df_sankey$next_node <- factor(x = df_sankey$next_node,
                              levels = cats,
                              ordered = T)

fig <- ggplot(data = df_sankey,
              aes(x = x,
                  next_x = next_x,
                  node = node,
                  next_node = next_node,
                  fill = factor(node)
                  , label = value
              )) +
  geom_sankey() +
  theme_sankey(base_size = 16)  + geom_sankey_label()

fig
plotly::ggplotly(fig)


library(plotly)

fig <- plot_ly(
  type = "sankey",
  orientation = "h",

  node = list(
    label = c("A1", "A2", "B1", "B2", "C1", "C2"),
    color = c("blue", "blue", "blue", "blue", "blue", "blue"),
    pad = 15,
    thickness = 20,
    line = list(
      color = "black",
      width = 0.5
    )
  ),

  link = list(
    source = c(0,1,0,2,3,3),
    target = c(2,3,3,4,4,5),
    value =  c(8,4,2,8,4,2)
  )
)
fig <- fig %>% layout(
  title = "Basic Sankey Diagram",
  font = list(
    size = 10
  )
)

fig





df_count <- df[, .(count = round(.N / nrow(df)*100, 2)), by= .(case_dani, case_rafa)]

df_sankey <- ggsankey::make_long(df, case_dani, case_rafa)

df_sankey <- left_join(df_sankey, df_count,
          by=c('node'='case_dani', 'next_node' = 'case_rafa'))


head(df_sankey)

#cats <- c(1:4, 44, 5:12)
cats <- c(12:5, 44, 4:1)
df_sankey$node <- factor(x = df_sankey$node,
                         levels = cats,
                         ordered = T)

df_sankey$next_node <- factor(x = df_sankey$next_node,
                              levels = cats,
                              ordered = T)
data.table::setDT(df_sankey)[, count2 := ifelse(is.na(count), lead(count), count)]
head(df_sankey)

fig <- ggplot(data = df_sankey,
              aes(x = x,
                  next_x = next_x,
                  node = node,
                  next_node = next_node,
                  fill = factor(node)
                  , label = count2
              )) +
  geom_sankey() +
  theme_sankey(base_size = 16)  + geom_sankey_label()

fig
plotly::ggplotly(fig)
