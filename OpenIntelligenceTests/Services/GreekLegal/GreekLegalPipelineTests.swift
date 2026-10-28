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

// MARK: - Phase 2: entity masker and bilingual schema

@Suite("Greek legal entity masker")
struct GreekLegalEntityMaskerTests {
    static let sample = "\u{00B5}ισθός του Άρθρου 38 παρ. 1 του Ν. 4808/2021 (ΦΕΚ Α' 101/19.06.2021)"

    @Test func testGreekEntityMaskingAndNFKC() {
        let normalized = GreekLegalEntityMasker.normalizeGreekText(Self.sample)
        #expect(normalized.unicodeScalars.first == "\u{03BC}")
        #expect(!normalized.unicodeScalars.contains("\u{00B5}"))

        let (masked, entities) = GreekLegalEntityMasker.maskEntities(in: Self.sample)
        #expect(entities.map(\.canonicalKey) == ["ART:38", "PAR:1", "LAW:4808/2021", "FEK:Α:101:19.06.2021"])
        #expect(masked == "μισθός του __LEX_ENT_001__ __LEX_ENT_002__ του __LEX_ENT_003__ (__LEX_ENT_004__)")
        // Deterministic: the same input gives the same output.
        #expect(GreekLegalEntityMasker.maskEntities(in: Self.sample).maskedText == masked)

        let anchored = GreekLegalEntityMasker.unmaskEntities(in: masked, entities: entities, mode: .bilingualAnchor)
        #expect(anchored == "μισθός του Article 38 [Άρθρο 38] paragraph 1 [παρ. 1] του Law 4808/2021 [Ν. 4808/2021] (FEK A 101/19.06.2021 [ΦΕΚ Α' 101/19.06.2021])")

        let greek = GreekLegalEntityMasker.unmaskEntities(in: masked, entities: entities, mode: .greekVerbatim)
        #expect(greek == GreekLegalEntityMasker.normalizeGreekText(Self.sample))
    }

    @Test func translatorMangledPlaceholdersAreRestored() {
        let (_, entities) = GreekLegalEntityMasker.maskEntities(in: "Άρθρο 66 του Ν. 4808/2021")
        let translated = "Article LEX_ENT_001 of __lex_ent_002 __ applies."
        let restored = GreekLegalEntityMasker.unmaskEntities(in: translated, entities: entities, mode: .bilingualAnchor)
        #expect(restored == "Article Article 66 [Άρθρο 66] of Law 4808/2021 [Ν. 4808/2021] applies.")
    }

    @Test(arguments: [
        ("Π.Δ. 80/2022", "PD:80/2022"),
        ("ΠΔ 62/2025", "PD:62/2025"),
        ("Υ.Α. 40331/Δ1.13521", "MD:40331/Δ1.13521"),
        ("ΑΠ 123/2023", "COURT:ΑΠ:123/2023"),
        ("ΟλΑΠ 1/2022", "COURT:ΟλΑΠ:1/2022"),
        ("ΣτΕ 456/2021", "COURT:ΣτΕ:456/2021"),
        ("Οδηγία (ΕΕ) 2019/1152", "EU_DIR:2019/1152"),
        ("Νόμος 4093/2012", "LAW:4093/2012"),
        ("§ 2", "PAR:2"),
        ("εδ. α'", "SUBPAR:α"),
        ("ΑΡΘΡΟ 5", "ART:5"),
        ("Law 4808/2021", "LAW:4808/2021"),
        ("Article 38", "ART:38"),
        ("Presidential Decree 80/2022", "PD:80/2022"),
    ])
    func recognizesIdentifier(text: String, key: String) {
        #expect(GreekLegalEntityMasker.canonicalKeys(in: text) == [key])
    }

    @Test func ordinaryWordsAreNotIdentifiers() {
        let text = "Ο εργαζόμενος απολύθηκε από την εργασία του το 2021 χωρίς αποζημίωση 1.200,50 ευρώ."
        #expect(GreekLegalEntityMasker.extractEntities(from: text).isEmpty)
    }

    @Test func primaryStatuteIsTheMostCited() {
        let entities = GreekLegalEntityMasker.extractEntities(
            from: "Ν. 4093/2012, Ν. 4808/2021, Άρθρο 66 Ν. 4808/2021")
        #expect(GreekLegalEntityMasker.primaryStatuteKey(for: entities) == "LAW:4808/2021")
    }

    @Test func greekLetterRatio() {
        #expect(GreekLegalEntityMasker.greekLetterRatio("εργασία και άδεια") == 1)
        #expect(GreekLegalEntityMasker.greekLetterRatio("employment law") == 0)
    }
}

@Suite("Bilingual chunk storage")
struct BilingualChunkStorageTests {
    @Test func legalMetadataRoundTripsThroughSQLite() async {
        let documentId = UUID()
        let containerId = UUID()
        let greek = "Άρθρο 66 του Ν. 4808/2021: Η καταγγελία της σύμβασης εργασίας."
        let entities = GreekLegalEntityMasker.extractEntities(from: greek)
        let metadata = LegalChunkMetadata(
            sourceTextEl: greek, sourceLanguage: "el", legalEntities: entities,
            primaryStatuteKey: GreekLegalEntityMasker.primaryStatuteKey(for: entities)
        )
        let store = SQLiteFullTextService.shared
        let chunkId = "\(documentId.uuidString)_0"
        await store.storeLegalChunkMetadata(
            chunkId: chunkId, documentId: documentId, containerId: containerId, metadata: metadata)

        let read = await store.legalChunkMetadata(for: documentId)
        #expect(read[chunkId] == metadata)
        #expect(read[chunkId]?.primaryStatuteKey == "LAW:4808/2021")
        #expect(read[chunkId]?.canonicalKeys == ["ART:66", "LAW:4808/2021"])

        await store.deleteChunks(for: documentId)
        #expect(await store.legalChunkMetadata(for: documentId).isEmpty)
    }

    @Test func documentChunkDecodesWithoutLegalField() throws {
        let chunk = DocumentChunk(
            documentId: UUID(), content: "x", embedding: [],
            metadata: ChunkMetadata(chunkIndex: 0, startPosition: 0)
        )
        let data = try JSONEncoder().encode(chunk)
        let decoded = try JSONDecoder().decode(DocumentChunk.self, from: data)
        #expect(decoded.legal == nil)
        #expect(decoded.sourceTextEl == nil)
    }
}
