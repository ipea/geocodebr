# geocodebr Python: Geolocalizacao de Enderecos Brasileiros

Versao Python experimental do `geocodebr`, usando DuckDB como motor tabular
principal. A proposta e preservar a dinamica de uso do pacote R, incluindo nomes
de funcoes em portugues, mas mantendo o processamento interno em SQL/DuckDB para
boa performance e menor uso de memoria.

O pacote geolocaliza enderecos brasileiros sem limite de numero de consultas,
com base em dados abertos do CNEFE (Cadastro Nacional de Enderecos para Fins
Estatisticos), publicado pelo IBGE.

## Instalacao

No momento, esta versao Python ainda esta em desenvolvimento dentro deste
repositorio. Para instalar localmente:

```bash
cd python-package
python -m pip install -e .
```

Dependencias principais:

- `duckdb`: motor principal de dados e SQL.
- `pyarrow`: formato padrao de retorno e interoperabilidade com Parquet.
- `requests`: download dos dados CNEFE.
- `h3`: criacao opcional de celulas H3.

Para desenvolvimento e testes:

```bash
python -m pip install -e ".[test]"
python -m pytest -q
```

## Utilizacao

O pacote possui tres funcoes principais:

1. `geocode()`
2. `geocode_reverso()`
3. `busca_por_cep()`

As funcoes retornam, por padrao, um `pyarrow.Table`. Caso precise converter para
`pandas`, use `.to_pandas()` no resultado final.

## 1. Geolocalizacao: de enderecos para coordenadas

Primeiro, indique quais colunas da sua tabela representam cada campo do
endereco usando `definir_campos()`. Depois, chame `geocode()`.

O primeiro uso pode baixar os dados CNEFE em cache local.

```python
import pyarrow.csv as pv

from geocodebr import definir_campos, geocode

enderecos = pv.read_csv("../inst/extdata/small_sample.csv")

campos = definir_campos(
    logradouro="nm_logradouro",
    numero="Numero",
    cep="Cep",
    localidade="Bairro",
    municipio="nm_municipio",
    estado="nm_uf",
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

Tambem e possivel passar um caminho para arquivo `.csv` ou `.parquet`:

```python
resultado = geocode(
    enderecos="../inst/extdata/small_sample.csv",
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

Com `resultado_completo=True`, tambem retorna campos encontrados no CNEFE, como
`logradouro_encontrado`, `numero_encontrado`, `cep_encontrado`,
`localidade_encontrada`, `municipio_encontrado`, `estado_encontrado`,
`similaridade_logradouro`, `contagem_cnefe`, `empate` e `cod_setor`.

## 2. Geolocalizacao reversa: de coordenadas para enderecos

`geocode_reverso()` busca o endereco mais proximo de cada ponto dentro de uma
distancia maxima em metros.

A entrada pode ser:

- tabela com colunas `lon` e `lat`
- tabela com colunas `longitude` e `latitude`
- tabela com colunas `x` e `y`
- `GeoDataFrame` em `EPSG:4674`

```python
import pyarrow as pa

from geocodebr import geocode_reverso

pontos = pa.table(
    {
        "id": [1, 2],
        "lon": [-47.9001, -43.2001],
        "lat": [-15.8001, -22.9001],
    }
)

enderecos_proximos = geocode_reverso(
    pontos=pontos,
    dist_max=1000,
    verboso=False,
)

print(enderecos_proximos.to_pandas())
```

O resultado inclui os campos do endereco encontrado e a coluna
`distancia_metros`.

## 3. Busca por CEP

`busca_por_cep()` retorna os enderecos associados a um ou mais CEPs.

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

## Exemplos de uso do geocodebr Python

Esta pasta contem exemplos simples usando as funcoes principais da versao Python:

- `geocode()`: busca coordenadas a partir de enderecos.
- `busca_por_cep()`: busca enderecos/coordenadas a partir de CEPs.
- `geocode_reverso()`: busca endereco proximo a coordenadas.

Execute os exemplos a partir da raiz do repositorio:

```bash
uv run python exemple/geocode_enderecos.py
uv run python exemple/busca_por_cep.py
uv run python exemple/geocode_reverso.py
```

## Cache dos dados CNEFE

Na primeira execucao, o pacote baixa arquivos Parquet do release CNEFE usado
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

# definir uma pasta de cache especifica
definir_pasta_cache("D:/dados/geocodebr-cache", verboso=True)

# apagar cache configurado
# deletar_pasta_cache()
```

## DuckDB-first

Esta versao evita usar `pandas` no pipeline interno. O fluxo principal registra
entradas no DuckDB, executa joins/filtros/matches em SQL e so materializa o
resultado no final como `pyarrow.Table`.

Isso facilita a paridade com o pacote R, que tambem usa DuckDB para o motor de
geocodificacao, e ajuda em bases maiores.

## Estado atual

Esta versao Python ainda e experimental.

Ja implementado:

- `definir_campos()`
- `download_cnefe()`
- funcoes de cache
- `busca_por_cep()`
- `geocode()` com motor DuckDB
- `geocode_reverso()` com DuckDB Spatial
- testes unitarios com Parquets sinteticos

Pontos que ainda precisam de validacao ampla:

- paridade completa da padronizacao com o pacote R `enderecobr`
- comparacao Python vs R em amostras reais maiores
- retorno espacial equivalente a `sf`/`GeoDataFrame` quando `resultado_sf=True`

