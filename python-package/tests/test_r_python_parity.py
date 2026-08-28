import shutil
import subprocess
import textwrap
from pathlib import Path

import math
from collections import Counter

import pyarrow as pa
import pyarrow.csv as pv
import pyarrow.parquet as pq
import pyarrow.types as patypes
import pytest

from geocodebr import definir_campos, definir_pasta_cache, geocode


R_SCRIPT = shutil.which("Rscript")
if R_SCRIPT is None:
    for candidate in sorted(Path("C:/Program Files/R").glob("R-*/bin/Rscript.exe"), reverse=True):
        if candidate.exists():
            R_SCRIPT = str(candidate)
            break


pytestmark = pytest.mark.r_parity


def test_geocode_matches_r_small_sample(repo_root, tmp_path):
    _require_r_parity()
    cache_dir = tmp_path / "cache"
    r_output = _run_r_geocode(
        repo_root=repo_root,
        dataset="small",
        input_path=repo_root / "r-package" / "inst" / "extdata" / "small_sample.csv",
        cache_dir=cache_dir,
        output_path=tmp_path / "r_small.parquet",
    )
    py_output = _run_python_geocode(
        dataset="small",
        input_path=repo_root / "r-package" / "inst" / "extdata" / "small_sample.csv",
        cache_dir=cache_dir,
    )

    diffs = run_all_comparisons(py_output, r_output)

    if diffs:
        report = "\n".join(diffs)
        pytest.fail(
            f"Parity check failed for small sample:\n\n{report}"
        )
    # _assert_tables_identical(py_output, r_output)


def test_geocode_matches_r_large_sample(repo_root, tmp_path):
    _require_r_parity()
    cache_dir = tmp_path / "cache"
    r_output = _run_r_geocode(
        repo_root=repo_root,
        dataset="large",
        input_path=repo_root / "r-package" / "inst" / "extdata" / "large_sample.parquet",
        cache_dir=cache_dir,
        output_path=tmp_path / "r_large.parquet",
    )
    py_output = _run_python_geocode(
        dataset="large",
        input_path=repo_root / "r-package" / "inst" / "extdata" / "large_sample.parquet",
        cache_dir=cache_dir,
    )

    diffs = run_all_comparisons(py_output, r_output)

    if diffs:
        report = "\n".join(diffs)
        pytest.fail(
            f"Parity check failed for large sample:\n\n{report}"
        )
#     _assert_tables_identical(py_output, r_output)


@pytest.fixture(scope="session")
def repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _require_r_parity() -> None:
    if R_SCRIPT is None:
        pytest.skip("Rscript not found in PATH.")


def _run_python_geocode(dataset: str, input_path: Path, cache_dir: Path) -> pa.Table:
    definir_pasta_cache(str(cache_dir), verboso=False)
    if dataset == "small":
        enderecos = pv.read_csv(input_path)
        campos = definir_campos(
            logradouro="nm_logradouro",
            numero="Numero",
            cep="Cep",
            localidade="Bairro",
            municipio="nm_municipio",
            estado="nm_uf",
        )
    elif dataset == "large":
        enderecos = pq.read_table(input_path)
        campos = definir_campos(
            logradouro="logradouro",
            numero="numero",
            cep="cep",
            localidade="bairro",
            municipio="municipio",
            estado="uf",
        )
    else:
        raise ValueError(f"Unknown dataset: {dataset}")

    return geocode(
        enderecos=enderecos,
        campos_endereco=campos,
        resultado_completo=True,
        resolver_empates=True,
        resultado_sf=False,
        h3_res=None,
        padronizar_enderecos=True,
        verboso=False,
        cache=True,
        n_cores=1,
    )


