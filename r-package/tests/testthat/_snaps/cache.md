# messages are formatted correctly

    Code
      definir_pasta_cache(path = NULL)
    Message <geocodebr_cache_dir>
      i Definido como pasta de cache '<path_to_default_dir>'.

---

    Code
      definir_pasta_cache("aaa")
    Message <geocodebr_cache_dir>
      i Definido como pasta de cache 'aaa'.

# behaves correctly

    Code
      listar_dados_cache(print_tree = TRUE)
    Output
      <path_to_cache_dir>
      +-- hello.parquet
      \-- oie.parquet

# deletar_pasta_cache behaves correctly

    Code
      res <- deletar_pasta_cache()
    Message <geocodebr_message_removed_cache_dir>
      v Deletada a pasta de cache que se encontrava em '<path_to_cache_dir>'.

