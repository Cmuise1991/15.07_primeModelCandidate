#!/usr/bin/env bash
# run_app_bench.sh: one adb-driven run of the scout-bench llama.android app on the A17 (Scout, Oct 14, 2026).
#
#   bash run_app_bench.sh <run_id> <model.gguf> <prompt_file> <n_predict> [extra am-start extras...]
#   e.g. bash run_app_bench.sh q35-cpu-r1 Qwen3.5-0.8B-Q8_0.gguf SYNTHETIC-ENGINEERING-ONLY_qwen35_4096.txt 1000
#
# <prompt_file> is a file in the phone's prompts/ folder, fed as raw text (render any chat template beforehand).
# App defaults: -c 10240 -t 4 -ngl 0, KV q8_0/q8_0, flash attention on, batch 2048, ubatch 512, mmap, temp 0,
# EOS blocked. Override with extras, e.g. --es type_k f16 --es type_v f16 --ei ngl 99.
# Before and after the run it records thermal status, AP (SoC) and battery temperature, airplane mode and free
# memory; it force-stops the app so each run is a fresh process (clean peak memory), waits for "BENCH_DONE" in
# logcat (or an lmkd kill / crash), and pulls results/<run_id>.json and .txt plus a <run_id>.state.json into ./results/.
# Failures: the exact evidence (lmkd kill line with its reason, process death, crash, engine errors, and the app's
# own error in the result JSON) goes to results/<run_id>.fail.txt; the workbook copies it into Notes.
# Raw data kept per run: <run_id>.json (app metrics), .txt (generated text), .state.json, .log (engine lines),
# .logcat.txt (full phone log for the run), .samples.csv (5 s heat, memory and CPU speed series),
# .device_before.txt / .device_after.txt (full phone snapshot: getprop, cpuinfo, all thermal sensors, battery,
# meminfo, CPU speeds and governors, app build and APK sha256, model and prompt sha256), .tokens.csv (every prompt
# chunk and generated token with its time) and .mem.csv (in-app memory every 500 ms), .fail.txt if not ok.
set -u
export MSYS_NO_PATHCONV=1   # Git Bash would otherwise rewrite /sdcard/... into a Windows path
ADB="${ADB:-$(cygpath -u "$LOCALAPPDATA")/Android/Sdk/platform-tools/adb.exe}"
PKG="${PKG:-com.example.llama.aichat}"          # LiteRT-LM app (Oct 15): PKG=com.example.gemmathepirate
ACT="${ACT:-com.example.llama.BenchActivity}"   # LiteRT-LM app: ACT=com.example.gemmathepirate.BenchActivity
FILES=/sdcard/Android/data/$PKG/files
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$(cygpath -m "$HERE/results")"; mkdir -p "$OUT"