def _run_r_geocode(
    repo_root: Path,
    dataset: str,
    input_path: Path,
    cache_dir: Path,
    output_path: Path,
) -> pa.Table:
    r_code = textwrap.dedent(
        r"""
        args <- commandArgs(trailingOnly = TRUE)
        repo_root <- normalizePath(args[[1]], winslash = "/", mustWork = TRUE)
        dataset <- args[[2]]
        input_path <- normalizePath(args[[3]], winslash = "/", mustWork = TRUE)
        cache_dir <- normalizePath(args[[4]], winslash = "/", mustWork = FALSE)
        output_path <- args[[5]]

        lib <- tempfile("geocodebr-r-lib-")
        dir.create(lib, recursive = TRUE)
        .libPaths(c(lib, .libPaths()))

        install_result <- system2(
          file.path(R.home("bin"), "R"),
          c("CMD", "INSTALL", "-l", lib, file.path(repo_root, "r-package")),
          stdout = TRUE,
          stderr = TRUE
        )
        if (!identical(attr(install_result, "status"), NULL)) {
          cat(install_result, sep = "\n")
          stop("Could not install local R package geocodebr.")
        }
        if (!"geocodebr" %in% rownames(installed.packages(lib.loc = lib))) {
          cat(install_result, sep = "\n")
          stop("Local R package geocodebr was not installed into temporary library.")
        }

        suppressPackageStartupMessages(library(geocodebr, lib.loc = lib))
        suppressPackageStartupMessages(library(arrow))

        geocodebr::definir_pasta_cache(cache_dir, verboso = FALSE)

        if (dataset == "small") {
          enderecos <- read.csv(input_path, stringsAsFactors = FALSE)
          campos <- geocodebr::definir_campos(
            logradouro = "nm_logradouro",
            numero = "Numero",
            cep = "Cep",
            localidade = "Bairro",
            municipio = "nm_municipio",
            estado = "nm_uf"
          )
        } else if (dataset == "large") {
          enderecos <- arrow::read_parquet(input_path)
          campos <- geocodebr::definir_campos(
            logradouro = "logradouro",
            numero = "numero",
            cep = "cep",
            localidade = "bairro",
            municipio = "municipio",
            estado = "uf"
          )
        } else {
          stop("Unknown dataset")
        }

        out <- geocodebr::geocode(
          enderecos = enderecos,
          campos_endereco = campos,
          resultado_completo = TRUE,
          resolver_empates = TRUE,
          resultado_sf = FALSE,
          h3_res = NULL,
          padronizar_enderecos = TRUE,
          verboso = FALSE,
          cache = TRUE,
          n_cores = 1
        )

        arrow::write_parquet(out, output_path)
        """
    )
    script_path = output_path.with_suffix(".R")
    script_path.write_text(r_code, encoding="utf-8")
    cache_dir.mkdir(parents=True, exist_ok=True)
    result = subprocess.run(
        [
            R_SCRIPT,
            str(script_path),
            str(repo_root),
            dataset,
            str(input_path),
            str(cache_dir),
            str(output_path),
        ],
        cwd=repo_root,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=1800,
        check=False,
    )
    if result.returncode != 0:
        pytest.fail(f"R geocode failed with exit code {result.returncode}:\n{result.stdout}")
    # if result.stdout:
    #     print(f"\n--- R stdout/stderr ---\n{result.stdout}\n--- end R output ---")
    return pq.read_table(output_path)

def _column_to_str_list(table: pa.Table, col_name: str) -> list[str | None]:
    """Extract a column's values as a list of strings (None unchanged)."""
    col = table[col_name]
    return [None if v is None else str(v) for v in col.to_pylist()]


def _column_to_float_list(table: pa.Table, col_name: str) -> list[float | None]:
    """Extract a column's values as floats with None preserved."""
    col = table[col_name]
    return [None if v is None else float(v) for v in col.to_pylist()]


# ---------------------------------------------------------------------------
# Comparison functions (one per level)
# ---------------------------------------------------------------------------

