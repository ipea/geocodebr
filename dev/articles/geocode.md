# Geocode

## Geolocalização: de endereços para coordenadas espaciais

A principal função do pacote {geocodebr} é a
[`geocode()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode.md),
que recebe uma tabela (`data.frame`) de endereços como entrada e retorna
a mesma tabela geolocalizada como saída. Para demonstrar essa função,
utilizamos no exemplo abaixo pequeno conjunto de dados que contém
endereços com problemas comuns, como informações ausentes e campos
digitados incorretamente.

A geolocalização desses dados com **{geocodebr}** pode ser feita em
apenas dois passos:

1.  O primeiro passo é usar a função
    [`definir_campos()`](https://ipeagit.github.io/geocodebr/dev/reference/definir_campos.md)
    para indicar os nomes das colunas no seu `data.frame` que
    correspondem a cada campo dos endereços. No exemplo abaixo, nós
    indicamos que coluna que contém a informação de logradouro se chama
    `"nm_logradouro"`, que a coluna de número se chama `"Numero"`, etc.

obs. Note que as colunas indicando o `"estado"` e `"município"` são
obrigatórias.

``` r

library(geocodebr)

# leitura de amostra de dados
ends <- read.csv(system.file("extdata/small_sample.csv", package = "geocodebr"))

# definição dos campos de endereço
campos <- definir_campos(
  estado = "nm_uf",
  municipio = "nm_municipio",
  logradouro = "nm_logradouro",
  numero = "Numero",
  cep = "Cep",
  localidade = "Bairro"
)
```

2.  O segundo passo é usar a função
    [`geocode()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode.md)
    para encontrar as coordenadas geográficas dos dados de input.

**Nota:** A função
[`geocode()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode.md)
requer que os dados do CNEFE estejam armazenados localmente. A primeita
vez que a função é executada, ela baixa os dados do CNEFE e salva em um
cache local na sua máquina. No total, esses dados somam cerca de 1.2 GB,
o que pode fazer com que a primeira execução da função demore. Esses
dados, no entanto, são salvos de forma persistente, logo eles são
baixados uma única vez. Mais informações sobre o cache de dados
[aqui](https://ipea.github.io/geocodebr/articles/geocodebr.html#cache-de-dados).

``` r

# geolicalização
ends_geo <- geocode(
  enderecos = ends, 
  campos_endereco = campos, 
  resultado_completo = FALSE,
  resolver_empates = TRUE,
  h3_res = 9,
  resultado_sf = FALSE,
  verboso = FALSE
  )

head(ends_geo)
#>   id            nm_logradouro Numero       Cep               Bairro
#> 1  1 Rua Maria Lucia Pacifico     17 26042-730           Santa Rita
#> 2  2      Rua Leopoldina Tome     46 25030-050           Centenario
#> 3  3          Rua Dona Judite      0 23915-700          Caputera II
#> 4  4     Rua Alexandre Amaral      0 23098-120           Santissimo
#> 5  5                Avenida E    300 23860-000         Praia Grande
#> 6  6      Rua Princesa Isabel    263           Estacao Experimental
#>      nm_municipio code_muni nm_uf        lat       lon   precisao
#> 1     Nova Iguacu   3303500    RJ -22.695509 -43.47116     numero
#> 2 Duque de Caxias   3301702    RJ -22.779174 -43.31132     numero
#> 3  Angra dos Reis   3300100    RJ -22.978800 -44.20846 logradouro
#> 4  Rio de Janeiro   3304557    RJ -22.869117 -43.51140 logradouro
#> 5     Mangaratiba   3302601    RJ -22.929864 -43.97214     numero
#> 6      Rio Branco   1200401    AC  -9.963438 -67.83559     numero
#>   tipo_resultado desvio_metros
#> 1           dn01             8
#> 2           dn01             6
#> 3           dl01            59
#> 4           dl01           300
#> 5           dn01             6
#> 6           dn03             6
#>                                                           endereco_encontrado
#> 1      RUA MARIA LUCIA PACIFICO, 17 - SANTA RITA, NOVA IGUACU - RJ, 26042-730
#> 2       RUA LEOPOLDINA TOME, 46 - CENTENARIO, DUQUE DE CAXIAS - RJ, 25030-050
#> 3               RUA DONA JUDITE - CAPUTERA II, ANGRA DOS REIS - RJ, 23915-700
#> 4           RUA ALEXANDRE AMARAL - SANTISSIMO, RIO DE JANEIRO - RJ, 23098-120
#> 5                  AVENIDA E, 300 - PRAIA GRANDE, MANGARATIBA - RJ, 23860-000
#> 6 RUA PRINCESA ISABEL, 263 - ESTACAO EXPERIMENTAL, RIO BRANCO - AC, 69921-026
#>             h3_09
#> 1 89a8a39850fffff
#> 2 89a8a06c55bffff
#> 3 89a8a1c190fffff
#> 4 89a8a066c47ffff
#> 5 89a8a026c77ffff
#> 6 898b5131e0fffff
```

Por padrão, a tabela de *output* é igual à tabela de input do usuário
acrescida de colunas com a latitude e longitude encontradas, bem como de
colunas indicando o nível de precisão dos resultados e o endereço
encontrado. Quando `resultado_completo = TRUE`, o output é acrescido de
algumas colunas extras discriminando separadamente cada componente do
endereço que teria sido encontrado.

Cabe também destacar aqui outros três argumentos da função
[`geocode()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode.md):

