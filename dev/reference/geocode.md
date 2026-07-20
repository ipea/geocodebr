# Geolocaliza endereços no Brasil

Geocodifica endereços brasileiros com base nos dados do CNEFE. Os
endereços de input devem ser passados como um `data.frame`, no qual cada
coluna descreve um campo do endereço (logradouro, número, cep, etc). Os
resuldos dos endereços geolocalizados podem seguir diferentes níveis de
precisão. Consulte abaixo a seção "Detalhes" para mais informações. As
coordenadas de output utilizam o sistema de coordenadas geográficas
SIRGAS 2000, EPSG 4674.

## Uso

``` r
geocode(
  enderecos,
  campos_endereco = definir_campos(),
  resultado_completo = FALSE,
  resolver_empates = TRUE,
  resultado_sf = FALSE,
  h3_res = NULL,
  padronizar_enderecos = TRUE,
  verboso = TRUE,
  cache = TRUE,
  n_cores = NULL
)
```

## Argumentos

- enderecos:

  Um `data.frame`. Os endereços a serem geolocalizados. Cada coluna deve
  representar um campo do endereço.

- campos_endereco:

  Um vetor de caracteres. A correspondência entre cada campo de endereço
  e o nome da coluna que o descreve na tabela `enderecos`. A função
  [`definir_campos()`](https://ipeagit.github.io/geocodebr/dev/reference/definir_campos.md)
  auxilia na criação deste vetor e realiza algumas verificações nos
  dados de entrada. Campos de endereço passados como `NULL` serão
  ignorados, e a função deve receber pelo menos um campo não nulo, além
  dos campos `"estado"` e `"municipio"`, que são obrigatórios. Note que
  o campo `"localidade"` é equivalente a 'bairro'.

- resultado_completo:

  Lógico. Indica se o output deve incluir colunas adicionais, como o
  endereço encontrado de referência. Por padrão, é `FALSE`.

- resolver_empates:

  Lógico. Alguns resultados da geolocalização podem indicar diferentes
  coordenadas possíveis (e.g. duas ruas diferentes com o mesmo nome em
  uma mesma cidade). Esses casos são trados como 'empate' e o parâmetro
  `resolver_empates` indica se a função deve resolver esses empates
  automaticamente. Por padrão, é `TRUE`, e a função retorna apenas o
  caso mais provável. Para mais detalhes sobre como é feito o processo
  de desempate, consulte abaixo a seção "Detalhes".

- resultado_sf:

  Lógico. Indica se o resultado deve ser um objeto espacial da classe
  `sf`. Por padrão, é `FALSE`, e o resultado é um `data.frame` com as
  colunas `lat` e `lon`.

- h3_res:

  Um número que indica a resolução espacial da célula hexagonal H3 da
  localização dos pontos retornados. Também aceita um vetor de números,
  e.g. `c(8, 9)` Por padrão, é `NULL`. Detalhes sobre as resoluções
  disponíveis em <https://h3geo.org/docs/core-library/restable/>

- padronizar_enderecos:

  Lógico. Indica se os dados de endereço de entrada devem ser
  padronizados. Por padrão, é `TRUE`. Essa padronização é essencial para
  uma geolocalizaçao correta. Alerta! Apenas utilize
  `padronizar_enderecos = FALSE` caso os dados de input já tenham sido
  padronizados anteriormente com
  `enderecobr::padronizar_enderecos(..., formato_estados = 'sigla', formato_numeros = 'integer')`.

- verboso:

  Um valor lógico. Indica se barras de progresso e mensagens devem ser
  exibidas durante o download dos dados do CNEFE e a geocodificação dos
  endereços. O padrão é `TRUE`.

- cache:

  Um valor lógico. Indica se os dados do CNEFE devem ser salvos ou lidos
  do cache, reduzindo o tempo de processamento em chamadas futuras. O
  padrão é `TRUE`. Quando `FALSE`, os dados do CNEFE são baixados para
  um diretório temporário.

- n_cores:

  Um número. O número de núcleos de CPU a serem utilizados no
  processamento dos dados. Por padrão, `n_cores = NULL` e o pacote
  utiliza o número máximo de cores físicos disponíveis.

## Valor

Retorna o `data.frame` de input `enderecos` adicionado das colunas de
latitude (`lat`) e longitude (`lon`), bem como as colunas (`precisao` e
`tipo_resultado`) que indicam o nível de precisão e o tipo de resultado.
Alternativamente, o resultado pode ser um objeto `sf`.

## Detalhes

Precisão dos resultados:

A precisão dos resultados do **geocodebr** são apresentadas em 3
colunas, `precisao`, `tipo_resultado` e `desvio_metros`, explicadas
abaixo.

Lidando com casos de empate:

No processo de geolocalização de dados, é possível que para alguns
endereços de input sejam encontrados diferentes coordenadas possíveis
(e.g. duas ruas diferentes com o mesmo nome, mas em bairros distintos em
uma mesma cidade). Esses casos são trados como empate'. Quando a função
`geocode()` recebe o o parâmetro `resolver_empates = TRUE`, os casos de
empate são resolvidos automaticamente pela função. A solução destes
empates é feita da seguinte maneira:

1.  Quando se encontra diferente coordenadas possíveis para um mesmo
    endereço de input, nós assumimos que essas coordendas pertencem
    provavelmente a endereços diferentes se (a) estas coordenadas estão
    a mais de 1Km entre si, ou (b) estão associadas a um logradouro
    'ambíguo', i.e. que costumam se repetir em muitos bairros (e.g. "RUA
    A", "RUA QUATRO", "RUA 10", etc). Nestes casos, a solução de
    desempate é retornar o ponto com maior número de estabelecimentos no
    CNEFE, valor indicado na coluna `"contagem_cnefe"`.

2.  Quando as coordenadas possivelmente associadas a um endereço estão a
    menos de 1Km entre si e não se trata de um logradouro 'ambíguo', nós
    assumimos que os pontos pertencem provavelmente ao mesmo logradouro
    (e.g. diferentes CEPs ao longo de uma mesma rua). Nestes casos, a
    solução de desempate é retornar um ponto que resulta da média das
    coordenadas dos pontos possíveis ponderada pelo valor de
    `"contagem_cnefe"`. Nesse caso, a coluna de output
    `"endereco_encontrado"` recebe valor do ponto com maior
    `"contagem_cnefe"`.

## Precisão

Os resultados são classificados em seis amplas categorias de `precisao`:

1.  "numero"

2.  "numero_aproximado"

3.  "logradouro"

4.  "cep"

5.  "localidade"

6.  "municipio"

Cada nível de precisão pode ser desagregado em tipos de resultado mais
refinados.

## Tipos de resultados

A coluna `tipo_resultado` fornece informações mais detalhadas sobre como
exatamente cada endereço de entrada foi encontrado no CNEFE. Em cada
categoria, o **geocodebr** calcula a média da latitude e longitude dos
endereços incluídos no CNEFE que correspondem ao endereço de entrada,
com base em combinações de diferentes campos. No caso mais rigoroso, por
exemplo, a função encontra uma correspondência determinística para todos
os campos de um dado endereço (`"estado"`, `"municipio"`,
`"logradouro"`, `"numero"`, `"cep"`, `"localidade"`). Pense, por
exemplo, em um prédio com vários apartamentos que correspondem ao mesmo
endereço de rua e número. Nesse caso, as coordenadas dos apartamentos
podem diferir ligeiramente, e o **geocodebr** calcula a média dessas
coordenadas. Em um caso menos rigoroso, no qual apenas os campos
(`"estado"`, `"municipio"`, `"logradouro"`, `"localidade"`) são
encontrados, o **geocodebr** calcula as coordenadas médias de todos os
endereços no CNEFE ao longo daquela rua e que se encontram na mesma
localidade/bairro. Assim, as coordenadas de resultado tendem a ser o
ponto médio do trecho daquela rua que passa dentro daquela
localidade/bairro.

A coluna `tipo_resultado` fornece informações mais detalhadas sobre os
campos de endereço utilizados no cálculo das coordenadas de cada
endereço de entrada. Cada categoria é nomeada a partir de um código de
quatro caracteres:

- o primeiro caracter, sempre `d` ou `p`, determina se a correspondência
  foi feita de forma determinística (`d`) ou probabilística (`p`);

- o segundo faz menção à categoria de `precisao` na qual o resultado foi
  classificado (`n` para `"numero"`, `a` para `"numero_aproximado"`, `r`
  para `"logradouro"`, `c` para `"cep"`, `b` para `"localidade"` e `m`
  para `"municipio"`);

- o terceiro e o quarto caracteres designam a classificação de cada
  categoria dentro de seu grupo - via de regra, quanto menor o número
  formado por esses caracteres, mais precisa são as coordenadas
  calculadas.

As categorias de `tipo_resultado` são listadas abaixo, junto às
categorias de `precisao` a qual elas estão associadas:

- precisao `"numero"`

  - `dn01` - logradouro, numero, cep e localidade

  - `dn02` - logradouro, numero e cep

  - `dn03` - logradouro, numero e localidade

  - `dn04` - logradouro e numero

  - `pn01` - logradouro, numero, cep e localidade

  - `pn02` - logradouro, numero e cep

  - `pn03` - logradouro, numero e localidade

  - `pn04` - logradouro e numero

- precisao `"numero_aproximado"`

  - `da01` - logradouro, numero, cep e localidade

  - `da02` - logradouro, numero e cep

  - `da03` - logradouro, numero e localidade

  - `da04` - logradouro e numero

  - `pa01` - logradouro, numero, cep e localidade

  - `pa02` - logradouro, numero e cep

  - `pa03` - logradouro, numero e localidade

  - `pa04` - logradouro e numero

- precisao `"logradouro"` (quando o número de entrada está faltando
  'S/N')

  - `dl01` - logradouro, cep e localidade

  - `dl02` - logradouro e cep

  - `dl03` - logradouro e localidade

  - `dl04` - logradouro

  - `pl01` - logradouro, cep e localidade

  - `pl02` - logradouro e cep

  - `pl03` - logradouro e localidade

  - `pl04` - logradouro

- precisao `"cep"`

  - `dc01` - municipio, cep, localidade

  - `dc02` - municipio, cep

- precisao `"localidade"`

  - `db01` - municipio, localidade

- precisao `"municipio"`

  - `dm01` - municipio

Endereços não encontrados são retornados com latitude, longitude,
precisão e tipo de resultado `NA`.

## Desvio em metros

A coluna `desvio_metros` apresenta uma forma intuitiva e prática de
saber o grau de incerteza do resultado encontrado. Essa coluna informa
que pelo menos 95% de todos os pontos do CNEFE que possuem
corrêspondência com o endereço de input estão num raio de `x` metros da
localização encontrada.

Um desvio de até `30` metros, por exemplo, tende a representar um
resultado muito confiável. A depender de como o dado geolocalizado será
utilizado, até mesmos resultados com `desvio_metros` de até 500 ou 900
metros podem ser ser aceitáveis.

A coluna `desvio_metros` é particularmente útil para decidir por exemplo
se um resultado encontrado com a `precisao` de CEP, localidade ou
logradouro deveria ser aceitável. Por exemplo, muitas cidades do Brasil
possuem um CEP único, o que tende a gerar resultados com alto grau de
incerteza. Em várias cidades, no entanto, um CEP pode ser circunscrito a
uma área muito pequena e as vezes até um único edifício. Nesses casos, o
valor do `desvio_metros` tende a ser bem pequeno.

## Busca probabilistica

Os tipos de resultado com busca probabilitisca usam como base o
algoritmo de semelhança de Jaro para comparar as strings de 'logradouro'
dos dados de input e da base de endereços do geocodebr. O pacote
considera como match o logradouro da base de endereços que apresenta a
maior semelhança de Jaro condicionado a uma semelhança mínima, e desde
que também haja match determinístico em ao menos um dos campos "cep" e
"localidade". O geocodebr utiliza uma semelhança mínima de `0.85` nos
casos de match probabilistico, e de `0.90` nos demais casos.

## Código do setor censitário

Quando o usuário passa o argumento `resultado_completo = TRUE`, a função
`geocode()` também retorna a coluna `cod_setor` com o código do setor
censitário do endereço encontrado. Atualmente, a função somente retorna
o código do setor dos casos em que todos os pontos do CNEFE
correspondentes estão 100% dentro de um único setor censitário. Quando
os dados do CNEFE correspondentes ao endereço buscado estão em mais de
um setor, o resultado da coluna `cod_setor` é `NA`.

## Exemplos

``` r
library(geocodebr)

# ler amostra de dados
data_path <- system.file("extdata/small_sample.csv", package = "geocodebr")
input_df <- read.csv(data_path)[1:2,]

fields <- geocodebr::definir_campos(
  logradouro = "nm_logradouro",
  numero = "Numero",
  cep = "Cep",
  localidade = "Bairro",
  municipio = "nm_municipio",
  estado = "nm_uf"
)

df <- geocodebr::geocode(
  enderecos = input_df,
  campos_endereco = fields,
  resolver_empates = TRUE
  )
#> ℹ Padronizando endereços de entrada
#> ℹ Utilizando dados do CNEFE armazenados localmente
#> duckdb is keeping downloaded extensions in a temporary directory:
#> ℹ /tmp/RtmpM4IjxA/duckdb/extensions
#> This is removed when the R session ends, so extensions are re-downloaded each session.
#> ℹ To keep them, point `options(duckdb.extension_directory =)` or the `DUCKDB_EXTENSION_DIRECTORY` environment variable at a permanent path.
#> ℹ Geolocalizando endereços
#>  Casos processados: 0/2 ■                                  0% - dn01 
#>  Casos processados: 2/2 ■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■  100% - Fim! 
#> 
#> ℹ Preparando resultados
#> 

head(df)
#>   id            nm_logradouro Numero       Cep     Bairro    nm_municipio
#> 1  1 Rua Maria Lucia Pacifico     17 26042-730 Santa Rita     Nova Iguacu
#> 2  2      Rua Leopoldina Tome     46 25030-050 Centenario Duque de Caxias
#>   code_muni nm_uf       lat       lon precisao tipo_resultado desvio_metros
#> 1   3303500    RJ -22.69551 -43.47116   numero           dn01             8
#> 2   3301702    RJ -22.77917 -43.31132   numero           dn01             6
#>                                                      endereco_encontrado
#> 1 RUA MARIA LUCIA PACIFICO, 17 - SANTA RITA, NOVA IGUACU - RJ, 26042-730
#> 2  RUA LEOPOLDINA TOME, 46 - CENTENARIO, DUQUE DE CAXIAS - RJ, 25030-050
```
