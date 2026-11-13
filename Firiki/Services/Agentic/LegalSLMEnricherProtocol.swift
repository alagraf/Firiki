//
//  LegalSLMEnricherProtocol.swift
//  Firiki
//
//  Thesis fork, plan phase C.2: the boundary for the supervisor's small-language-model experiment.
//  An enricher (a <1B legal SLM, Speculative-RAG style) reads the question and the passages chosen
//  for the answer and returns an evidence brief that is put in front of the context Apple's model
//  reads, within a token budget. With no enricher registered the pipeline is unchanged, so
//  baseline AFM and SLM + AFM can be compared in benchmarks without editing `RAGService`.
//

import Foundation

protocol LegalSLMEnricherProtocol: Sendable {
    /// Shown in the brief's label and the log ("legal-slm-0.5b").
    var name: String { get }

    /// A brief for `query` from `passages`, at most `tokenBudget` tokens, or nil to add nothing.
    func draft(query: String, passages: [DocumentChunk], tokenBudget: Int) async -> String?

    /// The passages in the order the enricher prefers (retrieval re-scoring). Not called by the
    /// pipeline yet; the default keeps the order.
    func rescore(query: String, passages: [RetrievedChunk]) async -> [RetrievedChunk]
}

extension LegalSLMEnricherProtocol {
    func rescore(query: String, passages: [RetrievedChunk]) async -> [RetrievedChunk] { passages }
}

nonisolated enum LegalSLMEnricherRegistry {
    /// The enricher in use; nil (the default) is the AFM-only baseline.
    nonisolated(unsafe) static var current: (any LegalSLMEnricherProtocol)?

    /// Largest brief, in tokens, so the device's context window (4,096 tokens on device) keeps room
    /// for the passages and the answer.
    static let maxBriefTokens = 300

    /// `context` with the enricher's brief in front, or unchanged.
    static func enrich(context: String?, query: String, passages: [DocumentChunk]) async -> String? {
        guard let enricher = current, let context, !context.isEmpty else { return context }
        guard let brief = await enricher.draft(query: query, passages: passages, tokenBudget: maxBriefTokens),
              !brief.isEmpty
        else { return context }
        let limited = String(brief.prefix(maxBriefTokens * 4))
        Log.info("[SLMEnricher] \(enricher.name) added a \(limited.count)-character brief", category: .llm)
        return "[Evidence brief from \(enricher.name)]\n\(limited)\n\n\(context)"
    }
}
