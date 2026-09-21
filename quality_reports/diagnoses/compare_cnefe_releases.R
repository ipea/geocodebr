# -----------------------------------------------------------------------------
# Auditoria: comparacao de dois releases do CNEFE pre-processado (dados_agregados)
#
# Compara, tabela a tabela: numero de linhas, numero de colunas, quais colunas
# existem, classes das colunas (schema), e atribuicao byte-a-byte da diferenca
# de tamanho em disco (coluna por coluna, via metadados do parquet).
#
# Le apenas o *footer* dos arquivos parquet -- nenhuma pagina de dados e lida
# nas Etapas 1-4, entao o custo e de segundos, nao de minutos.
#
# Uso:
#   Rscript quality_reports/diagnoses/compare_cnefe_releases.R [dir_v1] [dir_v2]
# -----------------------------------------------------------------------------

suppressPackageStartupMessages({
  library(arrow)
  library(duckdb)
  library(DBI)
  library(data.table)
})

args <- commandArgs(trailingOnly = TRUE)

BASE <- "//STORAGE6/bases/DADOS/PUBLICO/CNEFE/cnefe_padrao_geocodebr/2022"
V1_DIR <- if (length(args) >= 1) args[1] else file.path(BASE, "v0.4.1", "dados_agregados")
V2_DIR <- if (length(args) >= 2) args[2] else file.path(BASE, "v0.5.0", "dados_agregados")

V1 <- basename(dirname(V1_DIR))
V2 <- basename(dirname(V2_DIR))

OUT_DIR <- if (nzchar(Sys.getenv("CNEFE_AUDIT_OUT"))) {
  Sys.getenv("CNEFE_AUDIT_OUT")
} else {
  file.path(tempdir(), "cnefe_audit")
}
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)

msg <- function(...) cat(sprintf(...), "\n", sep = "")

msg("== Auditoria CNEFE: %s vs %s ==", V1, V2)
msg("v1: %s", V1_DIR)
msg("v2: %s", V2_DIR)
msg("saida: %s", OUT_DIR)


# -- Etapa 1: inventario -------------------------------------------------------

f1 <- sort(basename(list.files(V1_DIR, pattern = "\\.parquet$")))
f2 <- sort(basename(list.files(V2_DIR, pattern = "\\.parquet$")))
tabelas <- sort(union(f1, f2))

so_v1 <- setdiff(f1, f2)
so_v2 <- setdiff(f2, f1)

msg("\n-- Etapa 1: inventario --")
msg("tabelas em %s: %d | em %s: %d | uniao: %d", V1, length(f1), V2, length(f2), length(tabelas))
if (length(so_v1)) msg("APENAS em %s: %s", V1, paste(so_v1, collapse = ", "))
if (length(so_v2)) msg("APENAS em %s: %s", V2, paste(so_v2, collapse = ", "))
if (!length(so_v1) && !length(so_v2)) msg("Mesmo conjunto de arquivos nas duas versoes.")


con <- dbConnect(duckdb::duckdb())
on.exit(dbDisconnect(con, shutdown = TRUE), add = TRUE)

qs <- function(x) dbQuoteString(con, x)


# -- Etapas 2 e 3: metadados de arquivo + schema -------------------------------

# Schema de um parquet, como data.table (coluna, tipo arrow, posicao)
le_schema <- function(path) {
  if (!file.exists(path)) return(NULL)
  sch <- ParquetFileReader$create(path)$GetSchema()
  data.table(
    coluna   = sch$names,
    tipo     = vapply(seq_along(sch$names), function(i) sch$field(i - 1L)$type$ToString(), character(1)),
    posicao  = seq_along(sch$names)
  )
}

# Metadados de arquivo, via duckdb (le so o footer)
le_file_meta <- function(path) {
  if (!file.exists(path)) return(NULL)
  as.data.table(dbGetQuery(con, sprintf(
    "SELECT num_rows, num_row_groups, format_version FROM parquet_file_metadata(%s)", qs(path)
  )))
}

