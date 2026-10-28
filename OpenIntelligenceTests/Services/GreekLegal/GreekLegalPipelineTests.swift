//
//  GreekLegalPipelineTests.swift
//  OpenIntelligenceTests
//
//  Thesis fork: the Greek labour-law pipeline (Docs/Thesis/plans/greek-legaltech.md). One suite per
//  stage; each phase of the plan adds its suite here.
//

import Foundation
import Testing

@testable import OpenIntelligence

// MARK: - Phase 1: strict local control (R1.1–R1.4)

@Suite("Strict local control guard")
struct StrictLocalControlGuardTests {
    private func makeDefaults() -> UserDefaults {
        let name = "StrictLocalControlGuardTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func strictModeIsOnByDefault() {
        #expect(StrictLocalControlGuard.isStrictLocalModeEnabled(in: makeDefaults()))
    }

    @Test func storageFolderIsExcludedFromBackup() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("StrictLocal-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        #expect(StrictLocalControlGuard.enforceLocalStorage(for: folder, defaults: makeDefaults()))
        let values = try folder.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test func applicationSupportRootIsExcludedFromBackup() throws {
        let root = OpenIntelligenceRuntimePaths.applicationSupportRoot()
        let values = try root.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test func iCloudContainerAndWebImportAreBlocked() async {
        let defaults = makeDefaults()
        #expect(StrictLocalControlGuard.ubiquityContainerURL(defaults: defaults) == nil)
        #expect(!StrictLocalControlGuard.allowsRemoteURLIngestion(defaults: defaults))
        #expect(throws: StrictLocalControlGuard.GuardError.remoteIngestionBlocked) {
            try StrictLocalControlGuard.checkRemoteURLIngestion(defaults: defaults)
        }
        // The shared fetch path refuses before any request is made (standard defaults: strict on).
        await #expect(throws: StrictLocalControlGuard.GuardError.self) {
            _ = try await WebPageFetchService.fetch(URL(string: "https://example.com")!)
        }
    }

    @Test func turningStrictModeOffAllowsWebImport() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: StrictLocalControlGuard.strictLocalModeDefaultsKey)
        #expect(StrictLocalControlGuard.allowsRemoteURLIngestion(defaults: defaults))
    }

    @Test func pccNeedsEntitlementAndNoRefusal() {
        let defaults = makeDefaults()
        #expect(!StrictLocalControlGuard.canUsePCC(defaults: defaults, hasEntitlement: { false }))
        #expect(StrictLocalControlGuard.canUsePCC(defaults: defaults, hasEntitlement: { true }))
        defaults.set(CloudConsentState.denied.rawValue, forKey: StrictLocalControlGuard.pccConsentDefaultsKey)
        #expect(!StrictLocalControlGuard.canUsePCC(defaults: defaults, hasEntitlement: { true }))
    }
}
