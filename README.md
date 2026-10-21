# 15.07 Prime Model Candidate

Part of a Mitacs research project: a small language model that runs on a cheap Android phone and writes a clinic note (SOAP: Subjective, Objective, Assessment, Plan) from a doctor-patient conversation. All test data is synthetic. No real patient data is used anywhere in this folder.

This folder is a new set of benchmarks on three models. The goal is to see which one is the best candidate to fine-tune later. **There is no fine-tuning in this folder, and no model has been picked yet.**

Status (Oct 21, 2026): set up, not yet run.

## Why this test set

The earlier on-device tests (folder `15.06_OnDeviceApp`) forced every model to write exactly 1,000 tokens. They blocked the model's end token (the token a model emits to say "I am done"). That made speed comparisons fair, because every model did the same amount of work. But it hid three things that matter in a real app:

1. **Looping.** In the 15.06 notes, some models repeated the same lines until they hit 1,000 tokens. With the end token blocked, we cannot tell a real loop from a model that had finished and was forced to keep going. Here the model is allowed to stop, so any loop that remains is the model's own.
2. **True speed of the GGUF.** A real app stops when the note is done. The time to a finished note, on the real phone with the real model file, is the number a clinic would actually wait. It is closer to production than a fixed 1,000-token time.
3. **Stopping behaviour.** Does each model know when the note is finished? A model that never stops is a problem whatever its speed.

These runs are **quality and behaviour rows, not speed-comparison rows**. Each model writes a different number of tokens. The fixed 1,000-token speed comparison stays in 15.06.

## The three models

Picked by Chad on Oct 21, 2026. All Q8_0 (8-bit weights). That rule comes from the team On-Device Plan and Chad's Oct 14 decision for the native app.

| # | Model | File | Source | Licence | Setting (fastest in 15.06) | 15.06 team case, 1,000 tokens |
|---|---|---|---|---|---|---|
| 02 | Gemma 3 1B IT | `gemma-3-1b-it-Q8_0.gguf` | ggml-org/gemma-3-1b-it-GGUF | Gemma Terms of Use | 2 threads, KV q8_0/q8_0, flash attention on | 145.6 s |
| 03 | Qwen3.5-0.8B | `Qwen3.5-0.8B-Q8_0.gguf` | unsloth (Qwen3.5-0.8B GGUF) | Apache 2.0 | 2 threads, KV q8_0/f16, flash attention off | 134.5 s |
| 04 | MiniCPM-V 4.7 1B | `MiniCPM-V-4_7-1B-Q8_0.gguf` | openbmb/MiniCPM-V-4.7-1B-gguf (text model only) | Apache 2.0 | 2 threads, KV f16/f16, flash attention off | 144.4 s |

KV cache: the model's working memory of the conversation. q8_0 and f16 are how precisely it is stored. Two threads means the phone's two fast cores.

## Test device

Samsung Galaxy A17 5G (SM-A176W), Android 16, Exynos 1330 (2 fast + 6 slow cores), 4 GB RAM, Mali-G68 GPU (not used: CPU only). It is the slowest phone the team has, on purpose: if a model works here, it works on most phones. The target is a finished note in 60 s. No model met it in 15.06.

## What each run does

| Setting | Value |
|---|---|
| Engine | llama.cpp a0e6dc7, inside llama.cpp's own Android example app with our test mode added (`scout-bench`, app build f23b516) |
| Compute | CPU only (`-ngl 0`) |
| Context | 10,240 tokens |
| Tokens out | Up to 2,000. **End token allowed** (`--ei ignore_eos 0`): the model stops when it chooses. The cap only ends a runaway loop. |
| Decoding | Greedy (temperature 0): always the most likely next token, so a rerun writes the same text |
| Prompt | Pre-rendered with each model's own chat template, thinking off, fed as raw text |
| Batch / ubatch | 2048 / 512, model memory-mapped from storage |
| Per run | A fresh app process (the model loads every time). Two runs per case, back to back, after a cool-down to thermal status 0 and SoC at or below 40 C (15 min at most). Phone in airplane mode. |

Two test cases per model:

- **1-patient:** one complete visit (Jonathan with Dr. Vance). Real visits never mix two patients, so this is the fair note-quality test. About 3,400 tokens in.
- **team:** the team's standard test file, with two visits (Jonathan complete, Elena cut off mid-sentence). About 4,200 to 4,300 tokens in. It is kept for continuity with every earlier result.

