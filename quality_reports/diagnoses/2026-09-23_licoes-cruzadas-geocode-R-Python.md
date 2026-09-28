# Lições cruzadas de eficiência — `geocode()` em R vs Python

**Data:** 23/09/2026 · **Status:** diagnóstico (nada foi alterado no código)
**Versões analisadas:** R 0.6.4.900 (`r-package/`, `main` @ `b18c93a`) · Python 0.1.0 (`python-package/`) · DuckDB 1.5.5 nos dois lados
**Premissa:** a paridade de resultado já está confirmada (benchmark de 23/09 sobre `large_sample.parquet`: 20.028 linhas idênticas, diferença máx. de 4e-14 grau). Aqui a questão é só **tempo e memória**.

## Método

Quatro agentes independentes, cada um com uma lente principal (podendo apontar achados fora dela), leram os dois códigos lado a lado e rodaram micro-benchmarks em ambientes isolados (R instalado em lib temporária; Python em venv, com e sem Segment Heap; mesmo cache CNEFE v0.5.0):

| Agente | Lente |
|---|---|
| 1 | Fluxo geral e movimentação de dados (entrada, `callr`, padronização, merge, saída) |
| 2 | SQL do laço de 25 etapas (`match_*`, Jaro, registro de tabelas, `update_input_db`) |
| 3 | SQL pós-matching (empates, `precisao`, merge, coleta do resultado) |
| 4 | Memória e configuração do DuckDB (pico de RSS, ciclo de vida de tabelas, threads, heap) |

Entradas de teste: `large_sample.parquet` (20k), replicado 50× (1M) e 500× (10M, só agente 3).
**Ressalva de medição:** os quatro agentes rodaram ao mesmo tempo na mesma máquina, então tempos absolutos estão inflados e ruidosos (±40%). Só valem comparações A/B intercaladas ou no mesmo processo. Números de memória são estáveis. Entradas replicadas exageram ganhos de deduplicação (valores repetidos 50×). As afirmações centrais (ausência de `DROP` no Python, `update_input_db` sem filtro, `usa_dedup` no R, `SELECT *` vs `EXCLUDE`, `REGEXP_REPLACE` por linha, `UPDATE ... COALESCE` no R) foram reconferidas no código antes deste relatório.

Legenda de **intervenção:** P = pequena (<20 linhas, 1 arquivo) · M = média (1 módulo, <100 linhas) · G = grande (vários arquivos ou arquitetura).
Nenhuma lição abaixo altera o resultado, a menos que indicado — todas preservam a paridade.

## Resumo executivo

- **O R está à frente no SQL e na memória.** O Python é um retrato de um R mais antigo e não recebeu quatro otimizações posteriores do R: deduplicação no Jaro, agregação curta na interpolação, descarte progressivo de tabelas e `DELETE` filtrado. Todas são portes diretos de código R que já provou dar o mesmo resultado.
- **O Python está à frente na arquitetura de processo.** Roda no próprio processo, com Arrow sem cópia. O `callr` do R custa ~2–4 s fixos por chamada e serializa o input inteiro em RDS, o que cresce linearmente com linhas × colunas.
- **Os dois ganhariam** com um merge "estreito": exportar do DuckDB só as colunas de resultado e anexar as colunas do usuário em memória. É o maior ganho medido fora do laço (−7 a −12 s por lado em 10M).

---

## A. O que o R pode aprender com o Python

### A1. Tirar o input do caminho do `callr` (ou torná-lo barato) — **maior item de tempo no R**
- **Evidência:** `r-package/R/geocode.R:111-188` passa `enderecos` inteiro em `callr::r(args = ...)`, que usa `saveRDS(compress = FALSE)` e `readRDS` no filho. A volta já foi migrada para parquet (`geocode.R:99-109`), a ida não. O Python roda no próprio processo e registra o input sem cópia (`geocode.py:201-315`).
- **Medido:**
  - 20k: `geocode()` 17,4 s vs `geocode_core()` no processo 13,0 s (mediana, sob carga), ou seja ~2–4 s de overhead. Só spawn + `loadNamespace` já dá 2,0 s.
  - 1M: transporte do input +2,6 s. RDS escrita+leitura ~7 s vs Feather ~1,9 s (3,7×, `identical()`).
  - Arquivo RDS: ~100 MB por milhão de linhas, ou seja ~4,3 GB de disco temporário em 43M.
