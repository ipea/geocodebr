# Auditoria de dados: CNEFE `dados_agregados` v0.4.1 × v0.5.0

**Data:** 2026-09-15
**Fontes:**
`\\STORAGE6\bases\DADOS\PUBLICO\CNEFE\cnefe_padrao_geocodebr\2022\{v0.4.1,v0.5.0}\dados_agregados`
**Scripts:** [`compare_cnefe_releases.R`](compare_cnefe_releases.R) (metadados) ·
[`compare_cnefe_values.R`](compare_cnefe_values.R) (conteúdo)

---

## Veredito em uma linha

**O v0.5.0 é 27,8% menor (−765,7 MB) porque `lat` e `lon` passaram de `double` (8 bytes) para
`float` (4 bytes). Essas duas colunas respondem por 100% do encolhimento. Não houve perda de dados** —
a soma de `n_casos` cai 0,006%, e as ~57 mil linhas a menos são *renomeações* de logradouro produzidas por
uma nova versão da padronização, não registros descartados.

O corte de `double` para `float` reduz as casas decimais armazenadas de ~13 para ~6, mas custa no máximo
**45 cm** de posição (§5.1) — mais de 1.000× menos que o `desvio_metros` médio de 607 m. **Única pergunta em aberto:**
16,95% das coordenadas se moveram mais do que o cast consegue explicar (§5.2).

---

## 1. Resumo por tabela

As 12 tabelas existem nas duas versões, com os mesmos nomes de arquivo. **Todas** ganharam 2 colunas
(`code_muni`, `n_setor`) e tiveram 3 mudanças de tipo (`lat`, `lon`, `cod_setor`). Nenhuma coluna foi removida.

| tabela | linhas v0.4.1 | linhas v0.5.0 | Δ linhas | Δ % | cols v0.4.1 | cols v0.5.0 | MB v0.4.1 | MB v0.5.0 | Δ MB % |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `municipio` | 5,570 | 5,570 | 0 | 0% | 8 | 10 | 0.2 | 0.1 | -14.7% |
| `municipio_cep` | 928,913 | 928,905 | -8 | -0.001% | 9 | 11 | 20.0 | 10.7 | -46.3% |
| `municipio_cep_localidade` | 1,724,915 | 1,722,368 | -2,547 | -0.148% | 10 | 12 | 43.0 | 28.0 | -35.0% |
| `municipio_localidade` | 518,429 | 517,547 | -882 | -0.170% | 9 | 11 | 14.0 | 10.7 | -23.1% |
| `municipio_logradouro` | 2,625,065 | 2,618,772 | -6,293 | -0.240% | 9 | 11 | 70.7 | 55.3 | -21.8% |
| `municipio_logradouro_cep` | 3,035,632 | 3,030,776 | -4,856 | -0.160% | 10 | 12 | 85.3 | 67.6 | -20.7% |
| `municipio_logradouro_cep_localidade` | 3,999,311 | 3,993,584 | -5,727 | -0.143% | 11 | 13 | 116.9 | 94.3 | -19.3% |
| `municipio_logradouro_localidade` | 3,723,068 | 3,716,920 | -6,148 | -0.165% | 10 | 12 | 104.5 | 83.1 | -20.4% |
| `municipio_logradouro_numero` | 48,878,977 | 48,865,689 | -13,288 | -0.027% | 10 | 12 | 541.5 | 378.6 | -30.1% |
| `municipio_logradouro_numero_cep` | 49,713,656 | 49,706,450 | -7,206 | -0.014% | 11 | 13 | 568.1 | 403.0 | -29.1% |
| `municipio_logradouro_numero_cep_localidade` | 50,229,982 | 50,225,509 | -4,473 | -0.009% | 12 | 14 | 606.3 | 439.6 | -27.5% |
| `municipio_logradouro_numero_localidade` | 50,050,763 | 50,045,035 | -5,728 | -0.011% | 11 | 13 | 587.6 | 421.3 | -28.3% |
| **TOTAL** | **215,434,281** | **215,377,125** | **-57,156** | **-0.027%** | — | — | **2,757.9** | **1,992.3** | **-27.8%** |

