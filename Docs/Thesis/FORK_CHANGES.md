# Changes to the original OpenIntelligence code (thesis fork)

This document records every change made to the original OpenIntelligence codebase for the thesis
proof of concept: a Greek-language legal assistant for iPhone, focused on Greek labour law, built on
Apple Intelligence. It is the reference for the thesis's implementation chapter and should be
updated with every further change.

- **Repository:** `OpenIntelligence-main/` (thesis folder)
- **Branch:** `main`. Changes 2.5 and 2.6 were developed on `legal-jurisdiction-caveat` and
  fast-forwarded into `main` on 2026-10-22.
- **Last updated:** 2026-10-22

## 1. Baseline

The original code is the OpenIntelligence app (Swift/SwiftUI, Apple Foundation Models, on-device
RAG). It was imported as a single commit:

| Commit | Date | Description |
|---|---|---|
| `e61cbb4` | 2026-10-18 | "Baseline: Working app with Lifetime plan and zero limits" (1,198 files) |

The project's `MARKETING_VERSION` is 5.3. The original `CHANGELOG.md` already had an unreleased 5.7
section with the original author's own work in progress, which is part of the original code and
not a thesis change.

**Limitation:** the baseline commit already contains the fork-setup changes in sections 2.1 and 2.2.
The original upstream code isn't in this repository, so those two changes can't be shown as a git
diff. They are documented from the changelog and were checked against the current code on
2026-10-22. Every later change is a separate commit and can be inspected with `git show <commit>`.

## 2. Summary of changes

| # | Date | Commit | Area | Change |
|---|---|---|---|---|
| 2.1 | ≤ 2026-10-18 | in `e61cbb4` | Configuration | Own bundle IDs and signing; iCloud and Private Cloud Compute entitlements removed; free document limit raised |
| 2.2 | ≤ 2026-10-18 | in `e61cbb4` | Billing and quota | App defaults to the Lifetime tier with no library, document or mode limits |
| 2.3 | 2026-10-18 | `1244d88` | UI | Atlas tab and Knowledge Atlas link removed |
| 2.4 | 2026-10-19 | `c73c6d5` | Documentation | Original author's unreleased 5.7 changelog entries removed, keeping only fork changes |
| 2.5 | 2026-10-22 | `61218d3` | Answer verification | Medical domain-isolation guardrail replaced by an advisory jurisdiction caveat |
| 2.6 | 2026-10-22 | `7b83c4a` | Answer verification | Jurisdiction caveat applied at the query entry point so every answer path gets it |

### 2.1 Fork and account configuration (in baseline)

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

**Files:** `OpenIntelligence.xcodeproj/project.pbxproj`, `OpenIntelligence/OpenIntelligence.entitlements`,
`OpenIntelligence/Services/Infrastructure/Configuration/QuotaPolicy.swift`

**Checked 2026-10-22:** bundle IDs, the cleared team, the entitlement contents and
`freeDocumentLimit = 1_000` are all present in the current code.

**Consequence for the thesis:** Private Cloud Compute is unavailable until the
`com.apple.developer.private-cloud-compute` entitlement is granted and added back. That is the one
route that handles Greek well, according to the original author.

### 2.2 Lifetime tier and limits removed (in baseline)

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

### 2.3 Atlas tab removed (`1244d88`)

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

### 2.4 Changelog trimmed (`c73c6d5`)

**Why:** to keep the 5.7 section of `CHANGELOG.md` to the fork's own changes.

**What changed:** 193 lines of the original author's unreleased 5.7 entries were removed from
`CHANGELOG.md`, for example the Shortcuts actions, JSON Lines import and app links. Documentation
only: the code those entries describe is still in the app.

### 2.5 Medical domain isolation replaced by a jurisdiction caveat (`61218d3`)

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

### 2.6 Caveat applied at the query entry point (`7b83c4a`)

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

## 3. How to inspect the changes

```bash
git log --oneline e61cbb4..legal-jurisdiction-caveat
```

```bash
git show 61218d3 --stat
```

```bash
git diff e61cbb4 legal-jurisdiction-caveat -- OpenIntelligence
```

## 4. Open items and known limitations

- **iPhone check pending:** the caveat has been seen working on macOS (M3 MacBook Pro), but not yet
  on an iPhone. For a complete record, check a Greek question in each mode (Standard, Deep Think,
  Maximum); Deep Think and Maximum lookups are the path fixed in 2.6.
- **Jurisdiction is recognised from text patterns only.** A chunk with no citation, court or gazette
  signal is "unknown". Court authority (for example Areios Pagos plenary decisions versus
  lower courts) and whether a provision was in force on the date of the facts aren't handled yet;
  both need per-document legal metadata.
- **Stale documentation:** `Docs/RETRIEVAL_PIPELINE.md` line 12 still names the deleted
  `DomainIsolationService`.
- **Build script:** `scripts/build_simulator_smoke.sh` defaults to an "iPhone 17 Pro" simulator that
  isn't installed. Run it with
  `OPENINTELLIGENCE_SIMULATOR_DESTINATION="platform=iOS Simulator,name=iPhone 18 Pro"`.
- **Observation, not a fork change:** for a Greek Cypriot labour-court document, the app's automatic
  document summary rendered "αποζημίωση απόλυσης" (severance pay) as "notice of termination". This
  is relevant to the thesis's Greek-language accuracy work.

## 5. Authorship note

The changes in sections 2.5 and 2.6 were implemented with the help of Claude Code (Anthropic). Each
of those commits carries a `Co-Authored-By` trailer.
