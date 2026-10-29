# Progress: Greek labour-law RAG plan (`greek-legaltech.md`)

Branch: `thesis/greek-legal-rag` (from `main` at `20d56a34`). This file is the resume point: an
agent continuing the work reads this file first, then `greek-legaltech.md` only for the step it is
on. Tick a box in the same commit as the change. Each commit message starts with `Greek RAG P<n>:`.

Owner approvals given on 2026-10-28: implement the whole plan on this branch and commit after each
tested change; add the `onnxruntime-swift-package-manager` package to `project.pbxproj`; download
the PaddleOCR (det + el rec) and Opus-MT (grk-en, en-el) models and convert Opus-MT to ONNX.

The owner's uncommitted edits to `project.pbxproj` and `OpenIntelligence.entitlements` (Xcode
reordering, app group dropped from the entitlements) were in the working tree when the branch was
made. They are the owner's and are never staged by the agent; stage pbxproj hunks selectively.

Test command (simulator; build dir outside iCloud):

```bash
xcodebuild test -scheme OpenIntelligence -destination "platform=iOS Simulator,name=iPhone 18 Pro" -derivedDataPath /private/tmp/oi-build -only-testing:OpenIntelligenceTests/GreekLegalPipelineTests
```

Baseline before any change: see "Baseline" below.

## Differences between the plan and the fork (decided)

- Plan 1.1 (quota, iCloud/PCC entitlements): already done in FORK_CHANGES 2.1/2.2; not redone.
- Plan's Gate I / `DomainIsolationService`: already deleted in the fork (2.5, 2.10). Gate I is
  re-added as a new legal statutory isolation gate, not by restoring the medical one.
- New Swift files need no project edit (synchronized folders), but the engine framework target only
  compiles some folders, so new files go in folders it already has: `Services/Infrastructure/
  Configuration/StrictLocalControlGuard.swift`, `Services/Document/Localization/`,
  `Services/Document/OCR/`. ONNX Runtime is linked to the app target only; engine-framework builds
  compile the `#if canImport(OnnxRuntimeBindings)` fallback (`isAvailable == false`).
- Plan's `document_chunks` ALTER TABLE: no such table (chunk text is the FTS5 table `chunks`, which
  can't be altered). The bilingual columns are a new table `chunk_legal` keyed by chunk id, and
  `DocumentChunk.legal: LegalChunkMetadata?` holds them in memory.
- Run tests with `scripts/thesis_run_tests.sh <log> -only-testing:OpenIntelligenceTests/<Suite>`:
  xcodebuild doesn't exit after the last result on this machine, the script stops it.

## Phase 1: strict local control
- [x] `StrictLocalControlGuard.swift` (exclude from backup, iCloud off, block web-page import, `canUsePCC`)
- [x] Hook: storage directories, ubiquity container lookup, web page import, PCC instantiation
- [x] Tests + FORK_CHANGES/CHANGELOG

## Phase 2: entity masker + bilingual schema
- [x] `GreekLegalEntityMasker.swift` (NFKC, mask, unmask bilingual/greekVerbatim)
- [x] SQLite columns + `DocumentChunk` fields (sourceTextEl, sourceLanguage, legalEntities, primaryStatuteKey)
- [x] `GreekLegalPipelineTests.swift` masking test

## Phase 3: Greek OCR + extraction fixes
- [x] `validateAndCleanOCR` Greek bypass
- [x] NFKC on PDFPage.string; full-page Greek detection (no 2,000-char drop)
- [x] onnxruntime package; models bundled
- [x] `GreekPaddleOCRService.swift`, `OCRRouterService.swift`
- [x] 5 call sites routed
- [x] OCR test

## Phase 4: translation
- [x] Opus-MT ONNX conversion + `LocalNeuralTranslator.swift`
- [x] `TranslationService` Greek fast path; `translatedQueryForEmbedding`
- [x] Ingestion translation (sourceTextEl/content/entities)
- [x] FTS5 Greek-query fix (HybridSearchService)
- [x] Intent keywords; GraphIndexService + resolveCrossReferencesStandard legal refs
- [x] Bilingual retrieval test