[ $# -ge 4 ] || { sed -n 3,5p "$0"; exit 2; }
RUN="$1"; MODEL="$2"; PROMPT="$3"; NP="$4"; shift 4
EXTRAS="$*"
# A model path starting with "/" is used as is (LiteRT-LM: /data/local/tmp/llm/...); otherwise it is in models/
case "$MODEL" in /*) MPATH="$MODEL"; MARG="$MODEL" ;; *) MPATH="$FILES/models/$MODEL"; MARG="models/$MODEL" ;; esac

state() {
  "$ADB" shell 'echo "thermal=$(dumpsys thermalservice | grep -m1 "Thermal Status" | grep -o "[0-9]*$")"
    echo "ap_c=$(dumpsys thermalservice | grep -m1 "mName=AP," | grep -o "mValue=[0-9.]*" | cut -d= -f2)"
    echo "battery_c10=$(dumpsys battery 2>/dev/null | grep -m1 " temperature:" | grep -o "[0-9]*$")"
    echo "airplane=$(settings get global airplane_mode_on)"
    grep -E "^(MemAvailable|SwapFree):" /proc/meminfo | tr -s " " | sed "s/: /=/"' 2>/dev/null | tr -d '\r' | tr '\n' ' '
}

# Full phone snapshot (raw): properties, CPU, every thermal sensor, battery, memory, CPU speeds, app build.
snapshot() {
  "$ADB" shell "echo '=== date'; date; echo '=== getprop'; getprop; echo '=== cpuinfo'; cat /proc/cpuinfo;
    echo '=== cpufreq (cur/max kHz per core)'; for c in 0 1 2 3 4 5 6 7; do echo cpu\$c \$(cat /sys/devices/system/cpu/cpu\$c/cpufreq/scaling_cur_freq) \$(cat /sys/devices/system/cpu/cpu\$c/cpufreq/cpuinfo_max_freq) \$(cat /sys/devices/system/cpu/cpu\$c/cpufreq/scaling_governor); done;
    echo '=== thermalservice'; dumpsys thermalservice; echo '=== battery'; dumpsys battery; echo '=== meminfo'; cat /proc/meminfo;
    echo '=== app package'; dumpsys package $PKG | grep -E 'versionCode|versionName|lastUpdateTime|firstInstallTime';
    echo '=== app apk sha256'; sha256sum \$(pm path $PKG | sed 's/package://');
    echo '=== prompt sha256'; sha256sum $FILES/prompts/$PROMPT" 2>&1 | tr -d '\r'
  # The model hash reads the whole 800 MB file, which would warm the page cache and shorten the load time,
  # so it is taken only after the run.
  [ "${1:-}" = after ] && "$ADB" shell "echo '=== model sha256'; sha256sum $MPATH" 2>&1 | tr -d '\r'
}

"$ADB" shell am force-stop $PKG   # first, so "before" free memory is not held by the previous run
sleep 2
snapshot > "$OUT/$RUN.device_before.txt"
BEFORE="$(state)"; echo "$(date -Iseconds) $RUN before: $BEFORE" | tee -a "$OUT/runs.log"
"$ADB" logcat -c
"$ADB" shell am start -W -n $PKG/$ACT \
  --es run_id "$RUN" --es model "$MARG" --es prompt "prompts/$PROMPT" --ei n_predict "$NP" "$@" > /dev/null

# Raw time series while the run is live: every 5 s, phone heat, free memory and the app's own memory (PSS).
sample() {
  echo "time,thermal,ap_c,battery_c10,mem_available_kb,swap_free_kb,app_pss_kb,cpu0_khz,cpu6_khz,cpu7_khz" > "$OUT/$RUN.samples.csv"
  while :; do
    "$ADB" shell "echo \"\$(date +%H:%M:%S),\$(dumpsys thermalservice | grep -m1 'Thermal Status' | grep -o '[0-9]*\$'),\$(dumpsys thermalservice | grep -m1 'mName=AP,' | grep -o 'mValue=[0-9.]*' | cut -d= -f2),\$(dumpsys battery 2>/dev/null | grep -m1 ' temperature:' | grep -o '[0-9]*\$'),\$(grep MemAvailable /proc/meminfo | grep -o '[0-9]*'),\$(grep SwapFree /proc/meminfo | grep -o '[0-9]*'),\$(dumpsys meminfo --package $PKG 2>/dev/null | grep -m1 'TOTAL PSS:' | grep -o 'TOTAL PSS: *[0-9]*' | grep -o '[0-9]*\$'),\$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq),\$(cat /sys/devices/system/cpu/cpu6/cpufreq/scaling_cur_freq),\$(cat /sys/devices/system/cpu/cpu7/cpufreq/scaling_cur_freq)\"" 2>/dev/null | tr -d '\r' >> "$OUT/$RUN.samples.csv"
    sleep 5
  done
}
sample & SAMPLER=$!

KILL_RE="Kill '$PKG|Process $PKG .*has died|FATAL EXCEPTION|Fatal signal|lowmemorykiller.*$PKG|lmkd.*$PKG"
t0=$(date +%s)
result=timeout   # TIMEOUT (s) can be set from outside; default 3600 (Oct 16: raised for slow GPU runs)
while [ $(( $(date +%s) - t0 )) -lt ${TIMEOUT:-3600} ]; do
  log=$("$ADB" logcat -d 2>/dev/null | tr -d '\r')
  if echo "$log" | grep -q "BENCH_DONE $RUN"; then result=$(echo "$log" | grep -o "BENCH_DONE $RUN [a-z]*" | awk '{print $3}'); break; fi
  if echo "$log" | grep -qE "$KILL_RE"; then result=killed; break; fi
  sleep 5
done
secs=$(( $(date +%s) - t0 ))
kill $SAMPLER 2>/dev/null; wait $SAMPLER 2>/dev/null
"$ADB" pull "$FILES/results/$RUN.json" "$OUT/" > /dev/null 2>&1
"$ADB" pull "$FILES/results/$RUN.txt" "$OUT/" > /dev/null 2>&1
"$ADB" pull "$FILES/results/$RUN.tokens.csv" "$OUT/" > /dev/null 2>&1   # per-token timeline (app builds from Oct 14 ~10 PM)
"$ADB" pull "$FILES/results/$RUN.mem.csv" "$OUT/" > /dev/null 2>&1      # in-app memory every 500 ms
"$ADB" pull "$FILES/results/$RUN.rendered.txt" "$OUT/" > /dev/null 2>&1 # LiteRT-LM: the prompt as the engine rendered it
snapshot after > "$OUT/$RUN.device_after.txt"
full=$("$ADB" logcat -d 2>/dev/null | tr -d '\r')
echo "$full" > "$OUT/$RUN.logcat.txt"   # the whole phone log for the run, unfiltered
# engine log lines for this run: devices, layers offloaded, KV buffer sizes, flash attention as applied
echo "$full" | grep -E "offload|Vulkan|ggml_vulkan|load_tensors|KV buffer|kv_cache|flash_attn|n_ctx|CPU_REPACK|model buffer|compute buffer|BENCH_|lmkd|lowmemorykiller|ScoutBench|litert|LiteRt|tflite|xnnpack|XNNPack" > "$OUT/$RUN.log"
AFTER="$(state)"
if [ "$result" != ok ]; then
  {
    echo "run $RUN: runner result $result after ${secs} s"
    echo "before: $BEFORE"
    echo "after:  $AFTER"
    echo "--- kill / death / crash lines (logcat) ---"
    echo "$full" | grep -E "$KILL_RE|lowmemorykiller|lmkd" | tail -10
    echo "--- engine error lines (logcat) ---"
    echo "$full" | grep -iE "ai-chat.*(error|failed|fail |abort|assert|out of memory|vk::|ErrorOutOf|cannot)|GGML_ASSERT|ggml_vulkan.*(error|fail)" | tail -15
    echo "--- last ScoutBench / ai-chat lines ---"
    echo "$full" | grep -E "ScoutBench|ai-chat|litert|LiteRt" | tail -12
    [ -f "$OUT/$RUN.json" ] && { echo "--- app result JSON (status, stage, error) ---"; grep -o '"status":"[a-z]*"\|"fail_stage":"[^"]*"\|"error":"[^"]*"' "$OUT/$RUN.json"; }
  } > "$OUT/$RUN.fail.txt"
fi
echo "$(date -Iseconds) $RUN result=$result wall_s=$secs after: $AFTER" | tee -a "$OUT/runs.log"
printf '{"run_id":"%s","runner_result":"%s","wall_s":%s,"model":"%s","prompt":"%s","n_predict":%s,"extras":"%s","before":"%s","after":"%s"}\n' \
  "$RUN" "$result" "$secs" "$MODEL" "$PROMPT" "$NP" "$EXTRAS" "$BEFORE" "$AFTER" > "$OUT/$RUN.state.json"
