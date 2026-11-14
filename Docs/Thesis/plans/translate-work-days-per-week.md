# Plan: Fix untranslated «6 work days per week» in Greek opinions and answers (E23)

**Status:** implemented 15 Nov 2026
**Goal:** Eliminate the untranslated English fragment `"6 work days per week"` (and the mistranslation `"6 εργοδοτούμενων ημερών"`) produced when translating Law 5239/2025 Article 7 (`"a work system of six (6) working days per week"`) into Greek, and verify on `GreekLegalOpinionEvaluation` (`split=dev`, including Q1 and Q11).

## Diagnosis

Reproducing `GreekLegalOpinionEvaluation` (`split=dev`) in the iOS 27 Simulator (`firiki-opinion-dev-baseline`) revealed the exact failure chain on both **Q1** and **Q11**:
1. The English draft states `"for workers with a work system of six (6) working days per week, ..."` (mirroring `opus-mt-tc-big-el-en`'s translation of Law 5239/2025 Article 7).
2. `SpelledNumber.digitsForEnglishNumberWords` collapses `"six (6)"` to `"6"`, producing `"a work system of 6 working days per week"`.
3. `opus-mt-tc-big-en-el` stumbles on `"a work system of 6 working days per week"` — either leaving `"6 work days per week"` verbatim in English inside the Greek sentence (`"με σύστημα εργασίας 6 work days per week"`, twice in `dev`: Q1 and Q11) or mistranslating `"working days"` as `"εργοδοτούμενων ημερών"` (Q1 sentence 3). By contrast, `"a six-day work week"` (from Q11's Conclusion) translates cleanly as `"μια εβδομάδα εργασίας 6 ημερών"`.

## Planned changes

1. `Firiki/Services/Document/Localization/LocalNeuralTranslator.swift`:
   - In `legalEnglishPreEdited(_:)`, rewrite `"a work system of <N> work(ing) day(s) per/a week"` → `"a <N>-day work week"` (and without article `"work system of <N> work(ing) day(s) per/a week"` → `"<N>-day work week"`), so `opus-mt-tc-big-en-el` sees natural English phrasing it translates cleanly across Q&A, summaries, and opinions.
2. `Firiki/Services/Legal/GreekLegalOpinionWriter.swift`:
   - In `repairedGreek(_:)`, add defense-in-depth rules fixing any residual `<N> work(ing) day(s) per/a week` (`σύστημα εργασίας <N> εργάσιμων ημερών την εβδομάδα` or `<N> εργάσιμες ημέρες την εβδομάδα`) and `<N> εργοδοτούμενων ημερών` → `<N> εργάσιμων ημερών`.
3. `FirikiTests/Services/GreekLegal/GreekLegalPipelineTests.swift` & `FirikiTests/Services/GreekLegal/GreekLegalOpinionTests.swift`:
   - Add a live `Opus-MT` test translating Q11's exact English sentence through `translateEnglishToGreekPreservingCitations` + `repairedGreek` and asserting zero `"work days"` / English leak, plus unit tests covering `repairedGreek`.
4. Run unit tests + `GreekLegalOpinionEvaluation` (`split=dev`) before/after comparison, verify Q1 & Q11 Greek outputs have no untranslated `"work days per week"`, record **E23**, commit by name, and push to `origin main`.
