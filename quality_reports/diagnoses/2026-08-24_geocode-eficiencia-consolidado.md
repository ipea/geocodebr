# `geocode()` — análise consolidada de eficiência e proposta priorizada — 2026-08-24

**O que é este documento.** Não é um novo diagnóstico do zero — é uma auditoria de status: cada achado dos
três relatórios anteriores (`2026-08-23_geocode-diagnostico-performance.md`,
`2026-08-23_analise-pacote-desempenho-manutencao.md`, `2026-08-24_temp-view-benchmark.md`) foi verificado
contra o `HEAD` atual (código-fonte + `git log`), reclassificado em **feito / refutado / ainda aberto**, e
o item de maior impacto ainda aberto foi remedido nesta sessão para confirmar que a magnitude continua
válida. O resultado é uma lista única, priorizada, pronta para a próxima rodada de implementação.

**Metodologia da verificação:** leitura do código atual em `R/`, `git log --since="2026-08-23" -- R/` para
saber o que mudou, e duas rodadas de `Rprof()` frescas (HEAD atual, 20.028 endereços, cache local v0.4.1,
`n_cores = 7`) comparando cenário "todos os campos" vs. "só CEP/bairro/município/UF" — ver
`tests/tests_rafa/benchmark_empty_field_guard.R`.

---

## 1. Status de cada item conhecido

