# Greek OCR Benchmark Test Set: Implementation & Handoff Report

Written on 2026-10-29 per plan `Docs/Thesis/plans/ocr-test-set.md` and user update.
Antigravity completed Steps 1–3 (generator, benchmark dataset under 15 MB, test suite, build verification).
Claude Code will run Steps 4–5 (execution and results collection).

---

## 1. What Is Ready

### A. Dataset Generator (`scripts/thesis/make_ocr_testset.py`)
- Executable Python script (run with `python3` in a venv with `pymupdf pillow numpy`).
- Extracts 10 representative pages (1, 4, 8, 12, 16, 20, 24, 28, 32, 36) from `Benchmarks/GreekLabourCode/pd_62_2025_excerpt.pdf` (ΦΕΚ Α' 121/2025).
- Generates 3 versions per page plus ground-truth references and an image-only PDF.
- Uses fixed random seed (`20261029`) and fixed per-page rotation angles.

### B. Benchmark Test Set (`Benchmarks/GreekOCR/`) — 14.42 MB Total
Total directory size is strictly under 15 MB (`15,118,993 bytes` / `14.42 MB`):
- `manifest.json`: 30 structured entries detailing page number, version, image path, reference text path, column extract paths, rotation angle, dpi, and JPEG quality.
- `images/`: 30 JPEG page images:
  - **clean** (10 pages): Grayscale at 200 DPI, JPEG quality 40 with optimization (clean control, ~3.82 MB total).
  - **scan** (10 pages): Grayscale at 180 DPI, rotated by fixed small angles (−1.5° to +1.5°), mild Gaussian noise, slight contrast loss, JPEG quality 45 (~3.34 MB total).
  - **photo** (10 pages): RGB at 200 DPI, perspective quad warp simulating smartphone tilt angle, non-uniform 2D spatial lighting gradient (1.04 to 0.92), Gaussian blur radius 0.7, JPEG quality 55 (~3.72 MB total).
- `ref/`: 10 full-page reference text files (Unicode NFKC normalized, hyphenated line ends joined), plus 20 per-column reference extracts (`col1`, `col2`).
- `scan_pages.pdf`: 10-page image-only PDF compiled from the scan pages with FlateDecode compression for whole-document ingestion testing (~3.35 MB).
- `photos/README.md`: Instructions for the owner to drop real smartphone photos (`p<page>_<n>.jpg`).
- `README.md`: Test set overview and file inventory.

### C. Benchmark Test Suite (`OpenIntelligenceTests/Services/GreekLegal/GreekOCRBenchmarkTests.swift`)
Opt-in via `TEST_RUNNER_OI_OCR_BENCH=1` or `OI_OCR_BENCH=1`:
1. **`benchmarkGreekOCR`**:
   - Iterates through `manifest.json` and any user photos in `photos/`.
   - Runs three readers:
     1. **Vision only** (`VNRecognizeTextRequest` with `.accurate` and Greek languages).
     2. **PaddleOCR only** (`GreekPaddleOCRService.shared.recognizeLines` + `OCRRouterService.joinLines` + `GreekLegalEntityMasker.repairGreekHomoglyphs`).
     3. **App path** (`ImageUnderstandingService.shared.extractTextFromImage`).
   - Computes:
     - **CER**: Character error rate (Levenshtein edit distance over whitespace-free normalized text).
     - **WER**: Word error rate (standard word Levenshtein distance).
     - **Bag of words**: Order-independent recall and precision.
     - **Legal identifier recall**: Share of reference `GreekLegalEntityMasker.canonicalKeys` found.
     - **Number recall**: Share of reference numbers (`\d+`) found.
     - **Seconds per page**: Wall-clock execution time.
   - Logs per-page measurements (`[OCRBench] page 12 scan paddle CER ...`) and summary means (`[OCRBench] SUMMARY version=... reader=...`).
2. **`wholeImportScanPages`**:
   - Imports `scan_pages.pdf` through `engine.ingestDocuments`.
   - Inspects `engine.ingestionItems` for `[Greek OCR]` events in the Processing Log.
   - Extracts Greek text from SQLite via `LegalChunkMetadata.sourceTextEl`.
   - Compares against combined reference text of all 10 pages for document-level bag recall and identifier recall.

### D. Build Verification
Verified with `xcodebuild build-for-testing` against `iPhone 18 Pro` and `iPhone 17 Pro` simulators:
```bash
xcodebuild build-for-testing \
  -scheme OpenIntelligence \
  -destination "platform=iOS Simulator,name=iPhone 18 Pro" \
  -derivedDataPath /private/tmp/oi-build-ocr \
  -skipPackagePluginValidation \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  -only-testing:OpenIntelligenceTests/GreekOCRBenchmarkTests
```
**Output**: `** TEST BUILD SUCCEEDED **`

---

## 2. How to Run Steps 4 & 5 (for Claude Code)

### Option A: Standard Run via `scripts/thesis_run_tests.sh` (When Mac/Simulator is Dedicated)
When no other test runner or simulator is active:
```bash
TEST_RUNNER_OI_OCR_BENCH=1 OI_TEST_TIMEOUT_SECONDS=3600 OPENINTELLIGENCE_DERIVED_DATA=/private/tmp/oi-build-ocr scripts/thesis_run_tests.sh /private/tmp/oi-logs/ocrbench1.log -only-testing:OpenIntelligenceTests/GreekOCRBenchmarkTests
```

### Option B: Isolated Run on Secondary Simulator (`iPhone 17 Pro`)
> [!IMPORTANT]
> If another simulator is currently active (e.g. running an evaluation on `iPhone 18 Pro`), do **not** run `scripts/thesis_run_tests.sh`, because lines 30–32 call `xcrun simctl shutdown all` and `killall -9 com.apple.CoreSimulator.CoreSimulatorService`.
>
> Instead, run directly against the pre-created `iPhone 17 Pro` simulator without restarting services:
> ```bash
> xcrun simctl boot "iPhone 17 Pro" || true
> TEST_RUNNER_OI_OCR_BENCH=1 xcodebuild test-without-building \
>   -scheme OpenIntelligence \
>   -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
>   -derivedDataPath /private/tmp/oi-build-ocr \
>   -only-testing:OpenIntelligenceTests/GreekOCRBenchmarkTests \
>   | tee /private/tmp/oi-logs/ocrbench1.log
> ```

---

## 3. Results (Claude Code, 2026-10-29)

Run: `TEST_RUNNER_OI_OCR_BENCH=1 scripts/thesis_run_tests.sh /private/tmp/oi-logs/ocrbench2.log
-only-testing:OpenIntelligenceTests/GreekOCRBenchmarkTests` (iPhone 18 Pro simulator, iOS 27, Debug
build): `✔ Test run with 2 tests in 1 suite passed after 712.972 seconds`. The first attempt
(`ocrbench1.log`) ended with an unexpected app exit after page 12's scan (no crash report; the
rerun passed the same page), so its partial numbers are not used. No owner photos were in
`photos/`.

