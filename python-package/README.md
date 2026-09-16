# geocodebr Python: Geolocalização de Endereços Brasileiros <img align="right" src="../r-package/man/figures/logo.svg" alt="" width="180">

[![PyPI](https://img.shields.io/badge/PyPI-em%20breve-9ca3af)]()
[![python-check](https://github.com/ipea/geocodebr/actions/workflows/python-check.yaml/badge.svg)](https://github.com/ipea/geocodebr/actions/workflows/python-check.yaml)
[![python-parity](https://github.com/ipea/geocodebr/actions/workflows/python-parity.yaml/badge.svg)](https://github.com/ipea/geocodebr/actions/workflows/python-parity.yaml)
[![Codecov test
coverage](https://codecov.io/gh/ipea/geocodebr/branch/test_python/graph/badge.svg?flag=python)](https://app.codecov.io/gh/ipea/geocodebr?tree/python_test?flag%5B0%5D=python)

Versão Python do `geocodebr`, usando DuckDB como motor tabular principal.
A proposta é preservar a dinâmica de uso do pacote R, incluindo nomes
de funções em português, mas mantendo o processamento interno em SQL/DuckDB para
boa performance e menor uso de memória.

O pacote geolocaliza endereços brasileiros sem limite de número de consultas,
com base em dados abertos do CNEFE (Cadastro Nacional de Endereços para Fins
Estatísticos), publicado pelo IBGE.

## Instalação

No momento, esta versão Python ainda está em desenvolvimento dentro deste
repositório (a publicação no PyPI está planejada). Para instalar localmente:

```bash
cd python-package
python -m pip install -e .
```

Dependências principais:

- `duckdb`: motor principal de dados e SQL.
- `pyarrow`: formato padrão de retorno e interoperabilidade com Parquet.
- `enderecobr`: padronização dos endereços, garantindo paridade com o pacote R.
- `polars`: processamento tabular interno, usado para integrar o `enderecobr`.
- `requests`: download dos dados do CNEFE.
- `h3`: criação opcional de células H3.

## Utilização

O pacote possui três funções principais:

1. `geocode()`
2. `geocode_reverso()`
3. `busca_por_cep()`

As funções retornam, por padrão, um `pyarrow.Table`. Caso precise converter para
`pandas`, use `.to_pandas()` no resultado final. Passando `resultado_gpd=True`, o
retorno é um `geopandas.GeoDataFrame` de pontos no CRS SIRGAS 2000 (EPSG 4674),
equivalente ao `sf` do pacote R. Esse retorno exige o extra `geo` na instalação
(`python -m pip install geocodebr[geo]`).

### 1. Geolocalização: de endereços para coordenadas

Primeiro, indique quais colunas da sua tabela representam cada campo do
endereço usando `definir_campos()`. Depois, chame `geocode()`.

Por padrão, os endereços são padronizados internamente pela função
`enderecobr_padronizar_enderecos()`, o que é essencial para uma
geolocalização correta. O primeiro uso pode baixar os dados do CNEFE para o
cache local.

```python
import polars as pl

from geocodebr import definir_campos, geocode

enderecos = pl.DataFrame({
    "logradouro": ["RUA PRESIDENTE VARGAS", "AVENIDA PAULISTA"],
    "numero": [123, 1000],
    "cep": ["20080-901", "01310-100"],
    "localidade": ["Centro", "Bela Vista"],
    "municipio": ["RIO DE JANEIRO", "SAO PAULO"],
    "estado": ["RJ", "SP"],
})

campos = definir_campos(
    logradouro="logradouro",
    numero="numero",
    cep="cep",
    localidade="localidade",
    municipio="municipio",
    estado="estado",
)

resultado = geocode(
    enderecos=enderecos,
    campos_endereco=campos,
    resultado_completo=False,
    resolver_empates=True,
    h3_res=[8, 10],
    verboso=False,
)

print(resultado.schema.names)
print(resultado.to_pandas().head())
```

Também é possível passar diretamente um caminho para arquivo `.csv` ou `.parquet`:

```python
resultado = geocode(
    enderecos="caminho/para/enderecos.csv",
    campos_endereco=campos,
    verboso=False,
)
```

O resultado preserva as colunas originais e adiciona, entre outras:

- `lat`
- `lon`
- `precisao`
- `tipo_resultado`
- `desvio_metros`
- `endereco_encontrado`

Com `resultado_completo=True`, também retorna campos encontrados no CNEFE, como
`logradouro_encontrado`, `numero_encontrado`, `cep_encontrado`,
`localidade_encontrada`, `municipio_encontrado`, `estado_encontrado`,
`similaridade_logradouro`, `contagem_cnefe`, `empate` e `cod_setor`.

### 2. Geolocalização reversa: de coordenadas para endereços

`geocode_reverso()` busca o endereço mais próximo de cada ponto dentro de uma
distância máxima em metros. Assim como no R, a entrada deve ser um
`GeoDataFrame` de pontos no CRS SIRGAS 2000 (`EPSG:4674`), e o retorno é o
próprio `GeoDataFrame` de input acrescido dos campos do endereço encontrado e
da coluna `distancia_metros`. Esta função requer o extra `geo`
(`pip install geocodebr[geo]`).

```python
import geopandas as gpd

from geocodebr import geocode_reverso

pontos = gpd.GeoDataFrame(
    {"id": [1, 2]},
    geometry=gpd.points_from_xy([-47.9001, -43.2001], [-15.8001, -22.9001]),
    crs="EPSG:4674",
)

enderecos_proximos = geocode_reverso(
    pontos=pontos,
    dist_max=1000,
    verboso=False,
)

print(enderecos_proximos)
```

O resultado inclui os campos do endereço encontrado e a coluna
`distancia_metros`.

### 3. Busca por CEP

`busca_por_cep()` retorna os endereços associados a um ou mais CEPs.

```python
from geocodebr import busca_por_cep

ceps = ["70390-025", "20071-001", "99999-999"]

resultado_cep = busca_por_cep(
    cep=ceps,
    h3_res=10,
    verboso=False,
)

print(resultado_cep.to_pandas())
```

O resultado inclui:

- `cep`
- `estado`
- `municipio`
- `logradouro`
- `localidade`
- `lon`
- `lat`

Se `h3_res` for informado, o pacote adiciona colunas como `h3_08` ou `h3_10`.

### Padronização de endereços

A função `enderecobr_padronizar_enderecos()` também está disponível
publicamente, para padronizar os endereços antes da geolocalização (ou usá-la
de forma independente). Ela recebe um `polars.DataFrame` e o dicionário criado
com `definir_campos()`, e adiciona as colunas `*_padr`:

```python
from geocodebr import enderecobr_padronizar_enderecos

enderecos_padrao = enderecobr_padronizar_enderecos(
    enderecos=enderecos,
    campos_do_endereco=campos,
    formato_estados="sigla",
    formato_numeros="integer",
    manter_cols_extras=True,
)
```

Se os seus dados já estiverem padronizados (ou seja, já contiverem as colunas
`*_padr`), chame `geocode(..., padronizar_enderecos=False)` para pular essa
etapa.

## Precisão dos resultados

Os resultados do `geocode()` são classificados em seis categorias de
`precisao` ("numero", "numero_aproximado", "logradouro", "cep", "localidade" e
"municipio"), desagregadas em códigos de `tipo_resultado` (e.g. `dn01`,
`pa03`), e incluem a coluna `desvio_metros`, com uma estimativa da incerteza
da localização encontrada. A interpretação dessas colunas, o significado de
cada código e as regras de resolução de empates estão documentadas na
[**vignette "geocode"**](https://ipea.github.io/geocodebr/articles/geocode.html).

## Cache dos dados do CNEFE

Na primeira execução, o pacote baixa arquivos Parquet do release do CNEFE usado
pelo `geocodebr`. Esses arquivos ficam em cache local para acelerar chamadas
futuras.

```python
from geocodebr import (
    definir_pasta_cache,
    listar_pasta_cache,
    listar_dados_cache,
    deletar_pasta_cache,
    download_cnefe,
)

print(listar_pasta_cache())

download_cnefe(tabela="municipio_logradouro_cep_localidade", verboso=True)

arquivos = listar_dados_cache()
print(arquivos)

# definir uma pasta de cache específica
definir_pasta_cache("D:/dados/geocodebr-cache", verboso=True)

# apagar cache configurado
# deletar_pasta_cache()
```

## Processamento interno (DuckDB-first)

Esta versão evita usar `pandas` no pipeline interno. O fluxo principal registra
as entradas no DuckDB, executa joins/filtros/matches em SQL e só materializa o
resultado no final como `pyarrow.Table`.

A padronização dos endereços é a única etapa fora do DuckDB: é feita em
`polars`, fazendo a ponte com os bindings Python do `enderecobr`, sem
materializar `pandas` em nenhum momento.

Isso facilita a paridade com o pacote R, que também usa DuckDB para o motor de
geocodificação, e ajuda em bases maiores.

## Windows e performance

No Windows, o `python.exe` roda por padrão no heap NT legacy e não no mais
moderno e eficaz Segment Heap. O heap legado degrada sob alocação multithread
intensa do DuckDB: o `geocode()` fica mais lento e piora a cada chamada na
mesma sessão (contexto em
[duckdb/duckdb#24027](https://github.com/duckdb/duckdb/issues/24027) e no
[relatório de diagnóstico do pacote](../quality_reports/diagnoses/2026-09-04_geocode-deterioracao-python-diagnostico.md)).

O pacote mitiga o problema de duas formas:

1. **Limitação automática de threads** — no Windows sem Segment Heap, se
   `n_cores` não for definido, o `geocode()` limita o DuckDB a
   `min(4, núcleos da máquina)` threads
   (mínimo da curva tempo x threads no heap legacy, confirmado por sweep com o
   workload canônico do duckdb#24027 — `benchmarks/verifica_sweep_threads.py`;
   bacia plana entre 3 e 6 threads) e emite um aviso uma vez
   por sessão. Um `n_cores` passado de forma explícita é respeitado.

2. **Interpretador com Segment Heap (recomendado)** — usuário pode gerar uma
   cópia do interpretador Python com o manifesto patcheado com o Segment Heap
   e rodar o `geocode()` a partir dele. Para criar a cópia, basta rodar:

   ```bash
   python -m geocodebr._heap_patch
   ```

   O comando cria o arquivo `python-geocodebr-sh.exe` ao lado do interpretador
   base (`python.exe`), sem alterar o original. Inicie a sessão pela cópia para
   que o DuckDB use o Segment Heap.

   **Em benchmarks internos com 10 milhões de endereços, o tempo total do
   `geocode()` caiu de 11:47 minutos para 3:08 minutos**.

Limitações conhecidas:

- Requer Windows 10 (build 19041) ou superior.
- Não existe configuração do Windows (variável de ambiente ou registro) que
  ligue o Segment Heap por processo. A camada de compatibilidade — via
  `__COMPAT_LAYER=SEGMENTHEAP` ou persistida no registro
  (`AppCompatFlags\Layers` / `Image File Execution Options`) — não alcança o
  heap criado no startup, por onde passam as alocações do DuckDB.
- O ganho vale apenas para sessões iniciadas pela cópia
  (`python-geocodebr-sh.exe`); Jupyter/IDEs que lançam outro interpretador não
  se beneficiam.
- A cópia é criada na pasta do interpretador base; se ela não for gravável
  (ex.: `Program Files`), execute o terminal como administrador ou use uma
  instalação por usuário (ex.: `uv`, `pyenv`).
- A cópia usa os pacotes do ambiente base. Com geocodebr instalado em venv,
  aponte `PYTHONPATH` para o `site-packages` da venv. Exemplo em PowerShell:

  ```powershell
   $env:PYTHONPATH = "C:\caminho\para\.venv\Lib\site-packages"; & "C:\caminho\para\python-geocodebr-sh.exe" "C:\caminho\para\seu_script.py"
   ```

- A limitação de threads reduz a contenção do heap, mas não elimina a
  deterioração entre chamadas sucessivas na mesma sessão; a cópia com Segment
  Heap resolve os dois problemas.

## Desenvolvimento e testes

Para rodar a suíte de testes:

```bash
uv run pytest -q -m "not r_parity"
```

Esse comando roda apenas os testes unitários, com
Parquets sintéticos, sem baixar dados do CNEFE.

### Testes de paridade R vs Python

O pacote também inclui testes que comparam a saída do Python com a saída do
pacote R usando os dados de exemplo `inst/extdata/small_sample.csv` e
`inst/extdata/large_sample.parquet`.

Esses testes exigem `Rscript` no `PATH`, instalam o pacote R localmente em uma
biblioteca temporária e podem baixar dados do CNEFE. Se `Rscript` não estiver
disponível, eles são pulados automaticamente.

```bash
uv run pytest -m r_parity -q
```

### Exemplos

A pasta `exemple/` contém scripts simples usando as funções principais da
versão Python:

- `geocode_enderecos.py`: busca coordenadas a partir de endereços.
- `busca_por_cep.py`: busca endereços/coordenadas a partir de CEPs.
- `geocode_reverso.py`: busca endereço próximo a coordenadas.

Execute os exemplos a partir da raiz do repositório:

```bash
uv run python exemple/geocode_enderecos.py
uv run python exemple/busca_por_cep.py
uv run python exemple/geocode_reverso.py
```
