
# Plano — Reorganização em monorepo (`r-package/` + `python-package/`)

**Status:** DRAFT
**Data:** 2026-08-25

## Contexto

Hoje o pacote R vive na raiz do repositório (`DESCRIPTION`, `R/`, `man/`, `tests/`, `vignettes/` etc.
todos no topo). O plano do projeto é que o repositório vire um monorepo com uma implementação em R
(`r-package/`) e, futuramente, uma em Python (`python-package/`, hoje só um placeholder). Esta mudança
prepara o terreno para o porte Python sem misturar os dois pacotes na raiz, e sem quebrar o CI do R
(`R CMD check`, cobertura, pkgdown) durante a transição.

**Decisão já tomada com o usuário:** README/LICENSE completos passam a viver dentro de `r-package/`
(é o que `pkgdown`/CRAN esperam, com paths relativos a `man/`, `vignettes/`); a raiz ganha um
`README.md` novo, curto, escrito à mão, descrevendo o repo como um todo e apontando para
`r-package/` e `python-package/`. `LICENSE` fica duplicado (raiz, para o GitHub detectar a licença
automaticamente; `r-package/LICENSE`, porque `DESCRIPTION` declara `License: MIT + file LICENSE`
relativo à raiz do pacote).

**Validado contra o sister package `ipeaGIT/geobr`** (mesmo layout `r-package/` + `python-package/`,
já em produção): o padrão `working-directory: r-package` nas actions `r-lib/actions@v2` está
confirmado funcionando (não é mais uma hipótese a testar), o que simplifica a seção de workflows
abaixo. A única divergência deliberada em relação ao geobr é o `LICENSE`: o geobr não duplica (só
existe dentro de `r-package/`), mas o usuário confirmou manter a duplicação (raiz + `r-package/`)
neste projeto, pelo badge de licença automático do GitHub na landing page.

## Princípio geral: o que muda de lugar vs. o que fica na raiz

**Fica na raiz** (compartilhado entre R e Python, ou específico de ferramentas que só funcionam na
raiz do repo Git):

- `.git/`, `.github/` (workflows — conteúdo editado, local não muda)
- `.claude/`, `CLAUDE.md`, `MEMORY.md`, `quality_reports/`, `templates/` — infraestrutura de workflow,
  compartilhada pelos dois pacotes
- `.pre-commit-config.yaml` — pre-commit só lê um config por repositório, na raiz
- `codecov.yml` — o backend do Codecov busca esse arquivo em paths fixos na raiz (`codecov.yml`,
  `.codecov.yml`, `.github/codecov.yml`); mover quebraria os status checks silenciosamente
- `LICENSE` — mantido também na raiz (GitHub usa para detectar a licença do repo), duplicado dentro
  de `r-package/`
- `README.md` — novo arquivo, curto, escrito à mão (não gerado de `.Rmd`)
- `.gitignore`, `python-package/` (já existe, intocado)

**Muda para dentro de `r-package/`** (tudo que é específico do pacote R e que `devtools`/`pkgdown`/CRAN
esperam encontrar relativo à raiz do pacote):

```
DESCRIPTION, NAMESPACE, NEWS.md, cran-comments.md, CRAN-SUBMISSION, codemeta.json,
.Rbuildignore, geocodebr.Rproj,
R/, man/, tests/, vignettes/, inst/, pkgdown/,
README.Rmd, README.md (a versão completa, com badges/logo), LICENSE (cópia)
```

Todo `git mv` preserva histórico de cada arquivo (`git mv` grava como rename quando o conteúdo não
muda, então `git log --follow` continua funcionando).

## Arquivos que precisam de conteúdo editado (não só movidos)

### 1. `r-package/.Rbuildignore`

