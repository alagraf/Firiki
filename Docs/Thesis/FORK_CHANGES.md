# Changes to the original OpenIntelligence code (thesis fork)

This document records every change made to the original OpenIntelligence codebase for the thesis
proof of concept: a Greek-language legal assistant for iPhone, focused on Greek labour law, built on
Apple Intelligence. It is the reference for the thesis's implementation chapter and should be
updated with every further change.

- **Repository:** `OpenIntelligence-main/` (thesis folder)
- **Branch:** `main`. It holds every fork change rebuilt on the original repository's history, plus
  the sync with the original author's latest code (2.7). It was developed as `thesis-sync` and
  renamed to `main` on 2026-10-22. The earlier `main` (the same fork changes before the sync, with no
  shared history) is kept as the backup branch `main-pre-sync`.
- **Original repository:** https://github.com/Gunnarguy/OpenIntelligence (git remote `upstream`);
  the owner's GitHub fork is https://github.com/alagraf/OpenIntelligence
- **Last updated:** 2026-10-22

## 1. Baseline

The original code is the OpenIntelligence app (Swift/SwiftUI, Apple Foundation Models, on-device
RAG) by its original author. The fork started from this commit of the original repository:

| Commit | Date | Description |
|---|---|---|
| `67977e40` | 2026-10-14 | Original author's "5.7: iCloud sends only what changed, …" (the fork point) |

The fork point was identified on 2026-10-22 by comparing the fork's first commit with every
original commit from October 2026. It differs from `67977e40` in only 21 files, all of them the
fork-setup changes in 2.1 and 2.2, and from every other commit in more.

The fork's first commit was originally imported as a standalone snapshot (`e61cbb4`, with no shared
history). On 2026-10-22 the fork's commits were rebuilt on top of `67977e40` with identical file
contents, so every fork change, including 2.1 and 2.2, can now be shown as a git diff against the
original code. The original's `MARKETING_VERSION` at the fork point was 5.3, and its `CHANGELOG.md`
had an unreleased 5.7 section with the original author's own work in progress, which isn't a
thesis change.

## 2. Summary of changes

| # | Date | Commit | Area | Change |
|---|---|---|---|---|
| 2.1 | 2026-10-18 | `0fbc4b16` | Configuration | Own bundle IDs and signing; iCloud, Private Cloud Compute and background-GPU entitlements removed; free document limit raised |
| 2.2 | 2026-10-18 | `0fbc4b16` | Billing and quota | App defaults to the Lifetime tier with no library, document or mode limits |
| 2.3 | 2026-10-18 | `7a160d9d` | UI | Atlas tab and Knowledge Atlas link removed |
| 2.4 | 2026-10-19 | `db296339` | Documentation | Original author's unreleased 5.7 changelog entries removed, keeping only fork changes |
| 2.5 | 2026-10-22 | `f11ce119` | Answer verification | Medical domain-isolation guardrail replaced by an advisory jurisdiction caveat |
| 2.6 | 2026-10-22 | `943e8639` | Answer verification | Jurisdiction caveat applied at the query entry point so every answer path gets it |
| 2.7 | 2026-10-22 | `f0f8fd6a` | Sync | Original author's latest code merged in (139 commits), keeping the fork's identity and guardrails |
| 2.8 | 2026-10-22 | `8f757eb5` | Agent workflow | Original author's agent rules, hooks and routing replaced by the thesis workflow |
| 2.9 | 2026-10-22 | commit after `8f757eb5` | Documentation | Stale retrieval-pipeline note fixed; smoke build defaults to an installed simulator; this record updated |

Commits `2e2d9086` and `10da7226` added and updated this document. Before the history was rebuilt,
2.1–2.6 had the commit IDs `e61cbb4`, `e61cbb4`, `1244d88`, `c73c6d5`, `61218d3` and `7b83c4a`.

### 2.1 Fork and account configuration (`0fbc4b16`)

**Why:** to build and run the app under the student's own Apple ID, without the original
developer's team, App Store products or cloud resources.