- `h3_res` : que permite o usuário inserir uma coluna no output
  indicando o id da célula H3 na resolução espacial desejada. Detalhes
  sobre as resoluções disponíveis em \code{;
- `resolver_empates`: serve para indicar se o usuário quer que a função
  resolva automaticamente casos de empate, i.e. casos que o endereço de
  input do usuário pode se referir a diferentes localidades na cidade
  (e.g. logradouros diferentes com mesmo nome mas em bairros distintos).
  Quando `TRUE`, a função resolve os empates selecioando os endereços
  com maior número de visitas do CNEFE. Quando `FALSE`, a função retorna
  todos os resultados indicando os casos empatados na coluna ‘empate’
  para que o usuário possa inspecionar cada caso coluna
  ‘endereco_encontrado’.
- `resultado_sf`: quando `TRUE`, o output é retornado como um objeto
  espacial de classe `sf` simple feature.

As coordendas espaciais do resultado usam o sistema de referência
SIRGAS2000 (EPSG 4674.), padrão adotado pelo IBGE em todo o Brasil.

## Processo de matching de endereços

As coordenadas incluídas no resultado da
[`geocode()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode.md)
são calculadas a partir da média das coordenadas dos endereços do CNEFE
que correspondem a cada um dos endereços de *input*. Esse cálculo é
feito em duas etapas, e retorna o ponto médio dos 95% pontos mais
próximos entre si, evitando eventual distorção por devido a poucos
pontos muito isolados.

A correspondência entre os endereços de entrada e os do CNEFE pode ser
feita com base em diferentes combinações de campos, impactando, assim,
na precisão do resultado retornado. No caso mais rigoroso, a função
encontra uma correspondência determinística para todos os campos do
endereço (estado, município, logradouro, número, CEP e localidade).
Pense, por exemplo, em um prédio com vários apartamentos, cuja única
variação no endereço se dá a nível de apartamento: o resultado, nesse
caso, é a média das coordenadas dos apartamentos, que podem diferir
ligeiramente.

Em um caso menos rigoroso, no qual são encontradas correspondências
apenas para os campos de estado, município, logradouro e localidade, a
função calcula as coordenadas médias de todos os endereços do CNEFE que
se encontram na mesma rua e na mesma localidade. O resultado, portanto,
é agregado a nível de rua, tendendo para a extremidade do logradouro com
maior concentração de endereços.

## Grau de precisão dos resultados

A precisão dos resultados do **{geocodebr}** são apresentadas em 3
colunas, `precisao`, `tipo_resultado` e `desvio_metros`, explicadas
abaixo.

### Precisão

A coluna `precisao` se refere ao nível de agregação das coordenadas do
CNEFE utilizadas no processo de geolicalização. A função
[`geocode()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode.md)
sempre retorna o resultado de maior precisão possível - ou seja, ela só
vai procurar endereços com precisão `"numero_aproximado"` (ver a seguir)
caso não tenha encontrado correspondência de precisão `"numero"`. As
coordenadas calculadas podem ser classificadas em seis diferentes
categorias de precisão:

1.  `"numero"` - calculadas a partir de endereços que compartilham o
    mesmo logradouro e número;
2.  `"numero_aproximado"` - calculadas a partir de endereços que
    compartilham o mesmo logradouro, mas número de *input* não encontra
    correspondência exata no CNEFE e sua localização é calculada a
    partir de uma interpolação espacial;
3.  `"logradouro"` - calculadas a partir de endereços que compartilham o
    mesmo logradouro (número de *input* está ausente ou é S/N);
4.  `"cep"` - calculadas a partir de endereços que compartilham o mesmo
    CEP;
5.  `"localidade"` - calculadas a partir de endereços que compartilham a
    mesma localidade;
6.  `"municipio"` - calculadas a partir de endereços que compartilham o
    mesmo município.

### Tipos de resultados

A coluna `tipo_resultado` fornece informações mais detalhadas sobre os
campos de endereço utilizados no cálculo das coordenadas de cada
endereço de entrada. Cada categoria é nomeada a partir de um código de
quatro caracteres:

- o primeiro, sempre `d` ou `p`, determina se a correspondência foi
  feita de forma determinística (`d`) ou probabilística (`p`);
- o segundo faz menção à categoria de `precisao` na qual o resultado foi
  classificado (`n` para `"numero"`, `a` para `"numero_aproximado"`, `l`
  para `"logradouro"`, `c` para `"cep"`, `b` para `"localidade"` e `m`
  para `"municipio"`);
- o terceiro e o quarto designam a classificação de cada categoria
  dentro de seu grupo - via de regra, quanto menor o número formado por
  esses caracteres, mais precisa são as coordenadas calculadas.

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
  ‘S/N’)
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

