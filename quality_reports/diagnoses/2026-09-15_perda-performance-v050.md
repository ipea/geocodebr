# Diagnóstico: a suposta perda de performance após o CNEFE v0.5.0

**Data:** 2026-09-15
**Pergunta:** o pacote ficou mais lento depois de apontar `data_release` para o v0.5.0?
A hipótese inicial era a mudança de classe de colunas — em especial `cod_setor`, que era
`string` no v0.4.1 e virou `int64` no v0.5.0, enquanto o pacote segue declarando `VARCHAR`
no schema de `output_db`.

---

## Veredito em uma linha

**Não há regressão atribuível ao v0.5.0.** No A/B controlado em escala real (43,9 milhões de
endereços do CadÚnico, mesmo código, mesma máquina, corridas consecutivas), v0.4.1 levou
**925,8 s** e v0.5.0 levou **920,4 s** — 0,6% de diferença, dentro do ruído. A hipótese dos
tipos foi testada isoladamente e **refutada**: reverter os tipos deixa o pacote *mais lento*.

---

## 1. Desenho experimental

Cópias locais das 8 tabelas de referência dos dois releases
(`\STORAGE6\...\2022\{v0.4.1,v0.5.0}\dados_agregados`), cada uma numa pasta de cache própria
nomeada `geocodebr_data_release_v0.5.0`, de modo que **só os dados mudam** — código,
`data_release`, disco e máquina idênticos entre os braços.

Medição por `geocode_core()` direto (sem `callr`), com as funções internas instrumentadas por
wrapper via `assignInNamespace()`: `match_*`, `register_cnefe_table`, `calculate_string_dist`,
`update_input_db`, `trata_empates_geocode_duckdb`, `merge_results_to_input` e
`enderecobr::padronizar_enderecos`.

Um terceiro braço isola o efeito dos **tipos**: conteúdo do v0.5.0 reescrito com o schema do
v0.4.1 (`cod_setor` → VARCHAR, `lat`/`lon` → DOUBLE, `code_muni` e `n_setor` removidas).

---

## 2. Resultados

### 2.1 Escala real — 43.882.020 endereços, `n_cores = 7`, `resultado_completo = FALSE`

| dados | total | achados |
|---|---:|---:|
| v0.4.1 | 925,8 s | 43.879.144 |
| v0.5.0 | **920,4 s** | 43.882.020 |

Nenhuma etapa se move de forma consistente com uma regressão de dados. As duas maiores
diferenças se cancelam e têm sinais opostos: `merge_results_to_input` −27,3 s no v0.5.0,
`padronizar_enderecos` +23,3 s — e a padronização **não toca nos dados de referência**, o que a
identifica como ruído de execução, não como efeito do release.

Mapa de custo (v0.5.0): probabilístico 301 s (32,7%, dos quais 287 s em `calculate_string_dist`),
padronização 208 s (22,6%), merge 145 s (15,8%), interpolação 79 s, determinístico 57 s,
`register_cnefe_table` 36 s (3,9%).

### 2.2 Efeito isolado dos tipos — 1M endereços, `resultado_completo = TRUE`

| arranjo | total |
|---|---:|
| dados v0.4.1 | 31,6 s |
| dados v0.5.0 | **29,9 s** |
| v0.5.0 com os tipos do v0.4.1 | 33,7 s |

**Reverter os tipos piora.** Faz sentido: `cod_setor` como `int64` ocupa 8 bytes contra ~15 do
texto de 15 dígitos, e `lat`/`lon` como `float` ocupam metade do `double`. O v0.5.0 move menos
bytes por linha em toda a pipeline.

### 2.3 Custo do cast `BIGINT → VARCHAR`, medido

`INSERT` de 50 milhões de `cod_setor`:

| | tempo |
|---|---:|
| v0.5.0 `BIGINT → VARCHAR` (código atual) | 0,57 s |
| v0.5.0 `BIGINT → BIGINT` (sem cast) | 0,09 s |
| v0.4.1 `VARCHAR → VARCHAR` (antigo) | 0,25 s |

