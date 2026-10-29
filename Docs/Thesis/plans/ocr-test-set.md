# Plan: Greek OCR test set from scanned and photographed pages

Written by Claude Code on 2026-10-29 for Antigravity to execute. Owner's approval: "OCR test set
only" (2026-10-29). `AGENTS.md` applies in full; this plan only says what to do inside it.

## Goal

Measure how well the app reads Greek legal text from **scans and photos** (so far OCR was only
tested on rendered, clean images), with numbers that can go in the thesis: per-engine error rates on
the same pages as a clean render, a "scanned" version and a "photographed" version.

Why: the app's developer pointed out that a ΦΕΚ PDF with a text layer reads most pages from that
layer, so it tests translation and search, not OCR. OCR runs on scanned PDFs (including Scan a
Document, which saves its pages as an image-only PDF), on photos of pages, and on low-text pages and
stamps inside PDFs (through `ImageUnderstandingService`).

## Rules for this task (in addition to AGENTS.md)

- **Another agent (Claude Code) is working in the same checkout at the same time** on the
  translator (`LocalNeuralTranslator.swift`, `GreekLegalIngestion.swift`, `RAGService.swift`) and on
  the shared docs. Touch only the files listed under "Files you may create or change".
- **No app code changes.** Nothing under `OpenIntelligence/` changes. If the measurements show an
  OCR bug, describe it (file, function, the evidence) in the results file; don't fix it.
- **Don't run the iOS Simulator or `xcodebuild test` until the owner tells you the Simulator is
  free.** Claude Code is timing imports and running evaluations; a second test run would slow
  both and spoil the timings. Generating the images (step 2) needs no Simulator and can run any
  time. When you are told it's free, run only the new suite, with a derived-data folder of your own:
  `-derivedDataPath /private/tmp/oi-build-ocr`.
- **Never touch** `/Users/alagra/Documents/thesis/rag-tests/` (a holdout set, AGENTS.md step 5),
  `OpenIntelligence.xcodeproj/project.pbxproj`, any `*.entitlements` or `Info.plist`. New test
  files are picked up automatically (the project uses synchronized folders), so the project file
  doesn't need to change.
- Don't commit. Leave the files for Claude Code to review, record and commit.

## Files you may create or change

| File | What |
|---|---|
| `scripts/thesis/make_ocr_testset.py` (new) | Generator of the page images and their reference text |
| `Benchmarks/GreekOCR/` (new folder) | `README.md`, `manifest.json`, the generated images, `photos/` for the owner's own photos |
| `OpenIntelligenceTests/Services/GreekLegal/GreekOCRBenchmarkTests.swift` (new) | Opt-in measurement suite |
| `Docs/Thesis/plans/ocr-test-set-results.md` (new) | Your results and the text to add to the thesis docs |

## Steps

### 1. Read first (only these)

- `OpenIntelligenceTests/Services/GreekLegal/GreekLegalPipelineTests.swift`, lines 180–306: the
  helpers `wordErrorRate` and `renderPage` and the suite `GreekOCRTests`, which show how the
  engines are called (`GreekPaddleOCRService.shared.recognizeLines`, `OCRRouterService`,
  `ImageUnderstandingService.shared.extractTextFromImage`, `GreekLegalEntityMasker.repairGreekHomoglyphs`,
  `GreekLegalEntityMasker.canonicalKeys`).
- `OpenIntelligence/Services/Document/OCR/OCRRouterService.swift` (whole file, about 200 lines).
- `OpenIntelligenceTests/Services/GreekLegal/GreekConstitutionEvaluationTests.swift`, lines 60–130,
  for the opt-in pattern (`.enabled(if: ProcessInfo.processInfo.environment[...] == "1")`) and how a
  test finds `Benchmarks/` from `#filePath`.
- Find the scanned-page path with `python3 .claude/codemap/codemap.py find parsePageImage` and read
  only `parsePageImage` in `StructuredDocumentParser.swift` (by line range).

### 2. Generate the pages (no Simulator)

`scripts/thesis/make_ocr_testset.py`, run in a temporary virtual environment (as
`scripts/thesis_fetch_translation_models.sh` does; `pip install pymupdf pillow numpy`):

- Source: `Benchmarks/GreekLabourCode/pd_62_2025_excerpt.pdf` (37 pages, ΦΕΚ Α' 121/2025, two
  columns, real text layer). Pick 10 pages spread over the excerpt (fixed list in the script, not
  random), skipping near-empty pages.
- Reference text per page: the PDF's text layer (PyMuPDF `get_text("text")`), with hyphenated line
  ends joined and Unicode normalized (NFKC). Also keep the reference per column if the two columns
  can be separated (`get_text("blocks")` sorted by x then y), since OCR may read across columns.
