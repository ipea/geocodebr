"""Testes de paridade R/Python para geocode(), geocode_reverso() e busca_por_cep().

Estrategia: cada caso roda um script R gerado em tempo de execucao (embutido
neste arquivo como string) que roda a funcao do lado R e grava os outputs em
parquet; o lado Python roda as mesmas operacoes com a mesma pasta de cache e
os resultados sao comparados em niveis (colunas, linhas, celulas nao
numericas, coordenadas com tolerancia). O pacote R local e instalado uma
unica vez por sessao, em biblioteca temporaria (fixture ``r_lib``).

Divergencias conhecidas (documentadas, nao sao falhas de paridade):

* ``geocode_reverso``: nos dois pacotes a funcao recebe pontos
  georreferenciados (sf no R, GeoDataFrame no Python, ambos EPSG 4674) e a
  geometria do output e o proprio ponto de input. O teste achata as geometrias
  dos dois lados em ``lon_geom``/``lat_geom``/``geom_epsg`` para a comparacao
  via parquet, e pareia as linhas por ``id`` (o join e interno: ponto sem
  endereco no raio some do output).
"""

import math
import shutil
import subprocess
import textwrap
from collections import Counter
from pathlib import Path

import pandas as pd
import pyarrow as pa
import pyarrow.csv as pv
import pyarrow.parquet as pq
import pyarrow.types as patypes
import pytest

from geocodebr import (
    busca_por_cep,
    definir_campos,
    definir_pasta_cache,
    geocode,
    geocode_reverso,
)
from geocodebr.cache import listar_pasta_cache_padrao


R_SCRIPT = shutil.which("Rscript")
if R_SCRIPT is None:
    for candidate in sorted(Path("C:/Program Files/R").glob("R-*/bin/Rscript.exe"), reverse=True):
        if candidate.exists():
            R_SCRIPT = str(candidate)
            break


pytestmark = pytest.mark.r_parity

CEPS = ["70390-025", "20071-001", "99999-999"]

ADDRESS_COLS = ["estado", "municipio", "logradouro", "cep", "localidade"]


# ---------------------------------------------------------------------------
# fixtures
# ---------------------------------------------------------------------------


@pytest.fixture(scope="session")
def repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


@pytest.fixture(scope="session")
def parity_cache() -> Path:
    # usa a pasta de cache padrao do pacote: estavel entre execucoes do pytest
    # e geralmente ja populada, evitando rebaixar o CNEFE (tabelas nacionais
    # somam mais de 1 GB). Os testes que definem tmp_path como cache (test_
    # geocode etc.) sobrescrevem a config global, por isso nao basta ler
    # listar_pasta_cache() aqui.
    return Path(listar_pasta_cache_padrao())


@pytest.fixture(scope="session", autouse=True)
def configure_cache(parity_cache):
    # outros testes (test_geocode etc.) sobrescrevem a config global com
    # tmp_path, entao este modulo fixa a pasta padrao para o lado Python ler
    # os mesmos dados que o lado R
    definir_pasta_cache(str(parity_cache), verboso=False)


@pytest.fixture(scope="session")
def r_lib(repo_root, tmp_path_factory) -> Path:
    """Instala o pacote R local uma unica vez, em biblioteca temporaria."""
    _require_r_parity()
    lib = tmp_path_factory.mktemp("geocodebr_r_lib")
    r_code = textwrap.dedent(
        r"""
        args <- commandArgs(trailingOnly = TRUE)
        repo_root <- normalizePath(args[[1]], winslash = "/", mustWork = TRUE)
        lib <- normalizePath(args[[2]], winslash = "/", mustWork = FALSE)

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
        cat("R LIB OK\n")
        """
    )
    script_path = lib / "install_geocodebr_r.R"
    script_path.write_text(r_code, encoding="utf-8")
    _run_rscript(repo_root, script_path, [repo_root, lib])
    return lib


