# Plano — Adaptar o workflow Claude Code para o geocodebr

**Status:** APROVADO — em execução
**Data:** 2026-08-22
**Escopo:** configuração do workflow apenas. Nenhuma alteração em `R/`, `tests/`, `man/` ou `NEWS.md`.

---

## Contexto

O workflow acadêmico (fork de `pedrohcgs/claude-code-my-workflow`) está instalado **globalmente** em
`~/.claude/` — 33 regras, ~52 skills, 18 agentes, hooks e `settings.json`. Ele é compartilhado com os
outros repositórios de pacotes R do usuário (`flightsbr`, `enderecobr`).

No `geocodebr`, porém, a adaptação nunca foi feita. O que existe hoje:

- `CLAUDE.md` é uma **cópia crua do template**, não rastreada pelo git, ainda cheia de placeholders
  (`[YOUR PROJECT NAME]`, `[YOUR INSTITUTION]`) e descrevendo um projeto de **slides Beamer/Quarto**:
  fala em `Slides/`, `Preambles/header.tex`, `scripts/sync_to_docs.sh`, paleta LaTeX↔SCSS. Nada disso
  existe aqui. Pior: ela instrui "Single source of truth — Beamer `.tex` é autoritativo", o que é
  simplesmente falso neste repositório (aqui quem manda é `R/`).
- Não existem `MEMORY.md`, `quality_reports/` nem `templates/` — ou seja, as três regras sempre ativas
  (`plan-first-workflow`, `session-logging`, `orchestrator-protocol`) apontam para diretórios inexistentes.
- `~/.claude/settings.json` lista `flightsbr` e `enderecobr` como repositórios confiáveis no bloco
  `autoMode.environment`. O `geocodebr` **não está lá**.

Os repositórios irmãos `flightsbr` e `enderecobr` já passaram por essa adaptação e servem de padrão
comprovado. O objetivo aqui é chegar ao mesmo estado, com as particularidades do `geocodebr`:
pacote CRAN em produção (v0.6.4, dev 0.6.4.900), pt-BR, com backend DuckDB/Arrow e hooks pre-commit.

---

## Decisões já tomadas (respostas do usuário)

| Questão | Decisão |
|---|---|
| Rastrear o scaffolding no git? | **Sim** — `CLAUDE.md`, `MEMORY.md`, `templates/`, `quality_reports/` versionados (padrão flightsbr/enderecobr). `.claude/` fica local. |
| Idioma | **Português em tudo** — inclusive `CLAUDE.md`, `MEMORY.md`, planos e logs de sessão. (Diverge dos repos irmãos, que estão em inglês; é intencional.) |
| Regras globais que não se aplicam | **Path-scope global** de `meta-governance.md` e `cross-artifact-review.md`. |
| Inconsistências encontradas no repo | **Adiar** — documentadas na seção "Achados adiados" abaixo. |

---

## Bloco 1 — Reescrever `CLAUDE.md` (pt-BR)

Substituir integralmente o template de slides. Alvo: ~170 linhas, seguindo a estrutura do
`enderecobr/CLAUDE.md` (que é o irmão mais próximo — também pt, também dependência deste pacote).

Seções:

1. **Cabeçalho** — projeto, mantenedor (Rafael H. M. Pereira, Ipea), repo `ipeaGIT/geocodebr`, branch `main`,
   e a nota de que `Language: pt` na DESCRIPTION obriga conteúdo voltado ao usuário em pt-BR.
2. **Princípios centrais** — plano primeiro; `R/` é autoritativo (`man/` e `NAMESPACE` são **gerados** por
   roxygen2, nunca editar à mão); o portão de release é `R CMD check --as-cran` com 0 erros / 0 warnings e
   toda NOTE justificada em `cran-comments.md`; **todo texto voltado ao usuário em pt-BR** (NEWS.md, blocos
   roxygen, mensagens `cli`, vignettes, README); `[LEARN:categoria]` → `MEMORY.md`.
3. **Estrutura de pastas** — a real deste repo (`R/`, `tests/testthat/` com `_snaps/`, `man/roxygen/templates/`,
   `inst/extdata/`, `vignettes/`, `pkgdown/`, `python-package/` que hoje é só um `placeholder.txt`).
4. **Comandos** — `devtools::document()`, `devtools::test()`, `devtools::check(args = "--as-cran")`,
   `covr::package_coverage()`, `pkgdown::build_site()`, e o equivalente shell `R CMD build . && R CMD check --as-cran`.
5. **Portão de qualidade** — tabela de barras (check as-cran, testes, cobertura de funções exportadas, roxygen
   completo). Mais a **nota crítica sobre `/commit`**: os Steps 0 e 0b da skill global chamam
   `scripts/quality_score.py` e `scripts/check-surface-sync.sh`, que **não existem neste repo** — devem ser
   pulados, exatamente como já está documentado em `flightsbr/CLAUDE.md` e `enderecobr/CLAUDE.md`.
