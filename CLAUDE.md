# CLAUDE.md — geocodebr

**Projeto:** geocodebr — geolocalização de endereços brasileiros, baseado no CNEFE
(Cadastro Nacional de Endereços para Fins Estatísticos), publicado pelo IBGE. Geocodificação em massa,
sem limite de consultas, a partir de dados abertos. **Monorepo com dois pacotes**: o pacote R vive em
`r-package/` (estável, no CRAN) e o pacote **Python** em `python-package/` (versão de testes, `0.1.0`,
ainda não publicado no PyPI). **Regra básica do projeto: paridade de resultado entre os dois pacotes** —
aplicados à mesma base de input, R e Python devem produzir output idêntico (ver "Paridade R ↔ Python").
Salvo indicação contrária, a documentação abaixo se refere ao pacote R; a seção "Pacote Python" cobre o porte.
**Mantenedor:** Rafael H. M. Pereira (aut, cre — Ipea) · **Autores:** Daniel Herszenhut, Gabriel Garcia de Almeida
· **Mantenedores do porte Python:** Camila Gonçalves de Brito, Jefferson Silva dos Anjos
**Financiamento/copyright:** Ipea; ITpS — Instituto Todos pela Saúde
**Repo:** https://github.com/ipeaGIT/geocodebr · **Branch:** main · **Versão R:** 0.6.4 (dev 0.6.4.900) ·
**Versão Python:** 0.1.0 (alpha; mesclado na `main` em 21/09/2026 via PR #109, `416f006`)
**Idioma:** `Language: pt` na DESCRIPTION — NEWS.md, blocos roxygen, mensagens de erro/aviso, vignettes e
README são em **português**. Todo conteúdo voltado ao usuário deve seguir isso — nos dois pacotes
(docstrings, mensagens `cli`/`warnings` e README do Python também em pt-BR).

---

## Princípios centrais

- **Plano primeiro** — entrar em plan mode antes de tarefas não triviais; salvar planos em `quality_reports/plans/`
- **`R/` é autoritativo** — `man/` (documentação) e `NAMESPACE` são **gerados** pelo roxygen2. Nunca editar
  à mão; editar os blocos roxygen em `R/` e rodar `devtools::document()`
- **O portão de release é `R CMD check --as-cran`** — 0 erros, 0 warnings, e toda NOTE restante justificada
  em `cran-comments.md`. Rodar via `/r-package-check` antes de qualquer release ou merge que toque
  `R/`, `tests/` ou `DESCRIPTION`
- **Paridade R ↔ Python é invariante do projeto** — a mesma base de input tem que produzir o mesmo
  output nos dois pacotes: mesmas colunas, mesmas linhas, mesmo `tipo_resultado`/`precisao`, mesmas
  coordenadas. Toda mudança de lógica em `r-package/R/` precisa ser espelhada em
  `python-package/geocodebr/` (e vice-versa) no mesmo PR, e `pytest -m r_parity` tem que passar.
  Uma otimização que muda o resultado num pacote só **não** é aceitável até o outro acompanhar
- **Português no que o usuário vê** — NEWS.md, roxygen, mensagens `cli`, vignettes e README em pt-BR.
  Comentários internos de código podem ser em pt ou en, mas siga o padrão do arquivo em que está mexendo
- **`[LEARN]`** — quando corrigido, ou quando uma abordagem não óbvia for confirmada, gravar
  `[LEARN:categoria] errado → certo` em [MEMORY.md](MEMORY.md)

Contexto entre sessões vive em [MEMORY.md](MEMORY.md); planos, specs e logs de sessão em
[quality_reports/](quality_reports/). As regras, skills e agentes do workflow estão configurados globalmente
em `~/.claude` (compartilhados com flightsbr / enderecobr) e chegam aqui por path-scoping — veja
"Skills vivas aqui" abaixo para o que de fato opera neste repo.

---

## Estrutura de pastas

Monorepo: infraestrutura de workflow e CI compartilhada na raiz; cada linguagem no seu próprio
subdiretório. Salvo indicação contrária, o resto deste arquivo se refere ao pacote R.

```
geocodebr/
├── CLAUDE.md                     # Este arquivo
├── MEMORY.md                     # Aprendizados [LEARN] entre sessões
├── README.md                     # Landing page do repo: tabela de badges R | Python, instalação dos dois
├── LICENSE                       # Duplicado em r-package/LICENSE (CRAN exige relativo à raiz do pacote)
├── codecov.yml                   # Fica na raiz — é onde o backend do Codecov procura por padrão
├── .github/workflows/            # R: check, check_as_cran, pkgdown, readme_rmd, rhub, test-coverage
│                                  # Python: python-check, python-parity, python-deterioracao, python-publish-pypi
├── quality_reports/               # Planos, specs, logs de sessão, relatórios de merge, diagnoses
│                                  #   único lugar certo; r-package/quality_reports/ é resíduo de uma
│                                  #   sessão rodada com cwd em r-package/ (limpar)
├── templates/                    # Templates de log de sessão / spec / relatório de qualidade
├── python-package/                # O pacote Python geocodebr (ver "Pacote Python")
│   ├── pyproject.toml / uv.lock   # hatchling; deps: duckdb, pyarrow, polars, enderecobr, h3, requests
│   ├── README.md                  # README do pacote Python, em pt-BR
│   ├── LICENSE.txt
│   ├── geocodebr/                 # Fonte do pacote (mapa módulo ↔ arquivo R na seção "Pacote Python")
│   ├── tests/                     # pytest; test_r_python_parity.py é o teste de paridade R ↔ Python
│   ├── benchmarks/                # Scripts de deterioração/heap no Windows + resultados
│   └── exemplos/                  # geocode_enderecos.py, busca_por_cep.py, geocode_reverso.py
└── r-package/                     # O pacote R {geocodebr} — raiz de tudo que segue abaixo
    ├── DESCRIPTION / NAMESPACE    # Metadados / exports GERADOS (nunca editar NAMESPACE à mão)
    ├── NEWS.md                    # Changelog voltado ao usuário, em pt-BR (bump por release)
    ├── cran-comments.md           # Notas de submissão CRAN (justificativa de cada NOTE)
    ├── CRAN-SUBMISSION            # Registro da última submissão (versão, data, SHA)
    ├── codemeta.json              # GERADO — precisa ser atualizado quando a DESCRIPTION muda
    ├── LICENSE                    # Cópia de LICENSE na raiz — exigido pelo CRAN dentro do pacote
    ├── README.Rmd / README.md     # README completo do pacote (badges, instalação, exemplos)
    ├── R/                         # Fonte do pacote (ver "Arquitetura interna")
    ├── tests/
    │   ├── testthat/              # testthat edition 3, incl. _snaps/ para texto de mensagens
    │   └── tests_rafa/, tests_pedro/  # scripts de bancada/benchmark, fora do build (.Rbuildignore)
    ├── man/
    │   ├── *.Rd                   # GERADOS — editar o roxygen em R/
    │   └── roxygen/templates/     # @template compartilhados (cache, verboso, n_cores, h3_res, ...)
    ├── inst/
    │   ├── CITATION                # Como citar o pacote
    │   └── extdata/                 # Amostras: small_sample.csv, large_sample.parquet, pontos.rds,
    │                                 #   munis_bbox_2022.parquet, states_bbox.rds
    ├── vignettes/                  # geocodebr.Rmd, geocode.Rmd, geocode_reverso.Rmd
    └── pkgdown/_pkgdown.yml        # Config do site pkgdown
```

---

## Comandos

O pacote R vive em `r-package/` — rode os comandos abaixo com `r-package` como diretório de trabalho
(`setwd("r-package")` ou abra `r-package/geocodebr.Rproj`), ou passe o path explicitamente
(`devtools::document("r-package")`).

```r
# Regenerar docs + NAMESPACE após editar blocos roxygen em R/
devtools::document("r-package")

# Rodar a suíte de testes
devtools::test("r-package")

# Check completo de prontidão CRAN (lento, ~4 min — rodar em background em execuções longas)
devtools::check("r-package", args = "--as-cran")

# Cobertura de testes
covr::package_coverage("r-package")

# Construir o site pkgdown
pkgdown::build_site("r-package")
```

```bash
# Equivalente local ao check da CI
cd r-package && R CMD build . && R CMD check --as-cran geocodebr_*.tar.gz
```

**Submissão CRAN:** atualizar `r-package/NEWS.md` + bump da `Version` na `r-package/DESCRIPTION`,
atualizar `r-package/cran-comments.md` com justificativa para cada NOTE restante, e então
`devtools::release("r-package")` (só o mantenedor, não automatizado).

### Pacote Python

O pacote Python vive em `python-package/` e usa `uv` (lockfile `uv.lock`). Rode com `python-package`
como diretório de trabalho.

```bash
cd python-package
uv sync --frozen --extra geo            # instala deps (extra geo = geopandas, p/ geocode_reverso e resultado_gpd)
uv run pytest -q -m "not r_parity"      # suíte unitária: parquets sintéticos, não baixa o CNEFE (~160 testes)
uv run pytest -m r_parity -q            # PARIDADE R ↔ Python: exige Rscript no PATH, instala o pacote R local
                                         # em lib temporária e pode baixar o CNEFE (>1 GB). Pulado sem Rscript
uv run python exemplos/geocode_enderecos.py
python -m geocodebr._heap_patch         # Windows: gera python-geocodebr-sh.exe com Segment Heap (ver README)
```

Não há `R CMD check` equivalente: o portão do Python é `pytest` unitário verde na matriz de CI
(`python-check.yaml`: Ubuntu/macOS/Windows × Python 3.10–3.14) **e** `pytest -m r_parity` verde
(`python-parity.yaml`). Publicação no PyPI via `python-publish-pypi.yaml` (ainda não usada).

---

## Hooks pre-commit deste repo

`.pre-commit-config.yaml` usa `lorenzwalthert/precommit` com três hooks que **rejeitam o commit** se ignorados:

| Hook | O que exige |
|---|---|
| `readme-rmd-rendered` | `r-package/README.md` regenerado a partir de `r-package/README.Rmd` — nunca editar o `.md` direto |
| `codemeta-description-updated` | `r-package/codemeta.json` atualizado sempre que a `r-package/DESCRIPTION` mudar (`codemetar::write_codemeta()`) |
| `pkgdown` | Config do pkgdown consistente com as funções exportadas |

Ou seja: mexeu na `DESCRIPTION`, atualize o `codemeta.json`; mexeu no `README.Rmd`, renderize o `README.md`
(ambos dentro de `r-package/`). O `.pre-commit-config.yaml` continua na raiz do repo — pre-commit só lê
um config por repositório — mas os três hooks operam sobre os arquivos de `r-package/`.

---

## Portão de qualidade

| Verificação | Barra |
|---|---|
| `R CMD check --as-cran` | 0 erros, 0 warnings, cada NOTE explicada em `cran-comments.md` |
| `devtools::test()` | Todos passando; toda função exportada com ao menos um teste |
| Cobertura (`covr`) | Nenhuma função exportada em 0% |
| Docs roxygen | Toda função exportada: `@param` (todos os args), `@return`, `@examples` executável |
| Matriz de CI | Windows, macOS e Ubuntu (devel/release/oldrel) verdes — `.github/workflows/check.yaml` |
| **Paridade R ↔ Python** | `pytest -m r_parity` verde (`python-parity.yaml`) sempre que `r-package/R/**` ou `python-package/geocodebr/**` mudar |
| Python: `pytest -m "not r_parity"` | Todos passando na matriz `python-check.yaml` (3 SOs × Python 3.10–3.14) |
| Python: docstrings | Toda função pública com docstring em pt-BR cobrindo todos os argumentos e o retorno |

Padrão completo: `r-package-conventions.md` (regra global, path-scoped para `R/**/*.R`, `tests/**/*.R`,
`man/**/*.Rd`, `DESCRIPTION`, `NAMESPACE`, `NEWS.md` — esses globs continuam batendo com os arquivos
agora que vivem em `r-package/R/**/*.R` etc., mas ainda não foi confirmado com um teste real; se a regra
parar de disparar, o glob path-scoped precisa ser ajustado em `~/.claude/rules/r-package-conventions.md`).

**Nota sobre `/commit`:** os Steps 0 e 0b da skill global chamam `scripts/quality_score.py` e
`scripts/check-surface-sync.sh` — construídos para o projeto-template de slides Beamer/Quarto. **Nenhum dos
dois existe aqui; pular os Steps 0/0b.** O portão real é `/r-package-check r-package` (passar o path
explicitamente, já que a raiz do repo não tem mais `DESCRIPTION` pra autodetectar), rodado separadamente
antes do merge. Os Steps 1–7 (branch, stage, commit, PR, merge) seguem normalmente.

---

## Skills vivas aqui

O índice completo (~52 skills) vive em `~/.claude/skills/`; a maior parte (paper, slides, aula, econometria,
Stata) fica **dormente** neste repo. Além dessas, o repo tem `.claude/skills/` **local** com 9 skills de
DuckDB/dados (`query`, `attach-db`, `read-file`, `convert-file`, `spatial`, `s3-explore`, `duckdb-docs`,
`install-duckdb`, `read-memories` — ver `.claude/skills/README-duckdb-skills.md`), diretamente úteis aqui
porque todo o motor do pacote é DuckDB + parquet. O que de fato opera:

- **Desenvolvimento do pacote R:** `/r-package-check` (o portão), `/code-review`, `/security-review`
- **Desenvolvimento do pacote Python:** não há skill dedicada; o portão é `pytest` (unitário + `r_parity`)
  rodado à mão — ver "Pacote Python". `/code-review` e `/security-review` valem para os dois
- **Workflow:** `/commit` (Steps 0/0b pulados — ver acima), `/diagnose`, `/checkpoint`, `/context-status`, `/deep-audit`
- **Memória / aprendizado:** `/learn`, `/promote-memory`
- **Meta:** `/permission-check`, `/new-skill`

---

## Funções exportadas

| Função | Propósito |
| --- | --- |
| `geocode()` | Função principal — geocodifica um `data.frame` de endereços; retorna `lat`/`lon` + `precisao`, `tipo_resultado`, `desvio_metros` |
| `geocode_reverso()` | Geocode reverso — recebe um `sf data frame` de pontos, devolve o endereço mais próximo dentro de `dist_max` |
| `busca_por_cep()` | Busca endereços e coordenadas a partir de um vetor de CEPs |
| `definir_campos()` | Monta o vetor de correspondência campo-do-endereço ↔ coluna. `estado` e `municipio` são obrigatórios |
| `download_cnefe()` | Baixa a versão pré-processada e enriquecida do CNEFE usada pelo pacote |
| `definir_pasta_cache()` | Define a pasta de cache (persistente entre sessões do R) |
| `deletar_pasta_cache()` | Apaga os dados em cache |
| `listar_pasta_cache()` | Retorna o caminho da pasta de cache em uso |
| `listar_dados_cache()` | Lista os arquivos presentes no cache |

Coordenadas de entrada e saída usam **SIRGAS 2000, EPSG 4674**.

---

## Arquitetura interna

- **`geocode()` só usa `callr::r()` no Windows com heap legado** (`R/geocode.R`, `usar_callr()`). Quando o exe
  que hospeda a sessão não declara Segment Heap (ex.: `rsession.exe` do RStudio), o motor roda num processo
  separado, porque ali o DuckDB degrada a cada chamada no mesmo processo. Em Linux, macOS e Windows sob
  Rterm/Rgui/Rscript, roda na própria sessão (2–3 s mais rápido, medido). Ao depurar no caminho `callr`,
  `browser()`/`print()` dentro do motor não se comportam como numa chamada comum: chame `geocode_core()` direto
  ou mocke `usar_callr()`. Diagnóstico: `quality_reports/diagnoses/2026-09-24_geocode-callr-deterioracao-heap.md`.
- **Backend DuckDB + Arrow/Parquet** — `R/create_geocodebr_db.R` cria a conexão; `R/register_cnefe_tables.R`
  registra as tabelas do CNEFE. Extensão espacial via `duckspatial`.
- **Matching em camadas** — determinístico em `R/match_cases.R`; probabilístico por similaridade de **Jaro**
  em `R/match_cases_probabilistic.R` + `R/string_dist.R` (limiar 0.85 na *primeira* etapa probabilística de
  cada família — `pn01`/`pa01`/`pl01` — e 0.90 em todas as demais, ver `get_prob_match_cutoff()`);
  interpolação ponderada por `contagem_cnefe` em `R/match_weighted_cases.R` e
  `R/match_weighted_cases_probabilistic.R`. A montagem das colunas `*_encontrado` dos quatro é
  compartilhada em `R/match_helpers.R` (`monta_colunas_encontradas()`).
- **Desempates** — `R/trata_empates_geocode_duckdb.R`, acionado por `resolver_empates = TRUE`.
- **Cache** — `R/cache.R`, versionado por *data release* dentro de `tools::R_user_dir()`. `data_release`
  (`R/cache.R:1`) está hoje em **`v0.5.0`**. Releases antigos na mesma pasta são **apagados** por
  `apaga_data_release_antigo()`, chamada dentro de `download_cnefe()`.
- **Infra transversal** — `R/utils.R` (o maior arquivo), `R/error.R`, `R/message.R`, `R/progress_bar.R`.

### Fontes da verdade — não duplicar

Estas informações já estão documentadas no código. **Aponte para elas em vez de copiá-las**, para não criar
duas versões divergentes da mesma informação:

| Assunto | Fonte |
|---|---|
| Taxonomia de `precisao`, `tipo_resultado` (`dn01`…`dm01`), `desvio_metros`, busca probabilística, `cod_setor` | `man/roxygen/templates/precision_section.R` |
| Regra de resolução de empates (limiar de 1 km, logradouro ambíguo, média ponderada) | `man/roxygen/templates/empates_section.R` |
| Parâmetros compartilhados (`cache`, `verboso`, `n_cores`, `h3_res`, `resultado_sf`) | `man/roxygen/templates/` |

Antes de adicionar um parâmetro novo a uma função, verifique se já existe um `@template` correspondente —
vários parâmetros são compartilhados por três ou mais funções exportadas.

---

## Notas sobre CNEFE / IBGE

- O CNEFE é publicado pelo IBGE; o pacote consome uma versão **pré-processada e enriquecida**, não o arquivo
  bruto. As URLs de origem estão documentadas nos blocos roxygen em `R/download_cnefe.R`, não duplicadas aqui.
- Quirks específicos da fonte (mudanças de schema entre releases, URLs quebradas, codificação de caracteres,
  cadência de publicação, coordenadas suspeitas) devem virar entradas `[LEARN:cnefe]` em
  [MEMORY.md](MEMORY.md) assim que descobertos, em vez de serem re-derivados a cada sessão.
- O geocodebr usa uma versão modificada do CNEFE, em que são gerados diversas agregações em diferentes tabelas 
  de referênca que são salvas em .parquet e utilizadas pelo pacote. Isso é feito numa etapa de pre-processamento
  e é uma das partes mais críticas de todo projeto, e é que viabiliza o geocodebr ser tão eficiente.


---

## Notas sobre pipeline de cada função

### geocode()

`geocode()` (`R/geocode.R`) é apenas um invólucro. O motor real é `geocode_core()`, no mesmo arquivo, e roda
em processo ou num subprocesso `callr`, conforme `usar_callr()` (ver "Arquitetura interna"). Nos dois caminhos
o resultado sai do DuckDB para um parquet temporário e passa pelo mesmo pós-processamento, então o output é
idêntico por construção. **O objeto do usuário precisa ser protegido**, porque o motor usa
`data.table::setDT()` e `:=`, que modificariam `enderecos` por referência. No caminho `callr` isso vem de graça;
em processo, `geocode()` passa `data.table::copy(enderecos)`. Não remover essa cópia (há teste de regressão).

**Etapa 0 — validação e preparação do input.** `checkmate` valida os tipos; `check_clean_colnames()`
(`R/utils.R`) faz duas rejeições: nomes de coluna com qualquer caractere fora de `[A-Za-z0-9_]`, **e**
nomes reservados que o próprio `geocode()` cria no output (`lat`, `lon`, `precisao`, `tipo_resultado`,
`empate`, `cod_setor`, `tempidgeocodebr`, todas as `*_encontrado`…) — se já existissem no input, o merge
final devolveria colunas duplicadas e o pós-processamento (H3, `sf`) leria a errada em silêncio.
`assert_and_assign_address_fields()`
completa com `NULL` os campos não declarados. Para cada campo ausente, cria-se uma **coluna-fantasma**
`<campo>tempgeocodebr` preenchida com `NA_character_` — isso mantém o SQL do matching uniforme, e as etapas
que exigem aquele campo simplesmente não encontram nada (o filtro `IS NOT NULL` as descarta). Essas colunas
são removidas do output no final.

**Etapa 1 — dados de referência (download + cache).** `geocode_core()` **não** baixa mais todas as tabelas:
chama `download_cnefe(tabela = tabelas_necessarias(campos_nao_declarados))`, e `tabelas_necessarias()`
(`R/utils.R`) devolve só o subconjunto das 8 tabelas que as etapas ainda ativas do laço vão usar, dado
quais campos o usuário declarou (no melhor caso — só CEP/bairro/município/UF — isso exclui as duas maiores
tabelas). O download é paralelo (`httr2::req_perform_parallel`), das *releases* do repositório
`ipeaGIT/padronizacao_cnefe`. A tag baixada é a constante `data_release` em `R/cache.R:1` (hoje `v0.5.0`)
— **é essa constante que define a versão dos dados, e ela é hardcoded**. O cache fica em
`{pasta_cache}/geocodebr_data_release_{data_release}/`, e `apaga_data_release_antigo()` remove releases
anteriores. Só os arquivos ausentes são baixados (`setdiff`), então o custo é pago uma única vez.
Com `cache = FALSE`, tudo vai para um `tempfile()` e é rebaixado a cada chamada.

**Etapa 2 — padronização.** `enderecobr::padronizar_enderecos()` com `formato_estados = "sigla"` e
`formato_numeros = "integer"`. As colunas `*_padr` resultantes são renomeadas removendo o sufixo, e
`bairro` vira `localidade` (nome usado no CNEFE). Com `padronizar_enderecos = FALSE` o pacote verifica que
as 6 colunas `*_padr` existem e aborta com `error_input_nao_padronizado()` se não existirem. Em seguida cria
`tempidgeocodebr` (a chave que amarra input e output do início ao fim) e duas colunas de trabalho vazias,
`temp_lograd_determ` e `similaridade_logradouro`, usadas só pelo match probabilístico.

**Etapa 3 — banco DuckDB temporário.** `create_geocodebr_db()` abre um `.duckdb` em `tempfile()` — **em
disco, não em memória**, para suportar volumes maiores que a RAM. Define `SET threads` (por padrão
`min(availableCores(), freeConnections())`) e passa `shared_home = TRUE` no **construtor** `duckdb::duckdb()`
(não no `dbConnect()`, onde seria engolido pelo `...` sem efeito). O input padronizado é gravado como
`input_padrao_db` via `duckdb::dbWriteTable()` direto — sem converter para Arrow antes, porque a tabela
precisa ser materializada e mutável de todo modo e a conversão dominava o custo da etapa. O `output_db` é
criado vazio a partir de um schema Arrow explícito; note que a coluna `empate` **não** está nesse schema, de
propósito (é criada adiante, e pré-declarar causava colisão silenciosa de nome — ver MEMORY.md).
`cria_col_logradouro_confusao()` marca em
`log_causa_confusao` os logradouros ambíguos (`RUA A`, `RUA 10`, `RUA UM`…), com exceção de datas
(`RUA 15 DE NOVEMBRO`). Esse flag é usado duas vezes adiante: exclui a linha do match probabilístico e
força o desempate pelo caminho "perdido".

> **As tabelas de referência NÃO são criadas todas aqui.** Elas são materializadas **sob demanda**, uma por
> vez, dentro de cada etapa do laço, por `register_cnefe_table()` (`R/register_cnefe_tables.R`), que faz
> `CREATE TEMP TABLE ... AS SELECT * FROM read_parquet(...) WHERE estado IN (...) AND municipio IN (...)`,
> filtrando pelos estados e municípios **ainda presentes** em `input_padrao_db`. Como o laço vai apagando
> linhas já encontradas, uma tabela criada numa etapa tardia é filtrada por um conjunto de municípios
> **menor** do que o original. Cada tabela é criada uma única vez (`dbExistsTable()` retorna cedo) e
> reaproveitada por todas as etapas que a compartilham. Essas tabelas **não são indexadas** — o código de
> índice existe, mas comentado (`create_index()` em `R/utils.R:230`, e um bloco `CREATE INDEX` comentado
> dentro de `register_cnefe_table()`).
>
> As etapas probabilísticas usam **um segundo registrador**, `register_unique_logradouros_table()` (mesmo
> arquivo): uma tabela `unique_logr_<tabela>` só com os logradouros distintos, contra a qual o Jaro é
> calculado. A tabela-base dela é sempre a "irmã sem número" do `match_type`
> (`municipio_logradouro_localidade` para `pn03`/`pa03`/`pl03`, `municipio_logradouro_cep_localidade` nos
> demais) — por design, porque a distância de Jaro deve comparar só o texto do logradouro, nunca o número.
> Se a tabela-raiz já estiver materializada, ela é filtrada de lá; senão, lê o parquet.

**Etapa 4 — o laço de matching.** `all_possible_match_types` (`R/utils.R:292`) define **25 etapas em ordem
fixa, da mais precisa para a menos precisa** (`pn04`, `pa04` e `pl04` existem no mapa de tabelas mas estão
desativados na lista — "too costly"). A cada etapa: (a) `get_key_cols()` devolve as colunas-chave;
(b) a etapa é **pulada** se alguma delas não existe no input **ou** se corresponde a um campo que o usuário
não declarou (`campos_nao_declarados`) — o segundo teste é o que evita materializar tabela de referência
para uma etapa que só encontraria `NULL`; (c) escolhe-se uma das 4 funções de match;
(d) os encontrados são inseridos em `output_db`; (e) `update_input_db()` **apaga** de `input_padrao_db` os
`tempidgeocodebr` já resolvidos. Se todos forem encontrados, o laço sai mais cedo.

| Família | Função | O que faz |
|---|---|---|
| `dn01`–`dn04` | `match_cases()` | Join determinístico exato, número incluído |
| `da01`–`da04` | `match_weighted_cases()` | Join sem o número; interpola por `1/ABS(numero - numero_cnefe)` |
| `pn01`–`pn03` | `match_cases_probabilistic()` | Jaro no logradouro, depois join determinístico |
| `pa01`–`pa03` | `match_weighted_cases_probabilistic()` | Interpolação por número; **não** recalcula Jaro (ver abaixo) |
| `dl01`–`dl04`, `pl01`–`pl03` | idem acima | Sem número (`S/N`) |
| `dc01`, `dc02`, `db01`, `dm01` | `match_cases()` | CEP / localidade / município, sem logradouro |

As 25 etapas consomem apenas **8 tabelas de referência** — `reference_table_by_match_type` /
`get_reference_table()` fazem o mapeamento, com vários `match_type` compartilhando a mesma tabela. (O mapa
tem 28 entradas, incluindo os três `*04` desativados.)

O match probabilístico (`calculate_string_dist()`, `R/string_dist.R`) tem duas particularidades que valem
mais que o resto: ele só considera linhas com `log_causa_confusao = FALSE`, e só recalcula a similaridade
onde `similaridade_logradouro IS NULL`. Ou seja, **o logradouro escolhido na primeira etapa probabilística
é memoizado e reusado por todas as etapas probabilísticas seguintes**, mesmo que elas usem tabelas de
referência diferentes. O corte é `> 0.85` para `pn01`/`pa01`/`pl01` e `> 0.90` nos demais
(`get_prob_match_cutoff()`), e o desempate entre logradouros candidatos é `RANK()` por similaridade
decrescente e depois ordem alfabética.

Como corolário dessa memoização, `pa01`/`pa02`/`pa03` **pulam por completo** o Jaro e a criação da tabela
`unique_logr_*`: a etapa `pn0k` imediatamente anterior tem o mesmo `key_cols`, a mesma tabela e o mesmo
corte, então recalcular ali é um no-op comprovado (0 matches em 20.028 endereços). A lista está em
`match_types_jaro_redundante` (`R/utils.R:374`) e a guarda em `match_weighted_cases_probabilistic.R`.
`pa04` **não** entra nessa lista, porque `pn04` está desativado e não haveria etapa anterior para
alimentar `similaridade_logradouro`.

**Etapa 5 — empates.** `trata_empates_geocode_duckdb()` age quando um `tempidgeocodebr` tem mais de uma
linha em `output_db`. A primeira coisa que faz é materializar `ids_empatados` (só os ids com `COUNT(*) > 1`),
e **todo o resto do trabalho é recortado por essa tabela** — os não-empatados passam direto por
`NOT EXISTS`, sem tocar em window function.

Três saídas:

- **Zero empates:** `ALTER TABLE output_db ADD COLUMN IF NOT EXISTS empate BOOLEAN DEFAULT FALSE` e retorna.
  Esse `ALTER` existe porque `merge_results_to_input()` sempre seleciona `empate` quando
  `resultado_completo = TRUE`.
- **`resolver_empates = FALSE`:** `ALTER ADD COLUMN` + `UPDATE ... IN (SELECT ... FROM ids_empatados)` +
  `RENAME TO output_db2` (zero cópia), e emite um `cli_warn`. O output pode ter mais linhas que o input, e
  a coluna `empate` entra no output **mesmo com `resultado_completo = FALSE`** (via `incluir_empate` em
  `merge_results_to_input()`) — cardinalidade 1:N nesse ramo é decisão de design, não bug.
- **`resolver_empates = TRUE` (default):** aplica uma macro `haversine`, materializa `empates_classif` e
  classifica em três grupos: sem empate; "perdidos" (fica o candidato de maior `contagem_cnefe`); e
  "salváveis" (média das coordenadas ponderada por `contagem_cnefe`). Resultado em `output_db2`.

O colapso de 300 m **anterior** ao limiar de 1000 m *está* documentado para o usuário
(`empates_section.R`, passo 1). O que **não** está:

1. A distância desse colapso é medida com **`LAG()`** (não `LEAD()`) contra a linha **anterior** na
   ordenação `contagem_cnefe DESC, desvio_metros, endereco_encontrado`, que por construção tem
   `contagem_cnefe` maior ou igual — é isso que garante a semântica prometida na doc ("reter apenas o ponto
   com maior `contagem_cnefe`"): **quem sai é sempre a linha de menor `contagem_cnefe`**, e a de maior
   (id = 1, cujo `LAG` é `NULL`) é sempre preservada. Trocar por `LEAD()` inverte isso silenciosamente.
2. A distância é entre **linhas consecutivas**, não entre todos os pares.
3. As categorias sem logradouro (`dc01`, `dc02`, `db01`, `dm01`) são **explicitamente** excluídas do ramo
   "perdidos" por `AND logradouro_encontrado IS NOT NULL`: ali o empate é entre endereços do mesmo
   CEP/bairro/município, e a média ponderada é justamente o centroide que a `precisao` promete. (Antes isso
   acontecia por acidente, via propagação de `NULL` no regex — foi tornado explícito.)
4. A exceção de ruas-data (`RUA QUINZE DE NOVEMBRO`) fica **dentro** do braço do regex de números por
   extenso, não como conjunto top-level: nomes-data seguem podendo ser "perdidos" por distância. O `\b` do
   regex tem escape simples no fonte R (`'\\bDE (JANEIRO|…)\\b'`) — a versão com `\\\\b` era código morto.
   Note que os dois regexes olham colunas diferentes: números por extenso em `endereco_encontrado`, a
   exceção de datas em `logradouro_encontrado`.

Ambos os `QUALIFY ROW_NUMBER()` (ramos "perdidos" e "salváveis") ordenam por
`contagem_cnefe DESC, desvio_metros, endereco_encontrado` — os três critérios são necessários para
determinismo, os dois primeiros sozinhos não fechavam.

**Etapa 6 — output.** `add_precision_col()` deriva `precisao` de `tipo_resultado` via `CASE`. O input
original volta como `input_db` e `merge_results_to_input()` faz o `LEFT JOIN` por `tempidgeocodebr`,
preservando a ordem original. `tempidgeocodebr` **não** é removido no fim: ele já fica de fora do `SELECT`
de `merge_results_to_input()` (embora siga valendo no `JOIN` e no `ORDER BY`), para não materializar uma
coluna que seria descartada em seguida. Depois: desconecta o DuckDB, adiciona colunas H3 se `h3_res` foi
passado (`h3r::latLngToCell`, uma coluna `h3_NN` por resolução), remove as colunas-fantasma, e converte para
`sf` (EPSG 4674) se `resultado_sf = TRUE`. A conexão também tem um `on.exit(if (DBI::dbIsValid(con)) …)`
como rede de segurança — o teste `dbIsValid()` é o que evita o aviso "Connection already closed".

#### Invariantes que não podem ser quebradas

1. **Ordem do laço.** Toda etapa `da*`/`pa*` (interpolação) **precisa** ser precedida pela `dn*`/`pn*`
   correspondente. A interpolação divide por `ABS(numero - numero_cnefe)`; se um match exato de número
   sobreviver até ali, o peso vira `Inf` no DuckDB (verificado) e a coordenada sai `NaN`. Hoje isso não
   acontece porque a etapa exata consome esses casos antes. Reordenar `all_possible_match_types` sem
   respeitar isso quebra o cálculo silenciosamente.
2. **`tempidgeocodebr`** é a única ligação entre input e output; nada pode reordenar ou reciclar esse id.
3. **`data_release`** (`R/cache.R:1`) precisa casar com uma tag existente em `ipeaGIT/padronizacao_cnefe`
   **e** com `DATA_RELEASE` em `python-package/geocodebr/constants.py` — o workflow `python-parity.yaml`
   compara as duas constantes e falha antes de rodar qualquer teste se divergirem.
4. `man/roxygen/templates/precision_section.R` e `empates_section.R` são a documentação de usuário desse
   pipeline — mudou a lógica aqui, atualize lá.
5. **Espelhamento no Python.** Qualquer mudança no laço de matching, no SQL dos `match_*()`, no desempate
   ou na ordem de `all_possible_match_types` precisa ser replicada em `python-package/geocodebr/`
   (`matching.py`, `match_types.py`, `string_dist.py`) — ver "Paridade R ↔ Python".

### geocode_reverso()

Apesar do nome sugerir simetria com `geocode()`, é um pipeline **completamente diferente**: não usa
`callr`, não usa o laço de 25 etapas, não tem desempate, e delega quase tudo à extensão espacial do DuckDB
via `duckspatial`. Roda no processo do próprio usuário.

**Etapa 1 — validação.** Exige `sf` com geometria **`POINT`** e **EPSG 4674** (aborta com outro CRS em vez
de reprojetar). `dist_max` é limitado a `[500, 100000]` metros — **não é possível pedir raio menor que
500 m**. Por fim, testa se a `st_bbox()` do conjunto cai dentro de um bounding box do Brasil hardcoded
(`R/geocode_reverso.R:78-83`); como o teste é sobre a bbox **agregada**, um único ponto fora do país
derruba a chamada inteira.

**Etapa 2 — dados.** Baixa **uma única tabela**, `municipio_logradouro_cep_localidade` — a **sem número**,
a mesma usada por `busca_por_cep()`. Mudou na versão de desenvolvimento atual (antes era
`municipio_logradouro_numero_cep_localidade`): a tabela sem número captura mais casos de logradouro sem
numeração, e em troca o output do geocode reverso **não tem coluna de número**. As colunas trazidas são
`estado`, `municipio`, `logradouro`, `cep`, `localidade`. Abre o DuckDB com `load_spatial = TRUE`, que
instala/carrega a extensão espacial.

**Etapa 3 — recorte geográfico, por geometria e não por coluna.** Esta é a diferença conceitual central em
relação ao `geocode()`: aqui o usuário **não informa** município nem UF. O pacote descobre os municípios
candidatos com um join espacial `within` entre os pontos de input e
`inst/extdata/munis_bbox_2022.parquet` — que contém **bounding boxes** dos municípios, não os polígonos
reais. Isso devolve deliberadamente um superconjunto (bboxes vizinhas se sobrepõem), o que é seguro para
não perder endereços na fronteira. Os códigos IBGE resultantes passam por
`enderecobr::padronizar_municipios()`, e os nomes são interpolados direto na string SQL — daí o
`gsub("'", "''")` para municípios com apóstrofo (`Olho d'Água`).

**Etapa 4 — busca espacial em UTM.** CNEFE e pontos de input são reprojetados para **EPSG:31983**
(SIRGAS 2000 / UTM 23S) para que as distâncias saiam em metros. Cria-se um buffer de `dist_max` em volta de
cada ponto, faz-se um join `intersects` contra os endereços do CNEFE, e um
`ROW_NUMBER() ... ORDER BY distancia_metros` mantém o **endereço mais próximo** de cada ponto. O resultado
volta para EPSG 4674 antes de ser coletado.

> **EPSG:31983 é uma única zona UTM aplicada ao país inteiro.** A zona 23S é centrada em -45° de longitude,
> então a distorção cresce conforme se afasta dela. Medido: erro de +0,2% em São Paulo, +0,7% em Salvador,
> +3,6% em Manaus e **+8,3% em Rio Branco**. Isso afeta tanto a coluna `distancia_metros` quanto o raio
> efetivo de busca do buffer. Ver o relatório de achados em `quality_reports/diagnoses/`.

**Etapa 5 — output.** Retorna o `sf` de input acrescido das colunas do endereço encontrado e de
`distancia_metros`, com a geometria movida para a última coluna. **O join é `INNER`**: pontos sem nenhum
endereço dentro de `dist_max` são **descartados silenciosamente**, e o output pode ter menos linhas que o
input. A função só falha se *nenhum* ponto encontrar endereço. Isso contrasta com `geocode()`, que preserva
todas as linhas via `LEFT JOIN` e devolve `NA`.

### busca_por_cep()

O mais simples dos três: sem `callr`, sem laço, sem empates, sem extensão espacial — uma única consulta SQL.

**Etapa 1 — normalização.** `enderecobr::padronizar_ceps()` e, em seguida, `unique()` + `na.omit()` +
remoção de strings vazias. Ou seja, **CEPs duplicados ou inválidos no input são eliminados** e não têm
correspondência 1:1 com as linhas do output.

**Etapa 2 — consulta.** Baixa apenas `municipio_logradouro_cep_localidade` e roda um
`SELECT ... FROM read_parquet(...) WHERE cep IN (...)`. Note que **não há recorte por município ou UF** —
é uma varredura do parquet nacional, viável porque o CEP já é discriminante.

**Etapa 3 — CEPs não encontrados.** Os CEPs sem correspondência são anexados de volta ao resultado como
linhas com `cep` preenchido e todo o resto `NA` (`data.table::rbindlist(..., fill = TRUE)`), para que o
usuário veja o que não foi achado. Se *nenhum* CEP for encontrado, a função aborta.

**Etapa 4 — output.** Adiciona colunas H3 se `h3_res` for informado e converte para `sf` se
`resultado_sf = TRUE`.

> **A cardinalidade do output não é a do input.** Um CEP costuma cobrir vários logradouros/localidades, e
> cada combinação vira uma linha. Somado à deduplicação da Etapa 1, o número de linhas do resultado não
> guarda relação direta com o comprimento do vetor `cep`.

#### Diferenças entre as três funções

| | `geocode()` | `geocode_reverso()` | `busca_por_cep()` |
|---|---|---|---|
| Isolamento em `callr` | Só no Windows com heap legado (RStudio) | Não | Não |
| Tabelas CNEFE baixadas | 8 (todas) | 1 | 1 |
| Extensão espacial DuckDB | Não | **Sim** | Não |
| Como limita municípios | Colunas UF+município do input (obrigatórias) | Join espacial com bboxes | Não limita |
| Linhas do input preservadas | Sim (`LEFT JOIN`, `NA` se não achou) | **Não** (`INNER JOIN`, descarta) | Não (dedup + 1:N) |
| Desconecta o DuckDB | Sim (+ `on.exit` guardado) | Sim (+ `on.exit` guardado) | Sim (só via `on.exit`) |

---

## Pacote Python

Porte do pacote R para Python, em `python-package/`, **DuckDB-first**: o input é registrado no DuckDB,
todo o matching roda em SQL e o resultado só é materializado no final como `pyarrow.Table`
(`.to_pandas()` fica a cargo do usuário). A única etapa fora do DuckDB é a padronização, feita em
`polars` como ponte para os bindings Python do `enderecobr` — `pandas` não entra no pipeline interno.
Estado atual: `0.1.0`, `Development Status :: 3 - Alpha`, PyPI planejado. Desenvolvido na branch
`python_test` e mesclado na `main` em 21/09/2026 (PR #109, `416f006`); o merge não alterou `r-package/R/`.
Revisão estrutural mais recente: `quality_reports/diagnoses/2026-09-17_revisao-port-python.md`.

### API pública

Mesmos nomes e semântica do R — `geocode()`, `geocode_reverso()`, `busca_por_cep()`, `definir_campos()`,
`download_cnefe()`, `definir_pasta_cache()`, `deletar_pasta_cache()`, `listar_pasta_cache()`,
`listar_dados_cache()` — mais `enderecobr_padronizar_enderecos()`, exposta publicamente. Diferenças de
interface (não de resultado):

| | R | Python |
|---|---|---|
| Input de `geocode()` | `data.frame` | `polars.DataFrame`, `pyarrow.Table`, ou caminho `.csv`/`.parquet` |
| Retorno padrão | `data.frame` | `pyarrow.Table` |
| Retorno espacial | `resultado_sf = TRUE` → `sf` | `resultado_gpd=True` → `geopandas.GeoDataFrame` (extra `geo`) |
| Input de `geocode_reverso()` | `sf` de pontos, EPSG 4674 | `GeoDataFrame` de pontos, EPSG 4674 |
| `definir_campos()` | vetor nomeado | `dict` |

### Mapa módulo Python ↔ arquivo R

| Python (`geocodebr/`) | R (`r-package/R/`) | Conteúdo |
|---|---|---|
| `geocode.py` | `geocode.R` | Pipeline do `geocode()`. **Sem subprocesso** — roda no processo do usuário; o input é materializado em `polars` (o objeto do usuário não é modificado por referência). No Windows sem Segment Heap, em vez do subprocesso que o R usa, limita as threads (`_heap.py`) |
| `matching.py` | `match_cases.R`, `match_cases_probabilistic.R`, `match_weighted_cases.R`, `match_weighted_cases_probabilistic.R`, `match_helpers.R`, `trata_empates_geocode_duckdb.R` + `update_input_db`/`add_precision_col`/`merge_results_to_input`/`cria_col_logradouro_confusao` de `utils.R` | Os quatro `match_*()`, desempate, e as etapas SQL do laço |
| `match_types.py` | `utils.R` (`all_possible_match_types`, `get_key_cols`, `get_reference_table`, `get_prob_match_cutoff`) | Módulo **puro** (sem DuckDB): a escada de 25 etapas e seus metadados |
| `string_dist.py` | `string_dist.R` | Similaridade de Jaro no DuckDB |
| `tables.py` | `register_cnefe_tables.R` | `CREATE TEMP TABLE ... FROM read_parquet(...)` sob demanda |
| `db.py` | `create_geocodebr_db.R` | Conexão DuckDB em disco (`tempfile`), `SET threads`, extensão espacial |
| `standardize.py` | (chamada a `enderecobr::padronizar_enderecos()` em `geocode.R`) | Ponte `polars` ↔ `enderecobr` |
| `reverse.py` / `cep.py` | `geocode_reverso.R` / `busca_por_cep.R` | |
| `cache.py` / `download_cnefe.py` / `constants.py` | `cache.R` / `download_cnefe.R` | `DATA_RELEASE` em `constants.py` ≡ `data_release` em `cache.R` |
| `fields.py` / `errors.py` / `messages.py` / `geo.py` / `utils.py` | `definir_campos.R` / `error.R` / `message.R` / (H3 + `sf`) / validação | |
| `_heap.py` / `_heap_patch.py` | — | Só Windows: detecção do Segment Heap e geração do interpretador patcheado |

### Particularidades que não existem no R

- **Windows + heap legado.** O `python.exe` padrão usa o heap NT legado, que degrada sob alocação
  multithread do DuckDB: `geocode()` fica mais lento **e piora a cada chamada na mesma sessão**
  (duckdb/duckdb#24027; diagnóstico em `quality_reports/diagnoses/2026-09-04_geocode-deterioracao-python-diagnostico.md`).
  Mitigação: sem Segment Heap e sem `n_cores` explícito, o pacote limita o DuckDB a `min(4, núcleos)`
  threads e avisa uma vez por sessão; a solução recomendada é o interpretador patcheado
  (`python -m geocodebr._heap_patch`; 10M endereços: 11:47 → 3:08 min). Benchmarks em `benchmarks/`.
  Ao medir performance do Python no Windows, controlar por isso antes de comparar com o R.
- **Sem subprocesso.** Não há equivalente ao `callr::r()`; `browser()`-style debugging funciona normal.
- **Workflow `python-deterioracao.yaml`** monitora a regressão de deterioração entre chamadas.

---

## Paridade R ↔ Python

**A regra:** aplicados à mesma base de input, com os mesmos argumentos e o mesmo `data_release` do
CNEFE, `geocode()`, `geocode_reverso()` e `busca_por_cep()` devem devolver o **mesmo resultado** nos
dois pacotes. Isso é uma restrição de projeto, não uma meta: um PR que altera o resultado de um lado sem
alterar o outro não é mesclável.

**Como é verificada.** `python-package/tests/test_r_python_parity.py` (marker `r_parity`) gera um script
R em tempo de execução, instala o pacote R local de `r-package/` numa biblioteca temporária, roda as três
funções nos dois lados sobre `r-package/inst/extdata/small_sample.csv` e `large_sample.parquet` (com e
sem `resultado_sf`/`resultado_gpd`), grava os outputs em parquet e compara em **5 níveis**: schema
(colunas), contagem de linhas, distribuição de `tipo_resultado`, coordenadas (`lat`, `lon`,
`distancia_metros`) e todas as células não numéricas. O critério para floats é
`math.isclose(abs_tol=1e-6)` — **não** é `identical()` bit-a-bit, porque a média ponderada do desempate
acumula em ordem dependente do paralelismo do DuckDB e diverge em ~1e-14 grau mesmo entre duas chamadas
do mesmo pacote (ver `[LEARN:testes]` em MEMORY.md). Divergências conhecidas e aceitas (ex.: geometria
achatada em `lon_geom`/`lat_geom` para comparar `geocode_reverso()` via parquet) ficam documentadas na
docstring do próprio teste — é lá que uma nova exceção precisa entrar, com justificativa.

**Quando roda.** `python-parity.yaml` dispara em push/PR para `main` que toque `r-package/R/**` ou
`python-package/geocodebr/**`. Antes de qualquer setup, o workflow extrai `data_release` de
`r-package/R/cache.R` e `DATA_RELEASE` de `python-package/geocodebr/constants.py` e **falha se
divergirem**; o valor também é a chave do cache do CNEFE no CI (mudou o release, rebaixa).

**Fluxo obrigatório ao mudar lógica de matching/desempate/padronização em qualquer um dos lados:**

1. Aplicar a mudança nos dois pacotes no mesmo PR (mapa de arquivos na seção "Pacote Python").
2. Rodar `uv run pytest -m r_parity -q` localmente (exige `Rscript` no PATH e o CNEFE em cache — usa a
   pasta de cache padrão do pacote, não `tmp_path`, justamente para reaproveitar o download).
3. Se a mudança for uma otimização do R (ver iniciativa em `MEMORY.md`), o critério de aceite
   `identical()` R-antes vs R-depois continua valendo, e o teste de paridade garante que o Python não
   ficou para trás.
4. Se um bug corrigido de um lado revela que o outro lado tinha o mesmo bug, corrigir os dois; se
   revela que o outro lado nunca teve o bug, a paridade estava quebrada antes — registrar em
   `MEMORY.md` como `[LEARN:paridade]`.

**Pendências conhecidas (setembro/2026):**

- **Paridade em escala confirmada em 22/09** sobre 43,9 M de endereços do CadÚnico
  (`quality_reports/diagnoses/2026-09-21_paridade-geocode-R-vs-Python-cadunico-43M.md`, §6): output
  idêntico em todas as colunas, diferença máxima de 1,8e-13 grau nas coordenadas. A rodada 1 (21/09)
  tinha achado dois bugs no Python (`similaridade_logradouro` fixa em 1 por dtype `Null` → `INTEGER`;
  `numero > 2^31−1` mantido como `Int64` enquanto o R vira `NA`), ambos corrigidos. **Lacuna que
  continua:** o teste de paridade não compara colunas numéricas além de `lat`/`lon`/`distancia_metros`
  nem tem fixture com número > int32 — teria deixado os dois bugs passarem.
- `DATA_RELEASE` do Python foi alinhado a `v0.5.0` no merge (PR #109); R e Python leem o mesmo release.
  Falta confirmar que `python-parity.yaml` rodou verde na `main` contra os dados `v0.5.0` (`lat`/`lon` em
  `float`, `cod_setor` em `int64`) — a última rodada confirmada à mão pela equipe (17/09) foi com `v0.4.1`.
- As otimizações de `geocode()` já na `main` (P1, P3, P4, P6, P7 — ver `MEMORY.md`) foram feitas só no R;
  precisam de contrapartida no Python ou de confirmação de que o resultado não mudou (a paridade só cobre
  resultado, não tempo).
- O teste de paridade não roda no ambiente de desenvolvimento atual (download do CNEFE via script R +
  `arrow` compilado no R 4.5.3 — problema pré-existente, não do porte); os 8 casos foram confirmados
  manualmente pela equipe em 17/09. Enquanto isso não for resolvido, a evidência de paridade local é o CI.