Codec (ZSTD), número de *row groups* e versão de formato do parquet são **idênticos** entre as versões —
não houve mudança de compressão.

---

## 2. Schema: o que mudou (igual nas 12 tabelas)

| coluna | v0.4.1 | v0.5.0 | status |
|---|---|---|---|
| `lat` | `double` | **`float`** | TIPO_ALTERADO |
| `lon` | `double` | **`float`** | TIPO_ALTERADO |
| `cod_setor` | `string` | **`int64`** | TIPO_ALTERADO |
| `code_muni` | — | `int32` | **ADICIONADA** |
| `n_setor` | — | `int32` | **ADICIONADA** |
| `estado`, `municipio`, `endereco_completo`, `n_casos`, `desvio_metros` | — | — | idênticas |
| `cep`, `logradouro`, `numero`, `localidade` (quando presentes) | — | — | idênticas |

- **`cod_setor` → `int64` é lossless.** Verificado: o código tem sempre 15 caracteres e nunca começa com
  zero (`count(cod_setor LIKE '0%') = 0`), então nenhuma informação se perde na conversão. Bônus: a cobertura
  *melhorou* — nulos em `municipio_cep` caem de 496.851 para 427.218.
- **`code_muni`** é o código IBGE de 7 dígitos do município (faixa 1100015–5300108).
- **`n_setor`** é a contagem de setores censitários cobertos por cada linha agregada (1–610).

---

## 3. Por que encolheu: atribuição byte a byte

Somando as 12 tabelas, o delta de bytes comprimidos por coluna:

| coluna | Δ MB comprimido | Δ MB descomprimido | % do encolhimento |
|---|---:|---:|---:|
| **`lon`** | **−402.3** | −823.0 | **52.5%** |
| **`lat`** | **−363.8** | −822.0 | **47.5%** |
| `cep` | −2.7 | −1.2 | 0.4% |
| `cod_setor` | −2.4 | −49.1 | 0.3% |
| `endereco_completo` | −1.9 | −1.5 | 0.2% |
| `localidade` | −1.0 | −0.1 | 0.1% |
| `desvio_metros` | −0.2 | −0.2 | 0.0% |
| `n_casos`, `logradouro`, `numero`, `estado`, `municipio` | +0.6 | −1.6 | −0.1% |
| `code_muni` *(nova)* | +0.5 | +0.7 | −0.1% |
| `n_setor` *(nova)* | **+6.9** | +44.9 | **−0.9%** |
| **soma das colunas** | **−766.4** | — | — |
| *delta real dos arquivos* | *−765.7* | — | — |
| *resíduo (footers/page headers)* | *+0.7 (0,09%)* | — | — |

**`lat` + `lon` = −766,1 MB, ou 100,1% do encolhimento líquido de −765,7 MB.** Tudo o mais se cancela: os
−8,2 MB das outras colunas existentes são quase exatamente compensados pelos +7,4 MB das duas colunas novas.

> `n_setor` é a única coluna que *cresce* de forma relevante (+6,9 MB comprimidos, +44,9 MB descomprimidos).
> Isso é custo de download pago por todo usuário do pacote — ver §6.

### 3.1 Por que `lat`/`lon` encolheram tanto

O lado **descomprimido** é aritmética trivial: 215.434.281 valores × 8 bytes = 1.643,6 MiB no v0.4.1 contra
215.377.125 × 4 = 821,6 MiB no v0.5.0. Exatamente a metade, por coluna.

O lado **comprimido** é o que explica a magnitude:

| | comp. v0.4.1 | comp. v0.5.0 | Δ MB | bits/valor v0.4.1 | bits/valor v0.5.0 | ratio v0.4.1 | ratio v0.5.0 |
|---|---:|---:|---:|---:|---:|---:|---:|
| `lat` | 749.8 | 386.0 | −363.8 | 29.2 | 15.0 | 2.19× | 2.13× |
| `lon` | 724.4 | 322.0 | −402.3 | 28.2 | 12.5 | 2.27× | **2.55×** |

