# Plano — item 6: bugfix do `\b` + unificação das listas de logradouros ambíguos

**Status:** ACORDADO E IMPLEMENTADO — veredito adversarial: **APROVAR INTERMEDIÁRIA** (nem A nem B).

**Registro do acordo (26/08):**
- Achado 1 (MAIOR) derrubou a proposta A: no nível do desempate, flag + regex são uma UNIÃO já
  completa — trocar pelo flag ancorado PERDERIA números compostos ("RUA VINTE E UM" é pego por
  substring do regex, não pelo flag `$`-ancorado) e o caso do typo casado com nome ambíguo do CNEFE.
- Achado 2 (MAIOR) mediu os Jaros: excluir `QUATORZE..NOVENTA` do probabilístico mata matches ruins
  (RUA QUATRO→RUA QUATORZE = 0,911, passa em todos os cutoffs) E matches bons (RUA QUATORZE→RUA
  CATORZE = 0,914, variante ortográfica legítima) — decisão adiada, a tomar com as contagens do 1M.
  Exceção: `QUATRO` é lacuna óbvia de enumeração (1–13 sem o 4) — entra no flag.
- Achado 4: grep confirmou que o padrão `\\\\b` quebrado só existe neste ponto do pacote.
- **Acordado:** (1) fix do `\b`; (2) `QUATRO` no flag; (3) `QUATORZE..NOVENTA` adiado; (4) NEWS.md.

**Descoberta na implementação (além do acordo, validada pelo próprio protocolo do adversário):** o fix
ingênuo do `\b` introduziria uma regressão que o caso "rua-data >1 km continua em E" do protocolo
pegaria — o `AND NOT <regex-data>` era conjunto de nível superior do predicado E, então com o regex
vivo ele anularia inclusive o critério `max_dist > 1000` (rua-data a 5 km cairia na média ponderada).
Corrigido na implementação: a exceção de datas foi movida para dentro do braço do regex de números
(`... OR (REGEXP(num-ext) AND NOT REGEXP(data))`), preservando "perdido por distância" para qualquer
nome. O bug `\b` estava mascarando essa falha estrutural desde sempre.
**Natureza:** MUDANÇA DE COMPORTAMENTO intencional — critério de aceite NÃO é `identical()`, e sim a
caracterização completa das diferenças no benchmark oficial (1M, `n_cores = 1`), inspecionadas e
aprovadas conscientemente. NEWS.md obrigatório.
**Arquivos alvo:** `r-package/R/utils.R` (`cria_col_logradouro_confusao()`),
`r-package/R/trata_empates_geocode_duckdb.R` (ramo E), `r-package/NEWS.md`.

## Os dois defeitos

**Defeito 1 — código morto (bug `\b`).** Em `trata_empates_geocode_duckdb.R`, a exceção de ruas-data
do ramo E (`AND NOT REGEXP_MATCHES(logradouro_encontrado, '\\bDE (JANEIRO|...)\\b')` — fonte R com
`\\\\b`) nunca casa: o RE2 recebe `\\b` = backslash literal + "b". Confirmado com repro mínimo
(sessão 329a63d2). Consequência: "RUA QUINZE DE NOVEMBRO" empatada a <1 km é tratada como "perdida"
(fica 1 candidato) em vez de "salvável" (média ponderada), contra a intenção documentada no próprio
comentário do código. A versão equivalente em `utils.R:604` usa raw string `r"{...\b...}"` e funciona.

**Defeito 2 — duas listas disjuntas de "logradouro ambíguo".**
- `cria_col_logradouro_confusao()` (`utils.R:560`): flag `log_causa_confusao` no INPUT, cobre letras
  (`RUA A`), dígitos (`RUA 10`), combinações, e números por extenso `UM, DOIS, TRES, CINCO...TREZE` —
  **sem `QUATRO`** (lacuna aparente, não decisão documentada). Usada em 2 lugares: exclui a linha do
  match probabilístico (`string_dist.R:42`) e alimenta o ramo E dos empates.
- Ramo E de `trata_empates_geocode_duckdb.R`: regex extra sobre `endereco_encontrado` cobrindo
  `QUATRO, QUATORZE, QUINZE, DEZESSEIS...NOVENTA` + a exceção de datas (morta, defeito 1).

Inconsistência resultante: input "RUA QUATORZE" **passa** pelo match probabilístico (Jaro) — o pacote
aceita casá-lo por similaridade com qualquer rua — mas na hora do desempate o mesmo nome é considerado
ambíguo demais para média ponderada. Ou o nome é confiável, ou não é.

## Proposta A (preferida — unificação completa)

1. **`utils.R`**: estender `ruas_num_ext` com
   `QUATRO, QUATORZE, QUINZE, DEZESSEIS, DEZESSETE, DEZOITO, DEZENOVE, VINTE, TRINTA, QUARENTA,
   CINQUENTA, SESSENTA, SETENTA, OITENTA, NOVENTA` (a exceção de datas de lá já funciona e continua).