- **Opções, da mais simples à mais completa:**
  1. **(P–M)** Gravar o input como Feather/parquet no pai e ler no filho. Exige cuidar de factor, POSIXct e difftime; `restaura_classes_input` já cobre a volta.
  2. **(M)** Mandar ao filho **só as 6 colunas de endereço**. O pai guarda `enderecos` e anexa o resultado por `tempidgeocodebr`. Isso também elimina `restaura_classes_input` e combina com C1.
  3. **(M)** Modo opcional sem isolamento de processo (ex.: `isolar_processo = FALSE`), como o Python.
- **Benefício:**
  - Tempo: −2 a −4 s por chamada em 20k (15–30% do tempo total nessa escala). ~1 min em 10M, minutos em 43M, e cresce com o nº de colunas não usadas (o CadÚnico tem muitas).
  - Memória: evita um arquivo RDS do tamanho do input e, com a opção 2, a segunda cópia completa no filho.
- **Por que importa:** explica por que o R quase não muda entre `n_cores = 1` e todos os núcleos em 20k. O tempo é dominado por custo fixo. Em escala, a serialização é single-thread e linear no tamanho total do input.
- **Ressalva (agente 4):** o `callr` tem um benefício oculto. Ele lança `Rterm.exe`, que usa o **Segment Heap**, enquanto o `rsession.exe` do RStudio **não usa**. Rodar no processo do RStudio (opção 3) pode trazer para o R o mesmo problema de heap do Python no Windows. As opções 1 e 2 mantêm o subprocesso e evitam isso.
- **Confiança:** alta (direção e overhead em 20k); média (extrapolação para 10M+). Três agentes (1, 3, 4) chegaram a isso independentemente.

### A2. `COALESCE(similaridade_logradouro, 1)` na projeção em vez de `UPDATE` da tabela inteira
- **Evidência:** `r-package/R/utils.R:204-212` faz `UPDATE {y} SET similaridade_logradouro = COALESCE(...)` quando `resultado_completo = TRUE`. O Python faz isso no `SELECT` final (`matching.py:376-385`, o "patch_merge").
- **Intervenção:** P.
- **Benefício:**
  - Tempo: ~0,1 s em 1M, ~0,8 s em 10M (inferido do `UPDATE` de `precisao`, de forma idêntica). Zero em 20k. Só afeta `resultado_completo = TRUE`.
  - Memória: evita a versão/undo do `UPDATE`.
- **Confiança:** média; ganho pequeno.

### A3. Não passar o input inteiro para o `enderecobr` (menor)
- **Evidência:** `geocode.R:373` passa `enderecos` completo, o `enderecobr` faz `as.data.table()` de todas as colunas, e `geocode.R:413` descarta as extras. O Python usa `clone()` raso (`standardize.py:204`).
- **Intervenção:** P (`enderecos[, cols_endereco]` + `manter_cols_extras = FALSE`).
- **Benefício:**
  - Tempo: desprezível (0,03–0,17 s em 1M × 17 colunas).
  - Memória: um vetor de ponteiros por coluna extra (8 B/linha/coluna), ~3,4 GB em 43M × 10 colunas. Fica obsoleto se A1-opção 2 for feita.
- **Confiança:** média; baixa prioridade.

*Nenhum agente achou SQL do laço de matching em que o Python seja melhor. RANK vs FIRST no Jaro e `information_schema` vs `dbExistsTable` foram testados e são equivalentes.*

---

