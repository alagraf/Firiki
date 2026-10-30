# Remaining work to the finished PoC (plan for Claude Code or Antigravity)

Written 2026-10-29 21:40 by Claude Code so that another agent can continue without the earlier
conversation. Read `AGENTS.md` and `Docs/Thesis/plans/HANDOFF.md` ("Rules that are easy to break")
first. The owner has given standing permission to change code and to commit and push the thesis
branch; this plan counts as approved. Check `git status` and `git log --oneline -10` before
starting: whatever is already committed below is done.

Order (the owner's): steps 1–3, then the capabilities in the owner's priority (2026-10-29 21:50):
five-document Q&A (4), template routing (5), then summary (6) and legal opinion (7), **one at a time: implement, test, commit,
and only then start the next**. Each step ends with its records: `Docs/Thesis/FORK_CHANGES.md`
(next free number; 2.11.22 is the last used at the time of writing), the 5.7 section of
`CHANGELOG.md`, `Docs/Thesis/METHODS_SUMMARY.md` (results row, revision history), the log in
`HANDOFF.md`, and the item marked done in `greek-legaltech-progress.md`.

## How to run things

```bash
# Is a Simulator run going? Must print nothing before you start one.
pgrep -lf thesis_run_tests | grep "^[0-9]* /bin/bash\|^[0-9]* bash"

# Greek unit suites (about 5 min). Pass: "Test run with N tests … passed" and "Executed N tests, with 0 failures".
bash scripts/thesis_run_tests.sh /private/tmp/oi-logs/greekunit.log \
  $(for s in GreekProcessingLogTests StrictLocalControlGuardTests GreekLegalEntityMaskerTests BilingualChunkStorageTests \
    GreekOCRTests GreekTranslationRetrievalTests GreekLegalVerificationTests GreekLegalReviewDetailsTests GreekNameQuestionTests \
    ReflowTests FragmentTranslationTests ArticleLookupTests GreekKeywordArmTests LegalGlossaryTests GreekLegalStructureChunkerTests \
    NumericSanityGateTests ClaimCheckTests ClaimCoverageFallbackTests HeadingClaimTests SemanticGroundingClaimTests; \
    do printf -- "-only-testing:OpenIntelligenceTests/%s " $s; done)

# Labour Code dev split (46 cases, about 25 min; REIMPORT=1 after any change to import, chunking or translation).
TEST_RUNNER_OI_GREEK_EVAL=1 TEST_RUNNER_OI_GREEK_EVAL_SET=GreekLabourCode TEST_RUNNER_OI_GREEK_EVAL_CORPUS=excerpt \
TEST_RUNNER_OI_GREEK_EVAL_SPLIT=dev TEST_RUNNER_OI_GREEK_EVAL_REIMPORT=1 OI_TEST_TIMEOUT_SECONDS=7200 \
  bash scripts/thesis_run_tests.sh /private/tmp/oi-logs/labourN.log -only-testing:OpenIntelligenceTests/GreekConstitutionEvaluationTests
grep -a "\[GreekEval\] \(imported\|summary\|answer pass\)" /private/tmp/oi-logs/labourN.log | cut -c1-250
```

- If the log says "failed to launch" or "Test runner hung", run the same command once more.
- Every run rebuilds the app: **don't edit source files while a run is going**, or the run measures a
  half-made change.
- Run-to-run noise is 2–8 of 46 dev cases. Run twice before claiming a gain of 1–3 cases.
- The Simulator writes answers with Apple Intelligence through the host Mac (the log says "model
  availability: available"). Speed and memory still need the device check (step 8).
- New Swift files need no project-file edit: the project uses synchronized folders (objectVersion 77).
  Never stage `project.pbxproj`.

## 1. Wrong-case figures, dev cases 34 and 46 (done: FORK_CHANGES 2.11.23, 2.11.24)

Committed with the records below (first written uncommitted):

- **Case 34, table rows mixed and mistranslated** (the severance-pay table: "more than 12 months"
  rows merged into one sentence).
  - `GreekLegalStructureChunker.swift`: `isTableCell`, `tableLineIndices` (runs of ≥4 short lines,
    at least half with a digit, extended to neighbouring lines that start with a number);
    `joined` keeps table rows on their own lines; `sentenceEnd` also cuts at newlines; `split`
    keeps each sentence's separator.
  - `LocalNeuralTranslator.swift` `reflow`: doesn't join table lines.
  - Tests: `GreekLegalStructureChunkerTests.tableRowsKeepTheirLines`,
    `FragmentTranslationTests.tableRowsAreTranslatedRowByRow`. These passed (74 Swift Testing
    tests, 67 XCTest, 0 failures).
- **Case 46, a right answer refused by gate C.** The model ended a correct answer about harassment
  with an off-topic bullet holding a figure ("Six (6) months after childbirth … the working father is
  protected from dismissal"), and gate C refused the whole answer.
  - `GreekLegalAnswerService.swift`: `droppingOffTopicFigures(from:query:)`. In `review`, when gate C
    is the only critical failure, it drops sentences that state a figure and share no topic word
    with the question, then verifies the rest again and uses it only if every gate passes. A figure
    on the question's own topic still means a refusal.
  - Test: `GreekLegalVerificationTests.offTopicFigureIsDroppedButAnOnTopicOneStillRefuses`. **Not run
    yet.**
- **Evaluation running at the time of writing:**
  - `labour13`: table fix only, reimport.
  - `labour14`: built after the case-46 edit, so it has both fixes.
  - Logs are `/private/tmp/oi-logs/labour13.log` and `labour14.log`. The baseline before the fixes was 35 of 46 (`labour12`).

To finish:

1. Run the Greek unit suites.
2. Run the dev split once more (`labour15`), so there are two runs with both fixes.
3. Check cases 34 and 46 in the logs.
4. Accept the fixes if both runs are ≥ 35 and neither case got worse; otherwise find out why first.
5. Commit as two FORK_CHANGES sections (table rows; gate C off-topic figures).

## 2. A question naming a law the library doesn't hold (Labour test case 69) (done: 2.11.25)

**Done 2026-10-30 (FORK_CHANGES 2.11.25):** Constitution 8/10, Labour dev 38/46; test case 69 is
measured with the next test-split run.

**Problem.** "What does Article 16 of the Constitution say …?" asked of a Labour Code library
retrieves Labour Code Article 16 and answers from it. Gate I (`statutoryIsolationViolation`) only
knows `LAW:`/`PD:` keys, and the Constitution has none. A check for "a passage mentions the
Constitution" is wrong, because most of the Constitution's own articles never name it. That would
refuse the Constitution evaluation set. The library has to know which statute each **document** is.

Case 69 is from the test split, so build the general rule, prove it with unit tests and the dev
split, and say in FORK_CHANGES where the case came from.

**Design.**

- `GreekLegalEntityMasker`:
  - A key for the Constitution (`CONST`). "Σύνταγμα/Συντάγματος" and English "the
    Constitution", "Article N of the Constitution" (capital C, so a union's "constitution" doesn't
    count) give `CONST`.
  - Optionally the major codes, all from one table: Civil Code `CODE:CIVIL`, Penal Code
    `CODE:PENAL`, Code of Civil Procedure `CODE:CIVPROC`, Code of Criminal Procedure `CODE:CRIMPROC`,
    "Labour Code / Κώδικας Εργατικού Δικαίου" `PD:62/2025`.
- The document's own statute, read once at import from its first passages (the Gazette title page):
  - "ΣΥΝΤΑΓΜΑ" → `CONST`;
  - "ΠΡΟΕΔΡΙΚΟ ΔΙΑΤΑΓΜΑ ΥΠ' ΑΡΙΘΜ. 62" plus the Gazette year → `PD:62/2025`;
  - "ΝΟΜΟΣ ΥΠ' ΑΡΙΘΜ. 5239" → `LAW:5239/2025`;
  - "ΥΠΟΥΡΓΙΚΗ ΑΠΟΦΑΣΗ"/"Αριθμ. 8934" → `YA:8934/2026`, or none.

  Put it in a new `GreekLegalIngestion.documentStatuteKey(firstTexts:)` and add `documentStatuteKey: String?` to
  `LegalChunkMetadata` (`Core/Models/DocumentChunk.swift`). Persist it as a new nullable column in
  `chunk_legal` (`SQLiteFullTextService`: table creation near line 321 plus an
  `ALTER TABLE … ADD COLUMN` for existing databases, `storeLegalChunkMetadata`,
  `legalChunkMetadata(for:)`).
- `GreekLegalAnswerFinalizer.preGenerationAbstentionReason`: refuse when all of these hold:
  - the English question names a statute S;
  - at least one retrieved passage has a known `documentStatuteKey`;
  - no retrieved passage's document is S;
  - no passage cites S.

  The reason is "the question is about S, which is not in the library". Passages from older imports
  (nil key) never cause a refusal.

**Tests.**

- Unit tests:
  - title pages of the five library PDFs and the Constitution give the right key (use short Greek
    strings copied from the first page, not the PDFs);
  - "Article 16 of the Constitution" with Labour Code passages is refused, and with Constitution
    passages is not;
  - "Article 16 of Law 5239/2025" in a five-document library is not refused when that law's
    document is retrieved;
  - a union "constitution" is not refused.
- Evaluations: Constitution set (10 cases, `TEST_RUNNER_OI_GREEK_EVAL_SET` unset, reimport) must stay
  ≥ 8 of 10; Labour dev twice, no drop.

## 3. Refusal rate over the full Labour Code (done: 2.11.30)

**Done 2026-10-30:** full Code, test split, once: 15 of 23; refused 3 of 3 (case 69 included); 1 wrong
refusal of 20.

Not measured since FORK_CHANGES 2.11.14. Run the Labour test split on the full Code once
(`TEST_RUNNER_OI_GREEK_EVAL_CORPUS=full TEST_RUNNER_OI_GREEK_EVAL_SPLIT=test`, reimport, about 15 min
of import plus answers).

- Record: answer pass, refusal cases (`shouldAbstain`) refused, and wrong refusals.
- Results only. Don't tune on the test split.
- If wrong refusals are common, look for the cause on the dev split with the full corpus (`SPLIT=dev CORPUS=full`).

## 4. Capability 1 (owner priority 1): Q&A over one document, then five (done: 2.11.27)

**Done 2026-10-30:** dev 14 of 24 (13 at the start), test 6 of 12 once. Statute scope, front
matter left out, no extractive override in Greek mode, and two import fixes (single-column pages;
word positions from the raw page text, which Law 5278 needed for 8 of its 16 article headings).

**Status 2026-10-29 22:00:**
- Written: the question set `Benchmarks/GreekLabourLibrary/library_qa_v1.jsonl` (36 questions, 24 dev
  and 12 test; the README there lists them).
- Written, not yet committed or run: the harness change in `GreekConstitutionEvaluationTests.swift`
  (a corpus is a list of PDFs; set `GreekLabourLibrary`, corpus `library`; cases with `document`
  and `alsoDocument`; "right documents retrieved").
- To run it: `TEST_RUNNER_OI_GREEK_EVAL_SET=GreekLabourLibrary TEST_RUNNER_OI_GREEK_EVAL_SPLIT=dev
  TEST_RUNNER_OI_GREEK_EVAL_REIMPORT=1`. The first import of the five PDFs takes about 25–40 min.

- **Library:** `Benchmarks/GreekLabourLibrary/README.md`, five Greek labour-law PDFs (Labour Code
  plus Ν. 5239/2025, Ν. 5278/2026, Ν. 5316/2026, Υ.Α. 8934/2026). One document is already measured
  by the Labour dev split; record it as the single-document result.
- **Question set:** `Benchmarks/GreekLabourLibrary/library_qa_v1.jsonl`, same format as
  `Benchmarks/GreekLabourCode/labour_qa_v1.jsonl` (`id, level, question, expectedAnswer, keyFacts,
  article, split, shouldAbstain`).
  - Add a `document` field (the file name the answer must come from).
  - About 40 questions: 8 per document, a few that need two documents (an article of the Code as amended by Ν. 5239/2025),
    and 5 that must be refused. Split them 2:1 into dev and test.
  - Write the questions in Greek from the statutes' own text, never from the EU holdout.
  - `keyFacts` are regexes over the folded answer, as in the existing set.
- **Harness:**
  - `GreekEvalSet` (`OpenIntelligenceTests/Services/GreekLegal/GreekConstitutionEvaluationTests.swift`,
    near line 101) takes one PDF per corpus today. Let a corpus be a list of PDFs (`"library": [five files]`)
    imported into one library, and add a `"GreekLabourLibrary"` set.
  - Add a check that the answer cites the expected document: the source chip, or `retrievedChunks`
    containing a passage of that document.
- **Scaling** (tune on the dev split only):
  - retrieval depth and per-document balance, so one long document (the 260-page Code) doesn't crowd
    out a 4-page decision;
  - the context budget for the model (on-device context is small: keep passages short, put the best
    passage of each document first);
  - the document name in each passage's prompt label, so the model can say which law it cites.
- **Done when:** the dev split is measured twice and the test split once; FORK_CHANGES and
  METHODS_SUMMARY record one-document and five-document numbers.

## 5. Capability 4 (owner priority 2): Routing to 10 labour contract templates (done: 2.11.26)

**Done 2026-10-30 (FORK_CHANGES 2.11.26):** dev 43/44, test 20/22 (keywords alone 26/44, 8/22).
The router is not yet reachable from the chat UI (a "which contract do I need" request in the app);
that and filling a template's `{{placeholders}}` are possible follow-ups.

- **Templates: drafted (2026-10-29).** The 10 Greek templates are in
  `Benchmarks/LabourContractTemplates/contracts/`, with a README listing each one's articles. Each is
  marked as a PoC draft and not legal advice. The set is grounded in the Code: domestic worker and
  mutual termination were dropped, temporary agency work and urgent-needs hiring added.

  Each file is Markdown with front matter (id, titles, articles, Greek and English keywords and
  description), then the contract with `{{placeholders}}`. When the router is built, move them to
  `OpenIntelligence/Resources/LabourContractTemplates/` and check that they're in the app bundle.
- **Router:**
  - `LabourContractTemplateRouter`: score a Greek or English prompt against each template's
    description and keywords. Use embeddings with the app's sentence-embedding model plus keyword
    rules.
  - Return the best template with a confidence, or "none" under a threshold.
  - An optional Apple Intelligence tie-break between the top two.
- **Test:**
  - `Benchmarks/LabourContractTemplates/routing_v1.jsonl` (written 2026-10-29): 66 labelled prompts
    (6 per template, Greek and English, plus 6 that fit none), 44 dev and 22 test.
  - Measure accuracy and a confusion matrix.
  - Unit tests run the router on the dev prompts (no Simulator model needed if embeddings run in
    tests).

## 6. Capability 2: Summary of one legal document (done: 2.11.28)

**Done 2026-10-30:** Law 5278 dev 5 of 6 provisions, 3 of 3 articles; decision 8934 test 0 of 5
held out (no articles), 4 of 5 after summarizing by parts (not held out).
`GreekLegalDocumentSummarizer.swift`, `GreekLegalSummaryTests.swift`, `summary_v1.jsonl`.

- **Behaviour:** a "summarise this document" request in Greek legal mode produces a complete Greek
  summary of one statute:
  - its structure (parts or chapters);
  - its main rules;
  - its figures and deadlines;
  - article references.
- **Method:**
  - Map–reduce over the document's article passages:
    - summarise groups of articles in English, with each article number kept;
    - then combine the group summaries;
    - then translate with the existing English→Greek path (citations preserved).
  - Check figures with gate C and articles with gate F against the document's own passages, and drop
    any unsupported sentence rather than refusing the whole summary.
  - Reuse `DocumentSummaryService` (`Services/Document/Analysis/DocumentSummaryService.swift`, actor,
    Apple Intelligence) where it fits; it makes short RAPTOR summaries today, so the legal summary is
    probably a new method or service.
  - Intent: recognise summary requests (Greek and English) where `classifyAnswerIntent` is called.
- **Test:**
  - For two documents (Ν. 5278/2026, 14 pages, and Υ.Α. 8934/2026, 4 pages; the Code is too long for
    a first version), write a checklist of key provisions (regexes, as `keyFacts`).
  - Report coverage, unsupported figures (gate C) and articles not in the document (gate F).
  - Unit tests for the map–reduce grouping and the sentence dropping with stubbed model calls.

## 7. Capability 3: Legal opinion from five documents (done: 2.11.29)

**Done 2026-10-30:** dev citations 10 of 12, key facts 11 of 20, refused 0 of 6; test citations
3 of 8, key facts 7 of 10, refused 0 of 4 (once). `GreekLegalOpinionWriter.swift`,
`GreekLegalOpinionTests.swift`, `opinion_qa_v1.jsonl`. Opt-in run: `TEST_RUNNER_OI_GREEK_OPINION=1`,
`_SPLIT=dev|test` (reads the five-document library, so import it first).

- **Behaviour:** a question asking for an opinion produces a structured Greek opinion with these
  sections:
  - question;
  - applicable law (which of the five documents and articles);
  - what each says;
  - how they combine (later law amends earlier; special over general);
  - conclusion;
  - a PoC disclaimer.

  Every claim is cited to document and article.
- **Method:**
  - Retrieve per document: the top passages of each of the five, not top-k overall.
  - Draft one section at a time, so each prompt fits the on-device context.
  - Verify each section with gates A–I.
  - Drop unsupported claims, and refuse only if the conclusion has no support.
- **Test:**
  - `Benchmarks/GreekLabourLibrary/opinion_qa_v1.jsonl`: about 10 questions, each with the
    documents and articles the opinion must cite, plus key facts; split into dev and test.
  - Measure citation recall, wrong citations, and key facts.

## 8. Device check (needs the owner)

On an iPhone or the M3 Mac:

- import time of the excerpt and of the full Code;
- memory with one translator direction loaded;
- answer quality on a few dev questions;
- whether the refusal thresholds hold.

The owner runs the app and reads the Processing Log; give them a checklist.

## 9. EU holdout (last)

Run the 16 EU questions once, as a measurement only (AGENTS.md step 5), with
`EUHoldoutEvaluationTests`. Record the numbers in METHODS_SUMMARY. Change nothing because of them.
