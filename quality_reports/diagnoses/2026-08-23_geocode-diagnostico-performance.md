# Diagnóstico de performance da função `geocode()` — 2026-08-23

Todas as medições foram feitas com `inst/extdata/large_sample.parquet` (**20.028 endereços, 215
municípios após padronização, 3 UFs**), contra o cache real do CNEFE (data release `v0.4.1`,
**1,46 GB, 111 milhões de linhas** em 8 parquets). Tempos medidos com `bench` e `system.time()`.

Nada foi alterado no código. Este documento é diagnóstico.

---

## 1. Onde o tempo vai hoje

Perfil de `geocode_core()` com os 20.028 endereços, instrumentando cada função interna
(100% dos endereços geocodificados, pico de memória em R ~52 MB):

| Fase | Segundos | % | Chamadas |
|---|---|---|---|
| **Materializar tabelas CNEFE (parquet → duckdb)** | **3,47** | **50,2%** | 34 |
| Joins de match propriamente ditos | 1,73 | 25,0% | 25 |
| Distância de string (Jaro) | 0,89 | 12,9% | 9 |
| Padronização (`enderecobr`) + I/O em R | 0,47 | 6,8% | — |
| Criar o db + coluna de logradouro confuso | 0,25 | 3,6% | 1 |
| Resolução de empates | 0,07 | 1,0% | 1 |
| Merge final + coluna `precisao` | 0,03 | 0,4% | 1 |
| **TOTAL (`geocode_core`, sem `callr`)** | **6,91** | | |

Somando o subprocesso `callr`, `geocode()` leva **8,35 s** — ver §5.

**Metade do tempo é gasta copiando dados do parquet para dentro do DuckDB antes de qualquer
geocodificação acontecer.** É aí que está a maior oportunidade, e não onde a intuição sugere.

---

## 2. Ler parquet **não** é o gargalo — materializar é

Duas hipóteses testadas e **refutadas** antes de chegar à conclusão:

**Hipótese A — o filtro por subquery impede o *pruning* de row groups.** O parquet grande já está
**ordenado por (estado, município)** (verificado nas estatísticas dos 409 row groups), então a lista
literal de municípios deveria permitir pular row groups. Medido, filtrando por 1 município:

| | Tempo |
|---|---|
| Filtro por subquery (como no `geocode()`) | 0,43 s |
| Filtro por lista literal (como no `geocode_reverso()`) | 0,41 s |
| Literal + só as colunas necessárias | 0,35 s |

Sem diferença relevante. O DuckDB já faz *pushdown* dinâmico do filtro. **Reescrever o filtro não traz
ganho.**

**Hipótese B — trocar parquet por um `.duckdb` permanente elimina o custo.** Construí o `.duckdb` e
comparei materializando os 215 municípios do `large_sample`:

| | Tempo | Tamanho em disco |
|---|---|---|
| Parquet → TEMP TABLE (atual) | 1,02 s | 606 MB |
| `.duckdb` permanente → TEMP TABLE | 0,98 s | **2.246 MB** |

**Apenas 4% mais rápido, com 3,7× mais download.** O custo não está em ler o parquet; está em **escrever**
3,66 milhões de linhas numa tabela temporária.

---

## 3. A mudança de maior impacto: `VIEW` em vez de `TEMP TABLE`

`register_cnefe_table()` faz `CREATE TEMP TABLE ... AS SELECT * FROM read_parquet(...) WHERE ...`.
Trocar por `CREATE TEMP VIEW` deixa o DuckDB empurrar o filtro para dentro de cada join e ler apenas os
row groups necessários, sem nunca materializar.

A objeção óbvia é que uma view **re-lê a fonte a cada uso**, e cada tabela de referência serve várias
etapas do laço. Medi o ponto de virada — tempo total (setup + N joins) sobre a tabela de 606 MB:

