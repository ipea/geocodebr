# Usage: Rscript compare_results.R <a.parquet> <b.parquet>
# Reports identical() / all.equal() and, on mismatch, which columns/rows differ.
args <- commandArgs(trailingOnly = TRUE)
suppressPackageStartupMessages(library(arrow))
a <- as.data.frame(arrow::read_parquet(args[1]))
b <- as.data.frame(arrow::read_parquet(args[2]))
cat(sprintf("A: %d x %d | B: %d x %d\n", nrow(a), ncol(a), nrow(b), ncol(b)))
cat("identical():", identical(a, b), "\n")
if (!identical(a, b)) {
  cat("same names:", identical(names(a), names(b)), "\n")
  if (!identical(names(a), names(b))) { cat("A:", names(a), "\nB:", names(b), "\n") }
  cat("same classes:", identical(lapply(a, class), lapply(b, class)), "\n")
  cls <- data.frame(col = names(a), A = sapply(a, function(x) paste(class(x), collapse = "/")),
                    B = sapply(b[names(a)], function(x) paste(class(x), collapse = "/")))
  print(cls[cls$A != cls$B, ], row.names = FALSE)
  ae <- all.equal(a, b)
  cat("all.equal():", if (isTRUE(ae)) "TRUE" else paste(head(ae, 20), collapse = "\n  "), "\n")
  if (nrow(a) == nrow(b)) {
    for (cn in intersect(names(a), names(b))) {
      x <- a[[cn]]; y <- b[[cn]]
      d <- which(!(is.na(x) & is.na(y)) & (is.na(x) != is.na(y) | x != y))
      if (length(d)) {
        cat(sprintf("col %-28s differs in %d rows", cn, length(d)))
        if (is.numeric(x)) cat(sprintf(" | max abs diff %.3g", max(abs(x[d] - y[d]), na.rm = TRUE)))
        cat("\n")
        print(head(data.frame(row = d, A = x[d], B = y[d]), 5), row.names = FALSE)
      }
    }
  }
}
