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
- **Last updated:** 2026-10-23

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
