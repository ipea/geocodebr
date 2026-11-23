# Sessão 2026-11-22 — interpolação de número ausente (lição 3 da comparação Geocenarios)

**Objetivo:** comparar o método atual (`1/|Δn|` sobre todos os números), o do Geocenarios (vizinho mais próximo) e
alternativas de 4 agentes criativos (geometria, estatística robusta, convenções de numeração, dados externos), em
precisão e tempo, com placebos na tabela mais completa e ruas curvas obrigatórias (issue ipea/padronizacao_cnefe#10).
Plano: `quality_reports/plans/2026-11-22_interpolacao-numero-ausente.md` (v2 após 3 revisores adversariais).

## Decisões
- Precisão = distância haversine entre a estimativa e o ponto CNEFE do número suprimido (confirmado pelo usuário).
- Forma da rua: sinuosidade por ordem de número descartada (mede desordem); curvatura por PCA robusta + classe
  "desordenada". 3 variantes, todas por inspeção visual antes de olhar erros.
- Métodos em SQL único (`02_metodos_sql.R`) usado no benchmark isolado e no override do `geocode()` (`05_override.R`).
- Portões passaram: override B0 ≡ produção (máx 0,37 m, float32); B0 isolado ≡ geocode com holdout (6e-9 m).
  1ª tentativa do portão B falhou por 2 alvos na mesma rua retirados juntos → 1 alvo por rua.
- Trava de salto do M1 retirada (ablação pós-hoc), confirmada em amostra nova (semente "confirmacao", 4% de ruas em comum).
- H (híbrido) não rodado: condição não ocorreu. M1_asof: mesma resposta, mais lento.

## Resultado
Relatório `quality_reports/diagnoses/2026-11-22_interpolacao-numero-ausente.md`. Recomendado: M1n (bracket mesmo lado,
sem trava). P2 internos: 23,2 m vs 57,9 m (atual) e 31,5 m (vizinho). Ponta a ponta +4–12% de tempo.
Não feito: urbano/rural (sem situação do setor local); verdade de campo independente; implementação no pacote (PR próprio).

## Adendo — B3/B5 (issue #36), 22/11

- Pedido do usuário: incluir o IDW atual com expoente 3 e 5 (`1/|Δn|^k`, issue ipeaGIT/geocodebr#36).
- Implementado em `02_metodos_sql.R` (agregados `b3_*`, `b5_*`; `METODOS` agora com B3/B5), `04_tempo.R`,
  `07_avaliacao.R` (bootstrap M1n−X para B0/B1/B3/B5; figura B com coluna B3), `09_tempo_e2e.R`.
- Rodado: P1/P2 principal e confirmação, P0a/P0b (B3, B5), tempo isolado (B0/B3/B5 a 1e5–1e7), ponta a ponta.
- Resultado: B3 17,3/28,7 m e B5 17,6/28,1 m (internos P1/P2) — ~80% do ganho do M1n a custo ~B0
  (+15–30% isolado). M1n segue melhor (−3,5/−5,5 m vs B3). P0b: B3 200, B5 192, M1n 180, B0 228.
- Relatório atualizado (resumo item 5, tabelas, tempo, ressalva, recomendação com B3 como alternativa mínima).

## Adendo 2 — sensibilidade ao expoente k = 2, 3, 4, 5, 6, 7, 9, 10, 11

- Família renomeada de Bk para **Wk** (B2 já era o bracket; colisão de nome). `EXPOENTES` em `02_metodos_sql.R`.
- Rodado: P1/P2 (principal + confirmação), P0a/P0b, tempo isolado 1e6/1e7 por k. Saídas:
  `saidas/sensibilidade_expoente.txt`, `saidas/fig_c_sensibilidade_expoente.png`.
- Resultado: ganho quase todo em k = 1 → 3; platô nos internos (17,3–17,9 / 28,1–28,8 m); pontas e P0
  melhoram monotonamente rumo ao B1; p90 interno piora com k > 3. k = 4–5 equilibra. Tempo independe de k
  (21–23 s a 10 M vs 19 s do B0). Nenhum k alcança o M1n.
- k = 8 não foi testado (não estava no pedido).


---
**Context compaction (auto) at 00:13**
Check git log and quality_reports/plans/ for current state.