O ZSTD já vinha espremendo o `double` de 64 para ~29 bits por valor, e empacava ali. Um float64 de
coordenada se divide em duas metades de natureza oposta: sinal, expoente e mantissa alta são altamente
repetitivos (endereços do mesmo município compartilham os primeiros dígitos, e os dados estão agrupados por
município), enquanto os bits finais da mantissa são essencialmente aleatórios — resíduo aritmético de dividir
uma soma por uma contagem. O ZSTD esmaga a primeira metade e não tem o que fazer com a segunda.

O cast para `float` descarta justamente essa metade incompressível. A magnitude confirma a leitura: se os 32
bits removidos fossem ruído puro, o ganho seria os 32 bits/valor inteiros (−822 MB); se fossem redundantes,
seria zero. O ganho real é de ~14 bits/valor — ou seja, o ZSTD já colapsava cerca de metade deles, e o resto
era entropia genuína (a precisão falsa de §5.1), paga a preço cheio em disco.

`lon` ainda compensa *melhor* depois do cast (2,27× → 2,55×), enquanto `lat` fica estável (2,19× → 2,13×).
Leitura provável: as longitudes brasileiras cabem todas em −74…−35, uma faixa estreita de expoentes; as
latitudes vão de −34 a +5 e cruzam o zero, cobrindo muito mais expoentes distintos de `float32` e repetindo
menos.

---

## 4. As −57.156 linhas: renomeação, não perda

### 4.1 `n_casos` está preservado

A soma de `n_casos` é o teste direto de "perdemos endereços?":

| família de tabelas | Σ `n_casos` v0.4.1 | Σ `n_casos` v0.5.0 | Δ | Δ % |
|---|---:|---:|---:|---:|
| `municipio*` (sem logradouro) | 106,379,950 | 106,373,461 | −6,489 | **−0.0061%** |
| `municipio_logradouro*` | 103,418,368 | 103,412,454 | −5,914 | **−0.0057%** |
| `municipio_logradouro_numero*` | 80,511,038 | 80,509,607 | −1,431 | **−0.0018%** |

Nulos em `lat`/`lon`: **zero** nas duas versões, em todas as 12 tabelas.

### 4.2 O anti-join mostra *rotatividade*, não remoção

| tabela | chaves só em v0.4.1 | chaves só em v0.5.0 | Δ líquido |
|---|---:|---:|---:|
| `municipio_cep` | 10 | 2 | −8 |
| `municipio_localidade` | 3,154 | 2,272 | −882 |
| `municipio_cep_localidade` | 12,489 | 9,942 | −2,547 |
| `municipio_logradouro` | **95,049** | **88,756** | −6,293 |

Nenhuma das duas versões tem chaves duplicadas. O padrão — dezenas de milhares de chaves *saindo* e quase
tantas *entrando*, com delta líquido pequeno — é assinatura de mudança de string, não de exclusão.

### 4.3 A causa, confirmada por amostra

Logradouros de SP que sumiram do v0.4.1 × os que apareceram no v0.5.0, lado a lado (mesmo `n_casos`, o que
prova serem os **mesmos registros**, apenas renomeados):

| v0.4.1 | v0.5.0 | `n_casos` | padrão |
|---|---|---:|---|
| `RODOVIA SP 270 RAPOSO TAVARES` | `RODOVIA SP-270 RAPOSO TAVARES` | 2013 | hífen em código de rodovia |
| `RODOVIA ... SP 280 KM 292 ...` | `RODOVIA ... SP-280 KM 292 ...` | 1033 | idem |
| `AVENIDA PRESIDENTE JUSCELINO KUBIS**CH**ECK` | `AVENIDA PRESIDENTE JUSCELINO KUBI**TSCH**EK` | 855 | correção de grafia |
| `**RUA** ESTRADA VELHA DE JACAREI` | `ESTRADA VELHA DE JACAREI` | 553 | tipo de logradouro redundante removido |
| `RODOVIA VICINAL MDN 0**10**` | `RODOVIA VICINAL MDN 10` | 539 | zero à esquerda removido |