**What changed:**
- Bundle identifiers changed to `com.openintelligence.app` and its suffixes `.engine`, `.tests`,
  `.uitests` and `.liveactivities`.
- `DEVELOPMENT_TEAM` cleared, so signing uses automatic Apple ID management.
- iCloud and Private Cloud Compute entitlements removed from `OpenIntelligence.entitlements` until
  the thesis's own developer account and PCC access are set up. The file now holds only
  app-sandbox, audio input, user-selected read-only files and network client.
- `QuotaPolicy.freeDocumentLimit` raised from 5 to 1,000.
- The background-GPU entitlement (`com.apple.developer.background-tasks.continued-processing.gpu`)
  was removed along with iCloud and Private Cloud Compute.
- The original author's bundle ID and team were replaced in other places that hard-code them:
  - the background-task identifiers in `BackgroundTaskService.swift`;
  - the log subsystem in `RouteLog.swift` and its test;
  - a UI test (`ShortcutsSystemTests.swift`);
  - `fastlane/Appfile` and `fastlane/Fastfile`;
  - the StoreKit test configuration's team ID.
- Three keys were removed from `Info.plist`: `ITSAppUsesNonExemptEncryption`,
  `NSSupportsLiveActivities` and `NSSupportsLiveActivitiesFrequentUpdates`.
- Minor housekeeping:
  - `.git.nosync` added to `.gitignore`;
  - a workspace settings file and the audit document `Docs/AUDIT/QUALITY_MODE_VERIFICATION_2026-07-30.md` removed;
  - machine-local paths added to `scripts/verify_doc_claims.py`.

**Files:** `project.pbxproj`, `OpenIntelligence.entitlements`, `Info.plist`, `QuotaPolicy.swift`,
`BackgroundTaskService.swift`, `RouteLog.swift`, `RouteLogLineTests.swift`,
`ShortcutsSystemTests.swift`, `StoreKitConfiguration.storekit`, `fastlane/Appfile`,
`fastlane/Fastfile`, `.gitignore`, `scripts/verify_doc_claims.py`. The full diff, together with 2.2:
`git diff 67977e40 0fbc4b16`.

**Checked 2026-10-22:** bundle IDs, the cleared team, the entitlement contents and
`freeDocumentLimit = 1_000` are all present in the current code.

**Consequence for the thesis:** Private Cloud Compute is unavailable until the
`com.apple.developer.private-cloud-compute` entitlement is granted and added back. That is the one
route that handles Greek well, according to the original author.

### 2.2 Lifetime tier and limits removed (`0fbc4b16`)

**Why:** a research prototype shouldn't be limited by the original app's paid tiers.

**What changed:**
- `EntitlementStore` defaults to `WorkspaceTier.lifetime` with
  `LegacyProtectionState.historicalPaidPurchase`. `reconcileEntitlementsOnLaunch` no longer demotes
  an unlinked StoreKit profile to Free.
- `QuotaPolicy.lifetimeLibraryLimit` is set to `unlimitedLibraryLimit` (`Int.max`). Libraries,
  documents, evidence threads and daily Maximum-mode use are unlimited.
- Settings, the plan upgrade sheet and the terms of service show "Unlimited", using a new
  `libraryLimitDisplayText`.

**Files:** `QuotaPolicy.swift`, `EntitlementStore.swift`, `SettingsView.swift`,
`PlanUpgradeSheet.swift`, `TermsOfServiceView.swift`, `SampleDocumentManager.swift`

**Checked 2026-10-22:** `lifetimeLibraryLimit = unlimitedLibraryLimit` and the `.lifetime` /
`.historicalPaidPurchase` defaults are present.

### 2.3 Atlas tab removed (`7a160d9d`)

**Why:** the Atlas, a knowledge-graph visualisation, isn't needed for the legal assistant and
simplifies the navigation.

**What changed:**
- `ContentView.Tab` no longer has `.visualizations`. The tab bar is Chat, Documents, Database and
  Settings.