# ---------------------------------------------------------------------------
# geocode
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("resultado_gpd", [False, True], ids=["dataframe", "geodataframe"])
def test_geocode_matches_r_small_sample(repo_root, r_lib, parity_cache, tmp_path, resultado_gpd):
    _require_r_parity()
    suffix = "sf" if resultado_gpd else "df"
    r_output = _run_r_geocode(
        repo_root=repo_root,
        lib=r_lib,
        dataset="small",
        input_path=repo_root / "r-package" / "inst" / "extdata" / "small_sample.csv",
        cache_dir=parity_cache,
        output_path=tmp_path / f"r_small_{suffix}.parquet",
        resultado_sf=resultado_gpd,
    )
    py_output = _run_python_geocode(
        dataset="small",
        input_path=repo_root / "r-package" / "inst" / "extdata" / "small_sample.csv",
        cache_dir=parity_cache,
        resultado_gpd=resultado_gpd,
    )

    diffs = run_all_comparisons(py_output, r_output)

    if diffs:
        report = "\n".join(diffs)
        pytest.fail(
            f"Parity check failed for small sample:\n\n{report}"
        )


@pytest.mark.parametrize("resultado_gpd", [False, True], ids=["dataframe", "geodataframe"])
def test_geocode_matches_r_large_sample(repo_root, r_lib, parity_cache, tmp_path, resultado_gpd):
    _require_r_parity()
    suffix = "sf" if resultado_gpd else "df"
    r_output = _run_r_geocode(
        repo_root=repo_root,
        lib=r_lib,
        dataset="large",
        input_path=repo_root / "r-package" / "inst" / "extdata" / "large_sample.parquet",
        cache_dir=parity_cache,
        output_path=tmp_path / f"r_large_{suffix}.parquet",
        resultado_sf=resultado_gpd,
    )
    py_output = _run_python_geocode(
        dataset="large",
        input_path=repo_root / "r-package" / "inst" / "extdata" / "large_sample.parquet",
        cache_dir=parity_cache,
        resultado_gpd=resultado_gpd,
    )

    diffs = run_all_comparisons(py_output, r_output)

    if diffs:
        report = "\n".join(diffs)
        pytest.fail(
            f"Parity check failed for large sample:\n\n{report}"
        )


def _run_python_geocode(
    dataset: str,
    input_path: Path,
    cache_dir: Path,
    resultado_gpd: bool,
) -> pa.Table:
    definir_pasta_cache(str(cache_dir), verboso=False)
    if dataset == "small":
        addresses = pv.read_csv(input_path)
        fields = definir_campos(
            logradouro="nm_logradouro",
            numero="Numero",
            cep="Cep",
            localidade="Bairro",
            municipio="nm_municipio",
            estado="nm_uf",
        )
    elif dataset == "large":
        addresses = pq.read_table(input_path)
        fields = definir_campos(
            logradouro="logradouro",
            numero="numero",
            cep="cep",
            localidade="bairro",
            municipio="municipio",
            estado="uf",
        )
    else:
        raise ValueError(f"Unknown dataset: {dataset}")

    result = geocode(
        enderecos=addresses,
        campos_endereco=fields,
        resultado_completo=True,
        resolver_empates=True,
        resultado_gpd=resultado_gpd,
        h3_res=None,
        padronizar_enderecos=True,
        verboso=False,
        cache=True,
        n_cores=1,
    )

    if resultado_gpd:
        result = _flatten_gpd_geometry(result)

    return result


