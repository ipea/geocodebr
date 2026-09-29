## R CMD check results

── R CMD check results ──────────────────────────────────────────────────────────────────────────────────── geocodebr 0.7.0 ────
Duration: 6m 41s

0 errors ✔ | 0 warnings ✔ | 0 notes ✔

obs.1 URL <www.ipea.gov.br> works fine on the browser.
obs.2 URL related to python has been removed


## Mudanças grandes (Major changes)

- Novo cache de dados ([v0.5.0](https://github.com/ipea/padronizacao_cnefe/releases/tag/v0.5.0)) 
com dados mais compactos. O tamanho do cache completo com todas tabelas caiu em 
aprox 18%. De 1.29 GB na V0.4.1 para 1.06 GB na v0.5.0.
- Esta versão do pacote geocodebr (e do data release) usa a nova versão do pacote 
enderecobr v0.6.1, que está mais rápido e mais abrangente.
- A função `geocode_reverso()` agora usa como referência de busca a tabela 
`municipio_logradouro_cep_localidade`, o que pemite captar mais casos onde não
há número no logradouro.
- Nos casos de resultado encontrado com número aproximado (interpolação — tipos
`da01` a `da04` e `pa01` a `pa03`), as colunas extras do output como `contagem_cnefe`,
`cod_setor` e `endereco_encontrado` podiam vir de um ponto arbitrário entre os usados
na interpolação, e podiam mudar entre chamadas idênticas de `geocode()` — inclusive as
coordenadas de casos de empate, que usam `contagem_cnefe` como critério de desempate.
Agora essas colunas sempre vêm do ponto com número mais próximo do buscado, e o
resultado é reprodutível entre chamadas. Como consequência, cerca de 1% dos endereços
geocodificados a partir de `da02`/`da04`/`pa02` podem retornar coordenadas ligeiramente
diferentes das versões anteriores do pacote.

## Mudanças pequenas (Minor changes)

- Otimização de diversas etapas da função `geocode()`, deixando a função com
menor uso de memória e aprox. 17% mais rápida em benchmarks com bases de dados 
de 10 e 43 milhões de endereços.
- A função `geocode()` agora pula, sem custo, as etapas internas de busca que 
dependem de um campo de endereço não declarado em `campos_endereco` (por exemplo, 
se input do usuário não possui as colunas `logradouro` e `numero`, o geocode agora
faz a busca só por CEP/bairro/município). Antes, essas etapas eram sempre executadas 
e materializavam a tabela de referência do CNEFE correspondente mesmo sabendo de 
antemão que nenhum resultado seria encontrado. Isso traz enorme ganho de performance
nesses casos. O resultado retornado não muda.
- A documentação da função `geocode()` agora descreve a etapa de resolução de 
empates entre candidatos separados por menos de 300 metros, que antes não estava 
documentada. Ver a seção "Lidando com casos de empate" em `?geocode`.
- A função `geocode()` agora baixa só as tabelas de referência do CNEFE que as 
etapas ativas do algoritmo de fato vão usar, em vez de baixar sempre as 8 tabelas 
disponíveis. No melhor caso (geocodificação só por CEP/bairro/município, sem 
logradouro/número), o volume baixado cai de ~1,5 GB para ~20 MB.
- A etapa interna de tratamento de empates de `geocode()` ficou mais eficiente: as 
janelas de cálculo agora rodam apenas sobre os casos efetivamente empatados, em vez 
de sobre o resultado inteiro (~2,4x mais rápida com `resolver_empates = TRUE`, ~5x 
com `FALSE`, medido em 1 milhão de endereços). O resultado retornado não muda.
- Com `resolver_empates = FALSE`, o output de `geocode()` agora inclui a coluna 
`empate` mesmo quando `resultado_completo = FALSE`. Antes, os casos empatados 
voltavam como linhas duplicadas sem nenhuma coluna que permitisse identificá-los 
(a mensagem de aviso instruía a inspecionar uma coluna que não estava no output).
- A função `geocode()` agora rejeita, com mensagem de erro, tabelas de input que 
já contenham colunas com nomes usados no output do próprio pacote (`lat`, `lon`, 
`precisao`, `tipo_resultado`, `desvio_metros`, `endereco_encontrado`, `empate`, 
`cod_setor`, as colunas `*_encontrado`/`*_encontrada` e `tempidgeocodebr`). Antes, 
esses casos passavam silenciosamente e o resultado ficava com colunas duplicadas 
de mesmo nome, o que fazia as etapas seguintes (como a criação de colunas H3) 
lerem a coluna errada. Se o seu input tiver alguma dessas colunas, renomeie-a 
antes de chamar a função.

## Correção de bugs (Bug fixes)

- Correção da estimativa da coluna `desvio_metros`, que pode causar alguma 
variação para cima ou para baixo em comparação às versões anteriores.
- As funções `geocode()`, `geocode_reverso()` e `busca_por_cep()` agora fecham a 
conexão com o banco DuckDB ao final da sua execução, inclusive quando são 
interrompidas por um erro no meio do caminho. Antes, uma interrupção deixava a 
conexão aberta e um arquivo temporário em disco, o que podia acumular recursos em 
usos repetidos ou dentro de laços.
- Bug corrigido na função `geocode_reverso()`, que agrupava os resultados por uma 
coluna `id` do input em vez de usar o seu identificador interno. Na prática, a função 
só funcionava quando a tabela de input tinha uma coluna chamada `id` com valores 
únicos. Agora o resultado independe das colunas presentes na tabela de input.
- Bug corrigido no argumento `h3_res` da função `busca_por_cep()`. Quando se passava 
um vetor com várias resoluções, a função criava as colunas com os nomes corretos mas 
preenchia todas elas com os índices de uma única resolução — a última do vetor.
Agora a função apresenta o comportamento esperado. Este é o  mesmo bug que havia 
sido corrigido na função `geocode()` na versão v0.6.4.
- Correção interna na etapa de resolução de empates da função `geocode()` nos casos
em que as coordenadas candidatas estão a menos de 300 metros entre si. Nessas 
situações, o pacote descartava o candidato com **maior** valor de `contagem_cnefe` e 
retornava o de menor, contrariando a regra de desempate documentada. Agora o 
candidato com maior `contagem_cnefe` é preservado.
- Correção interna na etapa de resolução de empates da função `geocode()`. A coluna
`logradouro_encontrado`, usada internamente para decidir como cada empate é resolvido, só
era preenchida quando o argumento `resultado_completo = TRUE`. Na prática, isso fazia com
que `resultado_completo` — que deveria controlar apenas quais colunas aparecem no
resultado — alterasse também as coordenadas devolvidas: no comportamento padrão, nenhum
empate era classificado como "perdido", e endereços com logradouros homônimos distantes
entre si recebiam a média ponderada das coordenadas dos candidatos, em vez das coordenadas
do candidato com maior `contagem_cnefe`. Agora a coluna é sempre repassada às etapas
internas, e as coordenadas devolvidas não dependem mais de `resultado_completo`. Na
amostra `large_sample.parquet` distribuída com o pacote, apenas 558 dos 20.028 (2.7%)
endereços eram afetados, com diferenças de até 26 km.
- Bug corrigido em função interna de limpeza automática do cache de dados do CNEFE. 
Quando a pasta de cache continha dados de um release antigo convivendo com os do 
release corrente, o pacote apagava a pasta de cache inteira — inclusive os dados 
correntes, que estavam íntegros —, forçando um novo download de todo o conjunto 
de dados. Agora apenas as pastas dos releases antigos são apagadas. Além disso,
uma pasta de release com nome fora do padrão esperado fazia a limpeza parar com o
erro `missing value where TRUE/FALSE needed`, o que interrompia qualquer chamada
a `geocode()`, `geocode_reverso()` ou `busca_por_cep()` com `cache = TRUE`. Esse
caso passa a ser tratado como release antigo.
- Bug corrigido no argumento `cache = FALSE` das funções `geocode()`,
`geocode_reverso()` e `busca_por_cep()`. Nesse modo, os dados do CNEFE são
baixados para um diretório temporário, mas as funções liam os dados da pasta de
cache persistente — isto é, de um lugar diferente daquele em que os dados haviam
acabado de ser gravados. Na prática, quem não tinha os dados em cache recebia o
erro `IO Error: No files found that match the pattern ...` depois de esperar o
download inteiro, e quem já tinha obtinha o resultado correto, mas lido do cache,
com o download recém-feito descartado. Agora a leitura usa a pasta devolvida por
`download_cnefe()`.
- Corrigido um erro em `geocode()` quando o pacote é carregado em modo de 
desenvolvimento (`devtools::load_all()`) ou quando há uma versão antiga instalada 
na biblioteca: o subprocesso usado internamente (via `callr`) carregava o geocodebr 
*instalado* em vez do da sessão, e a chamada falhava com 
`could not find function "geocode_core"`. Agora o subprocesso carrega o mesmo 
código da sessão e, em caso de divergência de versão, emite uma mensagem clara.
- Na resolução de empates (`resolver_empates = TRUE`), a exceção que protege ruas com
nome de data (e.g. "Rua Quinze de Novembro") de serem tratadas como logradouro ambíguo
nunca era aplicada, por um erro de escape de regex (`\\b` chegava ao motor como barra
literal). Com a correção, endereços dessas ruas com coordenadas candidatas a menos de
1 km entre si passam a ser resolvidos pela média ponderada (comportamento documentado),
em vez de descartar candidatos. A exceção vale apenas para o critério de nome ambíguo:
candidatos a mais de 1 km continuam sendo desempatados pelo caso mais provável. Afeta
~14 endereços por milhão (medido em amostra de 1M com alta incidência de empates).
- A lista interna de logradouros ambíguos (usada para excluir nomes genéricos do
match probabilístico e para o desempate) enumerava "Rua Um" a "Rua Treze" mas pulava
"Rua Quatro". A lacuna permitia, por exemplo, que "Rua Quatro" casasse por similaridade
com "Rua Quatorze" (Jaro 0,91, acima de todos os limiares do pacote). Endereços em
"Rua Quatro" sem match exato agora caem para categorias de menor precisão (CEP,
localidade ou município) em vez de arriscar um match probabilístico errado. Afeta
~26 endereços por milhão (medido na mesma amostra).