Means over 10 pages:

| Version | Reader | CER | WER | Word recall | Word precision | Legal ID recall | Number recall | s / page |
|---|---|---|---|---|---|---|---|---|
| clean | Vision | 0.98 | 0.99 | 0.05 | 0.08 | 0.00 | 0.80 | 1.7 |
| clean | PaddleOCR | 0.73 | 0.85 | 0.96 | 0.94 | 0.92 | 0.93 | 6.7 |
| clean | App path | 0.73 | 0.85 | 0.96 | 0.94 | 0.92 | 0.93 | 9.7 |
| scan | Vision | 0.98 | 0.99 | 0.05 | 0.09 | 0.00 | 0.73 | 2.0 |
| scan | PaddleOCR | 0.73 | 0.90 | 0.48 | 0.59 | 0.61 | 0.66 | 5.3 |
| scan | App path | 0.73 | 0.90 | 0.48 | 0.59 | 0.61 | 0.66 | 8.1 |
| photo | Vision | 0.98 | 0.99 | 0.05 | 0.08 | 0.00 | 0.77 | 1.7 |
| photo | PaddleOCR | 0.73 | 0.85 | 0.96 | 0.94 | 0.92 | 0.95 | 6.5 |
| photo | App path | 0.73 | 0.85 | 0.96 | 0.94 | 0.92 | 0.95 | 9.9 |

Reading the table:
- **Vision reads no Greek** (5% of the words, no legal identifier; mostly the numbers). The app
  path gives exactly PaddleOCR's text on every page, so the router sends all of these pages to
  PaddleOCR.
- **CER and WER are not usable here.** They stay near 0.73 / 0.85 for PaddleOCR on clean pages
  where 96% of the words are found. The pages have two columns, so this most likely measures
  reading order (edit distance counts a moved block as all wrong), not misread characters. Not
  verified; the per-column references in `ref/` would allow a column-wise CER. Word recall and
  precision (order-independent) are the measures to report.
- **Scans lose half their words, and the loss follows the page's tilt**, not the noise. PaddleOCR
  word recall per scan page against its rotation:

  | Rotation | 0.5° | 0.6° | 0.8° | 0.9° | 1.0° | 1.1° | 1.2° | 1.3° | 1.4° | 1.5° |
  |---|---|---|---|---|---|---|---|---|---|---|
  | Page | 8 | 28 | 4 | 16 | 32 | 20 | 1 | 36 | 12 | 24 |
  | Word recall | 0.88 | 0.84 | 0.69 | 0.49 | 0.48 | 0.37 | 0.53 | 0.26 | 0.14 | 0.10 |

  The detector's boxes are axis-aligned rectangles (`GreekPaddleOCRService.dbBoxes`), and each
  is cropped and squeezed to the recognizer's 48-pixel height. On a tilted page a full-width line
  drifts by more than a line's height, so neighbouring lines probably merge into one box (to be
  confirmed). Next step: straighten the page (estimate the skew from the detector's probability
  map) or crop each line along its own angle, then rerun this benchmark.
