PRIME MODEL CANDIDATE RESULTS (Samsung Galaxy A17)
Benchmarks to show which of 3 models is the best candidate for fine-tuning later. No fine-tuning here.
Models (Chad, Oct 21, 2026): 02 Gemma3-1B, 03 Qwen3.5, 04 MiniCPM-V4.7. All Q8_0 on llama.cpp, CPU.
Set up Oct 21, 2026 in the same layout as 15.06_OnDeviceApp\00_ondeviceResults. No runs yet.

FOLDER LAYOUT
  00_PrimeCandidateSummary.xlsx      START HERE. Verdict, one row per model, each model's block, every run.
  charts\                            Charts of the same results (added once there are runs).
  00_processingResults\              Results in the team's benchmark template.
  01_rawResults\                     Every measurement, plus the full text each model wrote.

00_processingResults\
  01_OnePatientRuns_Benchmarks.xlsx  One-patient note test, in the template.
  02 to 04 _<Model>_Benchmarks.xlsx  One file per model (team case). Each setting averaged over its two runs,
                                     plus a "- runs" sheet with each run.

01_rawResults\
  00_PrimeCandidateResults.xlsx      Every run, every column. One sheet per model + case.
  01_OnePatientRuns_Quality.xlsx     One-patient note test. Full note text per run.
  02 to 04 _<Model>_Results.xlsx     One file per model: its rows from 00 plus the full generated text.

WHAT THE SHEET NAMES MEAN
  1-patient EOS   Jonathan's visit alone. The model may stop at its own end token (cap 2,000 tokens).
  team EOS        The team two-visit case, same end-token rule.
  End token / Stop reason columns are new in this set: did the model stop by itself, or hit the cap?
  These are NOT speed rows (each model writes a different number of tokens).
  Times are seconds, load time excluded. Target is 60 s.

Per-run raw files (output text, logs): ..\results\