# ---------------------------------------------------------------------------
# busca_por_cep
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("resultado_gpd", [False, True], ids=["dataframe", "geodataframe"])
def test_busca_por_cep_matches_r(repo_root, r_lib, parity_cache, tmp_path, resultado_gpd):
    _require_r_parity()
    suffix = "sf" if resultado_gpd else "df"
    r_output = _run_r_busca_por_cep(
        repo_root=repo_root,
        lib=r_lib,
        cache_dir=parity_cache,
        output_path=tmp_path / f"r_cep_{suffix}.parquet",
        resultado_sf=resultado_gpd,
    )
    py_output = _run_python_busca_por_cep(resultado_gpd)

    diffs = []
    diffs += compare_schema(py_output, r_output)
    diffs += compare_row_count(py_output, r_output)

    key_cols = ["cep", "logradouro", "localidade", "estado", "municipio"]
    py_rows = _sorted_rows(py_output, key_cols)
    r_rows = _sorted_rows(r_output, key_cols)

    # colunas nao numericas devem ser identicas (inclui h3_03/h3_04 na
    # variante dataframe e geom_epsg na variante geodataframe)
    non_float_cols = [
        name for name in py_output.schema.names
        if name in r_output.schema.names and not _is_float_col(r_output, name)
    ]
    for col in non_float_cols:
        py_vals = [row[col] for row in py_rows]
        r_vals = [row[col] for row in r_rows]
        if py_vals != r_vals:
            diffs.extend(_cell_diffs(col, py_vals, r_vals))

    # coordenadas dentro de tolerancia
    for col in ("lon", "lat", "lon_geom", "lat_geom"):
        if col not in py_output.schema.names or col not in r_output.schema.names:
            continue
        py_vals = [row[col] for row in py_rows]
        r_vals = [row[col] for row in r_rows]
        diffs += _compare_floats(col, py_vals, r_vals, atol=1e-6)

    if diffs:
        pytest.fail(f"Parity check failed for busca_por_cep:\n\n" + "\n".join(diffs))


def _run_python_busca_por_cep(resultado_gpd: bool) -> pa.Table:
    result = busca_por_cep(
        cep=CEPS,
        h3_res=None if resultado_gpd else [3, 4],
        resultado_gpd=resultado_gpd,
        verboso=False,
        cache=True,
    )
    if resultado_gpd:
        return _flatten_gpd_geometry(result)
    return result


# ---------------------------------------------------------------------------
# geocode_reverso
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("dist_max", [1000, 5000], ids=["1km", "5km"])
def test_geocode_reverso_matches_r(repo_root, r_lib, parity_cache, tmp_path, dist_max):
    gpd = pytest.importorskip("geopandas")
    _require_r_parity()
    input_points, r_output = _run_r_geocode_reverso(
        repo_root=repo_root,
        lib=r_lib,
        cache_dir=parity_cache,
        output_path=tmp_path / f"r_reverso_{dist_max}.parquet",
        dist_max=dist_max,
    )

    input_df = input_points.to_pandas()
    points = gpd.GeoDataFrame(
        input_df[["id"]],
        geometry=gpd.points_from_xy(input_df["lon"], input_df["lat"]),
        crs="EPSG:4674",
    )
    py_output = _flatten_gpd_geometry(
        geocode_reverso(
            pontos=points,
            dist_max=dist_max,
            verboso=False,
            cache=True,
            n_cores=1,
        )
    )

    diffs = []
    diffs += compare_schema(py_output, r_output)
    diffs += compare_row_count(py_output, r_output)

    # pareia as linhas por id (o mesmo ponto de input pode aparecer como
    # nao-casado no output de um lado e do outro)
    py_rows = {row["id"]: row for row in py_output.to_pylist()}
    r_rows = {row["id"]: row for row in r_output.to_pylist()}

    if sorted(py_rows) != sorted(r_rows):
        only_py = sorted(set(py_rows) - set(r_rows))
        only_r = sorted(set(r_rows) - set(py_rows))
        diffs.append(
            f"Matched ids differ: only in Python={only_py}, only in R={only_r}"
        )
    else:
        for col in [*ADDRESS_COLS, "geom_epsg"]:
            py_vals = [py_rows[i][col] for i in sorted(py_rows)]
            r_vals = [r_rows[i][col] for i in sorted(r_rows)]
            if py_vals != r_vals:
                diffs.extend(_cell_diffs(col, py_vals, r_vals))

        # a geometria do R passa por roundtrip 4674 -> 31983 -> 4674, com erro
        # de ponto flutuante na casa de 1e-14 graus; comparar com tolerancia
        for col in ("lon_geom", "lat_geom"):
            py_vals = [py_rows[i][col] for i in sorted(py_rows)]
            r_vals = [r_rows[i][col] for i in sorted(r_rows)]
            diffs += _compare_floats(col, py_vals, r_vals, atol=1e-6)

        py_dist = [py_rows[i]["distancia_metros"] for i in sorted(py_rows)]
        r_dist = [r_rows[i]["distancia_metros"] for i in sorted(r_rows)]
        diffs += _compare_floats("distancia_metros", py_dist, r_dist, atol=1e-6)

    if diffs:
        pytest.fail(
            f"Parity check failed for geocode_reverso (dist_max={dist_max}):\n\n"
            + "\n".join(diffs)
        )


