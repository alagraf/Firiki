# Plan: CEO demo quick wins

Status: **implemented 14 Nov 2026** (owner approved: one commit; the «μαθητεία» test may change;
"as many template requests as possible"). That last answer added a second tier to item 1: a
described hiring arrangement (`possibleContractRouting`) runs the template router and falls back
to Q&A when no template fits, bringing the routing dev split to 38 of 40 (EXPERIMENTS E13). Record:
FORK_CHANGES "14 Nov 2026 (second entry)".
Written 14 Nov 2026 by Claude Code, at `main` = `07800929`. Background: `POC_PROGRESS.md`
(repository root), Phase 2a.

## Goal

Stop the chat from sending ordinary questions to the wrong capability, and make sure a summary,
opinion or template request never shows raw error text, a wrong progress stage, zero metrics or
mixed-language wording during the demo.

## Scope

- **Not touched:** `project.pbxproj`, any `*.entitlements` or `Info.plist`. The project uses
  file-system-synchronised groups, so no project-file edit is needed, and the plan adds no new
  source files anyway.
- **No change to:** retrieval, answering, gates, translation or any measured method other than
  chat intent recognition.
- **Holdout:** not read and not run. Router rules were designed only against the **dev** splits
  (routing set, Labour Code, library, opinion sets).

## Code read (line ranges at `07800929`)

| File | Lines | What |
|---|---|---|
| `Firiki/Services/Legal/GreekLegalChatRouter.swift` | 1–311 (all) | Intent regexes 42–50, `detectIntent` 52–76, `extractDocumentTarget` 79–93, `matchDocument` 95–114, `handleChatQuery` 118–155, the three executors 159–310 |
| `Firiki/Features/Chat/Conversation/ChatScreen.swift` | 3148–3170, 3200–3290, 3371–3381 | Stage set to `.embedding` at 3170; capability branch 3258–3284; normal `.generating` transition 3371–3381 |
| `Firiki/Features/Chat/Response/GreekLegalAssistantSheet.swift` | 135, 200–345, 552–565, 745–780 | Opinion tab (no refusal display, raw error at 338); template tab; summary tab (raw error at 775) |
| `Firiki/Features/Chat/Response/ResponseDetailsView.swift` | 345–395, 600–612, 672–692, 743–750 | Summary card time/tokens; performance section; metrics grid; `appleUsageText` |
| `Firiki/Services/Legal/GreekLegalOpinionWriter.swift` | 46–56, 490–500 | `Opinion` struct; the two English refusal reasons |
| `Firiki/Services/Legal/LabourContractTemplateRouter.swift` | 111–130 | Availability check and guardrail fallback (the pattern to copy) |
| `Firiki/Services/Storage/SQLiteFullTextService.swift` | 1114–1118 | `greekSearchFold` (accents and case removed, ς→σ) |
| `Firiki/Core/Models/RAGQuery.swift` | ~80 | `ResponseMetadata.totalGenerationTime` is a `let` |
| `FirikiTests/Services/GreekLegal/GreekLegalChatRouterTests.swift` | 18–151 | Existing intent tests |
| `FirikiTests/Services/LLM/AnswerUsageTallyTests.swift` | 60–63 | Locale-dependent assertion |
| FoundationModels SDK interface (iOS 27.0) | `GenerationError` | Cases: `exceededContextWindowSize`, `assetsUnavailable`, `guardrailViolation`, `unsupportedGuide`, `unsupportedLanguageOrLocale`, `decodingFailure`, `rateLimited`, `concurrentRequests`, `refusal` |

## Evidence for item 1 (prototype, dev splits only)

The current regexes and the proposed rules were run in a Python prototype (same patterns, folded
text) over the dev splits:

| Set (dev) | Want | Current | Proposed |
|---|---|---|---|
| Template routing set, 44 prompts (≈40 template requests + ≈4 "none" plain questions) | Template | **0** | **17** |
| Labour Code questions, 46 | Q&A | 46 | 46 |
| Library questions, 24 | Q&A | 24 | 24 |
| Opinion questions, 6 (plain questions) | Q&A or opinion | 6 | 6 |
| Misroutes found in the audit + 2 yes/no legal questions, 7 | Q&A | 1 | **7** |
| Existing unit-test prompts, 29 | as labelled | 27 | 28 |

So today **no naturally worded template request reaches the template router from the chat**. The
43/44 in the README measures the router once it is called (sheet, Siri, tests), not in-chat
recognition. The proposed rules fix the misroutes without losing a Q&A question. They catch about
4 in 10 natural template requests; the rest need a model-based intent check (a deeper fix, not in
this plan).

## Changes

### 1. Router: accent/case folding and narrower patterns (`GreekLegalChatRouter.swift`)

