# Plan — Audit: CNEFE `dados_agregados` v0.4.1 vs v0.5.0

**Status:** DRAFT
**Date:** 2026-09-15

---

## Context

Two releases of the pre-processed CNEFE reference data used by `{geocodebr}` sit side by side on STORAGE6:

- `\\STORAGE6\bases\DADOS\PUBLICO\CNEFE\cnefe_padrao_geocodebr\2022\v0.4.1\dados_agregados`
- `\\STORAGE6\bases\DADOS\PUBLICO\CNEFE\cnefe_padrao_geocodebr\2022\v0.5.0\dados_agregados`

Both contain the same **12 parquet tables** with identical filenames, but v0.5.0 is **~28% smaller on disk**
(2.76 GB → 1.99 GB). These files are the payload that `download_cnefe()` pulls into the user cache
(the release tag is pinned by the `data_release` constant at `r-package/R/cache.R:1`), so a size change of
this magnitude is either a deliberate encoding win or silent data loss. We need to know which, **per table**,
before this release is adopted.

Deliverable: a per-table comparison of row count, column count, column names, and column classes (schema),
plus a byte-level attribution of *where* the size difference comes from, and targeted value checks to confirm
no content was lost.

### Preliminary probe (already run, read-only — this is the hypothesis the audit must confirm at scale)

`municipio.parquet` — same 5,570 rows, but the schema changed:

| column | v0.4.1 | v0.5.0 |
|---|---|---|
| `code_muni` | *absent* | **`int32` (new)** |
| `n_setor` | *absent* | **`int32` (new)** |
| `lon` | `double` | **`float`** |
| `lat` | `double` | **`float`** |
| `cod_setor` | `string` | **`int64`** |

`municipio_cep.parquet` — 928,913 → 928,905 rows (**−8**), same ZSTD codec, same 8 row groups. Per-column
compressed bytes:

| column | v0.4.1 | v0.5.0 | note |
|---|---|---|---|
| `lat` | 5.84 MB | 2.22 MB | `double`→`float` halves the uncompressed payload |
| `lon` | 5.57 MB | 1.91 MB | idem |
| `endereco_completo` | 2.55 MB | 1.13 MB | **same uncompressed bytes** — compressed better, so row ordering changed |
| `cep` | 2.26 MB | 1.00 MB | idem |
| `cod_setor` | 1.13 MB | 1.01 MB | `string`→`int64` |

So three candidate mechanisms: **(1)** float64→float32 downcast of coordinates, **(2)** string→integer typing
of `cod_setor`, **(3)** a change in row sort order that made ZSTD far more effective on the high-cardinality
string columns. New columns (`code_muni`, `n_setor`) push the other way. The audit quantifies each.

**Precision caveat to flag:** `float32` holds ~7 significant decimal digits. At Brazilian longitudes
(`-73`…`-34`) that is ~7 digits total, leaving ~5 decimal places ≈ **~1 m of positional resolution**. That is
almost certainly fine next to CNEFE's own accuracy, but it is a deliberate, irreversible precision cut and it
belongs in the report explicitly — as does whether it materially moves any coordinate.

---

## Approach

One self-contained R script, run once, driving **DuckDB** (per-column byte accounting via `parquet_metadata()`,
which reads only the file footer) and **Arrow** (schema types). Metadata-only passes cost seconds, not minutes,
because no data pages are read. Value checks are pushed down as DuckDB aggregates — nothing is materialised in R
(see the standing constraint: joins/aggregations stay in DuckDB).

### Step 1 — Inventory

List both directories; assert the same 12 basenames exist in each. Report any file present in only one version
rather than silently skipping it.

### Step 2 — Table-level metadata (`parquet_file_metadata`, `parquet_schema`)

For each of the 24 files: file size on disk, `num_rows`, `num_row_groups`, `format_version`, column count.

### Step 3 — Schema diff (Arrow `ParquetFileReader$GetSchema()`)

Per table, build the union of column names across both versions and classify each column:

- `IDENTICAL` — present in both, same Arrow type
- `TYPE_CHANGED` — present in both, type differs (record `old → new`)
- `ADDED` — only in v0.5.0
- `REMOVED` — only in v0.4.1

### Step 4 — Byte attribution (`parquet_metadata`)