O cast custa ~0,48 s por 50M de linhas inseridas — **0,04% de uma corrida de 43M**, e
**exatamente zero** com `resultado_completo = FALSE`, que é como o benchmark de regressão roda:
nesse caminho `cod_setor` nem entra no `SELECT`.

### 2.4 `register_cnefe_table()` em escopo nacional (5.570 municípios)

4 tabelas maiores, `SELECT *` vs projeção só das colunas consumidas: ~4–5 s por tabela, **sem
diferença entre releases e sem ganho com a projeção**. As duas colunas novas (`code_muni`,
`n_setor`) não custam tempo mensurável aqui — continuam sendo desperdício de download
(pendência #2 da auditoria), não de CPU.

### 2.5 Modo de desenvolvimento no subprocesso `callr`

`geocode()` com o pacote **instalado** vs carregado por `devtools::load_all()` (1M, ordem
alternada, 2 pares): 54,7 / 50,7 s instalado contra 64,3 / 59,9 s em modo dev — **+9,3 s
fixos por chamada**, consistente com o já registrado no MEMORY. É custo de *startup*, não
proporcional ao volume: em 43M representa ~1% do total.

---

## 3. Por que o benchmark sugeria regressão

As linhas `devendbr` em `tests/tests_rafa/benchmark_reg_adm.R` não sustentam a leitura de
regressão:

- **As duas linhas de "10 milhões" que ficaram mais rápidas (54,3 s e 42,8 s) são de 1 milhão,
  não de 10.** O mesmo commit `9d03781` que trocou o `data_release` reativou
  `dplyr::slice_sample(n = sample_size)` com `sample_size = 1000000`. O `mem_alloc` caindo de
  ~1.016 MB para 143 MB confirma.
- **As três corridas de 43M pioram monotonicamente** (19,8 → 23,5 → 24,7 min) com o mesmo
  código e os mesmos dados. Uma mudança de dados produz *deslocamento constante*, não deriva
  crescente. Deriva monotônica em corridas repetidas é assinatura de contenção da máquina
  (servidor compartilhado, acesso por RDP), não de software.
- A corrida de referência aqui (920 s = 15,3 min, sem a serialização `callr` do resultado de
  43M de volta ao processo pai) é compatível com a linha `dev` de 16,7 min, **não** com 24,7 min.

---

## 4. Pendência #1 da auditoria: resolvida

`geocode(resultado_completo = TRUE)` contra o v0.5.0 devolve `cod_setor` como **`character`**,
com os mesmos valores de 15 dígitos do v0.4.1 (`small_sample`, 27 linhas, conferido item a
item). O cast implícito do DuckDB é lossless — como a auditoria previu, e agora testado.
Cobertura melhora de leve (14 achados no v0.5.0 contra 13 no v0.4.1).

---

## 5. Recomendações

1. **Não mexer nos tipos.** Alinhar o schema de `output_db` a `cod_setor = arrow::int64()`
   pouparia ~0,5 s por 43M — e mudaria a classe da coluna no output do usuário, quebra de
   contrato desproporcional ao ganho. Se um dia for feito, é por consistência, não por
   performance.
2. **Refazer a linha de base do benchmark** num momento de máquina ociosa, alternando a ordem
   dos braços, antes de registrar qualquer número como regressão.
3. **Anotar o `sample_size` junto de cada linha** do benchmark — a confusão 1M/10M já custou
   uma investigação.
4. Pendências #2 (`n_setor` sem uso, +6,9 MB de download) e #4 (mínimo de `{enderecobr}` na
   DESCRIPTION) da auditoria **seguem abertas** — nenhuma delas é de performance.

**Scripts:** no scratchpad da sessão (`harness.R`, `harness2.R`, `test_register.R`,
`test_cast.R`, `test_devmode.R`, `test_codsetor.R`, `make_oldtypes.R`).
