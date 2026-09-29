# Plano de Refatoração: geocodebr-py usar bindings `enderecobr`

Documento de referência para substituir a padronização reimplementada em
SQL/UDF artesanais do port Python do `geocodebr` por chamadas às funções
escalares do binding `enderecobr` v0.2.0 (Rust), garantindo paridade total
com o fluxo R (`geocode.R:262-314`).

Este plano assume que o `enderecobr_rs` já está pronto (binding Python com
`padronizar_estados_para_sigla` e `padronizar_numeros_para_int` expostas),
conforme verificação documentada no relatório anterior.

---

## Decisões confirmadas

- **Abordagem**: Polars-first (`Series.map_elements(..., return_dtype=...)`) —
  camada de staging da padronização em Polars (Arrow Utf8 nativo,
  multi-thread via Rayon), com zero-copy Polars↔DuckDB. Substitui a
  abordagem pandas-first original por ganho de memória (~5-10x mais compacto
  que `object` dtype) e paralelismo. DuckDB permanece como engine de
  matching (inalterado). A escolha pandas vs Polars **não afeta a paridade
  de output** — ambos geram a mesma Arrow table registrada no DuckDB; é
  decisão pura de performance/memória.
- **Justificativa Polars**: geocodebr é pacote público; 1M+ linhas não é
  exceção. Para 1-10M linhas, Polars é o sweet spot (cabe na RAM, multi-thread
  real, Arrow memory). O time IPEA já conhece Polars (usado em
  `enderecobr_rs/Cargo.toml` feature `polars_cli` e em `padronizacao_cnefe`).
  Acima de ~10M que não cabe na RAM, fallback seria DuckDB UDF arrow-batch
  (com spill) — fora do escopo desta refatoração.
- **Município**: remover `_resolve_municipio_codes*` (`geocode.py:451-632`),
  confiar em `enderecobr.padronizar_municipios` como o R faz (resolve códigos
  IBGE de 7-8 dígitos → nome).

---

## Fase 0 — Dependências e setup

### 0.1 `pyproject.toml` (raiz `geocodebr/`)
- Adicionar `"enderecobr>=0.2.0"` à lista `dependencies` (linha 12-20).
- Adicionar `"polars>=1.0"` à lista `dependencies`. Esta é uma nova
  dependência não prevista no plano de porting original §6 (que mapeava
  `data.table → pandas`); ver justificativa em "Decisões confirmadas".
- O `enderecobr` v0.2.0 ainda não está no PyPI (release `fe2b8b4` feito no
  repositório, mas publish pendente). Opções:
  - **(A)** Instalar localmente via
    `maturin develop --manifest-path enderecobr_rs/bindings/python/Cargo.toml`
    no env de dev.
  - **(B)** Aguardar publish no PyPI e usar `pip install enderecobr`.
- Validar presença do binding:
  ```bash
  python -c "import enderecobr; print(enderecobr.padronizar_estados_para_sigla('21'))"
  ```
  Saída esperada: `"MA"`.

### 0.2 Pré-requisito de build (se opção A)
- Rust toolchain (rustc 1.81+) instalado para compilar o binding.
- `maturin` disponível: `pip install maturin`.

---

## Fase 1 — Criar `geocodebr/standardize.py` (novo arquivo)

Espelha `enderecobr/R/padronizar_enderecos.R:83-182` e
`correspondencia_campos.R:41-74`.

### 1.1 `correspondencia_campos()` — helper trivial

```python
def correspondencia_campos(
    tipo_de_logradouro: str | None = None,
    logradouro: str | None = None,
    numero: str | None = None,
    complemento: str | None = None,
    cep: str | None = None,
    bairro: str | None = None,
    municipio: str | None = None,
    estado: str | None = None,
) -> dict[str, str]:
    ...
```

- Valida: ao menos 1 campo não-None; todos str ou None.
- Retorna `dict` nome_campo → nome_coluna (só não-None), igual ao R.

### 1.2 `padronizar_enderecos()` — nível-tabela

```python
def padronizar_enderecos(
    enderecos: pl.DataFrame,
    campos_do_endereco: dict[str, str],
    formato_estados: str = "por_extenso",   # "sigla" | "por_extenso"
    formato_numeros: str = "character",      # "character" | "integer"
    manter_cols_extras: bool = True,
) -> pl.DataFrame:
    ...
```

Lógica (espelha `padronizar_enderecos.R:116-181`):

