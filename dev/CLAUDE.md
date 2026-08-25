# CLAUDE.md — geocodebr

**Projeto:** geocodebr — pacote R para geolocalização de endereços
brasileiros, baseado no CNEFE (Cadastro Nacional de Endereços para Fins
Estatísticos), publicado pelo IBGE. Geocodificação em massa, sem limite
de consultas, a partir de dados abertos. **Mantenedor:** Rafael H. M.
Pereira (aut, cre — Ipea) · **Autores:** Daniel Herszenhut, Gabriel
Garcia de Almeida **Financiamento/copyright:** Ipea; ITpS — Instituto
Todos pela Saúde **Repo:** <https://github.com/ipeaGIT/geocodebr> ·
**Branch:** main · **Versão:** 0.6.4 (dev 0.6.4.900) **Idioma:**
`Language: pt` na DESCRIPTION — NEWS.md, blocos roxygen, mensagens de
erro/aviso, vignettes e README são em **português**. Todo conteúdo
voltado ao usuário deve seguir isso.

------------------------------------------------------------------------

## Princípios centrais

- **Plano primeiro** — entrar em plan mode antes de tarefas não
  triviais; salvar planos em `quality_reports/plans/`
- **`R/` é autoritativo** — `man/` (documentação) e `NAMESPACE` são
  **gerados** pelo roxygen2. Nunca editar à mão; editar os blocos
  roxygen em `R/` e rodar `devtools::document()`
- **O portão de release é `R CMD check --as-cran`** — 0 erros, 0
  warnings, e toda NOTE restante justificada em `cran-comments.md`.
  Rodar via `/r-package-check` antes de qualquer release ou merge que
  toque `R/`, `tests/` ou `DESCRIPTION`
- **Português no que o usuário vê** — NEWS.md, roxygen, mensagens `cli`,
  vignettes e README em pt-BR. Comentários internos de código podem ser
  em pt ou en, mas siga o padrão do arquivo em que está mexendo
