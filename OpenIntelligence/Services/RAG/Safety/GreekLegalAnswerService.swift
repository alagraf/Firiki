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
//  - out-of-scope questions are refused: one about another country's law that no passage
//    names before generation, and one whose draft opens by saying the passages don't answer it;
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

    /// The question as the user wrote it (in Greek), while the pipeline runs on its translation.
    @TaskLocal static var originalQuestion: String?

    /// Collects the model asset ids `LLMService` reports while a Greek legal question is answered.
    @TaskLocal static var assetRecorder: ModelAssetRecorder?

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

/// The model asset ids of the generations in one answer (on device vs Private Cloud Compute).
nonisolated final class ModelAssetRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var ids: [String] = []

    func record(_ assetIDs: [String]) {
        lock.lock(); defer { lock.unlock() }
        for id in assetIDs where !ids.contains(id) { ids.append(id) }
    }

    var assetIDs: [String] {
        lock.lock(); defer { lock.unlock() }
        return ids
    }
}

/// What the Greek legal review decided, for the response details and the thesis evaluation.
nonisolated struct LegalAnswerReview: Codable, Sendable, Equatable {
    /// One gate's outcome, as shown under Response Details.
    struct GateLine: Codable, Sendable, Equatable {
        let gate: String
        let passed: Bool
        let confidence: Float
        let details: String
    }

    let englishDraft: String
    let abstained: Bool
    let reason: String?
    let overallConfidence: Float
    let gates: [GateLine]
    let modelUsed: String
    /// The question as the gates read it (its English translation).
    var queryEn: String = ""
    var assetIDs: [String] = []

    /// One line per gate, for the log.
    var gateSummary: [String] {
        gates.map { "\($0.passed ? "PASS" : "FAIL") \($0.gate): \($0.details)" }
    }
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
        if let country = unsupportedForeignJurisdiction(query: query, chunks: chunks) {
            return "the question is about \(country), which no passage mentions"
        }
        if let statute = unsupportedNamedStatute(query: query, chunks: chunks) {
            return "the question names \(statute), which no passage comes from or cites"
        }
        return nil
    }

    /// A statute the question names ("Article 16 of the Constitution", "Law 4808/2021", "Ministerial
    /// Decision 8934") that no passage comes from or cites, or nil when one of them does. Applies
    /// only when some passage records its document's statute (`documentStatuteKey`, imports since
    /// 2.11.25): without it, a passage of the named law that doesn't cite its own number can't be
    /// told from one of another law.
    static func unsupportedNamedStatute(query: String, chunks: [RetrievedChunk]) -> String? {
        guard chunks.contains(where: { $0.chunk.legal?.documentStatuteKey != nil }) else { return nil }
        let requested = requestedStatutes(query)
        guard !requested.isEmpty else { return nil }
        let supported = chunks.contains { retrieved in
            let chunk = retrieved.chunk
            if requested.contains("CONST"),
               chunk.legal?.documentStatuteKey == "CONST" || namesConstitution(chunk.content + " " + (chunk.sourceTextEl ?? "")) {
                return true
            }
            let cited = LegalVerificationPolicy.statuteKeys(of: chunk)
                .union(LegalVerificationPolicy.evidenceKeys([retrieved]).filter { $0.hasPrefix("MD:") })
            return cited.contains { key in requested.contains { LegalVerificationPolicy.sameStatute(key, $0) } }
        }
        return supported ? nil : requested.sorted().first.map(statuteName)
    }

    /// The statutes a question names: laws, decrees and decisions by number, and the Constitution.
    static func requestedStatutes(_ query: String) -> Set<String> {
        var requested = GreekLegalEntityMasker.canonicalKeys(in: query)
            .filter { $0.hasPrefix("LAW:") || $0.hasPrefix("PD:") || $0.hasPrefix("MD:") }
        if namesConstitution(query) { requested.insert("CONST") }
        return requested
    }

    /// The documents a question is searched in when it names a statute that is one of the
    /// library's documents (`documentStatuteKey` of each document): "… according to Law
    /// 5278/2026" is answered from Law 5278/2026, not from the other laws whose passages are
    /// closest to its words. Nil when the question names no statute or none of them is a document;
    /// a named statute that is not a document is left to `unsupportedNamedStatute`.
    static func statuteScope(query: String, documentKeys: [UUID: String]) -> Set<UUID>? {
        let requested = requestedStatutes(query)
        guard !requested.isEmpty else { return nil }
        let scope = Set(documentKeys.filter { _, key in requested.contains { LegalVerificationPolicy.sameStatute(key, $0) } }.keys)
        return scope.isEmpty ? nil : scope
    }

    /// "Constitution" or "Σύνταγμα(τος)" as a word; "constitutional" doesn't count.
    static func namesConstitution(_ text: String) -> Bool {
        text.range(of: #"\bconstitution\b"#, options: [.regularExpression, .caseInsensitive]) != nil
            || SQLiteFullTextService.greekSearchFold(text).range(of: #"\bσυνταγμα(?:τοσ)?\b"#, options: .regularExpression) != nil
    }

    /// A statute key as the model and the reader see it: "Law 5278/2026", "the Constitution".
    static func statuteName(_ key: String) -> String {
        if key == "CONST" { return "the Constitution" }
        let names = ["LAW:": "Law ", "PD:": "Presidential Decree ", "MD:": "Ministerial Decision "]
        for (prefix, name) in names where key.hasPrefix(prefix) { return name + key.dropFirst(prefix.count) }
        return key
    }

    // MARK: Out-of-scope questions

    /// A country other than Greece that the question asks about ("… in Germany", "the law of
    /// France") and that no passage names, or nil. The library holds Greek law, so its passages
    /// can't answer for another country, however close their topic is.
    static func unsupportedForeignJurisdiction(query: String, chunks: [RetrievedChunk]) -> String? {
        let lower = query.lowercased()
        for country in foreignCountries {
            let name = NSRegularExpression.escapedPattern(for: country.english.lowercased())
            // An inquiry asking about a worker's or individual's nationality/origin (e.g. "worker from Albania",
            // "employee from Albania", "εργαζόμενος από την Αλβανία") asks about Greek law applying to a foreign
            // national, not about the foreign country's legal jurisdiction.
            let workerOriginEn = #"\b(?:worker|employee|person|national|citizen|individual|someone|anyone|immigrant|refugee|origin)\s+from\s+(?:the\s+)?"# + name + #"\b"#
            if lower.range(of: workerOriginEn, options: .regularExpression) != nil {
                continue
            }
            if let stem = country.greekStem {
                let workerOriginEl = #"\b(?:εργαζόμεν|μισθωτ|πρόσωπ|πολίτ|υπήκο|αλλοδαπ)\w*\s+από\s+(?:τη[νς]?\s+|το[υς]?\s+|τω[ν]?\s+)?"# + stem
                if lower.range(of: workerOriginEl, options: .regularExpression) != nil {
                    continue
                }
            }
            let asked = #"\b(?:in|of|from|under|for|to)\s+(?:the\s+)?"# + name + #"\b"#
            guard lower.range(of: asked, options: .regularExpression) != nil else { continue }
            let named = chunks.contains { retrieved in
                if retrieved.chunk.content.lowercased().range(of: #"\b"# + name + #"\b"#, options: .regularExpression) != nil {
                    return true
                }
                guard let stem = country.greekStem, let source = retrieved.chunk.sourceTextEl else { return false }
                return SQLiteFullTextService.greekSearchFold(source).contains(stem)
            }
            if !named { return country.english }
        }
        return nil
    }

    private struct Country {
        let english: String
        /// The folded Greek name without its ending ("γερμαν" for Γερμανία, Γερμανίας), nil when
        /// it would be too short to be specific.
        let greekStem: String?
    }

    /// Every ISO country but Greece, named in English and Greek by the system locale data, plus
    /// a few common English names the region list doesn't use.
    private static let foreignCountries: [Country] = {
        let english = Locale(identifier: "en_US")
        let greek = Locale(identifier: "el_GR")
        var countries: [Country] = Locale.Region.isoRegions.compactMap { region in
            let code = region.identifier
            guard code.count == 2, code.allSatisfy(\.isLetter), code != "GR",
                  let name = english.localizedString(forRegionCode: code) else { return nil }
            let folded = greek.localizedString(forRegionCode: code).map(SQLiteFullTextService.greekSearchFold)
            let stem = folded.flatMap { $0.count >= 6 && !$0.contains(" ") ? String($0.dropLast(2)) : nil }
            return Country(english: name, greekStem: stem)
        }
        countries += ["England", "Turkey", "Holland", "America"].map { Country(english: $0, greekStem: nil) }
        return countries
    }()

    /// The draft's opening sentence says the passages don't answer the question ("The excerpts do
    /// not specify …", "Insufficient evidence …") without qualifying it in the same sentence ("…,
    /// but …"). What follows is then padding from loosely related passages, not an answer.
    static func declaresMissingEvidence(_ draft: String) -> Bool {
        let body = draft.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }
            .joined(separator: " ")
            .replacingOccurrences(of: "**", with: "")
            .trimmingCharacters(in: CharacterSet.letters.inverted)
        guard !body.isEmpty else { return false }
        let opening = body.range(of: #"[.!?](\s|$)"#, options: .regularExpression)
            .map { String(body[..<$0.lowerBound]) } ?? body
        let qualified = opening.range(of: #"\b(but|however|although|though|yet|except)\b"#, options: [.regularExpression, .caseInsensitive]) != nil
        return !qualified && opening.range(of: missingEvidenceOpening, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static let missingEvidenceOpening = #"^(?:there (?:is|are) )?(?:insufficient evidence|not enough (?:evidence|information)|no (?:information|mention|details?|data) (?:is |are )?(?:provided |given |available )?(?:about|on|regarding|concerning|for|of)|(?:the |these |provided )?(?:documents?|excerpts?|sources?|text|passages?|context)(?: provided)? (?:does|do) not (?:directly |explicitly |specifically )?(?:specify|mention|contain|provide|state|address|include|cover|give|discuss|indicate|define|say)|(?:i|we) (?:cannot|can't|could not|couldn't) (?:find|answer|determine))"#

    /// The pipeline's own failure and not-found texts, which must never be translated and shown
    /// as an answer.
    static let pipelineFailureMarkers = [
        "unable to synthesize answer", "couldn't find relevant information", "could not find relevant information",
        "i couldn't find", "i could not find", "no relevant information",
    ]

    static func isPipelineFailureText(_ text: String) -> Bool {
        let lower = text.lowercased()
        return pipelineFailureMarkers.contains { lower.contains($0) }
    }

    /// A content word (4+ letters, excluding generic question words) or a legal identifier of the query appears in the passage.
    static func hasOverlap(query: String, chunk: DocumentChunk) -> Bool {
        let queryKeys = GreekLegalEntityMasker.canonicalKeys(in: query)
        let chunkKeys = LegalVerificationPolicy.evidenceKeys([RetrievedChunk(chunk: chunk, similarityScore: 0, rank: 0)])
        if !queryKeys.isDisjoint(with: chunkKeys) { return true }
        let chunkWords = Set((chunk.content + " " + (chunk.sourceTextEl ?? "")).lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { !$0.isEmpty })
        let words = query.lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { $0.count >= 4 && !genericQuestionWords.contains($0) }
        return words.contains { chunkWords.contains($0) }
    }

    /// Words of a labour-law question that don't tell its topic apart (every passage of the library
    /// is about work, employees and the Code).
    private static let genericQuestionWords: Set<String> = [
        "what", "which", "when", "where", "does", "about", "under", "with", "from", "that", "this", "there", "have",
        "must", "shall", "according", "work", "works", "working", "worker", "workers", "employee", "employees",
        "employer", "employers", "employment", "code", "article", "articles", "paragraph", "law", "laws", "provision",
        "provisions", "month", "months", "year", "years", "days", "much", "many", "long", "case", "cases",
    ]

    /// The draft without its sentences that state a figure and share no topic word with the
    /// question, or nil when there is none. The model sometimes ends a correct answer with an
    /// unrelated passage's figure ("Six (6) months after childbirth … the working father is protected
    /// from dismissal" under a question about harassment, labour dev case 46): gate C then refused
    /// the whole answer. A figure on the question's own topic is never dropped here.
    static func droppingOffTopicFigures(from draft: String, query: String) -> String? {
        let topic = Set(query.lowercased().components(separatedBy: CharacterSet.letters.inverted)
            .filter { $0.count >= 4 && !genericQuestionWords.contains($0) })
        guard !topic.isEmpty else { return nil }
        func isOffTopicFigure(_ sentence: String) -> Bool {
            guard !NumericValueExtractor.mentions(inAnswer: sentence).filter(NumericValueExtractor.isCountedByGate).isEmpty else { return false }
            let words = sentence.lowercased().components(separatedBy: CharacterSet.letters.inverted)
            // A topic word or a longer form of it ("harass" in "harassment") ties the sentence to the question.
            return !words.contains { word in word.count >= 4 && topic.contains { word.hasPrefix($0) || $0.hasPrefix(word) } }
        }
        var dropped = false
        var lines: [String] = []
        for line in draft.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") || trimmed.isEmpty {
                lines.append(line)
                continue
            }
            let sentences = LocalNeuralTranslator.segments(trimmed)
            let kept = sentences.filter { !isOffTopicFigure($0) }
            if kept.count == sentences.count {
                lines.append(line)
                continue
            }
            dropped = true
            // A list item that loses every sentence goes; otherwise it keeps its marker.
            let marker = trimmed.range(of: #"^(?:[-•*]\s+|\d{1,2}[.)]\s+)"#, options: .regularExpression).map { String(trimmed[$0]) } ?? ""
            let rest = kept.joined(separator: " ")
            guard !rest.isEmpty else { continue }
            lines.append(kept.first?.hasPrefix(marker) == true ? rest : marker + rest)
        }
        guard dropped else { return nil }
        let result = lines.joined(separator: "\n")
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // What remains must still answer: a cited sentence that isn't a heading.
        let body = result.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }.joined(separator: " ")
        guard body.contains("[S"), body.split(whereSeparator: \.isWhitespace).count >= 12 else { return nil }
        return result
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
        translate: (String, [LegalEntityRecord]) async throws -> String,
        assetIDs: [String] = []
    ) async -> (response: RAGResponse, review: LegalAnswerReview) {
        var draft = response.generatedResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        let chunks = response.retrievedChunks
        var reason: String?
        var confidence: Float = 0
        var gates: [LegalAnswerReview.GateLine] = []

        if response.metadata.modelUsed == "none" || response.metadata.tokensGenerated == 0 && chunks.isEmpty {
            reason = "the pipeline answered without generating (\(response.metadata.gatingDecision ?? "no evidence"))"
        } else if draft.isEmpty {
            reason = "empty draft"
        } else if response.structuredAnswer?.refuse == true || isPipelineFailureText(draft) {
            reason = "the pipeline returned a refusal or failure text instead of an answer"
        } else if declaresMissingEvidence(draft) {
            reason = "the draft says the passages don't answer the question"
        } else if let preReason = preGenerationAbstentionReason(query: queryEn, chunks: chunks) {
            reason = preReason
        } else {
            var result = await verify(draft, queryEn, chunks)
            // Gate C alone failed: drop off-topic sentences with figures and check the rest again.
            let critical: Set<VerificationGate> = [.retrievalConfidence, .numericSanity, .semanticGrounding, .statutoryIsolation, .quoteFaithfulness]
            let failed = Set(result.gateResults.filter { !$0.passed && critical.contains($0.gate) }.map(\.gate))
            if result.shouldAbstain, failed == [.numericSanity],
               let trimmed = droppingOffTopicFigures(from: draft, query: queryEn) {
                let retried = await verify(trimmed, queryEn, chunks)
                if !retried.shouldAbstain, retried.overallConfidence >= minimumCompositeConfidence {
                    Log.info("[GreekLegal] Dropped off-topic sentences with unsupported figures; the rest passes the gates", category: .retrieval)
                    draft = trimmed
                    result = retried
                }
            }
            confidence = result.overallConfidence
            gates = result.gateResults.map {
                LegalAnswerReview.GateLine(gate: $0.gate.rawValue, passed: $0.passed, confidence: $0.confidence, details: $0.details)
            }
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
            overallConfidence: confidence, gates: gates, modelUsed: response.metadata.modelUsed,
            queryEn: queryEn, assetIDs: assetIDs
        )
        var metadata = response.metadata
        metadata.legalReview = review
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
            metadata: metadata,
            confidenceScore: reason == nil ? confidence : 0,
            qualityWarnings: warnings,
            structuredAnswer: nil,
            legalReview: review
        )
        return (reviewed, review)
    }
}