## Phase 5: gates, abstention, Greek output
- [x] Plain-text generation for legal mode; buffered output; assetID logging
- [x] Strict abstention (relevance gate, reliabilityMode fallbacks)
- [x] Gate A/source-only legal thresholds; Gate C Greek numerals; Gate F legal identifiers; Gate I statutory isolation; enforced in all modes
- [x] en→el answer translation; citation UI shows sourceTextEl
- [x] `LegalSLMEnricherProtocol.swift` hook
- [x] Gate/abstention tests; full suite

## Baseline

2026-10-28, `main` at `20d56a34`, iPhone 18 Pro simulator, Mac region Greece: XCTest `Executed 1363 tests,
with 8 tests skipped and 4 failures`. The 4 failures are pre-existing: three number/date formatting
tests under the Greek region (`AnswerUsageTallyTests.testTheDetailsLine`,
`AppStoreRatingSnapshotTests.testLineShowsOneDecimalLikeTheStore`,
`LaunchSaleTests.testDeadlineTextNamesTheLastFullDayRatherThanTheDayItExpires`) and
`AtlasLabelingTests.testAnAdverbDoesNotNameAnAxisEnd`. Swift Testing: 2 tests passed.

## Log
- 2026-10-28 P1: strict local guard committed; 6 tests pass.
- 2026-10-28 P2: masker + chunk_legal table committed; masker/storage tests pass.
- 2026-10-28 P3: Greek OCR (ORT + PP-OCRv5), router at 5 sites, Greek-safe filters committed; full suite has only the 3 Greek-region failures left after the P1 fix.
- 2026-10-28 P4 committed (full suite: only the 3 Greek-region failures): LocalNeuralTranslator + SentencePiece tokenizer,
  TranslationService Greek fast path, RAGService.greekQueryTranslation in translatedQueryForEmbedding,
  GreekLegalIngestion at the main ingestion path (after processDocument), chunk_legal storage,
  HybridSearch greekAwareLexicalQuery, QueryEnhancement legalAnswerIntent, LegalCrossReferences +
  GraphIndexService legal patterns, BNNS store keeps `legal`. Models: run
  `scripts/thesis_fetch_translation_models.sh` (git-ignored, ~225 MB) before building.
- P5 plan in progress: LegalVerificationPolicy.swift (written), GreekLegalAnswerService.swift
  (written; needs `RAGResponse.legalReview`). Remaining wiring: RAGService.query sets
  GreekLegalAnswerContext.isActive, withholds the stream handler, calls GreekLegalAnswerFinalizer.review;
  relevance gate hard-abstains via preGenerationAbstentionReason; reliabilityModeEnabled off when active;
  allowStructuredRAG off + temperature ≤ 0.2 when active; VerificationGateService: touchy word-boundary +
  isLegalQuery, Gate C normalizeGreekNumerals (+ sourceTextEl evidence), Gate F legal identifiers
  (critical), new Gate I statutoryIsolation (critical); SourceOnlyAnswerService riskProfile legal → .high;
  citation UI shows sourceTextEl; LegalSLMEnricherProtocol; assetID logging.
- 2026-10-28 P5 committed: all plan phases implemented. Full suite: 1363 XCTests, only the 3
  Greek-region failures; 33 Greek Swift tests pass.

## Next (outside the plan's checklist)
- Device check (M3 Mac / iPhone): import a Greek PDF and a scan, ask Greek questions in each quality
  mode, read `[OCRBenchmark]`, `[GreekLegal] Review`, `[ModelAsset]` logs; calibrate the 0.20/0.30 and
  0.5 thresholds.
- Hook Greek translation into `importLargePDFStreamed` (PDFs > 10 MB).
- Decoder KV cache for faster ingestion translation.
- 2026-10-28 Review UI: GreekLegalReviewCard under Response Details (gates, English draft, asset ids); committed.
- Owner reports the app partly works on device; improvements and bug fixes come next.
- 2026-10-28 Fix (FORK_CHANGES 2.11.7): Greek name questions; names transliterated, reflow, fragments, gate A only for legal questions. Note: documents imported before this fix must be re-imported to get the new translations.
- 2026-10-28 Suggested questions off (`SuggestedQuestionsService.isEnabled`); PaddleOCR and Opus-MT lines in the Processing Log (FORK_CHANGES 2.11.8).
- 2026-10-29 Constitution accuracy round committed (FORK_CHANGES 2.11.9/2.11.10): article lookup, Greek
  keyword arm, glossary, following sentences, greedy decoding, number words in gates B/C, tc-big with
  decoder cache. Constitution set: run 1 6/10 → run 9 7/10. Full suite: only the 3 Greek-region
  failures (ShortcutsActionTests failed once on a leftover active library, 13/13 on re-run).