E em `municipio.parquet`, a única chave que não casa (5.569 de 5.570 pares) é uma renomeação **oficial do IBGE**:

| v0.4.1 | v0.5.0 |
|---|---|
| `RN / JANUARIO CICCO` | `RN / BOA SAUDE` |

Ou seja: o v0.5.0 foi gerado com uma versão mais nova da padronização de endereços (`{enderecobr}`). A perda
de linhas distribui-se por **todas as 27 UFs** (nenhuma com delta zero), o que é consistente com uma mudança de
regra global, e não com um problema regional de ingestão. As UFs com maior perda relativa são DF (−0,30%),
RR (−0,12%), MT/GO/MA (−0,095%).

---

## 5. As coordenadas: perderam casas decimais, não perderam precisão útil

### 5.1 Casas decimais: de ~13 para ~6

Casas decimais efetivamente armazenadas em `municipio_cep`:

| | média `lat` | máx `lat` | média `lon` | máx `lon` |
|---|---:|---:|---:|---:|
| v0.4.1 (`double`) | 12.80 | 20 | 12.42 | 15 |
| v0.5.0 (`float`) | 5.81 | **7** | 5.57 | **7** |

Sim, houve corte — mas as 13 casas eram **precisão falsa**. São coordenadas médias: um `double` carrega 15–17
dígitos significativos, e tudo depois do 6º ou 7º é resíduo aritmético da divisão da soma pela contagem, não
informação sobre onde o endereço está.

O que importa é quanto o truncamento custa em metros. Fazendo o cast do `double` do v0.4.1 para `float` e
medindo contra o original (isola o cast, sem contaminação de recomputação):

| | erro médio | erro máximo |
|---|---:|---:|
| `lat` | 3,96e-07° = **4,4 cm** | 1,90e-06° = **21 cm** |
| `lon` | 9,57e-07° = **10,1 cm** | 3,81e-06° = **40 cm** |

**Teto de 40 cm, típico de 10 cm** — contra um `desvio_metros` médio de 607 m na mesma tabela. A quantização
é cerca de 1.500× menor que a incerteza posicional que o CNEFE já carrega. Casas decimais se perderam;
precisão utilizável, não.

### 5.2 Deslocamento observado entre as versões

Comparando `lat`/`lon` nas chaves que existem nas duas versões (`municipio_cep`, 928.903 pares), a distância
haversine entre a coordenada v0.4.1 e a v0.5.0:

| faixa de deslocamento | pares | % |
|---|---:|---:|
| < 1 m | 832,074 | **89.6%** |
| 1–10 m | 87,361 | 9.4% |
| 10–100 m | 8,581 | 0.92% |
| 100 m – 1 km | 855 | 0.09% |
| > 1 km | **32** | 0.003% |

Mediana **0,149 m**; p95 2,4 m; p99,9 95,8 m; máximo 6,7 km.

- A mediana de 0,149 m é da mesma ordem do ULP de `float32` nessas magnitudes e bate com o erro de
  quantização medido em §5.1 (4–10 cm em média, teto de 40 cm). **A massa da distribuição é o arredondamento
  `double`→`float`, como esperado**, e é irrelevante diante da acurácia do próprio CNEFE (`desvio_metros`
  médio de ~607 m nessa tabela).
- `desvio_metros` médio praticamente não muda (607,0 → 606,4), e `n_casos` difere em apenas 517 dos 928.903
  pares — então o agregado não foi reconstruído sobre um conjunto diferente de endereços.