Per table × column: `sum(total_compressed_size)`, `sum(total_uncompressed_size)`, `compression` codec,
distinct `encodings`. Then compute, per table, the delta in compressed bytes broken down by column, so the
size drop is *explained* rather than asserted. Split the delta into:

- bytes saved by narrower physical types (`double`→`float`, `string`→`int64`)
- bytes saved at constant uncompressed size (i.e. **pure compression/ordering win**)
- bytes added by the new columns

### Step 5 — Targeted value checks (DuckDB aggregates, no data pulled into R)

Per table, for the columns present in **both** versions:

- row count by `estado` (catches region-specific loss — the −8 rows in `municipio_cep` must be located)
- `count(DISTINCT municipio)`, and `count(DISTINCT cep)` where the column exists
- `min`/`max`/`avg` of `lat`, `lon`; count of NULLs per shared column
- `sum(n_casos)` where present — the strongest single "did we lose records" signal
- coordinate-precision check: on a bounded sample, `max(abs(lat_v041 - lat_v050))` after casting v0.4.1 to
  `FLOAT`, to confirm the downcast is the whole story and no reprojection/recomputation happened

Joins for the coordinate check are keyed on the natural key of each table (e.g. `estado, municipio,
endereco_completo` + whatever discriminator the table adds) and executed inside DuckDB.

### Step 6 — Summary table + report

The headline artifact, one row per table:

| tabela | linhas v0.4.1 | linhas v0.5.0 | Δ linhas | Δ % | cols v0.4.1 | cols v0.5.0 | cols +/− | tipos alterados | MB v0.4.1 | MB v0.5.0 | Δ MB | Δ % |
|---|---|---|---|---|---|---|---|---|---|---|---|---|

Supporting tables: the per-column schema diff, and the per-column byte attribution for the largest tables.

---

## Files

| Path | What |
|---|---|
| `quality_reports/diagnoses/2026-09-15_cnefe-v041-vs-v050-auditoria.md` | **New.** The report: summary table, schema diff, byte attribution, value checks, verdict on the size drop. |
| `quality_reports/diagnoses/compare_cnefe_releases.R` | **New.** The reusable script that produced it — parameterised on the two version paths so it can be re-run for the next release. |

Both under the **repo-root** `quality_reports/` (the canonical one per `CLAUDE.md`), not `r-package/quality_reports/`.

Nothing under `r-package/R/`, `tests/`, or `DESCRIPTION` is touched, so `/r-package-check` is not gated on this
work and the pre-commit hooks (`readme-rmd-rendered`, `codemeta-description-updated`, `pkgdown`) are unaffected.

---

## Verification

1. **Script runs clean end to end** — `Rscript quality_reports/diagnoses/compare_cnefe_releases.R`, exit 0,
   no warnings about unreadable files.
2. **Inventory is complete** — the summary table has exactly 12 rows and no `NA` in the row/column-count columns;
   any file missing from one version is named explicitly.
3. **Byte attribution reconciles** — for each table, the sum of the per-column compressed-byte deltas equals the
   table's total compressed-byte delta to within parquet footer/page-header overhead (report the residual, don't
   hide it). This is the check that makes the "why is it smaller" answer trustworthy rather than a narrative.
4. **Every row-count delta is explained** — any table with `Δ linhas ≠ 0` gets a located cause (which `estado`,
   how many, plausible reason: dedup, filtered invalid geometry, upstream CNEFE change). An unexplained
   negative delta is a **blocking finding** and goes at the top of the report, not in a footnote.
5. **Spot-check by hand** — independently re-read two tables (one small, one of the four large
   `*_numero*` tables) with `arrow::open_dataset()$num_rows` and confirm the numbers match the report.

---

## Open questions for the report to answer (not for the plan)

- Is the −8 row delta in `municipio_cep` isolated, or does every table lose rows?
- Was the row re-ordering deliberate (a sort added to the pre-processing) or incidental? Affects whether the
  compression win is stable for future releases.
- Do `code_muni` / `n_setor` need to be consumed by `{geocodebr}`, or are they inert payload? If inert, they are
  pure download cost for every user.
- Does `cod_setor` as `int64` break any downstream string handling in `R/` (the output column is user-facing,
  documented in `man/roxygen/templates/precision_section.R`)?
