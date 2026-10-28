//
//  GreekLegalAnswerService.swift
//  OpenIntelligence
//
//  Thesis fork, plan phases C–F, for a question asked in Greek:
//  - the answer is generated in English as plain text (no @Generable schema, which made Apple's
//    guardrails refuse labour-law topics such as dismissal during pregnancy), at temperature 0.2
//    at most, and is not streamed to the screen;
//  - weak evidence is refused before generation, and the reliability-mode fallbacks (a second
//    generation attempt, raw passages as the answer) are off;
//  - when the pipeline returns, gates A–I run on the English draft in every quality mode
//    (Standard, Deep Think and Maximum alike), and a draft that fails a critical gate or scores
//    below the composite threshold is replaced by a fixed Greek abstention message;
//  - a verified draft is translated to Greek on device, legal identifiers and [C#] markers kept.
//
//  `RAGService.query` sets `GreekLegalAnswerContext.isActive` for the whole query, so every path
//  inside it (including the agentic Deep Think and Maximum paths) sees the same switch.
//

import Foundation

nonisolated enum GreekLegalAnswerContext {
    /// True while a Greek legal question is being answered.
    @TaskLocal static var isActive = false

    static let maxTemperature: Float = 0.2

    /// UserDefaults key; absent means on.
    static let strictLegalAbstentionDefaultsKey = "thesis.strictLegalAbstention"

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: strictLegalAbstentionDefaultsKey) as? Bool ?? true
    }

    /// Whether `question` is answered in Greek legal mode: the mode is on and the question is
    /// written in Greek.
    static func applies(to question: String, defaults: UserDefaults = .standard) -> Bool {
        isEnabled(defaults: defaults) && GreekLegalEntityMasker.greekLetterRatio(question) >= 0.3
    }
}

/// What the Greek legal review decided, for the response details and the thesis evaluation.
nonisolated struct LegalAnswerReview: Sendable, Equatable {
    let englishDraft: String
    let abstained: Bool
    let reason: String?
    let overallConfidence: Float
    let gateSummary: [String]
    let modelUsed: String
}

nonisolated enum GreekLegalAnswerFinalizer {
    /// Composite gate confidence below which a draft is not shown.
    static let minimumCompositeConfidence: Float = 0.5

    /// Why the question should not reach the model, or nil: no passages, top passage score under
    /// 0.20, or under 0.30 with no word and no legal identifier of the question in it.
    static func preGenerationAbstentionReason(query: String, chunks: [RetrievedChunk]) -> String? {
        guard let top = chunks.max(by: { $0.similarityScore < $1.similarityScore }) else {
            return "no passages retrieved"
        }
        if top.similarityScore < LegalVerificationPolicy.minimumTopScore {
            return String(format: "top passage score %.2f < %.2f", top.similarityScore, LegalVerificationPolicy.minimumTopScore)
        }
        if top.similarityScore < LegalVerificationPolicy.minimumTopScoreWithoutOverlap,
           !hasOverlap(query: query, chunk: top.chunk) {
            return String(format: "top passage score %.2f < %.2f with no overlap", top.similarityScore, LegalVerificationPolicy.minimumTopScoreWithoutOverlap)
        }
        return nil
    }

    /// A content word (4+ letters) or a legal identifier of the query appears in the passage.
    static func hasOverlap(query: String, chunk: DocumentChunk) -> Bool {
        let queryKeys = GreekLegalEntityMasker.canonicalKeys(in: query)
        let chunkKeys = LegalVerificationPolicy.evidenceKeys([RetrievedChunk(chunk: chunk, similarityScore: 0, rank: 0)])
        if !queryKeys.isDisjoint(with: chunkKeys) { return true }
        let text = (chunk.content + " " + (chunk.sourceTextEl ?? "")).lowercased()
        let words = query.lowercased().components(separatedBy: CharacterSet.letters.inverted).filter { $0.count >= 4 }
        return words.contains { text.contains($0) }
    }

    /// The reviewed response: the Greek translation of a verified draft, or the Greek abstention.
    /// - Parameters:
    ///   - question: the Greek question.
    ///   - queryEn: its English translation (the gates compare the English draft with English text).
    ///   - verify: runs gates A–I on the draft.
    ///   - translate: English draft → Greek.
    static func review(
        question: String,
        queryEn: String,
        response: RAGResponse,
        verify: (String, String, [RetrievedChunk]) async -> RAGVerificationResult,
        translate: (String, [LegalEntityRecord]) async throws -> String
    ) async -> (response: RAGResponse, review: LegalAnswerReview) {
        let draft = response.generatedResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        let chunks = response.retrievedChunks
        var reason: String?
        var confidence: Float = 0
        var summary: [String] = []

        if response.metadata.modelUsed == "none" || response.metadata.tokensGenerated == 0 && chunks.isEmpty {
            reason = "the pipeline answered without generating (\(response.metadata.gatingDecision ?? "no evidence"))"
        } else if draft.isEmpty {
            reason = "empty draft"
        } else if let preReason = preGenerationAbstentionReason(query: queryEn, chunks: chunks) {
            reason = preReason
        } else {
            let result = await verify(draft, queryEn, chunks)
            confidence = result.overallConfidence
            summary = result.gateResults.map { "\($0.passed ? "PASS" : "FAIL") \($0.gate.rawValue): \($0.details)" }
            if result.shouldAbstain {
                reason = result.abstainReason ?? "critical gate failed"
            } else if result.overallConfidence < minimumCompositeConfidence {
                reason = String(format: "composite confidence %.2f < %.2f", result.overallConfidence, minimumCompositeConfidence)
            }
        }

        var finalText: String
        if let reason {
            Log.warning("[GreekLegal] Abstained: \(reason)", category: .retrieval)
            finalText = LegalVerificationPolicy.greekAbstentionMessage
        } else {
            let entities = chunks.flatMap { $0.chunk.legal?.legalEntities ?? [] }
            do {
                finalText = try await translate(draft, entities)
            } catch {
                // An untranslated English answer is still verified; say so rather than hide it.
                Log.warning("[GreekLegal] Answer translation failed: \(error.localizedDescription)", category: .retrieval)
                finalText = draft
            }
        }

        let review = LegalAnswerReview(
            englishDraft: draft, abstained: reason != nil, reason: reason,
            overallConfidence: confidence, gateSummary: summary, modelUsed: response.metadata.modelUsed
        )
        Log.info(
            "[GreekLegal] Review: abstained=\(review.abstained) confidence=\(String(format: "%.2f", confidence)) model=\(review.modelUsed)",
            category: .retrieval
        )
        var warnings = response.qualityWarnings
        if let reason { warnings.append("Greek legal mode: abstained (\(reason))") }
        let reviewed = RAGResponse(
            id: response.id,
            queryId: response.queryId,
            retrievedChunks: chunks,
            generatedResponse: finalText,
            metadata: response.metadata,
            confidenceScore: reason == nil ? confidence : 0,
            qualityWarnings: warnings,
            structuredAnswer: nil,
            legalReview: review
        )
        return (reviewed, review)
    }
}
