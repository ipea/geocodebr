# Plano — `update_input_db` filtrado pela etapa no Python

**Status:** APPROVED (27/09) — implementado; ver "Resultado" no fim
**Data:** 27/09/2026
**Origem:** lição B4 de `quality_reports/diagnoses/2026-09-23_licoes-cruzadas-geocode-R-Python.md`

## Objetivo

Deixar o `update_input_db()` do Python igual ao do R: apagar do `input_padrao_db` só os ids que a etapa
**corrente** inseriu em `output_db`, e usar a contagem que o próprio `DELETE` devolve. Nenhum resultado
muda.

## Como o R faz (`r-package/R/utils.R:79-111`)

```r
filtro_etapa <- if (is.null(match_type)) "" else
  glue::glue("WHERE tipo_resultado = '{match_type}'")

DELETE FROM {update_tb}
WHERE tempidgeocodebr IN (
  SELECT tempidgeocodebr FROM {reference_tb} {filtro_etapa}
);
```

O R devolve o `dbExecute()`, que é o nº de linhas apagadas. Os quatro `match_*()` do R passam
`match_type = match_type`.

## Como o Python faz hoje (`python-package/geocodebr/matching.py:288-303`)

```python
before = con.execute(f"SELECT COUNT(*) FROM {update_tb}").fetchone()[0]
con.execute("DELETE FROM {update_tb} WHERE tempidgeocodebr IN "
            "(SELECT tempidgeocodebr FROM {reference_tb})")      # sem filtro
after = con.execute(f"SELECT COUNT(*) FROM {update_tb}").fetchone()[0]
return before - after
```

A cada uma das 25 etapas, ele varre o `output_db` inteiro, que só cresce, e faz duas contagens do input.

## Mudança (~12 linhas, 1 arquivo: `python-package/geocodebr/matching.py`)

1. **`update_input_db`:** novo parâmetro opcional `match_type: str | None = None`. O filtro entra na
   subconsulta e a contagem vem do `DELETE`:
   ```python
   def update_input_db(con, update_tb="input_padrao_db", reference_tb="output_db",
                       match_type: str | None = None) -> int:
       # so os ids inseridos NESTA etapa ainda estao em update_tb (as etapas
       # anteriores ja apagaram os seus); filtrar evita varrer a output_db
       # inteira 25 vezes. Espelha update_input_db() do R
       filtro = f"WHERE tipo_resultado = {sql_string(match_type)}" if match_type else ""
       return con.execute(
           f"""
           DELETE FROM {quote_ident(update_tb)}
           WHERE tempidgeocodebr IN (
             SELECT tempidgeocodebr FROM {quote_ident(reference_tb)} {filtro}
           )
           """
       ).fetchone()[0]
   ```
   `sql_string` já existe em `utils.py` e é o que protege o literal. Com `match_type=None`, o
   comportamento atual fica igual.
2. **Os quatro chamadores** (`matching.py:89, 146, 199, 273`) passam a chamar
   `update_input_db(con, update_tb=x, reference_tb=output_tb, match_type=match_type)`. `match_type` já é
   parâmetro de cada `match_*()`.

Nada mais muda: nem assinatura pública, nem `geocode.py`, nem SQL de match.

## Por que o resultado não muda (paridade)

- **Mesmo conjunto apagado.** Vale o invariante do laço: no início da etapa *k*, nenhum id do
  `input_padrao_db` está no `output_db`, porque cada etapa anterior apagou todos os ids que inseriu. Os
  ids que a etapa *k* insere levam `tipo_resultado = '{match_type}'` (`matching.py:79, 138, 189, 265`).
  Então a subconsulta com filtro e a sem filtro apagam exatamente as mesmas linhas. O R depende do mesmo
  invariante desde a otimização dele.