# ---------------------------------------------------------------------------
# execucao dos scripts R
# ---------------------------------------------------------------------------

# carrega o pacote R instalado em r_lib e aponta o cache para a mesma pasta
# usada pelo lado Python; espera que as variaveis lib e cache_dir ja estejam
# definidas pelo parse dos args
_R_SETUP = textwrap.dedent(
    r"""
    .libPaths(c(lib, .libPaths()))
    suppressPackageStartupMessages(library(geocodebr, lib.loc = lib))
    suppressPackageStartupMessages(library(arrow))

    geocodebr::definir_pasta_cache(cache_dir, verboso = FALSE)
    """
)


def _require_r_parity() -> None:
    if R_SCRIPT is None:
        pytest.skip("Rscript not found in PATH.")


def _run_rscript(repo_root: Path, script_path: Path, args: list) -> None:
    result = subprocess.run(
        [R_SCRIPT, str(script_path), *[str(arg) for arg in args]],
        cwd=repo_root,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=1800,
        check=False,
    )
    if result.returncode != 0:
        pytest.fail(
            f"R script {script_path.name} failed with exit code "
            f"{result.returncode}:\n{result.stdout}"
        )


def _run_r_geocode(
    repo_root: Path,
    lib: Path,
    dataset: str,
    input_path: Path,
    cache_dir: Path,
    output_path: Path,
    resultado_sf: bool,
) -> pa.Table:
    r_code = textwrap.dedent(
        r"""
        args <- commandArgs(trailingOnly = TRUE)
        lib <- normalizePath(args[[1]], winslash = "/", mustWork = TRUE)
        dataset <- args[[2]]
        input_path <- normalizePath(args[[3]], winslash = "/", mustWork = TRUE)
        cache_dir <- normalizePath(args[[4]], winslash = "/", mustWork = FALSE)
        output_path <- args[[5]]
        resultado_sf <- (args[[6]] == "TRUE")
        """
    ) + _R_SETUP + textwrap.dedent(
        r"""
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
          resultado_sf = resultado_sf,
          h3_res = NULL,
          padronizar_enderecos = TRUE,
          verboso = FALSE,
          cache = TRUE,
          n_cores = 1
        )

        if (resultado_sf) {
          # achata a geometria sf em colunas numericas para viabilizar a
          # comparacao com o geopandas via parquet
          coords <- sf::st_coordinates(out$geometry)
          out$lon_geom <- as.numeric(coords[, "X"])
          out$lat_geom <- as.numeric(coords[, "Y"])
          out$geom_epsg <- as.integer(sf::st_crs(out)$epsg)
          out$geometry <- NULL
        }

        arrow::write_parquet(out, output_path)
        """
    )
    script_path = output_path.with_suffix(".R")
    script_path.write_text(r_code, encoding="utf-8")
    cache_dir.mkdir(parents=True, exist_ok=True)
    _run_rscript(
        repo_root,
        script_path,
        [
            lib,
            dataset,
            input_path,
            cache_dir,
            output_path,
            "TRUE" if resultado_sf else "FALSE",
        ],
    )
    return pq.read_table(output_path)


