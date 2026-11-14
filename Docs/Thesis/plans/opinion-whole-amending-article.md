# Plan: an opinion reads the whole amending article

Status: implemented 14 Nov 2026, with the passages no longer numbered (EXPERIMENTS E14). Diagnosis in `POC_PROGRESS.md`,
"Why the overtime opinion concludes 'not allowed'".

## Goal

When a law in an opinion amends or adds a Labour Code article, and the question retrieved that
amending article, the model reads the whole amending article in order, not only its best three
passages. The amending article restates the amended paragraphs in full («… διαμορφώνονται ως
εξής»), which is the text the conclusion needs.

## What I read

| File | Lines | What it does |
|---|---|---|
| `Firiki/Services/Legal/GreekLegalOpinionWriter.swift` | 71–76 | `maxSources = 3`, `passagesPerSource = 3`, `relativeScore = 0.6` |
| same | 83–98 | `selectSources`: keeps the documents near the best score, the Labour Code when a kept law amends it, and cuts each to 3 passages |
| same | 113–145 | `codeLinks`: an article heading "… Τροποποίηση … άρθρου 194 Κώδικα Εργατικού" gives a link (law, article 7 → Code 194) |
| same | 155–165 | `enclosingArticles`: the article each passage belongs to, in chunk order |
| same | 175–204 | `replacingAmendedCodePassages`: a *retrieved* Code passage of an amended article is replaced by the amending article's heading passage and the one after it. It does nothing when the Code article wasn't retrieved, as here |
| same | 452–455 | `sectionPrompt`: the passages as numbered `[n]` blocks |
| same | 563–600 | `RAGService.greekLegalOpinion`: top 8 passages per document, cut to 3, then the replacement, then `selectSources`, then `write` |
| `Firiki/Services/Legal/GreekLegalDocumentSummarizer.swift` | 36–41 | `windowTokens = 4_096`; `groupCharacters` = 45% of the window at 4 characters a token (7,372 characters of passages) |
| `FirikiTests/Services/GreekLegal/GreekLegalOpinionTests.swift` | — | Unit tests with fixed passages and an injected model; the opt-in evaluation `GreekLegalOpinionEvaluation` |
| `Benchmarks/GreekLabourLibrary/n_5239_2025_fek_a178.pdf` | Article 7 | Its last paragraph is the new par. 3 of Article 194: «έως τέσσερις (4) ώρες ημερησίως … 150 ωρών ετησίως … 40%» |
| `Docs/Thesis/experiments/runs/firiki-opinion-dev2.txt` | — | Baseline: dev citations 10 of 12, key facts 11 of 20, refused 0 of 6; case 1: 2 of 2, 3 of 4 |

## Changes

1. **`GreekLegalOpinionWriter.swift`:** new `withWholeAmendingArticles(_ sources: [Source], links:
   [CodeLink], documents: [String: [DocumentChunk]]) -> [Source]`.
   - For each source with a link of kind `.amends` or `.adds` whose amending article is among its
     passages, the passages become all of that article's passages in chunk order (found with
     `enclosingArticles`), then its other retrieved passages by score.
   - Each such source is cut to `sectionCharacters` (= `GreekLegalDocumentSummarizer.groupCharacters`,
     7,372 characters). Whole passages are kept from the front, so the article's heading and its
     restated paragraphs come first; at least one passage is always kept.
   - Sources without such a link (the Code, a decision, the lecture notes) are unchanged and keep
     at most 3 passages.
   - The added passages carry the source's best score, so `selectSources` and `bestScore` behave
     as before.
2. **`RAGService.greekLegalOpinion`** (same file, line ~593): apply it after `selectSources` and
   before `keptLinks`. `keptLinks` still requires the amending article among a source's passages,
   so it is unchanged. The log lines already print every passage.
3. **Tests (`GreekLegalOpinionTests`):**
   - A law source holding only passage 2 of its Article 7 (four passages, then Article 8), with a
     link 7 → 194, gets Article 7's four passages in order, then its other passages; Article 8 is
     not added.
   - A long amending article is cut at the character budget, keeping its first passage.
   - A source with no link, and the Code source, are unchanged.
   - The existing opinion tests still pass.
4. **Records:**
   - `FORK_CHANGES.md` and `CHANGELOG.md`;
   - `EXPERIMENTS.md` E14, with the dev run, every case's outcome and the Mac app check;
   - `METHODS_SUMMARY.md` (results table and revision history) if the numbers change;
   - `POC_PROGRESS.md`.

No change to `project.pbxproj`, entitlements or `Info.plist`.

## Verification

```bash
./scripts/thesis_run_tests.sh /private/tmp/opinion_unit.log -only-testing:FirikiTests/GreekLegalOpinionTests
TEST_RUNNER_OI_GREEK_OPINION=1 TEST_RUNNER_OI_GREEK_OPINION_SPLIT=dev ./scripts/thesis_run_tests.sh /private/tmp/opinion_dev.log -only-testing:FirikiTests/GreekLegalOpinionEvaluation
./scripts/thesis_run_tests.sh /private/tmp/full.log
xcodebuild build -scheme Firiki -destination 'platform=macOS' -derivedDataPath /private/tmp/oi-mac
```

- **Dev set:** compare per case with `firiki-opinion-dev2`. Case 1 should name the four hours a day,
  150 a year and 40%; no case should lose a citation or key fact.
- **Model time:** each section now reads up to about 7,400 characters instead of three passages,
  so the time per opinion may grow; it is recorded.
- **Mac app:** the demo prompt «Θέλω γνωμοδότηση: ο εργοδότης ζητά τέσσερις ώρες υπερωρία την
  ημέρα. Επιτρέπεται;» on the 7-document library, with the log saved.
- **Not verified:** the test split (4 cases), unless the owner asks for one final run after the
  dev result.

## Open questions

1. **Test split:** run it once after the dev result, as a final measurement (the dev result
   decides whether to keep the change)?
2. **Lecture notes:** they take one of the three source places and add weekly limits. Keep them in
   the demo library, or move them to a separate library? This is the owner's call. The plan doesn't
   change how sources are chosen.
3. **Not in this plan** (recorded in `POC_PROGRESS.md`):
   - the Code's sixth-day Articles 191–192 being retrieved for an overtime question;
   - «Επιτρέπεται;» translated as "May I?";
   - the leftover `_LEX_…` placeholders in Law 5239 passage #108 (an import defect).

   This change may make the first two matter less; the third needs its own diagnosis.
