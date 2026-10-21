#!/usr/bin/env bash
# run_matrix.sh: back-to-back pairs of the team test case, one setting changed per pair (Scout, Oct 14, 2026).
#   bash run_matrix.sh <tag> <extras...>     e.g. bash run_matrix.sh kvf16 --es type_k f16 --es type_v f16
# Cool-down before the first run of a pair: wait until thermal status 0 and AP <= 40 C (checked every 30 s,
# at most 15 min; the reading is logged either way). The second run starts straight after the first (team plan).
set -u
export MSYS_NO_PATHCONV=1
HERE="$(cd "$(dirname "$0")" && pwd)"
ADB="${ADB:-$(cygpath -u "$LOCALAPPDATA")/Android/Sdk/platform-tools/adb.exe}"
TAG="$1"; shift
# Oct 15: MODEL, PROMPT, RUNPREFIX and PKG/ACT (passed through to run_app_bench.sh) can be set from outside,
# e.g. for the LiteRT-LM app and the 3,095-token side test; defaults are the Oct 14 llama.cpp team test case.
MODEL="${MODEL:-Qwen3.5-0.8B-Q8_0.gguf}"
PROMPT="${PROMPT:-SYNTHETIC-ENGINEERING-ONLY_qwen35_4096.txt}"
RUNPREFIX="${RUNPREFIX:-q35-q8-${DEV:-cpu}-4096x1000}"
NP="${NP:-1000}"   # Oct 21: tokens out; with --ei ignore_eos 0 it is a cap, the model may stop sooner
"$ADB" shell am force-stop "${PKG:-com.example.llama.aichat}"
for i in $(seq 1 30); do
  s=$("$ADB" shell 'echo "$(dumpsys thermalservice | grep -m1 "Thermal Status" | grep -o "[0-9]*$") $(dumpsys thermalservice | grep -m1 "mName=AP," | grep -o "mValue=[0-9.]*" | cut -d= -f2)"' | tr -d '\r')
  st=${s% *}; ap=${s#* }
  if [ "$st" = 0 ] && awk "BEGIN{exit !($ap <= 40)}"; then break; fi
  sleep 30
done
echo "$(date -Iseconds) pair $TAG cool-down done after $((i-1)) checks: status $st, AP $ap C" | tee -a "$HERE/results/runs.log"
for r in 1 2; do
  bash "$HERE/run_app_bench.sh" "$RUNPREFIX-$TAG-r$r" "$MODEL" "$PROMPT" "$NP" "$@" 2>&1 | grep -v "Broken pipe"
done