## What to expect

- **Time:** 6 pairs (3 models x 2 cases), 12 runs. Each run took about 110 to 155 s at 1,000 tokens in 15.06. A model that stops early will be faster; one that runs to the 2,000 cap could take about twice as long. With cool-downs the whole batch takes about 1 to 2 hours. The laptop must stay awake and the phone plugged in. No internet is needed.
- **Text before the stop is not new.** With greedy decoding, everything a model writes before it stops matches the 15.06 runs at the same setting. The new information is where it stops, whether it loops, and how long a finished note takes. (MiniCPM-V's one-patient run in 15.06 used KV q8_0/f16; here it uses its faster f16/f16 setting, so its text may differ.)
- **Known loops from 15.06** (end token blocked), which this set checks: Qwen3.5 repeated a history line in Objective and never reached Assessment or Plan; MiniCPM-V repeated the closing dialogue; Gemma ended the team-case note with repeated "Do you want me to add..." questions.
- **No model is expected to meet 60 s.** The best was 2.2x the target in 15.06.

## Folder structure

```
15.07_primeModelCandidate/
  README.md                    this file
  SHA256SUMS.txt               hashes of every model, the APK and the prompt files
  .gitignore                   keeps the large files (models, APK) and run output out of git
  run_quality_eos.sh           the batch: 3 models x 2 cases x 2 runs, end token allowed
  run_matrix.sh                one pair of runs (cool-down, then run 1 and run 2)
  run_app_bench.sh             one run: starts the app over adb, records heat and memory, pulls the results
  scaffold_results.py          created the empty results workbooks below (run once)
  apks/
    scout-bench-cpu-f23b516.apk  the test app (CPU build)
  models/                      the three Q8_0 GGUF files (not in git: 0.8 to 1.1 GB each)
  prompts/                     the four prompt files (not in the public repository, see below)
  results/                     raw output of every run (filled by the scripts; not in the public repository)
    quality_eos/               this set's runs, moved here when the batch ends
    runs.log                   one line per run: before and after heat, memory, result
  00_primeCandidateResults/    the workbooks (see its README.txt)
    00_PrimeCandidateSummary.xlsx      start here: verdict, one row per model, every run
    charts/                            charts, once there are runs
    00_processingResults/              results in the team's benchmark template
      01_OnePatientRuns_Benchmarks.xlsx
      02_Gemma3-1B_Benchmarks.xlsx, 03_Qwen3.5_..., 04_MiniCPM-V4.7_...
    01_rawResults/                     every measurement and the full text each model wrote
      00_PrimeCandidateResults.xlsx    every run, every column, plus a Columns sheet defining each one
      01_OnePatientRuns_Quality.xlsx   full note text per run
      02_Gemma3-1B_Results.xlsx, 03_Qwen3.5_..., 04_MiniCPM-V4.7_...
```

Files kept for every run in `results/` (named by run ID):

| File | What it holds |
|---|---|
| `<run>.json` | Every setting and measurement: load time, time to first token, prompt and writing speed, total time, peak memory, tokens written, `stop_reason` |
| `<run>.txt` | The note the model wrote |
| `<run>.tokens.csv` | Every generated token with its time, plus an `eos` row if the model stopped itself |
| `<run>.mem.csv`, `.samples.csv` | Memory every 0.5 s inside the app; heat, free memory and CPU speed every 5 s |
| `<run>.state.json`, `.device_before.txt`, `.device_after.txt` | Phone heat, memory and full snapshot before and after |
| `<run>.log`, `.logcat.txt` | Engine log lines and the full phone log for the run |
| `<run>.fail.txt` | Only if a run did not finish: the exact reason (for example Android's low-memory kill line) |

`stop_reason` is `eos` (the model stopped by itself), `n_predict` (it hit the 2,000 cap) or `error`.

Run IDs: `<model>-q8-cpu-<case>-eos2000-<setting>-r<1|2>`, for example `q35-q8-cpu-1patient-eos2000-t2-kq8vf16-fa0-r1`. Model tags: `g3-1b` Gemma 3 1B, `q35` Qwen3.5, `mcv47` MiniCPM-V 4.7.

## How to run

### What you need

- Windows laptop with Git Bash, Python 3 with `openpyxl`, and the Android SDK platform tools (`adb`). The scripts look for `adb` in the default Android SDK place, `%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe`; set `ADB=` to change it.
- Samsung Galaxy A17 with Developer options and USB debugging on, connected by USB. Check with `adb devices`; the phone must show as `device`, not `unauthorized`.

### 1. Install the app

```bash
adb install -r apks/scout-bench-cpu-f23b516.apk
```

Open the app once on the phone ("AI Chat basic sample") so Android creates its files folder.

### 2. Copy the models to the phone (once)

```bash
export MSYS_NO_PATHCONV=1   # stops Git Bash rewriting /sdcard/... into a Windows path
F=/sdcard/Android/data/com.example.llama.aichat/files
adb shell mkdir -p $F/models $F/prompts   # not results/: the app makes that itself (a folder made by adb belongs to the shell user, and the app may be refused write access)
for m in models/*.gguf; do adb push "$m" $F/models/; done
adb shell "sha256sum $F/models/*.gguf"   # compare with SHA256SUMS.txt
```

Do not copy files while a run is going; it slows the run. The batch script pushes the prompt files itself and checks their hashes.

### 3. Prepare the phone

Airplane mode on, plugged in, screen unlocked, nothing else open. Let it cool if it is warm. The scripts wait for a cool-down before each pair.

### 4. Run the batch

```bash
bash run_quality_eos.sh
```

It installs the APK, pushes and checks the prompts, then runs the 6 pairs. When it finishes it moves the output to `results/quality_eos/` and prints one line per run. Progress goes to `results/runs.log`. If `../15.03_finetuning/00_runner/notify-telegram.ps1` exists, it also sends a Telegram message at the start and end; without it the batch still runs.

### One run by hand

```bash
bash run_app_bench.sh test-q35-r1 Qwen3.5-0.8B-Q8_0.gguf SYNTHETIC-ENGINEERING-ONLY_qwen35_jonathan.txt 2000 \
  --ei threads 2 --es type_k q8_0 --es type_v f16 --ei flash_attn 0 --ei ignore_eos 0
```

Leave out `--ei ignore_eos 0` to get the old behaviour (exactly the requested number of tokens, end token blocked).

### Stopping

`Ctrl+C` stops the script. Then stop the app with `adb shell am force-stop com.example.llama.aichat`.

## Prompt files (not in the public repository)

The four prompt files hold the team's synthetic test conversations and its scribe instructions, so they are kept out of the public repository. Their SHA-256 hashes are in `SHA256SUMS.txt`, so any copy can be checked byte for byte. Each file is the scribe instructions plus the conversation, wrapped in the model's own chat template with thinking turned off.

| File | Used by | Case |
|---|---|---|
| `SYNTHETIC-ENGINEERING-ONLY_qwen35_jonathan.txt` | Qwen3.5 and MiniCPM-V 4.7 (same chat template, byte for byte) | 1-patient |
| `SYNTHETIC-ENGINEERING-ONLY_gemma3-1b_jonathan.txt` | Gemma 3 1B | 1-patient |
| `SYNTHETIC-ENGINEERING-ONLY_qwen35_4096.txt` | Qwen3.5 and MiniCPM-V 4.7 | team |
| `SYNTHETIC-ENGINEERING-ONLY_gemma3-1b_4096.txt` | Gemma 3 1B | team |

## Where the app comes from

The APK is built from llama.cpp's own Android example (`examples/llama.android`, MIT licence) on a local branch `scout-bench` (llama.cpp commit a0e6dc7 plus our test mode, app commit f23b516). The source sits in `15.06_OnDeviceApp/llama.cpp/` and is not published. Our changes add an adb-driven `BenchActivity` and a native `bench.cpp`: one timed run per launch, every setting taken from the command line, every measurement written to a JSON file. f23b516 adds the end-token switch. Its engine code is the same as the build behind the 15.06 speed results (a0e6dc7 app a8cb023); only the debug symbols were dropped.

## Limits to keep in mind

- One phone, two conversations, two runs per case.
- Note quality is fact-checked by the project team, not by a clinician.
- Times are wall-clock on a phone that heats up; run-to-run differences of 5 to 10% are normal.
- The workbooks in `00_primeCandidateResults/` are empty until the 15.06 workbook builders are adapted to this folder.
