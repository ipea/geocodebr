# Changelog

## [Unreleased]

### Corrigido

- `geocode()`: a coluna interna usada na busca probabilística
  (`temp_lograd_determ`) passa a começar nula, como no pacote R, e não como
  texto vazio. Antes, se a base do CNEFE tivesse um logradouro vazio, endereços
  sem candidato na busca por similaridade poderiam ser dados como encontrados
  nesse logradouro (`pn01`). O release atual do CNEFE não tem logradouro vazio,
  então o resultado com os dados atuais não muda.

### Modificado

- `geocode()`: a cada etapa do matching, a remoção dos endereços já encontrados
  passou a considerar só os resultados da etapa corrente, em vez de varrer
  todos os resultados acumulados, e deixou de fazer duas contagens extras por
  etapa. Espelha a otimização já presente no pacote R. O resultado não muda.
- `geocode()`: menor uso de memória. As tabelas de referência do CNEFE passam a
  ser apagadas assim que nenhuma etapa seguinte do matching precisa delas, assim
  como as tabelas intermediárias depois do laço e da resolução de empates; e as
  colunas do CNEFE que o pacote não usa (`code_muni`, `n_setor` e, sem
  `resultado_completo`, `cod_setor`) deixam de ser carregadas. Pico de memória
  ~12% menor com 20 mil endereços e ~33% menor com 1 milhão. Espelha o pacote
  R. O resultado não muda.
- `geocode()`: busca probabilística mais rápida. O cálculo de similaridade de
  logradouros passou a ser feito uma vez por combinação distinta de chave e
  logradouro (em vez de uma vez por endereço), sem candidatos repetidos, e as
  etapas sem número deixam de recalcular endereços com número, já testados na
  etapa anterior. Mesma query do pacote R. O resultado não muda.
- `geocode()`: interpolação por número (resultados `da01`–`da04` e
  `pa01`–`pa03`) mais rápida. O endereço encontrado passou a ser montado uma
  vez por grupo de candidatos, e não uma vez por candidato, e o agrupamento
  usa colunas curtas em vez do texto do endereço. Mesma query do pacote R. O
  resultado não muda.
- `geocode()`: as tabelas de logradouros usadas na busca probabilística passam
  a ser filtradas também pelos estados do input, e não só pelos municípios,
  deixando de carregar municípios homônimos de outros estados. Espelha o
  pacote R. O resultado não muda.

## [0.1.1] - 2026-09-23

### Modificado

- `download_cnefe()`: o download das tabelas do CNEFE passou a ser feito em
  paralelo, com `ThreadPoolExecutor` (até 8 workers, um por arquivo), em vez do
  laço sequencial anterior. Espelha o comportamento do R
  (`httr2::req_perform_parallel()`) e reduz o tempo de download. Erros de
  download agora são agregados e relançados como `GeocodeBRError`, e a barra de
  progresso passa a contar arquivos concluídos.

## [0.1.0] - 2026-09-22

Primeira versão pública do pacote Python `geocodebr`, um porte do pacote R
[{geocodebr}](https://github.com/ipeaGIT/geocodebr) (v0.6.4/desenvolvimento).
Preserva a dinâmica de uso do R, incluindo os nomes de funções em português e a
taxonomia de `precisao` / `tipo_resultado`, usando DuckDB como motor principal
de dados.

### Adicionado

- `geocode()`: geolocaliza endereços brasileiros a partir de uma tabela na qual
  cada coluna descreve um campo do endereço (logradouro, número, CEP, etc.). O
  resultado preserva as colunas originais e adiciona `lat`, `lon`, `precisao`,
  `tipo_resultado`, `desvio_metros` e `endereco_encontrado` (e, com
  `resultado_completo=True`, também `cod_setor`, `contagem_cnefe`, `empate` e as
  colunas `*_encontrado`/`*_encontrada`). Aceita `pyarrow.Table`,
  `polars.DataFrame`, `pandas.DataFrame` ou o caminho de um arquivo `.csv` ou
  `.parquet`.
- `geocode_reverso()`: busca o endereço mais próximo de pontos de um
  `geopandas.GeoDataFrame` dentro de `dist_max` metros, devolvendo o próprio
  `GeoDataFrame` de input acrescido do endereço encontrado e da coluna
  `distancia_metros`.
- `busca_por_cep()`: retorna os endereços e coordenadas associados a um ou mais
  CEPs.
- `definir_campos()`: monta o dicionário de correspondência entre os campos do
  endereço e as colunas da tabela de input. `estado` e `municipio` são
  obrigatórios.
- `download_cnefe()`: baixa uma ou mais tabelas da versão pré-processada e
  enriquecida do CNEFE usada pelo pacote.
- `definir_pasta_cache()`, `listar_pasta_cache()`, `listar_dados_cache()` e
  `deletar_pasta_cache()`: gerenciamento da pasta de cache local dos dados do
  CNEFE, persistente entre sessões.
- `enderecobr_padronizar_enderecos()`: padronização dos campos de endereço,
  espelhando `enderecobr::padronizar_enderecos` do R.

### Detalhes de implementação e diferenças em relação ao R

- **Retorno padrão em `pyarrow.Table`.** As três funções principais retornam um
  `pyarrow.Table` por padrão. Com `resultado_gpd=True`, o retorno é um
  `geopandas.GeoDataFrame` de pontos no CRS SIRGAS 2000 (EPSG 4674),
  equivalente ao `sf` do R. Esse retorno exige o extra `geo`
  (`pip install geocodebr[geo]`).
- **Pipeline DuckDB-first.** O fluxo interno registra as entradas no DuckDB,
  executa joins, filtros e matches em SQL e só materializa o resultado no final.
  A padronização de endereços é a única etapa fora do DuckDB, feita em `polars`.
- **Ciclo de vida da conexão DuckDB.** `geocode()`, `geocode_reverso()` e
  `busca_por_cep()` fecham a conexão com o banco ao final da execução, inclusive
  quando interrompidas por um erro no meio do caminho (bloco `finally`).
  Diferentemente do pacote R, o `geocode()` roda no próprio processo do usuário
  (sem subprocesso equivalente ao `callr::r()`).
- **Paralelismo configurável.** `geocode()` e `geocode_reverso()` aceitam
  `n_cores`.
- **Mitigação no Windows.** Sem Segment Heap, o `geocode()` limita
  automaticamente o DuckDB a `min(4, núcleos)` threads e emite um aviso uma vez
  por sessão. A criação opcional de uma cópia do interpretador com Segment Heap
  (`python -m geocodebr._heap_patch`) chega a reduzir o tempo de uma carga de 10
  milhões de endereços de ~11:47 para ~3:08 (benchmarks internos).
- **Suíte de testes de paridade R vs Python.** Testes comparam a saída do
  Python com a do pacote R nos arquivos de exemplo, marcados com `r_parity` e
  pulados automaticamente quando `Rscript` não está disponível.

### Validação de paridade com o R

- Em uma carga real de **43,9 milhões de endereços**, o
  `geocode()` retornou resultado **idêntico** ao do pacote R em todas as linhas,
  comparadas uma a uma: mesmas categorias (`tipo_resultado`, `precisao`), mesmo
  endereço encontrado, mesmos `desvio_metros`, `cod_setor` e `contagem_cnefe`, e
  mesmas coordenadas. As duas saídas foram geradas a partir do **mesmo arquivo de
  input**.