1. Construir `relacao_campos` — lista de tuplas
   `(nome_campo, funcao_enderecobr, return_dtype)`:

   | nome_campo            | função binding                          | return_dtype              | obs                                        |
   | ---                   | ---                                     | ---                       | ---                                        |
   | `tipo_de_logradouro`  | `enderecobr.padronizar_tipo_logradouro` | `pl.Utf8`                 | geocodebr NÃO usa                          |
   | `logradouro`          | `enderecobr.padronizar_logradouros`     | `pl.Utf8`                 |                                            |
   | `numero`              | `enderecobr.padronizar_numeros` (str) ou `enderecobr.padronizar_numeros_para_int` (int) | `pl.Utf8` ou `pl.Int32` | conforme `formato_numeros` |
   | `complemento`         | `enderecobr.padronizar_complementos`    | `pl.Utf8`                 | geocodebr NÃO usa                          |
   | `cep`                 | `enderecobr.padronizar_cep_leniente`    | `pl.Utf8`                 | plano §3.2 confirmou leniente é suficiente |
   | `bairro`              | `enderecobr.padronizar_bairros`         | `pl.Utf8`                 |                                            |
   | `municipio`           | `enderecobr.padronizar_municipios`      | `pl.Utf8`                 | resolve códigos IBGE 7-8 dígitos → nome     |
   | `estado`              | `enderecobr.padronizar_estados_para_sigla` (se sigla) ou `_para_nome` (se por_extenso) | `pl.Utf8` |                              |

2. Para cada campo em `relacao_campos` que está em `campos_do_endereco`:
   - `col_orig = campos_do_endereco[nome_campo]`
   - Aplicar via `map_elements` (multi-thread, Arrow nativo):
     ```python
     col_padr = (
         enderecos[col_orig]
         .fill_null("")                                   # None → "" para o binding
         .map_elements(enderecobr.padronizar_logradouros, return_dtype=pl.Utf8)
     )
     enderecos = enderecos.with_columns(col_padr.alias(f"{nome_campo}_padr"))
     ```
   - Para `numero` com `formato="integer"`:
     `.map_elements(enderecobr.padronizar_numeros_para_int, return_dtype=pl.Int32)`
     → `Int32` nullável (`None` vira null nativo do Polars). O R retorna `NA`.
   - **`return_dtype` é obrigatório**: sem ele o Polars cai em `Object` dtype,
     anulando todo o benefício de memória. Padronizar via helper.

3. Se `manter_cols_extras=False`: descartar colunas não especificadas
   (`enderecos.select([...colunas_padr...])`).

4. Retornar `pl.DataFrame` com colunas `*_padr` adicionadas (R cria
   `logradouro_padr`, `numero_padr`, `cep_padr`, `bairro_padr`,
   `municipio_padr`, `estado_padr`).

> **Observação sobre `map_elements`**: o binding `enderecobr` expõe apenas
> funções escalares (`fn(&str) -> &str`); não existe API vetorial
> `fn(&[&str]) -> Vec<String>`. Portanto `map_elements` itera
> elemento-a-elemento — o ganho do Polars está no **overhead ao redor**
> (buffers Arrow contíguos vs `PyUnicode` por célula do pandas) e no
> **paralelismo** (Rayon distribui entre cores). Para vetorização real seria
> preciso um PR upstream separado expondo API batch no `enderecobr_rs`.

### 1.3 Mapeamento `numero` integer — observação crítica

- `enderecobr.padronizar_numeros_para_int("0180 0181")` → `None` (múltiplos
  números).
- O port atual (`geocode.py:228-230`) extrai dígitos e faz `TRY_CAST` →
  `1800181` (INCORRETO vs R).
- A nova implementação via binding corrige essa divergência automaticamente.

---

## Fase 2 — Refatorar `geocode.py`

### 2.1 Reordenar fluxo de `geocode()` (linhas 124-148)

**Fluxo atual** (DuckDB-first, SQL standardization):

```
_register_input(con, enderecos)          # → enderecos_input
CREATE input_db (add tempidgeocodebr)
_create_standardized_input(con, campos)  # SQL + UDF → input_padrao_db
cria_col_logradouro_confusao(con)
```

**Fluxo alvo** (Polars-first, espelha `geocode.R:262-348`):

