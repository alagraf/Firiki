# Plan: Update README.md with PoC Capabilities, OCR Breakthroughs, and Latest Evaluation Metrics

## Context & Purpose
Since the initial `README.md` was published on 2026-10-29, the Firiki thesis proof of concept has reached several milestones:
1. **The 4 PoC Capabilities**:
   - Multi-document Greek labour law Q&A across a 5-document library (Labour Code, Laws 5239/2025, 5278/2026, 5316/2026, and Decision 8934/2026).
   - Automated statute summarization (`GreekLegalDocumentSummarizer`) via map-reduce fitting the 4,096-token device window.
   - Multi-document legal opinion drafting (`GreekLegalOpinionWriter`) analyzing statutory interactions and amendments between newer laws and the Labour Code.
   - Labour contract template routing (`LabourContractTemplateRouter`) matching natural-language hiring prompts to 10 bundled Greek contract templates.
   - App Intents / Siri / Shortcuts integration (`RouteLabourContractIntent`, `SummarizeStatuteIntent`, `GreekLegalOpinionIntent`).
2. **OCR Breakthrough on Tilted Scans**:
   - Oriented text line boxes (`TextLineBox`) following principal axes instead of axis-aligned boxes, improving word recall on tilted scans from 48% to 96% (matching clean pages) and achieving 98% on full scanned PDFs.
3. **Statutory Structure & Ingestion Refinements**:
   - Table row preservation (table rows kept distinct for schedules like severance pay in Art. 333).
   - Document statutory identity (`documentStatuteKey`) and pre-generation refusal for queries naming statutes outside the library.
   - Gate C off-topic figure pruning.
   - Spatial ordering and keraia fix preventing token displacement.
4. **Empirical Evaluation Updates**:
   - Final hand-graded EU directives holdout rerun: 38/39 correct answerable, 9/9 (100%) refused.
   - Full 260-page Labour Code test split: 15/23 (up from 11/23 baseline), with 3/3 (100%) correct refusals.
   - Template routing benchmark: 43/44 dev, 20/22 test (91%).
   - Multi-document library, summarization, and legal opinion evaluation numbers.

## Files to Modify

1. **`README.md`**:
   - **Architecture & Highlights**: Add a dedicated section for the 4 core PoC capabilities and App Intents.
   - **OCR Details**: Detail the oriented bounding box detection (`TextLineBox`) for tilted scan handling.
   - **Ingestion & Guardrails**: Add table row preservation, `documentStatuteKey` statutory identity, and Gate C figure pruning.
   - **Usage**: Add usage instructions and prompt examples for Multi-Document Q&A, Statute Summaries, Legal Opinions, Contract Template Routing, and iOS App Intents. Add test commands for the new evaluation suites.
   - **Empirical Evaluation**: Update the benchmark comparison table with all final evaluation figures from `METHODS_SUMMARY.md`.

2. **`Docs/Thesis/FORK_CHANGES.md`**:
   - Add subsection `2.11.32 Firiki README update: PoC capabilities, tilted OCR and evaluation results` describing why, what, files modified, and verification.

3. **`CHANGELOG.md`**:
   - Update the `## 5.7` section to record the updated technical documentation.

## Verification
- Verify formatting, links, and code blocks in `README.md`.
- Verify git diff and ensure no unintended files are staged.
