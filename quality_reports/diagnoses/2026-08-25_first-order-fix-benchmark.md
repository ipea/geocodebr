# Item #3 fechado: `ORDER BY` nos `FIRST()` de `da0x`/`pa0x` + achado extra em `trata_empates` — 2026-08-25

**Resultado: as três mudanças foram aplicadas e o não-determinismo foi fechado.** `geocode()` agora devolve
resultado idêntico entre chamadas repetidas com o mesmo input — confirmado em 3 rodadas consecutivas
(0/20.028 linhas divergentes em cada uma).

---

## Mudança 1 — `FIRST(... ORDER BY ...)` em `match_weighted_cases.R` / `match_weighted_cases_probabilistic.R`

Escopo e decisão de semântica já discutidos com o usuário (ver conversa da sessão): `contagem_cnefe` e as
demais colunas descritivas agregadas por `FIRST()` no `GROUP BY tempidgeocodebr, endereco_encontrado`
passam a vir do candidato **mais próximo do número buscado** (`ORDER BY ABS(numero - numero_cnefe),
numero_cnefe, lat, lon`), em vez de um candidato arbitrário do grupo. `lat`/`lon` em si já eram
determinísticos (média ponderada via `SUM`), não mudam de fórmula.

**Efeito medido** (20.028 endereços, cenário completo, duas chamadas idênticas a `geocode_core()`,
`n_cores = 7`, antes de qualquer outra mudança): divergência caiu de "algumas linhas em `lat`/`lon`" (o
sintoma original do item #3, confirmado em `2026-08-24_temp-view-benchmark.md`) para **0 linhas com `lat`
diferente** — o objetivo do item foi alcançado. Restaram 5 linhas divergentes só em colunas descritivas
(`desvio_metros`, `cod_setor`, `endereco_encontrado`) — ver Mudança 2.

## Mudança 2 (achado novo, fora do escopo original do item #3) — `QUALIFY` em `trata_empates_geocode_duckdb.R`

Investigando por que a reprodutibilidade não fechou 100% depois da Mudança 1, achei uma **segunda fonte de
não-determinismo**, não documentada em nenhum relatório anterior: dois `QUALIFY ROW_NUMBER() OVER
(PARTITION BY tempidgeocodebr ORDER BY contagem_cnefe DESC) = 1` (nos ramos "empatados perdidos" e
"empatados salváveis") tinham só `contagem_cnefe DESC` como critério — sem desempate quando `contagem_cnefe`
empata entre candidatos (comum: muitos candidatos têm `contagem_cnefe = 1`).

- No ramo **"salváveis"**: `lat`/`lon` já vêm de média ponderada determinística; só as colunas descritivas
  (`cod_setor`, `desvio_metros`, `endereco_encontrado`) ficavam arbitrárias.
- No ramo **"perdidos"**: a linha inteira sobrevive via `QUALIFY`, então um empate ali pode trocar a
  **coordenada** devolvida, não só metadado — observado uma vez nas medições abaixo.

**Fix aplicado em duas rodadas.** Primeiro, por instrução explícita do usuário: `ORDER BY contagem_cnefe
DESC, desvio_metros` — reduziu a divergência (5 → 2-3 de 20.028 nas medições), mas não fechou por completo,
porque `desvio_metros` (atributo do registro CNEFE, não uma distância calculada por consulta) ainda podia
empatar entre candidatos genuinamente diferentes. Em seguida, o usuário acrescentou `endereco_encontrado`
como terceiro critério — `ORDER BY contagem_cnefe DESC, desvio_metros, endereco_encontrado` — e isso fechou
o não-determinismo por completo nas medições desta sessão (ver abaixo).

## Medição — reprodutibilidade entre duas chamadas idênticas (`n_cores = 7`, 20.028 endereços)

| estado do código | linhas divergentes | linhas com `lat` diferente |
|---|---|---|
| antes de qualquer mudança (item #3 original) | algumas em `lat`/`lon` (ver `2026-08-24_temp-view-benchmark.md`) | > 0 |
| só Mudança 1 (`FIRST() ORDER BY` distância) | 5 de 20.028 | **0** |
| + `QUALIFY ..., desvio_metros` | 2–3 de 20.028 (3 rodadas: 2, 2, 3) | 0 em 3 das 4 rodadas; 3 numa rodada (ramo "perdidos") |
| + `QUALIFY ..., desvio_metros, endereco_encontrado` | **0 de 20.028** (3 rodadas consecutivas) | **0** |

**`ORDER BY contagem_cnefe DESC, desvio_metros, endereco_encontrado` fechou o não-determinismo** nas
medições desta sessão: 3 rodadas de "duas chamadas idênticas" seguidas, 0 linhas divergentes em cada uma
(antes eram 2-3 por rodada, só com `desvio_metros`). O padrão dos casos que sobravam (`da02`/`da04`,
`contagem_cnefe` e `desvio_metros` empatados) sugere que `endereco_encontrado` — a string final já com o
número do input substituído — raramente se repete entre candidatos genuinamente diferentes, então serviu
como desempate quase sempre decisivo. Não há garantia formal de que `endereco_encontrado` nunca empata
(duas ruas homônimas na mesma família de match_type, mesmo `contagem_cnefe`, mesmo `desvio_metros`, ainda
poderiam colidir em teoria), mas não foi observado em nenhuma das medições — se algum dia reaparecer,
`cod_setor` é o próximo candidato natural a desempate.

## Corretude / desempenho

- `devtools::test()`: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 257 ]`, rodado depois de cada rodada de mudanças
  (incluindo a final, com `endereco_encontrado` no desempate).
- Tempo: `geocode_core()` mediana 4,99s→5,51s no cenário completo (dentro do ruído observado nas outras
  medições desta semana no mesmo hardware — sem indício de regressão).
- `nrow`/`NA lat` inalterados (20.028 / 0) em todas as rodadas.

## NEWS.md

Entrada em "Mudanças grandes" (não "pequenas" — muda coordenadas retornadas em ~1% dos casos vindos de
interpolação, redação sugerida pelo usuário): ver `NEWS.md`, seção do dev version.

## Referências

- `quality_reports/diagnoses/2026-08-24_geocode-eficiencia-consolidado.md` — item #3 na lista priorizada.
- `quality_reports/diagnoses/2026-08-23_analise-pacote-desempenho-manutencao.md` §4 — medição original do
  patch de `FIRST() ORDER BY` (a4b8036, não estava na árvore).
- `tests/tests_rafa/benchmark_first_order.R` — script de benchmark (reprodutibilidade + corretude + tempo).