- **Ressalva — 16,95% do deslocamento não vem do cast.** O teto medido em §5.1 é de 21 cm em `lat` e 40 cm em
  `lon`, ou ~45 cm combinados. Acima disso o `float32` não consegue explicar o movimento:

  | deslocamento | pares | % | explicável pelo cast? |
  |---|---:|---:|---|
  | ≤ 0,45 m (teto do cast) | 771,491 | 83.05% | sim |
  | 0,45–1 m | 60,583 | 6.52% | **não** |
  | 1–10 m | 87,361 | 9.40% | **não** |
  | > 10 m | 9,468 | 1.02% | **não** |

  Coerente com isso, um corte puro de precisão produziria `lat_v041::FLOAT = lat_v050` exatamente, e isso só
  vale para 56% dos pares. Ou seja: **157.412 linhas (16,95%) tiveram a coordenada recalculada**, não apenas
  arredondada. A magnitude é pequena (p95 de 2,4 m, contra `desvio_metros` de 607 m) e `n_casos` difere em
  apenas 517 pares, então não é reagregação sobre outro conjunto de endereços — mas a causa precisa ser
  confirmada com quem gerou o v0.5.0 (ordem de soma, aritmética feita em `float` em vez de `double`, ou
  trimming de outliers). É a única pergunta em aberto desta auditoria.

---

## 6. Impacto no `{geocodebr}` — pendências

Levantado sobre `r-package/R/`; são itens a verificar antes de apontar o `data_release` para o v0.5.0.

1. **`cod_setor` declarado como `string` no schema de saída.**
   `R/geocode.R:405` cria `output_db` com `cod_setor = arrow::string()`, mas a tabela de referência v0.5.0
   entrega `int64`. O DuckDB faz o cast implícito BIGINT→VARCHAR, então provavelmente não quebra, mas o
   caminho não está testado. Rodar um `geocode(resultado_completo = TRUE)` contra o v0.5.0 e conferir o valor
   e a classe da coluna. `R/match_helpers.R:101-107` e `R/utils.R:178` também tocam `cod_setor`.

2. **`n_setor` não é consumido em lugar nenhum.** `grep -rn "n_setor" R/` não retorna nada. São +6,9 MB
   comprimidos (+44,9 MB descomprimidos) de download para todo usuário, sem uso no pacote. Ou o pacote passa
   a expor a coluna, ou ela deveria sair do pré-processamento.

3. **`code_muni` também não vem dessas tabelas hoje.** O único uso (`R/geocode_reverso.R:129`) lê `code_muni`
   de `inst/extdata/munis_bbox_2022.parquet`, não do CNEFE agregado. Custo baixo (+0,5 MB), mas é redundância
   a decidir conscientemente.

4. **A renomeação de logradouros muda resultados de match.** ~95 mil logradouros mudaram de string. Endereços
   de usuário padronizados por uma versão *antiga* do `{enderecobr}` (`padronizar_enderecos = FALSE`, quando o
   usuário traz as colunas `*_padr` prontas) podem deixar de casar deterministicamente e cair para o match
   probabilístico. Vale checar qual versão do `{enderecobr}` gerou o v0.5.0 e alinhar o mínimo na `DESCRIPTION`.

5. **`data_release` em `R/cache.R:1`** precisa apontar para uma tag existente em `ipeaGIT/padronizacao_cnefe`
   ao migrar.

---

## 7. Como reproduzir

```bash
cd L:/Proj_acess_oport/git_rafa/geocodebr
Rscript quality_reports/diagnoses/compare_cnefe_releases.R   # metadados, ~10 s (só lê footers)
Rscript quality_reports/diagnoses/compare_cnefe_values.R     # conteúdo, ~1 min
```

Ambos aceitam os dois diretórios como argumentos, então servem para o próximo release. CSVs intermediários
saem em `$CNEFE_AUDIT_OUT` (padrão: `tempdir()`): `resumo_tabelas.csv`, `schema_diff.csv`,
`bytes_por_coluna.csv`, `reconciliacao_bytes.csv`, `passoA_por_estado.csv`, `passoA_delta_por_uf.csv`,
`passoB_antijoin.csv`, `passoC_precisao.csv`.

**Verificação da atribuição de bytes:** a soma dos deltas por coluna bate com o delta real dos arquivos com
resíduo de +0,7 MB (0,09%) — overhead de footer e page header do parquet. Por tabela o resíduo fica abaixo de
1%, exceto em `municipio.parquet` (−5,1%), onde o arquivo tem só 150 KB e o footer pesa proporcionalmente mais.
