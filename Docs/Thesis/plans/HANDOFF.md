# Handoff: where the work stands (14 Nov 2026)

For the agent continuing the Firiki demo work, normally Antigravity, without the earlier
conversation. Written by Claude Code at the end of 14 Nov 2026. The earlier handoff (29 Oct, old
`OpenIntelligence…` paths) is in git history.

## Read first, in this order

1. `AGENTS.md`: the rules, which apply in full except where the standing permission below says
   otherwise.
2. `GEMINI.md`: Antigravity's role.
3. This file.
4. `POC_PROGRESS.md`: the demo audit, its checklists, the 14 Nov rehearsal, and every diagnosis.

## Standing permission from the owner (14 Nov 2026)

The owner said: "Don't ask me for approval, just continue everything." For the tasks below:

- **Plan and implement without waiting:**
  - write the plan first, as usual, in `Docs/Thesis/plans/<short-name>.md`, with Status
    "implemented <date>" once done;
  - then implement, test, measure and record without waiting for approval;
  - take the recommended option on an open question, and say which in the report.
- **Commit and push** to `origin main` (https://github.com/alagraf/Firiki, the only branch) after
  each finished task, once the tests pass. Use one commit per task, add files by name, and end the
  message with an attribution line.
- **Still stop and ask** for:
  - edits to `Firiki.xcodeproj/project.pbxproj`, any `*.entitlements` or `Info.plist`;
  - destructive git (force-push, reset, deleting branches);
  - deleting the owner's documents or libraries;
  - anything touching the EU holdout.

## Rules that are easy to break

- **EU holdout** (`/Users/alagra/Documents/thesis/rag-tests/eu_data.json`) is evaluation only.
  Never read it to diagnose, never change code because of it, never copy it.
- **Tuning uses dev splits only.** A test split is run once, as a final measurement, after the dev
  result decided the change. Never change code because of a test-split result.
- **Record every evaluation-relevant run**, including dropped ideas, with every case's outcome:
  - `Docs/Thesis/EXPERIMENTS.md`: the next entry is **E17**;
  - result lines in `Docs/Thesis/experiments/runs/`.
- **Record every code change:**
  - `Docs/Thesis/FORK_CHANGES.md` (dated entry: why, what, verification with the output lines);
  - the 5.7 section of `CHANGELOG.md`;
  - `Docs/Thesis/METHODS_SUMMARY.md` (results row and revision history) when a method or a number
    changes;
  - the status in `POC_PROGRESS.md`.
- **Show evidence:** never write "passes" without the command and its summary line
  ("Executed N tests, with M failures", "Test run with N tests … passed", `** BUILD SUCCEEDED **`).
- **Run one Simulator job at a time.** `scripts/thesis_run_tests.sh` shuts the simulators down
  before each run.

## State

`main` = the commit that adds this file. It is the latest of these, all pushed on 14 Nov 2026 and
each with a FORK_CHANGES entry:

| Commit | What |
|---|---|
| `a0411c68` | Demo quick wins: chat intent recognition (0 → 38 of 40 template requests), friendly errors, stage and metrics |
| `bbbaed29` | A summary finds its document by statute key, not filename |
| `7e7713c6` | Three display bugs; when two documents are the same statute the fuller is summarised; «Συνόψισε» |
| `7bc5cacd` | An opinion reads the whole amending article; passages not numbered (E14) |
| `bceabda1` | README opinion example: the overtime question that works |
| `96a97935` | Translation placeholders repaired at import and when stored passages are read (E15) |
| `74718ac2` | Summaries and opinions survive model errors; Stop works between passes (E16) |

Latest numbers (Simulator, iOS 27, Apple's on-device model, greedy decoding):
- **Library Q&A dev:** 15 of 24.
- **Opinion dev:** 10 of 12 citations, 13 of 20 key facts.
- **Opinion test** (once): 4 of 8 citations, 8 of 10 key facts.
- **Summary dev:** 5 of 6 provisions.
- **Full suite:** "Executed 1291 tests, with 8 tests skipped and 0 failures"; "Test run with 157
  tests in 29 suites passed".

The owner's Mac app library has 7 documents: the full Labour Code, Laws 5239/2025, 5278/2026 and
5316/2026, decision 8934/2026, the owner's lecture notes («ΑΤΟΜΙΚΟ ΕΡΓΑΤΙΚΟ ΔΙΚΑΙΟ.pdf») and a
Law 5278 excerpt.

## How to build, test and measure

- **Unit tests:**
  `./scripts/thesis_run_tests.sh /private/tmp/x.log -only-testing:FirikiTests/<SuiteStruct>`.
  Name the suite struct (for example `GreekLegalOpinionTests`); a file name silently runs
  nothing. The full suite has no `-only-testing` and takes about 5 minutes.
- **Evaluations** (the five-document library is already imported in the Simulator):
  - opinions:
    `TEST_RUNNER_OI_GREEK_OPINION=1 TEST_RUNNER_OI_GREEK_OPINION_SPLIT=dev ./scripts/thesis_run_tests.sh /private/tmp/o.log -only-testing:FirikiTests/GreekLegalOpinionEvaluation`
  - summaries: `TEST_RUNNER_OI_GREEK_SUMMARY=1 …_SPLIT=dev`, suite `GreekLegalSummaryEvaluation`
  - library Q&A:
    `TEST_RUNNER_OI_GREEK_EVAL=1 TEST_RUNNER_OI_GREEK_EVAL_SET=GreekLabourLibrary TEST_RUNNER_OI_GREEK_EVAL_SPLIT=dev OI_TEST_TIMEOUT_SECONDS=3600`,
    suite `GreekConstitutionEvaluationTests`
  - Decoding is greedy, so a rerun gives the same result: a change in a number is the change's
    effect, not noise.
- **Saving run results:** copy the log into an empty folder and run
  `python3 scripts/thesis/collect_run_results.py <folder> Docs/Thesis/experiments/runs`.
  **Bug:** it rewrites `runs/INDEX.md` from that folder alone. Keep a copy of `INDEX.md` first,
  restore it, and append the new rows.
- **macOS build:**
  `xcodebuild build -scheme Firiki -destination 'platform=macOS' -derivedDataPath /private/tmp/oi-mac`.
- **Mac app with its log:**
  - quit Firiki, then run
    `/private/tmp/oi-mac/Build/Products/Debug/Firiki.app/Contents/MacOS/Firiki > <file> 2>&1`
    in the background;
  - output is buffered, so quit the app to flush it;
  - `[LegalOpinion] Sources/Passage` lines show what an opinion read.
  - The app's sandbox container can't be read from the shell.
- **Simulator data:** the app's data folder moves on every test reinstall. Find it with
  `ls -t ~/Library/Developer/CoreSimulator/Devices/825FECCD-…/data/Containers/Data/Application/*/Library/Application\ Support/Firiki`.
- **New Swift files** need no project edit (file-system-synchronised groups).
- **Apple APIs:** check them in the installed SDK (`FoundationModels.swiftinterface`), not from
  memory. The deployment target is OS 26; OS 27 APIs need `if #available`.

## Next work, in order

1. **Demo mode** (deeper fix 5, `POC_PROGRESS.md`).
   - First check how visible the inherited upstream screens are, and record it:
     - `Firiki/Features/Telemetry/` (Dashboard, `Visualizations/Embedding3DView.swift`,
       `AdaptiveVisualizationsView.swift`);
     - the Database tab (`Firiki/Features/Database`);
     - the metrics bar chips (`UnifiedMetricsBar.swift`).
   - Then add a "Demo mode" setting that hides what doesn't fit the legal story, and default it
     on. A Settings toggle via `@AppStorage` needs no project edit.
2. **Testing plan (Phase 2b in `POC_PROGRESS.md`), remaining flows:**
   - **(3) Greek Q&A end to end with a fake model** over a small fixture library: a Greek answer
     with an article citation; the fixed refusal for a law not in the library; gate C removing an
     unsupported number. Copy the pattern of `GreekEvalOnDeviceModel` and the `LLMService`
     protocol.
   - **(4) Import of the five demo PDFs** (real ONNX, no model): statute key found, article count
     above a minimum, Greek and English text present, translation models in the bundle.
   - An opt-in XCUITest smoke run on "My Mac" with the four README prompts.
   - `scripts/demo_check.sh` running the unit suite and the smoke test.
3. **The short overtime question** («Θέλω γνωμοδότηση: ο εργοδότης ζητά τέσσερις ώρες υπερωρία την
   ημέρα. Επιτρέπεται;»): it concludes "not allowed" because the Labour Code's sixth-day Articles
   191–192 are retrieved (diagnosis in `POC_PROGRESS.md`). Do not tune on it directly. First add it
   to the opinion **dev** split (`Benchmarks/GreekLabourLibrary/opinion_qa_v1.jsonl`, next id,
   `"split": "dev"`, citations and key facts like case 1), record that, then work on it there.
4. **Summary cosmetic:** an article's numbered paragraphs render as list badges (a lone "4" under
   Article 8 of Law 5278). Find where the summary's provisions are built
   (`GreekLegalDocumentSummarizer.provisions`) or rendered, and keep "N." at a line start from
   becoming a list.
5. **Summary dev:** since E15 it cites 2 of 3 articles (3 before), and Article 8's "all normative
   terms continue" is missing. Investigate on the dev split only.
6. **README results table:** it still shows the 13–14 Nov figures. Run the library Q&A test split
   once, then update the table from E14–E16 and that run, with dates.
7. **Low priority:** «Επιτρέπεται;» is translated "May I?" in the question translation.

Not for the agent: the demo-day checklist on the owner's Mac (item 7 in `POC_PROGRESS.md`:
language, airplane mode, prompt rehearsal), and whether the lecture notes and the excerpt stay in
the demo library.

## Report back

After each task, a short report to the owner:
- what changed;
- the commands run and their summary lines;
- the measured numbers against the previous ones;
- the commit hash;
- anything left undone.
