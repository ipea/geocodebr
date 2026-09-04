"""Benchmark do port Python na sample de 10M de linhas do CadÚnico.

Protocolo: a cada alteração no pacote, rodar este script com --label antes e
depois do patch e comparar os tempos por fase em resultados_benchmark.md.

Uso:
    uv run python benchmarks/benchmark_sample.py --label baseline
"""

from __future__ import annotations

import argparse
import csv
import subprocess
import sys
import time
from contextlib import redirect_stderr, redirect_stdout
from datetime import datetime
from io import StringIO
from pathlib import Path

import duckdb

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import geocodebr  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[2]
SAMPLE_DEFAULT = REPO_ROOT / "data" / "sample_cad_unico.parquet"
BENCH_DIR = Path(__file__).resolve().parent
RESULTS_MD = BENCH_DIR / "resultados_benchmark.md"
RESULTS_CSV = BENCH_DIR / "resultados_benchmark.csv"

# mensagem do verboso -> marco de inicio da fase (mesmos limites usados na
# analise manual dos logs); conexao_fechada e opcional (instrumentacao do
# finally do geocode())
MESSAGE_MARCOS = [
    ("Utilizando dados do CNEFE armazenados localmente", "inicio_cnefe"),
    ("Baixando dados do CNEFE", "inicio_cnefe"),
    ("Padronizando enderecos de entrada", "inicio_padronizacao"),
    ("Geolocalizando enderecos", "inicio_matching"),
    ("Preparando resultados", "inicio_empates"),
    ("Adicionando coluna de precisão", "inicio_precisao"),
    ("Juntando com colunas do input", "inicio_merge"),
    ("Materializando tabela final em arrow", "inicio_materializacao"),
    ("Finalizado", "finalizado"),
    ("Conexão fechada", "conexao_fechada"),
]

FASES = [
    "cnefe", "padronizacao", "matching", "empates", "precisao",
    "merge", "materializacao", "fechamento_conexao", "pos_finalizado",
]

HEADER_MD = """# Benchmark — port Python, sample CadÚnico 10M

Protocolo: rodar antes e depois de cada alteração (`--label`) e comparar tempos por fase.
Sample: `data/sample_cad_unico.parquet` · args fixos: `resolver_empates=True`, `cache=True`, `n_cores=None` (24 threads).
`fechamento_conexao` = tempo de `con.close()` (marco "Conexão fechada" no `finally`); `-1` = marco ausente.

---

"""

CSV_COLUMNS = [
    "label", "data", "sha", "duckdb", "resultado_completo",
    "n_rows_input", "n_encontrados", *FASES, "total",
]

MARCOS_OBRIGATORIOS = {
    "inicio_padronizacao", "inicio_matching", "inicio_empates",
    "inicio_precisao", "inicio_merge", "inicio_materializacao",
    "finalizado",
}


def _fmt_seg(seg: float) -> str:
    total = int(round(seg))
    h, resto = divmod(total, 3600)
    m, s = divmod(resto, 60)
    return f"{h}:{m:02d}:{s:02d}" if h else f"{m}:{s:02d}"


def _delta(a: datetime, b: datetime) -> float:
    d = (a - b).total_seconds()
    if d < 0:  # virada de meia-noite
        d += 86400
    return d


def _parse_marcos(log_texto: str, ref: datetime) -> dict[str, datetime]:
    # ancora os horarios do log na data real da rodada (strptime puro daria
    # 1900-01-01 e corromperia os deltas contra datetime.now())
    marcos: dict[str, datetime] = {}
    for linha in log_texto.splitlines():
        if len(linha) < 10 or linha[2] != ":" or linha[5] != ":":
            continue
        hora_str, msg = linha[:8], linha[10:]
        for texto, chave in MESSAGE_MARCOS:
            if msg == texto and chave not in marcos:
                hora = datetime.strptime(hora_str, "%H:%M:%S").time()
                marcos[chave] = datetime.combine(ref.date(), hora)
    faltando = MARCOS_OBRIGATORIOS - set(marcos)
    if faltando:
        raise RuntimeError(f"Mensagens de fase ausentes no log: {faltando}")
    return marcos


def _duracoes(marcos: dict[str, datetime], t_inicio: datetime,
              t_fim: datetime) -> dict[str, float]:
    d = {
        "cnefe": _delta(marcos["inicio_padronizacao"], t_inicio),
        "padronizacao": _delta(marcos["inicio_matching"], marcos["inicio_padronizacao"]),
        "matching": _delta(marcos["inicio_empates"], marcos["inicio_matching"]),
        "empates": _delta(marcos["inicio_precisao"], marcos["inicio_empates"]),
        "precisao": _delta(marcos["inicio_merge"], marcos["inicio_precisao"]),
        "merge": _delta(marcos["inicio_materializacao"], marcos["inicio_merge"]),
        "materializacao": _delta(marcos["finalizado"], marcos["inicio_materializacao"]),
    }
    if "conexao_fechada" in marcos:
        d["fechamento_conexao"] = _delta(marcos["conexao_fechada"], marcos["finalizado"])
        d["pos_finalizado"] = _delta(t_fim, marcos["conexao_fechada"])
    else:
        d["fechamento_conexao"] = -1  # marco ausente nesta versao do codigo
        d["pos_finalizado"] = _delta(t_fim, marcos["finalizado"])
    return d