## B. O que o Python pode aprender com o R

### B1. Descartar tabelas quando nenhuma etapa seguinte precisa delas — **maior item de memória no Python**
- **Evidência:**
  - Não há **nenhum** `DROP` em `python-package/geocodebr/`.
  - O R chama `dropa_tabelas_obsoletas()` a cada etapa (`geocode.R:579-583`, helper em `utils.R:828-874`). Depois do laço, derruba tudo mais `input_padrao_db` (`geocode.R:597-598`), e ao fim dos empates `output_db`, `empates_classif` e `ids_empatados` (`trata_empates_geocode_duckdb.R:68, 306-308`).
  - No Python, as 8 tabelas de referência, os 2 `unique_logr_*`, `input_padrao_db`, `output_db`, `output_db2`, `empates_classif` e `geocodebr_result` convivem até `close_geocodebr_db`.
- **Medido (agentes 2, 3, 4):**
  - Pico de working set, 20k: 1.887 → 1.650 MB (−13%).
  - Pico de working set, 1M: 3.743 → 2.495 MB (**−33%**); o R fica em 2.180 MB.
  - Memória do DuckDB no fim do laço, 20k: 1.656 → 23 MB.
  - Memória do DuckDB na fase pós-matching, 1M: 2.100–2.500 MB → ~190 MB.
  - O `con.close()` cai de 0,5–1,9 s para 0,03–0,4 s. O `close` de 2:56 em 10M no heap legado (`benchmarks/resultados_benchmark.md`) é o mesmo efeito em escala.
- **Intervenção:** P para os `DROP`s pós-laço e pós-empates. M (~40–50 linhas) para o descarte progressivo, portando `tabelas_ainda_necessarias` para `match_types.py`.
- **Benefício:**
  - Memória: −13% a −33% de pico medido. Em escala nacional, o próprio R estima ~10 GB por tabela `*_numero_*`, e é isso que decide entre caber na RAM, fazer spill ou dar OOM.
  - Tempo: sem ganho total mensurável (os `free`s só acontecem mais cedo), exceto o `close`. No heap legado do Windows, menos volume de alocação reduz a contenção.
- **Confiança:** alta. Os **quatro** agentes apontaram isso.

### B2. Deduplicar antes do Jaro — **maior item de tempo no SQL do Python**
- **Evidência:** `python-package/geocodebr/string_dist.py:22-51` usa uma única forma de query: junta todo `tempidgeocodebr` elegível a todo o `unique_logr_*`. O R (`string_dist.R:34-129`) faz três coisas a mais:
  1. `usa_dedup`: o Jaro roda uma vez por `(chave, logradouro)` distinto quando a chave não tem cep + localidade.
  2. `cand_src` com `DISTINCT` nos candidatos, porque em chaves mais curtas (pn02/pl02) o mesmo logradouro se repete por localidade.
  3. `filtro_sem_numero`: em pl0k, linhas com número já foram testadas no pn0k correspondente.
- **Medido (mesmo estado, mín. de 5):**
  - 20k: as 6 etapas probabilísticas somam 1.432 ms (Python) vs 921 ms (forma R), −0,5 s por chamada (~5%).
  - 1M replicado: etapas do Python levaram 10–21 s cada vs 0,3–1 s no R. O pl02, por exemplo, levou 19 s vs 0,4 s, mas a replicação exagera esse ganho.
  - O comentário do R (`string_dist.R:44`) registra 178 s → ~60 s em 43,9M.
- **Intervenção:** M (~60 linhas, portar a query do R).
- **Benefício:**
  - Tempo: ~5% em 20k; em 10M+, provavelmente dezenas de segundos a minutos (inferido do ganho do R).
  - Memória: menos pares materializados antes do ranking.
- **Confiança:** alta. Agentes 2, 3 e 4 chegaram a isso.