- **`[LEARN]`** — quando corrigido, ou quando uma abordagem não óbvia
  for confirmada, gravar `[LEARN:categoria] errado → certo` em
  [MEMORY.md](https://ipeagit.github.io/geocodebr/dev/MEMORY.md)

Contexto entre sessões vive em
[MEMORY.md](https://ipeagit.github.io/geocodebr/dev/MEMORY.md); planos,
specs e logs de sessão em
[quality_reports/](https://ipeagit.github.io/geocodebr/dev/quality_reports/).
As regras, skills e agentes do workflow estão configurados globalmente
em `~/.claude` (compartilhados com flightsbr / enderecobr) e chegam aqui
por path-scoping — veja “Skills vivas aqui” abaixo para o que de fato
opera neste repo.

------------------------------------------------------------------------

## Estrutura de pastas

    geocodebr/
    ├── CLAUDE.md                     # Este arquivo
    ├── MEMORY.md                     # Aprendizados [LEARN] entre sessões
    ├── DESCRIPTION / NAMESPACE       # Metadados / exports GERADOS (nunca editar NAMESPACE à mão)
    ├── NEWS.md                       # Changelog voltado ao usuário, em pt-BR (bump por release)
    ├── cran-comments.md              # Notas de submissão CRAN (justificativa de cada NOTE)
    ├── CRAN-SUBMISSION               # Registro da última submissão (versão, data, SHA)
    ├── codemeta.json                 # GERADO — precisa ser atualizado quando a DESCRIPTION muda
    ├── R/                            # Fonte do pacote (ver "Arquitetura interna")
    ├── tests/testthat/               # testthat edition 3, incl. _snaps/ para texto de mensagens
    ├── man/
    │   ├── *.Rd                      # GERADOS — editar o roxygen em R/
    │   └── roxygen/templates/        # @template compartilhados (cache, verboso, n_cores, h3_res, ...)
    ├── inst/
    │   ├── CITATION                  # Como citar o pacote
    │   └── extdata/                  # Amostras: small_sample.csv, large_sample.parquet, pontos.rds, bboxes
    ├── vignettes/                    # geocodebr.Rmd, geocode.Rmd, geocode_reverso.Rmd
    ├── pkgdown/_pkgdown.yml          # Config do site pkgdown
    ├── python-package/               # Apenas placeholder.txt — porte para Python ainda não começou
    ├── .github/workflows/            # check, check_as_cran, pkgdown, readme_rmd, rhub, test-coverage
    ├── quality_reports/              # Planos, specs, logs de sessão, relatórios de merge, diagnoses
    └── templates/                    # Templates de log de sessão / spec / relatório de qualidade

------------------------------------------------------------------------

## Comandos

``` r

# Regenerar docs + NAMESPACE após editar blocos roxygen em R/
devtools::document()

# Rodar a suíte de testes
devtools::test()

# Check completo de prontidão CRAN (lento, ~4 min — rodar em background em execuções longas)
devtools::check(args = "--as-cran")

# Cobertura de testes
covr::package_coverage()

# Construir o site pkgdown
pkgdown::build_site()
```

``` bash
# Equivalente local ao check da CI
R CMD build . && R CMD check --as-cran geocodebr_*.tar.gz
```

**Submissão CRAN:** atualizar `NEWS.md` + bump da `Version` na
`DESCRIPTION`, atualizar `cran-comments.md` com justificativa para cada
NOTE restante, e então `devtools::release()` (só o mantenedor, não
automatizado).

------------------------------------------------------------------------

## Hooks pre-commit deste repo

`.pre-commit-config.yaml` usa `lorenzwalthert/precommit` com três hooks
que **rejeitam o commit** se ignorados:

| Hook | O que exige |
|----|----|
| `readme-rmd-rendered` | `README.md` regenerado a partir de `README.Rmd` — nunca editar o `.md` direto |
| `codemeta-description-updated` | `codemeta.json` atualizado sempre que a `DESCRIPTION` mudar (`codemetar::write_codemeta()`) |
| `pkgdown` | Config do pkgdown consistente com as funções exportadas |

Ou seja: mexeu na `DESCRIPTION`, atualize o `codemeta.json`; mexeu no
`README.Rmd`, renderize o `README.md`.

------------------------------------------------------------------------

## Portão de qualidade

| Verificação | Barra |
|----|----|
| `R CMD check --as-cran` | 0 erros, 0 warnings, cada NOTE explicada em `cran-comments.md` |
| `devtools::test()` | Todos passando; toda função exportada com ao menos um teste |
| Cobertura (`covr`) | Nenhuma função exportada em 0% |
| Docs roxygen | Toda função exportada: `@param` (todos os args), `@return`, `@examples` executável |
| Matriz de CI | Windows, macOS e Ubuntu (devel/release/oldrel) verdes — `.github/workflows/check.yaml` |

Padrão completo: `r-package-conventions.md` (regra global, path-scoped
para `R/**/*.R`, `tests/**/*.R`, `man/**/*.Rd`, `DESCRIPTION`,
`NAMESPACE`, `NEWS.md`).

**Nota sobre `/commit`:** os Steps 0 e 0b da skill global chamam
`scripts/quality_score.py` e `scripts/check-surface-sync.sh` —
construídos para o projeto-template de slides Beamer/Quarto. **Nenhum
dos dois existe aqui; pular os Steps 0/0b.** O portão real é
`/r-package-check`, rodado separadamente antes do merge. Os Steps 1–7
(branch, stage, commit, PR, merge) seguem normalmente.

------------------------------------------------------------------------

## Skills vivas aqui

O índice completo (~52 skills) vive em `~/.claude/skills/`; a maior
parte (paper, slides, aula, econometria, Stata) fica **dormente** neste
repo. O que de fato opera:

- **Desenvolvimento do pacote:** `/r-package-check` (o portão),
  `/code-review`, `/security-review`
- **Workflow:** `/commit` (Steps 0/0b pulados — ver acima), `/diagnose`,
  `/checkpoint`, `/context-status`, `/deep-audit`
- **Memória / aprendizado:** `/learn`, `/promote-memory`
- **Meta:** `/permission-check`, `/new-skill`

------------------------------------------------------------------------

## Funções exportadas

| Função | Propósito |
|----|----|
| [`geocode()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode.md) | Função principal — geocodifica um `data.frame` de endereços; retorna `lat`/`lon` + `precisao`, `tipo_resultado`, `desvio_metros` |
| [`geocode_reverso()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode_reverso.md) | Geocode reverso — recebe um `sf data frame` de pontos, devolve o endereço mais próximo dentro de `dist_max` |
| [`busca_por_cep()`](https://ipeagit.github.io/geocodebr/dev/reference/busca_por_cep.md) | Busca endereços e coordenadas a partir de um vetor de CEPs |
| [`definir_campos()`](https://ipeagit.github.io/geocodebr/dev/reference/definir_campos.md) | Monta o vetor de correspondência campo-do-endereço ↔︎ coluna. `estado` e `municipio` são obrigatórios |
| [`download_cnefe()`](https://ipeagit.github.io/geocodebr/dev/reference/download_cnefe.md) | Baixa a versão pré-processada e enriquecida do CNEFE usada pelo pacote |
| [`definir_pasta_cache()`](https://ipeagit.github.io/geocodebr/dev/reference/definir_pasta_cache.md) | Define a pasta de cache (persistente entre sessões do R) |
| [`deletar_pasta_cache()`](https://ipeagit.github.io/geocodebr/dev/reference/deletar_pasta_cache.md) | Apaga os dados em cache |
| [`listar_pasta_cache()`](https://ipeagit.github.io/geocodebr/dev/reference/listar_pasta_cache.md) | Retorna o caminho da pasta de cache em uso |
| [`listar_dados_cache()`](https://ipeagit.github.io/geocodebr/dev/reference/listar_dados_cache.md) | Lista os arquivos presentes no cache |

Coordenadas de entrada e saída usam **SIRGAS 2000, EPSG 4674**.

------------------------------------------------------------------------

## Arquitetura interna

- **[`geocode()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode.md)
  roda seu corpo dentro de
  [`callr::r()`](https://callr.r-lib.org/reference/r.html)**
  (`R/geocode.R`) — processo R separado, por isolamento de
  memória/DuckDB. Consequência prática ao depurar:
  [`browser()`](https://rdrr.io/r/base/browser.html) ou
  [`print()`](https://rdrr.io/r/base/print.html) dentro do corpo não se
  comportam como numa chamada comum. Para investigar, extraia a lógica
  ou chame as funções internas diretamente.
- **Backend DuckDB + Arrow/Parquet** — `R/create_geocodebr_db.R` cria a
  conexão; `R/register_cnefe_tables.R` registra as tabelas do CNEFE.
  Extensão espacial via `duckspatial`.
- **Matching em camadas** — determinístico em `R/match_cases.R`;
  probabilístico por similaridade de **Jaro** em
  `R/match_cases_probabilistic.R` + `R/string_dist.R` (limiar 0.85 nos
  casos probabilísticos, 0.90 nos demais); interpolação ponderada por
  `contagem_cnefe` em `R/match_weighted_cases.R` e
  `R/match_weighted_cases_probabilistic.R`.
- **Desempates** — `R/trata_empates_geocode_duckdb.R`, acionado por
  `resolver_empates = TRUE`.
- **Cache** — `R/cache.R`, versionado por *data release* dentro de
  [`tools::R_user_dir()`](https://rdrr.io/r/tools/userdir.html). O
  pacote usa apenas os dados do release corrente e ignora releases
  antigos na mesma pasta (corrigido na v0.6.2).
- **Infra transversal** — `R/utils.R` (o maior arquivo), `R/error.R`,
  `R/message.R`, `R/progress_bar.R`.

### Fontes da verdade — não duplicar

Estas informações já estão documentadas no código. **Aponte para elas em
vez de copiá-las**, para não criar duas versões divergentes da mesma
informação:

| Assunto | Fonte |
|----|----|
| Taxonomia de `precisao`, `tipo_resultado` (`dn01`…`dm01`), `desvio_metros`, busca probabilística, `cod_setor` | `man/roxygen/templates/precision_section.R` |
| Regra de resolução de empates (limiar de 1 km, logradouro ambíguo, média ponderada) | `man/roxygen/templates/empates_section.R` |
| Parâmetros compartilhados (`cache`, `verboso`, `n_cores`, `h3_res`, `resultado_sf`) | `man/roxygen/templates/` |

Antes de adicionar um parâmetro novo a uma função, verifique se já
existe um `@template` correspondente — vários parâmetros são
compartilhados por três ou mais funções exportadas.

------------------------------------------------------------------------

## Notas sobre CNEFE / IBGE

- O CNEFE é publicado pelo IBGE; o pacote consome uma versão
  **pré-processada e enriquecida**, não o arquivo bruto. As URLs de
  origem estão documentadas nos blocos roxygen em `R/download_cnefe.R`,
  não duplicadas aqui.
- Quirks específicos da fonte (mudanças de schema entre releases, URLs
  quebradas, codificação de caracteres, cadência de publicação,
  coordenadas suspeitas) devem virar entradas `[LEARN:cnefe]` em
  [MEMORY.md](https://ipeagit.github.io/geocodebr/dev/MEMORY.md) assim
  que descobertos, em vez de serem re-derivados a cada sessão.
- O geocodebr usa uma versão modificada do CNEFE, em que são gerados
  diversas agregações em diferentes tabelas de referênca que são salvas
  em .parquet e utilizadas pelo pacote. Isso é feito numa etapa de
  pre-processamento e é uma das partes mais críticas de todo projeto, e
  é que viabiliza o geocodebr ser tão eficiente.

------------------------------------------------------------------------

## Notas sobre pipeline de cada função

### geocode()

[`geocode()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode.md)
(`R/geocode.R`) é apenas um invólucro: todo o corpo roda dentro de
[`callr::r()`](https://callr.r-lib.org/reference/r.html), num processo R
separado. Isso isola a memória do DuckDB e — efeito colateral importante
— **protege o objeto do usuário**, já que o motor usa
[`data.table::setDT()`](https://rdrr.io/pkg/data.table/man/setDT.html) e
`:=` que modificariam `enderecos` por referência. O motor real é
`geocode_core()`, no mesmo arquivo.

**Etapa 0 — validação e preparação do input.** `checkmate` valida os
tipos; `check_clean_colnames()` rejeita nomes de coluna com qualquer
caractere fora de `[A-Za-z0-9_]`. `assert_and_assign_address_fields()`
completa com `NULL` os campos não declarados. Para cada campo ausente,
cria-se uma **coluna-fantasma** `<campo>tempgeocodebr` preenchida com
`NA_character_` — isso mantém o SQL do matching uniforme, e as etapas
que exigem aquele campo simplesmente não encontram nada (o filtro
`IS NOT NULL` as descarta). Essas colunas são removidas do output no
final.

**Etapa 1 — dados de referência (download + cache).**
`download_cnefe(tabela = 'todas')` baixa **as 8 tabelas de uma vez**, em
paralelo
([`httr2::req_perform_parallel`](https://httr2.r-lib.org/reference/req_perform_parallel.html)),
das *releases* do repositório `ipeaGIT/padronizacao_cnefe`. A tag
baixada é a constante `data_release` em `R/cache.R:1` — **é essa
constante que define a versão dos dados, e ela é hardcoded**. O cache
fica em `{pasta_cache}/geocodebr_data_release_{data_release}/`, e
[`apaga_data_release_antigo()`](https://ipeagit.github.io/geocodebr/dev/reference/apaga_data_release_antigo.md)
remove releases anteriores. Só os arquivos ausentes são baixados
(`setdiff`), então o custo é pago uma única vez. Com `cache = FALSE`,
tudo vai para um [`tempfile()`](https://rdrr.io/r/base/tempfile.html) e
é rebaixado a cada chamada.

**Etapa 2 — padronização.**
[`enderecobr::padronizar_enderecos()`](https://rdrr.io/pkg/enderecobr/man/padronizar_enderecos.html)
com `formato_estados = "sigla"` e `formato_numeros = "integer"`. As
colunas `*_padr` resultantes são renomeadas removendo o sufixo, e
`bairro` vira `localidade` (nome usado no CNEFE). Com
`padronizar_enderecos = FALSE` o pacote verifica que as 6 colunas
`*_padr` existem e aborta com `error_input_nao_padronizado()` se não
existirem. Em seguida cria `tempidgeocodebr` (a chave que amarra input e
output do início ao fim) e duas colunas de trabalho vazias,
`temp_lograd_determ` e `similaridade_logradouro`, usadas só pelo match
probabilístico.

**Etapa 3 — banco DuckDB temporário.** `create_geocodebr_db()` abre um
`.duckdb` em [`tempfile()`](https://rdrr.io/r/base/tempfile.html) — **em
disco, não em memória**, para suportar volumes maiores que a RAM. Define
`SET threads` (por padrão `min(availableCores(), freeConnections())`). O
input padronizado é gravado como `input_padrao_db` e o `output_db` é
criado vazio a partir de um schema Arrow explícito.
`cria_col_logradouro_confusao()` marca em `log_causa_confusao` os
logradouros ambíguos (`RUA A`, `RUA 10`, `RUA UM`…), com exceção de
datas (`RUA 15 DE NOVEMBRO`). Esse flag é usado duas vezes adiante:
exclui a linha do match probabilístico e força o desempate pelo caminho
“perdido”.

> **As tabelas de referência NÃO são criadas todas aqui.** Elas são
> materializadas **sob demanda**, uma por vez, dentro de cada etapa do
> laço, por `register_cnefe_table()` (`R/register_cnefe_tables.R`), que
> faz
> `CREATE TEMP TABLE ... AS SELECT * FROM read_parquet(...) WHERE estado IN (...) AND municipio IN (...)`,
> filtrando pelos estados e municípios **ainda presentes** em
> `input_padrao_db`. Como o laço vai apagando linhas já encontradas, uma
> tabela criada numa etapa tardia é filtrada por um conjunto de
> municípios **menor** do que o original. Cada tabela é criada uma única
> vez (`dbExistsTable()` retorna cedo) e reaproveitada por todas as
> etapas que a compartilham. Essas tabelas **não são indexadas** — o
> código de índice existe (`create_index()` em `R/utils.R`) mas está
> desativado.

**Etapa 4 — o laço de matching.** `all_possible_match_types`
(`R/utils.R`) define **25 etapas em ordem fixa, da mais precisa para a
menos precisa**. A cada etapa: (a) `get_key_cols()` devolve as
colunas-chave; (b) se alguma delas não existe no input, a etapa é
**pulada**; (c) escolhe-se uma das 4 funções de match; (d) os
encontrados são inseridos em `output_db`; (e)
[`update_input_db()`](https://ipeagit.github.io/geocodebr/dev/reference/update_input_db.md)
**apaga** de `input_padrao_db` os `tempidgeocodebr` já resolvidos. Se
todos forem encontrados, o laço sai mais cedo.

| Família | Função | O que faz |
|----|----|----|
| `dn01`–`dn04` | `match_cases()` | Join determinístico exato, número incluído |
| `da01`–`da04` | `match_weighted_cases()` | Join sem o número; interpola por `1/ABS(numero - numero_cnefe)` |
| `pn01`–`pn03` | `match_cases_probabilistic()` | Jaro no logradouro, depois join determinístico |
| `pa01`–`pa03` | `match_weighted_cases_probabilistic()` | Jaro + interpolação por número |
| `dl01`–`dl04`, `pl01`–`pl03` | idem acima | Sem número (`S/N`) |
| `dc01`, `dc02`, `db01`, `dm01` | `match_cases()` | CEP / localidade / município, sem logradouro |

As 25 etapas consomem apenas **8 tabelas de referência** —
`get_reference_table()` faz o mapeamento, com vários `match_type`
compartilhando a mesma tabela.

O match probabilístico (`calculate_string_dist()`, `R/string_dist.R`)
tem duas particularidades que valem mais que o resto: ele só considera
linhas com `log_causa_confusao = FALSE`, e só recalcula a similaridade
onde `similaridade_logradouro IS NULL`. Ou seja, **o logradouro
escolhido na primeira etapa probabilística é memoizado e reusado por
todas as etapas probabilísticas seguintes**, mesmo que elas usem tabelas
de referência diferentes. O corte é `> 0.85` para `pn01`/`pa01`/`pl01` e
`> 0.90` nos demais (`get_prob_match_cutoff()`), e o desempate entre
logradouros candidatos é `RANK()` por similaridade decrescente e depois
ordem alfabética.

**Etapa 5 — empates.** `trata_empates_geocode_duckdb()` age quando um
`tempidgeocodebr` tem mais de uma linha em `output_db`. Com
`resolver_empates = FALSE`, apenas marca a coluna `empate` e emite um
`cli_warn`. Com `TRUE`, aplica uma macro `haversine` e classifica em
três grupos: sem empate; “perdidos” (resolvidos pelo maior
`contagem_cnefe`); e “salváveis” (média das coordenadas ponderada por
`contagem_cnefe`). Atenção a dois detalhes que **não estão na
documentação do usuário**: existe um filtro anterior de **300 m**
(candidatos a menos disso são descartados da disputa, restando o último
da ordenação) além do limiar de 1000 m; e a distância é calculada com
`LEAD()`, isto é, entre **linhas consecutivas**, não entre todos os
pares. O resultado vai para `output_db2`.

**Etapa 6 — output.**
[`add_precision_col()`](https://ipeagit.github.io/geocodebr/dev/reference/add_precision_col.md)
deriva `precisao` de `tipo_resultado` via `CASE`. O input original volta
como `input_db` e `merge_results_to_input()` faz o `LEFT JOIN` por
`tempidgeocodebr`, preservando a ordem original. Depois: desconecta o
DuckDB, adiciona colunas H3 se `h3_res` foi passado
([`h3r::latLngToCell`](https://symbolixau.github.io/h3r/reference/latLngToCell.html),
uma coluna `h3_NN` por resolução), remove as colunas-fantasma e o id
temporário, e converte para `sf` (EPSG 4674) se `resultado_sf = TRUE`.

#### Invariantes que não podem ser quebradas

1.  **Ordem do laço.** Toda etapa `da*`/`pa*` (interpolação) **precisa**
    ser precedida pela `dn*`/`pn*` correspondente. A interpolação divide
    por `ABS(numero - numero_cnefe)`; se um match exato de número
    sobreviver até ali, o peso vira `Inf` no DuckDB (verificado) e a
    coordenada sai `NaN`. Hoje isso não acontece porque a etapa exata
    consome esses casos antes. Reordenar `all_possible_match_types` sem
    respeitar isso quebra o cálculo silenciosamente.
2.  **`tempidgeocodebr`** é a única ligação entre input e output; nada
    pode reordenar ou reciclar esse id.
3.  **`data_release`** (`R/cache.R:1`) precisa casar com uma tag
    existente em `ipeaGIT/padronizacao_cnefe`.
4.  `man/roxygen/templates/precision_section.R` e `empates_section.R`
    são a documentação de usuário desse pipeline — mudou a lógica aqui,
    atualize lá.

### geocode_reverso()

Apesar do nome sugerir simetria com
[`geocode()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode.md),
é um pipeline **completamente diferente**: não usa `callr`, não usa o
laço de 25 etapas, não tem desempate, e delega quase tudo à extensão
espacial do DuckDB via `duckspatial`. Roda no processo do próprio
usuário.

**Etapa 1 — validação.** Exige `sf` com geometria **`POINT`** e **EPSG
4674** (aborta com outro CRS em vez de reprojetar). `dist_max` é
limitado a `[500, 100000]` metros — **não é possível pedir raio menor
que 500 m**. Por fim, testa se a `st_bbox()` do conjunto cai dentro de
um bounding box do Brasil hardcoded (`R/geocode_reverso.R:79-84`); como
o teste é sobre a bbox **agregada**, um único ponto fora do país derruba
a chamada inteira.

**Etapa 2 — dados.** Baixa **uma única tabela**,
`municipio_logradouro_numero_cep_localidade` (a mais detalhada), e abre
o DuckDB com `load_spatial = TRUE`, que instala/carrega a extensão
espacial.

**Etapa 3 — recorte geográfico, por geometria e não por coluna.** Esta é
a diferença conceitual central em relação ao
[`geocode()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode.md):
aqui o usuário **não informa** município nem UF. O pacote descobre os
municípios candidatos com um join espacial `within` entre os pontos de
input e `inst/extdata/munis_bbox_2022.parquet` — que contém **bounding
boxes** dos municípios, não os polígonos reais. Isso devolve
deliberadamente um superconjunto (bboxes vizinhas se sobrepõem), o que é
seguro para não perder endereços na fronteira. Os códigos IBGE
resultantes passam por
[`enderecobr::padronizar_municipios()`](https://rdrr.io/pkg/enderecobr/man/padronizar_municipios.html),
e os nomes são interpolados direto na string SQL — daí o
`gsub("'", "''")` para municípios com apóstrofo (`Olho d'Água`).

**Etapa 4 — busca espacial em UTM.** CNEFE e pontos de input são
reprojetados para **EPSG:31983** (SIRGAS 2000 / UTM 23S) para que as
distâncias saiam em metros. Cria-se um buffer de `dist_max` em volta de
cada ponto, faz-se um join `intersects` contra os endereços do CNEFE, e
um `ROW_NUMBER() ... ORDER BY distancia_metros` mantém o **endereço mais
próximo** de cada ponto. O resultado volta para EPSG 4674 antes de ser
coletado.

> **EPSG:31983 é uma única zona UTM aplicada ao país inteiro.** A zona
> 23S é centrada em -45° de longitude, então a distorção cresce conforme
> se afasta dela. Medido: erro de +0,2% em São Paulo, +0,7% em Salvador,
> +3,6% em Manaus e **+8,3% em Rio Branco**. Isso afeta tanto a coluna
> `distancia_metros` quanto o raio efetivo de busca do buffer. Ver o
> relatório de achados em `quality_reports/diagnoses/`.

**Etapa 5 — output.** Retorna o `sf` de input acrescido das colunas do
endereço encontrado e de `distancia_metros`, com a geometria movida para
a última coluna. **O join é `INNER`**: pontos sem nenhum endereço dentro
de `dist_max` são **descartados silenciosamente**, e o output pode ter
menos linhas que o input. A função só falha se *nenhum* ponto encontrar
endereço. Isso contrasta com
[`geocode()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode.md),
que preserva todas as linhas via `LEFT JOIN` e devolve `NA`.

### busca_por_cep()

O mais simples dos três: sem `callr`, sem laço, sem empates, sem
extensão espacial — uma única consulta SQL.

**Etapa 1 — normalização.**
[`enderecobr::padronizar_ceps()`](https://rdrr.io/pkg/enderecobr/man/padronizar_ceps.html)
e, em seguida, [`unique()`](https://rdrr.io/r/base/unique.html) +
[`na.omit()`](https://rdrr.io/r/stats/na.fail.html) + remoção de strings
vazias. Ou seja, **CEPs duplicados ou inválidos no input são
eliminados** e não têm correspondência 1:1 com as linhas do output.

**Etapa 2 — consulta.** Baixa apenas
`municipio_logradouro_cep_localidade` e roda um
`SELECT ... FROM read_parquet(...) WHERE cep IN (...)`. Note que **não
há recorte por município ou UF** — é uma varredura do parquet nacional,
viável porque o CEP já é discriminante.

**Etapa 3 — CEPs não encontrados.** Os CEPs sem correspondência são
anexados de volta ao resultado como linhas com `cep` preenchido e todo o
resto `NA` (`data.table::rbindlist(..., fill = TRUE)`), para que o
usuário veja o que não foi achado. Se *nenhum* CEP for encontrado, a
função aborta.

**Etapa 4 — output.** Adiciona colunas H3 se `h3_res` for informado e
converte para `sf` se `resultado_sf = TRUE`.

> **A cardinalidade do output não é a do input.** Um CEP costuma cobrir
> vários logradouros/localidades, e cada combinação vira uma linha.
> Somado à deduplicação da Etapa 1, o número de linhas do resultado não
> guarda relação direta com o comprimento do vetor `cep`.

#### Diferenças entre as três funções

|  | [`geocode()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode.md) | [`geocode_reverso()`](https://ipeagit.github.io/geocodebr/dev/reference/geocode_reverso.md) | [`busca_por_cep()`](https://ipeagit.github.io/geocodebr/dev/reference/busca_por_cep.md) |
|----|----|----|----|
| Isolamento em `callr` | Sim | Não | Não |
| Tabelas CNEFE baixadas | 8 (todas) | 1 | 1 |
| Extensão espacial DuckDB | Não | **Sim** | Não |
| Como limita municípios | Colunas UF+município do input (obrigatórias) | Join espacial com bboxes | Não limita |
| Linhas do input preservadas | Sim (`LEFT JOIN`, `NA` se não achou) | **Não** (`INNER JOIN`, descarta) | Não (dedup + 1:N) |
| Desconecta o DuckDB | Sim | Sim | **Não** (ver achados) |
