# Plano de migracao R -> Python

Este documento resume a analise dos scripts R do pacote `geocodebr` e propoe
uma versao Python preservando a dinamica de uso e os nomes das funcoes publicas.

## API publica a manter

As funcoes exportadas no `NAMESPACE` devem existir tambem no pacote Python:

- `definir_campos(estado, municipio, logradouro=None, numero=None, cep=None, localidade=None)`
- `geocode(enderecos, campos_endereco=..., resultado_completo=False, resolver_empates=True, resultado_sf=False, h3_res=None, padronizar_enderecos=True, verboso=True, cache=True, n_cores=None)`
- `busca_por_cep(cep, h3_res=None, resultado_sf=False, verboso=True, cache=True)`
- `geocode_reverso(pontos, dist_max=1000, verboso=True, cache=True, n_cores=None)`
- `download_cnefe(tabela="todas", verboso=True, cache=True)`
- `definir_pasta_cache(path, verboso=True)`
- `listar_pasta_cache()`
- `listar_dados_cache(print_tree=False)`
- `deletar_pasta_cache()`

Em Python, a recomendacao e manter esses nomes em portugues para reduzir a
curva de aprendizado. Internamente, os modulos podem ser separados por dominio.

## Estrutura sugerida

```text
python-package/
  pyproject.toml
  src/geocodebr/
    __init__.py
    cache.py
    download_cnefe.py
    fields.py
    geocode.py
    reverse.py
    db.py
    matching.py
    tables.py
    string_dist.py
    utils.py
    errors.py
    messages.py
  tests/
    test_cache.py
    test_fields.py
    test_busca_por_cep.py
    test_geocode.py
    test_geocode_reverso.py
```

## Dependencias Python recomendadas

- `duckdb`: motor SQL central e tambem a camada principal de manipulacao
  tabular. A versao Python deve manter os dados em tabelas/views DuckDB sempre
  que possivel, evitando transformar o fluxo interno em `pandas`.
- `pyarrow`: leitura/escrita Parquet e interoperabilidade com DuckDB.
- `requests` ou `httpx`: download dos Parquets do release CNEFE.
- `platformdirs`: diretorio de cache/config persistente equivalente a `tools::R_user_dir`.
- `tqdm`: barra de progresso equivalente a `cli`/progress bar.
- `geopandas`, `shapely`, `pyproj`: saida espacial e `geocode_reverso`.
- `h3`: criacao de colunas `h3_03`, `h3_04` etc.
- `rapidfuzz` ou UDF DuckDB: apenas se `jaro_similarity` nao estiver disponivel
  de forma consistente na instalacao DuckDB Python.
- Uma camada propria de padronizacao de endereco ou dependencia Python
  equivalente a `enderecobr`.
- `pandas`: opcional apenas para aceitar/retornar dados no estilo familiar da
  API Python. Internamente, nao deve ser o motor de processamento.

## Pontos criticos de paridade

1. `enderecobr`
   - O R depende de `enderecobr::padronizar_enderecos`, `padronizar_ceps`,
     `padronizar_municipios` e `correspondencia_campos`.
   - A versao Python precisa gerar as mesmas colunas padronizadas:
     `estado_padr`, `municipio_padr`, `logradouro_padr`, `numero_padr`,
     `cep_padr`, `bairro_padr`.
   - Este e o maior risco de divergencia entre R e Python.

2. SQL DuckDB
   - As funcoes de matching (`match_cases`, `match_weighted_cases`,
     `match_cases_probabilistic`, `match_weighted_cases_probabilistic`) sao
     quase totalmente SQL.
   - A melhor estrategia e portar os templates SQL para Python com interpolacao
     controlada, preservando nomes de tabelas temporarias e colunas.
   - O DuckDB deve substituir tanto `data.table` quanto a maior parte do uso
     potencial de `pandas`: padronizacao, filtros, joins, atualizacoes,
     desempate, H3 e montagem do output devem preferir SQL/tabelas temporarias.

3. Dados CNEFE
   - `data_release` atual: `v0.4.1`.
   - Fonte: `https://github.com/ipeaGIT/padronizacao_cnefe/releases/download/{data_release}/{arquivo}`.
   - Os arquivos Parquet baixados sao a base compartilhada entre R e Python.

4. Geometria
   - `resultado_sf=TRUE` no R retorna `sf`.
   - Em Python, o equivalente natural e `geopandas.GeoDataFrame` com CRS
     `EPSG:4674`.
   - `geocode_reverso` hoje usa DuckDB Spatial via `duckspatial`; em Python deve
     usar `duckdb` com extensao `spatial` ou uma combinacao `geopandas`/`sjoin`.