### B3. Interpolação ponderada (`da*`/`pa*`): regex uma vez por grupo e `GROUP BY` curto
- **Evidência:** o Python aplica `REGEXP_REPLACE(endereco_completo, ...)` em **cada linha candidata** (~17–21 por endereço) e agrupa por essa string de ~70 bytes (`matching.py:121,143` e `:248,270`). O R aplica `REGEXP_REPLACE(FIRST(endereco_completo ORDER BY ...))` uma vez por grupo e agrupa por `tempidgeocodebr, numero, cep/localidade` (`match_weighted_cases.R:123-190`, `match_weighted_cases_probabilistic.R:193-282`).
- **Medido:** da01 em 1M: 1,94–2,25 s (Python) vs 1,00–1,33 s (forma R), resultado idêntico. Sem diferença em 20k.
- **Intervenção:** P–M (~30 linhas, duas queries).
- **Benefício:**
  - Tempo: ~−45% por etapa ponderada, em 7 etapas. Em 10M, ~−5 a −10 s por etapa (inferido).
  - Memória: menos estado de hash na agregação.
- **Confiança:** alta em ≥1M; irrelevante em 20k.

### B4. `update_input_db`: filtrar pela etapa atual e não contar duas vezes
- **Evidência:** `matching.py:288-303` faz `COUNT(*)`, depois `DELETE ... WHERE tempidgeocodebr IN (SELECT tempidgeocodebr FROM output_db)` **sem filtro**, depois outro `COUNT(*)`. Isso varre o `output_db` crescente 25 vezes. O R filtra por `tipo_resultado = '{match_type}'` e usa a contagem devolvida pelo `dbExecute` (`utils.R:79-111`). No Python, `con.execute("DELETE ...").fetchone()[0]` já devolve a contagem.
- **Medido (sintético, 10M, 25 etapas):** 10,8 s → 4,2 s (a parte do `DELETE` cai de ~9,5 s para ~2,9 s).
- **Intervenção:** P (~10 linhas).
- **Benefício:**
  - Tempo: ~6–7 s em 10M (~6% da fase de matching), crescendo com N × etapas. Zero em 20k.
  - Memória: tabela de hash menor.
- **Confiança:** alta. Agentes 1, 2, 3 e 4 chegaram a isso.

### B5. Projetar só as colunas necessárias ao carregar as tabelas de referência
- **Evidência:** `tables.py:33` usa `SELECT *`. O R usa `SELECT * EXCLUDE (code_muni, n_setor[, cod_setor])`, mantendo `cod_setor` só com `resultado_completo` (`register_cnefe_tables.R:60-76`).
- **Medido:**
  - Tabela `*_numero_cep_localidade` com 417 municípios: 986 → 897 MB (−9%).
  - A mesma tabela com SP+RJ+MG: 4,77 → 4,26 GB (−11%) e 7,2 → 6,5 s.
- **Intervenção:** P (passar `resultado_completo` para `register_cnefe_table`).
- **Benefício:** Memória: −9 a −11% em todas as 8 tabelas. Tempo: −10% no CTAS de cada tabela.
- **Confiança:** alta. Agentes 1, 2 e 4 chegaram a isso.

### B6. Não manter uma segunda cópia do resultado no DuckDB
- **Evidência:** `matching.py:385-395` faz `CREATE TEMP TABLE geocodebr_result AS ... ORDER BY`, e depois `geocode.py:308` faz `SELECT *` e `.to_arrow_table()`, então a cópia do DuckDB e a do Arrow coexistem. O R faz streaming direto com `COPY (query) TO parquet` (`utils.R:252-276`).
- **Medido (10M):**
  - Merge + fetch: 13,9–15,6 s (atual) vs 11,9 s no estilo R (`COPY` + `pq.read_table`).
  - O `geocodebr_result` segura ~2,6 GB do DuckDB junto com a cópia Arrow.
  - Em 1M com B1 já aplicado, o pico da fase final cai ~200 MB.