- `DocumentLibraryView` no longer takes `onViewVisualizations`.
- Screenshot-mode tab names that pointed at the Atlas ("visualizations", "telemetry", "atlas") now
  open Database.
- The "Knowledge Atlas" link is removed from the Developer diagnostics screen.
- `AdaptiveVisualizationsView` itself isn't deleted; it is just no longer reachable.

**Files:** `OpenIntelligence/App/ContentView.swift`,
`OpenIntelligence/Features/Diagnostics/Hub/DeveloperDiagnosticsHubView.swift`, `CHANGELOG.md`

**Verification (from the changelog entry):** the macOS smoke build succeeded and
`EntitlementProtectionTests` passed (8 tests) on the iOS Simulator.

### 2.4 Changelog trimmed (`db296339`)

**Why:** to keep the 5.7 section of `CHANGELOG.md` to the fork's own changes.

**What changed:** 193 lines of the original author's unreleased 5.7 entries were removed from
`CHANGELOG.md`, for example the Shortcuts actions, JSON Lines import and app links. Documentation
only: the code those entries describe is still in the app.

### 2.5 Medical domain isolation replaced by a jurisdiction caveat (`f11ce119`)

**Problem observed:** answers were replaced with:

> DOMAIN ISOLATION BREACH: Cannot answer reliably. Domain isolation found retrieved evidence in IN VIVO while the query targets IN VITRO.

The pipeline had retrieved relevant evidence and drafted a correct answer, but a guardrail from the
original app replaced it. That guardrail was built for medical and scientific research documents.

**Root cause:**
1. `DomainIsolationService` sorted text into experimental domains (in vitro, in vivo, clinical,
   in silico) using keyword lists matched as **substrings**. Short keywords matched inside ordinary
   words: `iv` in "give" and "civil", `rat` in "generate" and "separate", `um` in "document",
   `po` in "report". Legal prose was therefore classified as laboratory-study evidence.
2. When the question's domain and the evidence's domain disagreed, `SourceOnlyAnswerService`
   abstained before verifying anything. For state-lookup and exact-value questions,
   `RAGService.sourceOnlyOutcomeIfNeeded` kept that abstention, so the user saw the breach message
   instead of the drafted answer.

**Design for the legal fork:** in law, the counterpart of a domain mismatch is a **jurisdiction
mismatch**, for example Cypriot case law retrieved for a question about Greek law. Such evidence
isn't wrong; it isn't binding and can only serve as an interpretive aid. So the evidence is used,
and the answer says what it is.

**Removed:**
- `DomainIsolationService.swift`, deleted.
- `SourceOnlyAnswerService` (the step that rechecks lookup answers claim by claim against the
  sources):
  - the medical pre-check and its abstention;
  - the strict scientific verification mode and its two prompts, which covered dosing, mg/kg
    versus mg/mL, routes of administration and control cohorts;
  - the `SourceOnlyDomainBlockDraft` structured-output schema;
  - the route, dose, duration and control-cohort claim checks.

  Verification always uses the general evidence-grounded mode. Removing the domain blocks also frees
  output tokens in the draft step, which has a 700-token limit.
- The medical refusal message for Gate I in `VerificationGateService`.

**Added: `JurisdictionService`** (`OpenIntelligence/Services/RAG/Safety/JurisdictionService.swift`)
- **Rule-based classification at query time.** Each retrieved chunk is classified as one of Greek,
  EU, ECHR, Cypriot, German, French, Italian, UK, US or unknown. The classifier looks at the chunk's
  text, file name and section path for patterns such as:
  - Greek: statute citations (`ν. 4808/2021`), `ΦΕΚ`, `ΑΠ 1234/2022`, `ΣτΕ`, presidential decrees;
  - EU: directives, regulations, `ΔΕΕ`/CJEU, case numbers such as `C-55/18`;
  - Cypriot: `κυπριακ-`, Δικαστήριο Εργατικών Διαφορών, Επαρχιακό Δικαστήριο;
  - other countries: their codes and courts.
  - Matching is whole-word and ignores accents and case. Greek statute numbers, which Cypriot law
    shares, weigh less than court and gazette names.
