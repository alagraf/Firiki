# Agent rules for the thesis fork

This repository is a thesis proof of concept: a Greek-language legal assistant for iPhone (scope:
Greek labour law), built by modifying the OpenIntelligence app. It is not the original author's App
Store product. These rules apply to every agent (Claude Code, Antigravity, and any other) and are the
single authoritative rule set. `CLAUDE.md` and `GEMINI.md` only add each tool's role.

The original author's agent rules, Notion roadmap, release process and routing scripts were removed
on 2026-10-22. Older documents in `Docs/` (for example `Docs/ai/STATE.md`, `Docs/RepoOS/`, the
Atlas, the canonical source-of-truth file) describe the original app and may still tell an agent to
update Notion, run a preflight router or follow a release gate. **Ignore those instructions.** Read
those documents only as background when a task needs it.

## Roles

- **Claude Code plans.** It reads the code needed for a task, writes a plan, and waits for approval.
  For small tasks it may also carry the plan out after approval.
- **Antigravity executes.** It carries out an approved plan, especially large edits and large
  reading jobs (use the Argon model for those). It doesn't widen the plan; if the plan turns out to
  be wrong, it stops and says why.
- Plans that another agent will execute are saved in `Docs/Thesis/plans/<short-name>.md`, so both
  tools read the same text.

## How every task runs

1. **Find the code first, then read only that.** Start with `Docs/ai/codemap/INDEX.md` to find the
   feature, open its slice in `Docs/ai/codemap/features/<id>.json`, and read only the files and
   functions it names. Search with `python3 .claude/codemap/codemap.py find <words>`,
   `owner <path>` or `refs <Symbol>`. Some large files must never be read whole: find the symbol
   with `grep -n`, then read that range.
   - `OpenIntelligence/Services/Document/Processing/DocumentProcessor.swift`: about 10,700 lines.
   - `OpenIntelligence/Services/RAG/Orchestration/RAGService.swift`: about 22,800 lines.
2. **Plan before editing.** Before the first edit of a task, write a plan that lists every file
   you'll touch and what changes in each, then wait for the owner's approval (`PROCEED: IMPLEMENT`
   or an equally explicit OK). A request that only asks for a plan ends with the plan.
3. **Show the evidence.** Never say "done", "fixed" or "passes" without showing the command you ran
   and the lines of its output that prove it, such as the test summary (`Executed N tests, with M
   failures`) or `** BUILD SUCCEEDED **`. If something wasn't run, say so.
4. **Record the change.** Every change to the code is added to `Docs/Thesis/FORK_CHANGES.md` (why,
   what, files, verification) and to the 5.7 section of `CHANGELOG.md`, in the same task. A change
   to a method, or a new measured result, also updates the owner's thesis summary
   `Docs/Thesis/METHODS_SUMMARY.md` (high level, no file names; results table and revision
   history).
5. **Holdout test set.** The 16 EU labour-law questions in `/Users/alagra/Documents/thesis/rag-tests/`
   (`eu_data.json`) are a holdout for the thesis's before/after evaluation. Never tune anything on
   them: don't read their questions or answers to diagnose a failure, don't change code, prompts,
   glossary, patterns or thresholds because of a holdout result, and don't copy them into the
   repository or into another question set. Run them only as a final measurement and record the
   numbers. Tuning uses the Labour Code dev split only.
6. **Commit only when the owner asks.** Never run `git add .`. Add files by name. Never use
   destructive git commands (`reset --hard`, `push --force`, deleting branches) without being asked.

## Files that need the owner's explicit approval

These files hold the fork's identity, so the owner must name them when approving a plan:
`OpenIntelligence.xcodeproj/project.pbxproj`, every `*.entitlements` file, `Info.plist` and the
extensions' `Info.plist` files.

The fork's identity, which must survive every change and every sync with the original repository:

| What | Value |
|---|---|
| Bundle IDs | `com.openintelligence.app`, plus `.engine`, `.tests`, `.uitests`, `.liveactivities`, `.share`, `.capture` |
| App group | `group.com.openintelligence.app`, also typed into `SharedInbox.swift`, `WidgetSnapshot.swift` and `IngestionLiveActivityWidget.swift` |
| Signing | `DEVELOPMENT_TEAM = ""` (automatic), except the two macOS entries set to `J7R6G54TG4` |
| Entitlements left out | iCloud, Private Cloud Compute, background GPU, associated domains (`applinks:`), until the thesis account has them |

## Build and test

- Run `scripts/check_icloud_conflicts.sh` first if a build fails for no clear reason. The repository
  is in iCloud-synced `~/Documents`, which can create duplicate `Foo 2.swift` files.
- Smoke build (defaults to the iPhone 18 Pro simulator; set `OPENINTELLIGENCE_SIMULATOR_DESTINATION`
  to use another):

  ```bash
  bash scripts/build_simulator_smoke.sh
  ```

- Tests, using a `-derivedDataPath` outside `~/Documents`, with `-only-testing:` to run a subset:

  ```bash
  xcodebuild test -scheme OpenIntelligence -destination "platform=iOS Simulator,name=iPhone 18 Pro" -derivedDataPath /private/tmp/oi-build
  ```

- The iOS Simulator has no Apple Intelligence, so it can't write answers. Anything about the model's
  answers, speed or memory has to be checked on a real device (the owner's M3 MacBook Pro or an
  iPhone).

## Syncing with the original repository

The original repository is the git remote `upstream` (https://github.com/Gunnarguy/OpenIntelligence).
When merging `upstream/main`:
- the fork's identity (table above) wins in the project file, entitlements and the three Swift
  files;
- the fork's guardrail changes win: `DomainIsolationService` and the medical checks in
  `SourceOnlyAnswerService` stay removed, and so does the old gate I (`FORK_CHANGES.md`
  sections 2.5 and 2.10); the new gate I is the legal statutory-isolation gate (2.11.5);
- the 5.7 section of `CHANGELOG.md` keeps only fork changes.

## Where things are (verified 2026-10-22; confirm line numbers before use)

| Topic | Location |
|---|---|
| OCR of scanned PDF pages and photos | `parsePageImage` in `Services/Document/Processing/StructuredDocumentParser.swift` (runs Vision's document reader) |
| OCR fallback | `performOCR` in `Services/Document/Processing/DocumentProcessor.swift` |
| OCR quality filter (checks text against common English words, so it can drop correct Greek) | `validateAndCleanOCR` in `StructuredDocumentParser.swift` |
| Page language decision (first 2,000 characters of a page) | page cleanup step in the ingestion pipeline (find with `codemap.py find language`) |
| Stricter match bar for "touchy" questions (whole words since 2.11.5) and Greek legal mode | `detectTouchyQuery` in `Services/RAG/Safety/VerificationGateService.swift`; `LegalVerificationPolicy.swift` |
| Greek pipeline (OCR router, masker, translator, legal answer review) | `Docs/Thesis/FORK_CHANGES.md` 2.11; resume point `Docs/Thesis/plans/greek-legaltech-progress.md` |
| Record of all fork changes | `Docs/Thesis/FORK_CHANGES.md` |
| Ready-made prompts | `Docs/Thesis/AGENT_PROMPTS.md` |
