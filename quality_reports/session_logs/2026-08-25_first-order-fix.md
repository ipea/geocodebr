# Log de sessão — 2026-08-25 — item #3: ORDER BY nos FIRST() de da0x/pa0x

**Objetivo:** implementar e validar ponta a ponta o item #3 de
`quality_reports/diagnoses/2026-08-24_geocode-eficiencia-consolidado.md` — `FIRST()` sem `ORDER BY` em
`match_weighted_cases.R`/`match_weighted_cases_probabilistic.R` causa não-determinismo entre chamadas
idênticas de `geocode()`.

## Abordagem

- Discussão de design antes de implementar: expliquei o diagnóstico exato (quais `FIRST()`, por quê) e a
  decisão de semântica pendente (o que `contagem_cnefe` agregado deve significar). Usuário confirmou a opção
  recomendada: `FIRST(... ORDER BY ABS(numero - numero_cnefe), numero_cnefe, lat, lon)` — candidato mais
  próximo do número buscado vence.
- Implementado nos dois arquivos: variável `ordem_first` reaproveitada em toda `FIRST()` do agregado.
- Benchmark de reprodutibilidade (duas chamadas idênticas, `n_cores=7`) revelou que a divergência não
  zerava — investiguei e achei uma **segunda fonte**, não documentada antes: dois `QUALIFY ROW_NUMBER() ...
  ORDER BY contagem_cnefe DESC` em `trata_empates_geocode_duckdb.R`, sem desempate quando `contagem_cnefe`
  empata. Reportei ao usuário com números antes de agir.
- Usuário decidiu o fix simplificado: `ORDER BY contagem_cnefe DESC, desvio_metros` (não a versão mais
  extensa que propus). Implementado, testado — reduziu de 5 para 2-3 linhas divergentes em 20.028, mas
  **não fechou** o resíduo. Documentei isso explicitamente em vez de reportar como resolvido.
- Usuário então acrescentou `endereco_encontrado` como terceiro critério de desempate diretamente no código
  (`ORDER BY contagem_cnefe DESC, desvio_metros, endereco_encontrado`). Rodei o benchmark de novo (3 rodadas
  de "duas chamadas idênticas") e confirmei: **0/20.028 divergências em cada rodada** — fechou por completo.
- **Correção do usuário sobre o NEWS.md**: pediu para registrar a mudança do `FIRST()` como "Mudança grande"
  (não pequena/interna), com redação específica focada no efeito observável (colunas extras podiam vir de
  ponto arbitrário da interpolação; agora vêm do ponto mais próximo). Movida para a seção correta.

## Arquivos tocados

- `R/match_weighted_cases.R`, `R/match_weighted_cases_probabilistic.R` — `ordem_first` em todo `FIRST()`.
- `R/trata_empates_geocode_duckdb.R` — `ORDER BY contagem_cnefe DESC, desvio_metros` nos dois `QUALIFY`.
- `NEWS.md` — nova seção "Mudanças grandes" no dev version.
- `MEMORY.md` — entrada anterior (`FIRST() sem ORDER BY`) marcada como corrigida; nova entrada sobre o
  achado extra no `QUALIFY` e o resíduo não fechado.
- `tests/tests_rafa/benchmark_first_order.R` — script de benchmark (reprodutibilidade + corretude + tempo).
- `quality_reports/diagnoses/2026-08-25_first-order-fix-benchmark.md` — relatório com os números.

## Decisões / correções

- **Correção do usuário**: NEWS.md deve registrar mudança de comportamento observável como "grande", com
  foco no efeito para o usuário, não na causa técnica interna. Vale para qualquer entrada futura de NEWS.md
  nesta sessão de trabalho.
- **Decisão do usuário**: aceitar o resíduo de não-determinismo (2-3/20.028) em troca de um `ORDER BY` mais
  simples, em vez de fechar 100% com mais colunas de desempate. Documentado como decisão consciente, não
  como limitação escondida — se o resíduo incomodar depois, a extensão do `ORDER BY` já está desenhada no
  relatório de diagnóstico.

## Questões em aberto / bloqueios

- Nenhuma. O resíduo de não-determinismo mencionado na primeira rodada do desempate foi fechado depois que
  o usuário acrescentou `endereco_encontrado` ao `ORDER BY` — 0/20.028 divergências confirmado em 3 rodadas.
- Item #1 (guarda do laço) já foi commitado (`d27b722`) fora desta sessão. Item #3 (esta sessão) ainda não
  foi commitado.

## Status

**Concluído, mantido, não-determinismo fechado por completo.** `devtools::test()` verde (257 passes, 0 fail)
como smoke check, rodado depois de cada rodada de mudanças. `git status` limpo além dos arquivos
intencionais desta sessão (`MEMORY.md`, `NEWS.md`, os três `.R` de `R/`, o script de benchmark novo).
