# Diagnóstico — Revisão de código do porte Python (geocodebr)

**Data:** 2026-09-17
**Escopo:** revisão completa de `python-package/geocodebr/` focada em localização e
nomenclatura de funções, privacidade (`_`), organizaçao de módulos e melhores
práticas Python. Nenhuma mudança de comportamento do pipeline; refactors
estruturais + higiene de código.

**Estado dos testes ao final:** 161 passed (`pytest -m "not r_parity"`), 8
deselected; 8 `r_parity` confirmados manualmente pela equipe (falham apenas
neste ambiente por download do CNEFE via script R + arrow compilado em R 4.5.3,
pré-existente e não relacionado ao refactor).

---

## 1. O que foi implementado

### 1.1 Reorganização de módulos (Opção A)

Movidas de `utils.py` → `matching.py` (etapas SQL do pipeline do `geocode()`):

- `update_input_db`
- `add_precision_col`
- `merge_results_to_input`
- `cria_col_logradouro_confusao`
- `add_h3_columns`

Motivo: funções que emitem SQL para o pipeline não são "utilitários" — são
etapas de pipeline tanto quanto `match_cases`. Importantes para não quebrar:
`update_input_db` apaga de `input_padrao_db` os ids já resolvidos (invariante
1 do laço de matching).

### 1.2 Novo módulo `match_types.py` (Opção B)

Módulo **puro** (sem DuckDB, sem I/O), com `__all__` e docstring, unificando o
domínio "escada de 25 etapas":

- `ALL_POSSIBLE_MATCH_TYPES` + os 7 sets (`NUMBER_EXACT_TYPES`,
  `NUMBER_INTERPOLATION_TYPES`, `PROBABILISTIC_EXACT_TYPES`,
  `PROBABILISTIC_INTERPOLATION_TYPES`, `EXACT_TYPES_NO_NUMBER`,
  `PROBABILISTIC_TYPES_NO_NUMBER`, `MATCH_TYPES_JARO_REDUNDANTE`) — vindos de
  `constants.py`
- `get_key_cols`, `get_reference_table`, `get_prob_match_cutoff`,
  `tabelas_necessarias` — vindos de `utils.py`

Estado final:

| Módulo | Responsabilidade |
|---|---|
| `constants.py` | só configuração (`DATA_RELEASE`, arquivos CNEFE, nomes reservados) |
| `match_types.py` | metadados das etapas de matching |
| `matching.py` | funções de match + etapas SQL do pipeline |
| `utils.py` | validação de input + helpers SQL genéricos (`quote_ident`, `sql_string`, `db_table_columns`, `normalize_h3_res`) |

Importers atualizados: `geocode.py`, `matching.py`, `tables.py`,
`string_dist.py`, `cep.py`, `__init__.py` + testes diretos.

**Constraint de import que motivou o arquivo novo:** as funções de metadata
não podem morar em `matching.py`, pois `tables.py` e `string_dist.py` as
consomem e `matching.py` já importa ambos → import circular. `match_types.py`
não importa de volta ninguém (exceto `re`), o que elimina o risco.

### 1.3 Código morto removido

- `errors.py`: `SemCorrespondenciaError` + `error_sem_correspondencia()`
  (nunca usados; os casos que os motivariam usavam `ValueError` genérico)
- `utils.py`: `find_cached_parquet()` (superada por `caminho_parquet()` em
  `cache.py`) + imports órfãos (`Path`, `DATA_RELEASE`)
- `test_errors.py` / `test_utils.py`: testes do código removido

### 1.4 Guard de import no `__init__.py`

Antes:

```python
try:
    from .reverse import geocode_reverso
except Exception:  # pragma: no cover
    geocode_reverso = None
```

Problemas:

1. Desnecessário: `reverse.py` não importa geopandas no topo (só em
   `if TYPE_CHECKING:`); o geopandas é tocado apenas em runtime, via
   `_import_geopandas()` em `geo.py`
2. `except Exception` engole **qualquer** erro de carregamento (inclusive
   bugs como `NameError`) → `geocode_reverso = None` → o usuário só descobre
   na chamada, com `TypeError: 'NoneType' object is not callable`, longe da
   causa e sem informação

Depois: `from .reverse import geocode_reverso` direto. O erro informativo
real continua no lugar certo (`geo.py`, acionado por
`geocode(resultado_gpd=True)`, `busca_por_cep(resultado_gpd=True)` e
`geocode_reverso`), coberto por `test_geo.py`.

Princípio: falhar o mais tarde e o mais claro possível; nunca transformar
erro de import em `None` silencioso.

### 1.5 Tipagem de `_validate_points_bbox` (`reverse.py`)

Anotada `-> None` mas retorna a tupla do bbox. Corrigido para
`-> tuple[float, float, float, float]`.

### 1.6 `py.typed` (PEP 561)

Marker vazio criado em `geocodebr/py.typed` (hatchling o inclui no wheel por
padrão; verificado em build: `py.typed no wheel: True`). Efeito: type checkers
(mypy/pyright/IDEs) passam a usar as anotações inline do pacote — sem o marker,
o pacote é tratado como sem tipos (`Skipping analyzing "geocodebr": module is
installed, but missing library stubs or py.typed marker`).

### 1.7 Correção pontual em `fields.py`

Mensagem do `ValueError` de `definir_campos()` trocada na mão (commit
`33f818e`) sem atualizar o teste: typo "endreço" → "endereço" e regex do
`test_definir_campos_rejects_all_null` atualizada para a mensagem nova.

