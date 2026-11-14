# Plan: find the document to summarise by its law number

Status: implemented 14 Nov 2026 (approved by the owner; the heading shows the statute). Deeper fix 2 in `POC_PROGRESS.md`.

## Goal

A summary request in the chat («σύνοψη του ν. 5278/2026») picks the document by the statute its
title page names, not by its filename, and never summarises a different document than the one
asked for.

## What I read

| File | Lines | What it does |
|---|---|---|
| `Firiki/Services/Legal/GreekLegalChatRouter.swift` | 124–130 | A summary request keeps the target from `extractDocumentTarget` |
| same | 144–161 | `extractDocumentTarget` returns "5278/2026"; whether it was a law, a decree or a decision is lost |
| same | 165–182 | `matchDocument`: filename contains the target, else the first filename that contains the bare number |
| same | 322–386 | `executeStatuteSummary`: with one document in the library it summarises that one, whatever was asked |
| `Firiki/Services/Document/Localization/GreekLegalIngestion.swift` | 91–122 | The statute key is read from the title page at import ("LAW:5278/2026", "PD:62/2025", "MD:8934", "CONST") and stored on every passage |
| `Firiki/Services/RAG/Safety/GreekLegalAnswerService.swift` | 141–170 | `requestedStatutes` (statutes a question names) and `statuteName`; Q&A already uses them to search inside a named law |
| `Firiki/Services/RAG/Safety/LegalVerificationPolicy.swift` | 182–190 | `sameStatute`: "LAW:5239" is "LAW:5239/2025" |
| `Firiki/Services/RAG/Orchestration/RAGService.swift` | 6077–6093 | `greekLegalStatuteScope` reads each document's key from its first passage |
| `FirikiTests/Services/GreekLegal/GreekLegalChatRouterTests.swift` | 255–282 | Current target and match tests |
| `Benchmarks/GreekLabourLibrary/`, `Benchmarks/GreekLabourCode/` | — | Demo files are named `n_5278_2026_fek_a22.pdf`, `pd_62_2025_fek_a121.pdf`, `ya_8934_2026_fek_b1759.pdf` |

## What goes wrong today

1. **A renamed file isn't found.** With a file named, for example, «ΦΕΚ Α 22.pdf», the request gets
   "which document?" even though the library knows that file is Law 5278/2026.
2. **The number is matched as a substring.** "62" matches any filename that contains 62
   ("…b1762…", "…2062…"), and the kind is ignored (decree 62 vs law 62).
3. **One document means it is always summarised.** If the library holds only the Labour Code,
   «σύνοψη του ν. 5278/2026» summarises the Labour Code.
4. **The list of documents shows filenames only.**

The demo files' names happen to contain their numbers, so the demo works today. The risk is a
renamed file or a single-document library.

## Changes

1. **`GreekLegalChatRouter.swift`**
   - `matchDocument` takes the request, the target, the documents and each document's statute key.
     It returns one of three results: the document, "named a statute that isn't in the library",
     or "named nothing". It tries in this order:
     1. statutes named with their kind (`requestedStatutes`) against the documents' keys
        (`sameStatute`);
     2. the number (and year, if given) against the keys' numbers, any kind. This covers
        «νόμου 5239» with no year, and «ν. 62/2025» for the Labour Code, which is a decree;
     3. the filename, with the number compared as a whole number (not a substring), and the year
        too if given.
   - `executeStatuteSummary` reads the keys and uses the one-document shortcut only when the
     request names no statute. If the named statute isn't in the library, it answers «Ο ν. 5278/2026
     δεν υπάρχει στη βιβλιοθήκη.» followed by the list of documents. The list shows each
     document's statute next to its filename: «- ν. 5278/2026 (n_5278_2026_fek_a22.pdf)».
   - New `greekStatuteName(_:)`: «ν. 5278/2026», «π.δ. 62/2025», «Υ.Α. 8934», «Σύνταγμα». English
     uses the existing `statuteName`.
   - The summary heading shows the statute when known: «### Σύνοψη: ν. 5278/2026». This is open
     question 1.
2. **`RAGService.swift`:** move the key-reading loop (6082–6090) into
   `documentStatuteKeys(containerId:) -> [UUID: String]` and call it from `greekLegalStatuteScope`
   and from the summary. Q&A behaviour is unchanged.
3. **`GreekLegalChatRouterTests.swift`:** replace `matchDocumentInLibrary` with a table over the
   five demo files, under their real names and under renamed ones, with their keys:
   - «σύνοψη του ν. 5278/2026», «Σύνοψη του Π.Δ. 62/2025», «περίληψη της Υ.Α. 8934/2026»,
     «σύνοψη του νόμου 5239», «συνοψη του ν 5316/2026», «Summarize Law 5278/2026»;
   - a renamed file (no number in its name) is still found by its key;
   - with both a law 62/2025 and a decree 62/2025 present, the kind asked for wins;
     «ν. 62/2025» still finds the Labour Code when only the decree is present;
   - "62" doesn't match `ya_8934_2026_fek_b1762.pdf`;
   - a document without a key (imported before keys existed) is found by filename;
   - a one-document library with another statute named gives "not in the library";
   - «σύνοψη του εγγράφου» with several documents gives the list.
4. **Records:**
   - `FORK_CHANGES.md` and `CHANGELOG.md` (5.7);
   - a revision line in `METHODS_SUMMARY.md`;
   - tick deeper fix 2 in `POC_PROGRESS.md`.

   `EXPERIMENTS.md` is not updated: no question set goes through this path. The summary evaluation
   reads the document directly.

No change to `project.pbxproj`, entitlements or `Info.plist`.

## Verification

```bash
./scripts/thesis_run_tests.sh /private/tmp/router.log -only-testing:FirikiTests/GreekLegalChatRouterTests
./scripts/thesis_run_tests.sh /private/tmp/full.log
xcodebuild build -scheme Firiki -destination 'platform=macOS' -derivedDataPath /private/tmp/oi-mac
```

What I can't check here: an actual summary in the Mac app, which needs Apple Intelligence and the
imported library.

## Open questions

1. **Heading:** show the statute («### Σύνοψη: ν. 5278/2026») instead of the filename? I'd say yes,
   since it reads better in a demo.
2. **Deeper fix 6 (the `try!` patterns):** the existing masker and title-page tests already build
   every one of those patterns, so I'd mark it covered rather than add a test.