Remover as linhas que hoje excluem coisas que, depois da mudança, já ficam fora da árvore do pacote
por definição (não precisam mais de ignore): `^\.github$`, `^\.claude$`, `^quality_reports$`,
`^templates$`, `^CLAUDE\.md$`, `^MEMORY\.md$`, `^python-package$`, `^\.pre-commit-config\.yaml$`.
Manter as que continuam relevantes dentro de `r-package/`: `^.*\.Rproj$`, `^\.Rproj\.user$`,
`^tests_rafa$`, `^tests_pedro$` (ajustar path se necessário — hoje já não batem com
`tests/tests_rafa`, ver nota de risco abaixo), `^data_prep`, `^CRAN-SUBMISSION$`,
`^cran-comments\.md$`, `^docs$`, `.Rhistory`, `.RData`, `^_pkgdown\.yml$`, `^pkgdown$`,
`^README\.Rmd$`, `^codemeta\.json$`.

### 2. Novo `README.md` na raiz (curto, manual)

Título do projeto, uma frase sobre o CNEFE/geocodificação, e uma tabela/lista apontando para
`r-package/` (com link pro README completo) e `python-package/` (nota "em desenvolvimento").

### 3. `CLAUDE.md` (raiz)

Reescrever a seção "Estrutura de pastas" e "Comandos" prefixando os paths do pacote R com
`r-package/` (ex.: `r-package/R/`, `cd r-package && R CMD build .`, `devtools::document()` continua
igual em R mas assumindo `setwd("r-package")` ou `devtools::document("r-package")`). Atualizar a nota
sobre hooks pre-commit (paths passam a ser `r-package/README.Rmd`, `r-package/codemeta.json`) e a
nota sobre `/r-package-check` (a skill já autodetecta a raiz do pacote via `DESCRIPTION` — só
documentar que agora é `r-package/`, não a raiz do repo).

### 4. `.github/workflows/*.yaml`

Padrão comum, **copiado diretamente do `geobr` (`r-package/.github/workflows/`), já validado em
produção**: adicionar `working-directory: r-package` nos steps que hoje rodam implicitamente na raiz
do pacote (`setup-r-dependencies`, `check-r-package`, e os `run:`/`shell: Rscript` que chamam
`Rscript`/`git add`), e restringir o trigger com `paths: [r-package/**, .github/workflows/<arquivo>]`
para que mudanças em `python-package/` (ou em `quality_reports/`, `.claude/` etc.) não disparem o CI
do R à toa — mesmo padrão que o `python-package` vai usar no dia em que ganhar seu próprio CI.

| Workflow | Mudança |
|---|---|
| `check.yaml` | trigger ganha `paths: [r-package/**, .github/workflows/check.yaml]`; `setup-r-dependencies` e `check-r-package` ganham `working-directory: r-package` |
| `check_as_cran.yaml` | idem |
| `pkgdown.yaml` | trigger ganha `paths: [r-package/**, .github/workflows/pkgdown.yaml]`; `setup-r-dependencies` (`local::.`) e o step de deploy ganham `working-directory: r-package` — **sem** o truque de copiar README pra `index.md` que o geobr usa: no nosso caso o README completo já mora dentro de `r-package/`, então o pkgdown acha `r-package/README.md` sozinho |
| `readme_rmd.yaml` | trigger `paths:` passa a `r-package/README.Rmd`; steps de render e commit ganham `working-directory: r-package`; `git add README.md` vira `git add r-package/README.md` |
| `test-coverage.yaml` | trigger ganha `paths: [r-package/**, .github/workflows/test-coverage.yaml]`; `setup-r-dependencies` e o step "Test coverage" ganham `working-directory: r-package`; `file: ./cobertura.xml` vira `file: r-package/cobertura.xml`; adicionar `flags: r` e `name: codecov-r` no step do `codecov-action` (evita colisão com a cobertura do Python quando `python-package/` ganhar a sua) |
| `rhub.yaml` | **fora de escopo por ora** — o próprio `geobr` não tem esse workflow no monorepo (não migraram); mantemos o nosso como está, workflow manual (`workflow_dispatch`), e testamos separadamente se algum dia for usado de fato |

### 5. `.pre-commit-config.yaml`

