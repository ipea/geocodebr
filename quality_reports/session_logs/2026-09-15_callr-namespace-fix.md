# Session Log — 2026-09-15 — `geocode()`: subprocesso do callr carregava o pacote errado

## Problema relatado

Reprex do README falhando com:

```
Error in `geocode_core(enderecos = enderecos, campos_endereco = campos_endereco, ...)`:
! could not find function "geocode_core"
```

## Causa-raiz

`geocode()` usava `callr::r(..., package = TRUE)`. Nesse modo o callr mantém o
`environment()` da closure anônima — que é o *exec env* de `geocode()`, cuja cadeia termina no
namespace `geocodebr`. Namespace é serializado **por referência (só pelo nome)**, então o
subprocesso faz `loadNamespace("geocodebr")` e carrega **o pacote instalado na biblioteca**, não
o da sessão. Sem checagem de versão, em silêncio.

Reproduzido nesta máquina:

```
load_all(r-package/)  ->  sessão: 0.6.4.901
                          subprocesso do callr: 0.6.3  (win-library/4.5)
```

Qualquer função interna que só exista no fonte da sessão desaparece lá dentro. Já estava anotado
no `MEMORY.md` como gotcha de teste (`[LEARN:testes]`, `devtools::test()` não testa nada que passe
por `geocode()`), mas como convivência, não como bug.

## Correção — `r-package/R/geocode.R`

- `package = FALSE`; `geocode_core` resolvido explicitamente com `get(..., envir = asNamespace("geocodebr"))`.
- Novo helper interno `caminho_pacote_dev()`: detecta `.__DEVTOOLS__` no namespace e devolve
  `getNamespaceInfo(ns, "path")`; `NULL` quando o pacote está instalado normalmente.
- Em modo dev, o subprocesso roda `pkgload::load_all(dev_path)` no **mesmo** código da sessão.
- Guarda de versão: se sessão e subprocesso divergirem, erro explícito com as duas versões e a
  biblioteca de origem, em vez de `could not find function`.
- `pkgload` acrescentado a `Suggests`; entrada no `NEWS.md`; `[LEARN:testes]` do `MEMORY.md`
  atualizado (descrevia o comportamento agora corrigido).

## Verificação

Teste de regressão em `tests/testthat/test-geocode.R` — "subprocesso do callr enxerga as funcoes
internas do pacote". Força um erro de validação da Etapa 0 (campo apontando para coluna
inexistente), o que prova que o subprocesso executou `geocode_core` sem precisar baixar o CNEFE:

```
[ FAIL 0 | WARN 0 | SKIP 0 | PASS 2 ]   (com NOT_CRAN=true)
```

Reprex completo **não** foi rodado de ponta a ponta: não há cache do CNEFE nesta máquina
(`data_release = "v0.4.1"`, pasta vazia) e a chamada dispararia o download das tabelas.

## Impacto de performance (medido, R 4.5.1 / Windows)

Efeito colateral não previsto, a favor do usuário final: com `package = TRUE` o input era
serializado **duas vezes** — uma dentro do exec env de `geocode()` (promises já forçadas) e outra
em `args`. Com `package = FALSE` o environment vira `globalenv`, serializado por referência.

| 1.000.000 de endereços | antes (`package = TRUE`) | depois (`package = FALSE`) |
|---|---|---|
| payload serializado (a 300k linhas) | 47,6 MB | 23,8 MB — 2,0x menor |
| ida-e-volta do callr | 8,59 s | 4,43 s |
| RAM viva no subprocesso | 192 MB | 150 MB |

Overhead acrescentado ao caminho quente do usuário final: `exists(".__DEVTOOLS__")` +
`getNamespaceVersion()` no pai, `identical()` + `get()` no filho. Microssegundos. O motor
(`geocode_core`, DuckDB, laço de 25 etapas) não foi tocado — o ganho é só no overhead fixo de
entrada, não na geocodificação.

**Custo em modo dev:** `+9,5 s por chamada de `geocode()`** (1,22 s → 10,72 s), porque o
subprocesso reparseia todo o `R/`. Testado: `load_all(export_all = FALSE, helpers = FALSE,
attach_testthat = FALSE)` **não** ajuda (8,66 s vs 7,94 s, dentro do ruído) — o custo é o parse do
pacote inteiro.

## Decisão

Ofereci duas mitigações para o custo em dev — uma variável de ambiente
`geocodebr_DEV_SUBPROCESS=false` para voltar ao comportamento antigo, ou chamar `geocode_core()`
direto em processo durante a iteração. Resposta do Rafa: **"leave as it is"**. Nenhuma flag de
escape implementada. A troca foi aceita conscientemente: antes, dev era rápido e executava o
código errado.

## Pendência

`codemetar::write_codemeta()` ainda não rodado — a `DESCRIPTION` mudou (`pkgload` em `Suggests`) e
o hook `codemeta-description-updated` vai barrar o commit. `codemetar` não está instalado nesta
máquina.

## Arquivos tocados

- `M r-package/R/geocode.R`
- `M r-package/DESCRIPTION`
- `M r-package/NEWS.md`
- `M r-package/tests/testthat/test-geocode.R`
- `M MEMORY.md`
