import shutil
import subprocess
import textwrap
from pathlib import Path

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
        input_path=repo_root / "inst" / "extdata" / "small_sample.csv",
        cache_dir=cache_dir,
        output_path=tmp_path / "r_small.parquet",
    )
    py_output = _run_python_geocode(
        dataset="small",
        input_path=repo_root / "inst" / "extdata" / "small_sample.csv",
        cache_dir=cache_dir,
    )
    _assert_tables_identical(py_output, r_output)


def test_geocode_matches_r_large_sample(repo_root, tmp_path):
    _require_r_parity()
    cache_dir = tmp_path / "cache"
    r_output = _run_r_geocode(
        repo_root=repo_root,
        dataset="large",
        input_path=repo_root / "inst" / "extdata" / "large_sample.parquet",
        cache_dir=cache_dir,
        output_path=tmp_path / "r_large.parquet",
    )
    py_output = _run_python_geocode(
        dataset="large",
        input_path=repo_root / "inst" / "extdata" / "large_sample.parquet",
        cache_dir=cache_dir,
    )
    _assert_tables_identical(py_output, r_output)


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
          c("CMD", "INSTALL", "-l", lib, repo_root),
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
          verboso = TRUE,
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
    if result.stdout:
        print(f"\n--- R stdout/stderr ---\n{result.stdout}\n--- end R output ---")
    return pq.read_table(output_path)


def _assert_tables_identical(py_output: pa.Table, r_output: pa.Table) -> None:
    py_output = _normalize_table(py_output)
    r_output = _normalize_table(r_output)
    assert py_output.schema.names == r_output.schema.names
    assert py_output.num_rows == r_output.num_rows
    assert py_output.to_pylist() == r_output.to_pylist()


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
