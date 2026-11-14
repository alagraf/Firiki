# Plan: Do not render isolated numbered statute paragraphs as list badges

**Status:** implemented 14 Nov 2026
**Symptom:** Under Article 8 (and similar statutes), an isolated numbered paragraph (`"4. …"`) renders as a single Markdown numbered-list circle badge (`4`), and mid-line references after punctuation (`"παρ. 4. …"` or `"…. 4. …"`) are broken onto a new line as a lone badge.

## Root cause

In `Firiki/Core/Extensions/MarkdownRenderer.swift`:
1. `MarkdownParser.normalizeInlineMarkdown(_:)` unconditionally inserts `\n` before `(?<=[.!?:]) +(\d+[.)]\s)` and `(?<=\S) +(\d+[.)]\s+\*\*)`, splitting normal legal sentences containing paragraph numbers (`4. …`) or abbreviations (`παρ. 4. …`) onto a new line.
2. `MarkdownParser.parse(_:)` treats any line matching `^\d+[.)]\s+` (`isNumberedLine`) as `.numberedList`, even when it is a single standalone paragraph starting at a number greater than `1` (such as `"4. …"`).

## Planned changes

1. `Firiki/Core/Extensions/MarkdownRenderer.swift`:
   - In `normalizeInlineMarkdown(_:)`, only apply the mid-line numbered-item line-break rules to lines that actually contain an inline ordered list sequence (`1.` / `1)` followed later by `2.` / `2)`).
   - Add `startsNumberedList(at:in:)` in `MarkdownParser`: a line matching `N. ` / `N) ` starts a `.numberedList` only if `N == 1` or it is followed in the same list block by item `N + 1`. Single isolated items starting at `N > 1` (such as `"4. …"`) stay in `.paragraph` (and do not prematurely split `.bulletList` continuations).
   - Extend `MarkdownParserTesting` (`#if DEBUG`) with `parseBlockKinds(_:)` so hosted unit tests can assert parsed block types directly.
2. `FirikiTests/Core/Extensions/MarkdownRendererNumberedListTests.swift`:
   - Test that isolated `"4. …"`, inline `"**Article 8:** … παρ. 4. …"`, and `". 4. …"` parse as `.paragraph` rather than `.numberedList`.
   - Test that inline `"Features: 1. **A** 2. **B**"` and multi-line `"1. First\n2. Second"` / `"4. Fourth\n5. Fifth"` still parse as `.numberedList`.
3. Verify on iOS Simulator unit tests (`MarkdownRendererNumberedListTests`, `MarkdownRendererHorizontalRuleTests`, `GreekLegalSummaryTests`) and macOS build (`xcodebuild build -scheme Firiki -destination 'platform=macOS'`).
4. Record in `FORK_CHANGES.md`, `CHANGELOG.md`, `POC_PROGRESS.md`, commit, and push.