## Sequencia de implementacao sugerida

1. Criar pacote Python basico com `pyproject.toml`, `src/geocodebr` e exports em
   `__init__.py`.
2. Portar cache:
   - `definir_pasta_cache`
   - `listar_pasta_cache`
   - `listar_dados_cache`
   - `deletar_pasta_cache`
3. Portar `definir_campos` e validacoes de colunas.
4. Portar `download_cnefe`.
5. Portar constantes e utilitarios DuckDB-first:
   - `data_release`
   - `get_key_cols`
   - `get_reference_table`
   - listas de `match_type`
   - `add_precision_col`
   - `merge_results_to_input`
6. Portar funcoes de matching SQL.
7. Implementar/pinchar padronizacao de enderecos em Python.
8. Portar `busca_por_cep`.
9. Portar `geocode`.
10. Portar `geocode_reverso`. Primeira versao implementada com DuckDB Spatial,
    aceitando `lon`/`lat`, `longitude`/`latitude`, `x`/`y` ou GeoDataFrame em
    `EPSG:4674`, e retornando `pyarrow.Table`.
11. Criar testes Python com `pytest`, usando os testes R como contrato de
    comportamento.

## Mapeamento dos arquivos R

- `R/cache.R` -> `cache.py`
- `R/download_cnefe.R` -> `download_cnefe.py`
- `R/definir_campos.R` -> `fields.py`
- `R/create_geocodebr_db.R` -> `db.py`
- `R/geocode.R` -> `geocode.py`
- `R/busca_por_cep.R` -> `geocode.py` ou `cep.py`
- `R/geocode_reverso.R` -> `reverse.py`
- `R/match_cases*.R`, `R/match_weighted_cases*.R` -> `matching.py`
- `R/register_cnefe_tables.R` -> `tables.py`
- `R/string_dist.R` -> `string_dist.py`
- `R/trata_empates_geocode_duckdb.R` -> `matching.py` ou `ties.py`
- `R/utils.R` -> `utils.py`
- `R/error.R`, `R/message.R`, `R/progress_bar.R` -> `errors.py`, `messages.py`

## Contratos de saida importantes

`geocode` deve aceitar dados de entrada em formatos convenientes, mas o fluxo
interno deve registrar a entrada diretamente no DuckDB. A saida padrao pode ser
uma relacao DuckDB materializada sob demanda ou um `DataFrame` para ergonomia da
API; a decisao deve ficar explicita na implementacao.

`geocode` deve preservar as colunas originais e adicionar:

- sempre: `lat`, `lon`, `precisao`, `tipo_resultado`, `desvio_metros`,
  `endereco_encontrado`
- se `resultado_completo=True`: `logradouro_encontrado`, `numero_encontrado`,
  `cep_encontrado`, `localidade_encontrada`, `municipio_encontrado`,
  `estado_encontrado`, `similaridade_logradouro`, `contagem_cnefe`, `empate`,
  `cod_setor`
- se `h3_res` for informado: `h3_03`, `h3_04`, etc.

`busca_por_cep` deve retornar `cep`, `estado`, `municipio`, `logradouro`,
`localidade`, `lon`, `lat` e H3 quando solicitado.

`geocode_reverso` deve receber pontos em `EPSG:4674`, validar bounding box do
Brasil e retornar o endereco mais proximo dentro de `dist_max`, com
`distancia_metros`.

## Observacoes de risco

- O teste de paridade deve comparar resultados Python vs R em amostras pequenas,
  incluindo casos determiniscos, probabilisticos, interpolacao por numero,
  empates e CEP inexistente.
- A implementacao deve evitar chamar `.df()`/`.fetchdf()` no meio do pipeline.
  Essas chamadas devem ficar restritas a limites claros da API, por exemplo no
  retorno final quando o usuario pedir um objeto Python em memoria.
- A padronizacao inicial ja cobre normalizacao de acentos/caixa, UF por extenso
  para sigla, CEP numerico, numero inteiro e tentativa de municipio por codigo
  IBGE quando a tabela `municipio.parquet` trouxer coluna de codigo reconhecida.
  Ainda precisa de validacao ampla contra `enderecobr`.
- Ha possiveis bugs/quirks no R que talvez precisem ser replicados ou corrigidos
  explicitamente. Exemplo: nos loops de H3, o nome da coluna usa `h3_res` em vez
  do item `i`; funciona para vetor curto no teste, mas deve ser revisto ao portar.
- A versao Python deve evitar montar SQL com valores vindos diretamente do usuario.
  Os nomes de colunas podem ser validados contra `^[A-Za-z0-9_]+$`, como no R.
