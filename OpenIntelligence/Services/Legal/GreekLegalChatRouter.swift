//
//  GreekLegalChatRouter.swift
//  OpenIntelligence
//
//  Thesis fork: recognizes capability requests straight from the chat prompt
//  (statute summary, legal opinion, contract template routing) and executes them directly.
//

import Foundation
import FoundationModels

enum GreekLegalChatIntent: Equatable, Sendable {
    case statuteSummary(documentQuery: String?)
    case legalOpinion(question: String)
    case contractRouting(terms: String)
    case standardQA(query: String)
}

struct ChatCapabilityResult: Sendable {
    let content: String
    let metadata: ResponseMetadata?
    let retrievedChunks: [RetrievedChunk]?
    let structuredAnswer: StructuredAnswer?

    init(
        content: String,
        metadata: ResponseMetadata? = nil,
        retrievedChunks: [RetrievedChunk]? = nil,
        structuredAnswer: StructuredAnswer? = nil
    ) {
        self.content = content
        self.metadata = metadata
        self.retrievedChunks = retrievedChunks
        self.structuredAnswer = structuredAnswer
    }
}

enum GreekLegalChatRouter {
    // MARK: - Recognition Rules

    private static let summaryRegex = try? NSRegularExpression(
        pattern: #"(?i)\b(?:σύνοψ\w*|συνοψ[ίι]\w*|περίληψ\w*|περιληπτ\w*|summar(y|ize|ise)|digest)\b"#)

    private static let opinionRegex = try? NSRegularExpression(
        pattern: #"(?i)\b(?:γνωμοδότησ\w*|γνωμοδοτ\w*|νομική\s+(?:συμβουλή|άποψη|γνώμη)|(?:legal\s+)?opinion|formal\s+memo(?:randum)?)\b"#)

    private static let templateRegex = try? NSRegularExpression(
        pattern: #"(?i)\b(?:(?:υπόδειγμα|υποδείγματα|πρότυπο|πρότυπα)\s+(?:σύμβαση\w*|συμβάσ\w*)|σύμβαση\s+(?:εργασίας\s+)?για|ποιο\s+(?:υπόδειγμα|πρότυπο)|ποια\s+σύμβαση|contract\s+template|which\s+(?:contract\s+)?template|labou?r\s+contract)\b"#)

    /// Decides the capability intent of a chat prompt using program rules first.
    static func detectIntent(_ query: String) -> GreekLegalChatIntent {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let ns = trimmed as NSString
        let range = NSRange(location: 0, length: ns.length)

        // 1. Contract template routing
        if templateRegex?.firstMatch(in: trimmed, range: range) != nil {
            return .contractRouting(terms: trimmed)
        }

        // 2. Legal opinion synthesis
        if opinionRegex?.firstMatch(in: trimmed, range: range) != nil {
            return .legalOpinion(question: trimmed)
        }

        // 3. Statute summary
        if summaryRegex?.firstMatch(in: trimmed, range: range) != nil {
            let docTarget = extractDocumentTarget(from: trimmed)
            return .statuteSummary(documentQuery: docTarget)
        }

        // 4. Fallback to standard QA
        return .standardQA(query: trimmed)
    }

    /// Extracts named statute numbers or filenames from a summary prompt (e.g. «σύνοψη του ν. 5278/2026»).
    static func extractDocumentTarget(from query: String) -> String? {
        let patterns = [
            #"(?i)\b(?:ν\.|νόμ(?:ος|ου))\s*(\d{4}(?:/\d{4})?)\b"#,
            #"(?i)\b(?:π\.?\s*δ\.?|διάταγμ(?:α|ατος))\s*(\d{1,4}(?:/\d{4})?)\b"#,
            #"(?i)\b(?:υ\.?\s*α\.?|απόφασ(?:η|ης))\s*(\d{1,5}(?:/\d{4})?)\b"#,
            #"(?i)\b(?:law|decree|decision)\s*(\d{1,5}(?:/\d{4})?)\b"#,
            #"\b(\d{4}/\d{4})\b"#,
            #"(?<=(?:σύνοψη|περίληψη|summarize|summary)\s+(?:του\s+|της\s+|το\s+|the\s+)?(?:ν\.|νόμου\s+)?)\b(\d{4,5})\b"#
        ]
        let ns = query as NSString
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: query, range: NSRange(location: 0, length: ns.length)) {
                return ns.substring(with: match.range(at: 1))
            }
        }
        return nil
    }

    /// Matches a document in the library by a target query (e.g. "5278", "62/2025", or filename).
    static func matchDocument(target: String?, in documents: [Document]) -> Document? {
        guard let target = target?.lowercased().trimmingCharacters(in: .whitespaces), !target.isEmpty else {
            return nil
        }
        // Match exact or substring in filename
        if let direct = documents.first(where: { $0.filename.lowercased().contains(target) }) {
            return direct
        }
        let cleanTarget = target.replacingOccurrences(of: "/", with: "-")
        if let directClean = documents.first(where: { $0.filename.lowercased().contains(cleanTarget) }) {
            return directClean
        }
        let numberOnly = target.components(separatedBy: CharacterSet.decimalDigits.inverted).first { !$0.isEmpty } ?? ""
        if !numberOnly.isEmpty, let numMatch = documents.first(where: { $0.filename.contains(numberOnly) }) {
            return numMatch
        }
        return nil
    }

    // MARK: - Direct Chat Execution

    static func handleChatQuery(
        _ query: String,
        containerId: UUID,
        ragService: RAGService
    ) async -> ChatCapabilityResult? {
        let intent = detectIntent(query)

        switch intent {
        case .standardQA:
            return nil

        case .statuteSummary(let docTarget):
            do {
                return try await executeStatuteSummary(docTarget: docTarget, query: query, containerId: containerId, ragService: ragService)
            } catch {
                let isGreek = GreekLegalEntityMasker.greekLetterRatio(query) >= 0.3
                return ChatCapabilityResult(
                    content: isGreek
                        ? "Σφάλμα κατά τη σύνοψη του εγγράφου: \(error.localizedDescription)"
                        : "Error summarizing document: \(error.localizedDescription)"
                )
            }

        case .legalOpinion(let question):
            do {
                return try await executeLegalOpinion(question: question, containerId: containerId, ragService: ragService)
            } catch {
                let isGreek = GreekLegalEntityMasker.greekLetterRatio(question) >= 0.3
                return ChatCapabilityResult(
                    content: isGreek
                        ? "Σφάλμα κατά τη σύνταξη γνωμοδότησης: \(error.localizedDescription)"
                        : "Error preparing legal opinion: \(error.localizedDescription)"
                )
            }

        case .contractRouting(let terms):
            return await executeContractRouting(terms: terms)
        }
    }

    // MARK: - Statute Summary Execution

    private static func executeStatuteSummary(
        docTarget: String?,
        query: String,
        containerId: UUID,
        ragService: RAGService
    ) async throws -> ChatCapabilityResult {
        let documents = await MainActor.run { ragService.documentsForContainer(containerId) }

        guard !documents.isEmpty else {
            return ChatCapabilityResult(
                content: "Δεν βρέθηκαν έγγραφα στη βιβλιοθήκη για σύνοψη. Εισαγάγετε ένα νομικό κείμενο ή νόμο στην καρτέλα 'Documents'."
            )
        }

        let chosenDoc: Document?
        if let matched = matchDocument(target: docTarget, in: documents) {
            chosenDoc = matched
        } else if documents.count == 1 {
            chosenDoc = documents.first
        } else {
            chosenDoc = nil
        }

        guard let doc = chosenDoc else {
            let docList = documents.map { "- \($0.filename)" }.joined(separator: "\n")
            return ChatCapabilityResult(
                content: "Υπάρχουν περισσότερα από ένα νομοθετήματα στη βιβλιοθήκη. Ποιο έγγραφο θα θέλατε να συνοψίσω;\n\n\(docList)"
            )
        }

        let database = try await ragService.dbForContainer(containerId)
        let chunks = try await database.chunks(forDocument: doc.id).sorted { $0.metadata.chunkIndex < $1.metadata.chunkIndex }
        guard !chunks.isEmpty else {
            return ChatCapabilityResult(content: "Το έγγραφο '\(doc.filename)' δεν περιέχει αποσπάσματα για σύνοψη.")
        }

        let passages = chunks.map(\.content)
        let statuteKey = chunks.lazy.compactMap { $0.legal?.documentStatuteKey }.first
        let isGreekQuery = GreekLegalEntityMasker.greekLetterRatio(query) >= 0.3

        let summary = try await GreekLegalDocumentSummarizer.summarize(
            passages: passages,
            statuteKey: statuteKey
        )

        let answerText = isGreekQuery ? summary.greek : summary.english
        let retrieved = chunks.prefix(5).enumerated().map { index, chunk in
            RetrievedChunk(chunk: chunk, similarityScore: 1.0, rank: index + 1, sourceDocument: doc.filename)
        }

        return ChatCapabilityResult(
            content: "### Σύνοψη: \(doc.filename)\n\n" + answerText,
            metadata: ResponseMetadata(
                totalGenerationTime: 0,
                tokensGenerated: 0,
                modelUsed: "AFM 3 Core (Map-Reduce Summarizer)",
                retrievalTime: 0,
                originalQuery: query
            ),
            retrievedChunks: retrieved
        )
    }

    // MARK: - Legal Opinion Execution

    private static func executeLegalOpinion(
        question: String,
        containerId: UUID,
        ragService: RAGService
    ) async throws -> ChatCapabilityResult {
        let isGreekQuery = GreekLegalEntityMasker.greekLetterRatio(question) >= 0.3
        let opinion = try await ragService.greekLegalOpinion(question: question, containerId: containerId)

        if let refusal = opinion.refusal {
            return ChatCapabilityResult(
                content: isGreekQuery
                    ? "Δεν κατέστη δυνατή η έκδοση γνωμοδότησης: \(refusal)."
                    : "Unable to synthesize legal opinion: \(refusal)."
            )
        }

        let answerText = isGreekQuery ? opinion.greek : opinion.english
        let retrieved = opinion.sources.flatMap(\.passages)

        return ChatCapabilityResult(
            content: answerText,
            metadata: ResponseMetadata(
                totalGenerationTime: 0,
                tokensGenerated: 0,
                modelUsed: "AFM 3 Core (Cross-Statute Legal Opinion)",
                retrievalTime: 0,
                originalQuery: question
            ),
            retrievedChunks: retrieved
        )
    }

    // MARK: - Contract Template Routing Execution

    private static func executeContractRouting(terms: String) async -> ChatCapabilityResult {
        let isGreek = GreekLegalEntityMasker.greekLetterRatio(terms) >= 0.3
        let decision = await LabourContractTemplateRouter.route(terms)

        guard let template = decision.template else {
            let msg = isGreek
                ? "Δεν βρέθηκε κατάλληλο πρότυπο σύμβασης εργασίας για το αίτημά σας."
                : "No matching labour contract template was found for your request. \(decision.reason)"
            return ChatCapabilityResult(content: msg)
        }

        let methodBadge = decision.method == .model ? "AFM 3 On-Device Model" : "Keyword Rule"
        let articlesText = template.articles.isEmpty ? "" : "\n\n**Εφαρμοστέες διατάξεις:** " + template.articles.joined(separator: ", ")

        let content: String
        if isGreek {
            content = """
            ### Προτεινόμενο Υπόδειγμα: \(template.titleEl)
            *Μέθοδος επιλογής: \(methodBadge)*

            **Αιτιολόγηση:** \(LabourContractTemplateRouter.greekReason(for: template))
            \(articlesText)

            ---

            \(LabourContractTemplateRouter.displayedBody(template))
            """
        } else {
            content = """
            ### Recommended Template: \(template.titleEn)
            *Routing method: \(methodBadge)*

            **Reason:** \(decision.reason)
            \(articlesText)

            ---

            \(LabourContractTemplateRouter.displayedBody(template))
            """
        }

        return ChatCapabilityResult(
            content: content,
            metadata: ResponseMetadata(
                totalGenerationTime: 0,
                tokensGenerated: 0,
                modelUsed: "AFM 3 (Labour Contract Router)",
                retrievalTime: 0,
                originalQuery: terms
            )
        )
    }
}