| # | item | status em 24/08 | evidência |
|---|---|---|---|
| 1 | Laço não pula etapas cujo campo-chave está **vazio** (só checa presença da coluna-fantasma) | **ainda aberto** | `geocode.R:417` inalterado; reconfirmado nesta sessão (§2 abaixo) |
| 2 | `pa01`/`pa02`/`pa03` recalculavam Jaro sem poder resolver nada | **corrigido** | commit `282c302` (24/08) — `match_types_jaro_redundante` em `utils.R:357`, guarda em `match_weighted_cases_probabilistic.R` |
| 3 | `FIRST()` sem `ORDER BY` em `da*`/`pa*` — não-determinismo | **ainda aberto** | `grep FIRST(` em `match_weighted_cases.R`/`match_weighted_cases_probabilistic.R`: nenhum tem `ORDER BY`; reconfirmado ao vivo em `2026-08-24_temp-view-benchmark.md` (4/20.028 linhas divergentes) |
| 4 | `CREATE TEMP VIEW` em vez de `TEMP TABLE` em `register_cnefe_table()` | **testado e refutado** | `2026-08-24_temp-view-benchmark.md` — piora 42% ponta a ponta apesar de melhorar a função isolada 3,5× |
| 5 | Baixar só as tabelas necessárias (corolário do #1) | **ainda aberto** | `geocode.R:312` chama `download_cnefe(tabela = 'todas')` sempre; `download_cnefe()` só aceita uma tabela por vez, não vetor |
| 6 | Os quatro `match_*` são ~80% código duplicado | **ainda aberto** | tamanhos inalterados: 116+152+148+187 linhas, nenhum commit de refactor desde 23/08 |
| 7 | Código morto em `register_cnefe_tables.R` (blocos comentados, funções sem chamador) | **ainda aberto** | 161 de 289 linhas (56%) são comentário, confirmado hoje; `cache_message()` e `register_geocodebr_tables()` continuam sem nenhum chamador |
| 7b | `T`/`F` em vez de `TRUE`/`FALSE` em `geocode_reverso.R` | **corrigido** | `grep \bT\b|\bF\b` não encontra mais ocorrência |

---

## 2. Reconfirmação do item #1 (maior impacto, ainda não aplicado)

O relatório de 23/08 mediu ganho de 3,3×–9× comparando código com bug vs. protótipo corrigido, numa
`git worktree` em outro commit (`a4b8036`). Para confirmar que o problema **continua com a mesma
magnitude no `HEAD` atual** (depois do fix do item #2, que também mexeu no mesmo laço), rodei duas
medições frescas com `Rprof()`, mesma amostra de 20.028 endereços, `n_cores = 7`:

| cenário | campos declarados | `geocode_core()` total | `register_cnefe_table` (tempo / % do total amostrado) |
|---|---|---|---|
| completo | logradouro, número, cep, localidade, município, estado | 5,05 s | 1,70 s / 37% |
| só CEP | cep, localidade, município, estado (sem logradouro/número) | 3,45 s | **1,82 s / 58%** |

**A materialização não cai quando os campos que a justificariam somem — ao contrário, sobe em proporção**
(37% → 58% do tempo total), porque o resto do trabalho (joins que não encontram nada) fica mais rápido
enquanto a materialização das 8 tabelas continua fixa, incluindo as duas maiores
(`municipio_logradouro_numero_*`, 1,19 GB juntas) que **não podem gerar nenhum match** quando não há
`logradouro`/`numero` no input. Isso confirma qualitativamente o achado de 23/08: o guarda em
`geocode.R:417` — `if (all(key_cols %in% names(input_padrao)))` — testa presença da coluna-fantasma, não
se ela tem algum valor utilizável, então nunca pula etapa nenhuma.

> A magnitude exata do ganho (3,3×–9×) não foi re-medida aqui porque isso exige aplicar o fix e comparar —
> o que é o próximo passo natural, não parte desta auditoria de status. O que esta rodada confirma é que a
> **causa continua intacta e o custo continua concentrado no mesmo lugar** no código atual.

---

## 3. Proposta priorizada (atualizada)

| # | mudança | ganho estimado | esforço | risco | depende de |
|---|---|---|---|---|---|
| **1** | Pular etapas de `match_type` cujo campo-chave está **vazio** (não só ausente) — `geocode.R:417` | 3,3×–9× quando faltam campos (reconfirmado §2); no-op quando não faltam | Muito baixo (~8 linhas) | Muito baixo | — |
| **2** | Fechar o não-determinismo: `ORDER BY` explícito nos `FIRST()` de `match_weighted_cases.R`/`match_weighted_cases_probabilistic.R` | reprodutibilidade exata; **pré-requisito para verificar qualquer refactor por igualdade de output** (inclusive #4 e #6 abaixo) | Muito baixo (patch já existe, medido em 23/08: sem custo de tempo) | Baixo — decisão pendente sobre semântica de `contagem_cnefe` (ver `analise-pacote-desempenho-manutencao.md` §4) | — |
| **3** | Baixar só as tabelas de referência necessárias (`download_cnefe()` aceitar vetor; `geocode()` calcular o subconjunto) | 1.492 MB → 20 MB no melhor caso (só CEP) | Médio (assinatura de `download_cnefe()` muda) | Baixo | Item 1 (mesmo cálculo de "quais campos têm valor") |
| **4** | Helper único para os quatro `match_*` (extrair montagem de `colunas_encontradas`) | manutenção — bugs already duplicados 2× no histórico (`logradouro_encontrado`, H3) | Médio | Médio — mexe no SQL dos quatro arquivos | Item 2 (para verificar que o refactor não muda resultado) |
| **5** | Remover código morto de `register_cnefe_tables.R` (161 linhas comentadas) + `cache_message()`/`register_geocodebr_tables()` sem chamador | manutenção | Muito baixo | Nenhum | — |
| — | `CREATE TEMP VIEW` em `register_cnefe_table()` | ~~1,5–7×~~ | — | — | **Refutado** (24/08) — piora 42% ponta a ponta; não retentar sem mudar de abordagem (ver nota em MEMORY.md) |

**Sequência sugerida:** 1 → 2 → 3, depois 4 e 5 numa passada de manutenção à parte. 1 é o maior ganho
absoluto e o mais barato; 2 não muda desempenho mas é o que destrava poder validar 3 e 4 por igualdade
exata de output (sem ele, qualquer comparação antes/depois tem ruído de ±1-4 linhas por `FIRST()`
arbitrário, como visto em §2 do relatório de hoje sobre TEMP VIEW).

---

## 4. O que fica fora deste documento

- A decisão de semântica do item #2 (se `contagem_cnefe` agregado deve ser `FIRST(... ORDER BY distância)`
  ou `SUM(...)`) é do mantenedor — está detalhada em
  `quality_reports/diagnoses/2026-08-23_analise-pacote-desempenho-manutencao.md` §4, não repetida aqui.
- `geocode_reverso()` e `busca_por_cep()` não foram reauditados nesta rodada — o escopo desta análise é
  `geocode()`.
- Efeito de escala (milhões de endereços, poucos municípios) não foi remedido — a nota de 23/08 sobre isso
  (§8) continua valendo: o peso relativo da materialização cai com mais endereços por município, mas o
  item #1 não muda de sinal (nunca faz sentido materializar uma tabela que não pode gerar match).

## Referências

- `quality_reports/diagnoses/2026-08-23_geocode-diagnostico-performance.md`
- `quality_reports/diagnoses/2026-08-23_analise-pacote-desempenho-manutencao.md`
- `quality_reports/diagnoses/2026-08-24_temp-view-benchmark.md`
- `tests/tests_rafa/benchmark_empty_field_guard.R` — script usado na reconfirmação do §2
