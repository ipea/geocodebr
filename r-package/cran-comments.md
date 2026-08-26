## R CMD check results

── R CMD check results ──────────────────────────────────────────────────────────────────────────────────────────────────────── geocodebr 0.6.4 ────
Duration: 3m 40s

0 errors ✔ | 0 warnings ✔ | 0 notes ✔
> 
- The following url works fine on the browser \url{https://www.ibge.gov.br/estatisticas/sociais/populacao/38734-cadastro-nacional-de-enderecos-para-fins-estatisticos.html}

# geocodebr v0.6.4

## Correção de bugs (Bug fixes)

* Fixed a bug in the `h3_res` argument of the `geocode()` function. The function 
was overwriting columns when a vector containing multiple `h3_res` resolutions 
was provided. The function now behaves as expected.