- **Intervenção:** P sem `h3_res`. M se o H3 (hoje uma UDF Python + `ALTER`/`UPDATE`, `matching.py:418-450`) passar a ser calculado sobre o Arrow depois do fetch.
- **Benefício:**
  - Tempo: −2 a −4 s em 10M.
  - Memória: −2,6 GB em 10M.
  - H3 por UDF + `UPDATE`: ~4 s por milhão de linhas por resolução, comparável ao `h3r` do R. O ganho aqui é de memória, não de tempo.
- **Confiança:** média no tempo (a exportação Arrow do DuckDB foi, nesta máquina, mais lenta que parquet ida e volta); alta na memória.

### B7. Itens pequenos de higiene (P cada, benefício baixo)
- **Liberar `df_padrao`** (e o `input_padrao_view`) depois de copiado para o DuckDB, como faz o `rm(input_padrao)` do R (`geocode.R:480-482`). São ~54 MB por milhão de linhas, ~2,3 GB em 43M.
- **Filtrar `unique_logr_*` também por `estado`** (`tables.py:95-97`). Hoje só filtra por município e traz homônimos de outras UFs: 299k vs 254k linhas (+18%) que nunca casam.
- **Iniciar `temp_lograd_determ` como `NULL`, não `''`** (`geocode.py`, `pl.lit("")`; o R usa `NA_character_`, `geocode.R:432`). Hoje o filtro `IS NOT NULL` nunca exclui nada. O custo é desprezível, mas há um risco latente de resultado se o CNEFE algum dia tiver logradouro vazio.

### B8. Rodar o motor num subprocesso com Segment Heap (decisão de projeto)
- **Evidência:** o R ganha o heap rápido "de graça" porque o `callr` lança `Rterm.exe` (inclusive quando o usuário está no RStudio, cujo `rsession.exe` usa o heap legado). O Python depende de o usuário trocar de interpretador; senão limita o DuckDB a 4 threads. O processo Python também retém 0,7–1 GB após cada chamada em 20k, e 7 → 4,3 → 3,3 GB em chamadas de 7,8M (`quality_reports/plans/2026-09-02_python_isolamento-subprocesso-geocode.md`).
- **Intervenção:** G (motor em `multiprocessing` com `set_executable(python-geocodebr-sh.exe)` e troca de dados por Arrow IPC/parquet).
- **Benefício:**
  - Tempo: a diferença do heap para quem usa o interpretador padrão (8,6 vs 14,3 s em 20k; 3:08 vs 11:47 em 10M). Custa ~1–2 s de startup, então só compensa a partir de ~100k linhas.
  - Memória: devolvida ao SO ao fim da chamada.
- **Por que importa:** é o espelho da lição A1. O `callr` tem um custo fixo, mas dá isolamento de memória e heap rápido. O ideal nos dois lados é **subprocesso com transporte barato** (Arrow/parquet, só as colunas necessárias).
- **Confiança:** média. O mecanismo é certo; o custo de engenharia é real.

---

## C. O que os dois podem melhorar

### C1. Merge "estreito": exportar só as colunas de resultado e anexar o input em memória — **maior ganho fora do laço**
- **Evidência:** hoje os dois ordenam e exportam a linha larga (todas as colunas do usuário + resultado), com `SELECT {x}, {y} FROM input_db LEFT JOIN y ORDER BY tempidgeocodebr` (`utils.R:250-258`; `matching.py:388-394`). Mas o chamador já tem o input intacto em memória. A alternativa é `SELECT y FROM range(N) LEFT JOIN y ORDER BY id`, seguida de concatenação de colunas: `setDF(c(enderecos, y))` no R, `append_column` sem cópia no Python.
- **Medido (10M, colunas idênticas):**
  - Python: 13,9–15,6 s → 7,9 s (fetch Arrow) ou 5,6 s (parquet).
  - R, leitura no pai: 18,3–24,3 s → 6,5 s. O ganho no `COPY` do filho não está contado.
  - Só a ordenação de linhas largas custa: 8,0 s vs 3,9 s.