- `detectIntent`: match on `SQLiteFullTextService.greekSearchFold(query)`, and rewrite the patterns
  without accents and with σ only.
- **Template** when any of the following holds:
  - a template noun (`υποδειγμα*`, `προτυπ*`, `template(s)`) within three words of a contract noun
    (`συμβασ*`, `συμφωνητικ*`, `contract(s)`, `agreement(s)`), in either order;
  - `ποιο υποδειγμα|προτυπο`, or `which|what … contract|template … use|fit|suit`, or `which|what
    contract`;
  - a prompt that starts with `contract|agreement|συμβαση|συμφωνητικο` + `for|για`;
  - `τι|ποια|ποιο` + `συμβαση|συμφωνητικο` + `χρειαζομαι|κανουμε|να κανω|υπογραφουμε|να υπογραψω`;
  - a contract noun + a request verb (`χρειαζομαι`, `χρειαζομαστε`, `θελω`, `να χρησιμοποιησ*`,
    `ταιριαζ*`, `ετοιμασ*`, `συνταξ*`, `φτιαξ*`, `καταρτισ*`, `υπογραφουμε`, `υπογραψουμε`,
    `should I/we use`, `draft*`, `prepare*`, `fit(s)`, `suit(s)`, `sign`, `cover(s)`), unless the
    prompt opens as a yes/no legal question (`do`, `does`, `is`, `are`, `can`, `must`,
    `χρειαζεται`, `πρεπει`, `μπορει`).
- **Removed template patterns:** `σύμβαση (εργασίας) για`, `ποια σύμβαση`, `labour contract`.
- **Opinion:** `γνωμοδοτ*`, `νομικη συμβουλη|αποψη|γνωμη`, `legal opinion`, `formal memo*`. The bare
  `opinion` is removed ("In your opinion…" stays a question).
- **Summary:** a summary word (`συνοψ*`, `περιληψ*`, `περιληπτ*`, `summar*`, `digest`) **and**
  either a statute target or a document word (`εγγραφ*`, `νομο*`, `διαταγμ*`, `αποφασ*`,
  `κειμεν*`, `διαταξ*`, `law`, `decree`, `decision`, `document`, `statute`, `act`, or `NNNN/YYYY`).
- `extractDocumentTarget`: run the same patterns on folded text, so «συνοψη του ν. 5278/2026» and
  «ΣΥΝΟΨΗ ΤΟΥ Ν. 5278/2026» find `5278/2026`.
- **Tests** (`GreekLegalChatRouterTests.swift`):
  - table-driven `@Test(arguments:)` cases for the 7 misroutes (→ Q&A);
  - unaccented and all-caps capability requests (→ the capability);
  - a dev-split test that loads `routing_v1.jsonl` (via `GreekEvalCase.repository`, as
    `LabourContractTemplateRouterTests` does) and checks that at least 17 template-labelled dev
    prompts are recognised;
  - a test that every Labour Code and library **dev** question stays Q&A.
- **Existing expectation to change** (see open question 1): «Ποια σύμβαση εργασίας προβλέπεται
  για μαθητεία;» would become Q&A.

### 2. Friendly error and refusal messages

- `GreekLegalChatRouter.swift`: add `static func failureMessage(for error: Error, greek: Bool)
  -> String`. Fixed Greek and English text for:
  - context window exceeded («Το έγγραφο είναι πολύ μεγάλο για μία σύνοψη στη συσκευή…»);
  - guardrail violation or refusal;
  - assets unavailable / model not ready;
  - rate limited / concurrent requests («Δοκιμάστε ξανά σε λίγο»);
  - `LocalNeuralTranslator.TranslatorError.modelsMissing`;
  - `CancellationError` (no message);
  - anything else (a generic message).

  The technical detail goes to `Log.warning(…, category: .llm)` only.
- `executeStatuteSummary` / `executeLegalOpinion`: check `SystemLanguageModel.default.availability`
  first; if it isn't `.available`, return the fixed "Apple Intelligence isn't available on this
  device" message in the query's language (as `LabourContractTemplateRouter` already does).
- The `catch` blocks in `handleChatQuery` use `failureMessage`.
- `GreekLegalOpinionWriter.swift`: add a computed `Opinion.refusalGreek` that maps the two known
  English reasons to Greek. `refusal` keeps its English value, so the evaluation logs and
  `GreekLegalOpinionTests.swift:292` are unchanged. The router uses `refusalGreek` for Greek
  questions.
- `GreekLegalAssistantSheet.swift`:
  - the two `catch` blocks (338, 775) use `failureMessage`;
  - the opinion tab shows the refusal as a message when `op.refusal != nil`, instead of an empty
    card (today a refused opinion renders as blank text).
- **Tests:** `failureMessage` for each error case returns text with no English in the Greek
  variant and never contains `localizedDescription`; `refusalGreek` for both reasons.

