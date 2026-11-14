# Firiki PoC: progress since the fork and CEO demo readiness

Audit of 14 November 2026, at `main` = `07800929` (same as `origin/thesis/greek-legal-rag`).
Read-only audit: nothing in the code was changed to produce it.

**Diff base.** OpenIntelligence was forked at `67977e40`; the last upstream merge is `a7276983`
(22 Oct 2026). Every figure below is `a7276983..main`. The local `upstream/main` is no longer a
valid base: it has moved 355 commits past the fork point (upstream has since split
`RAGService.swift` into many files), so diffing against it makes the fork look like +22k lines in
`RAGService.swift`.

**Scale.** 63 fork commits (18 Oct → 14 Nov 2026), 1,511 files changed, +34k / −124k lines. Most
deletions are removed billing, release tooling, upstream documentation and assets.

---

## Phase 1: Changes since the fork

### 1. New components (about 6,900 lines of new Swift)

| Area | Components | What it does |
|---|---|---|
| Legal capabilities | `GreekLegalChatRouter` (311 lines), `GreekLegalDocumentSummarizer` (389), `GreekLegalOpinionWriter` (585), `LabourContractTemplateRouter` (211) + 10 Greek contract templates | Recognises summary, opinion and template requests in the chat and runs them |
| Greek OCR | `GreekPaddleOCRService` (490), `OCRRouterService` (206), `IngestionLogRecorder`, PP-OCRv5 ONNX models (12 MB, in git) | On-device Greek OCR (Apple Vision reads no Greek); tilt-aware line boxes; re-OCR of PDFs with a garbled Greek text layer |
| Greek ingestion and chunking | `GreekLegalStructureChunker` (461), `GreekLegalNotesChunker`, `GreekLegalQAChunker`, `GreekLegalDocumentClassifier`, `GreekLegalIngestion`, `PDFPage+Greek` | One passage per article paragraph; records which statute a document is (`LAW:5278/2026`); chunker chosen by document type |
| Translation | `LocalNeuralTranslator` (875), `GreekLegalEntityMasker` (580), `SpelledNumber` | Opus-MT el↔en (INT8 ONNX, decoder KV cache), citation masking, legal glossary. Models are about 726 MB and not in git (`scripts/thesis_fetch_translation_models.sh`) |
| Verification | `LegalVerificationPolicy`, `GreekLegalAnswerService` (460), `LegalCrossReferences` | Legal checks (gates A–I; the new gate I is statute isolation), fixed Greek refusals |
| Privacy | `StrictLocalControlGuard` | Data excluded from backups; no iCloud sync, web import or Private Cloud Compute |
| Interface | `GreekLegalAssistantSheet` (860), `GreekLegalReviewCard` | The "Greek Legal AI" sheet; legal review card in an answer's details |
| Siri / Shortcuts | 3 App Intents in `RAGAppIntents` | Template routing, statute summary, legal opinion |
| Evaluation | 11 test files in `FirikiTests/Services/GreekLegal/`, `Benchmarks/Greek*` (Constitution, Labour Code, five-document library, templates, OCR set), `scripts/thesis/` | Unit tests, benchmark sets, test harness, holdout regrader |
| Records | `Docs/Thesis/` (FORK_CHANGES, EXPERIMENTS, METHODS_SUMMARY, plans) | A full log of every change |

### 2. Changes to upstream code (largest first)

- **`RAGService.swift`** (+345/−112): Greek legal mode (switched on by the share of Greek letters),
  translation on the way in and out, search limited to the law a question names, article lookup,
  buffered plain-text answers, on-device context budget, the opinion entry point.
- **`DocumentProcessor.swift`** (+273/−21) and `StructuredDocumentParser` (+68): Greek pages sent
  to PaddleOCR, the Greek text layer checked, legal chunking and translation at import, table rows
  kept, single-column pages detected.
- **`SQLiteFullTextService`** (+210): Greek keyword index that ignores accents and case and matches
  word stems.
- **`ChatScreen`** (+138/−226): capability requests routed from the chat; upstream extras removed.
- **`VerificationGateService`** / `SourceOnlyAnswerService` (+81/−57, +81/−320): the medical
  domain-isolation rules replaced by legal checks; "touchy" detection matches whole words.
- **Smaller changes:** `HybridSearchService`, `TranslationService`, `DocumentChunk` (bilingual
  fields), `QueryEnhancementService`, `LLMService`, `FoundationModelSessionFactory`.
