"""Verificação rápida do efeito do Segment Heap (duckdb/duckdb#24027).

Roda geocode() com o arquivo passado como argumento. Nesse exemplo,
os campos do arquivo estão hard coded, alterar aqui se necessário

Sem SegmentHeap:
    python verifica_segment_heap_geocode.py path/arquivo.parquet
Com SegmentHeap:
    python-sh.exe verifica_segment_heap_geocode.py path/arquivo.parquet


"""

import sys
import time

import geocodebr

path_base = sys.argv[1] if len(sys.argv) > 1 else "../../data/sample_cad_unico.parquet"

print(path_base)

# Alterar aqui se necessário
campos = geocodebr.definir_campos(
  logradouro = 'logradouro',
  numero = 'numero',
  cep = 'cep',
  localidade = 'bairro',
  municipio = 'code_muni',
  estado = 'abbrev_state'
)


for i in range(5):
    print(f'---- Rodada {i+1} ---- \n')
    inicio = time.perf_counter()
    resultado = geocodebr.geocode(
            enderecos=path_base,
            campos_endereco=campos,
            resultado_completo=True,
            resolver_empates=True,
            verboso=False,
        )
    fim = time.perf_counter()
    print(f"tempo total: {(fim-inicio)/60:.2f} minutos")

print(f"Arquivo={path_base} | tempo total: {(fim-inicio)/60:.2f} minutos")

# Cad único completo:
# $env:PYTHONPATH = "\\storage6\usuarios\CGDTI\IpeaDataLab\repositorios\camila_brito\geocodebr\.venv\Lib\site-packages;\\storage6\usuarios\CGDTI\IpeaDataLab\repositorios\camila_brito\geocodebr\python-package"; & "D:\Users\R3529595\AppData\Roaming\uv\python\cpython-3.10-windows-x86_64-none\python-sh.exe" ".\verifica_segment_heap_geocode.py" "../../data/cad_unico.parquet"
# ../../data/cad_unico.parquet
# 10:09:17: Utilizando dados do CNEFE armazenados localmente
# 10:09:17: Padronizando enderecos de entrada
# \\storage6\usuarios\CGDTI\IpeaDataLab\repositorios\camila_brito\geocodebr\python-package\geocodebr\geocode.py:107: UserWarning: Alguns números não puderam ser convertidos para integer, introduzindo NAs no resultado.
#   df_padrao = enderecobr_padronizar_enderecos(
# 10:12:48: Geolocalizando enderecos
# Geolocalizando: 100%|█████████████████████████████████████████████████████████████████████████████████████████████████████████████████▉| 43879144/43882020 [, dm01]
# 10:18:01: Preparando resultados
# Foram encontrados e resolvidos 2918650 casos de empate.
# 10:18:28: Adicionando coluna de precisão
# 10:18:30: Juntando com colunas do input
# 10:18:57: Materializando tabela final em arrow
# 10:19:29: Finalizado
# 10:19:40: Conexão fechada
# Arquivo=../../data/cad_unico.parquet | tempo total: 10.48 minutos


# Rodadas seguidas da sample do cad único !! não houve deterioração !!

# ../../data/sample_cad_unico.parquet
# ---- Rodada 1 ---- 

# tempo total: 3.45 minutos
# ---- Rodada 2 ---- 

# tempo total: 3.22 minutos
# ---- Rodada 3 ---- 

# tempo total: 3.53 minutos
# ---- Rodada 4 ---- 

# tempo total: 3.17 minutos
# ---- Rodada 5 ---- 

# tempo total: 3.21 minutos
# Arquivo=../../data/sample_cad_unico.parquet | tempo total: 3.21 minutos