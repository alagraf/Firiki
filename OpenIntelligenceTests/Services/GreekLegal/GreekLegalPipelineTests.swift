//
//  GreekLegalPipelineTests.swift
//  OpenIntelligenceTests
//
//  Thesis fork: the Greek labour-law pipeline (Docs/Thesis/plans/greek-legaltech.md). One suite per
//  stage; each phase of the plan adds its suite here.
//

import CoreGraphics
import CoreText
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

// MARK: - Phase 3: Greek OCR and extraction fixes

/// Word error rate: word-level Levenshtein distance over the reference length.
func wordErrorRate(reference: String, hypothesis: String) -> Double {
    let fold: (String) -> [String] = { text in
        GreekLegalEntityMasker.normalizeGreekText(text).lowercased()
            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
    }
    let r = fold(reference), h = fold(hypothesis)
    guard !r.isEmpty else { return h.isEmpty ? 0 : 1 }
    var previous = Array(0...h.count)
    for i in 1...r.count {
        var current = [i] + Array(repeating: 0, count: h.count)
        for j in 1...max(1, h.count) where h.count > 0 {
            current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (r[i - 1] == h[j - 1] ? 0 : 1))
        }
        previous = current
    }
    return Double(previous[h.count]) / Double(r.count)
}

/// Black text on white, drawn with Core Text, top line first.
func renderPage(_ lines: [String], width: Int = 1240, lineHeight: Int = 80, fontSize: CGFloat = 36) -> CGImage {
    let height = lineHeight * (lines.count + 1)
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )!
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
    for (index, line) in lines.enumerated() {
        let attributed = NSAttributedString(string: line, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(red: 0, green: 0, blue: 0, alpha: 1),
        ])
        let ctLine = CTLineCreateWithAttributedString(attributed)
        context.textPosition = CGPoint(x: 60, y: CGFloat(height - lineHeight * (index + 1)))
        CTLineDraw(ctLine, context)
    }
    return context.makeImage()!
}

@Suite("Greek OCR and extraction")
struct GreekOCRTests {
    static let page = [
        "Άρθρο 66",
        "Καταγγελία σύμβασης εργασίας αορίστου χρόνου",
        "1. Η καταγγελία της σύμβασης εργασίας γίνεται εγγράφως.",
        "Ν. 4808/2021 (ΦΕΚ Α' 101/19.06.2021)",
    ]

    @Test func testGreekOCRAndValidationBypass() async throws {
        let engine = GreekPaddleOCRService.shared
        try #require(engine.isAvailable, "ONNX Runtime and the Greek OCR models must be in the app")
        let lines = try await engine.recognizeLines(in: renderPage(Self.page))
        let text = GreekLegalEntityMasker.repairGreekHomoglyphs(OCRRouterService.joinLines(lines))
        let wer = wordErrorRate(reference: Self.page.joined(separator: "\n"), hypothesis: text)
        #expect(wer < 0.05, "WER \(wer): \(text)")
        // The identifiers survive OCR.
        #expect(GreekLegalEntityMasker.canonicalKeys(in: text).isSuperset(of: ["ART:66", "LAW:4808/2021"]))

        // validateAndCleanOCR keeps the Greek paragraph and doesn't flag it.
        let paragraph = "Η καταγγελία της σύμβασης εργασίας αορίστου χρόνου γίνεται εγγράφως και ο εργοδότης καταβάλλει στον εργαζόμενο την αποζημίωση του άρθρου 66 του νόμου."
        let (cleaned, lowQuality) = StructuredDocumentParser.shared.validateAndCleanOCR(paragraph)
        #expect(cleaned == paragraph)
        #expect(!lowQuality)
    }

    @Test func mixedEnglishGreekPageKeepsGreekLines() {
        let english = String(repeating: "This agreement is governed by the terms set out below and by the law. ", count: 40)
        let greek = "Ο εργοδότης υποχρεούται να καταβάλει αποζημίωση απόλυσης στον εργαζόμενο."
        let page = english + "\n" + greek + "\n" + greek
        #expect(page.prefix(2000).unicodeScalars.allSatisfy { $0.isASCII })
        let (cleaned, removed) = OCRConfiguration.filterGarbageText(page)
        #expect(removed == 0)
        #expect(cleaned.components(separatedBy: greek).count == 3)
    }

    @Test func homoglyphsAreRepairedOnlyOnGreekLines() {
        #expect(GreekLegalEntityMasker.repairGreekHomoglyphs("N. 4808/2021 (ΦΕK A' 101/19.06.2021) του νόμου") == "Ν. 4808/2021 (ΦΕΚ Α' 101/19.06.2021) του νόμου")
        #expect(GreekLegalEntityMasker.repairGreekHomoglyphs("N. 5 and PDF") == "N. 5 and PDF")
        #expect(GreekLegalEntityMasker.canonicalKeys(in: "N. 4808/2021 (ΦΕK A' 101/19.06.2021) του νόμου") == ["LAW:4808/2021", "FEK:Α:101:19.06.2021"])
    }

    @Test func routerReplacesMisreadVisionTextWithGreek() async throws {
        struct FakeGreek: OCREngineProtocol {
            let name = "fake"
            var isAvailable: Bool { true }
            func recognizeLines(in image: CGImage) async throws -> [OCRTextLine] {
                [OCRTextLine(text: "Καταγγελία σύμβασης εργασίας", box: CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.05), confidence: 0.9)]
            }
        }
        let image = renderPage(["x"])
        let router = OCRRouterService(greekEngine: FakeGreek(), mode: .autoBenchmark)
        let misread = try await router.recognizeText(in: image, site: "test") { "Kataryeλia oupBaons epyaoias aopiorou xpovou ylvetal eyypadws" }
        #expect(misread == "Καταγγελία σύμβασης εργασίας")
        let english = try await router.recognizeText(in: image, site: "test") { "The employment contract is terminated in writing by the employer." }
        #expect(english == "The employment contract is terminated in writing by the employer.")
        let visionOnly = OCRRouterService(greekEngine: FakeGreek(), mode: .vision)
        #expect(try await visionOnly.recognizeText(in: image, site: "test") { "Kataryeλia oupBaons" } == "Kataryeλia oupBaons")
    }
}
