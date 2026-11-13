//
//  GreekLegalPipelineTests.swift
//  FirikiTests
//
//  Thesis fork: the Greek labour-law pipeline (Docs/Thesis/plans/greek-legaltech.md). One suite per
//  stage; each phase of the plan adds its suite here.
//

import CoreGraphics
import CoreImage
import CoreText
import Foundation
import PDFKit
import Testing

@testable import Firiki

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
        let root = FirikiRuntimePaths.applicationSupportRoot()
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

    @Test func numberAbbreviationsAreNotMaskedAsArticle() {
        let text = "ΚΥΡΩΣΗ ΣΥΜΒΑΣΗΣ υπ' αρ. 155 και υπ' αρ. 191 της Διεθνούς Οργάνωσης Εργασίας"
        let entities = GreekLegalEntityMasker.extractEntities(from: text)
        #expect(!entities.contains { $0.canonicalKey == "ART:155" || $0.canonicalKey == "ART:191" })
    }

    @Test func documentNamesAreMaskedAsWritten() {
        let text = "Article 5 of passage 3-2.txt and passage 1-2 [C1]; see also report_2024.pdf."
        let (masked, names) = GreekLegalEntityMasker.maskDocumentNames(in: text, names: ["passage 3-2.txt", "passage 1-2.txt"])
        #expect(names.map(\.verbatimEl) == ["passage 3-2.txt", "passage 1-2", "report_2024.pdf"])
        #expect(masked == "Article 5 of __LEX_ENT_900__ and __LEX_ENT_901__ [C1]; see also __LEX_ENT_902__.")
        #expect(GreekLegalEntityMasker.unmaskEntities(in: masked, entities: names, mode: .verbatim) == text)
        #expect(GreekLegalEntityMasker.canonicalKeys(in: "the passage and the passages") == ["TERM:passage", "TERM:passages"])
        #expect(GreekLegalEntityMasker.canonicalKeys(in: "the excerpts") == ["TERM:passages"])
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
        // The legal glossary adds "TERM:termination of the employment contract" for the phrase.
        // `filter` here is the array one, so the comparison is between sets.
        #expect(read[chunkId].map { Set($0.canonicalKeys.filter { !$0.hasPrefix("TERM:") }) } == ["ART:66", "LAW:4808/2021"])

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
/// `degrees` turns the text about the page's centre, as on a page laid crooked on a scanner.
func renderPage(_ lines: [String], width: Int = 1240, lineHeight: Int = 80, fontSize: CGFloat = 36, degrees: CGFloat = 0) -> CGImage {
    let height = lineHeight * (lines.count + 1)
    let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )!
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
    context.rotate(by: degrees * .pi / 180)
    context.translateBy(x: -CGFloat(width) / 2, y: -CGFloat(height) / 2)
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

    /// Closely spaced lines on a page turned by 2°: a straight box around one line also takes in
    /// the lines above and below, a box along the line doesn't.
    @Test func tiltedPageIsReadLineByLine() async throws {
        let engine = GreekPaddleOCRService.shared
        try #require(engine.isAvailable, "ONNX Runtime and the Greek OCR models must be in the app")
        let lines = try await engine.recognizeLines(in: renderPage(Self.page, lineHeight: 50, degrees: 2))
        let text = GreekLegalEntityMasker.repairGreekHomoglyphs(OCRRouterService.joinLines(lines))
        let wer = wordErrorRate(reference: Self.page.joined(separator: "\n"), hypothesis: text)
        #expect(wer < 0.1, "WER \(wer): \(text)")
        #expect(GreekLegalEntityMasker.canonicalKeys(in: text).isSuperset(of: ["ART:66", "LAW:4808/2021"]))
    }

    @Test func textBoxesFollowTheLine() throws {
        // A band 6 px thick, 360 px long, drawn level and at 3° on a 400 by 100 probability map.
        func band(degrees: Double) -> [Float] {
            var map = [Float](repeating: 0, count: 400 * 100)
            let slope = tan(degrees * .pi / 180)
            for x in 20..<380 {
                let top = 40 + Int((Double(x - 200) * slope).rounded())
                for y in top..<(top + 6) { map[y * 400 + x] = 0.9 }
            }
            return map
        }
        let level = GreekPaddleOCRService.dbBoxes(probabilities: band(degrees: 0), width: 400, height: 100)
        #expect(level.count == 1)
        #expect(level.first?.direction == CGVector(dx: 1, dy: 0))
        // The level box is PaddleOCR's axis-aligned box: 360 by 6, grown by 360·6·1.5 / (2·366).
        let grow = 360.0 * 6 * 1.5 / (2 * 366)
        let rect = try #require(level.first).boundingRect
        #expect(abs(rect.minX - (20 - grow)) < 1e-6 && abs(rect.minY - (40 - grow)) < 1e-6)
        #expect(abs(rect.width - (360 + 2 * grow)) < 1e-6 && abs(rect.height - (6 + 2 * grow)) < 1e-6)

        let tilted = GreekPaddleOCRService.dbBoxes(probabilities: band(degrees: 3), width: 400, height: 100)
        #expect(tilted.count == 1)
        let box = try #require(tilted.first)
        let angle = atan2(box.direction.dy, box.direction.dx) * 180 / .pi
        #expect(abs(angle - 3) < 0.3, "angle \(angle)")
        // Across the line the box stays near the band's own thickness (drawn in whole-pixel steps,
        // the band is about 7 px thick across, and the growth rises with it: about 17.3 px in all),
        // while an axis-aligned box spans the band's whole 25 px height plus growth.
        #expect(box.thickness < 6 + 2 * grow + 3, "thickness \(box.thickness)")
        #expect(box.boundingRect.height > 6 + 2 * grow + 15)
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

    /// Images inside a PDF and pages with little text (a stamp, a signature block) are read by
    /// `ImageUnderstandingService`, not by the page parser: its Greek must come from PaddleOCR too.
    @MainActor
    @Test func imageUnderstandingReadsGreekWithPaddleOCR() async throws {
        try #require(GreekPaddleOCRService.shared.isAvailable, "ONNX Runtime and the Greek OCR models must be in the app")
        let stamp = ["ΑΚΡΙΒΕΣ ΑΝΤΙΓΡΑΦΟ", "Ο Προϊστάμενος της Διεύθυνσης"]
        let text = try #require(await ImageUnderstandingService.shared.extractTextFromImage(CIImage(cgImage: renderPage(stamp))))
        let wer = wordErrorRate(reference: stamp.joined(separator: "\n"), hypothesis: text)
        #expect(wer < 0.2, "WER \(wer): \(text)")
        #expect(OCRConfiguration.containsGreekText(text))
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
        // Vision's Cyrillic reading of a short Greek stamp.
        let stamp = try await router.recognizeText(in: image, site: "test") { "АКРІВЕТ АТІГРАФО\nПроїотнаос ins Alaúduvons" }
        #expect(stamp == "Καταγγελία σύμβασης εργασίας")
        #expect(!OCRRouterService.visionTextNeedsGreekEngine("Revenue by quarter"))
        let visionOnly = OCRRouterService(greekEngine: FakeGreek(), mode: .vision)
        #expect(try await visionOnly.recognizeText(in: image, site: "test") { "Kataryeλia oupBaons" } == "Kataryeλia oupBaons")
    }
}

// MARK: - Phase 4: on-device translation, bilingual ingestion and retrieval

@Suite("Greek translation and bilingual retrieval")
struct GreekTranslationRetrievalTests {
    /// Short Greek articles written for this test in the style of Ν. 4808/2021 (not its text).
    static let articles = [
        "Άρθρο 64\nΕτήσια άδεια\nΚάθε εργαζόμενος δικαιούται ετήσια άδεια με αποδοχές σύμφωνα με το Ν. 4808/2021. Η άδεια χορηγείται από τον εργοδότη μέσα στο ημερολογιακό έτος.",
        "Άρθρο 65\nΥπερωριακή απασχόληση\nΗ υπερωριακή εργασία αμείβεται με προσαύξηση του ωρομισθίου σύμφωνα με το Ν. 4808/2021. Ο εργοδότης καταγράφει τις υπερωρίες στο ψηφιακό σύστημα.",
        "Άρθρο 66\nΚαταγγελία σύμβασης εργασίας αορίστου χρόνου\nΗ καταγγελία της σύμβασης εργασίας αορίστου χρόνου από τον εργοδότη γίνεται εγγράφως και είναι έγκυρη μόνο αν καταβληθεί στον εργαζόμενο η νόμιμη αποζημίωση σύμφωνα με το Ν. 4808/2021.",
    ]
    static let query = "Ποιες είναι οι προϋποθέσεις απόλυσης σύμφωνα με το Άρθρο 66 του Ν. 4808/2021;"

    @Test func tokenizerMatchesMarianReferenceIds() throws {
        let url = try #require(LocalNeuralTranslator.resourceURL("opus-mt-tc-big-el-en_tokenizer", "json"))
        let grk = try SentencePieceUnigramTokenizer(jsonData: Data(contentsOf: url))
        // Reference ids from transformers' MarianTokenizer (opus-mt-tc-big-el-en / opus-mt-tc-big-en-el).
        #expect(grk.encode("Η καταγγελία της σύμβασης εργασίας γίνεται εγγράφως.") == [42486, 44535, 55972, 54544, 41610, 36786, 38904, 39, 25697])
        #expect(grk.encode("Ποιες είναι οι προϋποθέσεις απόλυσης σύμφωνα με το __LEX_ENT_001__;") == [51499, 39238, 48994, 52589, 34526, 46673, 53235, 54721, 47004, 56092, 123, 7, 17751, 7, 11268, 7, 224, 7, 7, 17, 25697])
        let enURL = try #require(LocalNeuralTranslator.resourceURL("opus-mt-tc-big-en-el_tokenizer", "json"))
        let en = try SentencePieceUnigramTokenizer(jsonData: Data(contentsOf: enURL))
        #expect(en.encode("The employer must pay severance [C1].") == [29125, 11042, 19986, 22011, 26439, 3444, 161, 6047, 333, 97, 39, 25697])
    }

    @Test func greekToEnglishKeepsLegalIdentifiers() async throws {
        try #require(LocalNeuralTranslator.isAvailable(.greekToEnglish))
        let (english, entities) = try await LocalNeuralTranslator.shared
            .translateGreekToEnglishPreservingLegalEntities(Self.query)
        #expect(entities.map(\.canonicalKey) == ["ART:66", "LAW:4808/2021"])
        #expect(english.contains("Article 66 [Άρθρο 66]"), "\(english)")
        #expect(english.contains("Law 4808/2021 [Ν. 4808/2021]"), "\(english)")
        // "απόλυση": dismissal, termination, or the British legal "redundancy".
        #expect(["dismissal", "termination", "redundancy"].contains { english.lowercased().contains($0) }, "\(english)")
    }

    @Test func englishToGreekKeepsCitationsAndGreekIdentifiers() async throws {
        try #require(LocalNeuralTranslator.isAvailable(.englishToGreek))
        let answer = "According to Article 66 [Άρθρο 66] of Law 4808/2021 [Ν. 4808/2021], the employer must pay severance [C1]. The notice must be in writing [C2]."
        let greek = try await LocalNeuralTranslator.shared.translateEnglishToGreekPreservingCitations(answer)
        #expect(greek.contains("Άρθρο 66"), "\(greek)")
        #expect(greek.contains("Ν. 4808/2021"), "\(greek)")
        #expect(greek.contains("[C1]") && greek.contains("[C2]"), "\(greek)")
        #expect(!greek.contains("Article") && !greek.contains("LEX_ENT"), "\(greek)")
        #expect(GreekLegalEntityMasker.greekLetterRatio(greek) > 0.8, "\(greek)")
    }

    @Test func englishToGreekKeepsDocumentNamesAndSaysPassage() async throws {
        try #require(LocalNeuralTranslator.isAvailable(.englishToGreek))
        let answer = "As stated in Article 5 of passage 3-2.txt, the employer must give notice in writing [C1]. The passage also sets the severance pay [C2]."
        let greek = try await LocalNeuralTranslator.shared
            .translateEnglishToGreekPreservingCitations(answer, documentNames: ["passage 3-2.txt"])
        #expect(greek.contains("passage 3-2.txt"), "\(greek)")
        #expect(greek.contains("απόσπασμα"), "\(greek)")
        #expect(!greek.lowercased().contains("διόδ") && !greek.lowercased().contains("πέρασμ"), "\(greek)")
        #expect(greek.contains("[C1]") && greek.contains("[C2]"), "\(greek)")
    }

    @Test func bilingualAnchorsCollapse() {
        #expect(GreekLegalEntityMasker.collapseBilingualAnchors("Article 38 [Άρθρο 38] of Law 4808/2021 [Ν. 4808/2021] [C1]")
            == "Article 38 of Law 4808/2021 [C1]")
    }

    @Test func greekQueryUsesTranslatedKeywordQuery() {
        let english = "What are the conditions for dismissal under Article 66 [Άρθρο 66]?"
        let lexical = HybridSearchService.greekAwareLexicalQuery(query: english, originalQuery: Self.query)
        #expect(lexical == english + " Law 4808/2021")
        // English questions are left alone.
        #expect(HybridSearchService.greekAwareLexicalQuery(query: "x", originalQuery: "What is overtime?") == "What is overtime?")
    }

    @Test func testBilingualIngestionAndHybridRetrieval() async throws {
        try #require(LocalNeuralTranslator.isAvailable(.greekToEnglish))
        // 1. Ingestion: Greek source kept, English content with bilingual anchors.
        let translated = await GreekLegalIngestion.translateChunks(Self.articles)
        for (result, greek) in zip(translated, Self.articles) {
            #expect(result.legal?.sourceTextEl == GreekLegalEntityMasker.normalizeGreekText(greek))
            #expect(result.legal?.sourceLanguage == "el")
            #expect(result.text.contains("[Ν. 4808/2021]"), "\(result.text)")
            #expect(GreekLegalEntityMasker.greekLetterRatio(result.text) < 0.3, "\(result.text)")
            #expect(result.legal?.primaryStatuteKey == "LAW:4808/2021")
        }

        // 2. Intent: a question naming an article is a lookup.
        #expect(QueryEnhancementService().classifyAnswerIntent(Self.query) == .lookup)

        // 3. Hybrid retrieval over the English index, Greek question.
        let provider = CoreMLSentenceEmbeddingProvider()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("greek-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BNNSVectorDatabase(dimension: 384, storageURL: directory.appendingPathComponent("vector_database.json"))
        let library = UUID(), document = UUID()
        var chunks: [DocumentChunk] = []
        for (index, result) in translated.enumerated() {
            chunks.append(DocumentChunk(
                documentId: document, content: result.text,
                embedding: try await provider.embed(text: result.text),
                metadata: ChunkMetadata(chunkIndex: index), legal: result.legal
            ))
        }
        try await store.storeBatch(chunks: chunks)
        let rows = chunks.map { chunk in
            (
                chunkIndex: chunk.metadata.chunkIndex, pageNumber: Int?.none, sectionTitle: String?.none,
                sectionPath: String?.none, structureType: String?.none, chunkType: String?.none,
                tableTitle: String?.none, content: chunk.content,
                structuredMetadata: SQLiteFullTextService.StructuredChunkMetadata?.none
            )
        }
        await SQLiteFullTextService.shared.storeChunks(documentId: document, containerId: library, chunks: rows)
        defer { Task { await SQLiteFullTextService.shared.deleteChunks(for: document) } }

        let queryEn = try #require(await RAGService.greekQueryTranslation(Self.query))
        let search = HybridSearchService(vectorDatabase: store)
        let results = try await search.search(
            query: queryEn, originalQuery: Self.query,
            embedding: try await provider.embed(text: queryEn), topK: 3, containerId: library
        )
        #expect(results.first?.chunk.metadata.chunkIndex == 2, "R@1: \(results.map { $0.chunk.content.prefix(40) })")
        #expect(results.first?.chunk.sourceTextEl?.hasPrefix("Άρθρο 66") == true)
    }

    @Test func importPretranslatesAndReleasesTheModels() async throws {
        try #require(LocalNeuralTranslator.isAvailable(.greekToEnglish))
        let translator = LocalNeuralTranslator.shared
        // Sentences of all three articles pretranslated (a no-op with the one-sentence models the
        // app ships), then assembled chunk by chunk.
        let texts = Self.articles.map { GreekLegalEntityMasker.normalizeGreekText($0) }
        await translator.pretranslateGreekChunks(texts)
        for text in texts {
            let (english, _) = try await translator.translateGreekToEnglishPreservingLegalEntities(text)
            #expect(english.contains("[Ν. 4808/2021]") && GreekLegalEntityMasker.greekLetterRatio(english) < 0.3, "\(english)")
        }
        // Released models load again on the next translation.
        await translator.releaseModels()
        let again = try await translator.translate("Ο εργοδότης καταγράφει τις υπερωρίες.", direction: .greekToEnglish)
        #expect(again.lowercased().contains("overtime"), "\(again)")
    }

    /// Opt-in (`TEST_RUNNER_OI_TRANSLATE_BENCH=1`): the same Labour Code text translated one
    /// sentence at a time and in batches, back to back in one process, so both see the same load.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["OI_TRANSLATE_BENCH"] == "1"))
    func batchedTranslationSpeed() async throws {
        try #require(LocalNeuralTranslator.isAvailable(.greekToEnglish))
        try #require(try await LocalNeuralTranslator.shared.takesBatches(.greekToEnglish), "needs models from scripts/thesis/convert_opus_mt_batched.py")
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Benchmarks/GreekLabourCode/pd_62_2025_excerpt.pdf")
        let pdf = try #require(PDFDocument(url: url))
        let lines = (2..<min(pdf.pageCount, 8)).compactMap { pdf.page(at: $0)?.string }.joined(separator: "\n")
            .components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let chunks = stride(from: 0, to: lines.count, by: 6)
            .map { lines[$0..<min($0 + 6, lines.count)].joined(separator: "\n") }
            .filter(GreekLegalIngestion.isGreekChunk).map(GreekLegalEntityMasker.normalizeGreekText)
        let translator = LocalNeuralTranslator.shared
        _ = try await translator.translate("Ο εργοδότης.", direction: .greekToEnglish)  // loads the model
        await translator.clearCache()
        var started = Date()
        var alone: [String] = []
        for chunk in chunks { alone.append(try await translator.translateGreekToEnglishPreservingLegalEntities(chunk).textEn) }
        let aloneSeconds = Date().timeIntervalSince(started)
        await translator.clearCache()
        started = Date()
        await translator.pretranslateGreekChunks(chunks, batchSize: 16)
        var batched: [String] = []
        for chunk in chunks { batched.append(try await translator.translateGreekToEnglishPreservingLegalEntities(chunk).textEn) }
        let batchedSeconds = Date().timeIntervalSince(started)
        await translator.releaseModels()
        let same = zip(alone, batched).filter { $0 == $1 }.count
        print(String(format: "[TranslateBench] %d chunks: one sentence at a time %.1f s, batched %.1f s (%.1fx), identical chunks %d", chunks.count, aloneSeconds, batchedSeconds, aloneSeconds / batchedSeconds, same))
        #expect(batched.allSatisfy { GreekLegalEntityMasker.greekLetterRatio($0) < 0.3 })
    }

    @Test func importPretranslatesEveryWindowAndFinishesOnce() async {
        let greek = "Ο εργοδότης καταγράφει τις υπερωρίες στο ψηφιακό σύστημα."
        let texts = (0..<330).map { $0 % 10 == 0 ? "An English line \($0)." : greek + " \($0)" }
        var windows: [Int] = []
        var finished = 0
        let results = await GreekLegalIngestion.translateChunks(
            texts,
            translate: { (textEn: "Translated: " + $0, entities: []) },
            pretranslate: { windows.append($0.count) },
            finish: { finished += 1 })
        #expect(windows == [256, 41])  // 297 Greek chunks
        #expect(finished == 1)
        #expect(results.count == 330 && results[0].text == "An English line 0." && results[1].text.hasPrefix("Translated: "))
    }

    @Test func articleReferencesResolveToTheArticle() {
        let document = UUID()
        func chunk(_ index: Int, _ text: String) -> DocumentChunk {
            DocumentChunk(documentId: document, content: text, embedding: [], metadata: ChunkMetadata(chunkIndex: index))
        }
        let holder = chunk(0, "Article 22 [Άρθρο 22]\nThe employer keeps a register of working time.")
        let citing = chunk(1, "Article 30 [Άρθρο 30]\nThe register of Article 22 [Άρθρο 22] paragraph 1 is kept digitally.")
        let other = chunk(2, "Article 31 [Άρθρο 31]\nOvertime pay.")
        #expect(LegalCrossReferences.definedArticle(of: holder) == "ART:22")
        let resolved = LegalCrossReferences.resolve(top: [citing], query: "register", pool: [holder, citing, other])
        #expect(resolved.map(\.id) == [holder.id])
        let targets = GraphIndexService.extractReferenceTargets(from: "Βλ. Άρθρο 22 παρ. 1 του Ν. 4808/2021 και Article 5")
        #expect(targets.contains("article:22") && targets.contains("article:5") && targets.contains("statute:4808/2021"), "\(targets)")
    }
}

// MARK: - Phase 5: verification gates, strict abstention, Greek answers

@Suite("Greek legal verification and abstention")
struct GreekLegalVerificationTests {
    static func retrieved(_ text: String, score: Float, greek: String? = nil, index: Int = 0) -> RetrievedChunk {
        let entities = GreekLegalEntityMasker.extractEntities(from: greek ?? text)
        let legal = LegalChunkMetadata(
            sourceTextEl: greek, sourceLanguage: greek == nil ? "en" : "el", legalEntities: entities,
            primaryStatuteKey: GreekLegalEntityMasker.primaryStatuteKey(for: entities)
        )
        let chunk = DocumentChunk(
            documentId: UUID(), content: text, embedding: [], metadata: ChunkMetadata(chunkIndex: index), legal: legal)
        return RetrievedChunk(chunk: chunk, similarityScore: score, rank: index + 1, sourceDocument: "law.pdf")
    }

    static func response(_ text: String, chunks: [RetrievedChunk]) -> RAGResponse {
        RAGResponse(
            queryId: UUID(), retrievedChunks: chunks, generatedResponse: text,
            metadata: ResponseMetadata(
                timeToFirstToken: nil, totalGenerationTime: 1, tokensGenerated: 40, tokensPerSecond: nil,
                modelUsed: "Apple Intelligence (On-Device)", retrievalTime: 0, retrievalConfigSummary: "test",
                gatingDecision: nil, toolCallsMade: 0, embeddingProvider: nil
            )
        )
    }

    static let article38 = retrieved(
        "Article 38 [Άρθρο 38] of Law 4808/2021 [Ν. 4808/2021]: the employer records working time in the digital work card.",
        score: 0.9,
        greek: "Άρθρο 38 του Ν. 4808/2021: ο εργοδότης καταγράφει τον χρόνο εργασίας στην ψηφιακή κάρτα εργασίας."
    )

    @Test func testGateFHallucinatedArticleRejection() async {
        #expect(LegalVerificationPolicy.unsupportedLegalIdentifiers(
            response: "Σύμφωνα με το Άρθρο 99 του Ν. 4808/2021 ο εργοδότης ...", chunks: [Self.article38]) == ["ART:99"])
        #expect(LegalVerificationPolicy.unsupportedLegalIdentifiers(
            response: "Under Article 38 of Law 4808/2021 working time is recorded [C1].", chunks: [Self.article38]).isEmpty)
        let mdChunk = RetrievedChunk(
            chunk: DocumentChunk(
                documentId: UUID(),
                content: "For employees the minimum wage is set at 920.00 euros.",
                embedding: [],
                metadata: ChunkMetadata(chunkIndex: 0),
                legal: LegalChunkMetadata(sourceTextEl: "Για τους υπαλλήλους ο κατώτατος μισθός ορίζεται στα 920,00 ευρώ.", sourceLanguage: "el", legalEntities: [], documentStatuteKey: "MD:8934")
            ),
            similarityScore: 0.9, rank: 1, sourceDocument: "ya_8934_2026_fek_b1759.pdf"
        )
        #expect(LegalVerificationPolicy.unsupportedLegalIdentifiers(
            response: "According to Ministerial Decision 8934/2026, the minimum wage is 920.00 euros [S1].",
            chunks: [mdChunk]).isEmpty)

        let draft = "Under Article 99 of Law 4808/2021, the employer records working time in the digital work card [C1]."
        let result = await VerificationGateService().verify(
            response: draft, query: "How is working time recorded under Law 4808/2021?",
            retrievedChunks: [Self.article38], topScores: [0.9], enforceLegalChecks: true)
        let gateF = result.gateResults.first { $0.gate == .quoteFaithfulness }
        #expect(gateF?.passed == false)
        #expect(result.shouldAbstain)

        // Rejected before the UI: the reviewed answer is the Greek abstention, nothing is translated.
        var translated = false
        let reviewed = await GreekLegalAnswerFinalizer.review(
            question: "Πώς καταγράφεται ο χρόνος εργασίας;", queryEn: "How is working time recorded under Law 4808/2021?",
            response: Self.response(draft, chunks: [Self.article38]),
            verify: { d, q, c in await VerificationGateService().verify(response: d, query: q, retrievedChunks: c, topScores: [0.9], enforceLegalChecks: true) },
            translate: { text, _ in translated = true; return text }
        )
        #expect(reviewed.response.generatedResponse == LegalVerificationPolicy.greekAbstentionMessage)
        #expect(reviewed.review.abstained)
        #expect(!translated)
    }

    @Test func testGateILegalConstitutionNoFalseBreach() async {
        let constitution = Self.retrieved(
            "Article 51 [Άρθρο 51]: The number of Members of Parliament is fixed by law; it may not be less than two hundred nor more than three hundred.",
            score: 0.8,
            greek: "Άρθρο 51: Ο αριθμός των βουλευτών ορίζεται με νόμο, δεν μπορεί όμως να είναι κατώτερος από διακόσιους ούτε ανώτερος από τριακόσιους."
        )
        for query in ["What is the minimum and maximum allowable number of Members of Parliament?", "Ποιος είναι ο ελάχιστος και μέγιστος αριθμός βουλευτών;"] {
            let result = await VerificationGateService().verify(
                response: "Parliament has at least two hundred and at most three hundred Members [C1].",
                query: query, retrievedChunks: [constitution], topScores: [0.8], enforceLegalChecks: true)
            let gateI = result.gateResults.first { $0.gate == .statutoryIsolation }
            #expect(gateI?.passed == true)
            let allDetails = result.gateResults.map(\.details).joined(separator: " ").uppercased()
            #expect(!allDetails.contains("IN VIVO") && !allDetails.contains("IN VITRO") && !allDetails.contains("DOMAIN ISOLATION"))
        }
        // A real statutory conflict: the question names Ν. 4808/2021, every passage cites only Ν. 3863/2010.
        let other = Self.retrieved("Article 4 of Law 3863/2010 [Ν. 3863/2010] sets the pension contribution.", score: 0.8)
        #expect(LegalVerificationPolicy.statutoryIsolationViolation(
            query: "Τι ορίζει ο Ν. 4808/2021 για τις εισφορές;", chunks: [other.chunk]) == "LAW:4808/2021")
        #expect(LegalVerificationPolicy.statutoryIsolationViolation(
            query: "Τι ορίζει ο Ν. 4808/2021;", chunks: [other.chunk, Self.article38.chunk]) == nil)
    }

    @Test func testStrictAbstentionBelowThreshold() async {
        let weak = Self.retrieved("Annual leave is granted by the employer.", score: 0.15)
        #expect(GreekLegalAnswerFinalizer.preGenerationAbstentionReason(query: "What is the severance for dismissal?", chunks: [weak]) != nil)
        #expect(GreekLegalAnswerFinalizer.preGenerationAbstentionReason(query: "x", chunks: []) != nil)
        // 0.25 with no overlap abstains, with an overlapping word it doesn't.
        let middling = Self.retrieved("Annual leave is granted by the employer.", score: 0.25)
        #expect(GreekLegalAnswerFinalizer.preGenerationAbstentionReason(query: "What is the severance for dismissal?", chunks: [middling]) != nil)
        #expect(GreekLegalAnswerFinalizer.preGenerationAbstentionReason(query: "When is annual leave granted?", chunks: [middling]) == nil)

        var verified = false
        let reviewed = await GreekLegalAnswerFinalizer.review(
            question: "Ποια είναι η αποζημίωση απόλυσης;", queryEn: "What is the severance for dismissal?",
            response: Self.response("Severance is two months of pay.", chunks: [weak]),
            verify: { d, q, c in verified = true; return await VerificationGateService().verify(response: d, query: q, retrievedChunks: c, topScores: [0.15]) },
            translate: { text, _ in text }
        )
        #expect(reviewed.response.generatedResponse == LegalVerificationPolicy.greekAbstentionMessage)
        #expect(!verified, "no gate run, no second attempt, no raw passages")
        #expect(reviewed.response.retrievedChunks.count == 1)
    }

    @Test func foreignJurisdictionIsRefusedUnlessAPassageNamesIt() {
        let maternity = Self.retrieved(
            "The total duration of maternity leave is seventeen (17) weeks.", score: 0.9,
            greek: "Η συνολική διάρκεια της άδειας μητρότητας ορίζεται σε δεκαεπτά (17) εβδομάδες.")
        #expect(GreekLegalAnswerFinalizer.preGenerationAbstentionReason(
            query: "How long does maternity leave last in Germany?", chunks: [maternity])?.contains("Germany") == true)
        #expect(GreekLegalAnswerFinalizer.preGenerationAbstentionReason(
            query: "How long does maternity leave last?", chunks: [maternity]) == nil)
        // A passage that names the country, in its English text or only in the Greek source.
        let posted = Self.retrieved("Workers posted to Germany keep their maternity leave.", score: 0.9)
        #expect(GreekLegalAnswerFinalizer.unsupportedForeignJurisdiction(
            query: "How long does maternity leave last in Germany?", chunks: [posted]) == nil)
        let greekOnly = Self.retrieved(
            "Workers posted abroad keep their maternity leave.", score: 0.9,
            greek: "Οι εργαζόμενοι που αποσπώνται στη Γερμανία διατηρούν την άδεια μητρότητας.")
        #expect(GreekLegalAnswerFinalizer.unsupportedForeignJurisdiction(
            query: "How long does maternity leave last in Germany?", chunks: [greekOnly]) == nil)
        // Greece is not another jurisdiction.
        #expect(GreekLegalAnswerFinalizer.unsupportedForeignJurisdiction(
            query: "How long does maternity leave last in Greece?", chunks: [maternity]) == nil)
        // A worker originating from another country asks about their rights under Greek law.
        #expect(GreekLegalAnswerFinalizer.unsupportedForeignJurisdiction(
            query: "Can a worker from Albania get annual leave under Greek law?", chunks: [maternity]) == nil)
        #expect(GreekLegalAnswerFinalizer.unsupportedForeignJurisdiction(
            query: "Δικαιούται άδεια ένας εργαζόμενος από την Αλβανία;", chunks: [maternity]) == nil)
        // A country's adjective: the Mac app answered this from the Greek Code (9 Nov 2026).
        #expect(GreekLegalAnswerFinalizer.unsupportedForeignJurisdiction(
            query: "How many weeks of maternity leave does German labour law provide?", chunks: [maternity]) == "Germany")
        #expect(GreekLegalAnswerFinalizer.unsupportedForeignJurisdiction(
            query: "What does the French Labour Code say about overtime?", chunks: [maternity]) == "France")
        #expect(GreekLegalAnswerFinalizer.unsupportedForeignJurisdiction(
            query: "How many weeks of maternity leave does German labour law provide?", chunks: [posted]) == nil,
            "a passage that names Germany")
        // Not a jurisdiction: a worker's nationality, or EU law.
        #expect(GreekLegalAnswerFinalizer.unsupportedForeignJurisdiction(
            query: "Is a German worker in Athens entitled to maternity leave?", chunks: [maternity]) == nil)
        #expect(GreekLegalAnswerFinalizer.unsupportedForeignJurisdiction(
            query: "What does European law provide on maternity leave?", chunks: [maternity]) == nil)
    }

    @Test func documentStatuteIsReadFromTheTitlePage() {
        // Openings as the Simulator's import stored them; the law's "NOMOΣ" has Latin N, O, M, O.
        #expect(GreekLegalIngestion.documentStatuteKey(opening: """
            ΕΦΗΜΕΡΙΔΑ
            ΤΗΣ ΚΥΒΕΡΝΗΣΕΩΣ
            11 Ιουλίου 2025
            ΤΕΥΧΟΣ ΠΡΩΤΟ
            ΠΡΟΕΔΡΙΚΟ ΔΙΑΤΑΓΜΑ ΥΠ’ ΑΡΙΘΜ. 62
            Κώδικας Εργατικού Δικαίου.
            1. Την παρ. 6 του άρθρου 67 του ν. 4622/2019
            """) == "PD:62/2025")
        #expect(GreekLegalIngestion.documentStatuteKey(opening: """
            NOMOΣ ΥΠ’ ΑΡΙΘΜ. 5239
            Δίκαιη Εργασία για Όλους
            17 Οκτωβρίου 2025
            """) == "LAW:5239/2025")
        #expect(GreekLegalIngestion.documentStatuteKey(opening: """
            27 Μαρτίου 2026
            ΤΕΥΧΟΣ ΔΕΥΤΕΡΟ
            ΑΠΟΦΑΣΕΙΣ
            Αριθμ. 8934
            Καθορισμός νομοθετημένου κατώτατου μισθού
            α) Του άρθρου 141Α του Κώδικα Εργατικού Δικαίου (π.δ. 62/2025, Α’ 121)
            """) == "MD:8934")
        #expect(GreekLegalIngestion.documentStatuteKey(opening: "ΣΥΝΤΑΓΜΑ\nΤΗΣ\nΕΛΛΑΔΑΣ\nΌπως αναθεωρήθηκε\nμε το Ψήφισμα της 27ης Μαΐου 2008") == "CONST")
        // A text that only cites statutes is none of them.
        #expect(GreekLegalIngestion.documentStatuteKey(
            opening: "Σύμφωνα με το άρθρο 22 του Συντάγματος και τον ν. 4808/2021, ο εργοδότης ...") == nil)
        let tagged = GreekLegalIngestion.withDocumentStatute([nil, LegalChunkMetadata(sourceLanguage: "el")], opening: "ΝΟΜΟΣ ΥΠ' ΑΡΙΘΜ. 5278")
        #expect(tagged.map { $0?.documentStatuteKey } == ["LAW:5278", "LAW:5278"])
        #expect(tagged[1]?.sourceLanguage == "el")
    }

    static func retrieved(_ text: String, document statute: String?) -> RetrievedChunk {
        let base = retrieved(text, score: 0.9)
        var legal = base.chunk.legal ?? LegalChunkMetadata()
        legal.documentStatuteKey = statute
        let chunk = DocumentChunk(
            documentId: UUID(), content: text, embedding: [], metadata: ChunkMetadata(chunkIndex: 0), legal: legal)
        return RetrievedChunk(chunk: chunk, similarityScore: 0.9, rank: 1, sourceDocument: "law.pdf")
    }

    @Test func questionNamingALibraryStatuteIsSearchedInThatDocument() {
        let law5278 = UUID(), law5239 = UUID(), decision = UUID(), constitution = UUID()
        let keys = [law5278: "LAW:5278/2026", law5239: "LAW:5239/2025", decision: "MD:8934", constitution: "CONST"]
        #expect(GreekLegalAnswerFinalizer.statuteScope(
            query: "Για πόσο χρόνο ισχύουν οι κανονιστικοί όροι σύμφωνα με τον ν. 5278/2026;", documentKeys: keys) == [law5278])
        #expect(GreekLegalAnswerFinalizer.statuteScope(query: "What does Law 5239/2025 say about overtime?", documentKeys: keys) == [law5239])
        // The masker reads a law's number only with its year, so "Law 5239" alone scopes nothing.
        #expect(GreekLegalAnswerFinalizer.statuteScope(query: "What does Law 5239 say about overtime?", documentKeys: keys) == nil)
        #expect(GreekLegalAnswerFinalizer.statuteScope(query: "Τι ορίζει το άρθρο 16 του Συντάγματος;", documentKeys: keys) == [constitution])
        // No statute named, or only one that is not a document: the whole library.
        #expect(GreekLegalAnswerFinalizer.statuteScope(query: "Πόσες ώρες υπερωρίας επιτρέπονται;", documentKeys: keys) == nil)
        #expect(GreekLegalAnswerFinalizer.statuteScope(query: "What does Law 4808/2021 provide?", documentKeys: keys) == nil)
        // Another year is another statute.
        #expect(GreekLegalAnswerFinalizer.statuteScope(query: "What does Law 5239/2010 provide?", documentKeys: keys) == nil)
    }

    @Test func frontMatterIsLeftOutWhenTheDocumentHasArticles() {
        let law = UUID(), decision = UUID()
        func passage(_ document: UUID, _ index: Int, _ text: String) -> RetrievedChunk {
            RetrievedChunk(chunk: DocumentChunk(documentId: document, content: text, embedding: [], metadata: ChunkMetadata(chunkIndex: index)),
                           similarityScore: 1, rank: index + 1)
        }
        let title = passage(law, 0, "LAW NO. 5278 National Social Agreement. Article 8 After-effect of all normative terms. Article 9 Extension.")
        let contents = passage(law, 1, "CHAPTER D AFTER-EFFECT Article 8 After-effect of all normative terms of collective agreements")
        let article8 = passage(law, 12, "Article 8 [Άρθρο 8]\nThe normative terms continue to apply for three months.")
        let continued = passage(law, 13, "After the three months all normative terms continue to apply.")
        let wage = passage(decision, 0, "The statutory minimum wage is set at 920 euros.")
        let pool = [title, contents, passage(law, 2, "Article 1 [Άρθρο 1]\nPurpose of the law is the strengthening of agreements."), article8, continued, wage].map(\.chunk)
        let kept = LegalCrossReferences.droppingFrontMatter([title, wage, contents, article8, continued], pool: pool)
        #expect(kept.map(\.chunk.id) == [wage, article8, continued].map(\.chunk.id))
        // Only front matter: unchanged.
        #expect(LegalCrossReferences.droppingFrontMatter([title, contents], pool: pool).count == 2)
    }

    @Test func namedStatuteIsRefusedUnlessAPassageComesFromOrCitesIt() {
        let leave = Self.retrieved(
            "Article 210: the employee is entitled to annual paid leave of twenty (20) working days.", document: "PD:62/2025")
        let constitution = "What does Article 16 of the Constitution provide for employees' annual leave?"
        #expect(GreekLegalAnswerFinalizer.preGenerationAbstentionReason(query: constitution, chunks: [leave])?
            .contains("the Constitution") == true)
        // A passage of the Constitution, or one that cites it, answers.
        let article16 = Self.retrieved("Article 16: education is a basic mission of the State.", document: "CONST")
        #expect(GreekLegalAnswerFinalizer.unsupportedNamedStatute(query: constitution, chunks: [leave, article16]) == nil)
        let citing = Self.retrieved("Under Article 22 of the Constitution, work is a right.", document: "PD:62/2025")
        #expect(GreekLegalAnswerFinalizer.unsupportedNamedStatute(query: constitution, chunks: [citing]) == nil)
        // "Constitutional" is not the Constitution; imports without document keys are not judged.
        #expect(GreekLegalAnswerFinalizer.unsupportedNamedStatute(
            query: "Is a dismissal for union membership constitutional?", chunks: [leave]) == nil)
        #expect(GreekLegalAnswerFinalizer.unsupportedNamedStatute(
            query: constitution, chunks: [Self.retrieved(leave.chunk.content, score: 0.9)]) == nil)
        // A law the passage's document is, with or without the year on either side.
        let law = Self.retrieved("Article 5: the digital work card applies to all employers.", document: "LAW:5239/2025")
        #expect(GreekLegalAnswerFinalizer.unsupportedNamedStatute(
            query: "What does Article 5 of Law 5239/2025 provide?", chunks: [law]) == nil)
        #expect(GreekLegalAnswerFinalizer.unsupportedNamedStatute(
            query: "What does Article 5 of Law 5278/2026 provide?", chunks: [law]) == "Law 5278/2026")
        #expect(LegalVerificationPolicy.sameStatute("LAW:5239", "LAW:5239/2025"))
        #expect(!LegalVerificationPolicy.sameStatute("PD:62/2025", "PD:62/2010"))
        // Gate I: a passage of the named law counts as that law even when it cites only others.
        let amending = Self.retrieved(
            "Article 5 of Law 5239/2025 amends Article 38 [Άρθρο 38] of Law 4808/2021 [Ν. 4808/2021].", document: "LAW:5239/2025")
        let notCiting = Self.retrieved("Paragraph 2 of Law 4808/2021 [Ν. 4808/2021] is replaced.", document: "LAW:5239/2025")
        #expect(LegalVerificationPolicy.statutoryIsolationViolation(
            query: "What does Law 5239/2025 change?", chunks: [notCiting.chunk]) == nil)
        #expect(LegalVerificationPolicy.statutoryIsolationViolation(
            query: "What does Law 5239/2025 change?", chunks: [amending.chunk]) == nil)
    }

    @Test func draftThatOpensWithMissingEvidenceIsRefused() async {
        let padded = "### Income tax for employees\n\nThe excerpts do not directly specify an income tax rate for employees. However, **financial tax** is mentioned under Article 285 [S1]."
        #expect(GreekLegalAnswerFinalizer.declaresMissingEvidence(padded))
        #expect(GreekLegalAnswerFinalizer.declaresMissingEvidence("Insufficient evidence in provided sources. The excerpts cover compensation [S1]."))
        #expect(GreekLegalAnswerFinalizer.declaresMissingEvidence("**The document does not mention** any stamps for old-age pension."))
        // Qualified in the same sentence, an answer first, or the gap named after the answer: kept.
        #expect(!GreekLegalAnswerFinalizer.declaresMissingEvidence(
            "The documents do not specify a time limit in general, but certain procedural timelines are outlined [S1]."))
        #expect(!GreekLegalAnswerFinalizer.declaresMissingEvidence(
            "The dismissal is not invalid solely because the employee refused part-time work, as the excerpts do not say so."))
        #expect(!GreekLegalAnswerFinalizer.declaresMissingEvidence(
            "Annual leave is twenty (20) working days [S1]. The excerpts do not mention exceptions."))

        var verified = false
        let reviewed = await GreekLegalAnswerFinalizer.review(
            question: "Ποιος είναι ο συντελεστής φόρου εισοδήματος για τους μισθωτούς;",
            queryEn: "What is the income tax rate for employees?",
            response: Self.response(padded, chunks: [Self.article38]),
            verify: { d, q, c in verified = true; return await VerificationGateService().verify(response: d, query: q, retrievedChunks: c, topScores: [0.9]) },
            translate: { text, _ in text }
        )
        #expect(reviewed.response.generatedResponse == LegalVerificationPolicy.greekAbstentionMessage)
        #expect(reviewed.review.reason == "the draft says the passages don't answer the question")
        #expect(!verified)
    }

    @Test func verifiedDraftIsTranslated() async {
        let draft = "Under Article 38 of Law 4808/2021, the employer records working time in the digital work card [C1]."
        let reviewed = await GreekLegalAnswerFinalizer.review(
            question: "Πώς καταγράφεται ο χρόνος εργασίας;", queryEn: "How does the employer record working time?",
            response: Self.response(draft, chunks: [Self.article38]),
            verify: { _, _, _ in
                RAGVerificationResult(passed: true, gateResults: [], claimResults: [], overallConfidence: 0.9, shouldAbstain: false, abstainReason: nil)
            },
            translate: { text, _ in "GREEK: " + text }
        )
        #expect(reviewed.response.generatedResponse == "GREEK: " + draft)
        #expect(reviewed.review.englishDraft == draft)
        #expect(!reviewed.review.abstained)
        #expect(reviewed.response.structuredAnswer == nil)
    }

    @Test func greekNumeralsAndLegalQueries() {
        #expect(LegalVerificationPolicy.normalizeGreekNumerals("αποζημίωση 1.200,50 ευρώ από 19.06.2021, ποσοστό 12,5%")
            == "αποζημίωση 1200.50 ευρώ από 19/06/2021, ποσοστό 12.5%")
        #expect(LegalVerificationPolicy.normalizeGreekNumerals("version 1.2 of 3,000 units") == "version 1.2 of 3,000 units")
        #expect(LegalVerificationPolicy.isLegalQuery("Can a pregnant employee be dismissed?"))
        #expect(LegalVerificationPolicy.isLegalQuery("Πότε δικαιούται άδεια μητρότητας η εργαζόμενη;"))
        #expect(!LegalVerificationPolicy.isLegalQuery("Is illegal parking towed?"))
        #expect(GreekLegalAnswerContext.applies(to: "Ποια είναι η αποζημίωση απόλυσης;"))
        #expect(!GreekLegalAnswerContext.applies(to: "What is the severance for dismissal?"))
    }

    @Test func gateCReadsGreekNumbers() async {
        let chunk = Self.retrieved("Severance is EUR 1.200,50 [αποζημίωση].", score: 0.9, greek: "Η αποζημίωση είναι 1.200,50 ευρώ.")
        let result = await VerificationGateService().verify(
            response: "The severance is 1200.50 euros [C1].", query: "What is the severance?",
            retrievedChunks: [chunk], topScores: [0.9], enforceLegalChecks: true)
        #expect(result.gateResults.first { $0.gate == .numericSanity }?.passed == true)
    }

    @Test func numberWordsReadAsDigits() {
        let annotate = LegalVerificationPolicy.annotatingSpelledNumbers
        #expect(annotate("has completed the twenty-fifth year of age") == "has completed the twenty-fifth (25) year of age")
        #expect(annotate("not less than two hundred nor more than three hundred") == "not less than two hundred (200) nor more than three hundred (300)")
        #expect(annotate("one hundred and fifty days") == "one hundred and fifty (150) days")
        #expect(annotate("είναι εικοσιπέντε ετών") == "είναι εικοσιπέντε (25) ετών")
        #expect(annotate("μικρότερος από διακόσιους ούτε μεγαλύτερος από τριακόσιους") == "μικρότερος από διακόσιους (200) ούτε μεγαλύτερος από τριακόσιους (300)")
        #expect(annotate("το εικοστό πέμπτο έτος") == "το εικοστό πέμπτο (25) έτος")
        #expect(annotate("εκατόν πενήντα ημέρες") == "εκατόν πενήντα (150) ημέρες")
        // "One", "except" (εκτός) and "week" (εβδομάδα) are not numbers here.
        #expect(annotate("one of the members, εκτός από μία εβδομάδα") == "one of the members, εκτός από μία εβδομάδα")
        #expect(annotate("δύο ή τρεις φορές") == "δύο (2) ή τρεις (3) φορές")
    }

    @Test func answerMarkdownIsRemovedBeforeTranslation() {
        #expect(LocalNeuralTranslator.withoutMarkdown("### Notice\nfor the first **twelve (12)** months, *not* later [S1].\n- one item")
            == "Notice\nfor the first twelve (12) months, not later [S1].\n- one item")
    }

    @Test func englishNumberWordsBecomeDigitsBeforeTranslation() {
        let digits = SpelledNumber.digitsForEnglishNumberWords
        #expect(digits("not less than **two-hundred** nor more than **three hundred** [S3]")
            == "not less than **200** nor more than **300** [S3]")
        #expect(digits("one hundred and fifty hours a year, five days") == "150 hours a year, 5 days")
        #expect(digits("up to **twenty-six (26)** working days") == "up to **26** working days")
        // Fractions, ordinals, "one" and "a second" stay words.
        #expect(digits("a two-thirds majority, then three fifths, then one half") == "a two-thirds majority, then three fifths, then one half")
        #expect(digits("the twenty-fifth year, one month, a second notice") == "the twenty-fifth year, one month, a second notice")
        #expect(digits("two months and six months of service") == "2 months and 6 months of service")
    }

    @Test func offTopicFigureIsDroppedButAnOnTopicOneStillRefuses() async {
        let draft = """
            ### Violence and harassment at work

            - The employer must prevent and address violence and harassment at work, including gender-based harassment [S1].
            - The employer adopts a policy on the prevention of harassment and informs the employees about it [S1].
            - **Six (6)** months after childbirth [S1] is the period during which the working father is protected from dismissal.
            """
        let harassment = "What must the employer do against violence and harassment at work?"
        let trimmed = GreekLegalAnswerFinalizer.droppingOffTopicFigures(from: draft, query: harassment)
        #expect(trimmed?.contains("(6)") == false)
        #expect(trimmed?.contains("gender-based harassment [S1]") == true)
        #expect(trimmed?.hasPrefix("### Violence and harassment at work") == true)
        // The figure answers this question: never dropped.
        #expect(GreekLegalAnswerFinalizer.droppingOffTopicFigures(
            from: draft, query: "For how long after childbirth is the father protected from dismissal?") == nil)

        // Gate C fails only while the figure is in the draft.
        func gates(_ text: String) -> RAGVerificationResult {
            let ok = !text.contains("(6)")
            return RAGVerificationResult(
                passed: ok,
                gateResults: [.init(gate: .numericSanity, passed: ok, confidence: ok ? 1 : 0, details: ""),
                              .init(gate: .semanticGrounding, passed: true, confidence: 0.9, details: "")],
                claimResults: [], overallConfidence: ok ? 0.8 : 0.3, shouldAbstain: !ok, abstainReason: ok ? nil : "Gate C")
        }
        let answered = await GreekLegalAnswerFinalizer.review(
            question: "Τι οφείλει να κάνει ο εργοδότης για τη βία και την παρενόχληση;", queryEn: harassment,
            response: Self.response(draft, chunks: [Self.article38]),
            verify: { d, _, _ in gates(d) }, translate: { text, _ in text })
        #expect(!answered.review.abstained)
        #expect(!answered.review.englishDraft.contains("(6)"))

        let refused = await GreekLegalAnswerFinalizer.review(
            question: "Για πόσο διάστημα προστατεύεται ο πατέρας από απόλυση;",
            queryEn: "For how long after childbirth is the father protected from dismissal?",
            response: Self.response(draft, chunks: [Self.article38]),
            verify: { d, _, _ in gates(d) }, translate: { text, _ in text })
        #expect(refused.review.abstained)
        #expect(refused.response.generatedResponse == LegalVerificationPolicy.greekAbstentionMessage)
    }

    @Test func gatesBAndCReadNumberWordsInThePassages() async {
        let age = Self.retrieved(
            "Article 55 [Άρθρο 55] 1. A Member of Parliament must have completed the twenty-fifth year of age on the day of the election.",
            score: 0.9, greek: "Βουλευτής δεν μπορεί να εκλεγεί όποιος δεν έχει συμπληρώσει το εικοστό πέμπτο έτος της ηλικίας του.")
        let gateC = await VerificationGateService().verify(
            response: "A Member of Parliament must be at least 25 years old on the day of the election [S1].",
            query: "What is the minimum age to be elected?", retrievedChunks: [age], topScores: [0.9], enforceLegalChecks: true)
        #expect(gateC.gateResults.first { $0.gate == .numericSanity }?.passed == true)

        let seats = Self.retrieved(
            "Article 51 [Άρθρο 51] 1. The number of Members of Parliament is set by law and may not be less than two hundred or more than three hundred.",
            score: 0.9, greek: nil)
        let gateB = await VerificationGateService().verify(
            response: "The number of Members of Parliament may not be less than 200. The number of Members of Parliament may not be more than 300.",
            query: "What is the minimum and maximum number of Members of Parliament?", retrievedChunks: [seats], topScores: [0.9],
            enforceLegalChecks: true)
        #expect(gateB.claimResults.allSatisfy { $0.verdict != .unsupported }, "\(gateB.claimResults.map { "\($0.verdict) \($0.details)" })")
        #expect(gateB.gateResults.first { $0.gate == .numericSanity }?.passed == true)
        #expect(gateB.gateResults.first { $0.gate == .evidenceCoverage }?.passed == true,
                "\(gateB.gateResults.first { $0.gate == .evidenceCoverage }?.details ?? "")")
    }
}

@Suite("Greek legal review in Response Details")
struct GreekLegalReviewDetailsTests {
    @Test func reviewTravelsInTheMessageMetadata() async throws {
        let chunk = GreekLegalVerificationTests.article38
        let reviewed = await GreekLegalAnswerFinalizer.review(
            question: "Πώς καταγράφεται ο χρόνος εργασίας;", queryEn: "How does the employer record working time?",
            response: GreekLegalVerificationTests.response("Under Article 38 working time is recorded [C1].", chunks: [chunk]),
            verify: { _, _, _ in
                RAGVerificationResult(
                    passed: true,
                    gateResults: [.init(gate: .statutoryIsolation, passed: true, confidence: 1, details: "ok")],
                    claimResults: [], overallConfidence: 0.9, shouldAbstain: false, abstainReason: nil)
            },
            translate: { text, _ in text },
            assetIDs: ["instruct_3b"]
        )
        let review = try #require(reviewed.response.metadata.legalReview)
        #expect(review.assetIDs == ["instruct_3b"])
        #expect(review.queryEn == "How does the employer record working time?")
        #expect(review.gates.map(\.gate) == [VerificationGate.statutoryIsolation.rawValue])
        #expect(review.gateSummary == ["PASS Gate I: Statutory Isolation: ok"])

        // Saved with the message and read back; messages saved before have no review.
        let data = try JSONEncoder().encode(reviewed.response.metadata)
        let decoded = try JSONDecoder().decode(ResponseMetadata.self, from: data)
        #expect(decoded.legalReview == review)
        var plain = reviewed.response.metadata
        plain.legalReview = nil
        let old = try JSONDecoder().decode(ResponseMetadata.self, from: JSONEncoder().encode(plain))
        #expect(old.legalReview == nil)
    }

    @Test func abstentionResponseCarriesItsReview() {
        let response = RAGService.greekLegalAbstentionResponse(reason: "planner abstained")
        #expect(response.metadata.legalReview?.abstained == true)
        #expect(response.metadata.legalReview?.reason == "planner abstained")
    }

    @Test func assetRecorderKeepsEachIdOnce() {
        let recorder = ModelAssetRecorder()
        recorder.record(["instruct_3b"])
        recorder.record(["instruct_3b", "instruct_server_v2"])
        #expect(recorder.assetIDs == ["instruct_3b", "instruct_server_v2"])
    }
}

// MARK: - Names and non-legal Greek questions (owner's report, 2026-10-28)

@Suite("Greek names and non-legal Greek questions")
struct GreekNameQuestionTests {
    @Test func namesAreTransliteratedTheSameWay() {
        #expect(GreekLegalEntityMasker.transliterate("Ανδρέας Ζέρβας") == "Andreas Zervas")
        #expect(GreekLegalEntityMasker.transliterate("Θεσσαλονίκη") == "Thessaloniki")
        #expect(GreekLegalEntityMasker.transliterate("Ευάγγελος Μπακογιάννης") == "Evangelos Bakogiannis")
        #expect(GreekLegalEntityMasker.transliterate("Ευθύμιος Ντόκος") == "Efthymios Dokos")

        let names = GreekLegalEntityMasker.extractEntities(from: "Είμαι ο Ανδρέας Ζέρβας, γεννημένος στην Πάτρα το 1959.")
        #expect(names.map(\.canonicalKey) == ["NAME:andreas zervas"])
        #expect(names.first?.bilingualAnchor == "Andreas Zervas [Ανδρέας Ζέρβας]")
        #expect(GreekLegalEntityMasker.canonicalKeys(in: "Ποιός είναι ο Ανδρέας Ζέρβας") == ["NAME:andreas zervas"])
        // Sentence-initial function words, headings in capitals and Latin names are not names.
        #expect(GreekLegalEntityMasker.extractEntities(from: "Στην Ελλάδα η Εσπεράντο. Η Εσπεράντο σήμερα.").isEmpty)
        #expect(GreekLegalEntityMasker.extractEntities(from: "Η ΕΣΠΕΡΑΝΤΟ ΣΤΗΝ ΕΛΛΑΔΑ").isEmpty)
        #expect(GreekLegalEntityMasker.extractEntities(from: "MBA από το Kingston University").isEmpty)
    }

    @Test func greekAndMixedQuestionsNameThePersonLikeTheDocument() async throws {
        try #require(LocalNeuralTranslator.isAvailable(.greekToEnglish))
        let translator = LocalNeuralTranslator.shared
        let document = try await translator.translateGreekToEnglishPreservingLegalEntities(
            "Είμαι ο Ανδρέας Ζέρβας, γεννημένος στην Πάτρα το 1959.").textEn
        let greek = try await translator.translateGreekToEnglishPreservingLegalEntities("Ποιός είναι ο Ανδρέας Ζέρβας").textEn
        let mixed = try await translator.translateGreekToEnglishPreservingLegalEntities("Who is Ανδρέας Ζέρβας").textEn
        for text in [document, greek, mixed] {
            #expect(text.contains("Andreas Zervas [Ανδρέας Ζέρβας]"), "\(text)")
        }
        #expect(mixed == "Who is Andreas Zervas [Ανδρέας Ζέρβας]")
    }

    @Test func nonLegalGreekQuestionKeepsTheNormalGateAThreshold() async {
        let chunk = GreekLegalVerificationTests.retrieved(
            "I am Andreas Zervas [Ανδρέας Ζέρβας], born in Patras in 1959.", score: 0.45,
            greek: "Είμαι ο Ανδρέας Ζέρβας, γεννημένος στην Πάτρα το 1959.")
        let result = await GreekLegalAnswerContext.$isActive.withValue(true) {
            await VerificationGateService().verify(
                response: "Andreas Zervas was born in Patras in 1959 [C1].", query: "Who is Andreas Zervas [Ανδρέας Ζέρβας]",
                retrievedChunks: [chunk], topScores: [0.45], enforceLegalChecks: true)
        }
        #expect(result.gateResults.first { $0.gate == .retrievalConfidence }?.passed == true)
        // A legal question in the same mode still needs 0.55.
        let legal = await VerificationGateService().verify(
            response: "Severance is due [C1].", query: "What severance is due on dismissal?",
            retrievedChunks: [chunk], topScores: [0.45], enforceLegalChecks: true)
        #expect(legal.gateResults.first { $0.gate == .retrievalConfidence }?.passed == false)
    }

    @Test func pipelineFailureTextIsAnAbstention() async {
        let chunk = GreekLegalVerificationTests.article38
        var translated = false
        let reviewed = await GreekLegalAnswerFinalizer.review(
            question: "Ποιός είναι ο Ανδρέας Ζέρβας", queryEn: "Who is Andreas Zervas",
            response: GreekLegalVerificationTests.response("Unable to synthesize answer from reasoning chain.", chunks: [chunk]),
            verify: { _, _, _ in
                RAGVerificationResult(passed: true, gateResults: [], claimResults: [], overallConfidence: 1, shouldAbstain: false, abstainReason: nil)
            },
            translate: { text, _ in translated = true; return text }
        )
        #expect(reviewed.response.generatedResponse == LegalVerificationPolicy.greekAbstentionMessage)
        #expect(!translated)
    }
}

@Suite("Wrapped PDF lines")
struct ReflowTests {
    @Test func wrappedLinesAreJoinedBeforeTranslation() {
        let pdf = "[Part 1]\nΗ Εσπεράντο στην Ελλάδα το 2026: αναζωογόνηση,\nπροκλήσεις και προοπτικές\nΣτο κείμενο αυτό επιχειρώ να\nμεταφέρω τη μαρτυρία μου.\nΑνδρέας Ζέρβας\n\n- πρώτο\n- δεύτερο"
        #expect(LocalNeuralTranslator.reflow(pdf) == "[Part 1]\nΗ Εσπεράντο στην Ελλάδα το 2026: αναζωογόνηση, προκλήσεις και προοπτικές Στο κείμενο αυτό επιχειρώ να μεταφέρω τη μαρτυρία μου.\nΑνδρέας Ζέρβας\n\n- πρώτο\n- δεύτερο")
    }
}

@Suite("Sentence fragments")
struct FragmentTranslationTests {
    @Test func aChunkStartingInMidSentenceIsNotInvented() async throws {
        try #require(LocalNeuralTranslator.isAvailable(.greekToEnglish))
        let english = try await LocalNeuralTranslator.shared.translate(
            "στις προκλήσεις του μέλλοντος και ανοίγουν νέες προοπτικές για την επικοινωνία μεταξύ των ανθρώπων.",
            direction: .greekToEnglish)
        #expect(!english.contains("Commission") && !english.contains("European Union"), "\(english)")
        #expect(english.contains("communication between people"), "\(english)")
        #expect(!english.hasPrefix("..."), "\(english)")
    }

    /// Joined into one sentence, the rows came back as "16 years completed and more than 12 months
    /// compensation" (labour dev case 34).
    @Test func tableRowsAreTranslatedRowByRow() async throws {
        try #require(LocalNeuralTranslator.isAvailable(.greekToEnglish))
        let english = try await LocalNeuralTranslator.shared.translate(
            "14 έτη συμπληρωμένα 10 μηνών αποζημίωση\n15 έτη συμπληρωμένα 11 μηνών αποζημίωση\n16 έτη συμπληρωμένα και άνω 12 μηνών αποζημίωση",
            direction: .greekToEnglish)
        let lines = english.components(separatedBy: "\n")
        #expect(lines.count == 3, "\(english)")
        #expect(!english.lowercased().contains("more than 12"), "\(english)")
        #expect(lines.last.map { $0.contains("16") && $0.contains("12") && $0.lowercased().contains("month") } == true, "\(english)")
    }
}

// MARK: - Article lookup in a PDF that draws Greek with Latin glyphs (owner's report, 2026-10-28)

@Suite("Article lookup")
struct ArticleLookupTests {
    /// As PDFKit reads the Constitution's PDF: Latin o, T, M, E, P inside Greek words.
    static let page = "MEPOΣ ΠPΩTO\nBασικές διατάξεις\nTMHMA A’\nMoρφή τoυ πoλιτεύματoς\nΆρθρo 1\n1. To πoλίτευμα της Eλλάδας είναι Πρoεδρευόμενη \nKoινoβoυλευτική Δημoκρατία.\n2. Θεμέλιo τoυ πoλιτεύματoς είναι η λαϊκή  \nκυριαρχία.\nΆρθρo 2\n1. O σεβασμός και η πρoστασία της αξίας τoυ \nανθρώπoυ απoτελoύν την πρωταρχική υπoχρέωση \nτης Πoλιτείας."

    @Test func latinGlyphGreekIsRepaired() {
        let repaired = GreekLegalEntityMasker.normalizeGreekText(Self.page)
        #expect(repaired.contains("Μορφή του πολιτεύματος"), "\(repaired)")
        #expect(repaired.contains("\nΆρθρο 1\n"), "\(repaired)")
        #expect(repaired.contains("Το πολίτευμα της Ελλάδας"), "\(repaired)")
        #expect(repaired.hasPrefix("ΜΕΡΟΣ ΠΡΩΤΟ"), "\(repaired)")
    }

    @Test func headingsSurviveTranslationOnTheirOwnLines() async throws {
        try #require(LocalNeuralTranslator.isAvailable(.greekToEnglish))
        let english = try await LocalNeuralTranslator.shared
            .translateGreekToEnglishPreservingLegalEntities(GreekLegalEntityMasker.normalizeGreekText(Self.page)).textEn
        let lines = english.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        #expect(lines.contains("Article 1 [Άρθρο 1]"), "\(english)")
        #expect(lines.contains("Article 2 [Άρθρο 2]"), "\(english)")
        let chunk = DocumentChunk(
            documentId: UUID(), content: english, embedding: [], metadata: ChunkMetadata(chunkIndex: 3),
            legal: LegalChunkMetadata(sourceTextEl: GreekLegalEntityMasker.normalizeGreekText(Self.page), sourceLanguage: "el"))
        #expect(LegalCrossReferences.definedArticles(of: chunk) == ["ART:1", "ART:2"])
    }

    @Test func thePassageHoldingTheArticleComesFirst() {
        let document = UUID()
        func chunk(_ index: Int, _ greek: String, _ english: String) -> DocumentChunk {
            DocumentChunk(
                documentId: document, content: english, embedding: [], metadata: ChunkMetadata(chunkIndex: index),
                legal: LegalChunkMetadata(sourceTextEl: greek, sourceLanguage: "el"))
        }
        let transitional = chunk(90, "Μέχρι να εκδοθεί ο νόμος του άρθρου 86 παρ. 1 εφαρμόζονται οι διατάξεις των άρθρων 49 παρ. 1 και 85.",
                                 "Until the law of Article 86 [Άρθρο 86] paragraph 1 [παρ. 1] is enacted, the provisions of articles 49 paragraph 1 and 85 apply.")
        let article1 = chunk(3, GreekLegalEntityMasker.normalizeGreekText(Self.page),
                             "Form of government\nArticle 1 [Άρθρο 1]\n1. The form of government of Greece is a presidential parliamentary republic.")
        let toc = chunk(1, "Άρθρο 1. Μορφή του πολιτεύματος .......... 19", "Article 1 [Άρθρο 1]. Form of government .......... 19")
        let candidates = [transitional, toc].enumerated().map {
            RetrievedChunk(chunk: $1, similarityScore: 0.6 - Float($0) * 0.1, rank: $0 + 1)
        }
        let pinned = LegalCrossReferences.pinningRequestedArticle(
            query: "What does Article 1 [Άρθρο 1] of the Constitution say?", candidates: candidates,
            pool: [toc, article1, transitional], sourceDocument: { _ in "syntagma.pdf" })
        #expect(pinned.first?.chunk.id == article1.id)
        #expect(pinned.first?.similarityScore == 0.6)
        #expect(pinned.count == 3)
        // A question naming no article is left alone.
        #expect(LegalCrossReferences.pinningRequestedArticle(
            query: "What is the form of government?", candidates: candidates, pool: [article1], sourceDocument: { _ in "" })
            .map(\.chunk.id) == candidates.map(\.chunk.id))
    }
}

@Suite("Greek keyword arm")
struct GreekKeywordArmTests {
    @Test func greekQuestionBecomesStemPrefixes() {
        let query = SQLiteFullTextService.greekFTSQuery("Ποιο είναι το ανώτατο όριο διάρκειας της προφυλάκισης για τα κακουργήματα;")
        #expect(query == "\"ανωτα\"* OR \"οριο\"* OR \"διαρκει\"* OR \"προφυλακισ\"* OR \"κακουργημα\"*", "\(query ?? "nil")")
        #expect(SQLiteFullTextService.greekFTSQuery("Τι είναι;") == nil)
    }

    @Test func greekChunksAreFoundByTheQuestionsWords() async {
        let documentId = UUID(), containerId = UUID()
        let store = SQLiteFullTextService.shared
        let paragraphs = [
            "Η τήρηση του Συντάγματος επαφίεται στον πατριωτισμό των Ελλήνων.",
            "Ο σεβασμός στο Σύνταγμα και τους νόμους αποτελεί θεμελιώδη υποχρέωση.",
        ]
        for (index, text) in paragraphs.enumerated() {
            await store.storeLegalChunkMetadata(
                chunkId: "\(documentId.uuidString)_\(index)", documentId: documentId, containerId: containerId,
                metadata: LegalChunkMetadata(sourceTextEl: text, sourceLanguage: "el"))
        }
        let hits = await store.searchGreekChunks(
            question: "Σε ποιον επαφίεται αποκλειστικά η τήρηση του Συντάγματος;", containerId: containerId)
        #expect(hits.first?.chunkIndex == 0, "\(hits.map(\.chunkIndex))")
        await store.deleteChunks(for: documentId)
        #expect(await store.searchGreekChunks(question: "τήρηση Συντάγματος", containerId: containerId).isEmpty)
    }

    @Test func interleavingKeepsEachChunkOnce() {
        func hit(_ id: String) -> SQLiteFullTextService.ChunkSearchResult {
            .init(chunkId: id, documentId: UUID(), containerId: UUID(), chunkIndex: 0, pageNumber: nil,
                  sectionTitle: nil, sectionPath: nil, content: "", bm25Score: 0)
        }
        let merged = HybridSearchService.interleaving([hit("g1"), hit("e1"), hit("g2")], [hit("e1"), hit("e2")], limit: 10)
        #expect(merged.map(\.chunkId) == ["g1", "e1", "e2", "g2"])
    }

    @Test func pinnedArticleBringsItsContinuation() {
        let document = UUID()
        func chunk(_ index: Int, _ text: String) -> DocumentChunk {
            DocumentChunk(documentId: document, content: text, embedding: [], metadata: ChunkMetadata(chunkIndex: index))
        }
        let heading = chunk(10, "Article 120 [Άρθρο 120]\n1. This Constitution...\n2. Respect for the Constitution...")
        let continuation = chunk(11, "4. The observance of the Constitution is left to the patriotism of the Greeks...")
        let next = chunk(12, "Article 121 [Άρθρο 121]\nSomething else.")
        let pinned = LegalCrossReferences.pinningRequestedArticle(
            query: "Article 120 [Άρθρο 120]: to whom is the observance of the Constitution entrusted?",
            candidates: [RetrievedChunk(chunk: next, similarityScore: 0.5, rank: 1)],
            pool: [heading, continuation, next], sourceDocument: { _ in "" })
        #expect(pinned.map(\.chunk.metadata.chunkIndex) == [10, 11, 12])
    }
}

@Suite("Legal glossary")
struct LegalGlossaryTests {
    @Test func glossaryGreekReplacesTheModelsRendering() {
        let lemma = "σπουδαίος λόγος"
        #expect(LocalNeuralTranslator.replacingRendering("σοβαρός λόγος", with: lemma, in: "Η καταγγελία για σοβαρό λόγο είναι έγκυρη.")
            == "Η καταγγελία για σπουδαίο λόγο είναι έγκυρη.")
        #expect(LocalNeuralTranslator.replacingRendering("σοβαρός λόγος", with: lemma, in: "Σοβαρός λόγος υπάρχει όταν …")
            == "Σπουδαίος λόγος υπάρχει όταν …")
        #expect(LocalNeuralTranslator.replacingRendering("σοβαρός λόγος", with: lemma, in: "λόγω σοβαρών λόγων υγείας")
            == "λόγω σπουδαίων λόγων υγείας")
        // Other words, a different word count, or the rendering already right: unchanged.
        #expect(LocalNeuralTranslator.replacingRendering("σοβαρός λόγος", with: lemma, in: "σοβαρή βλάβη της υγείας") == "σοβαρή βλάβη της υγείας")
        #expect(LocalNeuralTranslator.replacingRendering("διάρκεια θητείας", with: "θητεία", in: "η διάρκεια θητείας") == "η διάρκεια θητείας")
    }

    @Test func termsHaveOneEnglishRendering() {
        let (masked, entities) = GreekLegalEntityMasker.maskEntities(in: "Το πολίτευμα της Ελλάδας και η Ακροτελεύτια διάταξη (Άρθρο 120).")
        #expect(entities.map(\.canonicalKey) == ["TERM:form of government", "TERM:final provision", "ART:120"])
        #expect(GreekLegalEntityMasker.unmaskEntities(in: masked, entities: entities, mode: .bilingualAnchor)
            == "Το form of government της Ελλάδας και η final provision (Article 120 [Άρθρο 120]).")
        #expect(GreekLegalEntityMasker.canonicalKeys(in: "The maximum pre-trial detention for felonies") == ["TERM:pre-trial detention", "TERM:felonies"])
        // An institution in capitals is a term, not a person's name.
        #expect(GreekLegalEntityMasker.canonicalKeys(in: "Ποιος είναι ο αρχηγός των Ενόπλων Δυνάμεων της Χώρας;") == ["TERM:Armed Forces"])
        // Labour Code terms, in the question and in an English answer alike.
        #expect(GreekLegalEntityMasker.canonicalKeys(in: "Πόση προειδοποίηση απαιτείται για την απόλυση;") == ["TERM:notice"])
        #expect(GreekLegalEntityMasker.canonicalKeys(in: "χωρίς προθεσμία για σπουδαίο λόγο") == ["TERM:serious reason"])
        #expect(GreekLegalEntityMasker.canonicalKeys(in: "for a good reason, without notice") == ["TERM:serious reason", "TERM:notice"])
        // A term is not a statutory identifier.
        #expect(!LegalVerificationPolicy.isLegalQuery("What is the form of government of Greece?"))
        #expect(LegalVerificationPolicy.unsupportedLegalIdentifiers(response: "The form of government is a republic.", chunks: []).isEmpty)
    }

    @Test func questionAndDocumentUseTheSameTerm() async throws {
        try #require(LocalNeuralTranslator.isAvailable(.greekToEnglish) && LocalNeuralTranslator.isAvailable(.englishToGreek))
        let question = try await LocalNeuralTranslator.shared
            .translateGreekToEnglishPreservingLegalEntities("Ποιο είναι το πολίτευμα της Ελλάδας σύμφωνα με το Σύνταγμα;").textEn
        let document = try await LocalNeuralTranslator.shared
            .translateGreekToEnglishPreservingLegalEntities("Το πολίτευμα της Ελλάδας είναι Προεδρευόμενη Κοινοβουλευτική Δημοκρατία.").textEn
        #expect(question.contains("form of government"), "\(question)")
        #expect(document.contains("form of government"), "\(document)")
        let greek = try await LocalNeuralTranslator.shared
            .translateEnglishToGreekPreservingCitations("Pre-trial detention may not exceed one year for felonies [S1].")
        #expect(greek.contains("κακουργήματα"), "\(greek)")
        #expect(greek.contains("[S1]"), "\(greek)")
    }
}

@Suite("Greek statute chunking")
struct GreekLegalStructureChunkerTests {
    /// A Government Gazette page as PDFKit reads it: running headers, words broken at line ends,
    /// a table of contents, titles under the headings, a part heading between articles, and a
    /// correlation table after the last article.
    static let gazette = """
    ΕΦΗΜΕΡΙΔΑ TΗΣ ΚΥΒΕΡΝΗΣΕΩΣ
    2866
    Τεύχος A’ 121/11.07.2025
    Άρθρο 1 Σύμβαση εργασίας
    Άρθρο 2 Δοκιμαστική περίοδος - Δόκιμος εργαζόμενος
    Άρθρο 3 Αμοιβή
    Άρθρο 1
    Σύμβαση εργασίας
    Με τη σύμβαση εργασίας ο εργαζόμενος έχει υπο -
    χρέωση να παρέχει, για ορισμένο ή αόριστο χρόνο, την
    εργασία του στον εργοδότη και αυτός να καταβάλλει το
    συμφωνημένο μισθό.
    Άρθρο 2
    Δοκιμαστική περίοδος - Δόκιμος εργαζόμενος
    1. Ο εργοδότης δύναται να συμφωνήσει με τον εργα-
    ζόμενο δοκιμαστική περίοδο έως έξι (6) μηνών.
    ΕΦΗΜΕΡΙΔΑ TΗΣ ΚΥΒΕΡΝΗΣΕΩΣ
    2867
    Τεύχος A’ 121/11.07.2025
    2. Αν ο εργοδότης κρίνει ότι η δοκιμαστική υπηρεσία είναι επιτυχής, ως χρόνος έναρξης της σύμβασης λογίζεται η αρχική ημερομηνία πρόσληψης.
    3. Η καταγγελία της σύμβασης κατά τη δοκιμαστική περίοδο γίνεται χωρίς προειδοποίηση και χωρίς αποζημίωση.
    ΜΕΡΟΣ Β’
    ΙΣΗ ΜΕΤΑΧΕΙΡΙΣΗ ΚΑΙ ΑΞΙΟΠΡΕΠΗΣ ΕΡΓΑΣΙΑ
    Άρθρο 3
    Αμοιβή
    Ο μισθός καταβάλλεται στο τέλος κάθε μήνα, εκτός αν συμφωνηθεί διαφορετικά.
    Πίνακας κωδικοποιούμενων διατάξεων
    Άρθρο 1
    άρθρο 648 Α.Κ.
    """

    @Test func gazettePagesAreCutByArticleAndParagraph() {
        #expect(GreekLegalStructureChunker.applies(to: Self.gazette))
        let passages = GreekLegalStructureChunker.passages(in: Self.gazette, maxWords: 200, minWords: 1)
        let articles = passages.filter { $0.article != nil }
        #expect(articles.map(\.article) == ["Άρθρο 1", "Άρθρο 2", "Άρθρο 2", "Άρθρο 2", "Άρθρο 3"])
        // The table of contents is text before the first article.
        #expect(passages.first?.article == nil)
        #expect(passages.filter { $0.article == nil }.contains { $0.text.contains("Άρθρο 2 Δοκιμαστική") })
        let first = articles[0].text
        #expect(first.hasPrefix("Άρθρο 1\nΣύμβαση εργασίας\nΜε τη σύμβαση"), "\(first)")
        #expect(first.contains("έχει υποχρέωση να παρέχει"), "\(first)")
        // Each paragraph keeps its article's heading, and no running header is left.
        #expect(articles[1].text == "Άρθρο 2\nΔοκιμαστική περίοδος - Δόκιμος εργαζόμενος\n1. Ο εργοδότης δύναται να συμφωνήσει με τον εργαζόμενο δοκιμαστική περίοδο έως έξι (6) μηνών.")
        #expect(articles.map(\.paragraphs) == [[], [1], [2], [3], []])
        #expect(!passages.contains { $0.text.contains("ΕΦΗΜΕΡΙΔΑ") || $0.text.contains("Τεύχος") || $0.text.contains("2867") })
        // The part heading goes with the next article, not into Article 2's last paragraph.
        #expect(!articles[3].text.contains("ΜΕΡΟΣ"))
        #expect(articles[4].sectionPath == ["ΜΕΡΟΣ Β'", "ΙΣΗ ΜΕΤΑΧΕΙΡΙΣΗ ΚΑΙ ΑΞΙΟΠΡΕΠΗΣ ΕΡΓΑΣΙΑ", "Άρθρο 3"])
        // The correlation table after the last article, with its "Άρθρο 1", is not an article.
        #expect(!articles[4].text.contains("Πίνακας"))
        #expect(passages.last?.article == nil && passages.last?.text.contains("άρθρο 648 Α.Κ.") == true)
        // Every passage is found as its article by the article lookup.
        for passage in articles {
            let chunk = DocumentChunk(documentId: UUID(), content: passage.text, embedding: [], metadata: ChunkMetadata(chunkIndex: 0))
            #expect(LegalCrossReferences.definedArticles(of: chunk).first == "ART:" + passage.article!.dropFirst(6))
        }
    }

    @Test func constitutionWithLookAlikeGlyphsKeepsEveryParagraph() {
        let paragraph4 = "4. Η τήρηση του Συντάγματος επαφίεται στον πατριωτισμό των Ελλήνων, που δικαιούνται και υποχρεούνται να αντιστέκονται με κάθε μέσο εναντίον οποιουδήποτε επιχειρεί να το καταλύσει με τη βία."
        let text = """
        Άρθρo 119
        Η διάταξη ισχύει από τη δημοσίευση του παρόντος Συντάγματος σε όλη την επικράτεια.
        Άρθρo 120
        1. Το Σύνταγμα αυτό, που ψηφίστηκε από την Ε' Αναθεωρητική Βουλή των Ελλήνων, υπογράφεται από τον Πρόεδρό της.
        2. Ο σεβασμός στο Σύνταγμα και τους νόμους που συμφωνούν με αυτό και η αφοσίωση στην Πατρίδα και τη Δημοκρατία αποτελούν θεμελιώδη υποχρέωση όλων των Ελλήνων.
        3. Ο σφετερισμός, με οποιονδήποτε τρόπο, της λαϊκής κυριαρχίας και των εξουσιών που απορρέουν από αυτή διώκεται.
        \(paragraph4)
        Αθήνα, 27 Ιουνίου 2008
        Ο ΠΡΟΕΔΡΟΣ ΤΗΣ ΒΟΥΛΗΣ
        ΔΗΜΗΤΡΙΟΣ Γ. ΣΙΟΥΦΑΣ
        Ψήφισμα της 6ης Μαρτίου 1986 για την αναθεώρηση διατάξεων του Συντάγματος.
        """
        let passages = GreekLegalStructureChunker.passages(in: text, maxWords: 40, minWords: 10)
        let article120 = passages.filter { $0.article == "Άρθρο 120" }
        #expect(article120.count >= 2)
        #expect(article120.allSatisfy { $0.text.hasPrefix("Άρθρο 120\n") })
        let holder = article120.first { $0.paragraphs.contains(4) }
        #expect(holder?.text.contains(paragraph4) == true, "\(article120.map(\.text))")
        #expect(passages.map(\.article).compactMap { $0 } .first == "Άρθρο 119")
        // The signatures and resolutions after the last article are not part of §4.
        #expect(holder?.text.hasSuffix("με τη βία.") == true, "\(holder?.text ?? "")")
        #expect(passages.last?.article == nil)
        #expect(passages.last?.text.contains("Ψήφισμα της 6ης Μαρτίου 1986") == true)
    }

    @Test func longParagraphIsSplitAtSentenceEnds() {
        let sentence = "Ο εργοδότης οφείλει να χορηγεί στον εργαζόμενο άδεια με αποδοχές κάθε ημερολογιακό έτος."
        let pieces = GreekLegalStructureChunker.split(Array(repeating: sentence, count: 6).joined(separator: " "), maxWords: 30)
        #expect(pieces.count == 3)
        #expect(pieces.allSatisfy { $0.hasSuffix("έτος.") && $0.split(separator: " ").count <= 30 })
    }

    /// Article 333 §1 as PDFKit reads it: the table's rows, one or two cells a line.
    static let severanceTable = """
    Άρθρο 333
    Αποζημίωση καταγγελίας χωρίς προειδοποίηση
    1. Εργοδότης που παραμελεί την υποχρέωση προειδοποίησης οφείλει να καταβάλει στον απολυόμενο εργαζόμενο αποζημίωση απόλυσης ως εξής:
    1 έτος συμπληρωμένο έως 4 έτη 2 μηνών αποζημίωση
    4 έτη συμπληρωμένα έως 6 έτη
    3 μηνών αποζημίωση
    15 έτη συμπληρωμένα
    11 μηνών αποζημίωση
    16 έτη συμπληρωμένα και άνω
    12 μηνών αποζημίωση
    Ο υπολογισμός της ως άνω αποζημίωσης γίνεται με
    βάση τις τακτικές αποδοχές του τελευταίου μήνα.
    Άρθρο 334
    Προθεσμία
    Η αποζημίωση καταβάλλεται κατά την απόλυση και η καταγγελία είναι άκυρη αν δεν καταβληθεί.
    Άρθρο 335
    Υπολογισμός
    Για τον υπολογισμό της αποζημίωσης λαμβάνεται υπόψη ο χρόνος υπηρεσίας στον ίδιο εργοδότη.
    """

    @Test func tableRowsKeepTheirLines() throws {
        let passage = try #require(GreekLegalStructureChunker.passages(in: Self.severanceTable).first { $0.article == "Άρθρο 333" })
        let lines = passage.text.components(separatedBy: "\n")
        // A row PDFKit read as two lines is one line again; every row is on its own line.
        #expect(lines.contains("16 έτη συμπληρωμένα και άνω 12 μηνών αποζημίωση"), "\(passage.text)")
        #expect(lines.contains("4 έτη συμπληρωμένα έως 6 έτη 3 μηνών αποζημίωση"), "\(passage.text)")
        #expect(lines.contains("15 έτη συμπληρωμένα 11 μηνών αποζημίωση"), "\(passage.text)")
        #expect(lines.contains("1 έτος συμπληρωμένο έως 4 έτη 2 μηνών αποζημίωση"), "\(passage.text)")
        // The prose around the table is still joined, and the sentence after it starts its own line.
        #expect(lines.contains { $0.hasPrefix("1. Εργοδότης") && $0.hasSuffix("ως εξής:") }, "\(passage.text)")
        #expect(lines.contains("Ο υπολογισμός της ως άνω αποζημίωσης γίνεται με βάση τις τακτικές αποδοχές του τελευταίου μήνα."), "\(passage.text)")
        // Cut for the token cap, the rows still keep their lines.
        let pieces = GreekLegalStructureChunker.pieces(of: passage) { $0.split(whereSeparator: \.isWhitespace).count <= 30 }
        #expect(pieces.count >= 2)
        #expect(pieces.contains { $0.components(separatedBy: "\n").contains("16 έτη συμπληρωμένα και άνω 12 μηνών αποζημίωση") }, "\(pieces)")
        // The translator's line joining leaves the rows apart too.
        let reflowed = LocalNeuralTranslator.reflow(passage.text).components(separatedBy: "\n")
        #expect(reflowed.contains("15 έτη συμπληρωμένα 11 μηνών αποζημίωση"), "\(reflowed)")
        #expect(reflowed.contains("16 έτη συμπληρωμένα και άνω 12 μηνών αποζημίωση"), "\(reflowed)")
    }

    @Test func passageOverTheTokenCapIsCutWithItsHeading() throws {
        let sentence = "Ο εργοδότης οφείλει να χορηγεί στον εργαζόμενο άδεια με αποδοχές κάθε ημερολογιακό έτος."
        let text = "Άρθρο 221\nΔικαίωμα άδειας με αποδοχές\n1. " + Array(repeating: sentence, count: 8).joined(separator: " ")
            + "\nΆρθρο 222\nΑποδοχές άδειας\nΚατά τη διάρκεια της άδειας ο εργαζόμενος δικαιούται τις συνήθεις αποδοχές.\nΆρθρο 223\nΕπίδομα άδειας\nΟι εργαζόμενοι δικαιούνται κάθε έτος επίδομα άδειας."
        let passage = try #require(GreekLegalStructureChunker.passages(in: text).first { $0.article == "Άρθρο 221" })
        // A stand-in for the token counter: at most 40 words a piece.
        let pieces = GreekLegalStructureChunker.pieces(of: passage) { $0.split(whereSeparator: \.isWhitespace).count <= 40 }
        #expect(pieces.count >= 3)
        #expect(pieces.allSatisfy { $0.hasPrefix("Άρθρο 221\nΔικαίωμα άδειας με αποδοχές\n") && $0.split(whereSeparator: \.isWhitespace).count <= 40 })
        #expect(pieces.joined().components(separatedBy: "ημερολογιακό έτος.").count - 1 == 8)
    }

    @Test func contentsWithHeadingsOnTheirOwnLinesAreNotTheArticles() {
        // PDFKit reads the Labour Code's contents with each heading on its own line, its title on
        // the next; the real articles follow with lower numbers than the last contents entry.
        let text = """
        Άρθρο 1
        Σύμβαση εργασίας και υποχρεώσεις των μερών
        Άρθρο 2
        Δοκιμαστική περίοδος και δόκιμος εργαζόμενος
        Άρθρο 588
        Έναρξη ισχύος του παρόντος διατάγματος
        Άρθρο 1
        Σύμβαση εργασίας
        Με τη σύμβαση εργασίας ο εργαζόμενος έχει υποχρέωση να παρέχει την εργασία του στον εργοδότη και αυτός να καταβάλλει το συμφωνημένο μισθό.
        Άρθρο 2
        Δοκιμαστική περίοδος
        1. Ο εργοδότης δύναται να συμφωνήσει με τον εργαζόμενο δοκιμαστική περίοδο έως έξι (6) μηνών, κατά τη διάρκεια της οποίας η σύμβαση τελεί υπό δοκιμή.
        2. Αν ο εργοδότης κρίνει ότι η δοκιμαστική υπηρεσία είναι επιτυχής, ως χρόνος έναρξης της σύμβασης λογίζεται η αρχική ημερομηνία πρόσληψης.
        Άρθρο 3
        Έλλειψη συμφωνίας για το μισθό
        Αν η εργασία κατά τις συνηθισμένες περιστάσεις παρέχεται μόνο με μισθό, λογίζεται ότι έχει σιωπηρά συμφωνηθεί μισθός.
        """
        let passages = GreekLegalStructureChunker.passages(in: text, maxWords: 200, minWords: 1)
        #expect(passages.compactMap(\.article) == ["Άρθρο 1", "Άρθρο 2", "Άρθρο 2", "Άρθρο 3"])
        #expect(!passages.contains { $0.article != nil && $0.text.contains("Έναρξη ισχύος") })
    }

    @Test func otherDocumentsAreLeftToTheGeneralChunker() {
        #expect(!GreekLegalStructureChunker.applies(to: "Article 1\nThe tenant pays rent.\nArticle 2\nThe landlord repairs.\nArticle 3\nNotice is given."))
        #expect(!GreekLegalStructureChunker.applies(to: "Η συνταγή για μουσακά.\nΥλικά: μελιτζάνες, κιμάς.\nΒήμα 1. Τηγανίζουμε."))
        // Only a table of contents: no heading on a line of its own.
        #expect(!GreekLegalStructureChunker.applies(to: "Άρθρο 1 Σκοπός\nΆρθρο 2 Ορισμοί\nΆρθρο 3 Πεδίο εφαρμογής\nΆρθρο 4 Κυρώσεις"))
    }
}
