//
//  GreekDemoPDFImportTests.swift
//  FirikiTests
//
//  Phase 2b (POC_PROGRESS.md, flow 4): checks the bundled OCR and translation ONNX assets and
//  verifies import behaviour (statute key, article counts, Greek source + real Opus-MT English
//  text) across the five Greek labour-law demo PDFs without requiring Apple Intelligence.
//

import Foundation
import Testing

@testable import Firiki

@Suite("Greek demo PDFs and bundled ONNX assets", .serialized)
struct GreekDemoPDFImportTests {
    struct DemoPDFSpec: Sendable, CustomTestStringConvertible {
        let relativePath: String
        let expectedStatuteKey: String
        let minimumArticles: Int
        let minimumChunks: Int
        var testDescription: String { expectedStatuteKey }
    }

    static let demoPDFs: [DemoPDFSpec] = [
        DemoPDFSpec(relativePath: "Benchmarks/GreekLabourCode/pd_62_2025_fek_a121.pdf", expectedStatuteKey: "PD:62/2025", minimumArticles: 300, minimumChunks: 500),
        DemoPDFSpec(relativePath: "Benchmarks/GreekLabourLibrary/n_5239_2025_fek_a178.pdf", expectedStatuteKey: "LAW:5239/2025", minimumArticles: 50, minimumChunks: 100),
        DemoPDFSpec(relativePath: "Benchmarks/GreekLabourLibrary/n_5278_2026_fek_a22.pdf", expectedStatuteKey: "LAW:5278/2026", minimumArticles: 12, minimumChunks: 20),
        DemoPDFSpec(relativePath: "Benchmarks/GreekLabourLibrary/n_5316_2026_fek_a105.pdf", expectedStatuteKey: "LAW:5316/2026", minimumArticles: 20, minimumChunks: 30),
        DemoPDFSpec(relativePath: "Benchmarks/GreekLabourLibrary/ya_8934_2026_fek_b1759.pdf", expectedStatuteKey: "MD:8934", minimumArticles: 0, minimumChunks: 2),
    ]

    @Test func bundledOCRAndTranslationModelsExist() {
        #expect(LocalNeuralTranslator.isAvailable(.greekToEnglish), "Missing Opus-MT el->en model/tokenizer in bundle")
        #expect(LocalNeuralTranslator.isAvailable(.englishToGreek), "Missing Opus-MT en->el model/tokenizer in bundle")
        #expect(GreekPaddleOCRService.shared.isAvailable, "Missing PaddleOCR assets in bundle")
        #expect(GreekPaddleOCRService.resourceURL(GreekPaddleOCRService.detModelName, "onnx") != nil)
        #expect(GreekPaddleOCRService.resourceURL(GreekPaddleOCRService.recModelName, "onnx") != nil)
        #expect(GreekPaddleOCRService.resourceURL(GreekPaddleOCRService.dictionaryName, "txt") != nil)
    }

    @Test(arguments: demoPDFs)
    func demoPDFExtractsStatuteArticlesAndBilingualText(_ spec: DemoPDFSpec) async throws {
        try #require(LocalNeuralTranslator.isAvailable(.greekToEnglish))
        let repo = GreekEvalCase.repository
        let processor = DocumentProcessor()

        let url = repo.appendingPathComponent(spec.relativePath)
        #expect(FileManager.default.fileExists(atPath: url.path), "Missing PDF at \(url.path)")

        let (_, extracted) = try await processor.processDocument(at: url)
        #expect(extracted.count >= spec.minimumChunks, "\(url.lastPathComponent): got \(extracted.count) chunks < \(spec.minimumChunks)")

        let openingText = extracted.prefix(3).map { $0.text }.joined(separator: "\n")
        let opening = String(openingText.prefix(GreekLegalIngestion.openingLength))
        let statuteKey = GreekLegalIngestion.documentStatuteKey(opening: opening)
        #expect(statuteKey == spec.expectedStatuteKey, "\(url.lastPathComponent): statuteKey=\(statuteKey ?? "nil") expected=\(spec.expectedStatuteKey)")

        let docId = UUID()
        let syntheticChunks: [DocumentChunk] = extracted.enumerated().map { idx, piece in
            DocumentChunk(
                documentId: docId,
                content: piece.text,
                embedding: [],
                metadata: ChunkMetadata(chunkIndex: idx, sectionTitle: piece.metadata.sectionTitle),
                legal: LegalChunkMetadata(sourceTextEl: piece.text, sourceLanguage: "el", legalEntities: [])
            )
        }
        let distinctArticles = Set(syntheticChunks.flatMap { LegalCrossReferences.definedArticles(of: $0) })
        #expect(
            distinctArticles.count >= spec.minimumArticles,
            "\(url.lastPathComponent): found \(distinctArticles.count) distinct articles < \(spec.minimumArticles)"
        )