| N joins | TEMP TABLE (atual) | TEMP TABLE + índice | VIEW sobre parquet | VIEW sobre `.duckdb` |
|---|---|---|---|---|
| 1 | 0,93 | 2,56 | **0,13** | 0,09 |
| 2 | 1,01 | 1,61 | **0,29** | 0,20 |
| 4 | 1,32 | 1,89 | **0,70** | 0,33 |
| 8 | 1,59 | 2,97 | **1,26** | 0,72 |
| 12 | 1,76 | 2,37 | 1,80 | 1,14 |

A view sobre parquet vence até ~12 joins, onde empata. **A tabela mais usada serve cerca de 10 etapas**
(`dn01`–`dn04`, `da01`–`da04`, `pn01`–`pn03`, `pa01`–`pa03` se distribuem entre duas tabelas), e o laço
sai mais cedo quando tudo é encontrado — então na prática a view fica no lado vantajoso da curva, e no
pior caso empata.

**Ganho estimado: 1,5× a 7× na fase que hoje é 50% do tempo**, dependendo de quantas etapas rodam.
Custo de implementação: trocar `CREATE TEMP TABLE` por `CREATE TEMP VIEW` em `register_cnefe_table()`.
Zero mudança no formato dos dados, zero mudança no download.

> **Ressalva de evidência:** este número vem de um benchmark isolado sobre a maior tabela, com joins
> sintéticos que imitam os do pacote. Não patcheei o `geocode()` inteiro para medir ponta a ponta. Antes
> de adotar, vale aplicar a mudança e reperfilar — em especial porque as etapas probabilísticas leem a
> tabela de referência por caminhos diferentes (`register_unique_logradouros_table()` filtra da tabela
> raiz quando ela já existe, o que muda se ela virar view).

---

## 4. Índices: **pioram**, não melhoram

A hipótese de indexar as tabelas foi testada e é a única que sai claramente negativa. Na tabela acima,
`TEMP TABLE + índice` é **pior que a versão sem índice em todos os cenários** — 2,56 s contra 0,93 s com
1 join, e ainda perde com 12.

A razão é arquitetural: o DuckDB resolve *equi-joins* com **hash join**, construindo a tabela hash em
memória a cada consulta. Um índice ART não é usado nesse plano; ele serve para busca pontual e para
restrições de unicidade. Então o `CREATE INDEX` só acrescenta o custo de construir a estrutura, que
ninguém consulta.

**Recomendação: não indexar, e remover o helper `create_index()` de `R/utils.R` ou documentá-lo como
inútil para este padrão de consulta.** O código de índice comentado em `register_cnefe_tables.R`
(linhas 78-97) deve continuar comentado.

---

## 5. Overhead do `callr`: 21% do tempo total

| | Tempo |
|---|---|
| `geocode()` (com subprocesso `callr`) | 8,35 s |
| `geocode_core()` (mesmo trabalho, em processo) | 6,62 s |
| **Overhead** | **1,73 s (21%)** |

São 1,73 s de custo fixo: subir um R novo, carregar o pacote, serializar a tabela de entrada e serializar
o resultado de volta. Para 20 mil endereços isso é um quinto do tempo; para 200 endereços seria a maior
parte dele.

O isolamento tem razão de ser (memória do DuckDB, e de quebra protege o objeto do usuário do `setDT()`
por referência — ver `CLAUDE.md`). Mas vale considerar: acionar o `callr` só acima de um limiar de
linhas, ou tornar o isolamento opcional por argumento. Um usuário que geocodifica em laço paga esse
custo em toda iteração.

---

## 6. Jaro: as etapas `pa*` fazem trabalho provadamente inútil

`calculate_string_dist()` já memoiza — só calcula onde `similaridade_logradouro IS NULL`. O problema é
outro: **as etapas de interpolação (`pa01`, `pa02`, `pa03`) refazem um cálculo que não pode produzir
nenhum resultado novo.** Medido por chamada:

| Etapa | Linhas restantes | Candidatos ao Jaro | **Resolvidos** | Segundos |
|---|---|---|---|---|
| `pn01` | 13.536 | 12.980 | 1.129 | 0,03 |
| `pa01` | 12.920 | 11.851 | **0** | 0,05 |
| `pn02` | 10.604 | 10.079 | 361 | 0,11 |
| `pa02` | 10.464 | 9.718 | **0** | 0,10 |
| `pn03` | 8.787 | 8.310 | 305 | 0,14 |
| `pa03` | 8.629 | 8.005 | **0** | 0,12 |
| `pl01` | 7.147 | 6.785 | 155 | 0,05 |
| `pl02` | 6.547 | 6.236 | 103 | 0,13 |
| `pl03` | 6.191 | 5.943 | 48 | 0,12 |

As três etapas `pa*` resolvem **zero** linhas. Não é acaso do dado: para cada par `pn0k`/`pa0k`,
`register_unique_logradouros_table()` devolve **a mesma tabela de logradouros** e
`get_prob_match_cutoff()` devolve **o mesmo corte** (0,85 para `pn01`/`pa01`; 0,90 para os demais). Como
`calculate_string_dist()` só olha linhas com similaridade `NULL`, a segunda chamada do par repete
exatamente as comparações que já falharam. É um no-op garantido.

**Ganho: 0,27 s de 0,89 s — 30% do tempo de Jaro** — simplesmente não chamando `calculate_string_dist()`
nas etapas `pa*`. As colunas `temp_lograd_determ` e `similaridade_logradouro` já estão preenchidas pela
etapa `pn*` anterior, que é tudo que o join da `pa*` consome.

Fica um desperdício maior e mais difícil: das ~12.980 linhas candidatas na primeira etapa, ~11.851 falham
e são recomparadas em todas as etapas seguintes. Essas recomputações **não** são provadamente inúteis
(cada etapa usa uma tabela de logradouros diferente), mas uma tabela de similaridades já testadas
(`tempidgeocodebr`, `logradouro_cnefe`, `similaridade`) evitaria repetir pares idênticos entre etapas que
compartilham a mesma tabela de referência.

---

## 7. Prioridades

| # | Mudança | Ganho medido | Esforço | Risco |
|---|---|---|---|---|
| 1 | `TEMP VIEW` em vez de `TEMP TABLE` em `register_cnefe_table()` | 1,5–7× na fase de 50% | Baixo | Médio — precisa reperfilar ponta a ponta |
| 2 | Não chamar `calculate_string_dist()` nas etapas `pa*` | −30% do Jaro (0,27 s) | Muito baixo | Muito baixo — é no-op comprovado |
| 3 | `callr` condicional a um limiar de linhas | Até 1,73 s por chamada | Médio | Médio — perde o isolamento de memória |
| 4 | Materializar só as colunas necessárias | ~15% da materialização | Baixo | Baixo |
| 5 | Tabela de similaridades reaproveitada entre etapas | Não medido | Alto | Médio |

**Não fazer:**

- **Indexar as tabelas** — medido, piora em todos os cenários (§4).
- **Trocar parquet por `.duckdb` permanente** — 4% de ganho por 3,7× de download (§2). O ganho que parecia
  vir do formato vem, na verdade, de não materializar; a mudança #1 captura isso de graça. Some-se o risco
  de compatibilidade: o formato de armazenamento do DuckDB tem versões, e distribuir um `.duckdb` amarra o
  usuário a uma faixa de versões do pacote `duckdb`, enquanto parquet é estável e portátil (inclusive para
  o porte em Python previsto em `python-package/`).

---

## 8. O que não foi medido

- Escalabilidade: tudo aqui é com 20 mil endereços em 215 municípios. O balanço muda com o tamanho do
  input — materialização depende do **número de municípios**, joins dependem do **número de endereços**.
  Com milhões de endereços em poucos municípios, os joins passam a dominar e a prioridade #1 perde peso.
- Efeito de `n_cores` (todas as medições usaram o padrão).
- As tabelas menores (as 6 que somam 18% dos dados) — o perfil agrega todas.
- Ponta a ponta com o pacote patcheado, para nenhuma das propostas.
