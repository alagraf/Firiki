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
   (υπόδειγμα/πρότυπο, γνωμοδότηση/legal opinion, συνόψισε/περίληψη + a statute).
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
- [x] Check items 1–5 in the Mac app with Apple Intelligence (14 Nov rehearsal; the friendly error messages were not triggered)

## Status of the deeper fixes

- [x] 1. Summary and opinion error handling (retry on context overflow, guardrail fallback) — E16
- [x] 2. Summary target by statute key (`Docs/Thesis/plans/summary-by-statute-key.md`)
- [x] 3. Cancellation between the summary's and opinion's passes — E16 (Stop idle in 0.3 s on the Mac)
- [x] 4. Latency of a summary and an opinion measured on the Mac — Q&A 26 s, template 2.5–20 s, summary of the whole Law 5278 83 s, opinion about 40–90 s (14 Nov rehearsal); iPhone not measured
- [x] 5. Optional demo mode (`Docs/Thesis/plans/demo-mode.md`): audit done (`Visualizations/` has no live call sites; `TelemetryDashboardView` is inside Developer & Diagnostics; `Database` tab and `showTechnicalDetails` on installs with saved `llmTemperature` were visible); added `Demo Mode` defaulting to `true` (`Settings -> System`) hiding `Database`, `Developer & Diagnostics`, HUD overlays, and telemetry/metrics chips while keeping Settings -> Appearance switches intact for `AccessibilityAuditTests`
- [x] 6. `try!` patterns: already built by the existing masker and title-page tests; no change

## Mac rehearsal, 14 Nov 2026 (driven by Claude Code, M3 MacBook Pro, Apple Intelligence)

Library at the time: Labour Code (`A-121.pdf`, π.δ. 62/2025), lecture notes
(`ΑΤΟΜΙΚΟ ΕΡΓΑΤΙΚΟ ΔΙΚΑΙΟ.pdf`), and an excerpt of Law 5278/2026
(`demo/poc_pdfs/n_5278_2026_excerpt.pdf`, 25 passages). Laws 5239/2025, 5316/2026 and decision
8934/2026 were not imported. App built from `bbbaed29`.

| Prompt | Time | Result |
|---|---|---|
| «Πόσες ημέρες άδεια πατρότητας δικαιούται ο εργαζόμενος;» | 26.2 s (details) | 14 working days, paid; Verified |
| «Θέλω γνωμοδότηση: ο εργοδότης ζητά τέσσερις ώρες υπερωρία την ημέρα. Επιτρέπεται;» | under 45 s | **Wrong conclusion**: "4 hours a day not allowed". The expected answer (opinion set case 1) comes from Law 5239/2025 art. 7, not in the library |
| «Ποιο υπόδειγμα σύμβασης ταιριάζει για τηλεργασία;» | under 20 s | Telework template, reason, π.δ. 62/2025 art. 73, 130–134 |
| «Σύνοψε το ν. 5278/2026» | under 30 s | Heading «Σύνοψη: ν. 5278/2026»; only Articles 7 and 8, because only the excerpt is imported |

The earlier request «σύνοψη του ν. 5278/2026», made before the excerpt was imported, got "not in the library" with the list of
documents, as designed.

Issues seen:
1. The demo library is incomplete: import the five documents of `Benchmarks/GreekLabourLibrary/`
   (full Law 5278, not the excerpt) before the demo; the opinion prompt depends on Law 5239/2025.
2. The opinion body cuts a file name with spaces: «ΑΤΟΜΙΚΟ ΕΡΓΑΤΙΚΟ ΔΙΚΑΙΟ.pdf» shows as
   «ΔΙΚΑΙΟ.pdf».
3. The template's signature block shows raw Markdown table pipes (`| Ο εργοδότης |`, `|---|`).
4. While a capability runs, the status bar keeps the previous answer's "Confidence: high · 73%
   P(correct)", and the header keeps the previous answer's time (26.2 s).

### After importing the library and fixing the display bugs (same day)

The four documents of `Benchmarks/GreekLabourLibrary/` were imported in about 16 minutes (Law
5239: 1,381 passages; Law 5278: 202; Law 5316: 510; decision 8934: 36). Library: 7 documents
(the excerpt and the lecture notes stay). App rebuilt with the display fixes (FORK_CHANGES 14 Nov
2026, fourth entry).

| Prompt | Result |
|---|---|
| Overtime opinion | 1–1.5 min. Now uses Law 5239/2025 art. 7 and says it amended art. 194; the notes' file name is whole. **The conclusion is still wrong**: its Law 5239 section speaks of the 45/48-hour weekly thresholds, not the 4-hour daily limit, and the lecture notes add more statements about limits. In the evaluation (five documents, no notes, the longer wording of case 1) the same case had 3 of 4 key facts |
| Telework template | 2.5 s; the signatures are two plain lines |
| «Συνόψισε το ν. 5278/2026» | Still Articles 7 and 8 only: the excerpt also names Law 5278/2026 on its title page and was imported first, so the lookup picks it |

