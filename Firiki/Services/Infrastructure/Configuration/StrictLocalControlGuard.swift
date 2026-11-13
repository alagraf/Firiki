//
//  StrictLocalControlGuard.swift
//  Firiki
//
//  Thesis requirement R1 (R1.1–R1.4): a lawyer's documents never leave the device except through
//  an attested channel the lawyer agreed to. While strict local mode is on (the default):
//  - the library's storage folders are excluded from iCloud and device backups (R1.1);
//  - the iCloud Drive container is never resolved, so workspace sync never runs (R1.2);
//  - web addresses are not downloaded into a library (R1.3);
//  - Private Cloud Compute is used only with its signed entitlement and when the user hasn't
//    refused cloud transmission (R1.4).
//

import Foundation

nonisolated enum StrictLocalControlGuard {
    /// UserDefaults key for the switch. Absent means on.
    static let strictLocalModeDefaultsKey = "thesis.strictLocalMode"

    /// The key `RAGService` stores the Private Cloud Compute consent under.
    static let pccConsentDefaultsKey = "cloudConsent.applePCC"

    static var isStrictLocalModeEnabled: Bool {
        isStrictLocalModeEnabled(in: .standard)
    }

    static func isStrictLocalModeEnabled(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: strictLocalModeDefaultsKey) as? Bool ?? true
    }

    enum GuardError: LocalizedError, Equatable {
        case remoteIngestionBlocked

        var errorDescription: String? {
            switch self {
            case .remoteIngestionBlocked:
                return "Strict local mode is on: web pages are not downloaded into a library."
            }
        }
    }

    // MARK: - R1.1 Local storage

    /// Marks `url` (a file or folder in Application Support) as excluded from backup. Called on
    /// the library's storage root, so the SQLite database and vector store under it stay on this
    /// device. Does nothing when strict local mode is off or the item doesn't exist.
    @discardableResult
    static func enforceLocalStorage(for url: URL, defaults: UserDefaults = .standard) -> Bool {
        guard isStrictLocalModeEnabled(in: defaults) else { return false }
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        var target = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        do {
            try target.setResourceValues(values)
            return true
        } catch {
            Log.warning("[StrictLocal] Could not exclude \(url.lastPathComponent) from backup: \(error.localizedDescription)", category: .initialization)
            return false
        }
    }

    // MARK: - R1.2 iCloud Drive

    /// The iCloud Drive container, or nil while strict local mode is on.
    static func ubiquityContainerURL(defaults: UserDefaults = .standard) -> URL? {
        guard !isStrictLocalModeEnabled(in: defaults) else { return nil }
        return FileManager.default.url(forUbiquityContainerIdentifier: nil)
    }

    // MARK: - R1.3 Remote ingestion

    static func allowsRemoteURLIngestion(defaults: UserDefaults = .standard) -> Bool {
        !isStrictLocalModeEnabled(in: defaults)
    }

    /// Throws `GuardError.remoteIngestionBlocked` when a web address may not be downloaded.
    static func checkRemoteURLIngestion(defaults: UserDefaults = .standard) throws {
        guard allowsRemoteURLIngestion(defaults: defaults) else {
            throw GuardError.remoteIngestionBlocked
        }
    }

    // MARK: - R1.4 Private Cloud Compute

    /// Whether a `PrivateCloudComputeLanguageModel` may be created: the signed entitlement is
    /// present and the user hasn't chosen "Never Allow". "Ask Each Time" still goes through the
    /// consent sheet before anything is sent.
    static func canUsePCC(
        defaults: UserDefaults = .standard,
        hasEntitlement: () -> Bool = { EntitlementChecker.hasEntitlement(EntitlementChecker.privateCloudComputeKey) }
    ) -> Bool {
        if defaults.string(forKey: pccConsentDefaultsKey) == CloudConsentState.denied.rawValue {
            return false
        }
        return hasEntitlement()
    }
}
