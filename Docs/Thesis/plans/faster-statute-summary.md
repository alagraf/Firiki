# Plan: Speed up statute summaries without losing provisions (E24)

**Status:** implemented 15 Nov 2026
**Goal:** Cut Law 5278/2026 summary runtime (`~140–142 s` in E21 / E24 baseline) while preserving `6 of 6` provisions covered, `3 of 3` articles cited, and `0` unsupported sentences dropped.

## Profiling findings (`firiki-summary-dev-baseline`)

Running `GreekLegalSummaryEvaluation` (`split=dev`) logged exact breakdown on `n_5278_2026_fek_a22.pdf` (`139.7 s`):
- Opus-MT (`en→el`, 4,043 chars / 27 segments) took only **3.1 s** (`2.2%`); **136.6 s (`97.8%`)** went into the 14 map calls + 1 reduce call to `SystemLanguageModel`.
- `onDeviceResponse` passed `GenerationOptions(samplingMode: .greedy)` with **no `maximumResponseTokens` cap**.
- Although `cleanedNotes(..., lines: lines)` keeps only 3–6 lines (`≤ 320` chars/line, ~800–1,000 chars for 3 lines), groups 4, 9, 10, 11, and 12 each generated **2,284 to 3,814 characters** (14,546 chars total across those 5 groups alone, `25,011` chars across all 14 groups) before discarding everything past line 3.
- `map` groups also still included standalone boilerplate articles whose heading explicitly marks only `"Entry into force"` (`Έναρξη ισχύος`) or `"Repealed provisions"` (`Καταργούμενες διατάξεις`) even though the prompt asks the model to omit them.

## Planned changes

1. `Firiki/Services/Legal/GreekLegalDocumentSummarizer.swift`:
   - Add token budgets: `mapMaximumResponseTokens(lines:)` (`min(480, lines * 75 + 45)`) for map calls and `reduceMaximumResponseTokens = 140` for the 1–2 sentence opening, wired through `onDeviceResponse(instructions:prompt:maximumResponseTokens:)` (`nil` default preserved for callers such as opinions).
   - Add `isBoilerplateClosingArticle(_:)` to exclude trailing/standalone `"Entry into force"` / `"Repealed provisions"` articles (short boilerplate sections after `Article 1`) from `groups(of:)` while still passing the full `articles` array to `droppingUnsupported(...)` so citation verification knows every article of the statute.
2. `FirikiTests/Services/GreekLegal/GreekLegalSummaryTests.swift`:
   - Add unit tests verifying `mapMaximumResponseTokens(lines:)`, `reduceMaximumResponseTokens`, and `isBoilerplateClosingArticle` (leaving substantive articles untouched while skipping pure entry-into-force / repealed-provisions boilerplate).
3. Run `GreekLegalSummaryTests` and `GreekLegalSummaryEvaluation` (`split=dev`), measure runtime, `groups`, `noteCharacters`, `provisions`, `articles cited`, and `dropped` against `firiki-summary-dev-baseline` / E21; verify `GreekLegalOpinionTests` + `GreekLegalSummaryTests` pass; record **E24** in all docs, commit by name, and push to `origin main`.
