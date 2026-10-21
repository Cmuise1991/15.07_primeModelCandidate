#!/usr/bin/env bash
# run_quality_eos.sh: note-quality runs with the end token allowed (Scout, Oct 21, 2026).
# Chad, Oct 21: run "without a mandatory 1k tokens and let the model do what the model does". Same as the speed
# runs (Q8_0, llama.cpp on the A17, greedy, each model's fastest CPU setting, same prompt files) except
# --ei ignore_eos 0: the model stops at its own end token, with a 2,000-token cap so a loop still ends.
# Three models (Chad, Oct 21): Qwen3.5-0.8B, Gemma 3 1B IT, MiniCPM-V 4.7 1B (uses the Qwen3.5 prompt files; its
# template renders them byte for byte the same, Oct 17). Two prompts: Jonathan's one-patient visit (the fair quality
# test) and the team two-visit case. NOT speed rows: tokens out differ per model. Outputs go to results/quality_eos/
# so build_workbook.py keeps them off the team sheets.
set -u
export MSYS_NO_PATHCONV=1
HERE="$(cd "$(dirname "$0")" && pwd)"
ADB="${ADB:-$(cygpath -u "$LOCALAPPDATA")/Android/Sdk/platform-tools/adb.exe}"
F=/sdcard/Android/data/com.example.llama.aichat/files
LOG="$HERE/results/runs.log"
NOTIFY="$(cygpath -m "$HERE/../15.03_finetuning/00_runner/notify-telegram.ps1")"
note() { powershell -NoProfile -File "$NOTIFY" "$1" > /dev/null 2>&1; }
APK="${APK:-$HERE/apks/scout-bench-cpu-f23b516.apk}"   # app source: 15.06_OnDeviceApp/llama.cpp, branch scout-bench, commit f23b516
[ -f "$APK" ] || { echo "missing $APK"; exit 1; }

# tag|model file|prompt file|case|best-setting tag|extras (fastest CPU setting from the speed runs)
Q="--ei threads 2 --es type_k q8_0 --es type_v f16 --ei flash_attn 0"
V="--ei threads 2 --es type_k f16 --es type_v f16 --ei flash_attn 0"   # MiniCPM-V best: t2-kvf16-fa0, 144.4 / 145.5 s (t2-kq8vf16-fa0 was 157.1 / 166.0 s)
SETS="q35|Qwen3.5-0.8B-Q8_0.gguf|SYNTHETIC-ENGINEERING-ONLY_qwen35_jonathan.txt|1patient|t2-kq8vf16-fa0|$Q
g3-1b|gemma-3-1b-it-Q8_0.gguf|SYNTHETIC-ENGINEERING-ONLY_gemma3-1b_jonathan.txt|1patient|t2|--ei threads 2
mcv47|MiniCPM-V-4_7-1B-Q8_0.gguf|SYNTHETIC-ENGINEERING-ONLY_qwen35_jonathan.txt|1patient|t2-kvf16-fa0|$V
q35|Qwen3.5-0.8B-Q8_0.gguf|SYNTHETIC-ENGINEERING-ONLY_qwen35_4096.txt|4096|t2-kq8vf16-fa0|$Q
g3-1b|gemma-3-1b-it-Q8_0.gguf|SYNTHETIC-ENGINEERING-ONLY_gemma3-1b_4096.txt|4096|t2|--ei threads 2
mcv47|MiniCPM-V-4_7-1B-Q8_0.gguf|SYNTHETIC-ENGINEERING-ONLY_qwen35_4096.txt|4096|t2-kvf16-fa0|$V"

echo "$(date -Iseconds) eos quality batch starting" | tee -a "$LOG"
while IFS='|' read -r tag m p c st ex; do
  "$ADB" push "$(cygpath -m "$HERE/prompts/$p")" "$F/prompts/" < /dev/null | tail -1  # adb reads stdin: without < /dev/null it eats the loop input
  want=$(sha256sum "$HERE/prompts/$p" | awk '{print $1}')
  got=$("$ADB" shell "sha256sum $F/prompts/$p" < /dev/null | tr -d '\r' | awk '{print $1}')
  echo "$(date -Iseconds) pushed $p, sha256 laptop $want phone $got" | tee -a "$LOG"
  [ "$want" = "$got" ] || { echo "$(date -Iseconds) EOS QUALITY STOPPED: hash mismatch $p" | tee -a "$LOG"
    note "Scout: ACTION NEEDED. Prompt copy failed its hash check ($tag, $p)."; exit 1; }
done <<< "$SETS"
"$ADB" install -r "$(cygpath -m "$APK")" | tail -1
note "Scout: quality runs with the end token allowed starting (3 models, 2 prompts, 2 runs each, about 1 to 2 h)."

while IFS='|' read -r tag m p c st ex; do
  MODEL="$m" PROMPT="$p" NP=2000 RUNPREFIX="$tag-q8-cpu-$c-eos2000" bash "$HERE/run_matrix.sh" "$st" $ex --ei ignore_eos 0 < /dev/null
done <<< "$SETS"

mkdir -p "$HERE/results/quality_eos"
mv "$HERE"/results/*-eos2000-* "$HERE/results/quality_eos/"
SUM=$(grep -- "-eos2000-" "$LOG" | grep -o "[a-z0-9.-]*-eos2000[^ ]* result=[a-z]*" | sed 's/-q8-cpu//; s/-eos2000//' | tr '\n' ' ')
cd "$HERE" && git rev-parse --git-dir > /dev/null 2>&1 && git add run_quality_eos.sh run_matrix.sh results/quality_eos results/runs.log && git commit -q -m "Note-quality runs with the end token allowed (2,000 cap), 3 models, one-patient and team case (A17)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" && git log --oneline | head -1
note "Scout: end-token quality runs finished. $SUM"
echo "$(date -Iseconds) EOS QUALITY BATCH DONE" | tee -a "$LOG"