def _run_r_busca_por_cep(
    repo_root: Path,
    lib: Path,
    cache_dir: Path,
    output_path: Path,
    resultado_sf: bool,
) -> pa.Table:
    r_code = textwrap.dedent(
        r"""
        args <- commandArgs(trailingOnly = TRUE)
        lib <- normalizePath(args[[1]], winslash = "/", mustWork = TRUE)
        cache_dir <- normalizePath(args[[2]], winslash = "/", mustWork = FALSE)
        output_path <- args[[3]]
        resultado_sf <- (args[[4]] == "TRUE")
        """
    ) + _R_SETUP + textwrap.dedent(
        r"""
        ceps <- c("70390-025", "20071-001", "99999-999")

        if (resultado_sf) {
          # variante sf: a geometria consome lon/lat (sfheaders keep = TRUE),
          # entao ela eh achatada de volta em colunas numericas para viabilizar
          # a comparacao com o geopandas via parquet
          out <- geocodebr::busca_por_cep(
            cep = ceps,
            h3_res = NULL,
            resultado_sf = TRUE,
            verboso = FALSE,
            cache = TRUE
          )
          coords <- sf::st_coordinates(out$geometry)
          out$lon_geom <- as.numeric(coords[, "X"])
          out$lat_geom <- as.numeric(coords[, "Y"])
          out$geom_epsg <- as.integer(sf::st_crs(out)$epsg)
          out$geometry <- NULL
        } else {
          # variante data.frame, com colunas h3
          out <- geocodebr::busca_por_cep(
            cep = ceps,
            h3_res = c(3, 4),
            resultado_sf = FALSE,
            verboso = FALSE,
            cache = TRUE
          )
        }

        arrow::write_parquet(as.data.frame(out), output_path)
        """
    )
    script_path = output_path.with_suffix(".R")
    script_path.write_text(r_code, encoding="utf-8")
    _run_rscript(
        repo_root,
        script_path,
        [lib, cache_dir, output_path, "TRUE" if resultado_sf else "FALSE"],
    )
    return pq.read_table(output_path)


def _run_r_geocode_reverso(
    repo_root: Path,
    lib: Path,
    cache_dir: Path,
    output_path: Path,
    dist_max: int,
) -> tuple[pa.Table, pa.Table]:
    """Devolve (input_points, r_output)."""
    r_code = textwrap.dedent(
        r"""
        args <- commandArgs(trailingOnly = TRUE)
        lib <- normalizePath(args[[1]], winslash = "/", mustWork = TRUE)
        cache_dir <- normalizePath(args[[2]], winslash = "/", mustWork = FALSE)
        output_path <- args[[3]]
        dist_max <- as.numeric(args[[4]])
        """
    ) + _R_SETUP + textwrap.dedent(
        r"""
        # mesmos 10 pontos usados no teste R (tests/testthat/test-geocode_reverso.R)
        pontos <- readRDS(system.file("extdata/pontos.rds", package = "geocodebr"))
        pontos <- pontos[1:10, ]

        # input achatado em lon/lat para reproduzir o input do lado Python
        # (pontos.rds so pode ser lido pelo R)
        coords <- sf::st_coordinates(pontos)
        input_df <- data.frame(
          id = pontos$id,
          lon = as.numeric(coords[, "X"]),
          lat = as.numeric(coords[, "Y"])
        )
        input_path <- file.path(dirname(output_path), "reverso_input.parquet")
        arrow::write_parquet(input_df, input_path)

        out <- geocodebr::geocode_reverso(
          pontos = pontos,
          dist_max = dist_max,
          verboso = FALSE,
          cache = TRUE,
          n_cores = 1
        )

        # no R a geometria do output e o proprio ponto de input; aqui ela e
        # achatada em colunas numericas para a comparacao via parquet
        coords <- sf::st_coordinates(out$geometry)
        out$lon_geom <- as.numeric(coords[, "X"])
        out$lat_geom <- as.numeric(coords[, "Y"])
        out$geom_epsg <- as.integer(sf::st_crs(out)$epsg)
        out$geometry <- NULL
        arrow::write_parquet(as.data.frame(out), output_path)
        """
    )
    script_path = output_path.with_suffix(".R")
    script_path.write_text(r_code, encoding="utf-8")
    input_path = output_path.parent / "reverso_input.parquet"
    _run_rscript(repo_root, script_path, [lib, cache_dir, output_path, dist_max])
    return pq.read_table(input_path), pq.read_table(output_path)