- **Removed:** billing, plans, StoreKit, What's New screens, fastlane, the Atlas tab,
  `DomainIsolationService`, the original author's agent tooling.
- **Rebranded:** Firiki targets and bundle IDs, `firiki://` scheme, new icon.

---

## Phase 2a: Demo polish and reliability

### Confirmed issues

**1. The chat router misroutes ordinary questions.** The router's regexes
(`Firiki/Services/Legal/GreekLegalChatRouter.swift:42-50`) were run against sample prompts; 5 of
10 went to the wrong place:

| Prompt | Routed to | Should be |
|---|---|---|
| «Τι ισχύει για τη σύμβαση εργασίας για ορισμένο χρόνο;» | Template | Q&A |
| «Ποια σύμβαση καταγγέλλεται χωρίς αποζημίωση;» | Template | Q&A |
| "Can an employer change a labour contract unilaterally?" | Template | Q&A |
| "In your opinion, how many days of paternity leave…" | Opinion | Q&A |
| «Δώσε μου μια περίληψη των δικαιωμάτων της εγκύου» | Summary (then "which document?") | Q&A |

- Greek typed without accents skips the capability: «συνοψη του ν. 5278/2026» and
  «ποιο υποδειγμα συμβασης…» both fall through to plain Q&A.
- A misrouted question never reaches the Q&A path, so the user gets a contract template instead of
  an answer.

**2. Raw error text reaches the user.** The router and the assistant sheet put
`error.localizedDescription` straight into a Greek message (`GreekLegalChatRouter.swift:133`,
`GreekLegalAssistantSheet.swift:338` and `:775`).
- The summarizer and opinion writer never check whether the model is available, and don't handle
  "context window exceeded" or guardrail errors.
- A failure therefore shows something like «Σφάλμα σύνοψης: The operation couldn't be completed
  (FoundationModels…)».
- The template router already handles these cases (`LabourContractTemplateRouter.swift:118-127`);
  that pattern can be reused.

**3. Wrong progress stage during the long capabilities.** `stage = .embedding` is set at
`ChatScreen.swift:3170`; the capability branch at line 3258 returns without changing it, so a
summary or opinion (several model passes) shows the "embedding" stage the whole time. These calls
also don't check for cancellation, so Stop may not stop the work.

**4. Answer details show zero metrics.** Capability answers set `totalGenerationTime: 0`,
`tokensGenerated: 0` and `retrievalTime: 0`; the details view prints "0.000s" and "0 tokens"
(`ResponseDetailsView.swift:683`).

**5. Summaries find documents by filename only.** `matchDocument`
(`GreekLegalChatRouter.swift:95`) ignores the statute key already stored for each document. A file
named differently (for example `Α-121.pdf` in the repository root) won't match, and `"62"` matches
the first filename containing "62" anywhere.

**6. Mixed languages in answers.** The summary header is always «### Σύνοψη:», even for an English
question; English template answers contain «Εφαρμοστέες διατάξεις»; a Greek message points the user
to the 'Documents' tab in English.

### Quick wins (hours each)

1. **Router:** fold accents and case before matching; drop the bare patterns `ποια σύμβαση`,
   `σύμβαση (εργασίας) για`, `labour contract` and a bare `opinion`; require a request word
   (υπόδειγμα/πρότυπο, γνωμοδότηση/legal opinion, σύνοψε/περίληψη + a statute).
2. **Friendly errors:** map errors to fixed Greek/English messages; technical detail goes to the
   log only.
3. **Progress:** set the generating stage before running a capability.
4. **Metrics:** time capability calls; hide metric rows whose value is 0.
5. **Language:** fix the three mixed-language strings.
6. **Green suite:** pin the locale in `AnswerUsageTallyTests.testTheDetailsLine` (fails on a Mac
   set to the Greece region: "1.100" vs "1,100").
7. **Demo setup (no code):**
   - Import the library on the demo Mac the day before (the full Labour Code takes about 15
     minutes).
   - Device language English, Apple Intelligence on.
   - Check the 726 MB translation models are in the build.
   - Run in airplane mode, which also shows the privacy claim.
   - Use a fixed list of prompts, each rehearsed 3–5 times; results vary between runs (2–8 of the
     46 Labour Code dev questions change from run to run).

### Deeper fixes (days)