Display bugs 1–3: fixed and seen fixed in the app.

Open for the demo:
1. ~~The summary picks the excerpt~~: fixed the same day, the document with more passages is
   taken. «Συνόψισε το ν. 5278/2026» now summarises Articles 3–13 of the whole law in 1 min 23 s.
   Cosmetic: an article's numbered paragraphs show as list badges (a lone "4" under Article 8).
2. The overtime opinion's conclusion: rehearse with the library of the evaluation (the five
   documents only) and the evaluation's wording of case 1, or pick a demo opinion that the
   evaluation got right.

### Why the overtime opinion concludes "not allowed" (diagnosis, 14 Nov 2026)

Run in the Mac app (7-document library, build `7e7713c6`) with the app's log saved
(`[LegalOpinion] Sources` / `Passage` lines). Translated question: "I want an opinion: the
employer requests four hours of overtime per day. May I?"

Sources kept (3 passages each):
- Labour Code: Articles **192 and 191** (work on the sixth day: "may not exceed eight hours; on
  this day overwork and overtime are not allowed"), score 0.57. Article 194 (overtime) is not
  retrieved.
- Law 5239/2025: Article 7, passages #108 (heading; the quoted new text is lost as unrestored
  placeholders `_LEX_007__`, `_LEX_008___…`), #109 (the change only: "three (3)" replaced by
  "four (4)") and #110 (new par. 2: over 45 hours a week, 48 in a six-day system; right to refuse).
- Lecture notes: weekly overwork limits (41st–48th hour), overwork paid without a surcharge.

The deciding text is the new par. 3 of Article 194 at the end of Law 5239 Article 7: «έως τέσσερις
(4) ώρες ημερησίως και μέχρι … εκατόν πενήντα (150) ωρών ετησίως … σαράντα τοις εκατό (40%)». It
is not among the law's 3 passages, and the Code's own Article 194 isn't either, so the "three →
four" change has no text to apply to. The model reads only "no overtime on the sixth day" and the
weekly thresholds, and concludes "not allowed".

Causes, in order of effect:
1. Only the best 3 passages of the amending law are kept; the amending article's last paragraph,
   which states the amended text in full, is left out.
2. The Code's passages are about a different rule (sixth-day work) that says "no overtime".
3. The lecture notes add more limits.
4. "Επιτρέπεται;" is translated "May I?".
5. Separate import defect: Law 5239 passage #108 keeps translation placeholders in its English
   text.

The evaluation's case 1 (dev) asks the longer question («…υπάλληλο πενθήμερης εργασίας… πώς
αμείβεται και μπορεί ο εργαζόμενος να αρνηθεί;») over the five laws only, and got 3 of 4 key facts
on 30 Oct (run `opinion6`).

**Whole amending article (EXPERIMENTS E14, same day):** implemented and measured on the dev set
(key facts 11 → 13 of 20, citations 10 → 9 of 12). In case 1 and in the Mac app the model now
writes the four-hours-a-day sentence but cites it as "Article 6" (the passage's `[6]` number in the
prompt), so the article check drops it and the conclusion is still "not allowed". Not committed.

**Passages not numbered (E14, same day):** dev key facts 15 of 20 (11 before), citations 10 of 12,
nothing dropped. In the Mac app the evaluation's wording of the overtime question («Ο εργοδότης
ζητά από υπάλληλο πενθήμερης εργασίας να κάνει τέσσερις ώρες υπερωρία την ημέρα. Επιτρέπεται, πώς
αμείβεται και μπορεί ο εργαζόμενος να αρνηθεί; Θέλω γνωμοδότηση.») gets the right conclusion; the
short README prompt still concludes "not allowed" (the Code's sixth-day Article 191 is retrieved).
For the demo, use the longer wording. Its Greek still has a leftover placeholder («__ΕΧΝ.») and one
wrong figure ("186 hours", from "Articles 169 to 186").
README's opinion example changed to the longer wording (same day).

**Placeholders repaired (E15, same day):** stored passages are repaired when read (450 of 8,022 →
0 in the Simulator), no re-import needed. The overtime opinion in the Mac app has no «__ΕΧΝ.» or
"186 hours" any more. Library Q&A dev 15 of 24; opinion dev 13 of 20 key facts; opinion test
(once) 4 of 8 citations, 8 of 10 key facts. Still open: the short overtime question (sixth-day
Articles 191–192); the demo uses the longer wording.