6. **Hooks pre-commit do repo** (`.pre-commit-config.yaml`) — `readme-rmd-rendered` exige regenerar `README.md`
   a partir de `README.Rmd`; `codemeta-description-updated` exige atualizar `codemeta.json` sempre que a
   `DESCRIPTION` mudar; mais o hook `pkgdown`. Isso não está documentado em lugar nenhum hoje e é uma fonte
   garantida de commit rejeitado.
7. **Skills vivas aqui** — `/r-package-check` (o portão), `/code-review`, `/security-review`, `/commit`
   (com Step 0/0b pulados), `/diagnose`, `/checkpoint`, `/context-status`, `/learn`, `/promote-memory`.
   Deixar explícito que as ~40 skills de paper/slide/lecture ficam dormentes.
8. **Funções exportadas** — tabela das 9: `geocode()`, `geocode_reverso()`, `busca_por_cep()`,
   `definir_campos()`, `download_cnefe()`, `definir_pasta_cache()`, `deletar_pasta_cache()`,
   `listar_pasta_cache()`, `listar_dados_cache()`.
9. **Arquitetura interna** — o mapa que hoje só existe na cabeça de quem escreveu:
   - `geocode()` roda seu corpo dentro de `callr::r()` (isolamento de processo — relevante para depuração:
     um `browser()` no corpo não funciona como se espera);
   - backend DuckDB + Arrow/Parquet (`create_geocodebr_db.R`, `register_cnefe_tables.R`);
   - match **determinístico** (`match_cases.R`) vs. **probabilístico** por similaridade de Jaro
     (`match_cases_probabilistic.R`, `string_dist.R`), com interpolação ponderada em
     `match_weighted_cases*.R` e desempate em `trata_empates_geocode_duckdb.R`;
   - cache versionado por *data release* via `tools::R_user_dir()` (`cache.R`).
10. **Fontes da verdade que NÃO devem ser duplicadas** — a taxonomia de `precisao` / `tipo_resultado` /
    `desvio_metros` vive em `man/roxygen/templates/precision_section.R`; a regra de desempate vive em
    `man/roxygen/templates/empates_section.R`. O `CLAUDE.md` **aponta** para esses arquivos em vez de copiá-los
    (evita a divergência entre duas cópias da mesma informação — mesmo anti-padrão que o `flightsbr/CLAUDE.md`
    já evita com as URLs da ANAC). Antes de adicionar um parâmetro novo, checar se já existe `@template`
    correspondente em `man/roxygen/templates/`.
11. **Notas sobre CNEFE / IBGE** — registrar quirks (mudanças de schema, URLs quebradas, codificação,
    cadência de publicação) como entradas `[LEARN:cnefe]` no `MEMORY.md`, em vez de re-derivá-las a cada sessão.

## Bloco 2 — Criar `MEMORY.md` + `quality_reports/` + `templates/`

- **`MEMORY.md`** — cabeçalho curto em pt-BR explicando o contrato `[LEARN:categoria] errado → certo`,
  e vazio de conteúdo (sem herdar a memória do template, que é sobre o desenvolvimento do próprio workflow
  e não sobre o geocodebr).
- **`quality_reports/`** com `plans/`, `specs/`, `session_logs/`, `merges/`, `diagnoses/` — cada uma com
  `.gitkeep` para que os diretórios existam no clone (as regras sempre ativas escrevem neles).
  Este próprio arquivo de plano já vive em `quality_reports/plans/`.
- **`templates/`** — os três templates de `flightsbr/templates/` (`session-log.md`, `requirements-spec.md`,
  `quality-report.md`), **traduzidos para pt-BR** e com o `quality-report.md` adaptado ao portão real daqui
  (check as-cran, testes, cobertura, achados do agente `r-package-reviewer`).

## Bloco 3 — `.Rbuildignore` (obrigatório, não opcional)

Arquivos no topo do diretório-fonte entram no tarball do `R CMD build` **mesmo sem estarem no git**. Sem isso,
a próxima submissão CRAN ganha uma NOTE de "non-standard files at top level" — ou seja, este bloco é o que
impede a adaptação do workflow de quebrar o portão de release.

Acrescentar (regex ancorados, no estilo das entradas já existentes):

```
^\.claude$
^quality_reports$
^templates$
^CLAUDE\.md$
^MEMORY\.md$
```

## Bloco 4 — `.gitignore` e `.claude/settings.local.json`

- `.gitignore`: acrescentar `.claude/settings.local.json` (config de máquina, não versionada — mesmo padrão
  dos repos irmãos, onde `.claude/` não é rastreado).
- Criar `.claude/settings.local.json` com um conjunto **estreito** de permissões `Bash` para comandos R
  somente-leitura do dia a dia (`Rscript -e "devtools::test()"`, `devtools::document()`, `R CMD build`,
  `covr::package_coverage()`), reduzindo prompts repetidos. Nada destrutivo entra na allowlist.

## Bloco 5 — Corrigir o path-scoping global em `~/.claude/rules/`

Duas regras carregam em **toda** sessão de **todos** os repositórios sem se aplicarem a nenhum deles hoje.
Auditei o frontmatter das 33 regras e a causa é concreta:

