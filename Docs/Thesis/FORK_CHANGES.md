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
- **Last updated:** 2026-11-13

> **The app is now called Firiki (2026-11-13).** Paths and names in this file are kept as they were
> when written. Today's equivalents: `OpenIntelligence/` → `Firiki/`, `OpenIntelligenceTests/` →
> `FirikiTests/`, `OpenIntelligenceUITests/` → `FirikiUITests/`, `OpenIntelligenceCapture/`,
> `…LiveActivities/`, `…Share/` → `FirikiCapture/`, `FirikiLiveActivities/`, `FirikiShare/`,
> `OpenIntelligence.xcodeproj` → `Firiki.xcodeproj`, scheme `OpenIntelligence` → `Firiki`, engine
> `OpenIntelligenceEngine` → `FirikiEngine`, types `OpenIntelligence*` → `Firiki*`, bundle IDs
> `com.openintelligence.app…` → `com.alagraf.firiki…`, app group → `group.com.alagraf.firiki`, links
> `openintelligence://` → `firiki://`, environment variables `OPENINTELLIGENCE_*` → `FIRIKI_*`.
> Billing, plans and limits were removed at the same time. See "13 Nov 2026 (second entry)".

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
| 2.9 | 2026-10-22 | `97604145` | Documentation | Stale retrieval-pipeline note fixed; smoke build defaults to an installed simulator; this record updated |
| 2.10 | 2026-10-23 | commit after `6b221e5d` | Answer verification | Jurisdiction caveat removed (2.5's caveat and 2.6); the medical check stays removed |
| 2.11 | 2026-10-28 | branch `thesis/greek-legal-rag` | Greek pipeline | Greek labour-law RAG plan (`Docs/Thesis/plans/greek-legaltech.md`), one subsection per phase |

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

### 2.5 Medical domain isolation replaced by a jurisdiction caveat (`f11ce119`; caveat removed in 2.10)

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

### 2.6 Caveat applied at the query entry point (`943e8639`; removed in 2.10)

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

### 2.10 Jurisdiction caveat removed

**Why:** on 2026-10-23 the owner reported that the caveat doesn't actually work and asked for it to
be reverted. The cause wasn't investigated. The removal of the medical domain-isolation check (2.5)
is kept, so the "DOMAIN ISOLATION BREACH" error can't return. Nothing replaces it; answers no longer
carry any jurisdiction note.

**What changed:**
- `JurisdictionService.swift` and `JurisdictionServiceTests.swift` (13 tests) deleted.
- `RAGService.query` returns the answer directly again. It is now identical to the original
  author's latest version.
- Verification gate I (`VerificationGate.jurisdiction`) removed. The fork runs gates A–H, so the
  overall confidence is the average of eight gates instead of nine. Gate I always passed, so the
  average can come out slightly lower than before.
- The Settings capability list now says "Verification Gates A–H" and "8-stage" instead of "A–I" and
  "9-stage".
- Comments and docs updated: `SourceOnlyAnswerService.swift`, `VerificationGateService.swift`'s
  header, `Docs/HOW_IT_WORKS.md` (Gate I row removed, with a note that the fork runs eight checks),
  `Docs/RETRIEVAL_PIPELINE.md`, `AGENTS.md`.

**Files:** `JurisdictionService.swift` (deleted), `JurisdictionServiceTests.swift` (deleted),
`RAGService.swift`, `VerificationGateService.swift`, `SourceOnlyAnswerService.swift`,
`SettingsView.swift`, `Docs/HOW_IT_WORKS.md`, `Docs/RETRIEVAL_PIPELINE.md`, `AGENTS.md`,
`CHANGELOG.md`

**Verification:** see the commit message for the build and test results.

### 2.11 Greek labour-law RAG pipeline (branch `thesis/greek-legal-rag`)

**Why:** to carry out the owner's implementation plan `Docs/Thesis/plans/greek-legaltech.md`
(Greek OCR, Greek legal identifier masking, on-device el↔en translation, bilingual storage and
retrieval, legal verification gates and strict abstention). Progress and the resume point are in
`Docs/Thesis/plans/greek-legaltech-progress.md`. Where the plan and the fork differ, the progress
file says what was decided.

#### 2.11.1 Phase 1: strict local control (thesis requirement R1.1–R1.4)

**What changed:**
- New `StrictLocalControlGuard` (`Services/Infrastructure/Configuration/`; the plan's
  `Services/Security/` is not a folder the engine framework compiles). Strict local mode is on unless
  the `thesis.strictLocalMode` default is set to false.
- R1.1: `OpenIntelligenceRuntimePaths` marks the Application Support root (and any overridden base
  or local-cache folder) `isExcludedFromBackup`, so the SQLite database and vector store under it
  stay on the device.
- R1.2: `WorkspaceSyncService` resolves the iCloud Drive container through the guard, which returns
  nil in strict mode, so workspace sync never starts.
- R1.3: `WebPageFetchService.fetch` throws `remoteIngestionBlocked` before any request in strict
  mode. This covers every web-address import path (Save a Web Page, Add to Library's link field,
  pasted addresses, the share sheet).
- R1.4: `StrictLocalControlGuard.canUsePCC()` requires the signed PCC entitlement and that the user
  hasn't chosen "Never Allow" for cloud transmission. `FoundationModelSessionFactory` checks it
  before creating `PrivateCloudComputeLanguageModel`, and `FoundationModelCapabilityProvider` before
  reporting PCC available, which is what `ModelExecutionPlanner` routes on.
- Plan step 1.1 (quota, iCloud/PCC entitlements) was already done in 2.1/2.2.

**Files:** `StrictLocalControlGuard.swift` (new), `OpenIntelligenceRuntimePaths.swift`,
`WorkspaceSyncService.swift`, `WebPageFetchService.swift`, `FoundationModelSessionFactory.swift`,
`FoundationModelCapabilityProvider.swift`, `GreekLegalPipelineTests.swift` (new)

**Verification:** `StrictLocalControlGuardTests` (6 tests: default on, folder and Application
Support root excluded from backup, iCloud and web import blocked, PCC needs entitlement and no
refusal) pass on the iPhone 18 Pro simulator; full build succeeded.

Follow-up: the full suite then showed three tests that download a web page
(`ShortcutsActionTests.testAddToLibraryTakesAFileALinkAndTextInOneRun`,
`testSaveAWebPageImportsTheArticlesText`) or check a non-web address
(`WebPageFetchServiceTests.testOnlyWebAddressesAreFetched`) failing. The address is now checked
before the strict-mode refusal (a non-web address is still `unsupportedAddress`), and the two
download tests switch strict mode off for their own run.

#### 2.11.2 Phase 2: Greek legal entity masker and bilingual chunk storage

**What changed:**
- New `GreekLegalEntityMasker` (`Services/Document/Localization/`): NFKC normalization (the micro
  sign U+00B5 becomes Greek mu U+03BC), Greek guillemets to quotes and prime-like marks to `'`
  (before NFKC, which would turn the tonos U+0384 into a space and an accent); a deterministic
  lexer for laws (`Ν. 4808/2021`), presidential decrees, ministerial decisions, articles,
  paragraphs and `εδ.`, Government Gazette issues (`ΦΕΚ Α' 101/19.06.2021`), court decisions (ΑΠ,
  ΟλΑΠ, ΣτΕ, ΕφΑθ) and EU directives, in Greek and in English, each with a canonical key
  (`ART:38`, `LAW:4808/2021`, `FEK:Α:101:19.06.2021`). `maskEntities` replaces each occurrence with
  `__LEX_ENT_001__`…; `unmaskEntities` restores them as bilingual anchors
  (`Article 38 [Άρθρο 38]`), as the Greek wording, or in English, and tolerates placeholders a
  translator has re-cased or re-spaced. Overlapping matches go to the earlier rule (gazette before
  law, so `ΦΕΚ Α' 101/2021` isn't read as a law).
- Deviation from the plan: `LegalEntityRecord` also has `canonicalEl` ("Άρθρο 38"), so an anchor
  reads `Article 38 [Άρθρο 38]` even when the source said `Άρθρου 38`; `verbatimEl` keeps the source
  wording.
- Storage: the plan's `ALTER TABLE document_chunks` has no target (chunk text lives in the FTS5
  table `chunks`, which can't be altered), so the four columns (`source_text_el`, `source_language`,
  `legal_entities_json`, `primary_statute_key`) are a new table `chunk_legal` keyed by chunk id,
  with an index on `primary_statute_key`, created with `IF NOT EXISTS` and deleted together with a
  document's or library's chunks. `DocumentChunk` gains `legal: LegalChunkMetadata?` (decoded as
  absent from chunks saved before) and `sourceTextEl`.

**Files:** `GreekLegalEntityMasker.swift` (new), `DocumentChunk.swift`,
`SQLiteFullTextService.swift`, `GreekLegalPipelineTests.swift`

**Verification:** `GreekLegalEntityMaskerTests` (the plan's
`testGreekEntityMaskingAndNFKC` sentence: mu normalized, 4 entities masked deterministically and
restored as anchors and as Greek; mangled placeholders; 14 identifier forms; plain Greek prose with
numbers gives no identifiers; primary statute) and `BilingualChunkStorageTests` (SQLite round trip
and deletion; old chunk JSON decodes) pass on the iPhone 18 Pro simulator.

#### 2.11.3 Phase 3: Greek OCR and extraction fixes

**Why:** Vision recognizes no Greek, and three text filters silently dropped correct Greek text.

**What changed:**
- ONNX Runtime (`onnxruntime-swift-package-manager` 1.24.x, module `OnnxRuntimeBindings`) linked
  to the app target (`project.pbxproj`, approved by the owner on 2026-10-28). The engine framework
  target doesn't link it; its build compiles the `#if canImport(OnnxRuntimeBindings)` fallback.
- Models in `Resources/MLModels/GreekOCR/`: `PP-OCRv5_mobile_det.onnx` (4.6 MB) and
  `el_PP-OCRv5_mobile_rec.onnx` (7.4 MB) from Hugging Face `PaddlePaddle/*_onnx` (Apache-2.0) and
  `el_dict.txt` (354 characters, from the recognizer's `inference.yml`). The project file excludes
  them from the engine framework target so the app doesn't carry them twice.
- New `GreekPaddleOCRService`: DB text detection (long side 960, multiple of 32, BGR ImageNet
  normalization, threshold 0.3, box threshold 0.6, unclip 1.5, axis-aligned boxes), crops resized to
  48 px high, CTC greedy decoding. Constants from the models' `inference.yml`. Checked first against
  a Python version of the same steps on a rendered Greek page.
- New `OCRRouterService` with `OCREngineProtocol` and `ocrEngineMode` (`vision`, `greekPaddleOCR`,
  `autoBenchmark`, default `autoBenchmark`, UserDefaults `thesis.ocrEngineMode`). In auto mode Vision
  runs first; when its text has Greek letters or is mostly non-English words, PaddleOCR reads the
  image and wins if it finds Greek. Every engine run is logged as `[OCRBenchmark] site= engine=
  chars= greekLetters= ms=` for the thesis comparison.
- All five call sites routed: `StructuredDocumentParser.parsePageImage` (Greek-hinted pages go to
  PaddleOCR first; misread Vision pages are re-read; the text fallback goes through the router),
  `DocumentProcessor.performOCR`, `LayoutAwareExtractor`'s multi-column pass (lines become blocks
  in Vision coordinates), `IntelligentDocumentProcessor.rescuePageRegions` (and a misread Vision
  table falls back to the text path), `ImageUnderstandingService.extractTextFromImage`.
- `validateAndCleanOCR`: text with at least 15% Greek letters is checked against a list of Greek
  function words and labour-law terms instead of the English list.
- Page cleanup (`OCRConfiguration.filterGarbageText`): the whole text is scanned for Greek (10 Greek
  letters make it non-Latin) before the 2,000-character language sample, and a line that is mostly
  Greek never goes through the Latin-only rules.
- `PDFPage.normalizedString`: PDFKit text with Greek in it is NFKC-normalized (micro sign → mu);
  used for every `page.string` read in `DocumentProcessor`, `LayoutAwareExtractor` and
  `PageComplexityAnalyzer`. English pages are unchanged.
- `GreekLegalEntityMasker.repairGreekHomoglyphs` (part of `normalizeGreekText`): on Greek lines,
  Latin look-alikes in Greek words and short capital abbreviations become Greek ("N." → "Ν.",
  "ΦΕK" → "ΦΕΚ", "A'" → "Α'"); OCR output is repaired the same way. PaddleOCR's Greek model returns
  these Latin letters for Greek capitals. Also `collapseBilingualAnchors` (used in phase 4).

**Files:** `GreekPaddleOCRService.swift`, `OCRRouterService.swift`, `PDFPage+Greek.swift` (new),
`GreekLegalEntityMasker.swift`, `StructuredDocumentParser.swift`, `DocumentProcessor.swift`,
`LayoutAwareExtractor.swift`, `IntelligentDocumentProcessor.swift`,
`ImageUnderstandingService.swift`, `OCRConfiguration.swift`, `PageComplexityAnalyzer.swift`,
`Resources/MLModels/GreekOCR/*`, `project.pbxproj`, `Package.resolved`,
`GreekLegalPipelineTests.swift`

**Verification:** `GreekOCRTests` on the iPhone 18 Pro simulator: the plan's
`testGreekOCRAndValidationBypass` renders an Article 66 / Ν. 4808/2021 page with Core Text, reads it
with the real models (word error rate under 5%, `ART:66` and `LAW:4808/2021` recognized) and checks
that `validateAndCleanOCR` keeps a Greek paragraph whole and unflagged; a page whose first 2,000
characters are English keeps its Greek lines; homoglyph repair; the router replaces misread Vision
text with Greek and keeps English. Full suite: `Executed 1363 tests, with 8 tests skipped and 6
failures`: the 3 Greek-region formatting tests plus the 3 web-download tests fixed in 2.11.1's
follow-up; Swift Testing 20 passed.

#### 2.11.4 Phase 4: on-device Greek↔English translation, bilingual ingestion and retrieval

**What changed:**
- Models: Helsinki-NLP `opus-mt-grk-en` and `opus-mt-en-el` exported to ONNX (encoder; decoder with
  LM head and final-logits bias, last position only) and quantized to INT8 (≈80 MB and ≈145 MB), plus a
  JSON tokenizer file each (source SentencePiece pieces and scores, Marian vocabulary, special ids).
  They are made by `scripts/thesis_fetch_translation_models.sh` (`scripts/thesis/convert_opus_mt.py`)
  into `Resources/MLModels/Translation/`, which git ignores (too large to commit). The project file
  excludes them from the engine framework target. A build without them has no Greek translation
  (`LocalNeuralTranslator.isAvailable == false`) and behaves as before.
- New `LocalNeuralTranslator` (actor): SentencePiece unigram tokenizer in Swift (Viterbi over the
  piece scores; ids match `transformers`' `MarianTokenizer` on the tested sentences), greedy decoding
  with ONNX Runtime (padding token never generated), line- and sentence-wise segmentation, an LRU
  cache of 4,096 segments, `[C#]` markers the model drops put back. `translateGreekToEnglishPreservingLegalEntities`
  masks identifiers, translates, restores them as bilingual anchors;
  `translateEnglishToGreekPreservingCitations` collapses anchors, masks identifiers, translates and
  restores them in Greek. Placeholders survive translation (the model sometimes drops one trailing
  underscore, which unmasking tolerates).
- `TranslationService`: Greek↔English (single and batch) goes to `LocalNeuralTranslator` instead of
  Apple's Translation framework, which has no Greek and returned the text untranslated.
- Ingestion (`RAGService`, right after `DocumentProcessor.processDocument`, so native PDF text and
  OCR text alike): a chunk with ≥30% Greek letters keeps its NFKC-normalized Greek text as
  `legal.sourceTextEl` and its content becomes the English translation with anchors; identifiers and
  the primary statute are recorded for every chunk; `chunk_legal` rows are written next to the FTS5
  rows. The plan put this in `DocumentProcessor`; the `RAGService` call site is the first point where
  both extraction paths have produced chunks. Large PDFs (>10 MB) go through
  `importLargePDFStreamed`, which is not hooked yet.
- The BNNS vector store and the chunk copies in `RAGService` and `WorkspaceSyncService` keep
  `DocumentChunk.legal`, so retrieved passages carry their Greek source.
- Query: `translatedQueryForEmbedding` translates a Greek question (≥30% Greek letters) with
  `LocalNeuralTranslator` whatever the library's translation setting.
- FTS5 fix (`HybridSearchService.searchWithFTS5`): for a Greek question with an English translation,
  the keyword query is the translation plus the English form of each identifier in the Greek
  question (`greekAwareLexicalQuery`), not the Greek original. The field weights the plan asks for
  (10× title, 5× section path, 1× body) were already in place.
- Intent (`QueryEnhancementService.classifyAnswerIntent`): a question citing a law, decree, article,
  ministerial decision, directive or court decision is `lookup`, or `compare` with a comparison cue
  (English or Greek).
- Cross-references: `GraphIndexService` gains `article`, `statute` and `gazette` reference types with
  the plan's patterns and resolves article references at ingestion; new `LegalCrossReferences`
  (passage holding an article = text or section title starting with its heading) is used by
  `RAGService.resolveCrossReferencesStandard` at query time.

**Files:** `LocalNeuralTranslator.swift`, `GreekLegalIngestion.swift`, `LegalCrossReferences.swift`
(new), `TranslationService.swift`, `RAGService.swift`, `HybridSearchService.swift`,
`QueryEnhancementService.swift`, `GraphIndexService.swift`, `BNNSVectorDatabase.swift`,
`WorkspaceSyncService.swift`, `project.pbxproj` (resource exceptions), `.gitignore`,
`scripts/thesis_fetch_translation_models.sh`, `scripts/thesis/convert_opus_mt.py`,
`GreekLegalPipelineTests.swift`

**Verification:** `GreekTranslationRetrievalTests` (iPhone 18 Pro simulator, real models): tokenizer
ids equal Marian's; el→en keeps `Article 66 [Άρθρο 66]` and `Law 4808/2021 [Ν. 4808/2021]`; en→el
keeps `Άρθρο 66`, `Ν. 4808/2021`, `[C1]`, `[C2]`; the plan's `testBilingualIngestionAndHybridRetrieval`
(three Greek articles written for the test, Core ML MiniLM embeddings, SQLite FTS5): intent `lookup`,
the Greek question about Άρθρο 66 retrieves Article 66 at rank 1 (R@1 = 1.0) with its Greek source,
content English with `[Ν. 4808/2021]`; article cross-references resolve. Full suite: `Executed 1363 tests, with 8 tests skipped and 3 failures` (the 3 Greek-region formatting tests); Swift Testing 27 passed.

#### 2.11.5 Phase 5: buffered plain-text answers, strict abstention, legal gates, Greek output

**What changed:**
- Greek legal mode (`GreekLegalAnswerContext`, a task-local switch): on for a question with ≥30%
  Greek letters unless `thesis.strictLegalAbstention` is false. `RAGService.query` sets it for the
  whole query, so the Standard, Deep Think and Maximum paths all see it.
- Buffered output: in this mode `query` withholds the stream handler, so no unverified token reaches
  the screen; the answer appears once, after review.
- Plain text at temperature ≤ 0.2: `generateWithFallback` skips the `@Generable` structured answer
  and caps the temperature.
- Strict abstention: the hard relevance gate also refuses (no model call) when the top passage scores
  under 0.20, or under 0.30 with no word or identifier of the question in it; the reliability-mode
  fallbacks (second generation attempt, raw passages as the answer) are off; a pipeline error becomes
  the Greek abstention.
- Review (`GreekLegalAnswerFinalizer`, `GreekLegalAnswerService.swift`): gates A–I run on the English
  draft with legal checks on; a critical failure or composite confidence under 0.5 gives the fixed Greek
  abstention message, otherwise the draft is translated to Greek (`LocalNeuralTranslator`, identifiers
  and `[C#]` kept). `RAGResponse.legalReview` holds the English draft, gate summary and decision; the
  structured answer is dropped for these responses.
- Gates (`VerificationGateService`, new `LegalVerificationPolicy`): with legal checks on, gate A uses
  the 0.55 threshold; gate C reads Greek numbers and dates (`1.200,50`, `19.06.2021`) and counts the
  Greek source as evidence; gate F fails, critically, when a statutory or case-law identifier in the
  answer is in none of the passages; new gate I (`statutoryIsolation`, critical) fails when the
  question names a statute and every passage that cites a statute cites only others. Gate I is not run
  outside legal mode, so English answers still average gates A–H. The touchy-topic check now matches
  whole words ("illegal" no longer counts as "legal").
- `SourceOnlyAnswerService`: labour-law words (and Greek stems) and Greek legal mode use the 0.88
  fidelity bar.
- Citation views (`ResponseDetailsView`, `GroundedAnswerView`): a translated passage shows its Greek
  source text, with the English translation under "English translation (technical details)"; the page
  highlight uses the Greek text.
- `LLMService` logs `[ModelAsset] assetIDs=…` from the session transcript after each generation.
- New `LegalSLMEnricherProtocol` and `LegalSLMEnricherRegistry`: an optional enricher's evidence brief
  (≤300 tokens) is put in front of the context in `generateWithFallback`; none is registered by default.
- Already in place, not changed: `ModelExecutionPlanner`/`FoundationModelTokenBudget` read
  `SystemLanguageModel.default.contextSize`; PCC is guarded since 2.11.1.

**Not done / limits:** thresholds (0.20/0.30, composite 0.5) need
calibrating on a device, since the simulator can't generate answers; a model refusal is turned into
the abstention, not retried.

**Files:** `GreekLegalAnswerService.swift`, `LegalVerificationPolicy.swift`,
`LegalSLMEnricherProtocol.swift` (new), `RAGService.swift`, `RAGQuery.swift`,
`VerificationGateService.swift`, `SourceOnlyAnswerService.swift`, `LLMService.swift`,
`ResponseDetailsView.swift`, `GroundedAnswerView.swift`, `GreekLegalPipelineTests.swift`,
`scripts/thesis_run_tests.sh`

**Verification:** `GreekLegalVerificationTests` (iPhone 18 Pro simulator): the plan's
`testGateFHallucinatedArticleRejection` (a draft citing Article 99 when the passage has Article 38 fails
gate F critically and is replaced by the Greek abstention, nothing translated),
`testGateILegalConstitutionNoFalseBreach` (the Members-of-Parliament question in English and Greek
passes gate I with no domain-isolation text; a Ν. 4808/2021 question over Ν. 3863/2010-only passages
fails), `testStrictAbstentionBelowThreshold` (score 0.15 abstains without running the gates), a verified
draft is translated, Greek numerals, gate C on Greek numbers. Full suite: `Executed 1363 tests, with 8
tests skipped and 3 failures` (the 3 Greek-region formatting tests); Swift Testing 33 passed.

#### 2.11.6 Greek legal review under Response Details

**Why:** the review of a Greek answer (gates, English draft, model) was only in the log.

**What changed:**
- `LegalAnswerReview` is `Codable` and kept in `ResponseMetadata.legalReview`, so it is saved with the
  chat message (messages saved before decode with no review). It holds each gate's result
  (`GateLine`), the English draft, the question as the gates read it (its English translation) and
  the model asset ids.
- `ModelAssetRecorder`: `RAGService.query` hands one to the Greek legal query as a task-local value;
  `LLMService` records the asset ids of each generation into it (and still logs them).
- New `GreekLegalReviewCard` under Response Details, after the verification summary: verified and
  translated, or abstained with the reason; gate confidence; one line per gate (pass/fail and detail);
  model and model assets; the English draft and the question in a "technical details" disclosure.

**Files:** `GreekLegalReviewCard.swift` (new), `ResponseDetailsView.swift`, `RAGQuery.swift`,
`GreekLegalAnswerService.swift`, `RAGService.swift`, `LLMService.swift`, `GreekLegalPipelineTests.swift`

**Verification:** `GreekLegalReviewDetailsTests` (review with gates, question and asset ids is in the
response metadata and survives a JSON round trip; old metadata decodes with none; the abstention
response carries its review; asset ids recorded once) and `GreekLegalVerificationTests` pass on the
iPhone 18 Pro simulator (`Test run with 9 tests in 2 suites passed`). The card's layout was not
checked on screen.

#### 2.11.7 Fix: Greek questions about a person failed (owner's report, 2026-10-28)

**Why:** with the owner's document "Η Εσπεράντο στην Ελλάδα του 2026" (a first-person essay by
Ανδρέας Ζέρβας), "Ποιός είναι ο Ανδρέας Ζέρβας" and "Who is Ανδρέας Ζέρβας" got a failure, "Who is
Andreas Zervas" an answer. Reproduced on the iPhone 18 Pro simulator by importing the document:
1. Opus-MT rendered the name differently in the question ("Andrew Zervas"; the mixed question became
   "Who is Men Zerva") than in the indexed document ("Andreas Zervas"), so the best passage scored
   0.37 instead of 0.62.
2. Greek legal mode applied the legal gate A threshold (0.55) to every Greek question, so 0.37 failed
   gate A and the answer was replaced by the abstention.
3. The PDF's text has a line break inside most sentences; translated line by line, fragments came
   back as invented text ("προκλήσεις και προοπτικές" → "The Commission will continue its efforts…"),
   and so did chunks that start in mid-sentence.
4. A pipeline failure text ("Unable to synthesize answer from reasoning chain.") passed the review and
   was translated and shown as an answer.

**What changed:**
- `GreekLegalEntityMasker`: new entity type `properName`: two or more consecutive capitalized Greek
  words (leading function words such as "Στην", "Η" dropped; all-caps headings and Latin words not
  names), transliterated by ELOT 743 (`transliterate`: "Ανδρέας Ζέρβας" → "Andreas Zervas") and kept
  out of the translation model like the legal identifiers, so the document and every question read
  "Andreas Zervas [Ανδρέας Ζέρβας]". Names are not legal identifiers for the legal-question check or
  gate F.
- `LocalNeuralTranslator`: segments with no Greek (placeholders aside) skip the Greek→English model
  ("Who is __LEX_ENT_001__" stays as it is); `reflow` rejoins lines wrapped in mid-sentence before
  translation; a segment starting in lower case is translated as "… segment" and the ellipsis dropped.
- Gate A's 0.55 threshold and the source-only 0.88 bar apply in Greek legal mode only when the
  question is a legal one (`LegalVerificationPolicy.isLegalQuery`).
- `GreekLegalAnswerFinalizer`: a refusal (`structuredAnswer.refuse`) or a pipeline failure/not-found
  text is an abstention, never translated.

**Verification:** with the owner's PDF imported in the simulator, all three questions now translate
to "Who is Andreas Zervas [Ανδρέας Ζέρβας]", retrieve the author's passage at 0.62 and pass gate A at
τ = 0.40 (diagnostic test, not kept: it reads the PDF from outside the repository). New tests:
`GreekNameQuestionTests` (transliteration, names found and not found, Greek and mixed questions match
the document, gate A threshold for non-legal vs legal questions, failure text abstains), `ReflowTests`,
`FragmentTranslationTests`. Full suite: `Executed 1363 tests, with 8 tests skipped and 3 failures` (the
3 Greek-region formatting tests); Swift Testing 42 passed. Answer generation not checked (Simulator).
Known limit: Opus-MT still mistranslates some rare words ("Εσπεράντο" → "Esperado", "σκυτάλη").

#### 2.11.8 Suggested questions removed; Greek engines in the Processing Log

**Why:** the owner asked for no suggested questions in the UI, and for the import's Processing Log
to say when PaddleOCR reads a file and when Opus-MT translates it.

**What changed:**
- `SuggestedQuestionsService.isEnabled` (false): the empty chat shows no starter questions and no
  refresh button ("Ask a question about the documents in this library."), no follow-up chips appear
  after an answer, and no questions are generated at import or for the chat (which saves model
  calls). The service and its code stay, so the switch can be turned back on.
- New `IngestionLogRecorder`: the import passes it down as a task-local value; `OCRRouterService`
  reports every PaddleOCR run to it (and whether its text was kept). The Processing Log gets
  "Greek OCR: PaddleOCR PP-OCRv5 (Greek model, on device) is reading this file's images…" at the
  first use and a summary after extraction ("PaddleOCR (paddle-el-v5) read N images, its text kept
  for M, C characters, in S s"). Translation adds "Translation: Opus-MT (opus-mt-grk-en, on device)
  is translating N Greek passages to English" and "Opus-MT translated X of N Greek passages in S s",
  and the import's status reads "Translating Greek text with Opus-MT (on device)...".
  `RAGService.appendIngestionEvent` adds a log line without changing the import's stage.
  `[OCRBenchmark]` log lines now include `used=`.
- Not covered: PDFs over 10 MB (streamed import path), as for translation.

**Files:** `SuggestedQuestionsService.swift`, `ChatScreen.swift`, `IngestionLogRecorder.swift` (new),
`OCRRouterService.swift`, `RAGService.swift`, `GreekProcessingLogTests.swift` (new)

**Verification:** `GreekProcessingLogTests` (iPhone 18 Pro simulator): a scanned (image-only) Greek
PDF imported through Add to Library gets the two PaddleOCR lines and the two Opus-MT lines in its
Processing Log; suggested questions are off. Full suite: `Executed 1363 tests, with 8 tests skipped
and 3 failures` (the 3 Greek-region formatting tests); Swift Testing 44 passed. The empty chat
screen was not looked at on screen.

#### 2.11.9 Greek Constitution accuracy: article lookup, Greek keyword arm, whole provisions

**Why:** the owner reported that "Τι αναφέρει το Άρθρο 1 του Συντάγματος;" was answered from a
transitional provision, and "ποιός είναι ο Ανδρέας Ζέρβας" was refused after gate E failed, and
asked for the owner's 10-question Constitution set (`Benchmarks/GreekConstitution/syntagma_qa_v1.jsonl`,
over `syntagma1_1.pdf`) to be evaluated and fixed without hard-coding answers.

**Evaluation:** new opt-in `GreekConstitutionEvaluationTests` runs the set through the whole app path
in the iOS 27 Simulator: import of the PDF, then `RAGService.query` per Greek question with Apple's
on-device model (the test hands the engine a model of its own, as `AnswerQualityEvaluationTests`
does). An answer passes when it contains every key fact of its case (regular expressions over the
lower-cased, accent-free answer); the table also says whether a passage holding the expected article
was retrieved. The imported library is kept between runs (`TEST_RUNNER_OI_GREEK_EVAL_REIMPORT=1`
imports again). Runs:

| Run | Change | Passed | Expected article retrieved |
|---|---|---|---|
| 1 | baseline (opus-mt-grk-en) | 6/10 | 6/10 |
| 2 | Greek→English with opus-mt-tc-big-el-en (2.11.10) | 5/10 | 8/10 |
| 4 | + Greek keyword arm, grading fix for "εικοστή πέμπτη" | 7/10 | 8/10 |
| 5 | + whole provisions, permissive guardrails, tc-big both ways, decoder cache (re-import, 487 s) | 6/10 | 5/10 |
| 6 | + two following sentences instead of whole passages | 6/10 | 7/10 |
| 7 | + legal glossary (re-import, 463 s), continuation up to 4 passages, Greek-mode instruction | stopped at Q8: 7 of 8 passed | – |
| 8 | + greedy decoding in Greek legal mode | 6/10 | 8/10 |
| 9 | + number words in gates B and C, softened instruction | 7/10 | 7/10 |

(Run 3 was stopped: its Greek index matched nothing, fixed before run 4. Runs 6, 8 and 9 reused the
library imported in run 7 or 5; run 7 was cut off by the session's usage limit. Run 9 took 796 s.)

Run 9 per question: PASS 1, 3, 4, 6, 7, 8, 9; FAIL 2, 5, 10.
- Q2 (200–300 MPs): the English draft was right ("not less than two-hundred nor more than three
  hundred", Article 51), and with the number-word fix the gates passed it (in run 8 gate B
  refused it); the English→Greek translation wrote "τρία εκατοντάδες", which the key fact
  `300|τριακοσι` does not match. Fixed in the next round (2.11.11: digits before translation).
- Q3 (age 25, Article 55): fixed by the number-word reading in gate C ("εικοσιπέντε χρόνια").
- Q5 (Armed Forces): the draft named Article 87 and an unnamed "leader"; gate B found its claims
  only partial and the app abstained. A refusal instead of run 8's wrong answer, still a fail.
- Q10 (Article 120 §4): §4 did not reach the prompt; structure-aware chunking (2.11.11) addresses it.

**Causes found and what changed:**
- **The PDF draws Greek with Latin look-alike glyphs** ("Άρθρo 1" with a Latin o, "MEPOΣ",
  "To πoλίτευμα"). `repairGreekHomoglyphs` now also converts a token made only of look-alike letters
  on a Greek line.
- **Article headings were lost:** line rejoining before translation merged "Άρθρο 1" into the line
  before it. `reflow` keeps an article heading, or a line that is only a masked identifier, on its
  own line. `LegalCrossReferences.articleHeadings` finds every article whose heading is a line of
  its own in a passage (a table-of-contents line is not a heading), with where it starts.
- **Article lookup:** a question naming an article gets, first in the context, the passage holding
  that article (the one whose heading comes earliest), found among the candidates or in the
  library, followed by up to two continuation passages of the same document before the next
  heading (`LegalCrossReferences.pinningRequestedArticle`, in `RAGService` before ordering).
- **Greek mode ran the pipeline on the Greek question.** The prompt carried the Greek question, the
  model answered in Greek, and gate E compared a Greek answer with English passages through an
  English embedding model and failed (the Ζέρβας refusal). `RAGService.query` now runs the whole
  pipeline on the English translation; the Greek question is kept in
  `GreekLegalAnswerContext.originalQuestion`.
- **Greek keyword arm** (the plan's bilingual dual index): new FTS5 table `chunk_greek` with each
  translated chunk's original Greek text, folded in Swift (accents removed, lower case, final sigma
  as sigma; SQLite's tokenizer keeps Greek accents). For a Greek question its content words (Greek
  and parser stop words removed) become stem prefixes ("προφυλάκισης" → `"προφυλακισ"*`) joined
  with OR; the hits are interleaved with the English keyword hits before fusion. A question's own
  words find the paragraph the translation paraphrased ("τήρηση του Συντάγματος επαφίεται").
- **Names:** a pair of capitalized Greek words is as often "Κοινοβουλευτική Δημοκρατία" as a
  person. Names are now translated in context and their ELOT 743 transliteration is added after
  the text; they stay masked only in a text that is not Greek apart from them.
- **Following sentences:** sentence extraction (for lookup questions) kept only the sentences
  sharing words with the question and dropped a provision's exception or deadline in the next
  sentence (Article 6: "six more months", "within three days"). Run 5 put passages into the prompt
  whole in Greek legal mode; from run 6 that was replaced by a narrower change: a chosen sentence
  brings the two sentences after it in its passage (`followingUnits`), so the 4,096-token context
  still holds passages from several articles.
- **Guardrails:** Apple's default guardrails refused to restate Article 120 §4 (the duty to resist
  anyone abolishing the Constitution "by force"). In Greek legal mode the on-device model is
  `SystemLanguageModel(guardrails: .permissiveContentTransformations)`, Apple's setting for
  transforming text the user supplies, with plain-text output only; everything else keeps the
  default (`greekLegalAwareOnDeviceModel`, `FoundationModelSessionFactory`).
- **Legal glossary** (after run 5): `GreekLegalEntityMasker` masks a few legal terms as `legalTerm`
  entities with one English rendering each ("πολίτευμα" → "form of government", "Ακροτελεύτια
  διάταξη" → "final provision", "προφυλάκιση" → "pre-trial detention", "Ένοπλες Δυνάμεις" → "Armed
  Forces", in every case form), so a question and the passage use the same English words.
- **Article continuation** up to four passages after the passage holding the requested article
  (was two).
- **Prompt:** in Greek legal mode the question carries "State every number, time limit, condition
  and exception that the excerpts give for this question" (run 5 answered "one year" for
  pre-trial detention without the six-month extension). Run 8 showed it also produced filler ("The
  document does not specify a time limit") and an invented "Chief of the Armed Forces", so it now
  ends "…; do not mention ones they do not give" and asks for the excerpts' own words for who or
  what they name (run 9).
- **Greedy decoding** in Greek legal mode (`GenerationOptions(samplingMode: .greedy)` in
  `LLMService` and in the evaluation's model), so a run is repeatable; the same question no longer
  passes in one run and fails in the next because of sampling.
- **Number words in gates B and C** (after run 8): Q3 drafted "25" but gate C reported "0/1 verified.
  Unverified: 25" and the answer was refused, because the Constitution writes "εικοστό πέμπτο"
  ("twenty-fifth"); Q2's claims about 200 and 300 MPs were only "partial" against "two hundred" /
  "three hundred" and gate B failed (grounded-only mode abstains on any failed gate). New
  `LegalVerificationPolicy.annotatingSpelledNumbers` writes the value after every English or Greek
  number word from 2 to 999 in the evidence ("twenty-fifth (25)", "διακοσίους (200)", compounds
  like "εικοσιπέντε", ordinals, "εκατόν πενήντα"; "one"/"ένα", "έκτος" = except and "εβδομάδα" are
  left alone). In legal mode gate C reads the passages and their Greek source through it, and
  gate B builds its claim corpus and numeric evidence through it. The answer side needs nothing:
  gate C does not count a number the answer writes in words.
- **Logging:** in Greek legal mode a rejected draft and each claim gate B did not support are
  logged (`[GreekLegal] Rejected draft`, `[GreekLegal]   claim …`), so an abstention can be traced.

**Files:** `GreekLegalEntityMasker.swift`, `LocalNeuralTranslator.swift`, `LegalCrossReferences.swift`,
`RAGService.swift`, `HybridSearchService.swift`, `SQLiteFullTextService.swift`,
`GreekLegalAnswerService.swift`, `FoundationModelSessionFactory.swift`, `GreekLegalPipelineTests.swift`,
`GreekConstitutionEvaluationTests.swift` (new), `Benchmarks/GreekConstitution/` (new: the owner's
question set and the PDF), `scripts/thesis_run_tests.sh`

**Verification:** Greek unit suites (iPhone 18 Pro simulator, `/private/tmp/oi-logs/greek11.log`):
`✘ Test run with 57 tests in 15 suites failed after 25.920 seconds with 1 issue`: the one issue
was in the new chunking suite of 2.11.11 (a wrong expectation, fixed there); every suite of this
round passed, including `numberWordsReadAsDigits`, `gatesBAndCReadNumberWordsInThePassages` and
`termsHaveOneEnglishRendering` (its accent pattern was fixed after run 8 was built).
`legalMetadataRoundTripsThroughSQLite` now ignores glossary `TERM:` keys (the glossary adds "TERM:
termination of the employment contract" for its phrase). Evaluation run 9 as above. Full suite
(`/private/tmp/oi-logs/full9.log`): `Executed 1363 tests, with 8 tests skipped and 7 failures`:
the 3 known Greek-region formatting tests and 4 issues in 2 `ShortcutsActionTests`, whose note was
filed into a library "Syntagma 99C669" left as the Simulator's active library by an earlier
diagnostic test while the question ran in "General"; re-run alone after resetting the active
library: `Executed 13 tests, with 0 failures` (`/private/tmp/oi-logs/shortcuts9.log`). Swift
Testing in the full suite: `✔ Test run with 60 tests in 18 suites passed`.

#### 2.11.10 Translator: opus-mt-tc-big in both directions, decoder key/value cache

**Why:** in run 1, opus-mt-grk-en mistranslated the questions ("πολίτευμα" → "sovereignty",
"Ακροτελεύτια διάταξη" → "CSCE provision", "προφυλάκιση" → "felony guard") and the indexed text
("not less than a 200-mile break-up"). Helsinki-NLP's Greek-specific transformer-big models
(`opus-mt-tc-big-el-en`, `opus-mt-tc-big-en-el`, CC-BY 4.0) translated every failing sentence
correctly. The owner chose to ship only tc-big in both directions and asked for a decoder cache.

**What changed:**
- `scripts/thesis/convert_opus_mt.py`: ties the output layer to the shared embeddings (the tc-big
  checkpoints store a different `lm_head`, which newer transformers leaves untied, giving garbage),
  converts the float16 checkpoints to float32 before INT8 quantization, and exports the decoder as
  `decoder_cross` (each layer's cross-attention keys and values, once per sentence) and
  `decoder_step` (one token with the self-attention key/value cache). The step graph is the Marian
  decoder written out for one token with the model's own weights; in full precision its greedy
  output equals transformers' `generate()` token for token.
- `LocalNeuralTranslator`: runs encoder → `decoder_cross` → `decoder_step` per token, the cache
  starting as [1, heads, 0, head_dim] tensors. Decoder time on 12 Constitution sentences: 4.4 s →
  1.2 s (3.5×); 8 of 12 translations identical to the uncached decoder, the other 4 differ by one
  word (INT8 rounding along a different path; both valid).
- Models: `opus-mt-tc-big-el-en_*` and `opus-mt-tc-big-en-el_*` (encoder 137 MB, decoder_step
  210 MB, decoder_cross 13 MB each, INT8), made by `scripts/thesis_fetch_translation_models.sh`;
  the small opus-mt-grk-en and opus-mt-en-el are no longer used. The project file's engine-target
  exclusions list the new files.
- Import of the 162-page Constitution in the Simulator: 6.6 min (opus-mt-grk-en), 15 min (tc-big
  without cache), 487 s and 463 s (tc-big with cache, runs 5 and 7).

**Files:** `LocalNeuralTranslator.swift`, `scripts/thesis/convert_opus_mt.py`,
`scripts/thesis_fetch_translation_models.sh`, `project.pbxproj` (resource exceptions),
`GreekLegalPipelineTests.swift`, `GreekProcessingLogTests.swift`

**Verification:** all Greek suites (32 tests) pass on the iPhone 18 Pro simulator with the cached
decoder; evaluation runs 5–9 and the full suite: see 2.11.9.

#### 2.11.11 Structure-aware chunking of Greek statutes (plan stage 3)

**Why:** the general chunker cut through provisions, and its overlapping "[Part N]" pieces separated
an article's paragraphs: Constitution Article 120 §4 (the duty to resist) was three passages after
its heading, so the question about it (Q10) never got §4 into the prompt, and Article 6 §4's
exception was split from its rule.

**What changed:**
- New `GreekLegalStructureChunker` (`Services/Document/Localization/`). A text is a Greek statute
  when at least 30% of its letters are Greek and it has at least three article headings, each a
  line of its own ("Άρθρο 5", "Άρθρo 5" with a Latin o is repaired first by
  `GreekLegalEntityMasker.normalizeGreekText`; a table-of-contents line "Άρθρο 16 Σκοπός" is not
  one). A heading counts only if text follows it and its number is above the last one, so a
  correlation table's "Άρθρο 1" after the last article stays text of that article.
- Each article is cut at its numbered paragraphs ("1. ", "2. ", … in order); every passage is one
  paragraph (a paragraph under 40 words takes the next with it; one over the word cap, 200 or the
  configured maximum, is split at sentence ends) and starts with the article's heading line and
  its title, so it says which article it belongs to and `LegalCrossReferences.articleHeadings`
  finds it. Section title "Άρθρο N"; section path: the book/part/chapter headings above it.
- Government Gazette pages: running headers ("ΕΦΗΜΕΡΙΔΑ ΤΗΣ ΚΥΒΕΡΝΗΣΕΩΣ", the issue line
  "Τεύχος A' 121/11.07.2025", page numbers) are dropped, words broken at a line end ("υπο -" +
  "χρέωση", "εργα-" + "ζόμενο") joined, and a part/chapter heading at the end of an article is moved
  to the next article's path.
- `DocumentProcessor` uses it before the structure-aware and semantic paths when the text is a
  Greek statute (`makeGreekLegalChunks`: page number from the page text ranges, structure type
  `legal_provision`); every other document is chunked as before.
- **Token cap:** the embedding tokenizer counts a Greek word as about four and a half tokens, so in
  run 10 146 of the 323 passages were over the 430-token cap and `enforceTokenLimitOnChunks` cut
  them again, without their headings (323 → 582 passages). `makeGreekLegalChunks` now cuts such a
  passage itself at sentence ends, with the same token counter, every piece keeping the heading
  and title (`GreekLegalStructureChunker.pieces`); run 11: 700 passages, none cut afterwards
  (`Token limit enforcement complete: 700→700 chunks, split=0, maxTokens=429/430`).
- **End of the last article:** with no heading after it, the Constitution's Article 120 §4 ran on
  into the signatures and resolutions printed after the articles, and in run 11 the answer about
  §4 was drafted from those ("48 acts", "1204 resolutions"). The last article now ends at a
  sign-off line ("Αθήνα, 27 Ιουνίου 2008"), a block in capitals ("Ο ΠΡΟΕΔΡΟΣ ΤΗΣ ΒΟΥΛΗΣ") or a
  table ("Πίνακας …", as after the Labour Code's last article); that text becomes passages of its
  own with no article.
- **Numbers to Greek as digits:** in run 9 the English draft for Q2 said "three hundred" and the
  English→Greek translator wrote "τρία εκατοντάδες". `translateEnglishToGreekPreservingCitations`
  now turns English cardinal number words from 2 to 999 into digits first
  (`SpelledNumber.digitsForEnglishNumberWords`: "two-hundred" → "200"; ordinals, "one" and "a
  second" stay words, and so does a fraction: "two-thirds" became "2-τρίτων" in run 10).
  `SpelledNumber` moved to its own file in `Localization/`, next to the
  translator that uses it.
- `scripts/thesis_run_tests.sh` shuts the simulator down and boots it before every run: twice a
  run waited for ever at launch with the device "Booted" after the previous run was stopped, and
  the retry alone did not clear it.
- `legalMetadataRoundTripsThroughSQLite` compares sets (its `filter` gave an array in random
  order, so it passed or failed by chance).

**Files:** `GreekLegalStructureChunker.swift` (new), `SpelledNumber.swift` (moved out of
`LegalVerificationPolicy.swift`), `LocalNeuralTranslator.swift`, `DocumentProcessor.swift`,
`scripts/thesis_run_tests.sh`, `GreekLegalPipelineTests.swift` (suite "Greek statute chunking",
`englishNumberWordsBecomeDigitsBeforeTranslation`)

**Verification:** Constitution set, whole app path (iPhone 18 Pro simulator, Apple's on-device
model, re-import each time):

| Run | Change | Passed | Expected article retrieved | Import |
|---|---|---|---|---|
| 9 | before this section (reused library) | 7/10 | 7/10 | – |
| 10 | structure-aware chunking, digits before translation | 7/10 | 9/10 | 356 s |
| 11 | + token-cap pieces with headings, fractions stay words | 8/10 | 10/10 | 362 s |
| 12 | + end of the last article, contents headings, glossary (2.11.13) | 9/10 | 10/10 | 340 s |

Run 11 (`/private/tmp/oi-logs/eval11.log`): PASS 1–7 and 9; Q2 (200/300) and Q5 (President of the
Republic) pass now. FAIL Q8: the draft gives the three-fifths and later rounds but not the
two-thirds of the first round (Article 114 was ranked above Article 32); FAIL Q10: drafted from the
text after §4, fixed afterwards by the end-of-last-article rule (not yet measured on this set).
Greek unit suites in the same run: `✔ Test run with 60 tests in 16 suites passed after 1335.952
seconds` (59 unit tests and the evaluation). Full suite with the end-of-last-article rule
(`/private/tmp/oi-logs/full11.log`): `Executed 1363 tests, with 8 tests skipped and 7 failures`:
the 3 Greek-region formatting tests and the same 4 issues in 2 `ShortcutsActionTests` as in 2.11.9
(the Simulator's saved active library was still the leftover "Syntagma 99C669"; reset to "General"
in the app's preferences afterwards); Swift Testing `✔ Test run with 62 tests in 18 suites passed`.

#### 2.11.12 Evaluation harness and the Greek labour-law QA set

**What changed:**
- `GreekConstitutionEvaluationTests` is a harness over any set in `Benchmarks/`:
  `TEST_RUNNER_OI_GREEK_EVAL_SET=GreekConstitution|GreekLabourCode`,
  `TEST_RUNNER_OI_GREEK_EVAL_SPLIT=dev|test|all`, `TEST_RUNNER_OI_GREEK_EVAL_CORPUS=excerpt|full`;
  a library per set and corpus (the Constitution's keeps its old name, so its import is reused);
  it reports retrieval hit, answer pass (every key fact and no abstention), false abstentions and
  abstention correctness for `shouldAbstain` cases, and a summary line. Time limit 150 min;
  `scripts/thesis_run_tests.sh` takes `OI_TEST_TIMEOUT_SECONDS` (default 1800) for longer runs.
- `Benchmarks/GreekLabourCode/`: the Labour Code Π.Δ. 62/2025 (ΦΕΚ Α' 121/11.07.2025, 260
  pages, the owner's PDF), a 37-page excerpt and `labour_qa_v1.jsonl` (69 cases: 61 answerable
  from the code's own article text, 6 of them cross-references and 6 in everyday words, and 8 that
  must be refused; 46 dev, 23 test). Sources and page numbers in its README.

**Files:** `GreekConstitutionEvaluationTests.swift`, `scripts/thesis_run_tests.sh`,
`Benchmarks/GreekLabourCode/` (new)

**Grading patterns changed after run 2 (justification):** case 32's answer said the termination
must be made "γραπτώς" (in writing), which the key fact `εγγραφ` (εγγράφως) did not accept: now
`(εγγραφ|γραπτ)`. Case 31's answer rendered «σπουδαίος λόγος» as «σοβαρός/καλός λόγος»; the key
fact now accepts `(σπουδαι|σοβαρ)\w*\s+λογ` (a serious reason, the code's meaning), not "καλός".
After run 3, case 28's correct answer read "τους δώδεκα πρώτους (12) μήνες", which the pattern
`(12|δωδεκα)\s*(\(12\)\s*)?μην` (number right before the unit) rejected. Every key fact of that
shape (17 cases, dev and test alike, before the test split was run) now accepts the whole-word
number followed within 25 characters, without another number or a sentence end, by the unit:
`\b(12|δωδεκα)\b(?:[^.;\d]|\(\d+\)){0,25}μην`. "18 μήνες" still fails a "6 months" fact.

**Verification:** see 2.11.13 for the runs on this set. The harness ran the Constitution set
unchanged (runs 9–11 and 12 print the same per-question lines plus the summary line).

#### 2.11.13 Labour Code fixes (dev split, excerpt corpus)

**Why and what (each from a logged failure of the labour dev runs):**
- **Contents headings:** PDFKit reads the Labour Code's table of contents with each "Άρθρο N" on
  a line of its own and the title on the next, so the chunker's first-come increasing chain was
  the contents (1 … 588), and every real heading after it, with a lower number, was rejected: all
  641 passages were headed "Άρθρο 588" (run 1: expected article retrieved 0 of 41; answers cited
  "Άρθρο 588"). `acceptedHeadings` now takes, of the headings in increasing order, the chain with
  the most text under its headings (a weighted longest increasing subsequence); a contents entry
  has only its title under it.
- **Markdown in Greek answers:** the draft's `**bold**` and `###` headings came back from the
  translator as "**δώδεκα (12)** μήνες", "8 (****) εβδομάδες" and "# #". Greek legal answers are
  plain text: `LocalNeuralTranslator.withoutMarkdown` removes emphasis and heading marks before
  English→Greek translation (list dashes and [S#] stay). A number the draft writes as "twenty-six
  (26)" is "26" once converted, not "26 (26)".
- **Glossary** (the code's own wording): «προειδοποίηση» → "notice" (the question said "warning",
  the passages "notice", and gate E refused case 29 as a topical mismatch on "warning");
  «σπουδαίος λόγος» → "serious reason" (was "good reason").

**Files:** `GreekLegalStructureChunker.swift`, `LocalNeuralTranslator.swift`, `SpelledNumber.swift`,
`GreekLegalEntityMasker.swift`, `GreekLegalPipelineTests.swift`

**Verification:** Labour Code set, whole app path (iPhone 18 Pro simulator, Apple's on-device
model). Corpus: excerpt (37 pages), re-imported each run (263 s, 641/691 passages):

| Run | Split | Change | Passed | Answers (key facts, no abstention) | Expected article retrieved | Refusals correct |
|---|---|---|---|---|---|---|
| 1 | dev (46) | baseline (2.11.11 chunker) | 24 | 20/41 | 0/41 | 4/5 |
| 2 | dev | + heading chain, markdown removed before translation | 29 of 45 graded* | 26/41 | – | 3/4 |
| 3 | dev | + glossary «προειδοποίηση», «σπουδαίος λόγος»; "26 (26)" → "26"; patterns of cases 31, 32 | 31 | 28/41 | 38/41 | 3/5 |
| 3' | dev | run 3 regraded with the number–unit patterns | 32 | 29/41 | – | 3/5 |
| 4 | test (23), once | same app as run 3, reused library | 14 | 13/20 | 19/20 | 1/3 |
| 5 | test (23), **full code** | same app; full 260-page import: 4,218 passages in 1,757 s | 11 | 11/20 | 18/20 | 0/3 |

\* Run 2 was stopped at question 45 of 46 by the test script's 30-minute default; its 45 answers
were graded from the log with a Python copy of the harness's grading, which reproduces run 1's 24
of 46 exactly. Retrieval is not given for it (the copy only sees the five passages printed).

Remaining failures (run 3, dev): model errors with the right article in the prompt (case 1 and 2
gave the six-day 26 days for a five-day week; 41 gave the mother's 18 months for the father; 19
cited Article 113 instead of 219; 43 left out the 30 months; 7 and 47 drifted to other passages);
retrieval misses (10: Article 188 instead of 187; 8, 58); one false abstention (50, gate E); two
questions that should have been refused were answered from other passages (65 pensions, 68
unemployment benefit, which the translator calls "IDP"). Test split: 42 renders «σπουδαίος λόγος»
as «σοβαρός λόγος» (its pattern was not widened after seeing it), 45 (Article 250 not retrieved),
48, 18, 30, 33, 54 wrong or incomplete figures; 63 and 66 (income tax, Germany) answered instead of
refused. With the full code (run 5) three more fail: 9 (does not say the leave can be replaced by
money only when the employment ends), 36 (Article 338 not retrieved among 4,218 passages) and 57
(pregnancy dismissal answered without "prohibited/void"), and none of the three off-code questions
is refused (the larger corpus always has some related passage); 18 passes there. Greek unit suites in run 3: `✔ Test run with 62 tests in 16 suites passed` (61 unit tests
and the evaluation). Constitution set, run 12 (re-import with this section's chunker, 712 passages, 340 s): 9 of 10,
expected article retrieved 10 of 10; Q10 (Article 120 §4) passes now that the last article ends
before the signatures; Q8 still leaves out the first round's two-thirds. Full suite
(`/private/tmp/oi-logs/full13.log`): `Executed 1363 tests, with 8 tests skipped and 3 failures`
(the 3 Greek-region formatting tests; `ShortcutsActionTests` pass with the active library reset);
Swift Testing `✔ Test run with 64 tests in 18 suites passed`.

#### 2.11.14 Out-of-scope refusals, glossary Greek in answers, figures tied to their case

**Why:** the progress file's next steps after 2.11.13. Off-code questions (income tax, pensions,
unemployment benefit, maternity leave in Germany) were answered from loosely related passages: the
model wrote "The excerpts do not specify …" or "Insufficient evidence …" and padded the rest with
whatever the passages held, and the review only knew a few fixed failure texts, so the padding
was translated and shown; a question about another country got the Greek figures. With the right
article in the prompt the model gave the six-day week's leave for a five-day week and the mother's
period for the father. «σπουδαίος λόγος» came back from English→Greek as «σοβαρός λόγος» (test
case 42). The app's developer also pointed out that Standard reuses a question's cached search
until the documents or the app's version and build change.

**What:**
- **Draft that says the passages don't answer** (`GreekLegalAnswerFinalizer.declaresMissingEvidence`):
  when the draft's opening sentence (headings and bold removed) starts with such a statement and
  doesn't qualify it in the same sentence ("…, but …"), the Greek abstention is shown. Checked
  against every English draft of the earlier runs (Constitution runs 1–12, labour runs 1, 3, 4,
  5) before writing it: it would have refused 63, 65 and 68 and drafts that failed anyway, and no
  draft that passed (without the "but/however" rule it would have refused Constitution run 1's
  Q9). Note: test-split drafts (runs 4 and 5) were among those read, so the test split's refusal
  numbers after this change are not a clean held-out measurement.
- **Another country's law** (`unsupportedForeignJurisdiction`, part of the pre-generation check):
  a question naming a country other than Greece after "in/of/from/under/for/to" is refused before
  generation unless a retrieved passage names that country (English text, or the Greek source by
  the country's Greek stem). Countries come from the system's region list in English and Greek.
- **Glossary Greek in answers** (`LocalNeuralTranslator.restoringGlossaryGreek`): when a glossary
  term of the English answer is not in the Greek translation in the glossary's words, the model's
  own rendering of the term alone is looked for and each of its words gets the glossary word's
  stem with the ending the sentence gave it (σοβαρό λόγο → σπουδαίο λόγο).
- **Figures tied to their case:** the Greek-mode instruction adds "Say which case or person each
  number applies to, and when the excerpts give different numbers for different cases, give the
  one for the case the question asks about." (general; no example from the dataset).
- **Evaluation clears cached searches** (`GreekConstitutionEvaluationTests`): every run starts with
  `deleteAllCachedQueries`, so a reused library cannot hand back an earlier build's passages. Of
  the earlier runs only Constitution run 8 reused cached searches (16, from run 7, whose retrieval
  code was the same); every other run re-imported, which empties the cache.
- **Greek stamps and short image text misread as Cyrillic** (`OCRRouterService.visionTextNeedsGreekEngine`):
  the developer noted that low-text pages and large annotations (stamps) of a PDF with a text
  layer are read by `ImageUnderstandingService`. Every OCR call of the import (`extractTextFromImage`
  for document images, stamps and standalone images; the page parser; region and table rescue;
  the multi-column extractor) already went through `OCRRouterService`, but a new test showed the
  router kept Vision's text for a rendered Greek stamp: «ΑΚΡΙΒΕΣ ΑΝΤΙΓΡΑΦΟ / Ο Προϊστάμενος της
  Διεύθυνσης» came back as "АКРІВЕТ АТІГРАФО / Проїотнаос ins Alaúduvons" (log:
  `site=imageUnderstanding engine=vision chars=44 greekLetters=0 used=true`). The misread detector
  only looked for Latin look-alikes in texts of 20+ characters and 6+ words. Now any Cyrillic
  letter in Vision's text sends the image to PaddleOCR (whose text is kept only when it has Greek
  letters); after the fix the same stamp logs `engine=paddle-el-v5 chars=47 greekLetters=42
  used=true`. New tests `imageUnderstandingReadsGreekWithPaddleOCR` (whole service, rendered stamp)
  and a Cyrillic case in `routerReplacesMisreadVisionTextWithGreek`.

**Files:** `GreekLegalAnswerService.swift`, `LocalNeuralTranslator.swift`, `RAGService.swift`
(instruction), `GreekLegalPipelineTests.swift`, `GreekConstitutionEvaluationTests.swift`,
`Docs/Thesis/METHODS_SUMMARY.md` (new: the owner's high-level thesis summary), `AGENTS.md`
(keep that summary current).

**Verification:** Labour dev split, excerpt corpus, reused library (iPhone 18 Pro simulator,
Apple's on-device model):

| Run | Change | Passed | Refusals correct | Answerable questions refused |
|---|---|---|---|---|
| 3 (2.11.13) | – | 31/46 | 3/5 | – |
| 6 | + missing-evidence and foreign-jurisdiction refusals | 36/46 | 4/5 (65 refused now; 68 still answered) | 7, 22, 26, 47, 50 |
| 7 | + glossary Greek, figures tied to their case, cache cleared, Cyrillic stamps | 37/46 (answers 32/41, expected article retrieved 39/41) | 5/5 | 26, 46, 50 |

In run 6 the new check refused one answerable question, 26, whose draft opened "The excerpts do not
directly address …" and listed unrelated notice periods; 7, 47 and 50 were refused by the
pipeline's own grounding check and 22 by gate F, as before. Case 68 (unemployment benefit, «ΔΥΠΑ»
translated "IDP") was answered with the special maternity protection benefit.

Run 7 against run 6: 8, 58 and 68 now pass (68 refused: the draft opened by saying the passages
don't give the benefit's amount); 34 and 46 fail. 34 is not a regression of this change: both
runs' drafts mix up "18 months" and "18 years" for the 16-years-and-over band (run 6's Greek
answer happened to carry "12 μηνών"). 46 (harassment) drifted to working time ("forty-eight (48)
hours") and gate C refused it, where run 6 answered from Article 60. Greek unit suites
(`/private/tmp/oi-logs/greekunit10.log`): `✔ Test run with 65 tests in 15 suites passed`.
Constitution set, run 13 (reused library, cached searches cleared): 9 of 10, as in run 12 (Q8
still leaves out the first round's two-thirds). Full suite (`/private/tmp/oi-logs/full14.log`):
`Executed 1363 tests, with 8 tests skipped and 3 failures` (the 3 Greek-region formatting tests);
Swift Testing `✔ Test run with 68 tests in 18 suites passed`.

#### 2.11.15 EU labour-law holdout: before/after measurement

**Why:** the owner asked for a "before and after" of the on-device model's accuracy and
hallucination, with and without translation to English, on a set that was never used for tuning
(thesis Chapter 6). The set is the app developer's test in `/Users/alagra/Documents/thesis/rag-tests/`
(`eu_data.json`): 11 articles of three EU labour directives in their official English and Greek
texts, 16 questions, 13 answered by the text and 3 not. It is a holdout (AGENTS.md step 5): it
stays outside the repository, only the summary lines of its runs were read, and nothing in the app
was changed because of it.

**What:**
- `EUHoldoutEvaluationTests` (opt-in `TEST_RUNNER_OI_EU_HOLDOUT=1`): imports each passage as a
  document of its own into two libraries (English passages, Greek passages) and asks every question
  through `RAGService.query` in Standard mode, as a user's question goes (a Greek question in Greek
  legal mode: translated, answered in English, verified, translated back). Three conditions as in the
  developer's `ragtests.swift`: English passages + English questions, Greek passages + English
  questions, Greek passages + Greek questions. Graded the developer's way: an answer is right when
  it holds one of the question's expected terms (whole word; a Greek term as a word start); a
  question with no answer counts as declined when the app abstains. Also reported: the right
  passage among the retrieved ones, and answerable questions declined. Cached searches are cleared
  first.
- `scripts/thesis/holdout/EUHoldoutStockAppTests.swift`: the same harness for the original app
  (git worktree of `upstream/main` at `a7276983`, the commit the fork last synced with), with the
  original app's model settings (default temperature and guardrails); copied into the worktree's
  test target to run, not part of the fork's tests.
- `GreekEvalOnDeviceModel` (in `GreekConstitutionEvaluationTests.swift`) is no longer private, so
  both harnesses use the same on-device model wrapper.

**Files:** `OpenIntelligenceTests/Services/GreekLegal/EUHoldoutEvaluationTests.swift` (new),
`OpenIntelligenceTests/Services/GreekLegal/GreekConstitutionEvaluationTests.swift`,
`scripts/thesis/holdout/EUHoldoutStockAppTests.swift` (new).

**Verification:** Apple's on-device model (AFM 3 Core Advanced, context window 8,192) in the iOS 27
Simulator on an M3 Mac, 2026-10-29. Right answers of 13; "declined" = of the 3 questions the text
doesn't answer (declining is right); retrieved = the right passage among those given to the model.

| System | English passages, English questions | Greek passages, English questions | Greek passages, Greek questions |
|---|---|---|---|
| Bare model, right passage given (developer's `run_all.sh`) | 12/13, declined 3/3 | 7/13, declined 2/3 | 12/13, declined 0/3 |
| Original app (`holdout_stock2.log`) | 13/13, declined 2/3, retrieved 13/13 | 9/13, declined 2/3, retrieved 12/13, 1 answerable declined | 5/13, declined 0/3, retrieved 12/13 |
| This fork at `f0460f5c` (`holdout_fork3.log`) | 13/13, declined 2/3, retrieved 13/13 | 13/13, declined 2/3, retrieved 13/13 | 13/13, declined 3/3, retrieved 13/13 |

Log lines: original app `✔ Test run with 1 test in 1 suite passed after 2876.766 seconds`; fork
`✔ Test run with 1 test in 1 suite passed after 2890.972 seconds`. An earlier fork run of the same
code (run 2, whose retrieval column was wrong because of a harness bug since fixed) gave 13/13 and
2/3, 13/13 and 2/3, 12/13 and 3/3 with one answerable question declined: runs of the same code can
differ by one question (the model runs greedily, but the import is not bit-for-bit repeatable).

Limits: 13 + 3 questions; a library of 11 short passages, of which Standard hands the model 5, so
finding the passage is easy compared with the 4,218-passage Labour Code; grading by expected terms,
not yet read by a person; Simulator, not a device.

#### 2.11.16 EU holdout: grading fixed and graded again

**Why:** reading the answers side by side (`rag-tests/results/holdout_comparison_2026-10-29.md`,
outside the repository) showed that the developer's automatic grading, used in 2.11.15, misjudged
answers of both apps: a Greek question answered correctly in English failed because only Greek
terms were accepted; a question whose expected-terms list is empty passed any answer; refusals
behind the app's "[Needs Verification]" banner ("The requested topic … is not explicitly addressed
in the provided excerpts") counted as answers; and a term mentioned anywhere passed an answer whose
main claim was wrong. Only the grading changed; nothing in the app was changed because of the
holdout, and `eu_data.json` is unchanged.

**What:** `scripts/thesis/holdout/regrade_holdout.py` grades the runs again from their logs, the same
way for every system (it holds no questions or answers and prints counts only): a Greek question
also accepts the English expected terms, and English answers to Greek questions are counted as a
language mismatch; a question without expected terms is left ungraded; a refusal is recognized
after the banner when the answer opens by saying the passages don't address the topic (unless it
goes on with "but/however"). It also writes `rag-tests/results/holdout_grading_sheet.csv`, one row
per answer with both automatic grades and a column for the owner's own grade, which is the final
one (a "first paragraph only" check is included as a hint; it is too crude to report, failing half
of the correct English answers).

**Files:** `scripts/thesis/holdout/regrade_holdout.py` (new).

**Verification:** grading of `holdout_stock2.log` and `holdout_fork3.log` (all 48 answers of each
matched). Right answers of 12 graded (Q09 has no expected terms), unanswerable questions refused of 3:

| System | English passages, English questions | Greek passages, English questions | Greek passages, Greek questions |
|---|---|---|---|
| Original app | 12/12, refused 3/3 | 8/12, refused 3/3, 2 answerable refused | 9/12, refused 0/3; all 16 answers in English |
| This fork | 12/12, refused 3/3 | 12/12, refused 3/3 | 12/12, refused 3/3; answers in Greek |

The fork's advantage stays; it is smaller than in 2.11.15 where the developer's grading counted the
original app's correct English answers to Greek questions as wrong, and larger in that the original
app answers a Greek user in English and answers every unanswerable Greek question. The bare-model
row of 2.11.15 is the developer's own grading and was not graded again (its raw output has another
format).

**The owner's grade (final), 2026-10-29:** every one of the 96 answers read and graded by the owner
in the sheet (`rag-tests/results/holdout_grading_sheet_completed.csv`). Of 13 answerable questions,
and of the 3 questions the text doesn't answer:

| System | English passages, English questions | Greek passages, English questions | Greek passages, Greek questions |
|---|---|---|---|
| Original app | 13 right; 3/3 refused | 7 right, 3 wrong, 3 refused although answerable; 3/3 refused | 0 right in Greek (9 right but in English, 4 wrong); 0/3 refused (all 3 answered) |
| This fork | 13 right; 3/3 refused | 12 right, 1 wrong; 3/3 refused | 13 right; 3/3 refused |

The grader knew which app wrote each answer (not blind).

#### 2.11.17 Translator: faster next-token pick, one direction loaded and released; batching tried and dropped

**Why:** the full Labour Code took 29 minutes to import in the Simulator, almost all of it
translation, and both translation directions stayed loaded (about 720 MB) for the rest of the
session, a risk on an 8 GB iPhone.

**What:**
- The next token is picked with Accelerate (`vDSP_maxvi`) instead of a Swift loop over the
  58,829-word vocabulary, which was most of the translation time in Debug builds (the Simulator
  tests run Debug builds; a Release build optimizes the loop, so the gain on a device is smaller).
- Only one direction's sessions are loaded at a time, and they are released at the end of an import
  and on a memory warning (`releaseModels()`; the memory-warning observer in `RAGService`).
- **Batching, tried and not shipped.** Models exported with a batch axis and an encoder mask on the
  decoder step (`scripts/thesis/convert_opus_mt_batched.py`) decode the Greek sentences of 256
  chunks together, sorted by length (`pretranslateGreekChunks`, batch size `importBatchSize`).
  The app ships the one-sentence models, for which this is a no-op, because:
  the INT8 activations are quantized per batch, so a batch rewords about a third of its sentences
  (taking finished sentences out of a batch reworded the others too, and a unit test's sentence
  ended after half its words); the evaluations dropped with batched import; and the batched step
  graph was 2.7× slower than the one-sentence graph at batch 1.

**Files:** `LocalNeuralTranslator.swift`, `GreekLegalIngestion.swift`, `RAGService.swift` (memory
warning), `scripts/thesis/convert_opus_mt_batched.py` (new, experiment), `GreekLegalPipelineTests.swift`
(`importPretranslatesAndReleasesTheModels`, `importPretranslatesEveryWindowAndFinishesOnce`,
opt-in `batchedTranslationSpeed`, which needs the batched models).

**Verification:**
- Import of the 37-page Labour Code excerpt (691 passages, all translated), Simulator, Debug build:

  | Translation | Import |
  |---|---|
  | Before (one-sentence models, Swift loop) | 307 s |
  | **One-sentence models, Accelerate (shipped)** | **131 s** |
  | Batched models: batch 1 | 347–349 s |
  | Batched models: batch 4 / 8 / 16 | 274 / 268 / 316 s |

- Translation quality against the uncompressed fp32 model, 160 Labour Code sentences: one at a
  time chrF 96.6, batches of 16 chrF 95.9 (103 and 102 sentences identical to fp32).
- Evaluations with batched import (one run each): labour dev split (excerpt) 35 of 46 at batch 16
  and 34 at batch 4, against 37 one sentence at a time (run 7) and 38 with the batched models at
  batch 1; Constitution 6 of 10 at batch 4 (article 51's passage no longer retrieved for question 2)
  against 8 at batch 1 and 9 in runs 12 and 13.
- Shipped setup, Greek unit suites: `✔ Test run with 70 tests in 15 suites passed`
  (`greekunit15.log`). Full Labour Code (260 pages, 4,218 passages): import 1757 → 924 s.
  Evaluations, one run each (`labour11`, `constitution15`, `labourtest3`, `labourfull3`): labour dev
  35 of 46 (run 7: 37), Constitution 7 of 10 (runs 12, 13: 9), labour test split 16 of 23 on the
  excerpt (before 14) and 12 of 23 on the full Code (before 11). The passages are translated as
  before, so these differences come from the model's drafts, which differ between runs (question
  4's draft cited "[S2]" in Constitution run 13 and "[Άρθρο 6 – syntagma1_1-2.pdf p.23]" here,
  which gate C refused, as in the batch-1 run; fixed in 2.11.20).

#### 2.11.18 Document names kept as written in Greek answers; "passage" in the glossary

**Why:** the English→Greek translator translated file names cited in an answer as words
("passage 3-2.txt" → «διόδου 3-2.txt», «πέρασμα 1-2.txt»), and "passage" itself became «δίοδος» or
«πέρασμα» (a way through). Noticed in the EU holdout's answers; fixed generally (no holdout text
used) and checked on the Labour Code dev split and unit tests.

**What:** before an answer is translated, the names of the retrieved documents (also without their
extension when that leaves a number, "passage 3-2") and any other `name.ext` file name are replaced
with placeholders numbered after the legal identifiers' and put back as written
(`GreekLegalEntityMasker.maskDocumentNames`, new entity type `DOC`). The glossary renders
"passage(s)" as «απόσπασμα / αποσπάσματα», which the answer then keeps in the glossary's words
(2.11.14). The Labour Code text doesn't contain «απόσπασμα», so imports are unchanged.

**Files:** `GreekLegalEntityMasker.swift`, `LocalNeuralTranslator.swift`
(`translateEnglishToGreekPreservingCitations(_:entities:documentNames:)`), `RAGService.swift`
(passes the retrieved documents' names), `GreekLegalPipelineTests.swift`
(`documentNamesAreMaskedAsWritten`, `englishToGreekKeepsDocumentNamesAndSaysPassage`).

**Verification:** both new tests passed in the 70-test run above; the translator test checks that
"As stated in Article 5 of passage 3-2.txt …" comes back with `passage 3-2.txt` and «απόσπασμα»
and without «διόδ» or «πέρασμ» (`greekunit15.log`, `✔ Test run with 70 tests in 15 suites passed`).
"excerpt(s)" was added to the same glossary entries afterwards (2.11.20's test run). Labour dev
split and Constitution set: see 2.11.17 and 2.11.20; no dev case changed because of this (the
graded facts are in the Greek answer, and none of the failures involved a file name).

#### 2.11.19 Greek OCR benchmark: clean, scanned and photographed pages

**Why:** the thesis needs a measured answer to how well the app reads Greek legal text from scans
and phone photos, and which reader does it. (Test set and suite written by Antigravity from the
plan `Docs/Thesis/plans/ocr-test-set.md`; run, checked and recorded by Claude Code.)

**What:** no app code changed.
- `scripts/thesis/make_ocr_testset.py` builds `Benchmarks/GreekOCR/` (14.4 MB) from 10 pages of
  the Labour Code excerpt (Π.Δ. 62/2025): each page clean (200 dpi), as a scan (180 dpi, rotated
  −1.5° to +1.5°, noise, less contrast) and as a phone photo (perspective, uneven light, blur),
  with reference texts and an image-only `scan_pages.pdf`; fixed seed. `photos/` takes the owner's
  own phone photos.
- Opt-in `GreekOCRBenchmarkTests` (`TEST_RUNNER_OI_OCR_BENCH=1`): Vision alone, PaddleOCR alone
  and the app's own path on every image (CER, WER, word recall and precision, legal identifier
  recall, number recall, seconds per page), and a whole import of `scan_pages.pdf`.

**Files:** `scripts/thesis/make_ocr_testset.py`, `Benchmarks/GreekOCR/`,
`OpenIntelligenceTests/Services/GreekLegal/GreekOCRBenchmarkTests.swift`,
`Docs/Thesis/plans/ocr-test-set.md`, `Docs/Thesis/plans/ocr-test-set-results.md` (full tables).

**Verification:** `/private/tmp/oi-logs/ocrbench2.log`, `✔ Test run with 2 tests in 1 suite passed
after 712.972 seconds`. Word recall (10 pages each): Vision 0.05 on every version (it reads no
Greek); PaddleOCR 0.96 clean, 0.96 photo, 0.48 scan; the app path equals PaddleOCR on all 30 images.
On scans, recall falls with the page's tilt, 0.88 at 0.5° to 0.10 at 1.5°; the detector's boxes
are axis-aligned, so tilted lines probably merge (to be confirmed by the fix). Whole import of the
scanned PDF: 195 Greek passages, word recall 0.62, legal identifier recall 0.69. CER and WER stay
near 0.73 / 0.85 even where 96% of the words are read, most likely because of the two-column
reading order, so they are not reported as accuracy. The first run ended with an unexpected app
exit after page 12's scan (no crash report); the rerun passed.

#### 2.11.20 Gate C: source references by file name are not figures

**Why:** a Constitution draft cited its source as "[Άρθρο 6 – syntagma1_1-2.pdf p.23]", and gate C
(numeric sanity) counted "syntagma1_1-2.pdf" and "23" as figures the passages don't state, so a
correct answer was refused (question 4, in two runs). Labour drafts cite "[pd_62_2025_excerpt.pdf,
p.30]" the same way.

**What:** the numbers an answer states (`NumericValueExtractor.mentions(inAnswer:)`) now leave out
a bracketed source reference that names a file (with its page), and any file name, as they already
left out citation labels ("[S2]") and list numbers. App-wide, not only in Greek legal mode.

**Files:** `NumericValueExtractor.swift`, `NumericSanityGateTests.swift`
(`testSourceReferencesAndFileNamesAreNotNumbersTheAnswerStates`).

**Verification:** `/private/tmp/oi-logs/greekunit16.log`: claim and numeric gate suites `Executed 67
tests, with 0 failures`, Greek suites `✔ Test run with 70 tests in 15 suites passed`. Constitution
set (`constitution16`): 8 of 10, question 4 passes (questions 3 and 8 fail as before: a padded
draft refused by gate B, and the first round's two-thirds left out). Labour dev split (`labour12`):
35 of 46, as before this change; the failing cases differ from run 7 by 1, 58 and 68 failing and
34 passing, which are a draft saying the passages don't answer, a figure left out, and an
abstention case answered (1 and 68 failed in the run before this change as well).

#### 2.11.21 Firiki open-source README and thesis documentation

**Why:** replace the upstream App Store product README with an open-source technical README for the
thesis fork, Firiki (an on-device Greek legal AI assistant for iOS).

**What:** new `README.md` covering project overview, thesis problem premise, architectural pipeline,
key new features (PaddleOCR router, structure-aware legal chunker, INT8 Opus-MT translation bridge,
legal identifier masker, bilingual hybrid retrieval, verification gates, strict local privacy),
installation and model setup steps, usage, empirical evaluation summary, and upstream credits.

**Files:** `README.md`.

**Verification:** markdown verified; links and model paths aligned with thesis scripts.

#### 2.11.22 Greek OCR: text boxes follow tilted lines

**Why:** on simulated scans PaddleOCR found 48% of the words, falling with the page's tilt (88% at
0.5°, 10% at 1.5°; 2.11.19). Mechanism, observed with a Python copy of the app's detection steps on
the benchmark images: the detector still finds every line (116 regions on page 24, clean and tilted
by 1.5°), but each box was the axis-aligned rectangle around its region. A line tilted by 1.5° rises
by more than its own height across a column, so the box was 11 px high for a 6.7 px line (at the
detector's scale; 6 px on the clean page), the crop took in parts of the lines above and below, and
the recogniser, which reads one line 48 px high, returned fragments. Reading the same regions along
their own angle: page 24 scan 0.128 → 0.969 of the words (clean 0.967), page 12 0.153 → 0.968.

**What:** `GreekPaddleOCRService.dbBoxes` returns each region as a rectangle along its principal
axis (`TextLineBox`: centre, direction, length, thickness), grown by PaddleOCR's unclip rule as
before; `RGBPixels.sampled(along:)` cuts the rectangle out level with bilinear sampling, and the
recogniser reads that. The angle is kept only for an elongated region (twice as long as thick)
within 15°, and only where the line rises by at least a quarter of its thickness: the principal axis
of a level line leans by a few tenths of a degree because of the letter shapes, and such lines keep
the exact axis-aligned crop used before, so clean pages read as before. A line's `OCRTextLine.box`
(used for reading order) is the axis-aligned rectangle around the new box.

**Choosing the threshold, and checking it on other pages:** the quarter-thickness rule was set on
the benchmark images (largest rise on clean pages 0.23 of the thickness; lines on 0.5° scans about
a third), so the benchmark's gain is in-sample. `scripts/thesis/ocr_tilt_check.py` checks it on 13
pages the benchmark doesn't use (9 Labour Code excerpt pages, 4 Constitution pages; random tilt
within ±2.5°, same degradation, fixed seed) with the Python copy of the app's steps: word recall on
the tilted scans 0.464 → 0.875, against 0.879 on the same pages untilted; untilted pages 0.879 →
0.880. With a half-thickness rule the scans reached 0.855 (pages tilted 0.6–0.8° kept part of the
loss). The Constitution pages read worse even untilted (0.61–0.79, against 0.95–0.97 for the Labour
Code); that is not about tilt and is not investigated here.

**Files:** `GreekPaddleOCRService.swift`; `GreekLegalPipelineTests.swift` (`tiltedPageIsReadLineByLine`:
closely spaced lines on a page turned by 2°, WER below 0.1; `textBoxesFollowTheLine`: a level band
gives PaddleOCR's axis-aligned box exactly, a band at 3° a box along it); `scripts/thesis/ocr_tilt_check.py`.

**Verification:** the new page test fails on the code before this change
(`/private/tmp/oi-work/tilt_before.log`: `WER 0.65`, only «Άρθρο 66» read) and passes after it.
Greek OCR suite `✔ Test run with 7 tests in 1 suite passed` (`greekocr1.log`); Greek suites and
the gate suites before the last test correction (`greekunit17.log`): `Executed 67 tests, with 0
failures`, and of 72 Greek tests only `textBoxesFollowTheLine` failed, on its own thickness limit
(the drawn band is 7 px thick across, not 6, and the growth rises with it), corrected and passing
in `greekocr1`. OCR benchmark (`ocrbench3.log`, `ocrbench4.log`, the same text in both),
PaddleOCR word recall clean / photo / scan 0.96 / 0.96 / **0.96** (scan was 0.48), legal
identifier recall on scans 0.92 (was 0.61), numbers 0.94 (was 0.66); the app path equals PaddleOCR
on every image. Whole import of `scan_pages.pdf`: word recall 0.98 (was 0.62), legal identifiers
0.96 (was 0.69), 207 passages. Time: the line sampler first ran at 8.4 s per scan page against
6.8 s for a clean page; written on raw buffers (same arithmetic, same output) it runs 7.0 s against
6.6 s (Simulator, Debug build), and the OCR of the scanned PDF takes 204 s (120 s before the fix,
when most crops read as fragments).

#### 2.11.23 Greek statutes: table rows keep their own lines

**Why:** labour dev case 34 asks for the severance pay of Article 333's table for 16 or more years
of service (12 months). The chunker joined a paragraph's lines into one line, so the table's rows
became one run-on sentence ("… 15 έτη συμπληρωμένα 11 μηνών αποζημίωση 16 έτη συμπληρωμένα και άνω
12 μηνών αποζημίωση …"), translated as "16 years completed and more than 12 months compensation",
and the model mixed rows and both of the article's tables. Seen in the stored passages of the
Simulator's import (`chunk_legal.source_text_el` of Article 333). A first version that only kept
table lines apart made it worse (labour13: case 34 answered "6 months"): PDFKit reads many rows as
two lines ("10 έτη συμπληρωμένα", then "6 μηνών αποζημίωση"), and a passage boundary fell between
"12 έτη συμπληρωμένα" and "8 μηνών αποζημίωση", so the next row's months read as this row's.

**What:** `GreekLegalStructureChunker.tableLineIndices` finds table rows: runs of at least four short
lines (≤34 characters, ≤5 words) of which half have a digit, extended to neighbouring lines that
start with a number (not a numbered paragraph "1. …"), and runs of three or more lines that start
with a number and hold a second one (rows already on one line). `secondCells` puts a row read as
two lines back on one line (a one-number line right after a line whose numbers all have another
unit: "έτη" then "μηνών"). `joined` keeps each row on its own line; the sentence splitter also cuts
at line breaks and keeps them; `LocalNeuralTranslator.reflow` doesn't join table rows, so each row
is translated on its own.

**Files:** `GreekLegalStructureChunker.swift`, `LocalNeuralTranslator.swift`;
`GreekLegalPipelineTests.swift` (`tableRowsKeepTheirLines`: Article 333's rows as PDFKit reads them,
one row a line after chunking, cutting for the token cap and reflow;
`tableRowsAreTranslatedRowByRow`: three rows translate to three lines, the last with 16, 12 and
"month", no "more than 12").

**Verification:** Greek suites `✔ Test run with 75 tests in 15 suites passed`, gate suites
`Executed 67 tests, with 0 failures` (`/private/tmp/oi-logs/greekunit19.log`). Labour dev split with
this change and 2.11.24, reimported: `labour15` 36 of 46, `labour16` 35 of 46 (35 before,
`labour12`; runs since have ranged 31–36). Case 34 passes in both runs. Its answer now gives 12
months for 16 or more years, but still adds figures from the article's second table ("28 years",
"17 years: 1 month"); the key fact passes, the extra figures are wrong, and gate C doesn't catch
them because the passages state them.

#### 2.11.24 Gate C: an off-topic figure no longer refuses a correct answer

**Why:** labour dev case 46 (`labour12`): a correct answer about violence and harassment ended with
an unrelated bullet holding a figure from another passage ("Six (6) months after childbirth … the
working father is protected from dismissal"), gate C found the figure unsupported, and the whole
answer was refused.

**What:** in `GreekLegalAnswerFinalizer.review`, when gate C is the only critical gate that failed,
`droppingOffTopicFigures(from:query:)` removes the sentences that state a figure the gate counts and
share no topic word with the English question (a word of 4+ letters, not a generic labour-law word
such as "employee" or "article", or a longer form of one). What remains must still be a cited answer
of at least 12 words; it is verified again from the start and used only if every gate passes and
the composite confidence is at least 0.5. Otherwise the refusal stands. A figure on the question's
own topic is never dropped, so an unsupported figure in the answer itself is still refused.

**Files:** `GreekLegalAnswerService.swift`; `GreekLegalPipelineTests.swift`
(`offTopicFigureIsDroppedButAnOnTopicOneStillRefuses`: the case-46 shape is answered without the
bullet; the same draft for a question about the father's dismissal protection is refused).

**Verification:** the unit test above in `greekunit19` (all passed). In the dev runs `labour14`–`16`
case 46 passed without the repair firing (the model didn't add the bullet; no "Dropped off-topic"
line in the logs), so the repair is checked by the unit test only so far.

#### 2.11.25 Every passage knows its document's statute; a question naming another one is refused

**Why:** Labour Code test case 69 asks what Article 16 *of the Constitution* says about annual
leave. Asked of a Labour Code library, retrieval brings the Code's own articles, and gate I
(`statutoryIsolationViolation`) couldn't object: it only knew the statutes passages *cite* (`LAW:`,
`PD:`), and the Constitution has no key at all. Checking for "a passage mentions the Constitution"
would not do, because most of the Constitution's own articles never name it. The library had to
know which statute each document is. The same gap affected the five-document library (PoC
capability 1): a passage of Law 5239/2025 that amends other laws cites only them, so gate I counted
it as "another statute" for a question about Law 5239.

**What:** at import, `GreekLegalIngestion.documentStatuteKey(opening:)` reads the first 1,500
characters of a document (its title page) and returns `PD:62/2025` (ΠΡΟΕΔΡΙΚΟ ΔΙΑΤΑΓΜΑ ΥΠ' ΑΡΙΘΜ.
62), `LAW:5239/2025` (ΝΟΜΟΣ ΥΠ' ΑΡΙΘΜ. 5239, with the Gazette date's year), `MD:8934` (ΑΠΟΦΑΣΕΙΣ
Αριθμ. 8934) or `CONST` (ΣΥΝΤΑΓΜΑ ΤΗΣ ΕΛΛΑΔΑΣ), after look-alike repair, so the Gazette's "NOMOΣ"
in Latin letters is read too. Every chunk of the document stores it as
`LegalChunkMetadata.documentStatuteKey`. Gate I counts it among a passage's statutes, and compares
keys by kind and number, and by year only when both have one (`sameStatute`). Before generation,
`unsupportedNamedStatute` refuses a question that names a statute (a law, decree or ministerial
decision key, or "Constitution"/"Σύνταγμα", not "constitutional") when no retrieved passage comes
from it or cites it. It applies only when some passage carries a document key (imports since this
change).

**Files:** `DocumentChunk.swift` (`LegalChunkMetadata.documentStatuteKey`), `GreekLegalIngestion.swift`,
`RAGService.swift` (one call after the chunks' legal metadata is built), `LegalVerificationPolicy.swift`,
`GreekLegalAnswerService.swift`; `GreekLegalPipelineTests.swift` (`documentStatuteIsReadFromTheTitlePage`,
with the openings the Simulator's import stored for the Code, Ν. 5239, Υ.Α. 8934 and the Constitution;
`namedStatuteIsRefusedUnlessAPassageComesFromOrCitesIt`).

**Verification:** Greek suites `✔ Test run with 77 tests in 15 suites passed`, gate suites
`Executed 67 tests, with 0 failures` (`/private/tmp/oi-logs/greekunit20.log`). Constitution set,
reimported: 8 of 10 (8 before; `constitution17`), and no question refused by the new rule. Labour dev
split, reimported: 38 of 46, refusals 5 of 5 (`labour17`; the last runs scored 35 and 36). No dev
question names another statute, so the rule didn't fire there; the result is within the usual noise.
Test case 69 is left for the test-split run.

#### 2.11.26 PoC capability 4: choosing a labour contract template from a request

**Why:** the owner's fourth PoC capability: given a request in Greek or English ("I need a waiter
only for the summer season"), pick the right one of ten labour contract templates, or none (a
question about wages, another kind of contract).

**What:** the ten Greek templates drafted on 2026-10-29 (`Benchmarks/LabourContractTemplates`,
committed in `0514b17c`) moved into the app as `OpenIntelligence/Resources/LabourContractTemplates/`
(they ship in the bundle). `LabourContractTemplateRouter` (`Services/Legal/`) reads their front
matter. A Greek request is translated by Opus-MT; Apple's on-device model then answers with a
schema built at run time from the templates' ids (`DynamicGenerationSchema(anyOf:)`), so it can
only return one of the ten ids or `none`. It first writes one sentence on the work arrangement the
request describes, and decodes greedily. The instructions list each template's English title and
description. Requests about employing 15- to 17-year-olds trip the default guardrails, so a
guardrail violation is retried as a plain-text reply under the permissive guardrails, and the
first id named in it is taken. Without the model, or if both calls fail, the templates' Greek and
English keywords decide (a keyword counts when each of its words starts a word of the request;
a tie gives none). Tuning on the dev split: the descriptions of part-time (shorter days, even every
day), rotating work (full days, fewer of them), telework (hybrid included) and urgent needs (up to
two days a week, often from the next day) were sharpened after `routing1`; the guardrail retry and
three Greek age words for apprenticeship were added.

**Files:** `OpenIntelligence/Services/Legal/LabourContractTemplateRouter.swift`;
`OpenIntelligence/Resources/LabourContractTemplates/*.md` (moved; five descriptions and one keyword
list changed); `OpenIntelligenceTests/Services/GreekLegal/LabourContractTemplateRouterTests.swift`
(unit suite `LabourContractTemplateTests`: the ten templates are in the bundle with their front
matter, front matter parsing, keywords in both languages, the instructions list every id; opt-in
evaluation `LabourContractTemplateRoutingEvaluation`, `TEST_RUNNER_OI_TEMPLATE_ROUTING=1`,
`_SPLIT=dev|test`); `Benchmarks/LabourContractTemplates/README.md`.

**Verification** (routing set v1, 66 prompts, half Greek, half English; iOS 27 Simulator):

| Run | Split | Router | Keywords alone | Misses |
|---|---|---|---|---|
| `routing1` | dev (44) | 40 (41 by the model) | 26 | part-time → rotating; hybrid telework → rotating; urgent → fixed-term; apprenticeship → none (guardrails, 3 prompts fell back to keywords) |
| `routing2` | dev (44) | 43 (42 by the model) | 26 | apprenticeship → none (guardrails under both settings) |
| `routing3` | test (22), once | **20 (21 by the model)** | 8 | apprenticeship → none (guardrails, no keyword); internship (a polytechnic student's practice) → apprenticeship |

All five unit and evaluation tests passed in each run (`✔ Test run with 5 tests in 2 suites
passed`). The six "none" prompts of the set were all answered none. Each prompt takes about 1–2 s
in the Simulator.

#### 2.11.27 PoC capability 1: questions over a five-document library; Gazette pages read in order

**Why:** the five-document library (the Labour Code, Laws 5239/2025, 5278/2026 and 5316/2026,
decision 8934/2026; `Benchmarks/GreekLabourLibrary`) answered 13 of 24 dev questions at the
baseline (`library1`). Tracing the failures on the dev split found five causes:
1. A question that names a law ("σύμφωνα με τον ν. 5278/2026") was searched over all five
   documents, and the Labour Code's 4,200 passages outranked the named law's.
2. Inside one document, its title page and contents (which list every article's title) outranked
   the articles.
3. The extractive shortcut replaced the Greek legal answer with a sentence picked from a passage
   ("62/2025", dev 1 and 2).
4. The import read every page of Laws 5278 and 5316 and of decision 8934 as two columns. Their
   text runs the full width, but the short lines (a paragraph number, the end of a paragraph) centre
   far left of the others, and the column detector moved them ahead of the rest of the page.
5. The import placed words on the page using ranges from the NFKC-normalized page text, which
   `PDFPage.selection(for:)` reads as ranges of the raw text. NFKC lengthens the text at every Greek
   keraia (U+0384, "ΚΕΦΑΛΑΙΟ Α΄" becomes a space and a combining accent), so every later word got a
   later word's position. On Law 5278 "1" of "Άρθρο 1" took the position of the next line, the
   line broke as "Άρθρο" / "1 Σκοπός", and the chunker never saw articles 1, 2, 3, 5, 8 and 9 as
   headings (8 of 16 articles stored). Measured offline: page 2 is 3,635 UTF-16 units raw and 3,641
   normalized, and the range of "1" selected "κ" one line down.

**What:**
1. `GreekLegalAnswerService.requestedStatutes` and `statuteScope(query:documentKeys:)`: the
   statutes a question names (law, decree, ministerial decision keys; the Constitution). If they
   match documents of the library, `RAGService.greekLegalStatuteScope` runs the question with
   `RAGQueryScope.documentIds` set to those documents (each document's statute is read from its
   first chunk's `documentStatuteKey`, 2.11.25). Otherwise, or when the caller already set a
   scope, nothing changes. `unsupportedNamedStatute` uses the same reading.
2. `LegalCrossReferences.droppingFrontMatter`: in Greek legal mode, passages before a document's
   first article heading are left out of the context when the document has articles (a document
   without articles, like the decision, keeps all), and the list is left as it was if nothing
   would remain.
3. The extractive override is off in Greek legal mode.
4. `DocumentProcessor.isSingleColumn(lineWidths:pageWidth:)`: a page whose median line is wider
   than half the page width is one column, and column detection is skipped. Measured on the
   library: one-column Gazette pages 0.56–0.79 of the width, two-column pages (Law 5239, the Code)
   0.07–0.38.
5. `extractTextWithSpatialOrdering` and `LayoutAwareExtractor.extractBlocksFromPDFPage` take
   ranges from the raw `page.string` and normalize only the text they keep
   (`PDFPage.normalized(_:pageHasGreek:)`, the normalization `normalizedString` applies).

After 4 and 5, Law 5278 is stored with all 16 articles (8 after 4 alone), and the Labour Code with
articles under 591 different numbers (590 after 4 alone; before, articles 2, 72 and those from 589
on were missing).

**Files:** `GreekLegalAnswerService.swift`, `RAGService.swift` (`greekLegalStatuteScope`, the Greek
query wrapper, front matter before the context is packed, the extractive override's condition,
`searchDocumentsRaw(containerId:)`, `documentsForContainer` internal), `LegalCrossReferences.swift`,
`DocumentProcessor.swift`, `LayoutAwareExtractor.swift`, `PDFPage+Greek.swift`;
`GreekLegalPipelineTests.swift` (`questionNamingALibraryStatuteIsSearchedInThatDocument`,
`frontMatterIsLeftOutWhenTheDocumentHasArticles`), `DocumentProcessorTests.swift`
(`testIsSingleColumn_MedianLineWidthDecides`, `testSpatialOrdering_KeraiaDoesNotShiftLaterWords`:
a generated Greek page with a keraia before "Άρθρο 1"), `GreekConstitutionEvaluationTests.swift`
(the `GreekLabourLibrary` set, reimported into its own library).

The statute scope's hypothesis (it would fix the six failed dev questions that name a law) was not
supported: none of them changed with it, and the dev result went from 13 to 11 (cases 2 and 36
flipped). Per-case results and the open failures (13, 33) are in `EXPERIMENTS.md` E1–E4.

**Verification** (five-document library, dev split, 24 questions, iOS 27 Simulator; one run each):

| Run | Change | Passed | Right documents retrieved |
|---|---|---|---|
| `library1` | baseline | 13 of 24 | 16 of 21 |
| `library2` | statute scope | 11 of 24 | 16 of 21 |
| `library3` | + front matter, no extractive override | 12 of 24 | 16 of 21 |
| `library4` | + single-column pages (reimport) | 12 of 24 | 15 of 21 |
| `library5` | + raw-string word positions (reimport) | **14 of 24** | 15 of 21 |
| `librarytest1` | test split (12), once, reimported | **6 of 12** | 6 of 11 |

Test-split failures: 3 and 24 abstained with the wrong documents retrieved; 27 abstained (article
244 of the Code not retrieved); 15 and 18 answered from the right article but missed a fact; 31
answered from the Code's article instead of naming Law 5239.

Labour Code dev split, reimported after 4 and 5: 38 of 46, refusals 5 of 5 (`labour18`; 38
before), so the import change cost the single-document set nothing.

Units: in `units6` the keraia test failed only on its own check (the generated page's font returns
Σ as the look-alike Ʃ) while "Άρθρο 1" came out as its own line; the check now matches the title
without its sigma. In `greekunit21` (`Executed 84 tests, with 0 failures`; Swift Testing 95 tests,
1 issue) `questionNamingALibraryStatuteIsSearchedInThatDocument` failed: it expected "Law 5239"
without a year to scope the search, but the masker reads a law's number only with its year. The
test now names "Law 5239/2025" and records that the number alone scopes nothing. `greekunit23`:
`✔ Test run with 57 tests in 7 suites passed`, `Executed 17 tests, with 0 failures`.

**Tried and dropped:** a glossary entry for «τρίμηνο» (library dev 8, where the translator's "a
quarter" came back as «ένα τέταρτο»). As "three-month period" it fixed dev 8 but Labour Code dev 4
came back as «πρώτη τρίμηνη περίοδο» (`library6` 13 of 24, `labour19` 32 of 46); as "three months"
dev 4 came back as «τους τρεις πρώτους μήνες» (`library7` 13 of 24, `labour20` 36 of 46). Each
variant traded one case for the other, so the entry was removed.

#### 2.11.28 PoC capability 2: a Greek summary of one statute

**Why:** the owner's second PoC capability: a complete Greek summary of one statute (main rules,
figures and deadlines, with article references), checked against the source.

**What:** `GreekLegalDocumentSummarizer` (`Services/Legal/`), map then reduce, sized for the
iPhone's 4,096-token window even where the model reports more:
1. The document's articles are built from its passages in chunk order; the title page, the
   contents and passages that are mostly headings are left out.
2. Articles are packed into groups of about 7,400 English characters. Each group begins with a
   marker line ("=== Article 8 ===", "(continued)" for a split article), so the model knows which
   article each rule belongs to.
3. Map: one call per group asks for short notes, a line limit set by the number of articles in the
   group, each labelled with its article. Notes are cleaned: marker lines and "Article N:" labels
   set the current article, a label naming an article not in the group is replaced by the
   group's own, and lines under 12 characters are dropped.
4. "Main provisions" is built in code: one bullet per article from its first two notes; with more
   than 12 articles, the 12 with the most notes are kept, in document order. The model writes
   only one or two opening sentences (reduce), so it cannot renumber articles.
5. Every sentence is checked: figures the document's passages do not state (gate C, ignoring the
   statute's own number), and articles or statutes the document neither has nor cites (gate F),
   are dropped. The rest is translated with the citation-preserving English→Greek path.
6. A document without article headings (the ministerial decision) is cut into parts of about
   2,500 characters between passages ("Part 1", "Part 2", …), noted with instructions for a text
   without articles, and listed without part labels. Added after the test run, which found the
   decision's summary empty.

Tried and dropped on the dev document: free reduce over all notes (it took figures and article
numbers from the notes into the wrong article: `summary1`, about 40 bullets, "Article 404" and
"410" for articles of Law 5278); a combine round, and a bullet cap.

**Files:** `OpenIntelligence/Services/Legal/GreekLegalDocumentSummarizer.swift`;
`OpenIntelligenceTests/Services/GreekLegal/GreekLegalSummaryTests.swift` (unit suite
`GreekLegalSummaryTests`: articles without contents or title page, groups and markers, notes keep
the group's articles, one bullet an article, a document without articles summarized by parts,
unsupported figures and articles dropped, the whole map → reduce → translate path with a stub model; opt-in `GreekLegalSummaryEvaluation`,
`TEST_RUNNER_OI_GREEK_SUMMARY=1`, `_SPLIT=dev|test`); `Benchmarks/GreekLabourLibrary/summary_v1.jsonl`
(Law 5278/2026 dev, 6 provisions and 3 articles; decision 8934/2026 test).

**Verification** (dev: Law 5278/2026; one run each):

| Run | Provisions covered | Articles cited | Note |
|---|---|---|---|
| `summary1` | 5 of 6 | 1 of 3 | free reduce; about 40 bullets, wrong article numbers |
| `summary2` | 1 of 6 | 1 of 3 | markers; articles 8 and 9 lost with their marker lines |
| `summary3` | 2 of 6 | 0 of 3 | provisions built in code |
| `summary4` | 2 of 6 | 0 of 3 | + single-column pages (8 of 16 articles still stored) |
| `summary5` | **5 of 6** | **3 of 3** | + raw-string word positions (16 of 16 articles); 0 sentences dropped; 81 s |

Missing in `summary5`: the 40% extension threshold (article 9). After the parts were added the
article path is unchanged: `summary8` 5 of 6, 3 of 3.

Test split (decision 8934/2026, 5 provisions, no articles): **0 of 5** held out (`summarytest1`:
no article headings, so no groups and an empty summary). After the parts: 4 of 5 (`summarytest2`,
26 s; missing "for the whole country"). The second figure is not a held-out result, since the fix
answers a failure the test run showed.

Units: `✔ Test run with 13 tests in 2 suites passed` (`sumunit9`, summary and opinion suites).

#### 2.11.29 PoC capability 3: a legal opinion from several documents

**Why:** the owner's third PoC capability: a coherent opinion on a question that draws on several
of the five documents (which law applies, what each provides, how they combine, conclusion),
every claim cited to its document and article.

**What:** `GreekLegalOpinionWriter` (`Services/Legal/`) and `RAGService.greekLegalOpinion(question:containerId:)`:
1. Passages are retrieved from each document separately (`searchDocumentsRaw` scoped to it,
   8 passages, front matter left out, best 3 kept), so the Labour Code cannot crowd out the other
   laws. Documents scoring at least 60% of the best are kept, up to 3.
2. Links to the Labour Code are read from the documents, not asked of the model: an article
   heading of a later law that amends, replaces or adds an article "στον Κώδικα Εργατικού
   Δικαίου", and, for the decision, the Code article it cites most. When a kept law amends a Code
   article, the Code joins the sources, and a retrieved Code passage of an amended or added
   article is replaced by the amending article's text (the Code's own text is the old version).
3. Each document's section is drafted in its own model call (fits the window); a conclusion is
   written from the sections. Sections lose sentences that say a point is not addressed; the
   conclusion is its first paragraph, at most 3 sentences.
4. Every sentence is checked as in 2.11.28 (gate C, gate F against the document's articles and the
   statutes it cites); the opinion is refused only when the conclusion has no supported sentence.
5. The English parts (Applicable law, What each provides, How they combine, Conclusion) are
   translated to Greek, under Greek headings, with a closing note that it is a PoC and not legal
   advice.

**Files:** `OpenIntelligence/Services/Legal/GreekLegalOpinionWriter.swift`;
`OpenIntelligenceTests/Services/GreekLegal/GreekLegalOpinionTests.swift` (unit suite
`GreekLegalOpinionTests`: links read from headings, source selection with the Code joining when
amended, an amended Code article read from the amending law, sections and conclusion cleaned, the
whole path with a stub model, refusal; opt-in `GreekLegalOpinionEvaluation`,
`TEST_RUNNER_OI_GREEK_OPINION=1`, `_SPLIT=dev|test`); `Benchmarks/GreekLabourLibrary/opinion_qa_v1.jsonl`
(10 requests, dev 6 and test 4, each with the two documents and articles it must cite and its key
facts).

**Verification** (dev, 6 requests, 12 citations, 20 key facts; one run each):

| Run | Citations | Key facts | Refused | Note |
|---|---|---|---|---|
| `opinion1` | 9 of 12 | 12 of 20 | 1 of 6 | |
| `opinion2` | 9 of 12 | 9 of 20 | 0 of 6 | scoped search per document, front matter |
| `opinion3` | 8 of 12 | 9 of 20 | 0 of 6 | + single-column pages |
| `opinion4` | **10 of 12** | **11 of 20** | 0 of 6 | + raw-string word positions |

Each opinion takes 19–29 s in the Simulator. Request 5 (hiring for urgent needs, Law 5239 article
21 + Code 578) is answered from other articles (0 of 2 citations).

Test split (4 requests, once, `opiniontest1`): **citations 3 of 8, key facts 7 of 10, refused 0 of
4.** Requests 7 and 8 cite other articles than the set expects (7, extension of an agreement:
articles 3, 4, 14, 49, 258 and 396, where Law 5278 article 9 and Code 404 were expected, 1 of 3
facts; 8, managers' leave: Code articles 221–225 and others, where Law 5316 article 36 and Code
220 were expected, 2 of 2 facts); 9 misses one of its two articles; 10 cites both.

#### 2.11.30 Measurement: the Labour Code test split over the full Code

**Why:** refusals had been measured on the 37-page excerpt only (2.11.14), and test case 69
(Article 16 *of the Constitution*, asked of a Labour Code library) was left for the test split
when the per-document statute key was added (2.11.25).

**What:** no code change. The Labour Code test split (23 questions) was run once on the full
260-page Code, reimported with the import of 2.11.27 (`fullcodetest1`, 4,191 passages, 862 s).

**Result:** **15 of 23** (12 of 23 on 2026-10-29). Answerable: 12 of 20, with the right article
retrieved for 18 of 20 and 1 wrong refusal (33). Must refuse: **3 of 3**, case 69 included.
Failures with the right article retrieved: 3 (two months), 18 (45 hours), 30 (four months), 48
(start and end), 54 (8 hours); with it not retrieved: 36 (article 338), 45 (article 250).

#### 2.11.31 Experiments record; EU holdout run again

**Why:** the owner asked (2026-10-30) for every experiment that can serve the evaluation chapter
to be recorded, including dropped ones and per-case outcomes. Run logs lived only in
`/private/tmp/oi-logs`, which is cleared on restart.

**What:**
- `Docs/Thesis/EXPERIMENTS.md`: each experiment's observation, change, hypothesis, runs, numbers and
  outcome (E1–E10), with a table pointing to the earlier experiments in this file.
- `scripts/thesis/collect_run_results.py` copies the result lines of every run log (per-case rows,
  summaries, test outcome lines) to `Docs/Thesis/experiments/runs/`, one file a run, with
  `INDEX.md`. For the EU holdout it keeps only the model, import and summary lines; a check of the
  71 longer strings of the holdout file found none of them in the saved files.
- The EU holdout run again at `ffff0241` (`holdout_fork4`, reimported, 2,341 s), evaluation only.

**Files:** `Docs/Thesis/EXPERIMENTS.md`, `Docs/Thesis/experiments/runs/` (147 runs),
`scripts/thesis/collect_run_results.py`, `Docs/Thesis/IMPLEMENTATION_SUMMARY.md` (the owner's
summary of every fork change for the implementation chapter).

**Verification:** holdout graded with `regrade_holdout.py`: 12 of 12 graded answerable questions
right and 3 of 3 refused in each of the three conditions, the same as `holdout_fork3` graded the
same way; right passage retrieved 13 of 13. The owner's grading sheet for this run is in
`rag-tests/results/2026-10-30/` (outside the repository). The owner's hand grade (final, every
answer read): 13 of 13, 13 of 13 and 12 of 13 right (English; Greek passages with English
questions; all Greek), 3 of 3 refused in each, against 13, 12 and 13 of 13 for `holdout_fork3`.
Nothing was changed because of it.

#### 2.11.32 Firiki README update: PoC capabilities, tilted OCR and empirical results

**Why:** update the open-source `README.md` to document the completed PoC capabilities (multi-document
labour law Q&A, legislative statute summarization, multi-document legal opinions, contract template
routing, and iOS App Intents), the oriented text line box (`TextLineBox`) deskewing mechanism for
tilted scans, table row preservation, statutory identity routing, and the final empirical benchmarks.

**What:** comprehensive expansion of `README.md` covering:
1. The 4 PoC capabilities and native iOS App Shortcuts (`RouteLabourContractIntent`, `SummarizeStatuteIntent`, `GreekLegalOpinionIntent`).
2. OCR oriented line bounding boxes with bilinear sampling (improving tilted scan word recall from 48% to 96% and full scanned PDFs to 98%).
3. Table row preservation (Art. 333 severance schedule) and document statute identity (`documentStatuteKey`) with off-statute query refusals.
4. Expanded usage workflows and evaluation commands for template routing, summarization, and opinions.
5. Consolidated empirical evaluation table reflecting all latest benchmark measurements (Full Code test split, template routing, multi-document library, summarization, legal opinions, and the hand-graded EU directives holdout).

**Files:** `README.md`.

**Verification:** markdown validated; benchmark figures aligned with `METHODS_SUMMARY.md` and `EXPERIMENTS.md`.

#### 2.11.33: Context-aware document chunking, direct chat capability routing, formatted answers, and Opus-MT observability

**Why:**
1. Support diverse legal document typologies beyond codified statutes: legal memoranda, practitioner notes, and Q&A sets require structure preservation tailored to their own conventions. Previously, any document with three or more article citations was cut as a statute, splitting legal arguments across arbitrary article references. Q&A documents were chunked as general prose, risking separation of questions from answers.
2. Enable direct execution of all legal capabilities (hierarchical statute summarization, cross-statute legal opinions, and labour contract template routing) from natural language prompts in the chat thread, removing friction from modal sheet menus.
3. Replace bullet-point outputs in summaries and legal opinions with cohesive, professionally formatted legal text (bold headings, structured paragraphs, semicolon-delimited statutory authorities).
4. Provide runtime observability into local translation via structured Xcode console logging (`[Opus-MT]` prefix, segment caching statistics, token truncation diagnostics).
5. Clean template headers by removing external tool watermarks ("Claude Code") from the legal disclaimers.

**What:**
1. `GreekLegalDocumentClassifier.swift`: classifies text into `statute`, `lawyerNotes`, `questionAnswer`, or `generic` using deterministic layout rules (Gazette headers, sequential articles, Q&A prefixes, memo headings) backed by schema-constrained foundation model inference.
2. `GreekLegalQAChunker.swift`: chunks Q&A documents keeping questions and answers atomically paired; when long answers are split across token limits, repeats the question header at the top of every piece.
3. `GreekLegalNotesChunker.swift`: chunks legal memoranda and practitioner notes along doctrinal headings (*Ιστορικό*, *Ερώτημα*, *Νομική Ανάλυση*, *Συμπέρασμα*); in-text article references are preserved as citations rather than chunk division points.
4. `DocumentProcessor.swift`: routes chunkable text through `classifyIfSpecialized`, creating passages via `makeGreekLegalChunks`, `makeGreekLegalQAChunks`, or `makeGreekLegalNotesChunks`.
5. `GreekLegalChatRouter.swift`: identifies capability intents from user prompts (`statuteSummary`, `legalOpinion`, `contractRouting`, `standardQA`), extracts statutory target identifiers (e.g., "5278/2026", "62/2025"), matches documents in the library, and returns direct execution results.
6. `ChatScreen.swift`: intercepts chat queries in `sendMessageNow` and delivers capability results directly into the conversation stream.
7. `LocalNeuralTranslator.swift`: tracks cumulative invocation counts, segment caching, token decodes, and latency via `callStats`, emitting `[Opus-MT]` diagnostic logs and warnings when long segments lack internal commas.
8. `GreekLegalDocumentSummarizer.swift` & `GreekLegalOpinionWriter.swift`: formatted paragraph text and bold headers instead of bulleted lists.
9. Contract templates (`01_indefinite_full_time.md` through `10_urgent_needs.md`): neutral legal disclaimer without tool references.

**Files:**
- `OpenIntelligence/Services/Document/Localization/GreekLegalDocumentClassifier.swift`
- `OpenIntelligence/Services/Document/Localization/GreekLegalQAChunker.swift`
- `OpenIntelligence/Services/Document/Localization/GreekLegalNotesChunker.swift`
- `OpenIntelligence/Services/Legal/GreekLegalChatRouter.swift`
- `OpenIntelligence/Services/Document/Processing/DocumentProcessor.swift`
- `OpenIntelligence/Features/Chat/Conversation/ChatScreen.swift`
- `OpenIntelligence/Services/Document/Localization/LocalNeuralTranslator.swift`
- `OpenIntelligence/Services/Legal/GreekLegalDocumentSummarizer.swift`
- `OpenIntelligence/Services/Legal/GreekLegalOpinionWriter.swift`
- `OpenIntelligence/Resources/LabourContractTemplates/*.md`
- `OpenIntelligenceTests/Services/GreekLegal/GreekLegalChatRouterTests.swift`
- `OpenIntelligenceTests/Services/GreekLegal/GreekLegalContextChunkingTests.swift`
- `OpenIntelligenceTests/Services/GreekLegal/GreekLegalSummaryTests.swift`
- `OpenIntelligenceTests/Services/GreekLegal/GreekLegalOpinionTests.swift`

**Verification:**
- `GreekLegalChatRouterTests`: 6 tests passed.
- `GreekLegalContextChunkingTests`: 7 tests passed.
- `GreekLegalSummaryTests`: 6 tests passed.
- `GreekLegalOpinionTests`: 7 tests passed.
- Full suite executed in iPhone 18 Pro simulator (`** TEST EXECUTE SUCCEEDED **`).

#### 2.11.34: Native macOS Greek PDF verification and unarticled Gazette / PCC budget / Gate F fixes (2026-11-01)

**Why:**
1. Following the 31 October commits (`2af92e2e`–`f10190e1`), running a digital Greek Gazette PDF (`ya_8934_2026_fek_b1759.pdf`) and a scanned Greek PDF page (`scan_page_p04.pdf` from `Benchmarks/GreekOCR/scan_pages.pdf`) through the native macOS build (`OpenIntelligence.app`) uncovered three post-evaluation issues:
   - Unarticled Gazette decisions (such as Ministerial Decision `Υ.Α. 8934/2026`, which has a Gazette header and a title-page statute key `MD:8934` but 0 `Άρθρο N` headings) were classified as `.statute` by `GreekLegalDocumentClassifier.classifyByRules`, causing `makeGreekLegalChunks` to return `[]` (`0` chunks) without falling back to `createStructureAwareChunks` / `SemanticChunker` in `DocumentProcessor.swift`.
   - On native macOS, `QueryRuntimeCoordinator` only forced `.onDeviceOnly` under `#if targetEnvironment(simulator)`. Because `OpenIntelligence.entitlements` omits `com.apple.developer.private-cloud-compute` (`StrictLocalControlGuard.canUsePCC() == false`), native macOS left `cloudEligible = true` during retrieval and packed ~13.6 KB of context for a 32,768-token PCC budget before falling back to the 8,192-token on-device model at generation time.
   - Gate F (`LegalVerificationPolicy.unsupportedLegalIdentifiers`) checked `chunk.legal?.legalEntities` by exact string equality and did not include `chunk.legal?.documentStatuteKey` or `chunk.legal?.primaryStatuteKey`, nor did it use `sameStatute(_:_:)` when comparing yearless title-page keys (`MD:8934`) against full citations (`MD:8934/2026`).

**What:**
1. `GreekLegalDocumentClassifier.swift`: requires `!headings.isEmpty` when classifying a document as `.statute` on Gazette header or statute title key alone, so unarticled Ministerial Decisions fall back to generic structure-aware chunking.
2. `DocumentProcessor.swift`: if a specialized Greek legal chunker returns `processedChunks.isEmpty` (and `jsonRecordPassages == nil`), falls back to `createStructureAwareChunks` / `SemanticChunker` instead of returning 0 chunks.
3. `QueryRuntimeCoordinator.swift`: checks `StrictLocalControlGuard.canUsePCC()` (`pccAvailableInBuild`) alongside `#if targetEnvironment(simulator)` and forces `.onDeviceOnly` whenever Private Cloud Compute is unavailable in the build, keeping retrieval context packing within the 8,192-token on-device window on native macOS.
4. `LegalVerificationPolicy.swift`: includes `chunk.legal?.documentStatuteKey` and `chunk.legal?.primaryStatuteKey` in Gate F's `evidenceKeys(_:)` and matches `LAW:`/`PD:`/`MD:` identifiers via `sameStatute(_:_:)`.

**Files:**
- `OpenIntelligence/Services/Document/Localization/GreekLegalDocumentClassifier.swift`
- `OpenIntelligence/Services/Document/Processing/DocumentProcessor.swift`
- `OpenIntelligence/Services/RAG/Orchestration/QueryRuntimeCoordinator.swift`
- `OpenIntelligence/Services/RAG/Safety/LegalVerificationPolicy.swift`
- `OpenIntelligenceTests/Services/GreekLegal/GreekLegalContextChunkingTests.swift`
- `OpenIntelligenceTests/Services/GreekLegal/GreekLegalPipelineTests.swift`

**Verification:**
- Native macOS (`platform=macOS`, `OpenIntelligence.app` via `--rag-validation`):
  - Digital Gazette PDF (`ya_8934_2026_fek_b1759.pdf`): 37 chunks ingested and translated via `opus-mt-tc-big-el-en`, 15 chunks packed (`Context Chars: 9214/9458`, `Execution Context: On-Device Only`), Gate A–I passed, verified Greek answer returned (`920,00 ευρώ [S4]`).
  - Scanned Greek PDF page (`scan_page_p04.pdf`): native macOS `GreekPaddleOCRService` (`PP-OCRv5` ONNX detector + Greek recognizer) extracted 22 chunks, translated via Opus-MT, retrieved 9 chunks (`Confidence: 0.93`, `Execution Context: On-Device Only`), verified Greek answer returned on Article 57.
- Added unit tests in `GreekLegalContextChunkingTests` (`unarticledGazetteDecisionFallsBackToGenericChunking`) and `GreekLegalPipelineTests` (`testGateFHallucinatedArticleRejection` `documentStatuteKey` check).

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

- **Legal checks on answers (2.11.5):** gate F checks statutory identifiers and gate I statutory
  isolation in Greek legal mode; nothing yet flags a lower-authority court or a provision that wasn't
  in force on the date of the facts.
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
  - all four items were acted on in 2.11.3–2.11.5 (Greek validation, full-page Greek detection,
    whole-word touchy check, PP-OCRv5 Greek OCR and translation after extraction).
- **Observation, not a fork change:** for a Greek Cypriot labour-court document, the app's automatic
  document summary rendered "αποζημίωση απόλυσης" (severance pay) as "notice of termination". This
  is relevant to the thesis's Greek-language accuracy work.

## 5. Authorship note

The changes in sections 2.5 to 2.10 were implemented with the help of Claude Code (Anthropic). Each
of those commits carries a `Co-Authored-By` trailer.

## 9 Nov 2026: Greek wording of opinions and summaries (after the evaluation)

Found while taking the thesis screenshots of the PoC capabilities. Presentation only: retrieval,
drafting and the verification of sentences are unchanged, and the Chapter 6 figures were measured
before this change.

- `GreekLegalOpinionWriter`: "Applicable law" and "How they combine" are written in Greek by the
  program (`applicableLaw`, `combinationGreek`, `greekStatuteName`) instead of being translated. The
  translator left the English "modified" in «Πώς συνδυάζονται», and the Labour Code article an
  amendment changes was missing from the applicable law, because its passages are replaced by the
  amending article's. Now: «ν. 5239/2025, άρθρο 7· Κώδικας Εργατικού Δικαίου (π.δ. 62/2025),
  άρθρο 194, όπως τροποποιήθηκε.»
- `repairedGreek`: post-edits of the translated sections and conclusion: «της Ν. 5239/2025» →
  «του ν. 5239/2025», «Άρθρο 7 (Άρθρο 7)» → «Άρθρο 7», a mid-sentence «Άρθρο» → «άρθρο», «του άρθρο
  194» → «του άρθρου 194», «ωριαίο ποσοστό/επιτόκιο» → «καταβαλλόμενο ωρομίσθιο», «προθεσμία» for an
  overtime limit → «όριο».
- `withoutRestatedLinks`: the conclusion drops sentences that only restate an amendment link (its
  translation lost the verb). `conclusionInstructions` asks for complete sentences.
- `LocalNeuralTranslator.legalEnglishPreEdited`: "a quarter"/"quarter" (three months) becomes
  "three months"/"three-month period" before en→el translation; it came back «τέταρτο» (a fourth) in
  the summary of Law 5278/2026. Glossary: «τρίμηνο» ↔ "three-month period".
- Tests: `GreekLegalOpinionTests` (Greek wording and repairs, restated links, quarter), and the
  applicable-law expectation of `sectionsAreCheckedAndTheOpinionIsInGreekSections`.
- Backups of the previous files: `Docs/Thesis/code_backup_2026-11-09/`.
- Not changed: the opinion over all three PDFs (with the minimum-wage decision) still omits the
  €920 amount and has wording errors («υπό Article 141Α», «νομικές υπερωρίες», «τους εργαζόμενους και
  τους εργαζόμενους»). The summary still has «Το καταστατικό αυτό» for "this statute" and «λεπτού»
  for "minutes" (πρακτικά).

## 9 Nov 2026 (second entry): remaining Greek wording, the missing €920, the template answer, a foreign-law question

Carries out `Docs/Thesis/plans/greek-wording-fixes-2026-11-09.md`. Every change was checked in the
Mac app (rebuilt from this tree, Apple Intelligence on the owner's M3 MacBook Pro) with the plan's
requests, and the app's log was read for the English behind each Greek error. Retrieval, drafting
and the verification gates are unchanged except where stated; the Chapter 6 figures (Table 6.6)
were measured before this change and were not re-run.

**Step 0.** The tests of the first 9 Nov entry had never been run: `GreekLegalOpinionTests`,
`GreekLegalSummaryTests`, `GreekLegalChatRouterTests` passed (22 tests) before anything changed.

**Why the €920 was missing (a fault, not wording).** The decision's best passage, with «920,00 €»,
was retrieved (score 0.48), and the model's section stated the figure, but cited it as "(Article 1
of Ministerial Decision 8934)". The decision has no articles, so the article gate (F) dropped both
of its sentences, and the conclusion then said no minimum-wage amount was given. Now a source
without article headings is cited by name only (`sectionInstructions(statute:hasArticles:)`), and
an article number the model adds to such a source is removed before the check
(`withoutInventedArticles`, sections and conclusion). The gate itself is unchanged.

**Opinion (`GreekLegalOpinionWriter`)**
- `sectionInstructions`: asks for amounts of money, and not to refer to "the provisions in force"
  without naming them (the loose «… ισχύουσες διατάξεις …» phrase of the two-document opinion).
- `repairedGreek`, new post-edits, each from a Greek string the app produced: «υπό Article 141Α» →
  «κατ’ εξουσιοδότηση του άρθρου 141Α» (and any other English "Article N" left in the Greek);
  «νομικές υπερωρίες» → «νόμιμες»; a phrase repeated around «και» («τους εργαζόμενους και τους
  εργαζόμενους») kept once; a participle before «καταβαλλόμενο ωρομίσθιο» absorbed («καταβεβλημένο
  καταβαλλόμενο»), and the feminine variant «την πληρωμένη ωριαία τιμή»; «με ισοτιμία ίση με» →
  «με αμοιβή ίση με»; «αυτό το αυξημένο τέλος» → «αυτή την αυξημένη αμοιβή»; «τροποποιεί / σύμφωνα
  με / υπό άρθρο N» get «το»; «στο Ν. 5239/2025» → «στον ν.»; a sentence the translator began in
  lower case gets its capital (not after abbreviations such as «επ.»).
- The English opinion, its dropped sentences and each source's passages are logged
  (`[LegalOpinion]`), so a missing figure can be traced.

**Summary (`GreekLegalDocumentSummarizer`)**
- The prompts say "law", not "statute" (the opening came back «Το καταστατικό αυτό»).
- A note line is kept whole up to 320 characters, and a longer one is cut at a sentence end, or a
  clause end closed with a full stop (`shortenedNoteLine`); at 230 characters Article 7 ended in
  «… και φυλάσσονται στην …».
- The Greek summary goes through `repairedGreek` too, with post-edits found in it: "minutes" of a
  vote («λεπτού του ψηφοδελτίου», «εκλογικών λεπτών») → «πρακτικά»; «τη λήξη ή τη λήξη» ("expiry or
  termination") → «τη λήξη ή τη λύση»; «ρυθμιστικοί όροι» → «κανονιστικοί όροι».
- The English summary is logged (`[LegalSummary]`): a summary has no Response Details card.

**Translator (`LocalNeuralTranslator.legalEnglishPreEdited`)**, before en→el translation:
"statute(s)" → "law(s)" (not "statute of limitations"); an amount in words followed by its figure
keeps only the figure ("forty-one euros and nine minutes (41.09 €)" came back «40-ένα ευρώ και 9
λεπτά»); an em dash between words becomes a comma (the translator dropped it and glued the words:
«υπερωρίαςέως»); a range's en dash ("130–134") stays.

**Template answer (`LabourContractTemplateRouter`, `GreekLegalChatRouter`)**
- A Greek answer's reason is written by the program from the chosen template («Το αίτημα ταιριάζει
  στο υπόδειγμα «Σύμβαση τηλεργασίας»: …» with its Greek description); the model's English reason
  is shown only in an English answer, and dropped from the Greek "no template" answer.
- A placeholder glued to its preposition («Στ{{place_of_signing}}», «στ{{workplace}}») is shown as a
  blank («Στ………»); the other fields keep their names.

**Foreign law (`GreekLegalAnswerFinalizer.unsupportedForeignJurisdiction`)**
- Reproduced first: «Πόσες εβδομάδες άδεια μητρότητας προβλέπει το γερμανικό εργατικό δίκαιο;»
  became "… does German labour law provide?" and was answered from the Greek Code (17 weeks,
  `abstained=false confidence=0.99`), because only "in/of/under Germany" was recognised. A
  country's adjective before a word for law ("German labour law", "French Labour Code") is now
  refused unless a passage names the country; not "European" or "English", nor a worker's
  nationality ("a German worker in Athens"). After the change the same question is refused.

**Files:** `Services/Legal/GreekLegalOpinionWriter.swift`, `GreekLegalDocumentSummarizer.swift`,
`LabourContractTemplateRouter.swift`, `GreekLegalChatRouter.swift`,
`Services/Document/Localization/LocalNeuralTranslator.swift`,
`Services/RAG/Safety/GreekLegalAnswerService.swift`; tests in `GreekLegalOpinionTests`
(`greekWordingOfTheThreeDocumentOpinionIsRepaired`, `aDecisionWithoutArticlesKeepsItsFigures`,
`statuteIsLawBeforeTranslation`), `GreekLegalSummaryTests` (`longNoteLinesAreCutAtASentenceOrClauseEnd`,
`notesKeepTheGroupsArticles` changed), `LabourContractTemplateRouterTests`
(`greekAnswerHasAGreekReasonAndABlankPlace`), `GreekLegalPipelineTests`
(`foreignJurisdictionIsRefusedUnlessAPassageNamesIt` extended). Backups of the files as they were
before this entry: `Docs/Thesis/code_backup_2026-11-09b/`.

**Verification:** the 20 Greek legal unit-test suites in the iOS Simulator (evaluation suites
excluded): `Test run with 119 tests in 20 suites passed`, `** TEST SUCCEEDED **`; Mac build
`** BUILD SUCCEEDED **`; the plan's four requests checked on screen in the Mac app.

**Still open:**
- The decision's «υπαλλήλους» and «εργατοτεχνίτες» both come back «εργαζόμενους» (the English has
  "employees" and "workers"); a glossary entry would change translation at import, so it was left.
- The summary's opening (written by the model) says the minutes are delivered after "the
  appointment of a court secretary"; Article 7 says after the election of the court
  representative. A content error of the model, not wording.
- The two empty ya_8934 copies in the «Γνωμοδότηση» library were not deleted (the owner's data);
  sources with no passages are never chosen, so they don't change the opinion.
- The thesis screenshots (Figs. 6.5–6.7) were not retaken.

## 13 Nov 2026: README for the company demo; commit identity

**Why:** the repository is being shown to a company CEO. The README was written before the PoC
work ended and had several claims the records don't support (a 0% "upstream" refusal baseline, the
fork's own first runs labelled as the original app, "Master's thesis", iOS 18 / Swift 6 / Xcode 16
requirements, a test command naming suites that don't exist).

**What:**
- `README.md` rewritten: what the app does and why (privacy, Greek documents, verified answers),
  the four capabilities with example requests, the pipeline, the components this fork added and
  the original code it changed, the results table taken from `METHODS_SUMMARY.md` §8 with how to
  read it (single runs, run-to-run variation, test split not fully held out, not re-measured after
  31 Oct / 9 Nov, no iPhone measurement), setup for Xcode 27 with Apple Intelligence and an English
  system language, the Mac as the demo target, test commands with real suite names, known
  limitations and credits.
- Commit identity: the owner's commits on all local branches were rewritten from the machine's
  host-name address to the GitHub account `alagraf` (noreply address), and the global git identity
  set to it. File contents unchanged (tree of the branch tip identical before and after); the
  original author's commits untouched. Backup refs: `refs/backup/pre-identity-rewrite/*`.
  Every fork commit got a new hash; the hashes cited in this file and the other thesis records
  are the old ones, kept as written. `Docs/Thesis/COMMIT_HASH_MAP.md` (kept on the owner's Mac and
  git-ignored, not in the repository) maps each of the 63 old
  hashes to its new one (pairs checked for the same tree, subject and author date).
- `.gitignore`: `node_modules/`, `Docs/Thesis/code_backup_*/`, `/thesis_v8_notes.md` (private
  review notes; the repository is public).

**Verification:** every README figure checked against `METHODS_SUMMARY.md` §8; suite names checked
with `grep` in `OpenIntelligenceTests/`; model sizes with `du`; deployment targets in
`project.pbxproj`. No code changed, nothing built or run.

## 13 Nov 2026 (second entry): renamed to Firiki; the released app's material removed

**Why:** the owner asked to remove every unnecessary mention of OpenIntelligence, rename what is left
to Firiki, and drop anything that belongs to a released app. Firiki is a thesis proof of concept: it
has no store listing, no purchases and no release process. Plan: `Docs/Thesis/plans/firiki-rename.md`
(approved, including `project.pbxproj`, the entitlements and the `Info.plist` files). Branch
`firiki-rename`, three commits, not merged or pushed until the owner has reviewed it.

**What:**
- *Release material deleted (commit 1):* `fastlane/`, `ci_scripts/`, `InAppEvents/`, the Gemfiles,
  `WHATS_NEW.md`, `PRIVACY.md`, the original author's root `HANDOFF.md`, the SDK's `Package.swift`,
  `.github/`, `Xrays/`, the App Store, sale, ads, screenshot and privacy-policy scripts, and the
  original app's documentation in `Docs/` except the three pipeline overviews (`HOW_IT_WORKS.md`,
  `INGESTION_PIPELINE.md`, `RETRIEVAL_PIPELINE.md`), the codemap and `Docs/Thesis/`. `CHANGELOG.md`
  keeps only the fork's 5.7 sections.
- *Billing removed, everything unlocked (commit 2):* StoreKit billing, entitlements and the quota
  policy are deleted (`Features/Billing`, `Services/Billing`, `Resources/StoreKit`, `WorkspaceTier`,
  `QuotaPolicy`, the StoreKit test scheme and configuration). Gone with them: the document, library
  and conversation limits, the daily Maximum cap, the Pro gates on iCloud and Shortcuts, the plan
  and sale screens and banners, the review, feedback and plan prompts, What's New and version
  history, the storefront lookup, the billing telemetry category, and the Plans section of the
  sample Product Guide (with its suggested question and three built-in QA cases). Share and the
  answer card link to the project's repository instead of the App Store; About says what the
  project is and credits the original app ("Built on OpenIntelligence", MIT licence). Copy Link
  uses the app's own `firiki://` link; the web form on the original author's site (`gunzino.me`)
  is removed. Tests that set a paid plan before creating a library no longer need to.
- *Rename (commit 3):* folders, files, targets, schemes, modules and types `OpenIntelligence*` →
  `Firiki*` (engine `FirikiEngine`); bundle IDs `com.openintelligence.app…` →
  `com.alagraf.firiki…`; app group `group.com.alagraf.firiki`; every other reverse-DNS ID
  (background tasks, activities, widgets, loggers, queues; `Gunndamental.OpenIntelligence` too) →
  `com.alagraf.firiki.…`; URL scheme `firiki://`; display names Firiki, Firiki Live, Firiki
  Camera; environment variables `FIRIKI_*`. One collision of the ordered replacement was fixed by
  hand: `com.openintelligence.app-refresh` → `com.alagraf.firiki.app-refresh`. The Live Activity
  icon symlink was repointed. `.gitattributes` (SDK packaging) and the original author's
  `.agent/RISK_REGISTER.md` are deleted. The codemap's three billing slices are removed and the
  nodes and edges that named deleted code pruned (`codemap.py check`: 0 errors, 43 slices).
  `AGENTS.md`: identity table updated (signing was already team `J7R6G54TG4` in all 16
  configurations, not `""` as the table said); the upstream-sync section is replaced by a note
  that merging `upstream/main` is no longer practical. Signing settings unchanged; no entitlement
  added or removed.
- *Kept on purpose:* `LICENSE` and `THIRD_PARTY_NOTICES.md`, the "Created by Gunnar Hostetler"
  file headers, the README's credits, the thesis records in `Docs/Thesis/`, `BenchmarkRuns/`,
  `Benchmarks/baselines/`, `scripts/thesis/holdout/EUHoldoutStockAppTests.swift` (it runs inside the
  original app), the DEBUG-only screenshot scenes, and the vendored `swift-transformers`.
- *Data:* the new bundle ID and data folder start empty. Libraries imported before the rename are
  not carried over and have to be imported again (the Labour Code takes about 15 minutes).

**Verification (iPhone 18 Pro simulator, iOS 27; macOS 26 build):**

| | Before (`89b73532`) | After |
|---|---|---|
| iOS test build | `** TEST BUILD SUCCEEDED **` | `** TEST BUILD SUCCEEDED **` |
| macOS build | `** BUILD SUCCEEDED **` | `** BUILD SUCCEEDED **` |
| 20 Greek legal suites | 119 tests in 20 suites passed | 119 tests in 20 suites passed |
| Full unit suite (XCTest) | 1,366 tests, 11 skipped, 4 failures | 1,288 tests, 9 skipped, 2 failures (one then fixed; its suites rerun, the full suite not) |
| Full unit suite (Swift Testing) | 128 tests in 28 suites passed | 128 tests in 28 suites passed |

The 78 fewer tests are the deleted billing, plan, rating, What's New and version-history tests and
the web-link test. Of the 4 failures before, two were billing tests (deleted), one was the passage
reveal test that needs a window scene (passed this time), and one is the Greek-region number format
(`AnswerUsageTallyTests.testTheDetailsLine`, "1.100" for "1,100"), still failing and unrelated.
The new failure (`SampleQuestionHeadingsTests`, the plans question without its heading) was fixed;
the two sample-question suites and `AppLinkTests` then passed (30 tests, 0 failures). The macOS app
launched as `com.alagraf.firiki` signed by `J7R6G54TG4`. **Not checked:** the app's screens by eye
and a PDF import under the new identity (left for the owner's review), and an iPhone build.

## 13 Nov 2026 (third entry): a Greek text layer is checked with PaddleOCR; new app icon

**Why (text layer):** the owner imported a 51-page set of Greek labour-law lecture notes, exported
from Word, and both questions asked about them were refused. Diagnosis (simulator import of the
same file): the PDF's Greek font maps to the wrong letters, so its text layer reads «Ζ ζρέζε
εμαξηεκέλεο εξγαζίαο» where the page shows «Η σχέση εξαρτημένης εργασίας». The import keeps a text
layer unless OCR of a sample page disagrees with it, but since the original author's 5.7 change
(`8bce78fb`, 2026-10-19) a page mostly in a script Vision does not read, such as Greek, is not a
sample, because Vision would misread it and flag every correct Greek PDF. So no Greek text layer
was ever checked, and the notes were stored as 632 unreadable passages whose English translations
were nonsense; PaddleOCR never ran. Not caused by the rename: the rule and the import code are the
same before and after it.

**What:**
- `DocumentProcessor.extractWithStructuredParsing`: when no sampled page is in a script Vision
  reads, the longest mostly-Greek sample page is read by PaddleOCR's Greek model
  (`OCRRouterService.greekLines`, forced) and compared with its text layer. Below the same bar as
  Vision's check (word Jaccard 0.15) the document's text layer is garbled, and every page goes
  through OCR, where the router reads Greek pages with PaddleOCR. When PaddleOCR is missing, the
  OCR mode is Vision only, or nothing is read, the text layer is kept as before.
- `DocumentProcessor.greekWordJaccard` (new, static): words of three letters or more, accents,
  case and final sigma ignored, Latin look-alike letters read as Greek.
- Test: `FirikiTests/Services/Document/Processing/GreekTextLayerCheckTests.swift` (3 tests: a
  correct layer against OCR with its usual slips, a wrong-letter layer, no words).
- Cost: one PaddleOCR page per page batch of a Greek PDF (6 s on the Labour Code excerpt).

**Why (icon) and what:** the owner supplied a new app icon (a drawn apple on an orange tile).
`AppIcon.appiconset`: every iPhone, iPad and 1024-pixel image rebuilt from it (the tile cropped
inside its bevel, its rounded corners filled with the tile's orange, scaled to 1024 from about 640
pixels); the Mac images use the same artwork inside the rounded square of the previous Mac icons
(824 on 1024, the old icon's alpha as the mask). The dark and tinted variants of the old
light-bulb icon are removed (30 files), so the system shows the orange icon in dark mode and
derives the tinted one. The Live Activity icon is a link to `AppIcon-1024.png` and follows.

**Verification:**
- Unit tests: `GreekTextLayerCheckTests` and `DocumentProcessorTests`, 20 tests, 0 failures; the
  20 Greek legal suites, 119 tests passed.
- Imports in the simulator (runs `greektextlayer0` before, `greektextlayer1` after, in
  `experiments/runs/`; EXPERIMENTS E11):

| | Lecture notes, before | Lecture notes, after | Labour Code excerpt (correct layer), after |
|---|---|---|---|
| Text-layer verdict | kept without a check | Jaccard 0.014, garbled | Jaccard 0.994, kept |
| Pages read by PaddleOCR | 0 | 54 images | 1 (the check) |
| Passages stored | 632 unreadable | 713 Greek | 692 |
| Passages with «υπερωρ» | 0 | 38 | 19 |
| Import time | 1,000 s (938 s translating junk) | 558 s | 143 s |

- Icons: `actool` compiles the set for iOS and macOS with no warnings; iOS test build
  `** TEST BUILD SUCCEEDED **` with the new icons.
- **Not checked:** answers to the owner's two questions (the simulator has no Apple Intelligence;
  to be asked in the Mac app after re-importing the notes). The notes have no article 58, so that
  question is still refused unless the Labour Code is in the library.

## 14 Nov 2026: re-measurement recorded, README updated, `firiki-rename` merged into `main`

**Why:** the owner asked to record the re-measurement of the full suite and the README's
evaluations (EXPERIMENTS E12), update the README to match, and merge the branch.

**What:** ten run files `experiments/runs/firiki-*.txt` and their index rows; E12 in
`EXPERIMENTS.md`; four rows and a revision line in `METHODS_SUMMARY.md` §8. `README.md`: a
"Nov re-run" column in Results (templates 44 of 44 / 20 of 22, summary 5 of 6 / 4 of 5, opinion
citations 10 of 12 / 5 of 8, OCR 95% / 97% with the scoring change noted), the summary test split
marked as no longer held out, the Greek text-layer check in "How it works" and in the changes to
the original app, the rename and billing removal under Repository, and in "Tests and
evaluations" how to import the library the summary and opinion evaluations need, the full-suite
command with its one known failure, and the `/tmp` cleanup workaround. `main` fast-forwarded to
`firiki-rename` (no merge commit); nothing pushed.

**Verification:** documentation only; the results are those of E12.

## 14 Nov 2026 (second entry): CEO demo quick wins

**Why:** the owner asked for a demo-readiness audit (`POC_PROGRESS.md`) and approved its quick wins
(`Docs/Thesis/plans/demo-quick-wins.md`), as one commit, with "as many template requests as
possible recognised". The audit found the chat's capability rules sent ordinary questions to a
capability («Τι ισχύει για τη σύμβαση εργασίας για ορισμένο χρόνο;» opened a template, "In your
opinion…" an opinion, «περίληψη των δικαιωμάτων της εγκύου» a summary), missed requests typed
without accents, and recognised none of the 40 naturally worded template requests of the routing
dev split. Failures showed raw error text, a refused opinion in the sheet showed an empty card, a
summary or opinion showed the "embedding" stage for minutes, and its details showed 0.000 s and 0
tokens.

**What:**
- `GreekLegalChatRouter.swift`:
  - every rule runs on the prompt folded like the Greek keyword index (`greekSearchFold`);
  - an explicit template request (a template noun near a contract noun, «ποιο υπόδειγμα»,
    "which … template … use", "Contract for …", «τι σύμβαση χρειάζομαι/κάνουμε/υπογράφουμε»)
    always opens a template;
  - a new intent, `possibleContractRouting`, covers a described hiring or work arrangement (a
    contract noun with a request verb, not a yes/no question; "which contract"; hiring phrases
    such as «θέλω να πάρω», "I need someone", not opening as a question). The template router
    runs, and when no template fits the prompt goes on to ordinary Q&A;
  - removed rules: «σύμβαση (εργασίας) για», «ποια σύμβαση», "labour contract", a bare
    "opinion";
  - a summary needs a document word or a named statute;
  - `extractDocumentTarget` works on folded text; its last pattern was an unbounded look-behind,
    which ICU rejects, so it never ran; it is now an ordinary capture;
  - `failureMessage(for:greek:task:)` gives fixed Greek/English text for each FoundationModels
    `GenerationError` case, missing translation models, cancellation and anything else; the
    technical detail goes to the log only;
  - `modelUnavailableMessage(greek:)` is checked before a summary or opinion;
  - capability answers carry their real duration (`ContinuousClock`);
  - English requests get English headers and messages ("### Summary:", "Applicable provisions",
    empty library, which document, no passages);
  - a Greek opinion refusal is in Greek.
- `GreekLegalOpinionWriter.swift`: `Opinion.refusalGreek` (the English `refusal` stays for the
  evaluation logs).
- `GreekLegalAssistantSheet.swift`: the opinion and summary tabs check the model first and show
  fixed messages; a refused opinion shows its reason as a notice instead of an empty card.
- `ChatScreen.swift`: the intent is detected first, a capability sets the "generating" stage, and
  a request stopped while a capability ran is neither answered nor passed on to Q&A.
- `ResponseDetailsView.swift`: the tokens stat, "Tokens Generated" and "Retrieval Time" are hidden
  when 0.
- Tests:
  - `GreekLegalChatRouterTests`: 7 former misroutes stay Q&A; unaccented and capitals requests;
    described arrangements; routing dev split ≥ 38 of 40 recognised and its "none" questions
    Q&A; every Labour Code, library and opinion dev question not sent to a template or summary;
    failure messages never contain the technical error and are in the request's language; Greek
    refusal reasons.
  - «Ποια σύμβαση εργασίας προβλέπεται για μαθητεία;» moved from the template cases to the
    questions (the owner agreed).
  - `AnswerUsageTallyTests.testTheDetailsLine` builds "1,100" with the locale's own formatting, so
    it passes on a Mac set to the Greece region.

**Verification:**
- Targeted suites (`thesis_run_tests.sh`, `-only-testing:` GreekLegalChatRouterTests,
  GreekLegalOpinionTests, GreekLegalSummaryTests, LabourContractTemplateTests,
  AnswerUsageTallyTests, GreekLegalVerificationTests): `** TEST BUILD SUCCEEDED **`; "Test run
  with 56 tests in 5 suites passed"; AnswerUsageTallyTests "Executed 5 tests, with 0 failures";
  the log prints "[ChatRouter] routing dev: 38 of 40 template requests recognised".
- Full unit suite: "Executed 1291 tests, with 8 tests skipped and 0 failures" (the Greece-region
  failure is gone); "Test run with 136 tests in 28 suites passed" (128 before).
- macOS build (`xcodebuild build -scheme Firiki -destination 'platform=macOS'`):
  `** BUILD SUCCEEDED **`.
- Measured recognition: EXPERIMENTS E13.
- **Not checked:** the stage indicator, messages and details view in the Mac app with Apple
  Intelligence (the simulator has no model); the template router's answer for a described
  arrangement that it judges "none" (falls back to Q&A by code, not yet seen in the app).

## 14 Nov 2026 (third entry): a summary finds its document by the statute it is

**Why:** deeper fix 2 of `POC_PROGRESS.md`; plan `Docs/Thesis/plans/summary-by-statute-key.md`,
approved by the owner. A chat summary request found its document by filename only: a statute saved
under a name without its number («ΦΕΚ Α 22.pdf») got "which document?"; the number was matched as a
substring ("62" in "…b1762…") whatever its kind; and a library of one document had that document
summarised whatever statute the request named («σύνοψη του ν. 5278/2026» over the Labour Code).
Every document already records its own statute at import (`documentStatuteKey`, 2.11.27).

**What:**
- `GreekLegalChatRouter.swift`:
  - `matchDocument(query:target:in:statuteKeys:)` returns a `SummaryTarget`: the document, a
    statute not in the library, or none named. It tries a statute named with its kind
    (`requestedStatutes`, `sameStatute`), then the number and year against the documents'
    statutes of any kind («νόμου 5239»; «ν. 62/2025» finds the Labour Code, a decree), then
    whole numbers in the filename for documents without a statute;
  - the one-document shortcut applies only when the request names no statute; a statute not in
    the library gets «Δεν υπάρχει στη βιβλιοθήκη: ν. 5278/2026.» and the list of documents;
  - the list shows each document's statute and file («- ν. 5278/2026 (n_5278_2026_fek_a22.pdf)»),
    and the summary heading shows the statute («### Σύνοψη: ν. 5278/2026») when it is known;
  - `greekStatuteName(_:)`, `statuteName(_:greek:)`, `documentList(_:statuteKeys:greek:)`;
  - `extractDocumentTarget` reads a law number of 1–5 digits after «ν.»/«νόμου» (was exactly 4).
- `RAGService.swift`: `documentStatuteKeys(containerId:documentIds:)`, moved out of
  `greekLegalStatuteScope`, which now calls it (Q&A unchanged).
- `GreekLegalChatRouterTests`: `matchDocumentInLibrary` replaced by tests over the five demo
  documents under their real names and renamed, the kind asked for winning over the same number,
  whole-number filename matching, a statute not in the library never swapped for another, the
  Constitution, an unnamed request, and the statute names and document list.
- Deeper fix 6 (`try!` patterns in the masker and title-page reader): already covered, since the
  existing masker and `documentStatuteKey` tests build every one of them; no change.

**Verification:**
- `thesis_run_tests.sh -only-testing:FirikiTests/GreekLegalChatRouterTests`:
  `** TEST BUILD SUCCEEDED **`; "Test run with 20 tests in 1 suite passed"; each new test (and the
  7 cases of `summaryFindsTheStatuteByItsKey`) logged as passed.
- Full unit suite: "Executed 1291 tests, with 8 tests skipped and 0 failures"; "Test run with 142
  tests in 28 suites passed" (136 before).
- macOS build (`xcodebuild build -scheme Firiki -destination 'platform=macOS'`):
  `** BUILD SUCCEEDED **`.
- **Not checked:** a summary in the Mac app with Apple Intelligence and the imported library.

## 14 Nov 2026 (fourth entry): three display bugs from the Mac rehearsal; «Συνόψισε»

**Why:** the owner asked Claude Code to rehearse the demo in the Mac app (`POC_PROGRESS.md`, "Mac
rehearsal") and then to fix the three display bugs it found. The owner also corrected the summary
example: the imperative is «Συνόψισε», not «Σύνοψε».

**What:**
- `GreekLegalOpinionWriter.swift`: the translation step takes the sources' file names
  (`translate(text, documentNames)`), and the default passes them to
  `translateEnglishToGreekPreservingCitations(_:documentNames:)`, as Q&A does. Without them only a
  name without spaces was masked: «ΑΤΟΜΙΚΟ ΕΡΓΑΤΙΚΟ ΔΙΚΑΙΟ.pdf» came back «ΔΙΚΑΙΟ.pdf».
- `Firiki/Resources/LabourContractTemplates/*.md` (all 10): the signature table, which the chat
  shows as raw `| … |` and `|---|`, is two lines, «**Ο εργοδότης:** {{employer_representative}}»
  and «**Ο/Η εργαζόμενος/η:** {{employee_name}}».
- `ChatScreen.swift`: when a capability starts, the previous answer's reasoning steps and final
  time are cleared (the bar showed "Confidence: high · 73% P(correct)" and 26.2 s during an
  opinion); when it ends, the bar shows its own duration.
- «Σύνοψε» → «Συνόψισε» in `README.md` and the router tests; the summary-target pattern accepts
  any «συνοψ…» word (the summary rule already did).
- Tests: `theTranslatorGetsTheSourcesFileNames` (GreekLegalOpinionTests),
  `templatesHaveNoTablesAndBothSignatures` (LabourContractTemplateTests); the three opinion tests
  that inject a translator take the new parameter.

**Verification:**
- `thesis_run_tests.sh` with GreekLegalOpinionTests, LabourContractTemplateTests and
  GreekLegalChatRouterTests: `** TEST BUILD SUCCEEDED **`; "Test run with 39 tests in 3 suites
  passed"; both new tests logged as passed.
- macOS build (`xcodebuild build -scheme Firiki -destination 'platform=macOS'`):
  `** BUILD SUCCEEDED **`.
- Mac app (new build, library of 7 documents): the opinion shows «ΑΤΟΜΙΚΟ ΕΡΓΑΤΙΚΟ ΔΙΚΑΙΟ.pdf»
  whole; the template's signatures are two lines; the bar shows a live timer instead of the
  previous answer's confidence and time, and the template's own time (2.5 s) after it.
- Full unit suite: "Executed 1291 tests, with 8 tests skipped and 0 failures"; "Test run with 144
  tests in 28 suites passed" (142 before).
- Also in this entry (owner's choice after the rehearsal): when several documents match a summary
  request at the same step, `matchDocument` takes the one with the most passages (`fullest`). An
  excerpt of Law 5278/2026 imported before the whole law names the same statute on its title page,
  and «Συνόψισε το ν. 5278/2026» summarised the excerpt's Articles 7 and 8. Test
  `theFullestDocumentOfAStatuteWins` (by key and by filename); GreekLegalChatRouterTests "Test run
  with 21 tests in 1 suite passed"; macOS build `** BUILD SUCCEEDED **`. Mac app: the summary now
  covers Articles 3–13 of the whole law, in 1 min 23 s.

## 14 Nov 2026 (fifth entry): an opinion reads the whole amending article; passages not numbered

**Why:** the demo's overtime opinion concluded "four hours a day not allowed". Diagnosis
(`POC_PROGRESS.md`): the three passages kept for Law 5239/2025 left out the end of its Article 7,
which restates Article 194 par. 3 («έως τέσσερις (4) ώρες ημερησίως … 150 … 40%»). Plan
`Docs/Thesis/plans/opinion-whole-amending-article.md`, approved by the owner. With the whole
article the model wrote the rule but cited it as "Article 6", the passage's `[6]` number in the
prompt, and the check dropped it; the owner approved removing the numbers.

**What:**
- `GreekLegalOpinionWriter.swift`:
  - `withWholeAmendingArticles(_:links:documents:)`: a source whose passages include an article
    that amends or adds a Code article reads that whole article in chunk order, then its other
    passages, within `sectionCharacters` (the summarizer's `groupCharacters`, 7,372 characters).
    Other sources are unchanged;
  - `RAGService.greekLegalOpinion` applies it after `selectSources`;
  - `sectionPrompt` separates passages with a `---` line instead of numbering them.
- `GreekLegalOpinionTests`: `aSourceReadsTheWholeAmendingArticle` (order, Article 8 not added,
  the Code and an unlinked source unchanged, the budget cut); the section test checks that no
  `[n]` numbers remain and that passages are separated.

**Verification:**
- `thesis_run_tests.sh -only-testing:FirikiTests/GreekLegalOpinionTests`: `** TEST BUILD
  SUCCEEDED **`; "Test run with 14 tests in 1 suite passed".
- Opinion dev split (EXPERIMENTS E14): citations 10 of 12, key facts 15 of 20, refused 0 of 6
  (11 of 20 before); nothing dropped by the article check.
- macOS build (`xcodebuild build -scheme Firiki -destination 'platform=macOS'`):
  `** BUILD SUCCEEDED **`.
- Mac app: case 1's wording gets a correct conclusion; the demo's short question still does not
  (the Code's sixth-day Article 191 is retrieved).
- Full unit suite: "Executed 1291 tests, with 8 tests skipped and 0 failures"; "Test run with 146
  tests in 28 suites passed" (144 before).
- Follow-up (owner's request): the README's opinion example is now the evaluation's wording of the
  overtime question («Ο εργοδότης ζητά από υπάλληλο πενθήμερης εργασίας … Θέλω γνωμοδότηση.»), which
  gets the right conclusion in the Mac app; the short form («Θέλω γνωμοδότηση: … Επιτρέπεται;») still
  does not. Documentation only.

## 14 Nov 2026 (sixth entry): translation placeholders repaired

**Why:** POC_PROGRESS open item; plan `Docs/Thesis/plans/placeholder-leftovers.md` (the owner said
to continue without approvals). 441 of 6,336 English passages of the five-document library kept
placeholders the translator had mangled, which the unmask pattern (LEX and ENT both required)
missed; the model copied them, and a Greek opinion showed «__ΕΧΝ.».

**What:**
- `GreekLegalEntityMasker.swift`:
  - `placeholderPattern` accepts the mangled forms (LEX or EX without ENT, ENT without LEX, doubled
    ENT, underscores and spaces, leading zeros); one of the words must stand before an underscore
    and the number;
  - new `removingPlaceholderDebris(_:)`, `hasPlaceholderDebris(_:)` (a placeholder without an
    entity, a word left without its number, looping runs of five or more underscores);
  - new `repairingLeftovers(_:)` unmasks a stored passage with its own entity list (bilingual
    anchors) and removes the debris.
- `LocalNeuralTranslator.swift`: debris removed after the Greek→English unmask at import, from the
  model's English before English→Greek translation, and from the Greek result.
- `BNNSVectorDatabase.swift`: every passage read (`decodePassage`, and the whole-file fallback) is
  repaired; the file and embeddings are unchanged until the next save or re-import.
- `GreekLegalPipelineTests` (masker suite): the seven forms found, debris removal with ordinary
  text, blanks, template fields and file names kept, and a stored Labour Code passage repaired.

**Verification:**
- `thesis_run_tests.sh` with GreekLegalEntityMaskerTests, GreekLegalOpinionTests,
  GreekTranslationRetrievalTests: `** TEST BUILD SUCCEEDED **`; "Test run with 36 tests in 3 suites
  passed".
- Leftovers in the Simulator's stored passages: 450 of 8,022 before, 0 after (EXPERIMENTS E15).
- Opinion dev 10 of 12 / 13 of 20; library Q&A dev 15 of 24; opinion test 4 of 8 / 8 of 10
  (EXPERIMENTS E15).
- macOS build (`xcodebuild build -scheme Firiki -destination 'platform=macOS'`):
  `** BUILD SUCCEEDED **`. Mac app: the overtime opinion has no placeholder.
- Full unit suite: "Executed 1291 tests, with 8 tests skipped and 0 failures"; "Test run with 149
  tests in 28 suites passed" (146 before).

## 14 Nov 2026 (seventh entry): summaries and opinions survive model errors; Stop between passes

**Why:** deeper fixes 1 and 3 of `POC_PROGRESS.md`; plan `Docs/Thesis/plans/model-errors-and-stop.md`
(the owner asked to continue without approvals). Any model error in one pass ended the whole
summary or opinion, and Stop took effect only after every pass. The OS 27 SDK also deprecates
`LanguageModelSession.GenerationError` for `LanguageModelError`, `SystemLanguageModel.Error` and
`LanguageModelSession.Error`, which `failureReason` did not map.

**What:**
- New `Firiki/Services/Legal/GreekLegalModelCall.swift`:
  - `failure(of:)` classifies both error families;
  - `respond(...)` runs one pass: it checks cancellation, retries with the prompt body cut to 60%
    then 35% (`shortened`, header kept) when too long, retries once after 1 s when busy, and
    throws `Declined` when the model refuses.
- `GreekLegalDocumentSummarizer.summarize`:
  - map and opening calls go through it;
  - a declined group is skipped, and a declined opening leaves the list of provisions;
  - nothing left throws `Declined`;
  - cancellation is checked before translation;
  - new `declinedAsNil(_:)`.
- `GreekLegalOpinionWriter.write`:
  - section and conclusion calls go through it;
  - a declined section is skipped;
  - a declined conclusion refuses with "the model declined to write the conclusion" (and its
    Greek);
  - cancellation is checked before each translation and before each document's search.
- `GreekLegalChatRouter.failureReason`: maps through `GreekLegalModelCall.failure`, so OS 27 errors
  and `Declined` get their specific messages.
- New `FirikiTests/Services/GreekLegal/GreekLegalModelCallTests.swift` (8 tests).

**Verification:**
- `thesis_run_tests.sh` with GreekLegalModelCallTests, GreekLegalOpinionTests,
  GreekLegalSummaryTests, GreekLegalChatRouterTests: `** TEST BUILD SUCCEEDED **`; "Test run with
  51 tests in 4 suites passed".
- Opinion and summary dev sets (EXPERIMENTS E16): no retry or decline logged; opinion dev
  identical to E15.
- macOS build (`xcodebuild build -scheme Firiki -destination 'platform=macOS'`):
  `** BUILD SUCCEEDED **`.
- Mac app: Stop during an opinion goes idle in about 0.3 s, and the log shows no pass after it.
- Full unit suite: "Executed 1291 tests, with 8 tests skipped and 0 failures"; "Test run with 157
  tests in 29 suites passed" (149 in 28 before).

---

## 14 Nov 2026 (eighth entry): Demo Mode hides inherited upstream screens

**Why (`POC_PROGRESS.md`, deeper fix 5):** An audit showed three inherited upstream areas
reaching or risking exposure during the legal-assistant demo:

1. `Features/Telemetry/Visualizations/` (`Embedding3DView`, `AdaptiveVisualizationsView`,
   `VisualizationsView`): already unreachable anywhere in the live app (only `#Preview` blocks and
   a comment in `DocumentLibraryView.swift`).
2. `Features/Telemetry/Dashboard/TelemetryDashboardView.swift`: reachable under
   `Settings -> Developer & Diagnostics -> Telemetry`.
3. `Features/Database/DatabaseDashboardView.swift`: always shown as top-level `Tab.database`
   ("Database") in `ContentView.swift`.
4. `UnifiedMetricsBar`, `CompactChatHeader`'s chunk-count chip, and hardware HUD overlays: gated by
   `showTechnicalDetails` / `showSiliconHUD`, where `SettingsStore` defaults `showTechnicalDetails`
   to `true` on an existing install that has a saved `llmTemperature`.

**What changed:**

- Plan saved in `Docs/Thesis/plans/demo-mode.md`.
- `Firiki/Services/Infrastructure/Configuration/SettingsStore.swift`: added `DemoModePreference`
  (`key = "demoMode"`, `defaultValue = true`, plus `isEnabled(in:)`,
  `effectiveShowTechnicalDetails(in:)` and `effectiveShowSiliconHUD(in:)`).
- `Firiki/App/ContentView.swift`: hides `Tab.database` when `demoMode` is on (unless
  `screenshotMode.initialTab == .database`), and returns `selectedTab` to `.chat` if `demoMode` is
  turned on while viewing `.database`.
- `Firiki/Features/Chat/Conversation/ChatScreen.swift` & `Firiki/Features/Database/DatabaseDashboardView.swift`:
  gate `HardwareXRayOverlay`, `UnifiedMetricsBar`, `.showsTechnicalDetails` environment,
  `CompactChatHeader` chunk count, and the iOS/macOS chat menu `"Technical Details"` toggles on
  `!demoMode`.
- `Firiki/Features/Settings/SettingsView.swift`: hides `.developer` (`Developer & Diagnostics`) when
  `demoMode` is on, gates `HardwareXRayOverlay`, and adds a `"Demo Mode"` toggle (searchable by
  `"demo"`) in `System`; keeps `Telemetry HUD` / `Technical Details` inside `Appearance` so UI
  accessibility tests stay compatible.
- `FirikiTests/Services/Infrastructure/SettingsPersistenceTests.swift`: added
  `testDemoModeDefaultsOnAndGatesTechnicalTelemetry()`.

**Verification:**

- `SettingsPersistenceTests`: `./scripts/thesis_run_tests.sh /private/tmp/demo-mode-unit.log -only-testing:FirikiTests/SettingsPersistenceTests` → `** TEST BUILD SUCCEEDED **`, `Executed 5 tests, with 0 failures (0 unexpected) in 0.492 (0.500) seconds`, `** TEST EXECUTE SUCCEEDED **`.
- macOS build: `xcodebuild build -scheme Firiki -destination 'platform=macOS' -derivedDataPath /private/tmp/oi-mac` → `** BUILD SUCCEEDED **`.
- Full unit suite: `./scripts/thesis_run_tests.sh /private/tmp/demo-mode-full.log` → `** TEST BUILD SUCCEEDED **`, `Executed 1292 tests, with 8 tests skipped and 0 failures (0 unexpected)`, `Test run with 157 tests in 29 suites passed`.
- UI tests: `xcodebuild test -scheme FirikiUITests -destination "platform=iOS Simulator,name=iPhone 18 Pro" -derivedDataPath /private/tmp/oi-build -only-testing:FirikiUITests/AccessibilityAuditTests` → `Executed 2 tests, with 0 failures (0 unexpected) in 89.741 (89.752) seconds`, `** TEST SUCCEEDED **`.

---

## 14 Nov 2026 (ninth entry): Phase 2b end-to-end Q&A, 5-PDF import tests, Mac smoke test and demo check

**Why (`POC_PROGRESS.md`, Phase 2b flows 3–4 + manual smoke test):** Phase 2b already covered
intent routing, capability errors, and template/summary routing, leaving end-to-end Greek Q&A over
a stand-in model, real-ONNX verification of all five demo PDFs and bundled ONNX models, an opt-in
`"My Mac"` smoke XCUITest over the four README prompts, and a single `scripts/demo_check.sh`
command.

**What changed:**

- Plan saved in `Docs/Thesis/plans/phase-2b-tests.md`.
- `Firiki/Features/Chat/Conversation/ChatComposerV2.swift`: added accessibility identifiers
  (`chatComposerField`, `sendMessageButton` / `stopGenerationButton`) and button accessibility
  labels (`"Send message"` / `"Stop generating"`).
- `FirikiTests/Services/GreekLegal/GreekLegalEndToEndFakeTests.swift` (new): 4 end-to-end tests
  using `GreekFakeLLMService` (real Opus-MT ingestion + query translation, hybrid retrieval, gates
  A–I, Greek back-translation, explicit async library cleanup):
  - `greekQuestionReturnsGreekAnswerWithArticleCitation()`
  - `questionAboutMissingLawReturnsFixedGreekRefusal()`
  - `questionWithUnsupportedNumberAbstainsInGreek()` (verifies Gate C `Numeric Sanity` in `gatingDecision` and fixed Greek refusal)
  - `answerCitingWrongStatuteAbstainsInGreek()` (verifies Gate F / Gate I failure in `gatingDecision` and fixed Greek refusal)
- `FirikiTests/Services/GreekLegal/GreekDemoPDFImportTests.swift` (new):
  - `bundledOCRAndTranslationModelsExist()`: checks bundled Opus-MT `el→en` / `en→el` and PaddleOCR `PP-OCRv5_mobile_det.onnx`, `el_PP-OCRv5_mobile_rec.onnx`, `el_dict.txt`.
  - `demoPDFExtractsStatuteArticlesAndBilingualText(_:)` (parameterized over all 5 demo PDFs: `PD:62/2025`, `LAW:5239/2025`, `LAW:5278/2026`, `LAW:5316/2026`, `MD:8934`): checks minimum chunk count, statute key detection, distinct article counts, Greek source preservation, and real Opus-MT translation of sampled Greek chunks.
  - `ragServiceIngestsCompactDemoPDFsWithBilingualPersistence()`: runs full `RAGService.ingestDocuments` + SQLite/BNNS persistence + cleanup on `n_5278_2026_fek_a22.pdf` and `ya_8934_2026_fek_b1759.pdf`.
  - Opt-in `fullFivePDFEndToEndImport()` gated on `OI_FULL_PDF_IMPORT=1`.
- `FirikiUITests/DemoSmokeUITests.swift` (new): opt-in (`OI_DEMO_SMOKE=1` /
  `TEST_RUNNER_OI_DEMO_SMOKE=1`, `#if os(macOS)` / iOS compatible) UI smoke test asking the four
  README prompts and checking for grounded Greek responses without error banners.
- `scripts/demo_check.sh` (new executable): runs `./scripts/thesis_run_tests.sh` across `FirikiTests`,
  and when `DEMO_SMOKE=1` runs `DemoSmokeUITests` on `platform=macOS`.
- `POC_PROGRESS.md`: ticked Phase 2b flows 3 and 4 and the manual smoke test.

**Verification:**

- `./scripts/demo_check.sh` (`FIRIKI_TESTS`):
  - `** TEST BUILD SUCCEEDED **`
  - `Executed 1292 tests, with 9 tests skipped and 0 failures (0 unexpected) in 296.626 (297.004) seconds`
  - `✔ Test greekQuestionReturnsGreekAnswerWithArticleCitation() passed after 39.719 seconds.`
  - `✔ Test questionAboutMissingLawReturnsFixedGreekRefusal() passed after 68.248 seconds.`
  - `✔ Test questionWithUnsupportedNumberAbstainsInGreek() passed after 16.388 seconds.`
  - `✔ Test answerCitingWrongStatuteAbstainsInGreek() passed after 9.754 seconds.`
  - `✔ Test bundledOCRAndTranslationModelsExist() passed after 0.124 seconds.`
  - `✔ Test demoPDFExtractsStatuteArticlesAndBilingualText(_:) with 5 test cases passed after 540.292 seconds.`
  - `✔ Test ragServiceIngestsCompactDemoPDFsWithBilingualPersistence() passed after 82.490 seconds.`
  - `✔ Test run with 165 tests in 31 suites passed after 623.051 seconds.`
- macOS UI test compile check: `xcodebuild build-for-testing -scheme FirikiUITests -destination 'platform=macOS' -derivedDataPath /private/tmp/oi-mac-build CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=""` → `** TEST BUILD SUCCEEDED **` (`DEMO_SMOKE=1` live run on `"My Mac"` deferred to owner with pre-imported library and provisioning profile).
- UI tests (iPhone 18 Pro Simulator): `xcodebuild test -scheme FirikiUITests -destination "platform=iOS Simulator,name=iPhone 18 Pro" -derivedDataPath /private/tmp/oi-build -only-testing:FirikiUITests/AccessibilityAuditTests -only-testing:FirikiUITests/DemoSmokeUITests` → `Executed 3 tests, with 1 test skipped and 0 failures (0 unexpected) in 83.779 (83.787) seconds`, `** TEST SUCCEEDED **` (`AccessibilityAuditTests`: `2` passed; `DemoSmokeUITests`: `1` skipped without `TEST_RUNNER_OI_DEMO_SMOKE=1`).

## 14 Nov 2026 (tenth entry)

**Why:** The short daily overtime question («Θέλω γνωμοδότηση: ο εργοδότης ζητά τέσσερις ώρες υπερωρία την ημέρα. Επιτρέπεται;», dev case 11 in `Benchmarks/GreekLabourLibrary/opinion_qa_v1.jsonl`) previously concluded *"not allowed"* under sixth-day Labour Code Article 192: opinion search dropped the Greek query in scoped retrieval, `PD:62/2025` (Articles 191–192 at `0.58`) appeared before later amending `Law 5239/2025` Article 7 (`0.57`), `relativeScore = 0.6` kept noisy `Law 5278/2026` (`0.37`), standalone «Επιτρέπεται;» translated as `"May I?"`, and prompts did not separate special-case limits from general `"up to"` limits (`Docs/Thesis/plans/short-overtime-opinion.md`, `EXPERIMENTS.md` E17).

**What:**

- `Benchmarks/GreekLabourLibrary/opinion_qa_v1.jsonl`: added Q11 (`split: "dev"`, short daily overtime question expecting `n_5239_2025_fek_a178.pdf` art. 7, `pd_62_2025_fek_a121.pdf` art. 194, 4 hours and 150 hours).
- `Firiki/Services/RAG/Orchestration/RAGService.swift`:
  - Added `normalizedGreekQuery(_:)` in `greekQueryTranslation` turning standalone impersonal `"Επιτρέπεται;"` into `"Επιτρέπεται αυτό;"` (`"Is that allowed?"` instead of `"May I?"`).
  - Added defaulted `originalQuery: String? = nil` parameter to `searchDocumentsRaw` forwarding to `hybridSearch.search`.
- `Firiki/Services/Storage/SQLiteFullTextService.swift`:
  - Extracted shared `greekQueryStems(_:)` helper used by both `greekFTSQuery(_:)` and scoped retrieval, and added `"επιτρεπεται"`, `"επιτρεπονται"`, `"επιτρεπτο"` to `greekQueryStopWords`.
- `Firiki/Services/RAG/Retrieval/HybridSearchService.swift`:
  - Updated `searchInsideScope` to query both English FTS5 (`searchChunks(query: query, ...)`) and `SQLiteFullTextService.shared.searchGreekChunks` for Greek scoped queries, and score `greekQueryStems` against `sourceTextEl` alongside English tokens against `content`.
- `Firiki/Services/Legal/GreekLegalOpinionWriter.swift`:
  - Added `strippedOpinionFraming(_:)` so opinion-request prefixes/suffixes do not pollute retrieval/prompts while `Ερώτημα` preserves the verbatim question; passed `originalQuery: searchQuestion` to `searchDocumentsRaw`.
  - Raised `relativeScore` (`0.6 → 0.68`) and ordered later statutes ahead of codified `PD:62/2025` in `selectSources`.
  - Updated `withWholeAmendingArticles` to expand only the top-scoring amending article in `source.passages` so neighbouring multi-chunk articles (`ART:8`) do not flood `ART:7`.
  - Updated `sectionInstructions` and `conclusionInstructions` so general `"up to"` limits govern over special-case arrangements unless the question asks about those special cases.
- `FirikiTests/Services/GreekLegal/GreekLegalOpinionTests.swift`: added `opinionFramingIsStrippedAndLaterLawsPrecedeTheCode()`.

**Verification:**

- `TEST_RUNNER_OI_GREEK_OPINION=1 TEST_RUNNER_OI_GREEK_OPINION_SPLIT=dev ./scripts/thesis_run_tests.sh /private/tmp/opinion-dev-e17-after5.log -only-testing:FirikiTests/GreekLegalOpinionTests -only-testing:FirikiTests/GreekLegalOpinionEvaluation`:
  - `** TEST BUILD SUCCEEDED **`
  - `✔ Test run with 16 tests in 2 suites passed after 218.982 seconds.`
  - `[GreekOpinion] | 11 | dev | written | citations 2 of 2 | other articles cited [12, 188, 191, 192] | facts 2 of 2 | dropped 0 | 27 s |` (`Συμπέρασμα`: permits 4 hours/day, up to 150 h/yr under `n. 5239/2025` art. 7 amending art. 194, replacing baseline `"not allowed"` under art. 192)
  - `[GreekOpinion] summary split=dev: citations 12 of 14, key facts 15 of 22, refused 0 of 7`
- `TEST_RUNNER_OI_GREEK_EVAL=1 TEST_RUNNER_OI_GREEK_EVAL_SET=GreekLabourLibrary TEST_RUNNER_OI_GREEK_EVAL_SPLIT=dev ./scripts/thesis_run_tests.sh /private/tmp/library-dev-e17.log -only-testing:FirikiTests/GreekConstitutionEvaluationTests`:
  - `✔ Test run with 1 test in 1 suite passed after 1155.432 seconds.`, `[GreekEval] summary set=GreekLabourLibrary corpus=library split=dev: passed 14 of 24` (`right documents retrieved 21 of 21`)
- `./scripts/thesis_run_tests.sh /private/tmp/task3-pipeline.log -only-testing:FirikiTests/GreekKeywordArmTests -only-testing:FirikiTests/GreekTranslationRetrievalTests`:
  - `✔ Test run with 15 tests in 2 suites passed after 3.169 seconds.`

## 14 Nov 2026 (eleventh entry)

**Why:** Numbered statute paragraphs (such as `"4. …"`) and statutory references (`"… παρ. 4. …"`) in Greek legal summaries and answers were split onto standalone lines by `MarkdownParser.normalizeInlineMarkdown` (`(?<=[.!?:]) +(\d+[.)]\s)`) and parsed as `.numberedList`, rendering an isolated paragraph as a lone Markdown numbered-list circle badge (`4`, e.g. under Article 8 of Law 5278/2026) (`Docs/Thesis/plans/summary-numbered-list.md`).

**What:**

- `Firiki/Core/Extensions/MarkdownRenderer.swift`:
  - Restricted mid-line numbered-list splitting in `normalizeInlineMarkdown(_:)` to lines carrying a genuine inline ordered sequence (`1. … 2. …`, or `1. …` continued on the next line by `2. `), leaving inline references such as `"παρ. 4. …"` and mid-paragraph numbered sentences inside the same paragraph.
  - Added `startsNumberedList(at:in:)` to `MarkdownParser`: a `N. ` / `N) ` line starts `.numberedList` only if `N == 1` or it is followed in the same list block by `N + 1`, so an isolated statute paragraph (`"4. …"`) stays a `.paragraph` and does not split `.bulletList` continuations.
  - Extended `MarkdownParserTesting` (`#if DEBUG`) with `parseBlockKinds(_:)`.
- `FirikiTests/Core/Extensions/MarkdownRendererNumberedListTests.swift` (new): 4 unit tests covering isolated `"4. …"` paragraphs, inline `"παρ. 4. …"` references, inline `"1. **…** 2. **…**"`, multi-line `1./2./3.`, and sequential `4./5.` continuation lists.

**Verification:**

- `./scripts/thesis_run_tests.sh /private/tmp/task4-markdown.log -only-testing:FirikiTests/MarkdownRendererNumberedListTests -only-testing:FirikiTests/MarkdownRendererHorizontalRuleTests -only-testing:FirikiTests/GreekLegalSummaryTests`:
  - `** TEST BUILD SUCCEEDED **`
  - `MarkdownRendererHorizontalRuleTests`: `Executed 15 tests, with 0 failures (0 unexpected) in 0.020 (0.044) seconds`
  - `MarkdownRendererNumberedListTests`: `Executed 4 tests, with 0 failures (0 unexpected) in 0.005 (0.007) seconds`
  - `GreekLegalSummaryTests`: `✔ Test run with 8 tests in 1 suite passed after 0.031 seconds.`
- `xcodebuild build -scheme Firiki -destination 'platform=macOS' -derivedDataPath /private/tmp/oi-mac CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=""`: `** BUILD SUCCEEDED **`.

## 14 Nov 2026 (twelfth entry)

**Why:** Since E15 (`firiki-summary-dev3`), the Law 5278/2026 summary (`dev`) cited `2 of 3` articles (`Article 3` missing; its notes merged under an early TOC chunk for `Article 5`), skipped 19 article chunks containing inline cross-references because `components(separatedBy: "Article ")` counted body references as TOC headings, packed `Article 6 + Article 7 + Article 8` into one map group (`Article 8` lost its rule that all normative terms continue after three months), and left echoed `=== Article N: Title ===` lines in notes (`Docs/Thesis/plans/summary-dev-article8.md`, `EXPERIMENTS.md` E18).

**What:**

- `Firiki/Services/Legal/GreekLegalDocumentSummarizer.swift`:
  - Updated `articles(from:)` to count line-starting `Article` headings when filtering table-of-contents passages and drop any leading TOC entries before `Article 1` when `Article 1` is present.
  - Updated `groups(of:limit:maxArticles:)` to cap map groups at `maxArticles = 2` for articles (`nil` when summarizing part-chunked ministerial decisions).
  - Updated `mapInstructions(lines:parts:)` to ask for exact scope words and each distinct rule/time stage on its own line, and extended `markerLine` to strip echoed `=== Article N: Title ===` headers.
- `FirikiTests/Services/GreekLegal/GreekLegalSummaryTests.swift`: extended `articlesAreBuiltFromPassagesWithoutContentsOrTitlePage()` and `notesKeepTheGroupsArticles()`.

**Verification:**

- `TEST_RUNNER_OI_GREEK_SUMMARY=1 TEST_RUNNER_OI_GREEK_SUMMARY_SPLIT=dev ./scripts/thesis_run_tests.sh /private/tmp/oi-e18-logs/firiki-summary-dev4-e18.log -only-testing:FirikiTests/GreekLegalSummaryTests -only-testing:FirikiTests/GreekLegalSummaryEvaluation -only-testing:FirikiTests/GreekLegalOpinionTests`:
  - `** TEST BUILD SUCCEEDED **`
  - `✔ Test run with 24 tests in 3 suites passed after 134.919 seconds.`
  - `[GreekSummary] document n_5278_2026_fek_a22.pdf statute=LAW:5278/2026 passages=203 groups=15 notes=25717 chars, 134 s`
  - `[GreekSummary] | 1 | dev | provisions 5 of 6 | articles cited 3 of 3 | dropped 0 | missing: ["extension threshold 40% of the sector's employees (art. 9)"] |` (`Άρθρο 3` and both parts of `Άρθρο 8` restored cleanly).

## 14 Nov 2026 (thirteenth entry)

**Why:** Re-measure the held-out five-document library `test` split (`GreekLabourLibrary`, 12 questions) once after E15–E18 and bring the `README.md` Results table up to date with dates across E14–E19 (`Docs/Thesis/plans/readme-results-update.md`, `EXPERIMENTS.md` E19).

**What:**

- Ran `GreekLabourLibrary` `test` split once (`firiki-library-test2-e19.txt`) and recorded it in `Docs/Thesis/experiments/runs/INDEX.md`, `Docs/Thesis/EXPERIMENTS.md` (E19), and `Docs/Thesis/METHODS_SUMMARY.md`.
- `README.md`: updated the Results table's `Nov re-run` column and notes with dated 13–14 Nov 2026 figures for the five-document library (`dev 14–15 of 24 / test 5 of 12`, right docs `9 of 11`), contract template routing (`44 of 44 / 20 of 22`), statute summaries (`5 of 6, 3 of 3 / 4 of 5`), and legal opinions (`dev 7 cases: 12 of 14 citations, 15 of 22 key facts`; `test 4 cases: 4 of 8 citations, 8 of 10 key facts`).

**Verification:**

- `TEST_RUNNER_OI_GREEK_EVAL=1 TEST_RUNNER_OI_GREEK_EVAL_SET=GreekLabourLibrary TEST_RUNNER_OI_GREEK_EVAL_SPLIT=test OI_TEST_TIMEOUT_SECONDS=5400 ./scripts/thesis_run_tests.sh /private/tmp/oi-e19-logs/firiki-library-test2-e19.log -only-testing:FirikiTests/GreekConstitutionEvaluationTests`:
  - `** TEST BUILD SUCCEEDED **`
  - `✔ Test run with 1 test in 1 suite passed after 333.466 seconds.`
  - `[GreekEval] answer pass 4 of 11; retrieval hit 7 of 11; false abstentions 3; abstention correct 1 of 1`
  - `[GreekEval] right documents retrieved 9 of 11`
  - `[GreekEval] summary set=GreekLabourLibrary corpus=library split=test: passed 5 of 12`
