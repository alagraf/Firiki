# Plan: Phase 2b testing gaps and demo smoke runner

Status: implemented 14 Nov 2026 (standing permission from the owner). Closes flows (3) and (4) plus
the opt-in `"My Mac"` smoke check and `scripts/demo_check.sh` from `POC_PROGRESS.md`.

## Goal

Close the remaining items of Phase 2b (`POC_PROGRESS.md` lines 167–178):
1. Flow (3): End-to-end Greek Q&A (`RAGService.query`) over a small fixture library using a stand-in
   `LLMService` (`GreekLegalEndToEndFakeTests`).
2. Flow (4): Verification of the five demo PDFs (`GreekDemoPDFImportTests`) without a language model:
   statute key detection, minimum article counts, Greek source and real Opus-MT English text, plus
   bundle asset presence for PaddleOCR and Opus-MT.
3. Opt-in UI smoke test (`DemoSmokeUITests` in `FirikiUITests`, enabled via `OI_DEMO_SMOKE=1` /
   `TEST_RUNNER_OI_DEMO_SMOKE=1`) running on `"My Mac"` with the pre-imported library and asking
   the four README prompts.
4. `scripts/demo_check.sh` running the unit suite and (by default on request or when `DEMO_SMOKE=1`)
   the `"My Mac"` smoke test.

## Open questions and choices

- **Full-corpus translation time in `GreekDemoPDFImportTests`:** Translating all chunks of all five
  PDFs via `RAGService.ingestDocuments` in the iOS Simulator takes ~23 minutes (`pd_62_2025_fek_a121.pdf`
  260 pages ≈ 15 min; `n_5239_2025_fek_a178.pdf` 104 pages ≈ 6 min).
  - *Recommended option (chosen):* Always extract and chunk all 5 PDFs via `DocumentProcessor`, verify
    every statute key and minimum article count, run real Opus-MT translation on sampled Greek chunks
    from each of the 5 PDFs, and run full end-to-end `RAGService.ingestDocuments` (real ONNX + SQLite
    + embeddings) on the two compact PDFs (`ya_8934_2026_fek_b1759.pdf` and `n_5278_2026_fek_a22.pdf`,
    under ~1 minute total). Keep a second `OI_FULL_PDF_IMPORT=1` opt-in test that runs full
    `RAGService.ingestDocuments` over all 5 PDFs. This keeps `scripts/demo_check.sh` fast enough to
    run routinely while exercising real ONNX translation and persistence on every run.
- **`scripts/demo_check.sh` behavior:** Run `scripts/thesis_run_tests.sh` over the unit suite first;
  run `DemoSmokeUITests` on `platform=macOS` when `DEMO_SMOKE=1` is passed (and print exact command
  instructions when omitted, or fail if `DEMO_SMOKE=1` fails), since `"My Mac"` Apple Intelligence
  smoke requires the pre-imported library and signed macOS test runner host permissions.

## Changes

1. **`Firiki/Features/Chat/Conversation/ChatComposerV2.swift`:**
   - Add `.accessibilityIdentifier("chatComposerField")` to the composer `TextField`.
   - Add `.accessibilityIdentifier(showsStop ? "stopGenerationButton" : "sendMessageButton")` and
     `.accessibilityLabel(showsStop ? "Stop generating" : "Send message")` to the send/stop button.
2. **`FirikiTests/Services/GreekLegal/GreekLegalEndToEndFakeTests.swift`** (new file):
   - Uses a stand-in `LLMService` (copying `GreekEvalOnDeviceModel`/`ShortcutsActionTests` pattern)
     and a synthetic 3-article Greek statute ingested into a temporary library via `RAGService.ingestDocuments`
     (with real Opus-MT & embeddings, cleaned up in `defer`).
   - Tests:
     a. Greek question gets a verified Greek answer citing the article (`review?.abstained == false`,
        Greek text, article number and grounded number present).
     b. Question about a statute not in the library (`ν. 9999/2026`) returns
        `LegalVerificationPolicy.greekAbstentionMessage` (`review?.abstained == true`).
     c. Unsupported numbers on the queried topic (`questionWithUnsupportedNumberAbstainsInGreek`) fail
        Gate C (`Numeric Sanity`) in `RAGService` Step 7.5 and return
        `LegalVerificationPolicy.greekAbstentionMessage` (`review?.abstained == true`).
     d. Answer citing a wrong statute (`answerCitingWrongStatuteAbstainsInGreek`) fails Gate F /
        Gate I and returns `LegalVerificationPolicy.greekAbstentionMessage` (`review?.abstained == true`).