        // Translate the first three Greek chunks through real Opus-MT and attach documentStatuteKey
        // just as `RAGService` does at import, verifying both Greek source and English index text.
        let sampleTexts: [String] = Array(extracted.map { $0.text }.filter(GreekLegalIngestion.isGreekChunk).prefix(3))
        #expect(!sampleTexts.isEmpty, "\(url.lastPathComponent): no Greek chunks found")
        let translated = await GreekLegalIngestion.translateChunks(sampleTexts)
        let tagged = GreekLegalIngestion.withDocumentStatute(translated.map { $0.legal }, opening: opening)
        for (item, legal) in zip(translated, tagged) {
            let sourceEl = try #require(legal?.sourceTextEl, "\(url.lastPathComponent): missing Greek sourceTextEl")
            #expect(!sourceEl.isEmpty, "\(url.lastPathComponent): empty Greek sourceTextEl")
            #expect(GreekLegalEntityMasker.greekLetterRatio(item.text) < 0.3, "\(url.lastPathComponent): untranslated English '\(item.text.prefix(80))'")
            #expect(legal?.documentStatuteKey == spec.expectedStatuteKey)
        }
    }

    @MainActor
    private func cleanupContainer(id: UUID, engine: RAGService, libraries: ContainerService) async {
        for doc in engine.documents where doc.containerId == id {
            try? await engine.removeDocument(doc)
        }
        libraries.deleteContainer(id: id)
    }

    @MainActor
    @Test(.timeLimit(.minutes(5)))
    func ragServiceIngestsCompactDemoPDFsWithBilingualPersistence() async throws {
        try #require(LocalNeuralTranslator.isAvailable(.greekToEnglish))
        let repo = GreekEvalCase.repository
        let pdfURLs = [
            repo.appendingPathComponent("Benchmarks/GreekLabourLibrary/n_5278_2026_fek_a22.pdf"),
            repo.appendingPathComponent("Benchmarks/GreekLabourLibrary/ya_8934_2026_fek_b1759.pdf"),
        ]
        let libraries = IntentSupport.libraries()
        let engine = RAGService(containerService: libraries)
        for _ in 0..<100 where !engine.hasLoadedDocumentsFromDisk {
            try await Task.sleep(for: .milliseconds(100))
        }
        let container = try libraries.createContainer(name: "Demo PDF compact import \(UUID().uuidString.prefix(8))")
        do {
            let batch = await engine.ingestDocuments(pdfURLs, containerId: container.id)
            #expect(batch.successCount == 2)
            let docs = engine.documents.filter { $0.containerId == container.id }
            #expect(docs.count == 2)
            let db = try await engine.dbForContainer(container.id)
            for doc in docs {
                let stored = try await db.chunks(forDocument: doc.id, limit: nil)
                #expect(!stored.isEmpty, "\(doc.filename): no persisted chunks")
                let expectedKey = doc.filename.contains("5278") ? "LAW:5278/2026" : "MD:8934"
                #expect(stored.contains { $0.legal?.documentStatuteKey == expectedKey }, "\(doc.filename) missing statute key \(expectedKey)")
                #expect(stored.contains { !($0.legal?.sourceTextEl ?? "").isEmpty && GreekLegalEntityMasker.greekLetterRatio($0.content) < 0.3 })
            }
        } catch {
            await cleanupContainer(id: container.id, engine: engine, libraries: libraries)
            throw error
        }
        await cleanupContainer(id: container.id, engine: engine, libraries: libraries)
    }

    /// Full real-ONNX `RAGService.ingestDocuments` over all 5 demo PDFs (~23 minutes in Simulator).
    @MainActor
    @Test(
        "Full 5-PDF end-to-end ingestion",
        .enabled(if: ProcessInfo.processInfo.environment["OI_FULL_PDF_IMPORT"] == "1"),
        .timeLimit(.minutes(45))
    )
    func fullFivePDFEndToEndImport() async throws {
        try #require(LocalNeuralTranslator.isAvailable(.greekToEnglish))
        let repo = GreekEvalCase.repository
        let pdfURLs = Self.demoPDFs.map { repo.appendingPathComponent($0.relativePath) }
        let libraries = IntentSupport.libraries()
        let engine = RAGService(containerService: libraries)
        for _ in 0..<100 where !engine.hasLoadedDocumentsFromDisk {
            try await Task.sleep(for: .milliseconds(100))
        }
        let container = try libraries.createContainer(name: "Demo PDF full import \(UUID().uuidString.prefix(8))")
        do {
            let batch = await engine.ingestDocuments(pdfURLs, containerId: container.id)
            #expect(batch.successCount == Self.demoPDFs.count)
        } catch {
            await cleanupContainer(id: container.id, engine: engine, libraries: libraries)
            throw error
        }
        await cleanupContainer(id: container.id, engine: engine, libraries: libraries)
    }
}