Os três hooks (`readme-rmd-rendered`, `codemeta-description-updated`, `pkgdown`) vêm de
`lorenzwalthert/precommit` e presumem, por padrão, que o pacote R está na raiz do repo — ver item 1 da
seção de riscos abaixo.

## Riscos / pontos a verificar depois da mudança (não bloqueiam o plano, mas precisam de teste real)

1. **Hooks do `pre-commit`** (`readme-rmd-rendered`, `codemeta-description-updated`, `pkgdown`, de
   `lorenzwalthert/precommit`) — diferente do item acima (já validado via `geobr`), não achei
   confirmação de que esses hooks aceitam pacote fora da raiz do repo. Plano: testar
   `pre-commit run --all-files` depois da mudança; se não acharem o pacote em `r-package/`, trocar por
   hooks locais (`language: system`, `entry: bash -c 'cd r-package && Rscript -e ...'`) que fazem o
   mesmo trabalho com `cd` explícito.
2. **`rhub.yaml`** — as actions `r-hub/actions/setup-deps@v1` e `run-check@v1` foram desenhadas pra
   pacote na raiz; não está claro se aceitam um path customizado, e o `geobr` simplesmente não tem
   esse workflow no monorepo. Como é workflow manual (`workflow_dispatch`), não bloqueia o CI
   principal — testar separadamente depois, e se necessário trocar por um job customizado
   (`checkout` + `cd r-package` + `R CMD check` direto, sem as actions empacotadas do r-hub).
3. **`^tests_rafa$` / `^tests_pedro$` no `.Rbuildignore`** — esses padrões hoje começam com `^` e
   provavelmente **já não batem** com o path real `tests/tests_rafa` (regex ancorada no início da
   string relativa à raiz do pacote, que é `tests/tests_rafa`, não `tests_rafa`). Isso é um problema
   pré-existente, não introduzido por este reorg — mas vale corrigir para `^tests/tests_rafa$` e
   `^tests/tests_pedro$` já que estamos mexendo no arquivo.
4. **Codecov** — se o Codecov App do repositório estiver configurado com um "YAML path" customizado
   apontando pra raiz (configuração no site codecov.io, fora do repo), isso já está coberto por manter
   `codecov.yml` na raiz. Só checar depois que o primeiro relatório de cobertura pós-mudança aparece
   corretamente no PR.

## Ordem de execução (tudo num commit/PR único, pra não deixar o CI quebrado no meio do caminho)

1. `git mv` de todos os arquivos/pastas listados acima para dentro de `r-package/`
2. Criar `r-package/LICENSE` (cópia do `LICENSE` da raiz) e manter o da raiz
3. Editar `r-package/.Rbuildignore` (remover linhas obsoletas, corrigir `tests_rafa`/`tests_pedro`)
4. Criar o novo `README.md` da raiz (curto, manual)
5. Editar os 5 workflows de `.github/workflows/` (exceto `rhub.yaml`, que fica marcado como
   "verificar separadamente" num comentário no topo do arquivo)
6. Editar `CLAUDE.md` (estrutura de pastas + comandos)
7. Rodar localmente: `devtools::document("r-package")`, `devtools::test("r-package")`,
   `Rscript -e 'pkgdown::build_site("r-package")'` — confirmar que tudo builda do novo local antes de
   commitar
8. Commit único, push numa branch (não `main`), abrir PR — deixar os workflows do GitHub Actions
   rodarem de verdade contra o PR antes de mergear (é a única forma de validar os itens de risco 1–3)

## Verificação

- `devtools::check("r-package", args = "--as-cran")` local, 0 erros/0 warnings
- PR aberto: os 5 workflows principais (`check`, `check_as_cran`, `pkgdown`, `readme_rmd`,
  `test-coverage`) verdes
- `pkgdown::build_site("r-package")` local gera `r-package/docs/index.html` com o README certo
- `pre-commit run --all-files` local passa (ou hooks trocados por versão local se não passar)
- Conferir que a landing page do GitHub (`github.com/ipeaGIT/geocodebr`) mostra o novo `README.md`
  curto da raiz corretamente
