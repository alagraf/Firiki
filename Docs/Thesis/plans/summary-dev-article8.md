# Plan: Restore Article 3 citation and Article 8 full after-effect in statute summaries (E18)

**Status:** implemented 14 Nov 2026
**Symptom:** Since E15 (`firiki-summary-dev3`, `docs/dev`), the Law 5278/2026 summary (`Benchmarks/GreekLabourLibrary/summary_v1.jsonl`, `dev` split) cites `2 of 3` expected articles (`Article 3` missing) and `5 of 6` provisions (missing `Article 8`'s rule that all normative terms continue after the three-month period).

## Root causes found on `dev` (`n_5278_2026_fek_a22.pdf`)

Inspecting the stored `n_5278_2026_fek_a22.pdf` chunks and dev summary log showed three defects in `Firiki/Services/Legal/GreekLegalDocumentSummarizer.swift`:
1. **TOC chunk accepted before `Article 1`:** Chunk 4 (`Article 5 [Άρθρο 5] Restriction of registration details...`) in the Table of Contents has >= 12 words and a single `Article` mention, so `articles(from:)` added `Article 5` ahead of `Article 1`. Group 1 started with `=== Article 5 ===` followed by Articles `1, 2, 3`, causing notes from Group 1 (including Article 3's GSEE rule) to fall under `Article 5` and omitting `Article 3` (`2 of 3` cited).
2. **Real article chunks skipped due to cross-reference counting:** `headings = passage.components(separatedBy: "Article ").count - 1` counted inline cross-references (`Article 404`, `Article 399`, `Article 396`), skipping 19 valid body chunks across Articles 4, 5, 6, 9 (5 chunks, including the Article 404 amendment opening), 10, 11, 12, and all of Article 15.
3. **Too many articles packed into one map group:** After E15's placeholder removal shortened passages slightly, `groups(of:)` merged `Article 6`, `Article 7`, and `Article 8` into one 3-article group (`groups = 12` instead of `13`), leaving `Article 8` with a single note line that dropped its second rule (all normative terms continuing until replaced).

## Planned changes

1. `Firiki/Services/Legal/GreekLegalDocumentSummarizer.swift`:
   - In `articles(from:)`: count **line-starting** `Article` headings when filtering table-of-contents blocks so inline cross-references do not skip real article chunks, and drop any leading entries before `Article 1` when `Article 1` appears later in the document.
   - In `groups(of:limit:maxArticles:)`: cap each map group at `maxArticles = 2` articles (within `limit`) so short/medium articles at the end of a long group (such as `Article 8` after `Article 6` and `Article 7`, or `Article 3`) receive their own note budget.
   - In `mapInstructions(lines:parts:)`: ask the model to cover each non-purpose article given and state each separate rule or time stage (including scope such as all terms vs partial) on its own line.
2. `FirikiTests/Services/GreekLegal/GreekLegalSummaryTests.swift`:
   - Add unit tests verifying that leading TOC entries before `Article 1` are dropped, article chunks with inline cross-references are kept, and `groups(of:)` caps articles per group cleanly.
3. Verify on `GreekLegalSummaryTests`, `GreekLegalSummaryEvaluation` (`split=dev`), and (to confirm zero regression on opinions) `GreekLegalOpinionTests`.
4. Collect dev run into `Docs/Thesis/experiments/runs/`, record **E18** in `Docs/Thesis/EXPERIMENTS.md`, `Docs/Thesis/METHODS_SUMMARY.md`, `Docs/Thesis/FORK_CHANGES.md`, `CHANGELOG.md`, `POC_PROGRESS.md`, commit by name, and push to `origin main`.