3. **`FirikiTests/Services/GreekLegal/GreekDemoPDFImportTests.swift`** (new file):
   - Always-on bundle check: `LocalNeuralTranslator.isAvailable(.greekToEnglish)` and `.englishToGreek`,
     plus `GreekPaddleOCRService.shared.isAvailable` and non-nil URLs for `PP-OCRv5_mobile_det.onnx`,
     `el_PP-OCRv5_mobile_rec.onnx`, and `el_dict.txt`.
   - Always-on 5-PDF import check: runs `DocumentProcessor.shared.processDocument` across all 5
     PDFs (`pd_62_2025_fek_a121.pdf`, `n_5239_2025_fek_a178.pdf`, `n_5278_2026_fek_a22.pdf`,
     `n_5316_2026_fek_a105.pdf`, `ya_8934_2026_fek_b1759.pdf`), checks statute keys (`PD:62/2025`,
     `LAW:5239/2025`, `LAW:5278/2026`, `LAW:5316/2026`, `MD:8934`), checks extracted article counts
     above minimums (`>= 300`, `>= 50`, `>= 12`, `>= 20`, parts `>= 2` for MD 8934), verifies Greek +
     real Opus-MT English text on sampled chunks from all 5, and runs full `RAGService.ingestDocuments`
     (real ONNX + persistence) on `n_5278_2026_fek_a22.pdf` and `ya_8934_2026_fek_b1759.pdf` with cleanup.
   - Opt-in (`OI_FULL_PDF_IMPORT=1`) test running `RAGService.ingestDocuments` across all 5 PDFs.
4. **`FirikiUITests/DemoSmokeUITests.swift`** (new file):
   - Skips unless `OI_DEMO_SMOKE=1` (via `TEST_RUNNER_OI_DEMO_SMOKE=1`).
   - Launches the app cleanly, dismisses first-run onboarding if shown, submits the 4 README prompts
     (`Πόσες ημέρες άδεια πατρότητας δικαιούται ο εργαζόμενος;`, `Συνόψισε το ν. 5278/2026`,
     overtime opinion prompt, `Ποιο υπόδειγμα σύμβασης ταιριάζει για τηλεργασία;`), waits for
     generation to complete (`sendMessageButton` restored), verifies no `"Σφάλμα"`/`"Error"` banner
     and non-empty grounded Greek response with citation/contract indicator.
5. **`scripts/demo_check.sh`** (new executable script):
   - Runs full `FirikiTests` via `scripts/thesis_run_tests.sh`.
   - When `DEMO_SMOKE=1` is set, runs `DemoSmokeUITests` against `platform=macOS`.

## Verification

- `./scripts/demo_check.sh` (runs `./scripts/thesis_run_tests.sh /private/tmp/firiki-demo-check-unit.log`):
  - `** TEST BUILD SUCCEEDED **`
  - `Executed 1292 tests, with 9 tests skipped and 0 failures (0 unexpected) in 296.626 (297.004) seconds`
  - `✔ Test greekQuestionReturnsGreekAnswerWithArticleCitation() passed after 39.719 seconds.`
  - `✔ Test questionAboutMissingLawReturnsFixedGreekRefusal() passed after 68.248 seconds.`
  - `✔ Test questionWithUnsupportedNumberAbstainsInGreek() passed after 16.388 seconds.`
  - `✔ Test answerCitingWrongStatuteAbstainsInGreek() passed after 9.754 seconds.`
  - `✔ Test bundledOCRAndTranslationModelsExist() passed after 0.124 seconds.`
  - `✔ Test demoPDFExtractsStatuteArticlesAndBilingualText(_:) with 5 test cases passed after 540.292 seconds.`
  - `✔ Test ragServiceIngestsCompactDemoPDFsWithBilingualPersistence() passed after 82.490 seconds.`
  - `✔ Test run with 165 tests in 31 suites passed after 623.051 seconds.`
  - `DemoSmokeUITests` skipped unless `DEMO_SMOKE=1` with a pre-imported Mac library.
- `xcodebuild build-for-testing -scheme FirikiUITests -destination 'platform=macOS' -derivedDataPath /private/tmp/oi-mac-build CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=""`:
  `** TEST BUILD SUCCEEDED **`.
- `xcodebuild test -scheme FirikiUITests -destination "platform=iOS Simulator,name=iPhone 18 Pro" -derivedDataPath /private/tmp/oi-build -only-testing:FirikiUITests/AccessibilityAuditTests -only-testing:FirikiUITests/DemoSmokeUITests`:
  `Executed 3 tests, with 1 test skipped and 0 failures (0 unexpected) in 83.779 (83.787) seconds`, `** TEST SUCCEEDED **` (`AccessibilityAuditTests`: `2` passed; `DemoSmokeUITests`: `1` skipped as opt-in).