### 3. Correct progress stage for capabilities (`ChatScreen.swift`, router)

- `handleChatQuery` gains an optional `intent:` parameter (default: detect inside, as now).
- In `ChatScreen` (around line 3255), detect the intent first. When it isn't `.standardQA`, set on
  the main actor `stage = .generating`, `generationStart` / `generatingStartTS = Date()`, and
  `continuedQueryCoordinator.markGenerating()`, as the normal path does at 3373–3380. Then call the
  router with that intent.
- Add `try Task.checkCancellation()` after the router returns, so a cancelled request isn't
  appended. Cancellation inside the summarizer and opinion passes is a deeper fix, not in this plan.

### 4. Real timing, no zero metrics

- `GreekLegalChatRouter.swift`: time each capability with `ContinuousClock` in `handleChatQuery`.
  The executors take the elapsed seconds and pass them as `totalGenerationTime` (the field is a
  `let`, so it's set at construction).
- `ResponseDetailsView.swift`:
  - hide the "tokens" stat (≈383) and the "Tokens Generated" row (685) when `tokensGenerated == 0`;
  - hide the "Retrieval Time" row (684) when `retrievalTime == 0`.

  This only affects answers without those values; normal Q&A answers always have them.

### 5. Language consistency of capability answers (`GreekLegalChatRouter.swift`)

- The summary header becomes `### Σύνοψη: …` for Greek questions and `### Summary: …` for English
  ones.
- The English template answer uses `**Applicable provisions:**` instead of «Εφαρμοστέες διατάξεις».
- The "empty library", "which document?" and "no passages" messages get English variants, chosen
  by the query's language.
- The opinion refusal is covered by item 2.
- The 'Documents' tab name in the Greek hint stays as is: the app's interface is English, so that
  is the label the user sees.

### 6. Locale-independent test (`AnswerUsageTallyTests.swift:62`)

- Build the expected string with `1_100.formatted()`, so it passes in any region. No change to app
  code: showing numbers in the user's locale is correct.

### 7. Demo setup checklist (no code)

Already in `POC_PROGRESS.md`. Done on the demo Mac by the owner:
- library pre-imported;
- device language English, Apple Intelligence on;
- translation models present;
- airplane mode;
- each demo prompt rehearsed 3–5 times.

## Records (same task, per AGENTS.md)

- `Docs/Thesis/FORK_CHANGES.md`: new dated entry "Demo quick wins" (why, what, files,
  verification), with the prototype table above.
- `CHANGELOG.md`: entries under the current section ("Fixed" for 2–6, "Changed" for 1).
- `Docs/Thesis/METHODS_SUMMARY.md`: one revision-history line, since chat intent recognition is
  part of the method: "capability requests in the chat recognised without accents; ordinary
  questions no longer sent to a capability".
- `POC_PROGRESS.md`: tick items 1–6.

## Verification

1. Build:
   ```bash
   bash scripts/build_simulator_smoke.sh
   ```
   Expected: `** BUILD SUCCEEDED **`.
2. Targeted suites:
   ```bash
   ./scripts/thesis_run_tests.sh /private/tmp/quickwins.log -only-testing:FirikiTests/GreekLegalChatRouterTests -only-testing:FirikiTests/GreekLegalOpinionTests -only-testing:FirikiTests/GreekLegalSummaryTests -only-testing:FirikiTests/LabourContractTemplateTests -only-testing:FirikiTests/AnswerUsageTallyTests -only-testing:FirikiTests/GreekLegalVerificationTests
   ```
   Expected: 0 failures; the log shows the new router test names ran (to rule out a silent
   `-only-testing` mismatch).
3. Full unit suite:
   ```bash
   ./scripts/thesis_run_tests.sh /private/tmp/quickwins_full.log
   ```
   Expected: `Executed N tests, with 0 failures` (the Greece-region failure is gone).
4. Owner, on the Mac with Apple Intelligence and the library imported (the simulator can't run
   the model):
   - the four README demo prompts;
   - «Τι ισχύει για τη σύμβαση εργασίας για ορισμένο χρόνο;» (must answer, not show a template);
   - «συνοψη του ν. 5278/2026» (must summarise);
   - an opinion request while watching the stage indicator;
   - opening the details of a summary (no "0 tokens").

## Open questions for the owner

1. «Ποια σύμβαση εργασίας προβλέπεται για μαθητεία;» is currently expected to open a template. With
   the new rules it is answered as a question about the law ("which contract does the law provide
   for apprenticeship?"). OK to change that test expectation?
2. Item 1 recognises about 4 in 10 naturally worded template requests from the chat. Is that
   enough for the demo (using the README's phrasing), or do you want a follow-up plan for a
   model-based intent check?
3. Items 1–6 as one commit, or one commit per item?