- **Mesma contagem.** `before - after` e o valor devolvido pelo `DELETE` são, ambos, o nº de linhas
  apagadas de `update_tb`. Não é o nº de linhas inseridas no output: um id empatado conta uma vez nos
  dois casos. Conferido no DuckDB 1.5.5: `con.execute("DELETE ...").fetchone()` devolve `(3,)` e `(0,)`
  quando não apaga nada. Isso alimenta `matched_rows`, a barra de progresso e a saída antecipada
  (`matched_rows == n_rows`), que continuam iguais.
- **O SQL de match, o de empates e o do merge não são tocados.** O output é o mesmo por construção. A
  verificação abaixo confirma.

## Verificação

1. **Teste unitário novo** em `python-package/tests/test_matching.py`, com tabelas sintéticas:
   `output_db` com ids de duas etapas (`dn01` e `dn02`) e `input_padrao_db` só com os ids de `dn02`.
   Conferir que `update_input_db(..., match_type="dn02")` apaga as mesmas linhas e devolve a mesma
   contagem que a chamada sem `match_type`. Também conferir que devolve 0 quando não há o que apagar.
2. **Suíte unitária:** `uv run pytest -q -m "not r_parity"` verde.
3. **Output idêntico antes/depois, no mesmo pacote.** `geocode()` sobre `small_sample.csv` e
   `large_sample.parquet`, com `resultado_completo=True`/`False` e `resolver_empates=True`/`False`.
   Comparar coluna a coluna; só `lat`/`lon` podem variar, dentro do ruído de ~1e-14 dos empates
   (`[LEARN:testes]`).
4. **Paridade R ↔ Python:** `uv run pytest -m r_parity -q` (ou o CI `python-parity.yaml`, que dispara
   porque o PR toca `python-package/geocodebr/**`).
5. **Ganho:** medir o tempo total do laço antes/depois com `large_sample` replicado (1M e, se der, 10M).
   Esperado: nenhum ganho em 20k; ~6–7 s em 10M (sintético: 10,8 → 4,2 s na parte de `DELETE`).
   Registrar em `python-package/benchmarks/resultados_benchmark.md`.

## Arquivos

- `python-package/geocodebr/matching.py` (função + 4 chamadas)
- `python-package/tests/test_matching.py` (1 teste)
- `python-package/CHANGELOG.md`: linha em "Modificado" (otimização interna, sem efeito no resultado)
- R: nada. Ele já faz isso.

## Resultado (27/09/2026)

Implementado como planejado: `update_input_db(..., match_type=None)` + 4 chamadores em `matching.py`,
1 teste parametrizado em `tests/test_matching.py`, entrada no `CHANGELOG.md`.

- **Suíte unitária:** 168 passed (`pytest -m "not r_parity"`).
- **Antes × depois (mesmo pacote), 2 amostras × `resultado_completo` × `resolver_empates`:** as 8
  combinações dão o **mesmo multiconjunto de linhas** (lat/lon arredondados a 1e-9). Com
  `resolver_empates=True` a comparação posicional também bate, exceto o ruído de ~1e-14 em lat/lon.
- **Achado à parte (pré-existente, não causado pelo patch):** com `resolver_empates=False`, a **ordem
  das linhas empatadas** de um mesmo id varia entre execuções idênticas, porque o `ORDER BY` final é só por
  `tempidgeocodebr`. Duas rodadas do código já corrigido deram ordens diferentes. Não mexido aqui.
- **Paridade R × Python (patch), `large_sample`, 4 combinações:** multiconjunto idêntico em todas.
  `pytest -m r_parity` não foi rodado localmente; fica para o CI (`python-parity.yaml`).
- **Tempo, 1M linhas (large_sample × 50), Segment Heap, 2 rodadas intercaladas:** tempo acumulado em
  `update_input_db` 1,66 / 1,31 s → 0,52 / 0,43 s (~3× menos, ~1 s por chamada). O tempo total
  (68–102 s) é ruidoso demais para mostrar esse 1 s.