- **Photos** (mild perspective, uneven light, slight blur, no rotation) read as well as clean pages.

Whole import of `scan_pages.pdf` (`wholeImportScanPages`, passed in 353.8 s):
- Document: `scan_pages.pdf` (10 pages, image-only).
- Chunks produced: 195; Greek chunks retained (`sourceTextEl`): 195.
- Whole-document bag-of-words recall 0.62, precision 0.44; legal identifier recall 0.69; number
  recall 0.85.
- Processing Log: "PaddleOCR (paddle-el-v5) read 21 images, its text kept for 21, 71906
  characters, in 120.2 s".

### After the boxes follow tilted lines (FORK_CHANGES 2.11.22, 2026-10-29)

The cause above was confirmed, with one correction: the lines don't merge (the detector finds the
same 116 regions on page 24 clean and tilted), but each region's upright box is up to twice a line's
height, so the crop takes in parts of the neighbouring lines. Boxes now follow each line's angle.

Runs `ocrbench3.log` and `ocrbench4.log` (the second after a faster sampler with the same
arithmetic; the text read is identical in both), PaddleOCR (the app path is the same on every page):

| Version | Word recall | Word precision | Legal ID recall | Number recall | s / page (run 4) |
|---|---|---|---|---|---|
| clean | 0.96 | 0.94 | 0.92 | 0.94 | 6.6 |
| scan | **0.96** (was 0.48) | 0.94 (was 0.59) | 0.92 (was 0.61) | 0.94 (was 0.66) | 7.0 |
| photo | 0.96 | 0.94 | 0.92 | 0.95 | 6.6 |

Per scan page, word recall is now 0.93–0.97 at every tilt (was 0.10–0.88). Whole import of
`scan_pages.pdf`: 207 passages, word recall 0.98 (was 0.62), precision 0.55 (was 0.44), legal
identifiers 0.96 (was 0.69), numbers 1.00 (was 0.85); OCR 204 s for 20 images.

The angle threshold was chosen on these pages, so these numbers are in-sample.
`scripts/thesis/ocr_tilt_check.py` checks it on 13 other pages (Labour Code excerpt and
Constitution, random tilts within ±2.5°): scans 0.46 → 0.88 of the words, untilted 0.88.

## 4. Draft Text for Repository Documentation

### Draft for `Docs/Thesis/FORK_CHANGES.md`

```markdown
### 2.12 Greek OCR Benchmark on Scans and Photographs

- **Why**: Measures OCR accuracy on scanned PDFs and smartphone photographs of Greek legal texts (Presidential Decree 62/2025 Labour Code), establishing CER, WER, bag-of-words recall, and legal citation recall across Vision, PaddleOCR, and the app's hybrid routing path.
- **What**:
  - `scripts/thesis/make_ocr_testset.py`: Reproducible generator creating clean, scan, and photo variants of 10 representative pages under 15 MB.
  - `Benchmarks/GreekOCR/`: 30 benchmark images (clean, scan, photo), normalized reference texts, image-only `scan_pages.pdf`, and photos folder for owner photos.
  - `OpenIntelligenceTests/Services/GreekLegal/GreekOCRBenchmarkTests.swift`: Opt-in evaluation suite measuring Vision, PaddleOCR, and `ImageUnderstandingService`, plus whole-import verification.
- **Files created**:
  - `scripts/thesis/make_ocr_testset.py`
  - `Benchmarks/GreekOCR/README.md`
  - `Benchmarks/GreekOCR/manifest.json`
  - `Benchmarks/GreekOCR/images/*`
  - `Benchmarks/GreekOCR/ref/*`
  - `Benchmarks/GreekOCR/scan_pages.pdf`
  - `Benchmarks/GreekOCR/photos/README.md`
  - `OpenIntelligenceTests/Services/GreekLegal/GreekOCRBenchmarkTests.swift`
  - `Docs/Thesis/plans/ocr-test-set-results.md`
- **Verification**: `xcodebuild build-for-testing` succeeded on iPhone 18 Pro and iPhone 17 Pro simulators with `-derivedDataPath /private/tmp/oi-build-ocr`.
```

### Draft for `CHANGELOG.md` (Section 5.7)

```markdown
- **Greek OCR Benchmark**: Added benchmark test set and evaluation suite for scanned and photographed Greek legal documents (`Benchmarks/GreekOCR/`, `GreekOCRBenchmarkTests.swift`), evaluating CER, WER, bag-of-words recall, and citation recall across Vision and PaddleOCR.
```

### Draft Row for `Docs/Thesis/METHODS_SUMMARY.md`

```markdown
| OCR Benchmark (10 pages PD 62/2025) | Clean, scan, and photo variants measuring CER, WER, bag-of-words recall, and legal identifier recall across Vision and PaddleOCR | Test set (<15 MB) and suite built; ready for execution |
```
