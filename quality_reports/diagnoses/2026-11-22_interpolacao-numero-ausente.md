# Interpolação de número ausente — geocodebr × Geocenarios × alternativas (lição 3)

**22/11/2026** · geocodebr dev 0.6.4.900, CNEFE `v0.5.0` · plano `quality_reports/plans/2026-11-22_interpolacao-numero-ausente.md`
· scripts e saídas `quality_reports/comparisons/2026-11-22_interpolacao/` · issues [ipea/padronizacao_cnefe#10](https://github.com/ipea/padronizacao_cnefe/issues/10)
e [ipeaGIT/geocodebr#36](https://github.com/ipeaGIT/geocodebr/issues/36) (expoente no IDW; W3/W5 acrescentados na mesma data)

**Precisão = distância (haversine) entre a coordenada estimada e a coordenada verdadeira, no CNEFE, do
número suprimido.** Todos os rankings abaixo usam só essa medida.

## Resumo

1. **O método atual (B0) é o pior em quase tudo.** Para números internos da rua, ele mede a média
   `1/|Δn|` sobre todos os números da rua.
   - Erro mediano: 34 m com 1 número suprimido (P1) e 58 m com ±10 suprimidos (P2).
   - Nas pontas da rua, 83 e 114 m.
   - Nas ruas curvas, a estimativa cai **dentro da curva**: fica a 14–18 m do eixo, contra 4–8 m dos
     métodos por vizinhos. É o fenômeno da issue #10.
2. **O vizinho mais próximo (B1, Geocenarios) já corta o erro pela metade:** 18,5 / 31,5 m.
3. **Recomendado: M1 sem trava.** É a interpolação linear entre o número inferior e o superior **do mesmo
   lado da rua** (paridade). Sem par do mesmo lado, usa qualquer lado; na ponta da rua, usa o vizinho
   mais próximo.
   - Erro mediano: 13,8 / 23,2 m.
   - Ganho sobre o B0: −20 / −35 m (IC95% por rua: [−21,0; −19,6] e [−35,8; −33,5]).
   - Ganho sobre o B1: −4,8 / −8,3 m.
   - O ganho vale em todas as formas de rua, inclusive as curvas.
4. **Custo de tempo pequeno:** no `geocode()` ponta a ponta a diferença entre os métodos fica dentro
   do ruído entre rodadas (≤ 1 s em 20 mil e 200 mil endereços). Na etapa isolada, com 10 M de
   entradas, o M1n leva 80 s contra 18 s do B0.
5. **O B0 com expoente (issue #36) é a alternativa de mudança mínima.** Trocar `1/|Δn|` por
   `1/|Δn|³` (W3) ou `1/|Δn|⁵` (W5) é uma linha de SQL e custa quase o mesmo que o B0 (21–23 s contra
   18 s a 10 M).
   - Erro mediano interno: W3 17,3 / 28,7 m e W5 17,6 / 28,1 m — melhor que o B1 e perto do B2.
   - Captura cerca de 80% do ganho do M1n nos placebos (P1/P2) e 60–90% no perfil real (P0).
   - Melhor p90 de todos em P2 (W3: 332 m) e nas pontas fica entre o B1 e o B0 (33 / 55 m).
   - O M1n continua melhor: −3,5 m (P1) e −5,5 m (P2) contra o W3, IC95% por rua sem cruzar zero.
   - **Sensibilidade (k = 2…11, §2.1):** quase todo o ganho vem de k = 1 → 3; depois, platô nos
     internos, enquanto pontas e P0 seguem melhorando até o nível do B1. k = 4–5 equilibra os dois.
     O tempo não depende de k.
6. **O `desvio_metros` dos casos interpolados não informa o erro.** Ele reporta a média dos desvios dos
   pontos usados (mediana 6 m), e só 3–8% dos erros do B0 ficam abaixo dele.

## 1. Desenho

**Base de teste.** Tabela mais completa do geocodebr, `municipio_logradouro_numero_cep_localidade`
(49,7 M linhas), na chave da etapa `da01` (rua + CEP + localidade). Maceió e Curitiba ficaram de fora
porque foram usadas no pré-teste dos agentes.

**Amostra.** 12,4 mil ruas e 36,7 mil alvos, estratificados por tamanho × forma, com 3 alvos por rua
(2 internos + 1 ponta).
- Formas: reta / intermediária / **curva** / desordenada; 3 mil ruas curvas.
- Inclui as ruas da issue #10: IQUIRIRIM (Butantã, 2 CEPs) e AV. MINISTRO IVAN LINS (Barra).

**Forma da rua.** A primeira tentativa, a sinuosidade do traçado na ordem dos números, mede
sobretudo a **desordem da numeração** (números que vão e voltam numa rua reta), não a curva
(`saidas/inspecao_sinuosidade.png`).
- **Curvatura** passou a ser a flecha p90 ÷ extensão em torno do eixo principal dos pontos, sem
  depender da ordem dos números e descartando pontos isolados. Curva = curvatura > 0,15 com
  flecha > 25 m.
- A **desordem** (comprimento do percurso pela ordem dos números ÷ extensão > 2,5) virou estrato
  próprio.
- Inspeção visual (`saidas/inspecao_curvatura.png`): 10 das 12 ruas logo acima do corte são curvas
  de fato. Foram 3 variantes da medida, todas antes de olhar os erros.

**Conjuntos com verdade conhecida.**

| Conjunto | O que suprime | Alvos |
|---|---|---|
| P1 leave-one-out | o número-alvo, em todos os CEPs da rua | 36.687 |
| P2 leave-window-out | ±10 números em torno do alvo e todo ponto a ≤ 5 m dele (neutraliza vizinhos duplicados ou centroides) | 34.674 |
| P0a real | linhas do `large_sample` interpoladas hoje (`da*`/`pa*`) cujo número existe, único, sob outra chave | 1.419 |
| P0b real | 200 mil endereços do CNEFE com o CEP trocado por outro CEP da mesma rua onde o número não existe (CEP genérico ou faixa errada) | 200.000 |

**Métodos.**

| id | Método |
|---|---|
| B0 | IDW `1/|Δn|` sobre todos os números (atual) |
| Wk | O mesmo IDW com peso `1/|Δn|^k`, k ∈ {2, 3, 4, 5, 6, 7, 9, 10, 11} (issue #36; W3 e W5 nas tabelas principais) |
| B1 | Número existente mais próximo (Geocenarios) |
| B2 | Linear entre os vizinhos L e U, qualquer lado (issue #10) |
| M1 | B2 do mesmo lado + trava de salto: se `dist(L,U) > 3·ΔN + 50 m`, usa o vizinho mais próximo |
| M1n | M1 sem a trava (ablação) |
| M1c | M1 + ponte de CEP |
| M2 | Mediana dos 4 vizinhos mais próximos |
| M4 | Interpolação sobre o eixo suavizado (mediana móvel de 5 pontos) |

O método H (híbrido) não foi rodado: a condição dele (o B1 vencer o M1 em curvas ou em ruas esparsas)
não ocorreu. Todos os métodos estão em SQL DuckDB puro, gerado por um único arquivo
(`02_metodos_sql.R`) usado pelo benchmark isolado e pelo override do `geocode()`.

**Portões** (`saidas/portao.txt`), ambos aprovados:
- O override com B0 reproduz o `geocode()` de produção nas 4.532 linhas interpoladas do
  `large_sample` (máx. 0,37 m, arredondamento float32; `endereco_encontrado` idêntico).
- O B0 isolado reproduz o `geocode()` com holdout em 200 alvos (máx. 6e-9 m).

**Determinismo** (entrada embaralhada): todos os novos métodos dão saída bit a bit idêntica. O B0
oscila em 2e-14 grau, ordem de soma conhecida (`saidas/equivalencia_determinismo.txt`).

## 2. Precisão

**Alvos internos** (mediana / p90 / % < 50 m):

| | B0 atual | W3 | W5 | B1 vizinho | B2 | M1 | **M1n** | M2 | M4 |
|---|---|---|---|---|---|---|---|---|---|
| P1 | 34,1 / 254 / 62% | 17,3 / 226 / 73% | 17,6 / 233 / 73% | 18,5 / 244 / 73% | 16,4 / **224** / 73% | **13,3** / 259 / 74% | 13,8 / 240 / 73% | 19,0 / 256 / 71% | 16,8 / 247 / 72% |
| P2 | 57,9 / 360 / 45% | 28,7 / **332** / 63% | 28,1 / 339 / 64% | 31,5 / 370 / 62% | 25,1 / 338 / 64% | **23,2** / 363 / 65% | **23,2** / 341 / 65% | 32,2 / 349 / 62% | 27,5 / 342 / 64% |

Na amostra de confirmação (outra semente, 12,5 mil ruas) a ordem se repete: P1 W3 18,0 e W5 18,1 m
contra M1n 14,4 e B0 34,6 m; P2 29,5 / 29,3 contra 23,8 e 58,3 m (`saidas/confirmacao_m1_trava.txt`).

**Pontas da rua:** B1 = B2 = M1 = M1n = 29 / 47 m, por construção; W5 30 / 50 m; W3 33 / 55 m;
B0 = 83 / 114 m; M2 e M4 pioram (38–58 m). O expoente maior se aproxima do vizinho mais próximo, por
isso o W5 é melhor que o W3 nas pontas.

**Erro mediano por forma (P2, internos):**

| forma | B0 | W3 | W5 | B1 | B2 | M1n |
|---|---|---|---|---|---|---|
| reta | 35,5 | 15,9 | 16,5 | 20,9 | 12,9 | **10,6** |
| intermediária | 51,9 | 25,5 | 25,8 | 29,8 | 22,6 | **21,0** |
| **curva** | 80,5 | 47,4 | 47,2 | 50,3 | 44,6 | **43,6** |
| desordenada | 82,5 | 57,0 | 52,4 | 55,2 | 53,5 | **49,7** |

O erro cresce com a curvatura em todos os métodos (`saidas/fig_a_erro_por_curvatura.png`), mas a ordem
entre eles não muda em nenhum decil. Nas ruas-âncora (`saidas/fig_b_ruas_ancora.png`, P1), a mediana
cai de B0 → W3/B1 → M1n:

| Rua | B0 | W3 | B1 | M1n |
|---|---|---|---|---|
| IQUIRIRIM 05586-001 | 28 m | 10 m | 11 m | 6 m |
| IQUIRIRIM 05586-000 | 32 m | 14 m | 18 m | 10 m |
| IVAN LINS (rua da issue #36) | 87 m | 68 m | 60 m | 60 m (rua de 15 pontos) |

**Quando o mesmo lado ajuda e quando não:**
- **Ruas em que a regra par/ímpar vale** (o vizinho do mesmo lado está mais perto que o do lado
  oposto): o M1n faz 10,7 / 15,7 m e o B2 faz 15,6 / 18,8 m.
- **Ruas em que não vale:** o M1n fica igual ou um pouco pior que o B2 (21,7 vs 18,3 m em P1).
- **DF:** também nesse caso (21,3 vs 21,0 m em P1).
- **Numeração não métrica** (correlação entre número e distância < 0,5): todos os métodos ficam em
  31–106 m.

**A trava de salto foi descartada** (ablação pós-hoc, confirmada numa amostra nova de 12,5 mil ruas,
`saidas/confirmacao_m1_trava.txt`).
- Nos casos em que ela dispara, o erro é **pior** com a trava: mediana 142 vs 130 m e p90 1.096 vs
  966 m em P1.
- Sem ela, a mediana fica igual e o p90 melhora: 363 → 341 m em P2, e 395 → 368 m na confirmação.

**A ponte de CEP (M1c) não acrescenta nada:** fica a ±0,1 m do M1, inclusive em ruas com vários CEPs.

**P0, perfil real.** O número existe, mas noutro trecho ou CEP, e por isso os erros são maiores.
- Ordem: B2 ≈ M1n ≈ B1 ≈ M4 < W5 ≈ M2 < W3 ≪ B0.
- P0a: mediana 160–168 m para os quatro primeiros, W5 175 m, W3 184 m, contra 241 m do B0.
- P0b: 176–182 m, W5 192 m, W3 200 m, contra 228 m.
- O B0 piora > 50 m em relação ao B1 em 31–38% dos casos; o W3, em 18–19%; o W5, em 12%; o M1n, em 4–7%.
  Aqui o número existe noutro trecho da rua, e o IDW ainda puxa a estimativa para os números do
  trecho errado — o expoente atenua, mas não elimina, esse efeito.

**Distância ao eixo suavizado** (só descritiva, porque favorece o M4 por construção): em ruas curvas,
o B0 fica a 14–18 m do eixo; os métodos por vizinhos e o W3/W5, a 4–8 m. O expoente já basta para
tirar a estimativa de dentro da curva.

### 2.1 Sensibilidade ao expoente do IDW

Peso `1/|Δn|^k` para k = 1 (atual), 2, 3, 4, 5, 6, 7, 9, 10 e 11, nos mesmos conjuntos
(`saidas/sensibilidade_expoente.txt`, `saidas/fig_c_sensibilidade_expoente.png`). Erro mediano, m:

| k | P1 int. | P2 int. | P2 curvas | P1 pontas | P2 pontas | P0a | P0b | p90 P2 int. | 10 M entradas |
|---|---|---|---|---|---|---|---|---|---|
| 1 (B0) | 34,1 | 57,9 | 80,5 | 82,9 | 113,6 | 241 | 228 | 360 | 19,0 s |
| 2 | 18,4 | 32,7 | 49,9 | 41,5 | 67,6 | 195 | 209 | 332 | 21,0 s |
| 3 | **17,3** | 28,7 | 47,4 | 33,2 | 55,4 | 184 | 200 | **332** | 21,3 s |
| 4 | 17,4 | **28,1** | **47,0** | 31,0 | 51,4 | 177 | 195 | 337 | 21,0 s |
| 5 | 17,6 | **28,1** | 47,2 | 29,9 | 50,0 | 175 | 192 | 339 | 22,0 s |
| 6 | 17,6 | 28,3 | 47,2 | 29,7 | 49,2 | 173 | 190 | 340 | 21,4 s |
| 7 | 17,7 | 28,5 | **47,0** | 29,4 | 48,6 | 173 | 188 | 343 | 21,6 s |
| 9 | 17,8 | 28,6 | 47,4 | 29,2 | 47,8 | 172 | 186 | 346 | 21,6 s |
| 10 | 17,9 | 28,7 | 47,5 | 29,2 | 47,6 | 172 | 186 | 347 | 20,8 s |
| 11 | 17,9 | 28,8 | 47,4 | 29,1 | 47,3 | **171** | **185** | 349 | 23,2 s |
| *B1 vizinho* | 18,5 | 31,5 | 50,3 | 28,8 | 47,1 | 165 | 181 | 370 | 28 s |
| *M1n* | 13,8 | 23,2 | 43,6 | 28,8 | 47,1 | 168 | 180 | 341 | 80 s |

- **Quase todo o ganho vem de k = 1 → 3.** Nos internos o erro fica num platô de k = 3 a 11
  (17,3–17,9 / 28,1–28,8 m); o ótimo é k = 3 em P1 e k = 4–5 em P2. A amostra de confirmação dá o mesmo
  platô (P1 18,0–18,1; P2 29,3–29,7 m).
- **Pontas e P0 melhoram sempre com k**, porque o IDW tende ao vizinho mais próximo quando k cresce;
  em k = 11 já está a < 1 m do B1 nas pontas e a 4–6 m no P0.
- **O p90 interno piora com k** a partir de k = 3 (332 → 349 m em P2): o peso concentrado num só
  vizinho herda os erros grosseiros dele.
- **Ponto de equilíbrio: k = 4 ou 5.** Ficam a ≤ 0,3 m do melhor interno, recuperam a maior parte do
  ganho nas pontas e no P0, e o p90 só sobe 5–7 m em relação a k = 3.
- **Nenhum k alcança o M1n nos internos** (−3,5 a −5 m a favor do M1n); quando k cresce o Wk
  se aproxima do B1 (com média quando os dois vizinhos estão à mesma distância em número).
- **O tempo não depende de k:** 21–23 s a 10 M (B0: 19 s), mesmos 4,5 GB.

## 3. Tempo de computação

Todas as medições com 2 threads, numa máquina.

**Etapa isolada** (tabela já materializada; aquecimento descartado; mediana de 3 rodadas, ou 1 rodada
a 10 M; `saidas/tempo_isolado.csv`):

| | B0 | W3 | W5 | B1 | B2 | M1/M1n | M2 | M4 | M1 via ASOF |
|---|---|---|---|---|---|---|---|---|---|
| 1 M entradas | 2,3 s | 2,6 s | 2,6 s | 4,1 s | 6,0 s | 9,3 s | 88 s (27 GB) | 65 s | 38 s* |
| 10 M entradas | 18 s (4,5 GB) | 21 s (4,5 GB) | 23 s (4,5 GB) | 28 s | — | 80 s (7,7 GB) | — | — | 108 s* |

B0, W3 e W5 foram medidos de novo na mesma sessão (B0: 2,3 s e 18 s, iguais à primeira medição).
O `pow()` custa +15–30% sobre o B0 e nenhuma memória extra; a observação da issue #36 de que o
expoente "deixou a rotina bem mais lenta" não se reproduz com o SQL atual.

\* ASOF com a referência já filtrada pelas ruas da entrada. Com a tabela nacional, ele ordena 50 M de
linhas a cada chamada (72 s fixos, 27 GB). A resposta é idêntica à do M1, mas **não** fica mais rápido
que o join + `GROUP BY` com agregados `FILTER`. M2 e M4 pagam pelas funções de janela.

**Ponta a ponta** (`geocode()`, 1 aquecimento + 3 rodadas alternadas, sem concorrência;
`saidas/tempo_ponta_a_ponta_vencedor.csv`):

| | B0 | W3 | W5 | M1n |
|---|---|---|---|---|
| `large_sample` (20 mil, mediana de 3) | 7,12 s | 7,51 s | 7,50 s | 7,41 s |
| P0b (200 mil, 1 rodada) | 18,9 s | 17,2 s | 17,7 s | 20,2 s |

A primeira rodada (só B0 × M1n) tinha dado 7,83 × 8,75 s e 19,4 × 20,1 s. As diferenças entre
métodos (≤ 1,3 s) são da ordem da variação entre rodadas: no `geocode()` completo o método de
interpolação não pesa. Nota: o override calcula todos os agregados para qualquer método, então esta
tabela não isola o custo de cada um — para isso vale a tabela da etapa isolada.

No `large_sample`, 4.507 linhas (22,5%) mudam de coordenada com o M1n (4.507 com o W3, 4.510 com o
W5), todas `da*`/`pa*`.

## 4. Ressalvas

- **A verdade é o próprio CNEFE agregado.** Cada número é a média dos registros com aquele número. O P2
  mitiga vizinhos duplicados, mas não há verdade de campo independente.
- **Números internos vs pontas.** Nos estratos, os números internos são 2/3 dos alvos; a proporção real
  de números ausentes nas pontas, em entradas de produção, é desconhecida. O P0b (CEP trocado) é o
  conjunto mais próximo do uso real e dá a mesma ordem.
- **Só a escolha da coordenada.** As etapas `pa*` usam a mesma interpolação depois de escolher a rua por
  Jaro. O erro de escolha da rua não muda com o método e ficou fora do estudo.
- **Etapas `da02` e `da04`** (vários candidatos + desempate) estão cobertas só pelo P0, que roda o
  `geocode()` completo.
- **Ajustes congelados antes do teste:** k = 4 e a trava. Os cortes de forma tiveram 3 variantes,
  ajustadas por inspeção visual, sem olhar erros. A única escolha pós-hoc (tirar a trava) foi
  confirmada numa amostra nova.
- **Pré-teste fora do teste:** Maceió e Curitiba, onde os agentes fizeram o pré-teste, foram excluídas
  da amostra.
- **Sem urbano/rural:** a situação do setor não está nas tabelas locais.
- **W3/W5 entraram depois dos demais resultados**, com expoentes fixados pela issue #36; a varredura
  k = 2…11 (sem k = 8, conforme pedido) foi feita depois e é descritiva — escolher k por ela é ajuste
  pós-hoc, mitigado porque o platô se repete na amostra de confirmação. O determinismo deles não foi medido à parte: a soma é a mesma do B0, então se espera a
  mesma oscilação de ~1e-14 grau. O resultado concorda com o k-fold da issue (Gabriel Almeida:
  `idw3` ≈ `segment` em 10 mil ruas).

## 5. Recomendação

**Substituir o B0 pelo M1n nas etapas `da01–da04` e `pa01–pa03`, num PR próprio com paridade R + Python.**

**Alternativa de mudança mínima: W3** (`1/|Δn|³`). É uma troca de uma expressão em
`match_weighted_cases*.R` e `matching.py`, sem agregados novos, a +15–20% de tempo na etapa isolada.
Leva cerca de 80% do ganho do M1n nos placebos, mas fica 3,5–5,5 m pior nos internos, pior nas pontas
(33 vs 29 m) e 20 m pior no P0b. Pela sensibilidade (§2.1), **k = 4 ou 5** é preferível a k = 3:
mesmo erro interno, pontas e P0 melhores, p90 quase igual. Faz sentido como passo intermediário se o
M1n tiver de esperar.

1. **Mudança na consulta.** Só a parte 2 da consulta de `match_weighted_cases.R`,
   `match_weighted_cases_probabilistic.R` e `matching.py` (Python) muda. Os agregados
   `max/arg_max ... FILTER` já são o que roda no override validado (`05_override.R`).
2. **Sem coluna nova** em `padronizacao_cnefe` e **sem novo `data_release`.** Nem o M4 nem o híbrido
   justificaram pré-cálculo.
3. **`desvio_metros` das etapas `da`/`pa`.** Hoje ele cobre só 21–30% dos erros do M1n.
   - **Proposta inicial:** `max(desvio do vizinho, dist(L,U)/2)`, que cobre 58–66%.
   - **Antes de adotar:** calibrar num leave-one-out de teste a um nível nominal (ex.: 80%).
   - **Documentação:** atualizar `precision_section.R`.
4. **Aceite.**
   - `identical()` fora das linhas `da*`/`pa*`.
   - `pytest -m r_parity`.
   - Reproduzir a tabela P2 com o código do pacote.
5. **Melhoria opcional, depois.** Usar o mesmo lado só quando a rua obedece à regra par/ímpar, com uma
   flag por rua: ganharia cerca de 3 m nas ruas fora da regra e no DF.
6. **Ponto representativo do logradouro** (tema literal da issue #10: a média simples das coordenadas
   da rua, nas etapas `dl*`/`pl*`). Fica para o `padronizacao_cnefe`. A classificação curva /
   desordenada deste estudo (`01_amostra.R`) serve para escolher ali entre a média e o número
   mediano.