# Bytes por coluna, via duckdb
le_col_bytes <- function(path) {
  if (!file.exists(path)) return(NULL)
  as.data.table(dbGetQuery(con, sprintf(
    "SELECT path_in_schema AS coluna,
            any_value(compression)                 AS compressao,
            string_agg(DISTINCT encodings, ' | ')  AS encodings,
            sum(total_compressed_size)::BIGINT     AS bytes_comp,
            sum(total_uncompressed_size)::BIGINT   AS bytes_uncomp
     FROM parquet_metadata(%s)
     GROUP BY 1", qs(path)
  )))
}

msg("\n-- Etapas 2-4: metadados, schema e bytes por coluna --")

resumo_l   <- list()
schema_l   <- list()
bytes_l    <- list()

for (tb in tabelas) {
  p1 <- file.path(V1_DIR, tb)
  p2 <- file.path(V2_DIR, tb)

  s1 <- le_schema(p1); s2 <- le_schema(p2)
  m1 <- le_file_meta(p1); m2 <- le_file_meta(p2)
  b1 <- le_col_bytes(p1); b2 <- le_col_bytes(p2)

  # --- schema diff (Etapa 3)
  sd <- merge(
    if (is.null(s1)) data.table(coluna = character(), tipo = character(), posicao = integer()) else s1,
    if (is.null(s2)) data.table(coluna = character(), tipo = character(), posicao = integer()) else s2,
    by = "coluna", all = TRUE, suffixes = c("_v1", "_v2")
  )
  sd[, status := fifelse(is.na(tipo_v1), "ADICIONADA",
                 fifelse(is.na(tipo_v2), "REMOVIDA",
                 fifelse(tipo_v1 != tipo_v2, "TIPO_ALTERADO", "IDENTICA")))]
  sd[, tabela := tb]

  # --- bytes por coluna (Etapa 4)
  bd <- merge(
    if (is.null(b1)) data.table(coluna = character()) else b1,
    if (is.null(b2)) data.table(coluna = character()) else b2,
    by = "coluna", all = TRUE, suffixes = c("_v1", "_v2")
  )
  for (cl in c("bytes_comp_v1", "bytes_comp_v2", "bytes_uncomp_v1", "bytes_uncomp_v2")) {
    if (!cl %in% names(bd)) bd[, (cl) := NA_real_]
    set(bd, which(is.na(bd[[cl]])), cl, 0)
  }
  bd[, `:=`(
    delta_comp   = bytes_comp_v2 - bytes_comp_v1,
    delta_uncomp = bytes_uncomp_v2 - bytes_uncomp_v1
  )]
  bd <- merge(bd, sd[, .(coluna, tipo_v1, tipo_v2, status)], by = "coluna", all.x = TRUE)
  bd[, tabela := tb]

  # --- resumo por tabela (Etapa 2 + 6)
  n1 <- if (is.null(m1)) NA_real_ else as.numeric(m1$num_rows)
  n2 <- if (is.null(m2)) NA_real_ else as.numeric(m2$num_rows)
  tam1 <- if (file.exists(p1)) file.size(p1) else NA_real_
  tam2 <- if (file.exists(p2)) file.size(p2) else NA_real_

  resumo_l[[tb]] <- data.table(
    tabela        = tb,
    linhas_v1     = n1,
    linhas_v2     = n2,
    d_linhas      = n2 - n1,
    d_linhas_pct  = 100 * (n2 - n1) / n1,
    cols_v1       = if (is.null(s1)) NA_integer_ else nrow(s1),
    cols_v2       = if (is.null(s2)) NA_integer_ else nrow(s2),
    cols_add      = sd[status == "ADICIONADA", .N],
    cols_rem      = sd[status == "REMOVIDA", .N],
    tipos_alt     = sd[status == "TIPO_ALTERADO", .N],
    mb_v1         = tam1 / 1024^2,
    mb_v2         = tam2 / 1024^2,
    d_mb          = (tam2 - tam1) / 1024^2,
    d_mb_pct      = 100 * (tam2 - tam1) / tam1,
    rowgroups_v1  = if (is.null(m1)) NA_integer_ else m1$num_row_groups,
    rowgroups_v2  = if (is.null(m2)) NA_integer_ else m2$num_row_groups,
    fmt_v1        = if (is.null(m1)) NA_character_ else as.character(m1$format_version),
    fmt_v2        = if (is.null(m2)) NA_character_ else as.character(m2$format_version)
  )

  schema_l[[tb]] <- sd
  bytes_l[[tb]]  <- bd

  msg("  %-52s  %12.0f -> %12.0f linhas | %8.1f -> %8.1f MB",
      tb, n1, n2, tam1 / 1024^2, tam2 / 1024^2)
}

