# Plan: Demo mode (hide inherited upstream screens)

Status: implemented 14 Nov 2026 (standing permission from the owner). Deeper fix 5 of
`POC_PROGRESS.md`.

## Goal

Record how visible the inherited upstream screens currently are, and add a "Demo Mode" setting
(defaulting to on) that hides the upstream screens and telemetry that do not fit the Greek legal
assistant story, without breaking existing UI tests or losing access to them when turned off.

## Visibility audit (before changes)

1. **`Firiki/Features/Telemetry/`:**
   - `Visualizations/Embedding3DView.swift`, `Visualizations/AdaptiveVisualizationsView.swift`, and
     `Visualizations/VisualizationsView.swift`: **not reachable anywhere in the live app** (zero
     live call sites; only `#Preview` blocks and a historical comment in
     `DocumentLibraryView.swift:543`).
   - `Dashboard/TelemetryDashboardView.swift`: **reachable** from `Settings` -> `Developer &
     Diagnostics` -> `Telemetry` (`DeveloperDiagnosticsHubView.swift:195`).
   - `Dashboard/MotherboardHUDView.swift` (`HardwareXRayOverlay`): controlled by
     `settings.showSiliconHUD` (`SettingsStore.swift:588`), which already defaults to `false` on a
     new install, and is overlaid on `ChatScreen`, `SettingsView`, and `DatabaseDashboardView` when
     enabled.
2. **Database tab (`Firiki/Features/Database/DatabaseDashboardView.swift`):**
   - **Always visible** as one of the four top-level tabs (`Tab.database` = `"Database"`) in
     `ContentView.swift:329-335`. Exposes SQLite FTS5 inverted-index internals, vocabulary charts,
     and maintenance actions.
3. **Metrics bar chips (`UnifiedMetricsBar.swift`) and technical details:**
   - `UnifiedMetricsBar` is only rendered in `ChatScreen.swift:2550-2563` when
     `settings.showTechnicalDetails` is `true` (likewise the chunk-count chip in
     `CompactChatHeader` at `ChatScreen.swift:4104`, mode/tool chips in `MessageBubbleV2.swift`,
     and confidence percentages in `GroundedAnswerView.swift`).
   - On a new install `showTechnicalDetails` defaults to `false`, **except** on an existing install
     where `SettingsStore` finds a saved `llmTemperature` (`SettingsStore.swift:595-598`) and
     defaults `showTechnicalDetails` to `true`, or where the user toggled it via the chat `...`
     menu or `Settings -> Appearance`.

## Changes

1. **`Firiki/Services/Infrastructure/Configuration/SettingsStore.swift`:**
   - Add `DemoModePreference` with `key = "demoMode"`, `defaultValue = true`, and
     `isEnabled(in: UserDefaults = .standard)` + `effectiveShowTechnicalDetails(in:)` /
     `effectiveShowSiliconHUD(in:)` helpers so the rule is shared and unit-testable.
2. **`Firiki/App/ContentView.swift`:**
   - Read `@AppStorage(DemoModePreference.key) private var demoMode = DemoModePreference.defaultValue`.
   - Hide `Tab.database` ("Database") when `demoMode` is `true` (unless `screenshotMode.initialTab == .database`).
   - Switch `selectedTab` back to `.chat` via `.onChange(of: demoMode)` if `demoMode` turns on while
     on `.database`.
3. **`Firiki/Features/Chat/Conversation/ChatScreen.swift`:**
   - Read `@AppStorage(DemoModePreference.key) private var demoMode = DemoModePreference.defaultValue`.
   - Gate `HardwareXRayOverlay` (`!demoMode && settings.showSiliconHUD`), `UnifiedMetricsBar`
     (`!demoMode && settings.showTechnicalDetails`), `.environment(\.showsTechnicalDetails, !demoMode && settings.showTechnicalDetails)`,
     the chunk-count chip in `CompactChatHeader` (`!demoMode && settings.showTechnicalDetails`), and
     the `"Technical Details"` toggle in the iOS/macOS chat toolbar menu (`if !demoMode`).
4. **`Firiki/Features/Database/DatabaseDashboardView.swift`:**
   - Gate `HardwareXRayOverlay` with `!demoMode && settings.showSiliconHUD`.
5. **`Firiki/Features/Settings/SettingsView.swift`:**
   - Read `@AppStorage(DemoModePreference.key) private var demoMode = DemoModePreference.defaultValue`.
   - Gate `HardwareXRayOverlay` with `!demoMode && settings.showSiliconHUD`.
   - In `visibleEntries(in:)`, hide `.developer` (`Developer & Diagnostics`, which holds
     `TelemetryDashboardView`, `ChunkInspectorView`, `RAGPipelineAuditView`, etc.) while `demoMode`
     is `true`.
   - Add a `"Demo Mode"` `Toggle` row in the `System` section of `settingsList` (also matched by
     Settings search for `"demo"`), with a clear subtitle explaining that it hides the Database
     tab, developer diagnostics, and technical telemetry.
   - Keep `Telemetry HUD` and `Technical Details` inside `Settings -> Appearance` so
     `AccessibilityAuditTests.testTheSwitchesAndSlidersInSettingsHaveNames` keeps passing unchanged.
6. **Tests (`FirikiTests/Services/Infrastructure/SettingsPersistenceTests.swift`):**
   - Add tests verifying `DemoModePreference.isEnabled(in:)` defaults to `true`, respects an
     explicit `false` saved in `UserDefaults`, and that `DemoModePreference` gates
     technical-details / HUD visibility even when `showTechnicalDetails` or `showSiliconHUD` are
     saved as `true`.

## Verification

- `SettingsPersistenceTests` (`thesis_run_tests.sh /private/tmp/demo-mode-unit.log -only-testing:FirikiTests/SettingsPersistenceTests`): `** TEST BUILD SUCCEEDED **`, `Executed 5 tests, with 0 failures (0 unexpected) in 0.492 (0.500) seconds`, `** TEST EXECUTE SUCCEEDED **`.
- Full unit suite (`./scripts/thesis_run_tests.sh /private/tmp/demo-mode-full.log`): `** TEST BUILD SUCCEEDED **`, `Executed 1292 tests, with 8 tests skipped and 0 failures (0 unexpected) in 503.676 (504.064) seconds`, `✔ Test run with 157 tests in 29 suites passed after 27.032 seconds.`
- macOS build (`xcodebuild build -scheme Firiki -destination 'platform=macOS' -derivedDataPath /private/tmp/oi-mac`): `** BUILD SUCCEEDED **`.
- `AccessibilityAuditTests` (`xcodebuild test -scheme FirikiUITests -destination "platform=iOS Simulator,name=iPhone 18 Pro" -derivedDataPath /private/tmp/oi-build -only-testing:FirikiUITests/AccessibilityAuditTests`): `Executed 2 tests, with 0 failures (0 unexpected) in 89.741 (89.752) seconds`, `** TEST SUCCEEDED **`.
