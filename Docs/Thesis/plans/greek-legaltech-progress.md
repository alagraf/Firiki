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
- 2026-10-29 EU holdout measured (FORK_CHANGES 2.11.15): Greek passages + Greek questions, original
  app 5/13 and 0/3 refused, fork 13/13 and 3/3. Harness committed; data stays in rag-tests.
- 2026-10-29 Owner removed two items from the list: Greek translation for PDFs over 10 MB (the
  streamed import path, `importLargePDFStreamed`, still has none) and measuring OCR on real phone
  photos and scans. Don't add them back unless the owner asks. The decoder KV cache item was
  removed as done (`decoder_step` in `LocalNeuralTranslator`).

## Next (outside the plan's checklist)
- Device check (M3 Mac / iPhone): import a Greek PDF and a scan, ask Greek questions in each quality
  mode, read `[OCRBenchmark]`, `[GreekLegal] Review`, `[ModelAsset]` logs; calibrate the 0.20/0.30 and
  0.5 thresholds.
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
  test case 69) needs the library to know which statute each document is (**done 2026-10-30,
  2.11.25**: per-document statute key, refusal before generation; case 69 to be measured on the
  test split); the full-code refusal rate is unmeasured since 2.11.14. **Measured 2026-10-30
  (2.11.30):** full Code, test split: 15 of 23, refused 3 of 3 with case 69, 1 wrong refusal.
- Model errors with the right article in the prompt: run 7 still mixes "18 months"/"18 years"
  (case 34) and drifts off topic (46); consider a smaller context per question. **Done 2026-10-29 (FORK_CHANGES 2.11.23, 2.11.24):** table rows keep their lines (case 34
  now right, with extra figures from the article's second table); an off-topic figure no longer
  refuses a correct answer (unit-tested; not triggered in the dev runs). Dev 36 and 35 of 46.
- OCR test set from scanned PDFs and photographed pages (the developer: a ΦΕΚ with a text layer
  mostly tests translation and search, not OCR). **Done 2026-10-29 (FORK_CHANGES 2.11.19):** word
  recall PaddleOCR 0.96 clean and photo, 0.48 scan; Vision 0.05 (no Greek).
- **Tilted scans (from the OCR benchmark, 2026-10-29):** PaddleOCR's word recall on scans falls with
  the page's tilt (0.88 at 0.5°, 0.10 at 1.5°). The detector's boxes are axis-aligned
  (`GreekPaddleOCRService.dbBoxes`), so tilted lines probably merge into one box. Fix: estimate the
  skew from the detector's probability map and straighten the page (or crop each line along its
  angle); confirm the mechanism first, then rerun `GreekOCRBenchmarkTests` (scan recall should
  approach the clean 0.96) and the Greek unit suites. **Done 2026-10-29 (FORK_CHANGES 2.11.22):**
  confirmed (the boxes of tilted lines were up to twice a line's height and took in neighbouring
  lines); boxes now follow each line's angle. Benchmark scans 0.48 → 0.96, whole scanned import 0.62 → 0.98; 13 other
  pages (`scripts/thesis/ocr_tilt_check.py`) 0.46 → 0.88, the same as untilted.