resumo <- rbindlist(resumo_l)
schema <- rbindlist(schema_l)
bytes  <- rbindlist(bytes_l)

setcolorder(schema, c("tabela", "coluna", "tipo_v1", "tipo_v2", "status", "posicao_v1", "posicao_v2"))
setcolorder(bytes, c("tabela", "coluna", "status", "tipo_v1", "tipo_v2"))


# -- Reconciliacao da atribuicao de bytes (verificacao 3 do plano) -------------

recon <- bytes[, .(delta_colunas = sum(delta_comp)), by = tabela]
recon <- merge(recon, resumo[, .(tabela, delta_arquivo = (mb_v2 - mb_v1) * 1024^2)], by = "tabela")
recon[, residuo := delta_arquivo - delta_colunas]
recon[, residuo_pct := 100 * residuo / delta_arquivo]

msg("\n-- Reconciliacao: soma dos deltas por coluna vs delta do arquivo --")
print(recon[, .(tabela,
                delta_arquivo_mb = round(delta_arquivo / 1024^2, 2),
                delta_colunas_mb = round(delta_colunas / 1024^2, 2),
                residuo_kb       = round(residuo / 1024, 1),
                residuo_pct      = round(residuo_pct, 2))])


# -- Saida ---------------------------------------------------------------------

fwrite(resumo, file.path(OUT_DIR, "resumo_tabelas.csv"))
fwrite(schema, file.path(OUT_DIR, "schema_diff.csv"))
fwrite(bytes,  file.path(OUT_DIR, "bytes_por_coluna.csv"))
fwrite(recon,  file.path(OUT_DIR, "reconciliacao_bytes.csv"))

msg("\n-- Resumo por tabela --")
print(resumo[, .(tabela, linhas_v1, linhas_v2, d_linhas,
                 cols_v1, cols_v2, cols_add, cols_rem, tipos_alt,
                 mb_v1 = round(mb_v1, 1), mb_v2 = round(mb_v2, 1),
                 d_mb_pct = round(d_mb_pct, 1))])

msg("\n-- Totais --")
msg("linhas: %.0f -> %.0f (%+.0f, %+.3f%%)",
    sum(resumo$linhas_v1), sum(resumo$linhas_v2),
    sum(resumo$linhas_v2) - sum(resumo$linhas_v1),
    100 * (sum(resumo$linhas_v2) - sum(resumo$linhas_v1)) / sum(resumo$linhas_v1))
msg("disco:  %.1f -> %.1f MB (%+.1f MB, %+.1f%%)",
    sum(resumo$mb_v1), sum(resumo$mb_v2),
    sum(resumo$mb_v2) - sum(resumo$mb_v1),
    100 * (sum(resumo$mb_v2) - sum(resumo$mb_v1)) / sum(resumo$mb_v1))

msg("\n-- Colunas nao identicas (schema) --")
print(schema[status != "IDENTICA", .(tabela, coluna, tipo_v1, tipo_v2, status)])

msg("\n-- Atribuicao do delta de bytes, por coluna (agregado sobre as 12 tabelas) --")
agg <- bytes[, .(
  delta_comp_mb   = sum(delta_comp) / 1024^2,
  delta_uncomp_mb = sum(delta_uncomp) / 1024^2,
  n_tabelas       = .N
), by = .(coluna)][order(delta_comp_mb)]
print(agg)

msg("\nOK. CSVs em: %s", OUT_DIR)
