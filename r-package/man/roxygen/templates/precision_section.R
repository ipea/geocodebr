#' @details Precisão dos resultados:
#'
#' A precisão dos resultados do **{geocodebr}** são apresentadas em 3 colunas,
#' `precisao`, `tipo_resultado` e `desvio_metros`, explicadas abaixo.
#'
#' # Precisão
#'
#' Os resultados são classificados em seis amplas categorias de `precisao`:
#'
#' 1. "numero"
#' 2. "numero_aproximado"
#' 3. "logradouro"
#' 4. "cep"
#' 5. "localidade"
#' 6. "municipio"
#'
#' Cada nível de precisão pode ser desagregado em tipos de resultado mais
#' refinados.
#'
#' # Tipos de resultados
#'
#' A coluna `tipo_resultado` fornece informações mais detalhadas sobre como
#' exatamente cada endereço de entrada foi encontrado no CNEFE. Em cada
#' categoria,  o **{geocodebr}** calcula a média da latitude e longitude dos
#' endereços incluídos no CNEFE que correspondem ao endereço de entrada, com
#' base em combinações de diferentes campos. No caso mais rigoroso, por exemplo,
#' a função encontra uma correspondência determinística para todos os campos de
#' um dado endereço (`"estado"`, `"municipio"`, `"logradouro"`, `"numero"`,
#' `"cep"`, `"localidade"`). Pense, por exemplo, em um prédio com vários
#' apartamentos que correspondem ao mesmo endereço de rua e número. Nesse caso,
#' as coordenadas dos apartamentos podem diferir ligeiramente, e o
#' **{geocodebr}** calcula a média dessas coordenadas. Em um caso menos rigoroso,
#' no qual apenas os campos (`"estado"`, `"municipio"`, `"logradouro"`,
#' `"localidade"`) são encontrados, o **{geocodebr}** calcula as coordenadas
#' médias de todos os endereços no CNEFE ao longo daquela rua e que se encontram
#' na mesma localidade/bairro. Assim, as coordenadas de resultado tendem a ser o
#' ponto médio do trecho daquela rua que passa dentro daquela localidade/bairro.
#'
#' A coluna `tipo_resultado` fornece informações mais detalhadas sobre os campos de
#' endereço utilizados no cálculo das coordenadas de cada endereço de entrada. Cada
#' categoria é nomeada a partir de um código de quatro caracteres:
#'
#' - o primeiro caracter, sempre `d` ou `p`, determina se a correspondência foi
#' feita de forma determinística (`d`) ou probabilística (`p`);
#' - o segundo faz menção à categoria de `precisao` na qual o resultado foi
#' classificado (`n` para `"numero"`, `a` para `"numero_aproximado"`, `r` para
#' `"logradouro"`, `c` para `"cep"`, `b` para `"localidade"` e `m` para `"municipio"`);
#' - o terceiro e o quarto caracteres designam a classificação de cada categoria
#' dentro de seu grupo - via de regra, quanto menor o número formado por esses
#' caracteres, mais precisa são as coordenadas calculadas.
#'
#' As categorias de `tipo_resultado` são listadas abaixo, junto às categorias de
#' `precisao` a qual elas estão associadas:
#'
#' - precisao `"numero"`
#'   - `dn01` - logradouro, numero, cep e localidade
#'   - `dn02` - logradouro, numero e cep
#'   - `dn03` - logradouro, numero e localidade
#'   - `dn04` - logradouro e numero
#'   - `pn01` - logradouro, numero, cep e localidade
#'   - `pn02` - logradouro, numero e cep
#'   - `pn03` - logradouro, numero e localidade
#'   - `pn04` - logradouro e numero
#'
#' - precisao `"numero_aproximado"`
#'   - `da01` - logradouro, numero, cep e localidade
#'   - `da02` - logradouro, numero e cep
#'   - `da03` - logradouro, numero e localidade
#'   - `da04` - logradouro e numero
#'   - `pa01` - logradouro, numero, cep e localidade
#'   - `pa02` - logradouro, numero e cep
#'   - `pa03` - logradouro, numero e localidade
#'   - `pa04` - logradouro e numero
#'
#' - precisao `"logradouro"` (quando o número de entrada está faltando 'S/N')
#'   - `dl01` - logradouro, cep e localidade
#'   - `dl02` - logradouro e cep
#'   - `dl03` - logradouro e localidade
#'   - `dl04` - logradouro
#'   - `pl01` - logradouro, cep e localidade
#'   - `pl02` - logradouro e cep
#'   - `pl03` - logradouro e localidade
#'   - `pl04` - logradouro
#'
#' - precisao `"cep"`
#'   - `dc01` - municipio, cep, localidade
#'   - `dc02` - municipio, cep
#'
#' - precisao `"localidade"`
#'   - `db01` - municipio, localidade
#'
#' - precisao `"municipio"`
#'   - `dm01` - municipio
#'
#' Endereços não encontrados são retornados com latitude, longitude, precisão e
#' tipo de resultado `NA`.
#'
#' # Desvio em metros
#'
#' A coluna `desvio_metros` apresenta uma forma intuitiva e prática de saber o
#' grau de incerteza do resultado encontrado. Essa coluna informa que pelo menos
#' 95% de todos os pontos do CNEFE que possuem corrêspondência com o endereço de
#' input estão num raio de `x` metros da localização encontrada.
#'
#' Um desvio de até `30` metros, por exemplo, tende a representar um resultado
#' muito confiável. A depender de como o dado geolocalizado será utilizado, até
#' mesmos resultados com `desvio_metros` de até 500 ou 900 metros podem ser ser
#' aceitáveis.
#'
#' A coluna `desvio_metros` é particularmente útil para decidir por exemplo se
#' um resultado encontrado com a `precisao` de CEP, localidade ou logradouro
#' deveria ser aceitável. Por exemplo, muitas cidades do Brasil possuem um CEP
#' único, o que tende a gerar resultados com alto grau de incerteza. Em várias
#' cidades, no entanto, um CEP pode ser circunscrito a uma área muito pequena e
#' as vezes até um único edifício. Nesses casos, o valor do `desvio_metros`
#' tende a ser bem pequeno.
#'
#' # Busca probabilistica
#'
#' Os tipos de resultado com busca probabilitisca usam como base o algoritmo de
#' semelhança de Jaro para comparar as strings de 'logradouro' dos dados de
#' input e da base de endereços do geocodebr. O pacote considera como match o
#' logradouro da base de endereços que apresenta a maior semelhança de Jaro
#' condicionado a uma semelhança mínima, e desde que também haja match
#' determinístico em ao menos um dos campos "cep" e "localidade".
#' O geocodebr utiliza uma semelhança mínima de `0.85` nos casos de match
#' probabilistico, e de `0.90` nos demais casos.
#'
#' # Código do setor censitário
#'
#' Quando o usuário passa o argumento `resultado_completo = TRUE`, a função
#' `geocode()` também retorna a coluna `cod_setor` com o código do setor
#' censitário do endereço encontrado. Atualmente, a função somente retorna o
#' código do setor dos casos em que todos os pontos do CNEFE correspondentes estão
#' 100% dentro de um único setor censitário. Quando os dados do CNEFE
#' correspondentes ao endereço buscado estão em mais de um setor, o resultado da
#' coluna `cod_setor` é `NA`.