2. **`trata_empates_geocode_duckdb.R`**: o predicado do ramo E reduz para
   `logradouro_encontrado IS NOT NULL AND (max_dist > 1000 OR log_causa_confusao)` — o regex de números
   por extenso e a exceção de datas (morta) saem. Fonte única da verdade: o flag.
3. **NEWS.md**: entrada em "Mudanças de comportamento"/bug fixes com os números do benchmark.

### Consequências comportamentais (a caracterizar no benchmark)

- (i) **Ruas-data** ("RUA QUINZE DE NOVEMBRO", "RUA VINTE E CINCO DE MARÇO"…): empates a <1 km passam
  de "perdido" para média ponderada — o comportamento documentado. `utils.R` não as flagra (exceção de
  datas funciona lá), então nada muda no matching delas.
- (ii) **Inputs `RUA QUATRO...NOVENTA`**: passam a ser excluídos do match probabilístico
  (`string_dist.R` filtra `log_causa_confusao = FALSE`). Endereços que hoje casam via `pn/pa/pl` com
  esses nomes caem para categorias menos precisas (CEP/localidade/município) ou `NA`. Matches
  determinísticos (exatos) não são afetados. Este é o efeito potencialmente maior — quantificar.
- (iii) **Assimetria de lado**: o regex atual roda sobre `endereco_encontrado` (lado CNEFE); o flag é
  do lado do INPUT. Caso raro afetado: input com typo ("RUA QUINZI") que casa probabilisticamente com
  "RUA QUINZE" do CNEFE — hoje o desempate vê o nome encontrado e manda para E; com o flag (input não
  flagrado) iria para F. Aceitável em princípio; quantificar se aparecer.

## Proposta B (fallback mínimo — só o bugfix)

Trocar `\\\\b` por `\\b` na linha do regex de datas do ramo E e **nada mais** (listas continuam
duplicadas e disjuntas). Corrige o defeito 1 (efeito (i) apenas), não toca no matching. Deixa viva a
inconsistência do defeito 2 e a duplicação de código.

## Resultado (26/08, pós-implementação — aguardando aprovação do usuário)

Benchmark oficial (1M, `n_cores = 1`, `resolver_empates = TRUE`), pré vs pós item 6:

| | valor |
|---|---|
| Linhas alteradas | **43 de 1M (0,004%)** |
| — ruas-data E→F (fix `\b`): média ponderada, mesmo `tipo_resultado` | 14 |
| — "RUA QUATRO" fora do probabilístico: recategorizadas (`pn/pa/pl` → `dn/da/dl/dc`) | 26 |
| — ruído FP sub-nanômetro (≤7e-15°, ordem de scan; não-comportamental) | 3 |
| Etapa de empates | 1,34 s → 1,34 s (neutro) |
| Harness (16 asserções, incl. 3 discriminantes novas) | verde; diffs old→new = exatamente ids 6 e 13 |

Contagens para a decisão adiada (`QUATORZE..NOVENTA` no flag): dos 248.753 logradouros padronizados
únicos do 1M, apenas **11** ganham o flag com `QUATRO` e apenas **23** seriam flagrados por
`QUATORZE..NOVENTA` — superfície mínima nos dois sentidos; a decisão pode esperar evidência de matches
errados reais.

Nota da amostra: casos como "RUA TRINTA UM MARCO" (input com typo, sem "DE") mudaram porque o regex
roda sobre o lado CNEFE (`logradouro_encontrado` = "RUA TRINTA E UM DE MARCO", com "DE") — o desenho
de operar no lado encontrado se mostrou correto na prática.

## Verificação (protocolo de mudança de comportamento)

1. **Harness sintético**: a asserção do id6 (rua-data → wavg) deve FLIPAR para OK; id5 continua em E
   (na proposta A, via flag — os dados do harness ganham `confusao = TRUE` no id5 para simular o novo
   flag de input; adicionar também um caso de rua-data >1 km, que deve continuar em E via `max_dist`).
2. **Benchmark oficial** (1M, `n_cores = 1`, `resolver_empates = TRUE`): old (working tree atual) vs
   new — relatório de diferenças, não `identical()`:
   - nº de linhas com `lat/lon/tipo_resultado/precisao` diferentes, e % do total;
   - decomposição por causa: (i) ruas-data E→F; (ii) perda de match probabilístico
     `pn/pa/pl → dc/db/dm/NA`; (iii) outros (investigar qualquer resíduo não explicado);
   - contagem prévia: quantos inputs do 1M têm logradouro batendo em `QUATRO...NOVENTA` (dimensiona o
     efeito (ii) antes de decidir).
3. Tempos das etapas como sempre (efeito colateral esperado: neutro ou levemente positivo — menos um
   regex no ramo E; possível redução de trabalho no probabilístico).
4. Apresentar o relatório ao usuário ANTES de dar o item por aceito.