```python
# 1. Materializar input em Polars
df_input = _materialize_input(enderecos)   # se Path: ler; se Table/df: converter

# 2. Tratar campos ausentes (R: geocode.R:246-255)
#    criar colunas temp com None para campos não informados
df_input = _fill_missing_fields(df_input, campos_endereco)

# 3. Padronizar via enderecobr (Polars map_elements, multi-thread)
df_padr = padronizar_enderecos(
    df_input,
    correspondencia_campos(
        logradouro=campos["logradouro"],
        numero=campos["numero"],
        cep=campos["cep"],
        bairro=campos["localidade"],        # geocodebr "localidade" → enderecobr "bairro"
        municipio=campos["municipio"],
        estado=campos["estado"],
    ),
    formato_estados="sigla",
    formato_numeros="integer",
    manter_cols_extras=False,
)

# 4. Renomear *_padr → canonical (R: geocode.R:301-314)
df_padr = _rename_padr_columns(df_padr)    # strip "_padr"; bairro → localidade

# 5. Adicionar tempidgeocodebr a ambos
df_input = df_input.with_row_count("tempidgeocodebr")
df_padr = df_padr.with_columns(df_input["tempidgeocodebr"])
df_padr = df_padr.with_columns(
    pl.lit(None).alias("temp_lograd_determ"),
    pl.lit(None).alias("similaridade_logradouro"),
)

# 6. Registrar no DuckDB (zero-copy Polars→Arrow→DuckDB)
con.register("input_db_arrw", df_input.to_arrow())
con.execute("CREATE TEMP TABLE input_db AS SELECT * FROM input_db_arrw")
con.register("input_padrao_arrw", df_padr.to_arrow())
con.execute("CREATE TEMP TABLE input_padrao_db AS SELECT * FROM input_padrao_arrw")

# 7. Continuar fluxo existente
cria_col_logradouro_confusao(con)
```

### 2.2 Funções a REMOVER de `geocode.py`

| Função                                       | Linhas   | Razão                                                          |
| ---                                          | ---      | ---                                                            |
| `_create_standardized_input`                 | 218-254  | Substituída por `standardize.padronizar_enderecos`            |
| `_create_standardized_input_from_padr`       | 257-271  | Repensar: path `padronizar_enderecos=False` ainda precisa renomear `*_padr` → canonical; manter lógica simplificada |
| `_install_normalize_function`                | 332-438  | UDFs artesanais `_geocodebr_norm`/`_geocodebr_uf` não serão mais usadas |
| `_resolve_estado_names`                      | 441-448  | `enderecobr.padronizar_estados_para_sigla` faz isto          |
| `_resolve_municipio_codes`                   | 451-498  | `enderecobr.padronizar_municipios` resolve códigos IBGE        |
| `_resolve_municipio_codes_from_cnefe_sector` | 501-551  | Remover (decisão confirmada)                                   |
| `_resolve_numeric_municipio_from_cep`        | 554-590  | Remover                                                        |
| `_resolve_numeric_municipio_from_address`    | 593-632  | Remover                                                        |

### 2.3 Funções a AVALIAR (manter ou remover)

| Função                       | Linhas   | Decisão                                                                                                                                                  |
| ---                          | ---      | ---                                                                                                                                                       |
| `_fix_logradouro_prefixes`   | 280-329  | **Validar**: corrige "RUA RUA X"→"RUA X", "RUA AVENIDA X"→"AVENIDA X". Pode ser redundante se `padronizar_logradouros` já trata. Verificar se R geocodebr tem lógica equivalente — não encontrei em `geocode.R`. Se paridade com R passar sem ela, remover. Se falhar, manter. |
| `_assert_standardized_columns` | 274-277 | **Manter** — valida que `input_padrao_db` tem colunas esperadas                                                                                            |
| `_create_standardized_input_from_padr` | 257-271 | **Manter simplificado** — para `padronizar_enderecos=False`, renomear `*_padr` → canonical                                                          |

### 2.4 `_materialize_input()` — novo helper

```python
import polars as pl

def _materialize_input(enderecos: Any) -> pl.DataFrame:
    if isinstance(enderecos, (str, Path)):
        path = Path(enderecos)
        suffix = path.suffix.lower()
        # Leitura lazy (streaming-friendly) + collect => Polars otimiza leitura
        if suffix == ".parquet":
            return pl.scan_parquet(path).collect()
        elif suffix in {".csv", ".txt"}:
            return pl.scan_csv(path).collect()
        else:
            raise ValueError("Arquivos suportados: .parquet, .csv, .txt.")
    elif isinstance(enderecos, pa.Table):
        return pl.from_arrow(enderecos)          # zero-copy
    elif isinstance(enderecos, pl.DataFrame):
        return enderecos.clone()
    elif isinstance(enderecos, pd.DataFrame):
        return pl.from_pandas(enderecos)         # backward-compat (custo de cópia)
    else:
        raise TypeError(
            "enderecos deve ser caminho de arquivo (.parquet/.csv/.txt), "
            "pyarrow.Table, polars.DataFrame ou pandas.DataFrame."
        )
```