# ---------------------------------------------------------------------------
# helpers Python
# ---------------------------------------------------------------------------


def _flatten_gpd_geometry(result) -> pa.Table:
    # achata a geometria em colunas numericas para viabilizar a comparacao
    # com o sf do R via parquet (mesmo esquema dos dois lados)
    xs = result.geometry.x
    ys = result.geometry.y
    df = pd.DataFrame(result.drop(columns=[result.geometry.name]))
    df["lon_geom"] = [None if pd.isna(v) else float(v) for v in xs]
    df["lat_geom"] = [None if pd.isna(v) else float(v) for v in ys]
    df["geom_epsg"] = int(result.crs.to_epsg())
    return pa.Table.from_pandas(df, preserve_index=False)


def _column_to_str_list(table: pa.Table, col_name: str) -> list[str | None]:
    """Extract a column's values as a list of strings (None unchanged)."""
    col = table[col_name]
    return [None if v is None else str(v) for v in col.to_pylist()]


def _column_to_float_list(table: pa.Table, col_name: str) -> list[float | None]:
    """Extract a column's values as floats with None preserved."""
    col = table[col_name]
    return [None if v is None else float(v) for v in col.to_pylist()]


def _is_float_col(table: pa.Table, col_name: str) -> bool:
    return patypes.is_floating(table.schema.field(col_name).type)


def _sorted_rows(table: pa.Table, key_cols: list[str]) -> list[dict]:
    rows = table.to_pylist()
    return sorted(rows, key=lambda row: tuple(str(row[c]) for c in key_cols))


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
    for col_name in ("lat", "lon", "lon_geom", "lat_geom"):
        if col_name not in py.schema.names or col_name not in r.schema.names:
            continue
        diffs += _compare_floats(
            col_name,
            _column_to_float_list(py, col_name),
            _column_to_float_list(r, col_name),
            atol,
        )
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


def _compare_floats(col_name: str, py_vals, r_vals, atol: float) -> list[str]:
    mismatches = []
    for i, (pv, rv) in enumerate(zip(py_vals, r_vals)):
        if pv is None and rv is None:
            continue
        if pv is None or rv is None or not math.isclose(pv, rv, abs_tol=atol):
            mismatches.append((i, pv, rv))

    if not mismatches:
        return []

    diffs = [f"{col_name}: {len(mismatches)} value(s) differ (atol={atol}):"]
    for idx, pv, rv in mismatches[:20]:
        diffs.append(f"  row {idx}: Python={pv}, R={rv}")
    if len(mismatches) > 20:
        diffs.append(f"  ... and {len(mismatches) - 20} more")
    return diffs


def _cell_diffs(col_name: str, py_vals, r_vals) -> list[str]:
    mismatches = [(i, pv, rv) for i, (pv, rv) in enumerate(zip(py_vals, r_vals)) if pv != rv]
    if not mismatches:
        return []
    diffs = [f"Column '{col_name}': {len(mismatches)} cell(s) differ:"]
    for idx, pv, rv in mismatches[:10]:
        diffs.append(f"  row {idx}: Python={pv!r}, R={rv!r}")
    if len(mismatches) > 10:
        diffs.append(f"  ... and {len(mismatches) - 10} more")
    return diffs