- **Nothing is stored.** It works on libraries indexed before the change, and the storage format is
  untouched.
- **Target jurisdiction:** Greek law, unless the question names another country's law. A question
  citing an EU instrument still targets Greek law.
- **Compatibility:** EU law counts as compatible with Greek law (Greece is a member state), and so
  do ECHR sources. Evidence with no recognisable signal is "unknown" and never triggers a caveat, so
  a missed classification stays silent instead of raising a false alarm.
- **Caveat text** is in Greek for a Greek question and in English otherwise. Example:

  > Σημείωση: Μέρος των διαθέσιμων πηγών αφορά το κυπριακό δίκαιο, ενώ το ερώτημά σας αφορά το
  > ελληνικό δίκαιο. Οι πηγές αυτές δεν δεσμεύουν τα δικαστήρια που εφαρμόζουν το ελληνικό δίκαιο
  > και μπορούν να χρησιμεύσουν μόνο ως ερμηνευτικό βοήθημα.

**Changed:**
- Gate I in `VerificationGateService` became `VerificationGate.jurisdiction` ("Gate I:
  Jurisdiction"). It is advisory: it always passes, its details carry the caveat, and its confidence
  is the share of recognised evidence that is compatible with the target.
- `AnswerIntelligenceView` shows the label "Jurisdiction" with a `building.columns` icon.
- The caveat was first added in `RAGService.finalizeResponse`. Section 2.6 moved it.

**Files:** `JurisdictionService.swift` (new), `SourceOnlyAnswerService.swift`,
`VerificationGateService.swift`, `RAGService.swift`, `AnswerIntelligenceView.swift`,
`DomainIsolationService.swift` (deleted), `JurisdictionServiceTests.swift` (new),
`CHANGELOG.md`, `Docs/HOW_IT_WORKS.md`

**Verification:**
- `JurisdictionServiceTests` (10 tests) and the existing Safety suites (`NumericSanityGateTests`,
  `SemanticGroundingClaimTests`): 25 of 25 passed on the iOS 27 simulator (iPhone 18 Pro).
- Full suite: 1,032 tests, 2 failures, 5 skipped. Both failures are billing-format tests that depend
  on the simulator's region ("4,8" vs "4.8", "29 September" vs "September 29"). They touch no
  changed file.
- Simulator smoke build succeeded.
- **Simulator check:** with a Cypriot labour-court document as the only evidence, the question
  "When is severance pay owed?" returned an answer that opened with the English caveat. The
  simulator has no Apple Intelligence, so this was the excerpt-answer path, not a written one.

### 2.6 Caveat applied at the query entry point (`943e8639`)

**Problem observed (reported 2026-10-22):** with the model writing answers, a question asked in
Greek showed no caveat. The mode and documents used weren't recorded.

**Cause found:** in Deep Think and Maximum modes, lookup-style questions go through
`executeAgenticPrecisionLookupIfAvailable`. That path builds its own response and returns without
reaching `finalizeResponse`, where the caveat was added. It isn't confirmed that this explains the
observation; see section 4.

**What changed:**
- `RAGService.query`, the entry point the chat uses, now applies the caveat to every response:
  `generatedResponse` and the structured answer. `queryWithAudit` goes through `query` and is
  covered.
- The caveat is no longer applied in `finalizeResponse`.
- New `JurisdictionService.caveated(_:query:chunks:)`. Applying it twice doesn't duplicate the
  caveat.

**Files:** `RAGService.swift`, `JurisdictionService.swift`, `JurisdictionServiceTests.swift`
(3 new tests), `CHANGELOG.md`

**Verification:**
- `JurisdictionServiceTests` (13 tests) and the Safety suites, 28 of 28 passed on the iOS 27
  simulator; smoke build succeeded.
- **On real hardware (2026-10-22):** the user confirmed the caveat appears in the macOS app on an
  M3 MacBook Pro, with Apple Intelligence writing the answers. The mode and the exact question
  weren't recorded.

### 2.7 Sync with the original author's latest code (`f0f8fd6a`)

**Why:** the original author fixed the bug behind the "DOMAIN ISOLATION BREACH" error, two
import freezes on iPhone, and Greek PDFs whose text was thrown away. They also added a Share
extension, a Lock Screen capture extension and an app group (shared storage between the app and its
extensions).

**How:**
1. The fork's history was rebuilt on the original commit it came from (`67977e40`, section 1), so
   git can see what both sides changed.
2. Then `upstream/main` (`a7276983`, 139 commits since the fork point) was merged. The owner's GitHub
   fork, https://github.com/alagraf/OpenIntelligence, pointed to the same commit when the merge was
   done.

**Rule for conflicts:** the fork's guardrail changes (2.5, 2.6) and identity (2.1) take priority over
the original author's.

| File | Resolution |
|---|---|
| `DomainIsolationService.swift` | Stays deleted, although the original author fixed it. Their new `DomainIsolationTests.swift`, which tests it, is deleted too. |
| `SourceOnlyAnswerService.swift` | The medical checks stay removed. The original author's new features are kept: Apple's money and date detector (`DetectedValueCheck`), and leaving headings out of the rebuilt answer (`claimsToList`). |
| `RAGService.swift` | `query()` keeps the jurisdiction caveat, wrapped around the original author's new per-answer usage tally (`AnswerUsageTally`). |
| `AnswerIntelligenceView.swift` | Deleted, as the original author did. |
| `ContentView.swift` | The original author's new tab style, without the Atlas tab (2.3). |
| `project.pbxproj` | Fork bundle IDs and signing kept; the new extensions get `com.openintelligence.app.share` and `com.openintelligence.app.capture`; the version is now 5.7. The merge had duplicated the UI-test target's objects; the duplicates were removed and the file checked with `plutil -lint`. |
| `OpenIntelligence.entitlements` | iCloud, Private Cloud Compute and background GPU stay removed. The original author's associated domain (`applinks:gunzino.me`, their website) is left out. The app group is `group.com.openintelligence.app`. The hardened-process keys are kept. |
| App group in code and extensions | `group.com.openintelligence.app` in `SharedInbox.swift`, `WidgetSnapshot.swift`, `IngestionLiveActivityWidget.swift`, and the Share and Live Activities extensions' entitlements |
| `CHANGELOG.md` | The 5.7 section keeps only fork entries (2.4). |
| `Docs/HOW_IT_WORKS.md` | The original author's new wording for gates G and H, and the fork's Jurisdiction row for gate I. |

**Verification:**
- Smoke build on the iPhone 18 Pro simulator: `** BUILD SUCCEEDED **`.
- Full test suite: `Executed 1376 tests, with 8 tests skipped and 3 failures`.
  - The three failures all check number and date formatting: `AnswerUsageTallyTests` ("1.100" vs
    "1,100"), `AppStoreRatingSnapshotTests` ("4,8" vs "4.8") and `LaunchSaleTests`
    ("29 September" vs "September 29").
  - They fail because this Mac's region is Greece (`en_US@rg=grzzzz`), not because of the fork. The
    last two failed the same way before the sync.
- Not yet checked on a device: the import freeze fixes, the Greek PDF fix, and the two new
  extensions with the fork's app group.

### 2.8 Agent workflow replaced (`8f757eb5`)

**Why:** the original author's agent rules told every agent to:
- read the original app's documentation set;
- run their RepoOS routing script;
- update their Notion roadmap;
- follow their App Store release gates.

That costs tokens and doesn't apply to a thesis. `DocumentProcessor.swift` (about 10,700 lines) and
`RAGService.swift` (about 22,800 lines) are too large to search blindly.

**What changed:**
- `AGENTS.md` is the single rule set for every agent:
  - roles: Claude Code plans; Antigravity executes approved plans, using the Argon model for large
    reading jobs;
  - find code through `Docs/ai/codemap/INDEX.md`;
  - plan and wait for approval before editing;
  - show build and test output instead of saying "done";
  - record every change here;
  - the files that need explicit approval, the fork's identity, build and test commands, the
    upstream sync rules, and where the OCR and quality-filter code is.
- `CLAUDE.md` imports `AGENTS.md` and adds the planner role; `GEMINI.md` adds the executor role.
- Antigravity's always-on rule is `.agents/rules/00-thesis.md`, and its one workflow is
  `.agents/workflows/record-change.md`.
- `Docs/Thesis/AGENT_PROMPTS.md` holds ready-made prompts, including one that plans a second OCR
  engine. Approved plans go in `Docs/Thesis/plans/`.
- `HANDOFF.md`, `.geminirules` and `.agents/AGENTS.md` now point at the new files.
- Removed:
  - the Claude Code hooks and their settings;
  - the six process rules in `.claude/rules/`;
  - the Notion, handoff, orient, context-audit, claim-audit and repo-map skills;
  - the `.codex` routing skill;
  - the Antigravity routing and Notion rules and workflows;
  - five scripts that only served the removed hooks.
- Kept: the codemap tool (`.claude/codemap/`) and the `apple-api-truth` and
  `diagnose-before-claiming` skills.

### 2.9 Documentation and tooling fixes

- `Docs/RETRIEVAL_PIPELINE.md` no longer describes `DomainIsolationService`. It points to
  `JurisdictionService` and this document.
- `scripts/build_simulator_smoke.sh` defaults to the iPhone 18 Pro simulator, which is installed,
  instead of the iPhone 17 Pro.

## 3. How to inspect the changes

Every fork commit since the fork point (`--first-parent` hides the original author's merged commits):

```bash
git log --oneline --first-parent 67977e40..main
```

One change, for example the jurisdiction caveat:

```bash
git show f11ce119 --stat
```

Everything the fork changes compared with the original author's latest code:

```bash
git diff upstream/main main -- OpenIntelligence
```

## 4. Open items and known limitations

- **iPhone check pending:** the caveat has been seen working on macOS (M3 MacBook Pro), but not yet
  on an iPhone. For a complete record, check a Greek question in each mode (Standard, Deep Think,
  Maximum); Deep Think and Maximum lookups are the path fixed in 2.6.
- **Jurisdiction is recognised from text patterns only.** A chunk with no citation, court or gazette
  signal is "unknown". Court authority (for example Areios Pagos plenary decisions versus
  lower courts) and whether a provision was in force on the date of the facts aren't handled yet;
  both need per-document legal metadata.
- **Device checks after the sync (2.7):** import freeze, Greek PDFs, and the Share and Lock Screen
  capture extensions with the fork's app group still need checking on an iPhone.
- **Live Activities:** the fork setup (2.1) removed `NSSupportsLiveActivities` and
  `NSSupportsLiveActivitiesFrequentUpdates` from `Info.plist`, so import progress Live Activities may
  not appear. It isn't confirmed whether this was intended.
- **Original author's web links remain:** the privacy-policy and terms links and the web form of
  app links (`AppNavigationRequest.webHost`) point to the original author's website, `gunzino.me`.
  With the associated domain left out (2.7), web links won't open the fork's app.
- **Region-dependent tests:** three tests fail under a Greek region (2.7). Run the suite with a US
  region, or update the tests, to get a clean result.
- **Not yet acted on:** the original author's guidance on Greek handling (sections 2–6 of the owner's
  to-do list):
  - `validateAndCleanOCR` can drop correct Greek text;
  - a page that starts in English can lose its Greek lines;
  - the "legal"/"financial" stricter match bar applies even inside words;
  - the Greek OCR model and translation placement.
- **Observation, not a fork change:** for a Greek Cypriot labour-court document, the app's automatic
  document summary rendered "αποζημίωση απόλυσης" (severance pay) as "notice of termination". This
  is relevant to the thesis's Greek-language accuracy work.

## 5. Authorship note

The changes in sections 2.5 to 2.9 were implemented with the help of Claude Code (Anthropic). Each
of those commits carries a `Co-Authored-By` trailer.