> **Backward-compat de input**: o teste de paridade passa `pa.Table`
> (`pyarrow.csv.read_csv`) — convertido via `pl.from_arrow` (zero-copy).
> Caminhos são lidos via `pl.scan_*` (lazy, streaming-friendly). Pandas
> DataFrame é aceito via `pl.from_pandas` (com custo de cópia, mas mantém
> compatibilidade).

### 2.5 Importação a adicionar no topo de `geocode.py`

```python
import enderecobr
import polars as pl
from .standardize import padronizar_enderecos, correspondencia_campos
```

---

## Fase 3 — Mover `busca_por_cep` para `cep.py` (novo arquivo)

Conforme plano de porting original §5, `busca_por_cep` deve viver em `cep.py`,
não em `geocode.py`.

### 3.1 Criar `geocodebr/cep.py`
- Mover `busca_por_cep()` (`geocode.py:37-93`) para `cep.py`.
- Mover helpers `_normalize_ceps`, `_format_cep_digits` (`geocode.py:668-684`).
- Substituir a normalização de CEP inline (`geocode.py:67-76`) por
  `enderecobr.padronizar_cep_leniente` onde aplicável.
- Não confundir: a normalização na query SQL (linhas 67-76) é para formatar a
  **saída** do CNEFE, não o input — avaliar se precisa mudar.

### 3.2 Atualizar imports em `geocode.py`
- Remover `busca_por_cep` e helpers movidos.
- Remover de `geocode.py` o que ficar em `cep.py`.

---

## Fase 4 — Atualizar `__init__.py` e `fields.py`

### 4.1 `__init__.py`
- `busca_por_cep` passa a vir de `.cep` em vez de `.geocode`:

```python
from .cep import busca_por_cep
from .geocode import geocode
```

### 4.2 `fields.py` — sem mudança necessária
- `definir_campos()` já funciona como `correspondencia_campos` do geocodebr
  (não do enderecobr).
- O mapeamento geocodebr `localidade` → enderecobr `bairro` acontece dentro de
  `geocode()` ao chamar `correspondencia_campos`, não em `definir_campos`.

---

## Fase 5 — Testes de paridade

### 5.1 Rodar testes existentes

```bash
cd geocodebr
python -m pytest python-package/tests/test_r_python_parity.py -m r_parity -v
```

- `test_geocode_matches_r_small_sample` — `small_sample.csv`.
- `test_geocode_matches_r_large_sample` — `large_sample.parquet`.
- `_assert_tables_identical` compara schema, num_rows e valores (floats com 8
  casas).

### 5.2 Pontos de atenção na paridade
1. **Numero**: `padronizar_numeros_para_int` retorna `None` para "0180 0181"
   (vs `1800181` atual) → pode mudar match results. Se paridade com R passar,
   está correto.
2. **Municipio**: códigos de 6 dígitos (prefixo de setor) não resolvidos por
   `padronizar_municipios` (só 7-8 dígitos). Se small/large sample os contém,
   validar se R também falha — se sim, paridade mantida. Se não, investigar.
3. **Logradouro**: `padronizar_logradouros` aplica centenas de regras de
   abreviação. Output pode mudar drasticamente vs UDF atual → mais matches
   esperados.
4. **`_fix_logradouro_prefixes`**: se removido e paridade falhar, reintroduzir.

### 5.3 Testes unitários do `standardize.py`
- Criar `python-package/tests/test_standardize.py`.
- Testar `padronizar_enderecos` com casos do R `padronizar_enderecos.R:42-80`:
  - `"r ns sra da piedade"` → `"RUA NOSSA SENHORA DA PIEDADE"`.
  - `nroLogradouro=20` (int) → `20` (int).
  - `cep=25220020` (int) → `"25220-020"`.
  - `codmun_dom=3304557` → `"RIO DE JANEIRO"`.
  - `uf_dom="rj"` → `"RJ"`.
- Verificações sobre `pl.DataFrame` retornado:
  `assert df_padr["logradouro_padr"][0] == "RUA NOSSA SENHORA DA PIEDADE"`.
- Confirmar dtypes das colunas `*_padr` (Utf8 / Int32 nullável) — protege
  contra regressão silenciosa para `Object` dtype caso `return_dtype` seja
  esquecido.
