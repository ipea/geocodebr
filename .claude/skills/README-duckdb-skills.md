# DuckDB skills (vendored)

Os nove diretórios abaixo (`attach-db`, `convert-file`, `duckdb-docs`, `install-duckdb`, `query`,
`read-file`, `read-memories`, `s3-explore`, `spatial`) são uma cópia das skills publicadas pela DuckDB
para o Claude Code, vendoradas aqui como skills de projeto para que fiquem disponíveis a qualquer
pessoa que clone o repo.

- **Origem:** https://github.com/duckdb/duckdb-skills
- **Anúncio:** https://duckdb.org/2026/09/16/duckdb-skills
- **Versão vendorada:** plugin 0.2.4, commit `7feda8e` (2026-04-14)
- **Licença:** MIT (Stichting DuckDB Foundation) — texto integral abaixo

## Alterações locais em relação ao upstream

1. Referências cruzadas `/duckdb-skills:<skill>` foram reescritas como `/<skill>`, porque o prefixo
   de namespace só existe quando o pacote é instalado via `/plugin`; como skills de projeto elas são
   invocadas pelo nome do diretório.
2. `install-duckdb/eval.sh` (harness de teste do plugin, exige `claude --plugin-dir`) não foi copiado.

## Pré-requisito

As skills chamam o CLI `duckdb` via Bash. Se ele não estiver no PATH, `/install-duckdb` se oferece para
instalá-lo. No Windows: `winget install DuckDB.cli`.

## Para atualizar

```bash
git clone --depth 1 https://github.com/duckdb/duckdb-skills /tmp/duckdb-skills
cp -r /tmp/duckdb-skills/skills/* .claude/skills/
rm -f .claude/skills/install-duckdb/eval.sh
sed -i 's#/duckdb-skills:#/#g' .claude/skills/*/SKILL.md
```

Depois, atualizar a versão/commit acima.

---

## LICENSE (upstream, MIT)

Copyright 2018-2025 Stichting DuckDB Foundation

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
