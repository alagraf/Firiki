# Plan: Run five-document library test split once and update README results table (E19)

**Status:** implemented 14 Nov 2026
**Goal:** Re-measure the five-document `GreekLabourLibrary` `test` split (12 held-out questions) once after the 13–14 November improvements (E15 placeholder repair, E16 model errors/Stop, E17 scoped bilingual search + query normalization + `relativeScore = 0.68`, E18 summary improvements), and update the `README.md` Results table from E14–E18 and this test run with dates.

## Rules respected

- Never inspect or tune on the `test` split; run it once only as a measurement.
- Never run or inspect `rag-tests/` (EU holdout).

## Planned steps

1. Run `GreekLabourLibrary` `test` split once via:
   `mkdir -p /private/tmp/oi-e19-logs && TEST_RUNNER_OI_GREEK_EVAL=1 TEST_RUNNER_OI_GREEK_EVAL_SET=GreekLabourLibrary TEST_RUNNER_OI_GREEK_EVAL_SPLIT=test ./scripts/thesis_run_tests.sh /private/tmp/oi-e19-logs/firiki-library-test2-e19.log -only-testing:FirikiTests/GreekConstitutionEvaluationTests`
   (note: include `OI_TEST_TIMEOUT_SECONDS=5400` / `TEST_RUNNER_OI_TEST_TIMEOUT_SECONDS=5400` if needed; wait, let's check `GreekConstitutionEvaluationTests` timeout default so 12 questions finish comfortably).
2. Collect the run output with `scripts/thesis/collect_run_results.py` into a scratch folder, copy `firiki-library-test2-e19.txt` to `Docs/Thesis/experiments/runs/`, and append its row to `Docs/Thesis/experiments/runs/INDEX.md`.
3. Update `README.md` (`## Results` section lines 125–160) so the `Nov re-run` / dates reflect E14–E18 (`13–14 Nov 2026`) and the new `GreekLabourLibrary` `dev`/`test` figures (`14 of 24` / `<test>` of `12`, plus template, summary, opinion dev/test from `14 Nov 2026`).
4. Record **E19** in `Docs/Thesis/EXPERIMENTS.md`, `Docs/Thesis/METHODS_SUMMARY.md`, `Docs/Thesis/FORK_CHANGES.md`, `CHANGELOG.md`, `POC_PROGRESS.md`, commit by name, and push to `origin main`.