- Testar `correspondencia_campos` com cases `None` e erro de all-None.

### 5.4 Validar `busca_por_cep`

```bash
python -m pytest python-package/tests/test_busca_por_cep.py -v
```

---

## Resumo de arquivos

| Arquivo                                                        | Ação                                                                       |
| ---                                                            | ---                                                                        |
| `geocodebr/pyproject.toml`                                     | Adicionar deps `enderecobr>=0.2.0` e `polars>=1.0`                         |
| `geocodebr/python-package/geocodebr/standardize.py`            | **Criar** — `padronizar_enderecos` + `correspondencia_campos` (Polars)     |
| `geocodebr/python-package/geocodebr/cep.py`                    | **Criar** — mover `busca_por_cep` + helpers                               |
| `geocodebr/python-package/geocodebr/geocode.py`                | Refatorar: Polars-first, remover 7 funções, reordenar fluxo               |
| `geocodebr/python-package/geocodebr/__init__.py`               | Atualizar import de `busca_por_cep`                                       |
| `geocodebr/python-package/geocodebr/utils.py`                  | Sem mudança (`cria_col_logradouro_confusao` é SQL puro)                   |
| `geocodebr/python-package/geocodebr/fields.py`                 | Sem mudança                                                                |
| `geocodebr/python-package/tests/test_standardize.py`           | **Criar** — testes unitários do `standardize` (Polars)                    |
| `enderecobr_rs/`                                               | Sem mudança (binding já pronto)                                            |

---

## Riscos e validações

| Risco                                                    | Mitigação                                                                                                                          |
| ---                                                      | ---                                                                                                                                 |
| `enderecobr` v0.2.0 não no PyPI                          | Instalar via `maturin develop` localmente                                                                                          |
| Códigos de município de 6 dígitos não resolvidos         | Validar com small/large sample; se R também falha, paridade OK                                                                     |
| `_fix_logradouro_prefixes` removido quebra paridade      | Testar sem; se falhar, reintroduzir                                                                                                |
| Performance para datasets grandes (1M-10M linhas)        | Polars `map_elements` com `return_dtype` obrigatório (Arrow Utf8, multi-thread Rayon). Sem `return_dtype` cai em `Object` dtype, anulando o ganho de memória. |
| Datasets >10M que não cabem na RAM                        | Fora de escopo desta refatoração. Fallback futuro: DuckDB UDF arrow-batch (com spill para disco). Avaliar se houver demanda real.   |
| `padronizar_numeros_para_int` muda resultados de match   | É correto vs R; paridade deve melhorar, não piorar                                                                                 |
| Threads Polars vs threads DuckDB (`n_cores`) dessincronizadas | Polars lê `POLARS_MAX_THREADS` ou usa todos os cores; DuckDB respeita `n_cores`. Alinhar passando `n_cores` ao Polars via `pl.threadpool_size()` ou env var em `create_geocodebr_db`. Detalhe de otimização, não bloqueante. |
| `map_elements` ainda é escalar (binding sem API vetorial) | Aceito como limitação atual. Para vetorização real seria preciso expor `fn(&[&str]) -> Vec<String>` no `enderecobr_rs` — PR upstream separado. |
| `return_dtype` esquecido → regressão silenciosa p/ `Object` dtype | Adicionar assertion de dtype no `test_standardize.py` (colunas `*_padr` devem ser `Utf8`/`Int32`, nunca `Object`).            |

---

## Ordem recomendada de execução

1. **Fase 0**: adicionar `enderecobr` como dep, validar import.
2. **Fase 1**: criar `standardize.py` com `padronizar_enderecos` e
   `correspondencia_campos` (sem tocar no resto ainda).
3. **Fase 5.3**: escrever e rodar `test_standardize.py` — confirmar que o
   módulo novo funciona isoladamente.
4. **Fase 2**: refatorar `geocode.py` para usar `standardize`.
5. **Fase 5.1-5.2**: rodar testes de paridade vs R — iterar até passar.
6. **Fase 3**: mover `busca_por_cep` para `cep.py`.
7. **Fase 4**: atualizar `__init__.py`.
8. **Fase 5.4**: rodar testes de `busca_por_cep`.

---

*Documento gerado a partir da verificação do `enderecobr_rs` (release v0.2.0,
commit `fe2b8b4`) e da análise do port Python em
`geocodebr/python-package/`. Referências ao plano de porting original em
`geocodebr-python-porting-plan.md` §3.4.2 e §5.*
