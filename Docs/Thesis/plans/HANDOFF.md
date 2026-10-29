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

## State (2026-10-29, 21:30)

Committed and pushed: FORK_CHANGES 2.11.17–2.11.22 (faster translation and translator memory;
batching tried and dropped; document names kept in Greek answers; OCR benchmark; gate C and file
names; README by Antigravity as 2.11.21; OCR boxes that follow tilted lines as 2.11.22).

Translation models: the app ships the **one-sentence** Opus-MT export
(`scripts/thesis/convert_opus_mt.py`, via `scripts/thesis_fetch_translation_models.sh`).
`scripts/thesis/convert_opus_mt_batched.py` is the batched experiment; don't install its models for
normal work: batches reword the INT8 translations and lowered the evaluations (2.11.17).

Latest numbers (Simulator, one run each; 2–8 of 46 dev cases flip between runs): Labour dev 35 of
46, Constitution 8 of 10, Labour test 16 of 23 (excerpt) and 12 of 23 (full Code); excerpt import
131–148 s, full Code 924 s. OCR word recall (PaddleOCR): clean, photo and scan 0.96; Vision 0.05.

## Next, in order

**The step-by-step plan for everything left is `poc-remaining-work.md`** (in this folder): how to run
the tests, what is uncommitted and how to finish it, and a design and test for each remaining item.
Start there.

The owner's list is `greek-legaltech-progress.md`: the open items under "Next (2026-10-29)", then
the section "PoC capabilities (owner, 2026-10-29)", one capability at a time (implement, test,
commit, then the next).

1. Accuracy items: wrong-case figures (dev 34, 46; done, 2.11.23–24), a question naming another law whose article
   number exists in the library (test case 69), refusal rate over the full Code. Tune on the dev
   split only; run it twice before claiming a gain of 1–3 cases.
2. PoC capabilities in the owner's priority: five-document Q&A, then template routing, then summary
   and legal opinion. The five
   documents are Greek **labour** laws only: the Labour Code plus four labour statutes not already
   codified in it, each downloaded only after the owner approves it (name, source, size). The 10
   contract templates are drafted by Claude Code from the Labour Code, marked as PoC drafts.
3. Device check on an iPhone (needs the owner): import time, memory with one direction loaded,
   answer quality, the refusal thresholds.
4. EU holdout: rerun only at the end (evaluation only, AGENTS.md step 5).

Removed by the owner (don't add back unless asked): Greek translation for PDFs over 10 MB (the
streamed import has none); measuring OCR on real phone photos and scans.

## Log

- 2026-10-30 00:30 (Claude Code): committed 2.11.25 (per-document statute key, named-statute
  refusal; Constitution 8/10, Labour dev 38/46). Owner (00:20): don't fix the remaining dev
  failures (cases 41, 68: diagnosed in the chat, patch at /private/tmp/oi-work/patch_split_refusal.py,
  not applied); priority is the template router, then the five-document Q&A, then summary and
  opinion. Router evaluation running (`routing1`).

- 2026-10-29 23:30 (Claude Code): committed 2.11.23 (table rows) and 2.11.24 (gate C off-topic
  figures); dev 36 and 35 of 46. Committed the data for the five-document Q&A and the template
  routing (`0514b17c`); the five-document harness change is written (compiles), not yet run.
  Next: named-law refusal (test case 69), then the full-Code refusal run, then capability 1.

- 2026-10-29 21:40 (Claude Code): fixes for dev cases 34 (table rows) and 46 (off-topic figure
  refused by gate C) written, **uncommitted**. The dev split is running as `labour13` (table fix) and
  `labour14` (both fixes). Wrote `poc-remaining-work.md` for whoever continues.

- 2026-10-29 21:30 (Claude Code): tilted scans fixed (2.11.22): boxes follow each line's angle;
  scans 0.48 → 0.96 word recall, 13 other pages 0.46 → 0.88 (`scripts/thesis/ocr_tilt_check.py`).
  The owner added the PoC capabilities to the progress file and removed two items.

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