def compare_schema(py: pa.Table, r: pa.Table) -> list[str]:
    """Level 1: column names and order."""
    py_cols = py.schema.names
    r_cols = r.schema.names
    if py_cols == r_cols:
        return []

    diffs = []
    py_set = set(py_cols)
    r_set = set(r_cols)
    if py_set != r_set:
        only_py = py_set - r_set
        only_r = r_set - py_set
        if only_py:
            diffs.append(f"Columns only in Python: {sorted(only_py)}")
        if only_r:
            diffs.append(f"Columns only in R golden: {sorted(only_r)}")
    if py_set == r_set and py_cols != r_cols:
        diffs.append(f"Column order differs:\n  Python: {py_cols}\n  R:      {r_cols}")
    return diffs


def compare_row_count(py: pa.Table, r: pa.Table) -> list[str]:
    """Level 2: same number of rows."""
    if py.num_rows == r.num_rows:
        return []
    return [
        f"Row count mismatch: Python={py.num_rows}, R golden={r.num_rows}"
    ]


def compare_match_types(py: pa.Table, r: pa.Table) -> list[str]:
    """Level 3: distribution of tipo_resultado."""
    if "tipo_resultado" not in py.schema.names or "tipo_resultado" not in r.schema.names:
        return []

    py_types = _column_to_str_list(py, "tipo_resultado")
    r_types = _column_to_str_list(r, "tipo_resultado")

    py_counts = Counter(py_types)
    r_counts = Counter(r_types)

    if py_counts == r_counts:
        return []

    diffs = ["Match-type distribution (tipo_resultado) differs:"]
    all_types = sorted(set(py_counts) | set(r_counts), key=lambda x: (x is None, x))
    for t in all_types:
        pc = py_counts.get(t, 0)
        rc = r_counts.get(t, 0)
        if pc != rc:
            diffs.append(f"  {t}: Python={pc}, R={rc}")
    return diffs


def compare_coordinates(
    py: pa.Table,
    r: pa.Table,
    atol: float = 1e-6,
) -> list[str]:
    """Level 4: lat/lon within tolerance."""
    diffs = []
    for col_name in ("lat", "lon"):
        if col_name not in py.schema.names or col_name not in r.schema.names:
            continue

        py_vals = _column_to_float_list(py, col_name)
        r_vals = _column_to_float_list(r, col_name)

        if len(py_vals) != len(r_vals):
            diffs.append(
                f"{col_name}: row count mismatch "
                f"(Python={len(py_vals)}, R={len(r_vals)})"
            )
            continue

        mismatches = []
        for i, (pv, rv) in enumerate(zip(py_vals, r_vals)):
            if pv is None and rv is None:
                continue
            if pv is None or rv is None:
                mismatches.append((i, pv, rv))
            elif not math.isclose(pv, rv, abs_tol=atol):
                mismatches.append((i, pv, rv))

        if mismatches:
            diffs.append(
                f"{col_name}: {len(mismatches)} value(s) differ "
                f"(atol={atol}):"
            )
            for idx, pv, rv in mismatches[:20]:
                diffs.append(f"  row {idx}: Python={pv}, R={rv}")
            if len(mismatches) > 20:
                diffs.append(f"  ... and {len(mismatches) - 20} more")
    return diffs


def compare_non_numeric_cells(py: pa.Table, r: pa.Table) -> list[str]:
    """Level 5: exact equality for string/int columns (excludes floats)."""
    if py.num_rows != r.num_rows:
        return ["Non-numeric comparison skipped (row count mismatch)."]

    diffs = []
    float_cols = {
        name for name in py.schema.names
        if patypes.is_floating(py[name].type)
    }

    for name in py.schema.names:
        if name in float_cols:
            continue
        if name not in r.schema.names:
            continue

        py_vals = _column_to_str_list(py, name)
        r_vals = _column_to_str_list(r, name)

        cell_diffs = []
        for i, (pv, rv) in enumerate(zip(py_vals, r_vals)):
            if pv != rv:
                cell_diffs.append((i, pv, rv))

        if cell_diffs:
            diffs.append(
                f"Column '{name}': {len(cell_diffs)} cell(s) differ:"
            )
            for idx, pv, rv in cell_diffs[:10]:
                diffs.append(f"  row {idx}: Python={pv!r}, R={rv!r}")
            if len(cell_diffs) > 10:
                diffs.append(f"  ... and {len(cell_diffs) - 10} more")
    return diffs