### 1.8 Remoção do fallback de `platformdirs` (`cache.py`)

`try/except ModuleNotFoundError` no topo de `cache.py` definia funções locais
de `user_cache_dir`/`user_config_dir` para o caso de `platformdirs` não estar
instalada. Código morto e problemático:

- é dependência obrigatória no `pyproject.toml` (instalada automaticamente;
  não existe cenário suportado em que falte)
- o fallback tinha caminhos de Windows hardcode (`AppData/Local`,
  `AppData/Roaming`) — errado em macOS/Linux
- nunca testado (`# pragma: no cover`)
- se disparasse, só adiaria o `ModuleNotFoundError` para a primeira chamada
  de cache, longe da causa

Substituído por import direto. Justificativa da dependência dura:
funcionalidade central (cache é API pública de primeira classe), padrão *de
facto* para diretórios apropriados por OS (sucessora mantida do `appdirs`;
Windows `%LOCALAPPDATA%`, macOS `~/Library/Caches`, XDG no Linux), custo
mínimo (v. 4.10.0: 159 KB, pure Python, zero dependências transitivas).

### 1.9 Consistência de erros, prints, mensagens e warnings

Contrato único por tipo de saída:

| Situação | Mecanismo |
|---|---|
| Falha de domínio (usuário certo, sem resultado) | `raise` de subclass `GeocodeBRError` |
| Argumento inválido (bug de quem chama) | `ValueError`/`TypeError` (padrão do ecossistema) |
| Aviso (continua, efeito implícito) | `warnings.warn(...)` |
| Progresso do pipeline | `messages.inform(msg, verboso)` (timestamp) |
| Ação explícita pedida pelo usuário | `messages.confirm(msg)` (sempre visível, sem timestamp) |

Mudanças:

- `errors.py`: só classes. Removida `error_input_nao_padronizado()`;
  recriada `SemCorrespondenciaError` e usada nos `ValueError` genéricos de
  `cep.py` ("Nenhum CEP foi encontrado") e `reverse.py` ("Nenhum endereco
  proximo foi encontrado")
- `geocode.py`: `raise InputNaoPadronizadoError(...)` direto em
  `_assert_standardized_columns`
- `matching.py`: aviso de empates não resolvidos → `warnings.warn(...)`;
  mensagem de empates resolvidos → `inform(..., verboso)`
- `cache.py`: `print`s → `messages.confirm(...)`
- `_heap.py`: **mantido como print em `stderr`** (canal inform), de
  propósito, para não correr risco de ser filtrado pelo mecanismo de
  warnings; `test_heap.py` já esperava isso
- `test_errors.py` agora testa a hierarquia; testes de `busca_por_cep` e
  `geocode_reverso` esperam `SemCorrespondenciaError`

---

## 2. Pendências (melhorias opcionais, não bloqueantes)

1. **`logging` no lugar de `print`**: `cache.py` (`definir_pasta_cache`,
   `deletar_pasta_cache`, `_print_tree`) e `matching.py` (aviso de empates)
   usam `print` direto, fora do módulo `messages.py`. O aviso de empates,
   semanticamente um warning, mereceria `warnings.warn` (como já faz
   `standardize.py`). Longo prazo: logger de módulo com `logging`.
2. **`__all__` por módulo**: hoje só `__init__.py` e `match_types.py` o
   definem. Padronizar nos demais módulos internos documentaria a fronteira
   entre "interface interna compartilhada" (público-nomeado) e "detalhe de
   implementação do arquivo" (`_`-prefixado). Critério atual misto.
3. **Consistência pt/en nos identificadores internos**: API pública em
   português (parity com o R) — manter; internamente há mistura
   (`cria_col_logradouro_confusao` vs `assert_no_reserved_columns`;
   `message_baixando_cnefe` vs `message_looking_for_matches`;
   `trata_empates_geocode_duckdb` carrega sufixo de implementação
   desnecessário). Renomear é mecânico, mas quebra os testes que inspecionam
   fontes (`test_regression_news_port.py` usa `inspect.getsource`).
4. **Higiene do repo**: `standardize.py` tem ~160 linhas de testes comentados
   no rodapé (mover para `tests/`); `htmlcov/` ausente do `.gitignore`
   (não commitado). *(Corrigidos nesta sessão: `exemple/` renomeada para
   `exemplos/` + README atualizado; fallback de `platformdirs` removido de
   `cache.py` — ver §1.8.)*
5. **Detalhes menores**: sentinela `"tempdir"`/`"memory"` em
   `db.py::create_geocodebr_db` poderia ser `Literal`; `RESERVED_COLUMN_NAMES`
   é list e não set; `matched_rows == n_rows` em `geocode.py` não quebra cedo
   com input vazio (usar `>=`); sets de `match_types.py` citam códigos fora
   da escada (`pn04`, `pa04`, `pl04`).

---

## 3. Commits e verificação

- `33f818e` — "limpeza 1 - apenas helpers no utils e novo arquivo para
  metadados do matching" (Opções A + B)
- Remoção de código morto, guard do `__init__`, tipagem e `py.typed`:
  working tree desta sessão (pendente de commit)
- Suíte: `pytest -q -m "not r_parity"` → **161 passed** em todos os passos
  (baseline pré-refactor: 164 passed, incluindo 3 testes removidos junto com
  o código morto)
- Parity R/Python: 8/8 passando manualmente (falha local pré-existente:
  `error_cnefe_download_failed` no script R)