- Three versions of each page, saved as JPEG (quality noted in the manifest):
  - **clean**: rendered at 300 dpi, no degradation (control);
  - **scan**: 200 dpi, grayscale, rotated by a fixed small angle (between −1.5° and +1.5°, fixed per
    page), mild Gaussian noise, slight contrast loss, JPEG quality 60;
  - **photo**: 300 dpi, perspective warp (as from a phone held at a slight angle), an uneven light
    gradient across the page, a light blur, JPEG quality 80.
  Use a fixed random seed so the set is reproducible.
- Also write an **image-only PDF** of the 10 "scan" pages (`scan_pages.pdf`), like Scan a Document
  produces, for the whole-import measurement in step 4.
- `manifest.json`: one entry per image (page number, version, file, reference text file, rotation,
  JPEG quality, dpi).
- Keep `Benchmarks/GreekOCR/` under about 15 MB; if it would be larger, lower the JPEG quality of the
  clean versions only and say so.
- `Benchmarks/GreekOCR/photos/README.md`: how the owner adds real phone photos (file name
  `p<page>_<n>.jpg`, the page number of the excerpt), so they are measured the same way.

### 3. The measurement suite

`GreekOCRBenchmarkTests.swift`, opt-in with `TEST_RUNNER_OI_OCR_BENCH=1`, one `@Test` that reads
the manifest and, for every image (and every photo in `photos/` that has a page number):

- runs three readers: **Vision only** (`OCRRouterService` in `.vision` mode, or Vision's text
  directly, whichever the existing code makes possible without app changes), **PaddleOCR only**
  (`GreekPaddleOCRService.shared.recognizeLines` + `OCRRouterService.joinLines` +
  `repairGreekHomoglyphs`), and **the app's own path** (`ImageUnderstandingService.shared.extractTextFromImage`);
- computes, against the reference:
  - **CER** (character error rate, edit distance over the normalized text without whitespace);
  - **WER** (the existing `wordErrorRate`);
  - **word recall and precision as bags of words** (order-free, so reading the two columns in a
    different order isn't counted as errors);
  - **legal identifier recall**: the share of the reference's `GreekLegalEntityMasker.canonicalKeys`
    (articles, laws, ΦΕΚ) found in the OCR text;
  - **number recall**: the share of the reference's numbers found;
  - seconds per page;
- prints one line per image (`[OCRBench] page 12 scan paddle CER 0.034 WER … idRecall …`) and a
  summary table per version and reader (means), as `[OCRBench] SUMMARY …` lines.

Keep the test from failing on low accuracy: it measures. It should fail only when the manifest or
an engine is missing.

### 4. Whole-import check (only after the owner says the Simulator is free)

Import `scan_pages.pdf` through the app's normal import (the same calls the evaluation harness uses
to ingest a file, `engine.ingestDocuments`; see `EUHoldoutEvaluationTests.swift` lines 95–140 for a
minimal library setup, but do not read or use its data file) and compare the stored chunks' Greek
source text (`LegalChunkMetadata.sourceTextEl`) with the reference text of those pages: bag-of-words
recall and identifier recall over the whole document. Report which OCR engine the Processing Log
says read the pages.

### 5. Run and report

Run: `TEST_RUNNER_OI_OCR_BENCH=1 OI_TEST_TIMEOUT_SECONDS=3600 OPENINTELLIGENCE_DERIVED_DATA=/private/tmp/oi-build-ocr scripts/thesis_run_tests.sh /private/tmp/oi-logs/ocrbench1.log -only-testing:OpenIntelligenceTests/GreekOCRBenchmarkTests`
(the script doesn't retry "Simulator device failed to launch": run it again once if that happens).

Write `Docs/Thesis/plans/ocr-test-set-results.md` with:
- the exact command(s) and the summary lines of the log (`[OCRBench] SUMMARY`, and the
  `✔ Test run with …` / `Executed N tests` line);
- a table: rows = version (clean, scan, photo, owner's photos) × reader (Vision, PaddleOCR, app
  path), columns = CER, WER, bag-of-words recall, identifier recall, number recall, s/page;
- the whole-import result of step 4;
- the three worst pages per version with a short note on what went wrong (columns, stamps, tables,
  rotation, accents), quoting at most a line of OCR output each;
- any OCR bug you found (file, function, evidence), not fixed;
- draft text for `Docs/Thesis/FORK_CHANGES.md` (why, what, files, verification), for the 5.7
  section of `CHANGELOG.md` and a results row for `Docs/Thesis/METHODS_SUMMARY.md`. Claude Code
  merges these.

## Done when

The generator, the set, the suite and the results file exist; the suite builds; the results file
holds the measured table (or, if the Simulator was never free, says so and has everything ready to
run).