def _git_info() -> tuple[str, bool]:
    sha = subprocess.check_output(
        ["git", "rev-parse", "--short", "HEAD"], cwd=REPO_ROOT
    ).decode().strip()
    dirty = bool(
        subprocess.check_output(["git", "status", "--porcelain"], cwd=REPO_ROOT)
        .decode()
        .strip()
    )
    return sha, dirty


def run_benchmark(sample: Path, label: str, resultado_completo: bool) -> None:
    sha, dirty = _git_info()
    sha_rotulo = sha + ("+dirty" if dirty else "")

    campos = geocodebr.definir_campos(
        logradouro="logradouro",
        numero="numero",
        cep="cep",
        localidade="bairro",
        municipio="code_muni",
        estado="abbrev_state",
    )

    stdout_buf, stderr_buf = StringIO(), StringIO()
    t0 = time.perf_counter()
    t_inicio = datetime.now()
    with redirect_stdout(stdout_buf), redirect_stderr(stderr_buf):
        resultado = geocodebr.geocode(
            enderecos=str(sample),
            campos_endereco=campos,
            resultado_completo=resultado_completo,
            resolver_empates=True,
            verboso=True,
        )
    t_total = time.perf_counter() - t0
    t_fim = datetime.now()

    log_texto = stdout_buf.getvalue()
    marcos = _parse_marcos(log_texto, t_inicio)
    duracoes = _duracoes(marcos, t_inicio, t_fim)

    n_rows = resultado.num_rows
    n_encontrados = n_rows - resultado.column("lat").null_count

    _salvar_md(label, sha_rotulo, resultado_completo, duracoes, t_total,
               n_rows, n_encontrados, log_texto, t_inicio, t_fim)
    _salvar_csv(label, sha_rotulo, resultado_completo, duracoes, t_total,
                n_rows, n_encontrados)

    print(f"[benchmark] label: {label} | sha: {sha_rotulo} | duckdb: {duckdb.__version__}")
    for fase, seg in duracoes.items():
        print(f"  {fase:<20} {_fmt_seg(max(seg, 0))}")
    print(f"  {'TOTAL (wall)':<20} {_fmt_seg(t_total)}")
    print(f"  linhas: {n_rows:,} | encontradas: {n_encontrados:,} "
          f"({100 * n_encontrados / n_rows:.1f}%)")


def _salvar_md(label: str, sha: str, rc: bool, duracoes: dict, t_total: float,
               n_rows: int, n_encontrados: int, log_texto: str,
               t_inicio: datetime, t_fim: datetime) -> None:
    existe = RESULTS_MD.exists()
    with open(RESULTS_MD, "a", encoding="utf-8") as f:
        if not existe:
            f.write(HEADER_MD)
        f.write(f"## {label} — {datetime.now():%Y-%m-%d %H:%M} (sha `{sha}`)\n\n")
        f.write(f"- args: `resultado_completo={rc}`, `resolver_empates=True`, `n_cores=None`\n")
        f.write(f"- início: {t_inicio:%H:%M:%S} · fim (return do geocode): {t_fim:%H:%M:%S}\n")
        f.write(f"- linhas: {n_rows:,} · encontradas: {n_encontrados:,} "
                f"({100 * n_encontrados / n_rows:.1f}%)\n\n")
        f.write("| fase | tempo |\n|---|---|\n")
        for fase in FASES:
            seg = duracoes[fase]
            tempo = "(ausente)" if seg < 0 else _fmt_seg(seg)
            f.write(f"| {fase} | {tempo} |\n")
        f.write(f"| **TOTAL (wall)** | **{_fmt_seg(t_total)}** |\n\n")
        f.write("```\n" + log_texto.strip() + "\n```\n\n---\n\n")


def _salvar_csv(label: str, sha: str, rc: bool, duracoes: dict, t_total: float,
                n_rows: int, n_encontrados: int) -> None:
    existe = RESULTS_CSV.exists()
    with open(RESULTS_CSV, "a", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        if not existe:
            w.writerow(CSV_COLUMNS)
        w.writerow([
            label, datetime.now().strftime("%Y-%m-%d %H:%M"), sha,
            duckdb.__version__, int(rc), n_rows, n_encontrados,
            *(_round_opt(duracoes.get(f)) for f in FASES),
            round(t_total),
        ])


def _round_opt(v: float | None) -> int:
    return -1 if v is None or v < 0 else round(v)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--label", required=True,
                        help="rótulo da rodada (ex.: baseline, patch_merge)")
    parser.add_argument("--sample", type=Path, default=SAMPLE_DEFAULT)
    parser.add_argument("--resultado-completo", action="store_true",
                        help="default False, espelhando o benchmark do R")
    args = parser.parse_args()
    run_benchmark(args.sample, args.label, args.resultado_completo)


if __name__ == "__main__":
    main()
