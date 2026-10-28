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
- New Swift files need no project edit (the target uses synchronized folders).

## Phase 1: strict local control
- [ ] `StrictLocalControlGuard.swift` (exclude from backup, iCloud off, block web-page import, `canUsePCC`)
- [ ] Hook: storage directories, ubiquity container lookup, web page import, PCC instantiation
- [ ] Tests + FORK_CHANGES/CHANGELOG

## Phase 2: entity masker + bilingual schema
- [ ] `GreekLegalEntityMasker.swift` (NFKC, mask, unmask bilingual/greekVerbatim)
- [ ] SQLite columns + `DocumentChunk` fields (sourceTextEl, sourceLanguage, legalEntities, primaryStatuteKey)
- [ ] `GreekLegalPipelineTests.swift` masking test

## Phase 3: Greek OCR + extraction fixes
- [ ] `validateAndCleanOCR` Greek bypass
- [ ] NFKC on PDFPage.string; full-page Greek detection (no 2,000-char drop)
- [ ] onnxruntime package; models bundled
- [ ] `GreekPaddleOCRService.swift`, `OCRRouterService.swift`
- [ ] 5 call sites routed
- [ ] OCR test

## Phase 4: translation
- [ ] Opus-MT ONNX conversion + `LocalNeuralTranslator.swift`
- [ ] `TranslationService` Greek fast path; `translatedQueryForEmbedding`
- [ ] Ingestion translation (sourceTextEl/content/entities)
- [ ] FTS5 Greek-query fix (HybridSearchService)
- [ ] Intent keywords; GraphIndexService + resolveCrossReferencesStandard legal refs
- [ ] Bilingual retrieval test

## Phase 5: gates, abstention, Greek output
- [ ] Plain-text generation for legal mode; buffered output; assetID logging
- [ ] Strict abstention (relevance gate, reliabilityMode fallbacks)
- [ ] Gate A/source-only legal thresholds; Gate C Greek numerals; Gate F legal identifiers; Gate I statutory isolation; enforced in all modes
- [ ] en→el answer translation; citation UI shows sourceTextEl
- [ ] `LegalSLMEnricherProtocol.swift` hook
- [ ] Gate/abstention tests; full suite

## Baseline

(pending)

## Log