1. **Summary and opinion error handling:** check model availability, shrink and retry on context
   overflow, fall back on guardrail errors (as the template router does).
2. **Summary target by statute key:** match `documentStatuteKey` first, filename only as a fallback.
3. **Cancellation:** check for cancellation between the summary's map/reduce passes and the
   opinion's passes.
4. **Measure latency before the demo:** no timings exist for summaries or opinions, and nothing
   has run on a physical iPhone. Demo on the Mac unless the iPhone has been measured.
5. **Optional demo mode:** hide inherited upstream screens (telemetry HUD, 3D embedding view,
   database dashboard) that don't fit the legal story. Not yet checked how visible these are.
6. **Low priority:** the `try!` regexes in `GreekLegalEntityMasker` and `GreekLegalIngestion` use
   fixed patterns; a test that builds each once would rule out a crash.

---

## Phase 2b: Test-driven development

**Current state.**
- 186 test files: 170 XCTest, 12 Swift Testing (128 `@Test`). The Greek suites are Swift Testing.
- No CI (`.github/` was removed).
- UI tests cover only Shortcuts and accessibility.
- The iOS Simulator has no Apple Intelligence: model-backed tests must run on the Mac.

**Framework.**
- **Swift Testing** for all new logic: table-driven `@Test(arguments:)`, suite names that work
  with `-only-testing:`.
- **XCUITest** for one smoke flow on "My Mac".
- **Pre-demo gate:** `scripts/thesis_run_tests.sh` plus a short pre-push hook or `make demo-check`.
- **Testability seam:** the summarizer, template router and opinion writer create
  `LanguageModelSession` themselves, so their error paths can't be tested. Inject a small
  text-generator protocol and use a fake in tests (the `LLMService` protocol and the test
  harness's `GreekEvalOnDeviceModel` show the pattern).

**Flows to cover first.**

1. **Chat intent routing** (pure functions, no model): a table of about 40 prompts in Greek,
   unaccented Greek and English, including the 5 misroutes above. They fail today; fixing the
   regexes turns them green. Best value for effort.
2. **Capability error paths** (fake model): model unavailable, context overflow and guardrail
   errors give a fixed Greek message, never raw error text; an empty library gives the import hint;
   a missing document gives the document list.
3. **Greek Q&A end to end** with a fake model over a small fixture library: a Greek question gets
   a Greek answer with an article citation; a question about a law not in the library gets the
   fixed Greek refusal; a number not in the passages is removed by gate C.
4. **Import of the demo documents** (real ONNX, no model): for each of the 5 library PDFs, the
   statute key is found, the article count is above a minimum, Greek and English text are both
   present; plus a check that the OCR and translation models are in the bundle.
5. **Template routing and summary matching:** keyword fallback over `routing_v1.jsonl`; summary
   lookup by statute key once deeper fix 2 is in.

**Plus a manual-trigger smoke test:** on "My Mac" with the library pre-imported, an XCUITest asks
the 4 demo prompts and checks that each answer appears within a time limit, contains no
"Σφάλμα"/"Error" text, and has a citation. Run it the morning of the demo.

---

## Status of the quick wins

The plan is in `Docs/Thesis/plans/demo-quick-wins.md`. Tick items here as they land.

- [x] 1. Router: accent/case folding and narrower patterns, plus a second tier for described
  hiring arrangements (template requests recognised from the chat: 0 → 38 of 40 dev, 13 of 20
  test; EXPERIMENTS E13)
- [x] 2. Friendly error messages (and refused opinions shown as a notice in the sheet)
- [x] 3. Correct progress stage for capabilities
- [x] 4. Real timing / no zero metrics
- [x] 5. Language consistency of capability answers
- [x] 6. Locale-independent `AnswerUsageTallyTests`
- [ ] 7. Demo setup checklist done on the demo Mac
- [ ] Check items 1–5 in the Mac app with Apple Intelligence (the simulator can't run the model)

## Status of the deeper fixes

- [ ] 1. Summary and opinion error handling (retry on context overflow, guardrail fallback)
- [x] 2. Summary target by statute key (`Docs/Thesis/plans/summary-by-statute-key.md`)
- [ ] 3. Cancellation between the summary's and opinion's passes
- [ ] 4. Latency of a summary and an opinion measured on the Mac
- [ ] 5. Optional demo mode
- [x] 6. `try!` patterns: already built by the existing masker and title-page tests; no change
