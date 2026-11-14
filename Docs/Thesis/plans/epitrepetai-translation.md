# Plan: Verify and harden standalone «Επιτρέπεται;» Greek query translation

**Status:** implemented 14 Nov 2026
**Goal:** Confirm that standalone impersonal «Επιτρέπεται;» (`"Is that allowed?"`) never translates via Opus-MT as `"May I?"` across Greek legal Q&A, query embedding translation, and legal opinions, including after comma/dash punctuation (`, επιτρέπεται;`), and lock down this behavior with a live Opus-MT unit test in `GreekTranslationRetrievalTests`.

## Background

In E17 (`Docs/Thesis/plans/short-overtime-opinion.md`), `RAGService.normalizedGreekQuery(_:)` was added to rewrite standalone `[Εε]πιτρέπεται([?;]|$)` after start-of-string or `[.!?;:\n]\s` to `Επιτρέπεται αυτό` before `LocalNeuralTranslator` translates the query (`"Is that allowed?"`), and all three Greek query paths (`RAGService` embedding translation, `RAGService` answer prompt translation, and `GreekLegalOpinionWriter`) call `RAGService.greekQueryTranslation(_:)`.

## Planned checks & changes

1. `Firiki/Services/RAG/Orchestration/RAGService.swift`:
   - Widen the preceding-delimiter class in `normalizedGreekQuery(_:)` from `[.!?;:\n]` to `[.!?;:,\n—–-]` (plus optional `,?` whitespace before punctuation) so forms such as `"…, επιτρέπεται;"` also normalize cleanly to `"…, επιτρέπεται αυτό;"`.
2. `FirikiTests/Services/GreekLegal/GreekLegalPipelineTests.swift`:
   - Add a live Opus-MT test in `GreekTranslationRetrievalTests` translating both `"Ο εργοδότης ζητά τέσσερις ώρες υπερωρία την ημέρα. Επιτρέπεται;"` and `"Ο εργοδότης ζητά 4 ώρες υπερωρία, επιτρέπεται;"` via `RAGService.greekQueryTranslation(_:)`, asserting `!english.lowercased().contains("may i")` and `english.lowercased().contains("allowed")`.
3. Run `GreekKeywordArmTests`, `GreekTranslationRetrievalTests`, and `GreekLegalOpinionTests` via `./scripts/thesis_run_tests.sh`.
4. Record in `FORK_CHANGES.md`, `CHANGELOG.md`, `POC_PROGRESS.md`, commit by name, and push to `origin main`.
