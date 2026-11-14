//
//  GreekLegalEndToEndFakeTests.swift
//  FirikiTests
//
//  Phase 2b (POC_PROGRESS.md, flow 3): end-to-end Greek legal Q&A over a small fixture library
//  using a stand-in `LLMService`, real Opus-MT ingestion/translation, real hybrid retrieval, and
//  verification gates A–I. Does not require Apple Intelligence.
//

import Foundation
import Testing

@testable import Firiki

private final class GreekFakeLLMService: LLMService {
    var toolHandler: RAGToolHandler?
    var isAvailable: Bool { true }
    var modelName: String { "Fake-Greek-Legal-LLM" }

    private let respond: (String, String?) -> String

    init(respond: @escaping (String, String?) -> String) {
        self.respond = respond
    }

    func generate(prompt: String, context: String?, config: InferenceConfig) async throws -> LLMResponse {
        let text = respond(prompt, context)
        return LLMResponse(
            text: text,
            tokensGenerated: text.split(separator: " ").count,
            timeToFirstToken: 0.01,
            totalTime: 0.01,
            modelName: modelName,
            toolCallsMade: 0
        )
    }
}

@Suite("Greek legal Q&A end-to-end with stand-in model", .serialized)
@MainActor
struct GreekLegalEndToEndFakeTests {
    /// Compact synthetic Greek statute whose articles share clear statutory anchors and numbers.
    private static let fixtureText = """
        ΕΦΗΜΕΡΙΔΑ ΤΗΣ ΚΥΒΕΡΝΗΣΕΩΣ
        ΝΟΜΟΣ ΥΠ' ΑΡΙΘΜ. 5278
        1 Φεβρουαρίου 2026

        Άρθρο 5
        Άδεια πατρότητας
        1. Κάθε εργαζόμενος πατέρας δικαιούται άδεια πατρότητας δεκατεσσάρων (14) εργάσιμων ημερών με αποδοχές κατά τη γέννηση τέκνου.
        2. Η άδεια λαμβάνεται συνεχόμενα ή τμηματικά εντός τριάντα (30) ημερών από τον τοκετό.

        Άρθρο 9
        Ετήσια άδεια αναψυχής
        1. Ο εργαζόμενος δικαιούται ετήσια άδεια αναψυχής τουλάχιστον είκοσι (20) εργάσιμων ημερών ετησίως.
        """

    private func ingestFixture(llm: any LLMService) async throws -> (engine: RAGService, libraries: ContainerService, libraryId: UUID, tempURL: URL) {
        try #require(LocalNeuralTranslator.isAvailable(.greekToEnglish) && LocalNeuralTranslator.isAvailable(.englishToGreek))
        let libraries = IntentSupport.libraries()
        let engine = RAGService(llmService: llm, containerService: libraries)
        for _ in 0..<100 where !engine.hasLoadedDocumentsFromDisk {
            try await Task.sleep(for: .milliseconds(100))
        }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("greek-e2e-fixture-\(UUID().uuidString.prefix(8)).txt")
        try Self.fixtureText.write(to: tempURL, atomically: true, encoding: .utf8)

        let container = try libraries.createContainer(name: "Greek e2e fixture \(UUID().uuidString.prefix(8))")
        let imported = await engine.ingestDocuments([tempURL], containerId: container.id)
        try #require(imported.successCount == 1)
        return (engine, libraries, container.id, tempURL)
    }

    private func cleanup(engine: RAGService, libraries: ContainerService, libraryId: UUID, tempURL: URL) async {
        for document in engine.documents where document.containerId == libraryId {
            try? await engine.removeDocument(document)
        }
        libraries.deleteContainer(id: libraryId)
        try? FileManager.default.removeItem(at: tempURL)
    }

    private func withFixture(
        llm: any LLMService,
        body: (RAGService, UUID) async throws -> Void
    ) async throws {
        let (engine, libraries, libraryId, tempURL) = try await ingestFixture(llm: llm)
        do {
            try await body(engine, libraryId)
        } catch {
            await cleanup(engine: engine, libraries: libraries, libraryId: libraryId, tempURL: tempURL)
            throw error
        }
        await cleanup(engine: engine, libraries: libraries, libraryId: libraryId, tempURL: tempURL)
    }