- **Intervenção:** M em cada lado (`merge_results_to_input` + wrapper).
- **Ressalvas:**
  - Depende de `tempidgeocodebr` denso (R 1..N, Python 0..N−1).
  - Com `resolver_empates = FALSE` há várias linhas por id, então a junção vira `enderecos[idx, ]` / `Table.take`.
  - Os tipos das colunas do usuário passariam a sobreviver exatamente (factor ordenado, POSIXct com tz, categorical) em vez de normalizados pelo DuckDB. É uma mudança visível de tipo a revisar contra o teste de paridade.
- **Benefício:**
  - Tempo: −7 a −12 s por lado em 10M (medido), −1 a −2 s em 1M, ~5× isso em 43M (inferido).
  - Memória: sem segunda cópia larga do input no DuckDB ou no parquet.
- **Confiança:** alta no tempo; média no risco de implementação. No R, combina naturalmente com A1-opção 2.

### C2. Padronizar valores únicos, não linhas
- **Evidência:** `standardize.py` aplica `map_elements(enderecobr.<fn>)`, uma chamada Python→Rust por linha por campo, single-thread sob o GIL. Isso vale até para `estado` (27 valores) e `municipio` (≤5.570). O R chama as funções vetorizadas do `enderecobr`, mas também por linha.
- **Medido:**
  - Python, 1M replicado: 11,1 s → 0,54 s com unique → map → join, saída `equals`. A replicação exagera o ganho nos campos de alta cardinalidade.
  - R, uf/município/logradouro: 0,22/0,35/0,75 s → 0,06/0,07/0,13 s.
- **Intervenção:** P–M no Python (`standardize.py`); P no R, antes de chamar o `enderecobr`. É preciso preservar a semântica dos avisos (o Python conta nulos vs. input).
- **Benefício:**
  - Tempo no Python: a parte garantida (estado + município, ~20% do custo por linha) dá ~10–20 s dos 54 s de padronização em 10M. Mais se cep/bairro se repetirem, como no CadÚnico.
  - Tempo no R: ~1–3 s em 10M.
  - Memória: neutra.
- **Confiança:** alta para estado/município; média para o resto.

### C3. Calcular `precisao` na projeção final em vez de `ALTER` + `UPDATE`
- **Evidência:** `UPDATE` idêntico nos dois lados (`utils.R:122-153`; `matching.py:306-325`).
- **Medido:** 0,07–0,14 s em 1M; 0,79 s em 10M.
- **Intervenção:** P. Encaixa na projeção estreita de C1.
- **Benefício:** ~−0,8 s em 10M e uma coluna VARCHAR a menos armazenada em `output_db2`.
- **Confiança:** média.

### C4. O arquivo `.duckdb` em disco não é usado de fato; definir `memory_limit`/`temp_directory`
- **Evidência:** os dois abrem um banco em arquivo "para suportar volumes maiores que a RAM" (`create_geocodebr_db.R:12-27`; `db.py:15-24`), mas **todas** as tabelas do pipeline são `TEMP` e nunca tocam o arquivo.
- **Medido:** uma tabela temp de 21M linhas com `memory_limit='1GB'` deixou o arquivo com 12 KB. Em disco e `:memory:` fazem o mesmo spill (~2 GB em `temp_directory`) no mesmo tempo (13,5 vs 13,2 s).
- **O que importa de verdade:** `memory_limit` (padrão 80% da RAM, sem descontar as cópias no host) e `temp_directory`, que nenhum dos pacotes define.
- **Intervenção:** P.
- **Benefício:** nenhum em tempo. Controle explícito do teto de memória (inferido) e limpeza de arquivo mais simples.
- **Confiança:** alta nos fatos.

