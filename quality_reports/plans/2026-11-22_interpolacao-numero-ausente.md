# Plan — interpolação de número ausente: geocodebr × Geocenarios × alternativas (lição 3)

**Status:** COMPLETED (v2) · 2026-11-22 · consenso após 3 revisores adversariais (simplicidade / validade / abrangência)

## Context

Lição 3 da comparação com o Geocenarios trata do número que não existe no CNEFE.
- **Hoje no geocodebr:** etapas `da01–da04` e `pa01–pa03`, em `r-package/R/match_weighted_cases.R:106` e `match_weighted_cases_probabilistic.R`. A coordenada é `SUM(lat/|Δn|)/SUM(1/|Δn|)` sobre **todos** os números da rua.
- **No Geocenarios:** usa a coordenada do **número existente mais próximo**.
- **Leave-one-out anterior** (300 casos RJ/AL, mediana / p90):
  - nosso método: 30 m / 150 m;
  - vizinho mais próximo: 18 m / 134 m.

A issue [ipea/padronizacao_cnefe#10](https://github.com/ipea/padronizacao_cnefe/issues/10) mostra o problema em ruas **curvas**: a média de muitos pontos cai fora do traçado. Ruas-âncora:
- RUA IQUIRIRIM (Butantã);
- AV. MINISTRO IVAN LINS (Barra).

**Objetivo:** comparar **precisão** e **tempo** de 6 métodos com placebos de localização conhecida. Os placebos vêm da tabela mais completa do geocodebr, com ruas curvas como estrato obrigatório. Ao final, recomendar um método.

Esta tarefa não muda código dos pacotes. O vencedor vira um PR próprio, com paridade R + Python.

**Pré-teste de um agente** (arrow, leave-one-out, mediana / p90 em m), feito com SQL ainda não rodado em DuckDB. Por isso Maceió e Curitiba ficam **fora** do conjunto de teste.

| Método | Maceió | Curitiba |
|---|---|---|
| IDW atual | 27,7 / 160 | 26,2 / 104 |
| Vizinho mais próximo | 13,6 / 139 | 15,7 / 46 |
| Bracket do mesmo lado | 12,2 / 146 | 8,1 / 42 |

**Fatos do código que o benchmark tem que respeitar** (`utils.R:413,445,608`):
- `da01` roda logo após `dn01`, antes de `dn02–dn04`. Logo, um número que existe com outro CEP ou outra localidade é interpolado.
- `da02` e `da04` juntam sem localidade (o `da04` também sem CEP), agrupam por `localidade_cnefe`/`cep_cnefe` e geram vários candidatos. Quem resolve é o desempate.
- Cada `da0k` usa sua própria tabela e chave. A dos `da03`/`da04` é a `..._localidade`, sem CEP.
- `lat`/`lon` são FLOAT (float32).

## Métodos (todos em SQL DuckDB puro, determinísticos e portáveis ao Python; parâmetros **congelados antes** do teste)

| id | Método | Origem |
|---|---|---|
| B0 | IDW `1/|Δn|` sobre todos os números (atual) | geocodebr |
| B1 | Número existente mais próximo; desempate pelo menor número | Geocenarios |
| B2 | Linear entre os vizinhos inferior L e superior U, ignorando o lado; nas pontas, o extremo | issue #10 (ablação) |
| M1 | B2 **do mesmo lado** (`numero % 2`).<br>• Sem par do mesmo lado: ignora o lado.<br>• Na ponta: B1.<br>• Trava de salto: se `dist(L,U) > 3·(U−L)+50 m`, usa o vizinho mais próximo.<br>• **Chave on/off:** ponte de CEP, que refaz o ASOF sem CEP quando o suporte é unilateral. | 3 dos 4 agentes |
| M2 | Mediana componente a componente dos k = 4 números mais próximos | agente estatística |
| M4 | Referenciamento linear.<br>• Eixo suavizado: mediana móvel de 5 pontos, com os dois lados.<br>• Comprimento acumulado `s`.<br>• Interpola `s` entre L e U e devolve o ponto sobre o eixo. | agente geometria |
| H | *Só se* B1 vencer M1 em curvas ou ruas esparsas: M1 nas ruas retas e densas, B1 nas demais | condicional |

Cortados após revisão:
- M3 (local-linear): dominado por M1/M2 e com dois hiper-parâmetros.
- M5 (B0 projetado): herda o viés do B0.

Fora do escopo:
- geometria de faces do IBGE ou do OSM como método;
- incerteza conformal;
- o ponto representativo **do logradouro**, tema literal da issue #10: vira uma nota/ticket em `padronizacao_cnefe`.

## Passos

### 0 — Organização
- Salvar este plano como `quality_reports/plans/2026-11-22_interpolacao-numero-ausente.md` e restaurar neste arquivo o plano de 21/11 (COMPLETED), que o relatório cita.
- Scripts em `quality_reports/comparisons/2026-11-22_interpolacao/`; saídas grandes no scratchpad.
- Reusar `2026-11-21_geocenarios/00_config.R` (lib temporária com duckdb 2.0.0) e o override de `listar_pasta_cache` (`05_synthetic.R:137`).
- Em todas as consultas: mesmo `SET threads = 2`, mesmo `memory_limit`, coordenadas convertidas para DOUBLE.

### 1 — Universo e estratos (`01_amostra.R`)
Fonte: as tabelas de referência de cada etapa `da0k`. A principal é `municipio_logradouro_numero_cep_localidade.parquet` (50,2 M linhas, 2,9 M ruas-chave).

Atributos por rua-chave:
- `n_pontos`;
- gap mediano de número;
- **conformidade de lado**: % de pontos mais perto do eixo do seu lado do que do lado oposto;
- **numeração métrica**: correlação entre Δnúmero e distância ao longo do eixo; abaixo de 0,5 = numeração por bloco/lote;
- `n_cep`;
- situação urbana/rural do setor;
- **sinuosidade** do eixo suavizado, calculada **sem a janela do alvo** (por alvo, evita circularidade).

Amostra estratificada:
- forma: reta / intermediária / curva;
- tamanho: `n ≤ 3`, 4–15, 16–60, `> 60`;
- urbano/rural.

Regras da amostra:
- curvas = ≥ 1/3;
- mesmo número de alvos por rua (3);
- DF entra com estrato próprio, sinalizado.

Cortes (curva > 1,15, reta < 1,05) apenas para estratificar. Validar com inspeção visual de 30 ruas em torno do corte. O relatório também mostra o erro **contínuo por decil de sinuosidade**.

### 2 — Conjuntos de teste com verdade conhecida
| Conjunto | Como | Por quê |
|---|---|---|
| **P0 real** | Entradas que hoje caem em `da0k` mas cujo número existe exatamente sob outra chave (match `dn03`/`dn04`).<br>Verdade = essa coordenada.<br>Fonte: `large_sample.parquet` + 200 mil endereços sorteados da própria base com CEP/localidade trocados como no input real. | Perfil de entrada real, não só lacunas internas (revisor de validade). |
| **P1 leave-one-out** | Retira 1 número; as pontas da rua formam um estrato. | Caso típico. |
| **P2 leave-window-out** | Retira ±10 números em volta do alvo **e** todo ponto a ≤ 5 m dele. | Neutraliza vizinhos duplicados/centróides, que inflariam B1. |

Volume: ~30 mil alvos em P1 e P2 (em ruas fora de Maceió e Curitiba); P0, o que existir.

Cada método roda **por etapa** (`da01–da04`), com a chave e a tabela de cada uma. Assim reproduz o caminho real, inclusive candidatos múltiplos + desempate (`trata_empates_geocode_duckdb`) nos `da02`/`da04`. As etapas `pa*` usam a mesma interpolação depois de escolher a rua. O erro de escolha da rua é independente do método e fica fora deste estudo; isso é dito no relatório.

### 3 — Precisão (`02_metodos.sql`, `03_avaliacao.R`)
Métricas por método × conjunto × estrato:
- erro haversine: mediana, p90, % < 50 m;
- **% de casos em que o método piora > 50 m em relação a B1** (risco da troca);
- **calibração de `desvio_metros`**: % de casos com erro ≤ o `desvio_metros` reportado. Hoje é `AVG` dos pontos e não reflete a interpolação;
- **distância ao eixo**: só descritiva, não ranqueia, porque favorece o M4 por construção. Nas 2 ruas-âncora, conferir contra o traçado do OSM (MAY: consulta Overpass de 2 vias; pede OK de download).

Cortes de resultado:
- `n_casos = 1` vs `> 1`;
- conforme ao lado vs não;
- multi-CEP (onde a chave da ponte de CEP do M1 é avaliada);
- diagnóstico de chave que mistura ruas físicas: `dist(L,U) > 2 km`, resultado com e sem.

Bootstrap por rua **só** das diferenças vencedor − B0 e vencedor − B1.

Figuras (carregar `/dataviz` antes):
- (a) erro por decil de sinuosidade, um traço por método;
- (b) mapas das 2 ruas-âncora com verdade, B0, B1 e vencedor.

### 4 — Tempo (`04_tempo.R`)
- **Isolado, por etapa:** 100 mil e 1 milhão de entradas (P0 + placebos, SP+RJ+MG), contra a tabela já materializada.
  - Cache aquecido, 1ª rodada descartada, mediana de 3 rodadas.
  - Para os 2 finalistas, também **10 milhões** de entradas.
- Memória de pico só para M4 e para o vencedor.
- **Pré-cálculo do M4:** tempo nacional e MB a mais no parquet, reportados à parte e amortizados.
- **Ponta a ponta, só o vencedor vs B0:** `geocode()` com override das duas funções no namespace (sem editar `R/`) no `large_sample.parquet`. Medir s/1k endereços e quantas linhas mudam de coordenada.

### 5 — Relatório e recomendação
`quality_reports/diagnoses/2026-11-22_interpolacao-numero-ausente.md` (pt-BR), com:
- métodos × precisão × tempo;
- curvas;
- ressalvas;
- 1 recomendação, com o que ela exige:
  - `match_weighted_cases*.R` + `matching.py`;
  - coluna nova em `padronizacao_cnefe`? Só aceitável se for o M4/H **e** ganhar > 5 m na mediana sobre o M1;
  - novo `desvio_metros`;
  - texto de `precision_section.R`.

Mais: nota sobre o ponto do logradouro (issue #10), log de sessão e `[LEARN]` no MEMORY.md.

## Verificação
- **Portão do harness:** o B0 isolado tem que reproduzir o `geocode()` com o mesmo holdout em 200 casos **de cada** etapa `da0k`, desempate incluído, com diferença ≤ 1 m (em haversine, após converter para DOUBLE). Se falhar, nada segue.
- **Coerência:** B0 e B1 em P1 RJ/AL ≈ 30 m e 18 m (estudo de 21/11).
- **Determinismo:** cada método 2× com a entrada embaralhada → saída idêntica.
- **Congelamento:** k = 4, trava `3·Δn+50`, cortes de sinuosidade. Fixados antes de olhar o teste; o número de variantes tentadas é reportado.
- Se o duckdb do R travar no parquet nacional (houve um segfault relatado), rodar por UF e registrar.
- Os números do relatório saem dos scripts a partir de parquets salvos.
- O que não rodar é reportado como não rodado.
