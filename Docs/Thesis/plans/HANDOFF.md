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

## State (2026-10-29, 18:30)

Committed and pushed: FORK_CHANGES 2.11.17–2.11.20 (faster translation and translator memory;
batching tried and dropped; document names kept in Greek answers; OCR benchmark; gate C and file
names). Nothing in progress.

Translation models: the app ships the **one-sentence** Opus-MT export
(`scripts/thesis/convert_opus_mt.py`, via `scripts/thesis_fetch_translation_models.sh`).
`scripts/thesis/convert_opus_mt_batched.py` is the batched experiment; with its models,
`pretranslateGreekChunks` batches at import (`importBatchSize`, now 1) and the opt-in
`batchedTranslationSpeed` test runs. Don't install those models for normal work: batches reword
the INT8 translations and lowered the evaluations (FORK_CHANGES 2.11.17).

Latest numbers (Simulator, one run each; 2–8 of 46 dev cases flip between runs): Labour dev 35 of
46, Constitution 8 of 10, Labour test 16 of 23 (excerpt) and 12 of 23 (full Code); excerpt import
131–148 s, full Code 924 s. OCR word recall: PaddleOCR 0.96 clean/photo, 0.48 scan; Vision 0.05.

## Next, in order

1. **Tilted scans** (progress file): PaddleOCR loses words on scans in proportion to the page's
   tilt; its boxes are axis-aligned (`GreekPaddleOCRService.dbBoxes`). Confirm the mechanism (dump
   the boxes for a 1.5° page), then deskew or crop along each line's angle; rerun
   `GreekOCRBenchmarkTests` and the Greek unit suites.
2. The accuracy items of `greek-legaltech-progress.md` "Next (2026-10-29)": wrong-case figures
   (dev 34, 46), refusal over the full Code (2 of 3 in `labourfull3`), named-statute mismatch (test
   case 69). Tune on the dev split only; run it twice before claiming a gain of 1–3 cases.
3. Device check on an iPhone (needs the owner): import time, memory with one direction loaded,
   answer quality.
4. EU holdout: rerun only at the next milestone (evaluation only, AGENTS.md step 5).

## Log

- 2026-10-29 18:30 (Claude Code): batching settled. Batch 4/8/16 import 274/268/316 s against
  307 s, but evaluations dropped (Constitution 6 of 10 at batch 4); the batched export at batch 1
  ran 347 s, while the original models with the Accelerate argmax ran 131 s. Shipped the original
  models. Added file-name masking, "passage/excerpt" glossary, gate C file-name fix; ran the OCR
  benchmark (first attempt exited unexpectedly after page 12, the rerun passed). All recorded and
  committed.

- 2026-10-29 13:40 (Claude Code): excerpt import with batching and the Accelerate fix: 355 s (batch
  translation 300 s for 964 sentences) against 307 s before, so batches still waste work. Added:
  finished sentences leave the batch (`rows(_:of:)` copies the remaining rows), and pretranslation
  sorts over 256 chunks instead of 32. Running `/private/tmp/oi-work/batch_round2.sh` (Greek unit
  suites, then the excerpt import → `import_after3.log`). Dropping finished rows changed translations (INT8 scales are per batch) and was removed; the 256-chunk sort stays. If batching still isn't faster than 307 s,
  set `importBatchSize` to 1 or remove the pretranslation call and record why.
- 2026-10-29 13:15 (Claude Code): file created; batched translation measured in the app (2.3×),
  quality equal; import re-timing running.
