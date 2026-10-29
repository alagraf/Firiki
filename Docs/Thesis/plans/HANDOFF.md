# Handoff: where the work stands

For any agent (Claude Code, Antigravity) continuing the thesis work without the earlier
conversation. Kept current by the agent doing the work; the last update is at the top of the log.
Read `AGENTS.md` first; its rules apply in full (the owner has given standing permission to make
changes and to commit and push the thesis branch to `origin`, https://github.com/alagraf/Firiki).

## Rules that are easy to break

- **EU holdout** (`/Users/alagra/Documents/thesis/rag-tests/`): evaluation only (AGENTS.md step 5).
  Never read its questions or answers to diagnose, never change the app because of it, never copy it
  into the repository. A problem first seen there is fixed generally and verified on the Labour Code
  dev split and unit tests.
- **Never stage** `OpenIntelligence.xcodeproj/project.pbxproj`, `OpenIntelligence/OpenIntelligence.entitlements`
  or `greek_legaltech_implementation_plan.md` (the owner's local changes). Never `git add .`.
- **One Simulator user at a time.** `scripts/thesis_run_tests.sh` shuts down every simulator before
  each run, so a second agent's run kills the first. Check that no run is going first:
  `pgrep -lf thesis_run_tests | grep "^[0-9]* /bin/bash\|^[0-9]* bash"` must print nothing.
- Run tests with `scripts/thesis_run_tests.sh <log> -only-testing:...` (env `OI_TEST_TIMEOUT_SECONDS`,
  `TEST_RUNNER_*`). It doesn't retry "Simulator device failed to launch": run it again once. A Swift
  Testing method needs its parentheses: `-only-testing:OpenIntelligenceTests/Suite/test()`.
- Record every change in `Docs/Thesis/FORK_CHANGES.md`, the 5.7 section of `CHANGELOG.md`, and
  results in `Docs/Thesis/METHODS_SUMMARY.md`; show the test output that proves a claim.

## State (2026-10-29, 13:15)

Committed and pushed: everything up to `7ef19654` (EU holdout final, hand-graded; see FORK_CHANGES
2.11.15–2.11.16).

**Uncommitted, in progress: batched translation and translator memory** (to become FORK_CHANGES
2.11.17):
- `LocalNeuralTranslator.swift`: batches of up to 16 sentences at import (`pretranslateGreekChunks`),
  4 threads, next-token pick with Accelerate (`vDSP_maxvi`), one direction loaded at a time,
  `releaseModels()` after an import and on a memory warning, batch timing logged.
- `GreekLegalIngestion.swift`: pretranslates every 32 Greek chunks, releases the models at the end.
- `RAGService.swift`: memory-warning observer also releases the translator.
- `scripts/thesis/convert_opus_mt.py`: exports the models with a batch axis and
  `encoder_attention_mask`. The batched models are installed in
  `OpenIntelligence/Resources/MLModels/Translation/` (git-ignored); copies: batched
  `/private/tmp/oi-work/models-batched/`, the previous one-sentence models `/private/tmp/oi-work/models-batch1/`.
  `scripts/thesis_fetch_translation_models.sh` rebuilds the batched ones.
- Tests in `GreekLegalPipelineTests.swift`: `importTranslatesInBatchesAndReleasesTheModels`,
  `importPretranslatesEveryWindowAndFinishesOnce`, opt-in `batchedTranslationSpeed`
  (`TEST_RUNNER_OI_TRANSLATE_BENCH=1`).

Measured so far:
- Greek unit suites: `✔ Test run with 67 tests in 15 suites passed` (before the Accelerate change).
- Python (M3, 64 Labour Code sentences): batch 16 at 4 threads 3.7× faster; 4 threads alone no gain.
- In the app, back to back (`translatebench2.log`): 117 chunks, one sentence at a time 21.3 s,
  batched 9.3 s (2.3×); ONNX Runtime 8.1 of 8.9 s.
- Translation quality vs the uncompressed fp32 model (160 sentences): one at a time chrF 96.6,
  batched chrF 95.9 (identical sentences 103 vs 102).
- Excerpt import: 307 s with the old models; 579 s with batching BEFORE the Accelerate change (the
  per-token Swift loop is slow in Debug test builds); being re-timed (`/private/tmp/oi-logs/import_after2.log`).
- Labour dev split with batching (`labour8.log`): 35/46 (run 7 before: 37/46); 8 cases flipped both
  ways (3 new passes, 5 new fails: 1, 8, 19, 40, 68), retrieval unchanged 39/41. Looks like
  wording-driven variation, not worse translation (see quality above), but it is one run.

## Next, in order

1. Read the import re-timing; then run the Greek unit suites again (list in
   `/private/tmp/oi-work/greek_suites.txt`, or every suite in `GreekLegalPipelineTests.swift` and
   `GreekProcessingLogTests.swift`) and the Constitution set (`TEST_RUNNER_OI_GREEK_EVAL=1`, default
   set). Record 2.11.17 and commit the batched translation (by file name), push.
2. Run the OCR benchmark Antigravity prepared: `Docs/Thesis/plans/ocr-test-set-results.md` says how
   (`TEST_RUNNER_OI_OCR_BENCH=1`, suite `GreekOCRBenchmarkTests`). Fill in its results, merge its
   draft doc text, commit its files (`Benchmarks/GreekOCR/`, `scripts/thesis/make_ocr_testset.py`,
   the test file, the results file).
3. Full Labour Code: import time with batching (was 1757 s) and the test split (23) on excerpt and
   full corpus (`TEST_RUNNER_OI_GREEK_EVAL_SPLIT=test`, `_CORPUS=full`).
4. The "Next (2026-10-29)" items of `greek-legaltech-progress.md`: document names translated as
   words (mask file names before English→Greek), wrong-case figures (dev 34, 46), refusal over the
   full Code, the named-statute mismatch (test case 69). Tune on the dev split only.
5. Device check on an iPhone (needs the owner).

## Log

- 2026-10-29 13:15 (Claude Code): file created; batched translation measured in the app (2.3×),
  quality equal; import re-timing running.
