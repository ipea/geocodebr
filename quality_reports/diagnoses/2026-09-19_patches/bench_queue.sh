#!/usr/bin/env bash
# Sequential 43.9M benchmark queue. Each arg is "<label>:<libname>[:mode]" (mode = core|geocode, default core).
# One Rscript per arm; nothing else should run on the machine meanwhile.
SCR="C:/Users/r1701707/AppData/Local/Temp/3/claude/L--Proj-acess-oport-git-rafa-geocodebr/61ca0503-92cd-4af1-9e4a-9e71e4fbb810/scratchpad"
DATA="L:/Proj_acess_oport/git_rafa/geocodebr/df_full_data.parquet"
cd "$SCR"
for spec in "$@"; do
  label="${spec%%:*}"; rest="${spec#*:}"; lib="${rest%%:*}"; mode="${rest#*:}"
  [ "$mode" = "$rest" ] && mode="core"
  echo "################ $label (lib_$lib, mode=$mode)  start $(date)"
  Rscript prof_geocode.R --lib="$SCR/lib_$lib" --data="$DATA" --label="$label" --mode="$mode" --save=TRUE --out="$SCR/runs" > "runs/$label.log" 2>&1
  echo "exit=$?" >> "runs/$label.log"
  grep -E "^exit=|^Error|Execution halted" "runs/$label.log" | head -3
  grep -A6 "SUMMARY" "runs/$label.log" | tail -6
  echo "################ $label end $(date)"
done
echo "BENCH QUEUE DONE $(date)"
