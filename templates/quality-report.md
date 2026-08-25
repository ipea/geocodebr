<!-- Copiar para quality_reports/merges/AAAA-MM-DD_[nome-da-branch].md -->

# Relatório de qualidade — [nome-da-branch] — AAAA-MM-DD

**Merge em:** main
**Escopo:** [o que esta branch/PR mudou]

## Portão de release (`/r-package-check`)

| Verificação | Resultado |
|---|---|
| `R CMD check --as-cran` | E erros, W warnings, N notes (cada uma justificada abaixo) |
| `devtools::test()` | P passaram, F falharam |
| Cobertura (`covr`) | X% das funções exportadas; listar qualquer uma em 0% |
| Completude do roxygen | [ok/falha — toda função exportada com @param/@return/@examples] |
| Matriz de CI | [Windows / macOS / Ubuntu devel-release-oldrel — verdes?] |

### Justificativa das NOTEs

- [texto da NOTE] → [por que é aceitável, ou a entrada correspondente em `cran-comments.md`]

## Achados do agente `r-package-reviewer`

- Críticos: [quantidade] — [resolvidos / adiados]
- Altos: [quantidade] — [resolvidos / adiados]

## Hooks pre-commit

- `readme-rmd-rendered`: [README.md regenerado a partir do .Rmd? n/a se o README não mudou]
- `codemeta-description-updated`: [codemeta.json atualizado? n/a se a DESCRIPTION não mudou]
- `pkgdown`: [ok?]

## Veredito

LIBERÁVEL / CORRIGIR-ANTES / VIOLA-POLÍTICA-CRAN

## Follow-ups

- [qualquer coisa adiada para um PR posterior]
