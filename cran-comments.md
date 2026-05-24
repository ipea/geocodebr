## R CMD check results

── R CMD check results ───────────────────────────────────────────── geocodebr 0.6.3 ────
Duration: 2m 39s

0 errors ✔ | 0 warnings ✔ | 0 notes ✔

- The following url works fine on the browser \url{https://www.ibge.gov.br/estatisticas/sociais/populacao/38734-cadastro-nacional-de-enderecos-para-fins-estatisticos.html}

# geocodebr v0.6.3

## Bug fixes

- Fixed a bug that now allows users to pass address tables containing only a 
subset of address fields as input. Municipality and state fields remain 
mandatory. Closes [#89](https://github.com/ipea/geocodebr/issues/89)
and [#94](https://github.com/ipea/geocodebr/issues/94)

## Minor changes

- The `geocode_reverso()` function achieved a small speed improvement, along 
with a substantial reduction in memory usage. In a sample of 1,000 points, 
memory consumption dropped from 161MB to 95MB.