def run_all_comparisons(py_table: pa.Table, r_table: pa.Table) -> list[str]:
    """Run all 5 comparison levels, collecting all diffs."""
    all_diffs = []
    all_diffs += compare_schema(py_table, r_table)
    all_diffs += compare_row_count(py_table, r_table)
    all_diffs += compare_match_types(py_table, r_table)
    all_diffs += compare_coordinates(py_table, r_table)
    all_diffs += compare_non_numeric_cells(py_table, r_table)
    return all_diffs


def _assert_tables_identical(py_output: pa.Table, r_output: pa.Table) -> None:
    py_output = _normalize_table(py_output)
    r_output = _normalize_table(r_output)
    assert py_output.schema.names == r_output.schema.names, (
        f"Schema mismatch:\n  python: {py_output.schema.names}\n  R:      {r_output.schema.names}"
    )
    assert py_output.num_rows == r_output.num_rows, (
        f"Row count mismatch: python={py_output.num_rows}, R={r_output.num_rows}"
    )
    _assert_rows_identical(py_output, r_output)


def _null_summary(label: str, table: pa.Table) -> str:
    lines = [f"  {label} null counts per column:"]
    for name in table.schema.names:
        nulls = table[name].null_count
        total = table.num_rows
        if nulls > 0:
            lines.append(f"    {name}: {nulls}/{total}")
    return "\n".join(lines)


def _assert_rows_identical(py_output: pa.Table, r_output: pa.Table) -> None:
    py_rows = py_output.to_pylist()
    r_rows = r_output.to_pylist()
    if py_rows == r_rows:
        return

    diffs = []
    for i, (py_row, r_row) in enumerate(zip(py_rows, r_rows)):
        for col in py_output.schema.names:
            py_val = py_row.get(col)
            r_val = r_row.get(col)
            if py_val != r_val:
                diffs.append(
                    f"  row {i}, col '{col}':\n"
                    f"    python = {py_val!r}\n"
                    f"    R      = {r_val!r}"
                )
    if len(py_rows) != len(r_rows):
        diffs.append(
            f"  row count: python={len(py_rows)}, R={len(r_rows)}"
        )

    # Detect widespread nulls in R output (sign that geocode didn't run properly)
    r_null_cols = [
        name for name in py_output.schema.names
        if r_output[name].null_count > 0 and py_output[name].null_count == 0
    ]
    null_info = ""
    if r_null_cols:
        null_info = (
            "\n\nWARNING: R output has nulls where Python does not in columns: "
            f"{r_null_cols}\nThis suggests the R geocode() may not have matched any addresses.\n"
            + _null_summary("python", py_output)
            + "\n"
            + _null_summary("R", r_output)
        )

    summary = "\n".join(diffs[:50])
    if len(diffs) > 50:
        summary += f"\n  ... and {len(diffs) - 50} more differences"
    assert py_rows == r_rows, f"{len(diffs)} cell(s) differ:\n{summary}{null_info}"


def _normalize_table(table: pa.Table) -> pa.Table:
    columns = []
    arrays = []
    for name in table.schema.names:
        column = table[name]
        if patypes.is_floating(column.type):
            values = [None if value is None else round(float(value), 8) for value in column.to_pylist()]
            arrays.append(pa.array(values, type=pa.float64()))
        else:
            values = [None if value is None else str(value) for value in column.to_pylist()]
            arrays.append(pa.array(values, type=pa.string()))
        columns.append(name)
    return pa.table(arrays, names=columns)