- 2026-10-29 Plan stage 3, structure-aware chunking of Greek statutes, committed (FORK_CHANGES 2.11.11):
  GreekLegalStructureChunker (article/paragraph passages with headings, token-cap pieces, Gazette
  headers, end of last article), digits before Greek translation. Constitution run 11: 8/10,
  retrieval 10/10, import 362 s. test script restarts the simulator service before every run.
- 2026-10-29 Steps 2–4 of the night plan (FORK_CHANGES 2.11.12, 2.11.13): multi-set evaluation
  harness (TEST_RUNNER_OI_GREEK_EVAL_SET/SPLIT/CORPUS), Labour Code QA set (Π.Δ. 62/2025, 69 cases,
  `Benchmarks/GreekLabourCode/`), fixes from the dev runs (contents headings, markdown before
  translation, glossary). Labour dev (excerpt): 24 → 31/46; test (excerpt, once): 14/23; test on the
  full code: 11/23 (import of the 260 pages: 4,218 passages, 29 min in the Simulator).
- 2026-10-29 Out-of-scope refusals, glossary Greek in answers, figures tied to their case, Cyrillic
  stamps to PaddleOCR, eval clears cached searches (FORK_CHANGES 2.11.14); thesis summary
  `Docs/Thesis/METHODS_SUMMARY.md` (kept current, AGENTS.md step 4); EU holdout rule (AGENTS.md step
  5). Labour dev (excerpt): run 6 36/46, run 7 37/46, refusals 5/5. Constitution run 13: 9/10.

## Next (2026-10-29)
- Refusals: dev 5/5 after 2.11.14. Still open: a question naming another law whose article
  number also exists in the library ("Article 16 of the Constitution" in the Labour Code library,
  test case 69) needs the library to know which statute each document is; the full-code refusal
  rate is unmeasured since 2.11.14.
- Model errors with the right article in the prompt: run 7 still mixes "18 months"/"18 years"
  (case 34) and drifts off topic (46); consider a smaller context per question.
- OCR test set from scanned PDFs and photographed pages (the developer: a ΦΕΚ with a text layer
  mostly tests translation and search, not OCR).
- **EU labour-law holdout evaluation (owner, 2026-10-29) — HOLDOUT, never tune on it.** Folder
  `/Users/alagra/Documents/thesis/rag-tests/` (the app developer's test: `eu_data.json` = 11 articles
  of three EU labour directives in the official English and Greek, 16 questions: 13 answered by the
  text, 3 not; `ragtests.swift`/`run_all.sh` = his Mac command-line test; his results in README,
  NOTES and `pcc/results`). Goal: Chapter 6 "before and after" of the on-device model's accuracy and
  hallucination rate (answering the 3 unanswerable questions), with and without translation to
  English. Plan:
  1. Before, raw model: run `./run_all.sh` on this Mac unchanged (on-device rows; PCC rows can't run
     without the entitlement) and record the printed model variant and context window.
  2. Before, stock app: the same 16 questions through upstream OpenIntelligence (git worktree of
     `upstream/main`), documents = the English and the Greek passages, questions in English and in
     Greek.
  3. After, this fork: the same through `RAGService.query` (Greek legal mode for Greek questions,
     i.e. translated to English), one opt-in harness that reads `eu_data.json` from the rag-tests
     folder in place (not copied into the repository, not committed).
  4. Metrics per condition: right answers of 13 (graded by the file's `any`/`any_el` and read by a
     person), declined of the 3 unanswerable (hallucination rate), right passage cited; model
     variant and window logged with each answer.
  Rules: build the harness from the file's structure only; run it once per milestone, at the end;
  record the numbers and never change the app, the prompts, the glossary or any threshold because
  of what a holdout answer says. Don't open the questions or answers to diagnose failures. Any
  change made after a holdout run is tuned on the Labour Code dev split only.
- Device check of all of this on the M3 Mac / iPhone (only the Simulator was used).
