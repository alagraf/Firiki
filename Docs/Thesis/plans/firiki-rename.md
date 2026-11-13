# Plan: rename the app to Firiki and remove what belonged to the released app (13 Nov 2026)

**Goal.** The repository and the app say "Firiki" everywhere except where the original app must be
named, and nothing of the App Store product remains (billing, release tooling, marketing, the
original app's documentation).

**Owner's decisions (13 Nov 2026):**
- Rename the internal identifiers too: bundle IDs, app group, data folder. Firiki becomes a new app
  on the Mac, so the imported library has to be imported again.
- Remove billing; every feature is on and nothing is limited.
- Keep only the documentation Firiki uses.
- Claude Code executes this on a branch and stops for review before merging or pushing.

**Survey (13 Nov 2026).** 1,515 tracked files, 912 mention "OpenIntelligence" (27,400 times): 547
Swift, 187 Markdown. Seven Xcode targets, four shared schemes, one local package
(`OpenIntelligence/swift-transformers`, vendored). The project uses folder-synced groups, so a
folder rename is a path change in `project.pbxproj`. 74 test files `import OpenIntelligenceEngine`,
123 import `OpenIntelligence`. Billing: 17 files in `Features/Billing` and `Services/Billing`;
`EntitlementStore` is used in 18 other files (ContentView, ChatScreen, DocumentLibraryView,
SettingsView, ContainerSettingsSheet, RAGService, previews, the RAG validation harness).

## Mentions that stay

- `LICENSE`: "Copyright (c) 2025 Gunnar Hostetler". The MIT licence requires the notice to stay.
  Firiki's own line is added under it.
- `THIRD_PARTY_NOTICES.md` attributions, and the README's credits.
- `Docs/Thesis/` records (`FORK_CHANGES`, `EXPERIMENTS`, `METHODS_SUMMARY`, `IMPLEMENTATION_SUMMARY`,
  run files, plans): the original app is what the thesis compares against, and their file paths are
  kept as written. A note at the top of `FORK_CHANGES` maps old paths to new ones
  (`OpenIntelligence/` → `Firiki/`, `OpenIntelligenceTests/` → `FirikiTests/`, …).
- `scripts/thesis/holdout/EUHoldoutStockAppTests.swift`: it runs inside the original app.
- The git remote `upstream`. Note: after this rename, merging `upstream/main` is no longer
  practical (every file is renamed); the "Syncing" section of `AGENTS.md` is replaced by that note.
- `OpenIntelligence/swift-transformers/` (vendored third-party code): moved with its folder, not edited.

## Step 0: branch and baseline

- `git switch -c firiki-rename` from `thesis/greek-legal-rag`.
- `bash scripts/check_icloud_conflicts.sh`.
- Baseline: iOS smoke build, macOS build, the 20 Greek legal suites (expected 119 tests pass), and
  the full unit suite (expected: only the 3 Greek-region formatting failures). Record counts.

## Step 1: delete release-only material (no compiled code)

- Root: `fastlane/`, `ci_scripts/`, `InAppEvents/`, `Gemfile`, `Gemfile.lock`, `WHATS_NEW.md`,
  `PRIVACY.md`, `HANDOFF.md` (the original author's index; the thesis one is
  `Docs/Thesis/plans/HANDOFF.md`), `Package.swift` (the engine SDK's distribution manifest; the
  Xcode project doesn't use it), `.github/` (OpenIntelligence issue templates and store art),
  `Xrays/` (original app's traces).
- `scripts/`: App Store Connect (`asc_*.rb`), sales (`schedule_sale.py`, `test_schedule_sale.py`,
  `verify_sale_prices.py`), ads and video (`google_ads/`, `create_video_campaign.py`,
  `prepare_pmax_assets.py`, `link_youtube_oauth.py`), store art (`compose_store_screenshots.py`,
  `render_iap_images.swift`, `screenshots/`), `privacy_policy.py`, `xcode_cloud_toolchain.rb`, the
  release claims gate (`verify_capabilities.py`, `verify_doc_claims.py`,
  `test_verify_doc_claims.sh`). Every other script is kept if it builds, tests or benchmarks; each
  is checked with `git grep` for callers before deletion.
- `Docs/`: everything except `Docs/Thesis/`, `Docs/ai/codemap/` (used by `AGENTS.md`), and
  `HOW_IT_WORKS.md`, `INGESTION_PIPELINE.md`, `RETRIEVAL_PIPELINE.md` (still describe the engine;
  edited to Firiki, release and pricing passages removed). Before deleting, `git grep` for code or
  tests that read a file under `Docs/` (for example a bundled guide) and keep or move those.
- `CHANGELOG.md`: keep only the 5.7 section (the fork's changes), retitled "Firiki changelog".
- `Benchmarks/`: kept (thesis sets and the original fixtures the harness uses); mentions renamed.

## Step 2: remove billing and App Store features (compiled code)

- Delete `Features/Billing/` (plan sheet, launch sale and banner, price comparison, redeem code,
  rating snapshot, the original author's privacy policy and terms views), `Services/Billing/`
  (StoreKit service, entitlement store, quota store, monetization policy),
  `Resources/StoreKit/`, the `OpenIntelligence-StoreKitTesting` scheme, `App/ReviewPromptService.swift`,
  the What's New screen (`Features/Onboarding/WhatsNew*.swift`).
- Remove every use: no `EntitlementStore` environment object, no plan sheet, no paywall entry
  point, no document, library or Maximum-mode limits. Where a check gates a feature, the feature is
  always on (`canAddDocument`, `canAddLibrary`, `canUseMaximumModeNow`, `isAtLeast(.pro)` → true;
  remaining-uses labels removed). `RAGService(containerService:entitlementStore:)` loses the
  parameter. The engine's stand-in `EntitlementStore` in `Core/Support/EngineSDKCompatibility.swift`
  goes too.
- `AboutView` / links: the original author's website, support e-mail, App Store and review links
  are removed; About shows Firiki, the thesis, the licence and the credits.
- Settings rows for plan, restore purchases, redeem code and rating are removed.
- Tests of removed code are deleted (billing, sale, quota, rating, What's New); tests that
  constructed an `EntitlementStore` to build `RAGService` drop it.

## Step 3: rename (scripted, then built)

Order: rename paths with `git mv`, then replace text with one ordered script over tracked text files
(excluding the "stay" list above), then fix what the build reports.

| Old | New |
|---|---|
| `OpenIntelligence.xcodeproj` | `Firiki.xcodeproj` |
| `OpenIntelligence/` (app sources) | `Firiki/` |
| `OpenIntelligenceTests/`, `OpenIntelligenceUITests/` | `FirikiTests/`, `FirikiUITests/` |
| `OpenIntelligenceCapture/`, `…LiveActivities/`, `…Share/` | `FirikiCapture/`, `FirikiLiveActivities/`, `FirikiShare/` |
| Targets, products, schemes, modules `OpenIntelligence*` | `Firiki*` (engine: `FirikiEngine`) |
| `OpenIntelligence.entitlements` and the extensions' | `Firiki.entitlements`, … |
| Swift files named `OpenIntelligence*.swift` | `Firiki*.swift` |
| Types `OpenIntelligence*` (`RuntimePaths`, `Links`, `ResourceBundle`, `EngineError`, `DeepLink`, `AppDelegate`, …) | `Firiki*` |
| Bundle IDs `com.openintelligence.app` (+ `.engine`, `.tests`, `.uitests`, `.liveactivities`, `.share`, `.capture`) | `com.alagraf.firiki` (+ same suffixes) |
| App group `group.com.openintelligence.app` (pbxproj, entitlements, `SharedInbox.swift`, `WidgetSnapshot.swift`, `IngestionLiveActivityWidget.swift`) | `group.com.alagraf.firiki` |
| Other reverse-DNS IDs `com.openintelligence.*` (background tasks, user activities, Spotlight, widget kinds, logger subsystems, queues) | `com.alagraf.firiki.*` |
| URL scheme `openintelligence://` | `firiki://` |
| Data folder `OpenIntelligence` (Application Support, caches), UserDefaults suites | `Firiki` |
| Display names (`INFOPLIST_KEY_CFBundleDisplayName`, Share and Live Activity `Info.plist`) | `Firiki`, `Firiki Live` |
| User-visible text ("OpenIntelligence closed unexpectedly", microphone message, export speaker, …) | "Firiki …" |
| File headers `//  OpenIntelligence…` | `//  Firiki…` |
| `.gitignore` paths, scripts' scheme/target/paths, `scripts/thesis_run_tests.sh`, `build_simulator_smoke.sh` | renamed |
| `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, `README.md` | Firiki names and paths; identity table updated |
| `Docs/ai/codemap/` | regenerated with `.claude/codemap/codemap.py` (or paths rewritten) |

## Files that need the owner's explicit approval (AGENTS.md)

`OpenIntelligence.xcodeproj/project.pbxproj` (targets, schemes, bundle IDs, app group, paths,
signing unchanged: `DEVELOPMENT_TEAM` stays "" and `J7R6G54TG4` for the two macOS entries),
`OpenIntelligence/OpenIntelligence.entitlements` and the extensions' `*.entitlements` (app group
only; no entitlement added or removed), `Info.plist` (background task IDs, URL scheme, activity
types), `OpenIntelligenceShare/Info.plist`, `OpenIntelligenceLiveActivities/Info.plist`,
`OpenIntelligenceCapture/Info.plist` (display names and IDs).

## Step 4: verify

- `grep -ri openintelligence` over tracked files returns only the "stay" list; the list of hits is
  attached to the review.
- `xcodebuild -list -project Firiki.xcodeproj` shows the renamed targets and schemes.
- iOS smoke build and macOS build: `** BUILD SUCCEEDED **`.
- The 20 Greek legal suites: 119 tests pass. Full unit suite: same failures as the baseline only.
- Mac app launched: the name is Firiki in the menu bar, Dock and About; no plan, sale or rating UI
  anywhere; a PDF imports and a Greek question gets an answer (the answer is the owner's check on
  Apple Intelligence).
- Records: `FORK_CHANGES.md` entry (why, what, files, verification, old→new path note),
  `CHANGELOG.md`, `AGENTS.md` identity table.

## Risks

- **Library re-import.** A new bundle ID and data folder means an empty library. Re-import the demo
  documents after merging; the full Labour Code takes about 15 minutes.
- **Signing.** New bundle IDs and app group must be registered by Xcode's automatic signing for the
  macOS team `J7R6G54TG4`. If Xcode can't do it from the command line, the owner opens the project
  once in Xcode (Signing & Capabilities) to let it register them.
- **Upstream.** Merging the original repository is no longer practical after this change.
- **Thesis draft.** Its paths, screenshots and figures show the old names; the records keep them,
  with the old→new path note.
- **Size.** About 900 files change in one branch. It's merged only after the owner's review and the
  checks above, and should land well before the demo, not the day of it.