    @Test func greekQuestionReturnsGreekAnswerWithArticleCitation() async throws {
        let fake = GreekFakeLLMService { _, _ in
            "Under Article 5 of Law 5278/2026, a working father is entitled to 14 working days of paid paternity leave upon the birth of a child [S1]."
        }
        try await withFixture(llm: fake) { engine, libraryId in
            let response = try await engine.query(
                "Πόσες ημέρες άδεια πατρότητας δικαιούται ο εργαζόμενος σύμφωνα με το άρθρο 5 του ν. 5278/2026;",
                topK: 3,
                containerId: libraryId,
                qualityModeOverride: .standard
            )

            #expect(response.metadata.legalReview?.abstained == false, "reason=\(response.metadata.legalReview?.reason ?? "-")")
            #expect(GreekLegalEntityMasker.greekLetterRatio(response.generatedResponse) >= 0.3, "\(response.generatedResponse)")
            #expect(GreekLegalEntityMasker.canonicalKeys(in: response.generatedResponse).contains("ART:5"), "\(response.generatedResponse)")
            #expect(response.generatedResponse.contains("14"), "\(response.generatedResponse)")
            #expect(response.retrievedChunks.contains { $0.chunk.legal?.documentStatuteKey == "LAW:5278/2026" })
        }
    }

    @Test func questionAboutMissingLawReturnsFixedGreekRefusal() async throws {
        let fake = GreekFakeLLMService { _, _ in
            "Under Article 10 of Law 9999/2026, severance is doubled [S1]."
        }
        try await withFixture(llm: fake) { engine, libraryId in
            let response = try await engine.query(
                "Τι προβλέπει το άρθρο 10 του ν. 9999/2026 για την αποζημίωση;",
                topK: 3,
                containerId: libraryId,
                qualityModeOverride: .standard
            )

            #expect(response.metadata.legalReview?.abstained == true)
            #expect(response.generatedResponse == LegalVerificationPolicy.greekAbstentionMessage)
        }
    }

    @Test func questionWithUnsupportedNumberAbstainsInGreek() async throws {
        let fake = GreekFakeLLMService { _, _ in
            "Under Article 5 of Law 5278/2026, a working father receives 99 working days of paternity leave across 7 months [S1]."
        }
        try await withFixture(llm: fake) { engine, libraryId in
            let refused = try await engine.query(
                "Πόσες ημέρες άδεια πατρότητας δικαιούται ο εργαζόμενος σύμφωνα με το άρθρο 5 του ν. 5278/2026;",
                topK: 3,
                containerId: libraryId,
                qualityModeOverride: .standard
            )
            #expect(refused.metadata.legalReview?.abstained == true)
            #expect(refused.generatedResponse == LegalVerificationPolicy.greekAbstentionMessage)
            let gatingDecision = try #require(refused.metadata.gatingDecision)
            #expect(gatingDecision.contains(VerificationGate.numericSanity.rawValue), "decision=\(gatingDecision)")
        }
    }

    @Test func answerCitingWrongStatuteAbstainsInGreek() async throws {
        let fake = GreekFakeLLMService { _, _ in
            "Under Article 5 of Law 5239/2025, paternity leave is 14 working days [S1]."
        }
        try await withFixture(llm: fake) { engine, libraryId in
            let refused = try await engine.query(
                "Πόσες ημέρες άδεια πατρότητας δικαιούται ο εργαζόμενος σύμφωνα με το άρθρο 5 του ν. 5278/2026;",
                topK: 3,
                containerId: libraryId,
                qualityModeOverride: .standard
            )
            #expect(refused.metadata.legalReview?.abstained == true)
            #expect(refused.generatedResponse == LegalVerificationPolicy.greekAbstentionMessage)
            let gatingDecision = try #require(refused.metadata.gatingDecision)
            #expect(
                gatingDecision.contains(VerificationGate.quoteFaithfulness.rawValue)
                    || gatingDecision.contains(VerificationGate.statutoryIsolation.rawValue),
                "decision=\(gatingDecision)"
            )
        }
    }
}