### C5. Layout mais enxuto das tabelas de referência (pré-processamento)
- **Medido (tabela `*_numero_cep_localidade`, 417 municípios):**
  - Projeção atual do R: 897 MB.
  - Chaves `code_muni`/`cep` como INTEGER em vez de VARCHAR: 732 MB (−18%).
  - Deixando `endereco_completo` fora das tabelas de join e buscando-o só para os casados: 409 MB (−54%).
- **Por que importa:** o pico de memória nos dois pacotes é a janela da3→pn3, em que as duas tabelas `*_numero_*` estão vivas ao mesmo tempo. Nacionalmente são ~10 GB cada.
- **Intervenção:** G (`padronizacao_cnefe` + SQL de match dos dois lados + padronização do input). A paridade só se mantém se os dois mudarem juntos.
- **Confiança:** média. A memória foi medida; o efeito no tempo de join não.

---

## Testado e descartado (para não repropor)

| Ideia | Resultado |
|---|---|
| Listas constantes `IN ('AC',...)` em vez de `IN (SELECT DISTINCT ...)` ao registrar tabelas | Sem ganho; o DuckDB 1.5.5 já empurra o filtro para o scan do parquet |
| Semi-join em pares (estado, município) | Mesmas linhas, mais lento (3,4 vs 1,4 s) |
| Join direto contra `read_parquet` em vez de materializar | Pior: `*_numero_cep_localidade` serve ~9 etapas e o scan lê 30M linhas a cada uma |
| Resolver empates no próprio `output_db` (DELETE + INSERT) | Empate técnico (1M: 0,76 vs 1,05 s; 10M: 6,05 vs 5,50 s) |
| `POSITIONAL JOIN` para evitar ordenar linhas largas | Mais lento (16–31 s) |
| Trocar `dbWriteTable` do R por register + CTAS | Marginal, e já avaliado em `quality_reports/plans/2026-08-27_registro-input-padrao.md` |
| RANK vs `FIRST` no Jaro | Sem diferença em 20k e 1M |

## Prioridade sugerida

| # | Lição | Lado | Intervenção | Ganho principal | Escala em que importa |
|---|---|---|---|---|---|
| 1 | B4 `update_input_db` filtrado | Py | P | tempo | ≥1M |
| 2 | B1 + B5 descartar tabelas e projetar colunas | Py | P–M | **memória (−33%)** | todas; decisiva em escala nacional |
| 3 | B2 dedup no Jaro | Py | M | **tempo** | todas; forte em ≥1M |
| 4 | A1 transporte do input no `callr` | R | P–M | **tempo** (−2 a −4 s em 20k) | todas |
| 5 | B3 regex por grupo na interpolação | Py | P–M | tempo (−45%/etapa) | ≥1M |
| 6 | C1 merge estreito | ambos | M+M | tempo + memória | ≥1M |
| 7 | C2 padronizar valores únicos | Py (R menor) | P–M | tempo | ≥1M |
| 8 | B6, C3, A2, B7 | — | P | pequeno | ≥10M |
| 9 | B8 subprocesso com Segment Heap; C5 layout CNEFE | Py / ambos | G | tempo/memória | decisão de projeto |

Os itens 1, 2, 3 e 5 são portes diretos de código R cuja equivalência de resultado já está provada, então o risco de paridade é baixo. Mesmo assim, rodar `pytest -m r_parity` após cada um.

## Correções à documentação encontradas no caminho

- **CLAUDE.md, "Etapa 5 — empates":** diz que a distância usa `LEAD()`. Os dois pacotes usam **`LAG()`**, de propósito (comentário em `trata_empates_geocode_duckdb.R:155`).
- **CLAUDE.md, "Etapa 3":** diz que o banco fica "em disco, não em memória, para suportar volumes maiores que a RAM". Na prática, todas as tabelas são `TEMP` e o spill vem do buffer manager, não do arquivo (ver C4).

Scripts e logs dos agentes: `%TEMP%/claude/R--Dropbox-git-geocodebr/d5c06b95-.../scratchpad/agent{1..4}/` (temporários, não versionados).
