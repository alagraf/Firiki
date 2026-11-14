# Plan: no translation placeholders left in passages and answers

Status: implemented 14 Nov 2026 (repair on read, no re-import; EXPERIMENTS E15).

## Goal

The placeholders the translator protects legal identifiers with (`__LEX_ENT_007__`) never reach
the reader or the model. A placeholder the translator mangles is still put back as its identifier,
and passages already stored with leftovers are repaired when they are read, without a re-import.

## What I found

- **Where:** at import, each Greek passage is masked (`Άρθρο 7`, `ν. 5239/2025` →
  `__LEX_ENT_00N__`), translated to English and unmasked
  (`LocalNeuralTranslator.translateGreekToEnglishPreservingLegalEntities`, lines 688–695). The
  unmask pattern (`GreekLegalEntityMasker.placeholderPattern`, line 501) needs both `LEX` and
  `ENT`.
- **How much:** in the Simulator's five-document library, **439 of 6,336 stored English passages
  (7%)** keep a placeholder the pattern missed; 400 of them still store their entity list with
  the ids.
- **The forms** (from those passages):
  - `__LEX_005___` (239), `LEX_004___` (214), `__LEX_004__` (118);
  - `ENT_005___`, `__EX_ENT_003_`, `LEX__007_______`, `__L_ENT_00_00_00_`;
  - runs where the translator looped (`___0____0__0_______0_0___`).
- **What the reader sees:** the model copies them into its drafts. The opinion of 14 Nov showed
  «στην __ΕΧΝ. 5239/2025»: a leftover the English→Greek translator turned into Greek letters. The
  Law 5239 passage the overtime opinion needed had its quoted new text replaced by `_LEX_008___…`.

## Changes

1. **`GreekLegalEntityMasker.swift`:**
   - `placeholderPattern` also accepts the mangled forms: `LEX` or `EX` without `ENT`, `ENT`
     without `LEX`, doubled `ENT`, any underscores and spaces around, and leading zeros. It still
     needs one of the words `LEX`/`EX`/`ENT` next to an underscore, so ordinary text such as
     "Article 7" or "EX 5" can't match;
   - `unmaskEntities` keeps replacing only numbers it has an entity for;
   - new `removingPlaceholderDebris(_:)` deletes what is left afterwards: a placeholder-shaped
     token with no entity, and runs of three or more underscores mixed with digits;
   - new `repairingLeftovers(_ chunk: DocumentChunk) -> DocumentChunk` unmasks a stored passage's
     content with its own `legal.legalEntities`, as at import (bilingual anchors), then removes the
     debris. A passage without leftovers is returned unchanged.
2. **`LocalNeuralTranslator.swift`:** after each unmask (Greek→English at import and in the
   question, English→Greek for answers), `removingPlaceholderDebris`.
3. **`BNNSVectorDatabase.swift`:** `decodePassage` (line 674) and the whole-file fallback (line
   341) return `repairingLeftovers(chunk)`.
   - Every stored passage is repaired as it is read, in memory, on iPhone and Mac.
   - The file and the embeddings are unchanged: the embeddings were made from the broken text, and
     only a re-import refreshes them.
   - The keyword index keeps the old English text; Greek keyword search uses the Greek original.
4. **Tests (`GreekLegalEntityMaskerTests`):**
   - every form above is put back as its identifier;
   - a placeholder with no entity and a looping run are removed;
   - "Article 7", "EX 5", «Στ………» and a template's `{{employee_name}}` are untouched;
   - `repairingLeftovers` on a passage copied from the Simulator library (the Article 54 passage
     with `EEC__EX_ENT_003_/ LEX_004__`) gives its identifiers back;
   - a passage without leftovers is the same value.
5. **Records:**
   - `FORK_CHANGES.md` and `CHANGELOG.md`;
   - `EXPERIMENTS.md` E15 (leftover count before and after; dev runs);
   - `METHODS_SUMMARY.md` if a number changes;
   - `POC_PROGRESS.md`.

No change to `project.pbxproj`, entitlements or `Info.plist`.

## Verification

```bash
./scripts/thesis_run_tests.sh /private/tmp/masker.log -only-testing:FirikiTests/GreekLegalEntityMaskerTests -only-testing:FirikiTests/GreekLegalOpinionTests
TEST_RUNNER_OI_GREEK_OPINION=1 TEST_RUNNER_OI_GREEK_OPINION_SPLIT=dev ./scripts/thesis_run_tests.sh /private/tmp/opinion_dev5.log -only-testing:FirikiTests/GreekLegalOpinionEvaluation
TEST_RUNNER_OI_GREEK_EVAL=1 TEST_RUNNER_OI_GREEK_EVAL_SET=GreekLabourLibrary ./scripts/thesis_run_tests.sh /private/tmp/library_dev.log -only-testing:FirikiTests/GreekConstitutionEvaluationTests
./scripts/thesis_run_tests.sh /private/tmp/full.log
xcodebuild build -scheme Firiki -destination 'platform=macOS' -derivedDataPath /private/tmp/oi-mac
```

- **Leftovers:** counted again with the same script over the Simulator library, after the repair
  (target: 0 of 6,336 in what the model reads; the 39 passages without an entity list only lose
  their debris).
- **Dev sets:** the opinion dev set and the library Q&A dev set, compared with E14 and E12. The
  repaired text may change retrieval-free answers, so each case is compared.
- **Mac app:** the overtime opinion (longer wording); no «__ΕΧΝ» in the Greek.
- **Last:** the opinion test split, once, as the final measurement (the item left from E14).

## Not in this plan

- **The short overtime question picking the Code's sixth-day Articles 191–192.** I found no
  principled fix: the retrieval is right by its own measure (those articles do mention overtime
  and eight hours a day), and steering it away would be tuning toward the demo question, which is
  not in a question set. The demo uses the evaluation's wording (README, 14 Nov). If wanted later:
  add the short question to the opinion dev split first, then work on it there.
- **«Επιτρέπεται;» translated "May I?".** It doesn't change the outcome on its own.

## Open questions

1. **Repair on read vs. re-import:** repairing on read fixes every existing library at once,
   without the 30-minute re-import. Embeddings stay from the broken text, which costs little:
   most of each passage is unaffected. Is that acceptable, or do you prefer a re-import of the
   demo library as well?