- **`cross-artifact-review.md`** declara `globs:` + `alwaysApply: false` — chaves no estilo Cursor que **este
  harness ignora**. As outras 27 regras com escopo usam `paths:`, e nenhuma delas carregou nesta sessão;
  esta carregou. **Correção:** renomear a chave `globs:` → `paths:`, preservando os mesmos padrões
  (`*.tex`, `*.qmd`, `Slides/**`, `master_supporting_docs/**`). Nenhuma linha de conteúdo muda.
- **`meta-governance.md`** não tem frontmatter algum. É a regra que declara "este repositório é ao mesmo tempo
  um projeto e um template para terceiros" — verdade para o repo do workflow, falso para o geocodebr.
  **Correção:** adicionar `paths: [".claude/**"]`, para que só carregue quando se estiver mexendo na própria
  infraestrutura do workflow.

Também em `~/.claude/settings.json`: acrescentar o `geocodebr` ao bloco `autoMode.environment` como repositório
confiável (`R:\Dropbox\git\geocodebr` ↔ `https://github.com/ipeaGIT/geocodebr`, público, pacote CRAN), com a
área de trabalho normal sendo `R/`, `tests/testthat/`, `man/`, `vignettes/`, `quality_reports/`. Hoje só
`flightsbr` e `enderecobr` estão listados.

> Estas são as **únicas** alterações fora do repositório. Ambas são aditivas e reversíveis; nenhum conteúdo
> de regra é apagado.

---

## Arquivos

**Criados:** `MEMORY.md`, `templates/{session-log,requirements-spec,quality-report}.md`,
`quality_reports/{plans,specs,session_logs,merges,diagnoses}/.gitkeep`, `.claude/settings.local.json`

**Modificados:** `CLAUDE.md` (reescrita integral), `.Rbuildignore`, `.gitignore`,
`~/.claude/rules/cross-artifact-review.md` (1 chave de frontmatter),
`~/.claude/rules/meta-governance.md` (+3 linhas de frontmatter),
`~/.claude/settings.json` (bloco `autoMode.environment`)

**Intocados:** `R/`, `tests/`, `man/`, `NAMESPACE`, `DESCRIPTION`, `NEWS.md`, `cran-comments.md`, `vignettes/`

---

## Verificação

1. **O tarball fica limpo** (o teste que importa — confirma que o Bloco 3 funcionou):
   ```bash
   R CMD build . && tar -tzf geocodebr_0.6.4.900.tar.gz | grep -iE "claude|quality_reports|templates|MEMORY"
   ```
   Esperado: **nenhuma saída**. Se algo aparecer, o `.Rbuildignore` está errado.
2. **O path-scoping funcionou**: numa sessão nova neste repo, `meta-governance` e `cross-artifact-review`
   não devem mais aparecer no contexto. Verificação imediata e barata: reler o frontmatter dos dois arquivos
   e confirmar a chave `paths:`; a confirmação definitiva vem na próxima sessão.
3. **Sem regressão no pacote**: `devtools::test()` deve continuar passando exatamente como antes
   (nenhum arquivo de código foi tocado — é uma checagem de sanidade, não uma expectativa de mudança).
4. **Coerência interna do `CLAUDE.md`**: cada caminho e cada comando citados existem de fato — verificar
   um a um antes de fechar a tarefa.
5. `R CMD check --as-cran` completo **não** será rodado neste passo (leva ~4 min e nenhum código mudou);
   o passo 1 cobre o risco real introduzido aqui.

---

## Achados adiados (não serão tocados agora)

Encontrados durante a exploração. Registrados para não se perderem; cada um é uma correção pequena e
independente, a ser feita quando você quiser:

1. **URLs da `DESCRIPTION` desatualizadas** — apontam para `github.com/ipea/geocodebr` e
   `ipea.github.io/geocodebr/`, mas o remote real é `ipeaGIT/geocodebr` e o `pkgdown/_pkgdown.yml` usa
   `ipeagit.github.io/geocodebr/`. Hoje funciona só por causa do redirecionamento do GitHub. Metadado CRAN —
   vale corrigir antes da próxima submissão. (Os links de issue no `NEWS.md` têm a mesma divergência.)
2. **`inst/CITATION` obsoleto** — declara `version = "v0.1.0"` e `year = 2025`, com o pacote em v0.6.4.
   Além disso lista apenas dois autores, enquanto a `DESCRIPTION` tem três `aut`.
3. **`.gitignore` com resíduo de copy-paste** — a linha `censobr_*.tar.gz` deveria ser `geocodebr_*.tar.gz`.
   Consequência concreta: o tarball gerado pelo `R CMD build` **não** está sendo ignorado hoje.
4. **`.Rbuildignore` com entradas mortas** — `^data_prep`, `^tests_rafa$`, `^tests_pedro$` referenciam
   diretórios que não existem mais. Inofensivo, mas é ruído.

## Fora de escopo

- Qualquer alteração em código, testes ou documentação do pacote.
- `AGENTS.md` (o espelho do `CLAUDE.md` para o Codex, que o `flightsbr` tem e o `enderecobr` não) — não será
  criado. Diga se quiser, é barato.
- Commit/push. Ao final apresento o diff; o commit só acontece com `/commit` explícito.
