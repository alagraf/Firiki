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
        let url = try #require(LocalNeuralTranslator.resourceURL("opus-mt-grk-en_tokenizer", "json"))
        let grk = try SentencePieceUnigramTokenizer(jsonData: Data(contentsOf: url))
        // Reference ids from transformers' MarianTokenizer (opus-mt-grk-en / opus-mt-en-el).
        #expect(grk.encode("Η καταγγελία της σύμβασης εργασίας γίνεται εγγράφως.") == [77, 12348, 14, 5193, 1061, 1396, 1078, 2752, 2471, 2, 0])
        #expect(grk.encode("Ποιες είναι οι προϋποθέσεις απόλυσης σύμφωνα με το __LEX_ENT_001__;") == [288, 512, 201, 39, 72, 4037, 35, 7729, 7, 386, 24, 16, 2254, 1733, 505, 8263, 1733, 1011, 342, 1733, 469, 400, 1733, 1733, 29, 0])
        let enURL = try #require(LocalNeuralTranslator.resourceURL("opus-mt-en-el_tokenizer", "json"))
        let en = try SentencePieceUnigramTokenizer(jsonData: Data(contentsOf: enURL))
        #expect(en.encode("The employer must pay severance [C1].") == [58, 15509, 338, 1619, 51513, 429, 383, 28634, 2, 0])
    }

    @Test func greekToEnglishKeepsLegalIdentifiers() async throws {
        try #require(LocalNeuralTranslator.isAvailable(.greekToEnglish))
        let (english, entities) = try await LocalNeuralTranslator.shared
            .translateGreekToEnglishPreservingLegalEntities(Self.query)
        #expect(entities.map(\.canonicalKey) == ["ART:66", "LAW:4808/2021"])
        #expect(english.contains("Article 66 [Άρθρο 66]"), "\(english)")
        #expect(english.contains("Law 4808/2021 [Ν. 4808/2021]"), "\(english)")
        #expect(english.lowercased().contains("dismissal") || english.lowercased().contains("termination"), "\(english)")
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
}