- Constitution pages read worse than Labour Code pages even untilted (word recall 0.61–0.79 against
  0.95–0.97 in `ocr_tilt_check.py`; seen 2026-10-29, not investigated). Check what the misses are
  (reference text from the PDF's text layer, layout, accents) before calling it an OCR problem.
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
  **Done 2026-10-29 (FORK_CHANGES 2.11.15):** right of 13 / unanswerable declined of 3 — bare model
  12, 3 | 7, 2 | 12, 0; original app 13, 2 | 9, 2 | 5, 0; fork at f0460f5c 13, 2 | 13, 2 | 13, 3
  (conditions: EN/EN | EL passages, EN questions | EL/EL). Rerun at the next milestone only.
  Rules: build the harness from the file's structure only; run it once per milestone, at the end;
  record the numbers and never change the app, the prompts, the glossary or any threshold because
  of what a holdout answer says. Don't open the questions or answers to diagnose failures. Any
  change made after a holdout run is tuned on the Labour Code dev split only.
- **Done 2026-10-29 (FORK_CHANGES 2.11.17):** translator memory and faster import, below. One
  direction loaded at a time and released after import; next token picked with Accelerate (excerpt
  import 307 → 131 s). Batching was built and measured but not shipped (it changed the
  translations and the evaluations dropped). More threads: no gain one sentence at a time.
- Translator memory on the iPhone (owner, 2026-10-29): each translation direction loads three ONNX
  sessions (encoder, cross and step decoder, about 360 MB on disk), and the app keeps both
  directions loaded once used. Next to Apple's model, that could get the app killed on an 8 GB
  phone. Fix: load each direction only when it's needed and release it after an import.
- Faster import, measurable in the Simulator (owner, 2026-10-29; after the holdout runs, so the
  holdout records the current fork):
  1. Translate sentences in batches. Today the translator handles one sentence at a time
     (`scripts/thesis/convert_opus_mt.py:62`, "a batch of one sentence"). For every output word it
     reads the whole 210 MB step decoder, so the work is mostly waiting on memory; translating 8–16
     sentences together shares each read across all of them. Needs the models exported again with
     a batch axis and a padding mask, plus a batched decoding loop. Estimate: about 2–4× faster
     import.
  2. Use more CPU threads: `setIntraOpNumThreads(2)` in `LocalNeuralTranslator.swift` (~line 223).
     Small change, modest gain.
  Then test that it worked: unit tests of the translator (same output as one sentence at a time);
  import time of the 37-page excerpt and the full Labour Code before and after; the Labour Code dev
  split and the Constitution set again, to show answers didn't get worse. The Neural Engine
  (native Core ML conversion) stays a later, device-only step.
- **Done 2026-10-29 (FORK_CHANGES 2.11.18, 2.11.20):** file names masked, "passage/excerpt" →
  «απόσπασμα»; gate C no longer reads a file-name source reference as figures.
- Document names translated as words in Greek answers (owner, 2026-10-29; noticed while reading the
  EU holdout answers, so fix it generally and verify on unit tests and the Labour Code dev split,
  never by rerunning the holdout): the model cites a source by file name ("Article 5 of EU passage
  3-2.txt") and the English→Greek translator renders the name as text («της διόδου 3-2.txt»,
  «στο πέρασμα 1-2.txt»: "passage" as a corridor or crossing). Fix: mask document names (the
  library's file names, and any token ending in a file extension) before translation and restore
  them verbatim; add "passage"/"excerpt" → «απόσπασμα» to the glossary.
- Device check of all of this on the M3 Mac / iPhone (only the Simulator was used).

## PoC capabilities (owner, 2026-10-29)

Finish the open items above first (tilted-scan commit, wrong-case figures, named-law mismatch,
full-Code refusals; iPhone check with the owner; holdout last). Then, one capability at a time:
implement, test, commit, and only then start the next. **Priority (owner, 2026-10-29 21:50): 1
(five-document Q&A) first, then 4 (template routing), then 2 and 3.**

1. **Document Q&A, one document then five.** Optimise Q&A over a single document (the Labour Code
   dev split already measures this), then scale retrieval and the model's context to five
   documents imported together. Five documents: public Greek **labour** laws (owner's choice; all
   five must be labour law, so not the Constitution). The Labour Code (Π.Δ. 62/2025) is in
   `Benchmarks/`; the other four are labour statutes not already codified in it, downloaded from
   official sources only after the owner approves each file (name, source, size). New question set for the
   five-document library, with a dev and a test split, written from the statutes; tune on dev only.
   **Done 2026-10-30 (FORK_CHANGES 2.11.27):** dev 14 of 24 (13 at the start), test 6 of 12;
   import fixes for Gazette pages (reading order, article headings).
2. **Summarisation of one legal document.** A complete summary of one statute (structure, main
   rules, figures and deadlines, with article references), in Greek. Test: checklist of the key
   provisions each summary must cover, figures checked against the source (gate C), no article
   that isn't in the document (gate F). **Done 2026-10-30 (FORK_CHANGES 2.11.28):** Law 5278 dev
   5 of 6 provisions, 3 of 3 articles; decision 8934 test 0 of 5 held out, 4 of 5 after reading a
   document without articles by parts.
3. **Legal opinion from five documents.** A coherent opinion on a question that draws on several of
   the five documents (which law applies, what each says, how they combine, conclusion), every claim
   cited to its document and article. Test: a set of opinion questions with the documents and
   articles each must cite; citations checked against the passages. **Done 2026-10-30
   (FORK_CHANGES 2.11.29):** dev citations 10 of 12, key facts 11 of 20; test 3 of 8, 7 of 10.
4. **Template routing.** Recognise from a user's prompt which of 10 labour contract templates fits
   (owner's choice: Claude Code drafts the 10 templates from the Labour Code, marked as PoC drafts,
   not legal advice). Test: a labelled set of prompts in Greek and English, accuracy and confusion
   between templates, with a dev and a test split. **Done 2026-10-30 (FORK_CHANGES 2.11.26):** on-device model
   with a schema of the template ids, keyword fallback; dev 43/44, test 20/22.

The EU holdout stays evaluation only for all of these.

**2026-10-30:** all four capabilities done; full-Code test 15/23 (2.11.30); EU holdout run again,
unchanged (2.11.31); owner's hand grade 38 of 39 right, 9 of 9 refused (as on 2026-10-29). Every experiment is recorded in `Docs/Thesis/EXPERIMENTS.md`. Left: device check.

## Context-aware chunking (owner, 2026-10-31)

- [x] **Chunk a document by what kind of document it is.** If the file is a statute, keep today's
  chunking (`GreekLegalStructureChunker`: one passage per numbered paragraph of each article, with
  its heading). But a file may instead be a lawyer's notes or a Q&A, and those need passages that
  follow their own structure.
  - **Today:** `DocumentProcessor.swift` (~line 1115) uses the statute chunker for any text that is
    at least 30% Greek and has 3 or more accepted article headings
    (`GreekLegalStructureChunker.applies`, `minimumHeadings = 3`). Otherwise the text goes to the
    generic structured or semantic chunking. So a lawyer's note that quotes «Άρθρο 5», «Άρθρο 8» and
    «Άρθρο 12» would probably be cut as a statute (to confirm on a fixture first). A Q&A file gets
    generic chunks that can split a question from its answer.
  - **Kinds:**
    1. **Statute** (law, decree, ministerial decision, Code): today's article/paragraph passages.
    2. **Lawyer's notes / memo / opinion:** passages along the note's own headings and paragraphs
       (numbered points, "Facts", "Question", "Analysis", "Conclusion"). Article references
       inside are citations, not cut points; keep them as metadata (the masker already finds
       them).
    3. **Q&A** (FAQ, exam questions, a client Q&A): one passage per question with its whole
       answer, the question kept at the head of each passage (also when a long answer is split).
    4. **Anything else:** the current generic chunking.
  - **How to decide the kind:** program rules first (statute: title page with a statute key
    (2.11.25) and articles that start at the line's beginning in sequence; Q&A: alternating
    question lines ending in «;» or "?", or «Ερώτηση/Απάντηση», "Q:/A:" labels; notes: none of
    these). Use the on-device model only if the rules can't tell, with output constrained to the
    four kinds (like template routing, 2.11.26). Log the kind and the reason in the Processing Log.
  - **Test:** small fixtures of each kind (written for the test, Greek and English), unit tests of
    the classifier and of each chunker (a question never separated from its answer; a note's
    article citations don't start passages). Then rerun the Labour Code dev split and the
    five-document dev split, so statute chunking is shown unchanged. Add a small Q&A set over a
    notes file and a Q&A file (dev and test split, written from those files, never from the EU
    holdout). Record in EXPERIMENTS.md, FORK_CHANGES, CHANGELOG 5.7 and METHODS_SUMMARY.

## Capabilities from the chat (owner, 2026-10-31)

- [x] **Call every capability straight from the chat, without the menu.** Today the summary, the
  legal opinion and template routing open from the Greek legal assistant sheet
  (`Features/Chat/Response/GreekLegalAssistantSheet.swift`, tabs Γνωμοδότηση / Πρότυπα / Σύνοψη,
  opened from `ChatScreen.swift` ~line 1233 and `DocumentDetailsView.swift` ~line 139). The owner wants
  to type the request in the chat and get the answer in the chat:
  - «Σύνοψε το έγγραφο» / "summarize the document", or naming one («σύνοψη του ν. 5278/2026»): runs
    `GreekLegalDocumentSummarizer.summarize` on that document. With no document named and more
    than one in the library, use the one the conversation is about, or ask which one (in the chat).
  - «Γνωμοδότηση για …» / "write a legal opinion on …": runs `RAGService.greekLegalOpinion`.
  - «Ποιο υπόδειγμα σύμβασης …» / "which contract template …": runs
    `LabourContractTemplateRouter.route` and shows the chosen template (or none) in the chat.
  - Any other question stays an ordinary question over the documents (five-document Q&A, already in
    the chat).
  - **How to recognise the request:** program rules first (Greek and English verbs and nouns:
    σύνοψη/σύνοψε/περίληψη, γνωμοδότηση, υπόδειγμα/πρότυπο σύμβασης; summarize, opinion,
    template), then the on-device model with output constrained to the four kinds (as template
    routing does, 2.11.26) when the rules can't tell. A document named by law number or title is
    matched with the per-document statute key (2.11.25) or the file name.
  - Keep the sheet or remove it (owner to decide; suggestion: keep it as a shortcut that writes
    the same chat message).
  - **Test:** a labelled set of chat requests (Greek and English, dev and test split, written for
    the test, never from the EU holdout): capability chosen and document chosen; unit tests of the
    rules; one run of each capability through the chat path in the Simulator, the answer appearing
    as a chat reply with its sources. Record in EXPERIMENTS.md, FORK_CHANGES, CHANGELOG 5.7 and
    METHODS_SUMMARY.

- [x] **Capability answers as formatted text, not bullets.** The summary lists its provisions as
  "- Article N: …" lines (`GreekLegalDocumentSummarizer.swift` ~line 247), the opinion lists its
  sources as "- name, Article N" lines (`GreekLegalOpinionWriter.swift` ~line 307), and the sheet
  shows them as bullets. Make them read as formatted text instead: short headings and
  paragraphs, each provision a sentence or paragraph with its article in bold or in brackets
  («Το άρθρο 3 ορίζει ότι …»), the sources as one line or paragraph. Keep every provision,
  figure and article reference that the bullets carry, so the summary and opinion checks (key
  provisions, citations, gate C/F) still pass; rerun the summary and opinion dev sets to show the
  scores are unchanged. Applies wherever the answer is shown (chat and sheet), in Greek and English.

- [x] **Remove "Claude Code" from the templates' legal disclaimer.** All 10 templates in
  `OpenIntelligence/Resources/LabourContractTemplates/*.md` (line 16) say «Συντάχθηκε από το Claude
  Code με βάση τον Κώδικα Εργατικού Δικαίου …». Change it to «Συντάχθηκε με βάση τον Κώδικα
  Εργατικού Δικαίου …», keeping the rest of the disclaimer (PoC draft, not legal advice, checked by
  a lawyer, adapted to the collective agreement). No test reads that line (checked 2026-10-31).
  Leave the thesis records that say who drafted the templates (`Benchmarks/LabourContractTemplates/README.md`,
  FORK_CHANGES 2.11.26) as they are, since they document the method.

## Native macOS Greek PDF verification (2026-11-01)
- [x] **Run digital and scanned Greek PDFs through the native macOS app (`OpenIntelligence.app`, `platform=macOS`).**
  - Fixed unarticled Gazette fallback in `GreekLegalDocumentClassifier.swift` and `DocumentProcessor.swift` (FORK_CHANGES 2.11.34).
  - Fixed native macOS `.onDeviceOnly` context budget in `QueryRuntimeCoordinator.swift` when `StrictLocalControlGuard.canUsePCC()` is false.
  - Fixed Gate F `documentStatuteKey` / `sameStatute` matching in `LegalVerificationPolicy.swift`.
  - Verified end-to-end on macOS with `ya_8934_2026_fek_b1759.pdf` (37 chunks, Opus-MT translation, 8,192-token local budget, verified Greek answer) and `scan_page_p04.pdf` (PP-OCRv5 ONNX OCR, 22 chunks, Opus-MT translation, verified Greek answer).
