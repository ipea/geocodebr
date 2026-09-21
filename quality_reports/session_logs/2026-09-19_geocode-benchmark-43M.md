
## Continuação — 20-21/09 (aplicação manual à `main`)

- O usuário commitou todo o cumulativo numa branch `otimizacao_claude` (inclui patches, relatório
  e scripts em `quality_reports/diagnoses/2026-09-19_patches/`) e está **reaplicando patch a patch
  na `main`**, pedindo antes a explicação de cada mudança.
- **Já na `main`:** P3 (`duckdb_register()` para `input_db`, commit `b985cba`, feito à mão pelo
  usuário); P7 (resultado via parquet + `pos_processa_output()`/`restaura_classes_input()`, commit
  `c95917c`); P4 (`DELETE` só da etapa, `update_input_db(match_type)` + 4 chamadores +
  `man/update_input_db.Rd`) — aplicado e verificado em 21/09 (282 testes, `identical()` 1M via
  `geocode()`), commit a cargo do usuário.
- **Receita usada para cada patch:** `git show otimizacao_claude:<p.patch>` → normalizar os arquivos
  alvo para LF → `git apply --directory=r-package --recount` → voltar para CRLF →
  `devtools::document()` → `devtools::test()` → restaurar `_snaps/` → instalar em lib privada e
  rodar `prof_geocode.R --mode=geocode --ncores=1` no 1M → `compare_results.R` contra
  `runs/base1M_nc1_result.parquet` (scratchpad da sessão 61ca0503; se o scratchpad sumir, regerar a
  referência com a `main` anterior a P3).
- **Faltam:** P1, P5, P6, P8 (+ híbrido `cum2_hibrido_jaro.patch`), P9-P12 (bundle de memória). P2
  não se aplica isolado (está dentro do P8). Ordem sugerida pelo ganho: P5, P8+híbrido, P1, P9-12,
  P6. Atenção ao aplicar P1 depois de P8: o filtro `numero IS NULL` entra nas DUAS cláusulas
  (CTE `to_compute` e `WHERE` do `UPDATE`) e na forma direta do híbrido — ver `cumulativo.patch`.