### Desvio em metros

A coluna `desvio_metros` apresenta uma forma intuitiva e prática de
saber o grau de incerteza do resultado encontrado. Essa coluna informa
que pelo menos 95% de todos os pontos do CNEFE que possuem
corrêspondência com o endereço de input estão num raio de x metros da
localização encontrada.

Um desvio de `30` metros, por exemplo, tende a representar um resultado
muito confiável. A depender de como o dado geolocalizado será utilizado,
até mesmos resultados com um `desvio_metros` de até 500 ou 900 metros
podem ser ser aceitáveis.

A coluna `desvio_metros` pode ser particularmente útil para decidir por
exemplo se um resultado encontrado com a `precisao` de CEP deveria ser
aceitável. Muitas cidades do Brasil possuem um CEP único, o que tende a
gerar resultados com altíssimo grau de incerteza. Em várias cidades, no
entanto, um CEP pode ser circunscrito a uma área muito pequena e as
vezes até um único edifício. Nesses casos, o valor do `desvio_metros`
tende a ser bem pequeno.

## Código do setor censitário

- Quando o usuário passa o argumento `resultado_completo = TRUE`, a
  função
  [`geocode()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode.md)
  também retorna a coluna `cod_setor` com o código do setor censitário
  do endereço encontrado. Atualmente, a função somente retorna o código
  do setor dos casos em que todos os pontos do CNEFE correspondentes
  estão 100% dentro de um único setor censitário. Quando os dados do
  CNEFE correspondentes ao endereço buscado estão em mais de um setor, o
  resultado da coluna `cod_setor` é `NA`.
