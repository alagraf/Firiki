//
//  GreekLegalOpinionWriter.swift
//  OpenIntelligence
//
//  Thesis fork (PoC capability 3): a structured Greek legal opinion drawn from several documents
//  of a library. Passages are retrieved from each document separately (top passages of each, not
//  top-k overall), and the documents that match best are kept. Where a later law amends or adds
//  an article of the Labour Code, the opinion says so (read from the amending article's heading,
//  not from the model). Each document's section is drafted in its own model call, so each prompt
//  fits the on-device window; a conclusion is written from the sections. Every sentence is checked
//  against the passages (gate C figures, gate F articles and statutes) and dropped if
//  unsupported; the opinion is refused only when its conclusion has no supported sentence. The
//  English text is translated to Greek with the citation-preserving path.
//

import Foundation

nonisolated enum GreekLegalOpinionWriter {
    /// One document's passages for the opinion.
    struct Source: Sendable {
        let document: String
        /// The document's statute (`documentStatuteKey`), nil when its title page names none.
        let statuteKey: String?
        let passages: [RetrievedChunk]

        var name: String {
            guard let statuteKey else { return document }
            return statuteKey == labourCodeKey ? "the Labour Code (Presidential Decree 62/2025)" : GreekLegalAnswerFinalizer.statuteName(statuteKey)
        }

        var bestScore: Float { passages.map(\.similarityScore).max() ?? 0 }
    }

    /// A later law's change to an article of the Labour Code ("Article 7 of Law 5239/2025 amends
    /// Article 194"), or a decision issued under one ("under Article 141Α").
    struct CodeLink: Equatable, Sendable {
        enum Kind: String, Sendable { case amends, adds, appliesUnder }
        let statuteKey: String
        /// The amending article ("7"), nil for a decision.
        let article: String?
        let kind: Kind
        /// The Code's article ("194", "578Α").
        let codeArticle: String
    }

    struct Opinion: Sendable {
        /// The opinion in Greek; English sections where translation failed.
        let greek: String
        let english: String
        let sources: [Source]
        let links: [CodeLink]
        /// Sentences removed because a figure, article or statute was unsupported.
        let dropped: [String]
        /// Nil when written; the reason when refused (no supported conclusion).
        let refusal: String?
    }

    /// The Labour Code's statute key: the base text the other documents amend or apply.
    static let labourCodeKey = "PD:62/2025"
    /// Sources an opinion draws on, and passages per source.
    static let maxSources = 3
    static let passagesPerSource = 3
    /// A document is kept when its best passage scores at least this share of the best document's.
    static let relativeScore: Float = 0.6

    static let disclaimerGreek = "Η γνωμοδότηση αυτή συντάχθηκε αυτόματα από εφαρμογή επίδειξης (proof of concept) με βάση μόνο τα έγγραφα της βιβλιοθήκης. Δεν αποτελεί νομική συμβουλή και πρέπει να ελεγχθεί από δικηγόρο."

    // MARK: Sources

    /// The documents an opinion draws on: those whose best passage scores at least `relativeScore`
    /// of the best one's, at most `maxSources`; the Labour Code joins when a kept document amends
    /// or applies it. Each keeps its `passagesPerSource` best passages.
    static func selectSources(_ candidates: [Source], links: [CodeLink]) -> [Source] {
        let ranked = candidates.filter { !$0.passages.isEmpty }.sorted { $0.bestScore > $1.bestScore }
        guard let top = ranked.first?.bestScore else { return [] }
        var kept = Array(ranked.filter { $0.bestScore >= top * relativeScore }.prefix(maxSources))
        let keptKeys = Set(kept.compactMap(\.statuteKey))
        if !keptKeys.contains(labourCodeKey),
           links.contains(where: { keptKeys.contains($0.statuteKey) }),
           let code = ranked.first(where: { $0.statuteKey == labourCodeKey }) {
            if kept.count == maxSources { kept.removeLast() }
            kept.append(code)
        }
        return kept.map { Source(document: $0.document, statuteKey: $0.statuteKey, passages: Array($0.passages.prefix(passagesPerSource))) }
    }

    // MARK: Links to the Labour Code

    private static let amendment = try? NSRegularExpression(
        pattern: #"(τροποποιηση|αντικατασταση|προσθηκη)[^«»]{0,80}?αρθρου\s+(\d{1,4}[α-ω]?)\s+(?:στον\s+)?κωδικα\s+εργατικου"#)
    private static let issuedUnder = try? NSRegularExpression(
        pattern: #"αρθρ(?:ο|ου)\s+(\d{1,4}[α-ω]?)\s+του\s+(?:κωδικα\s+εργατικου\s+δικαιου|π\.\s?δ\.\s?62/2025)"#)

    /// "141α" as the Code writes it: "141Α".
    private static func codeArticle(_ folded: String) -> String {
        folded.uppercased()
    }

    /// The Code articles a document's passages amend or add (from each article's heading, "Άρθρο
    /// 7 Χρονικά όρια εργασίας - Τροποποίηση παρ. 2 και 3 άρθρου 194 Κώδικα Εργατικού Δικαίου"),
    /// and for a decision (no articles) the Code article it is issued under, the one its passages
    /// cite most.
    static func codeLinks(statuteKey: String?, passages: [DocumentChunk]) -> [CodeLink] {
        guard let statuteKey, statuteKey != labourCodeKey else { return [] }
        var links: [CodeLink] = []
        if statuteKey.hasPrefix("MD:") {
            var counts: [String: Int] = [:]
            for passage in passages {
                let folded = SQLiteFullTextService.greekSearchFold(passage.sourceTextEl ?? passage.content)
                let ns = folded as NSString
                for match in issuedUnder?.matches(in: folded, range: NSRange(location: 0, length: ns.length)) ?? [] {
                    counts[ns.substring(with: match.range(at: 1)), default: 0] += 1
                }
            }
            if let most = counts.max(by: { $0.value == $1.value ? $0.key > $1.key : $0.value < $1.value }) {
                links.append(CodeLink(statuteKey: statuteKey, article: nil, kind: .appliesUnder, codeArticle: codeArticle(most.key)))
            }
            return links
        }
        for passage in passages {
            guard let article = LegalCrossReferences.definedArticle(of: passage) else { continue }
            let folded = SQLiteFullTextService.greekSearchFold(String((passage.sourceTextEl ?? passage.content).prefix(500)))
            let ns = folded as NSString
            guard let match = amendment?.firstMatch(in: folded, range: NSRange(location: 0, length: ns.length)) else { continue }
            let link = CodeLink(
                statuteKey: statuteKey, article: String(article.dropFirst("ART:".count)),
                kind: ns.substring(with: match.range(at: 1)) == "προσθηκη" ? .adds : .amends,
                codeArticle: codeArticle(ns.substring(with: match.range(at: 2))))
            if !links.contains(link) { links.append(link) }
        }
        return links
    }

    /// "141Α" and "141A" alike: the Code's letter suffixes are Greek capitals that look Latin.
    static func sameArticle(_ first: String, _ second: String) -> Bool {
        func normal(_ text: String) -> String {
            text.uppercased().replacingOccurrences(of: "Α", with: "A").replacingOccurrences(of: "Β", with: "B")
                .replacingOccurrences(of: "ART:", with: "")
        }
        return normal(first) == normal(second)
    }

    /// The article each passage of a document belongs to: the last article heading at or before
    /// it, in chunk order ("194" for the passages after "Άρθρο 194" up to the next heading).
    static func enclosingArticles(_ chunks: [DocumentChunk]) -> [UUID: String] {
        var result: [UUID: String] = [:]
        var current: String?
        for chunk in chunks.sorted(by: { $0.metadata.chunkIndex < $1.metadata.chunkIndex }) {
            if let article = LegalCrossReferences.definedArticles(of: chunk).last { current = String(article.dropFirst("ART:".count)) }
            if let current { result[chunk.id] = current }
        }
        return result
    }

    /// The later law prevails in what the model reads, not only in what the opinion says: a
    /// retrieved passage of a Labour Code article that a document of the library amends or adds
    /// is replaced by the amending article's passages (its heading passage and the one after it),
    /// with the Code passage's score, in that document's source. Dev opinion 3 stated Article 402
    /// of the Code as Law 5278/2026 had replaced it ("only the basic wage and some allowances
    /// continue"), because the amending Article 8 was not among the law's best passages.
    /// `documents` holds every document's passages in chunk order, by file name.
    static func replacingAmendedCodePassages(_ sources: [Source], links: [CodeLink], documents: [String: [DocumentChunk]]) -> [Source] {
        guard let code = sources.first(where: { $0.statuteKey == labourCodeKey }), let codeChunks = documents[code.document] else { return sources }
        let changes = links.filter { $0.kind != .appliesUnder }
        guard !changes.isEmpty else { return sources }
        let articleOf = enclosingArticles(codeChunks)
        var kept: [RetrievedChunk] = []
        var added: [String: [RetrievedChunk]] = [:]
        for passage in code.passages {
            guard let article = articleOf[passage.chunk.id],
                  let link = changes.first(where: { sameArticle($0.codeArticle, article) }),
                  let amending = sources.first(where: { $0.statuteKey == link.statuteKey }),
                  let lawChunks = documents[amending.document]?.sorted(by: { $0.metadata.chunkIndex < $1.metadata.chunkIndex }),
                  let start = lawChunks.firstIndex(where: { chunk in LegalCrossReferences.definedArticle(of: chunk).map { sameArticle($0, link.article ?? "") } ?? false })
            else {
                kept.append(passage)
                continue
            }
            for chunk in lawChunks[start..<min(lawChunks.count, start + 2)] where !(added[amending.document] ?? []).contains(where: { $0.chunk.id == chunk.id }) {
                added[amending.document, default: []].append(RetrievedChunk(
                    chunk: chunk, similarityScore: passage.similarityScore, rank: 1, sourceDocument: amending.document, pageNumber: chunk.metadata.pageNumber))
            }
        }
        return sources.map { source in
            if source.document == code.document { return Source(document: source.document, statuteKey: source.statuteKey, passages: kept) }
            guard let extra = added[source.document] else { return source }
            let ids = Set(extra.map(\.chunk.id))
            return Source(document: source.document, statuteKey: source.statuteKey, passages: extra + source.passages.filter { !ids.contains($0.chunk.id) })
        }
    }

    /// The "how they combine" sentences, written from the links (no model call).
    static func combination(_ links: [CodeLink]) -> [String] {
        links.map { link in
            let statute = GreekLegalAnswerFinalizer.statuteName(link.statuteKey)
            switch link.kind {
            case .amends:
                return "Article \(link.article ?? "") of \(statute) amended Article \(link.codeArticle) of the Labour Code; the amended text applies, as the later law."
            case .adds:
                return "Article \(link.article ?? "") of \(statute) added Article \(link.codeArticle) to the Labour Code."
            case .appliesUnder:
                return "\(statute) was issued under Article \(link.codeArticle) of the Labour Code and applies it."
            }
        }
    }

    // MARK: Model calls

    /// The section call's instructions for one statute.
    static func sectionInstructions(statute: String) -> String {
        """
        You help a Greek lawyer write a legal opinion. Use only the passages given, which come from \(statute). In two to four sentences, state what they provide on the question: the rules, their figures and time limits, and who they apply to. Cite each rule as (Article N of \(statute)), with N from the passage's "Article N" heading. If the passages do not address the question, write only: Not addressed.
        """
    }

    /// A section without the sentences that say something is not addressed (the model wrote "Not
    /// addressed: …" between rules, dev opinion 3).
    static func cleanedSection(_ text: String) -> String {
        LocalNeuralTranslator.segments(text)
            .filter { !$0.lowercased().contains("not addressed") && !$0.lowercased().hasPrefix("the passages do not") }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The conclusion's first paragraph, without a heading, at most three sentences: the model
    /// repeated it in two more paragraphs under "**Conclusion**" (dev opinion 3).
    static func cleanedConclusion(_ text: String) -> String {
        let paragraphs = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { line in
                let bare = line.trimmingCharacters(in: CharacterSet(charactersIn: "*#: "))
                return !line.isEmpty && bare.lowercased() != "conclusion"
            }
        guard let first = paragraphs.first else { return "" }
        let body = first.hasPrefix("**Conclusion") || first.lowercased().hasPrefix("conclusion:")
            ? String(first.drop { $0 != ":" }.dropFirst()).trimmingCharacters(in: CharacterSet(charactersIn: "* ")) : first
        return cleanedSection(LocalNeuralTranslator.segments(body).prefix(3).joined(separator: " "))
    }

    static let conclusionInstructions = """
        You write the conclusion of a Greek legal opinion. Use only the sections given. In two or three sentences, answer the question directly, citing the articles the sections cite. Where a later law amended an article of the Labour Code, apply the amended rule. Do not add advice or anything the sections don't say.
        """

    static func sectionPrompt(question: String, source: Source) -> String {
        let passages = source.passages.enumerated().map { "[\($0 + 1)] \($1.chunk.content)" }.joined(separator: "\n\n")
        return "Question: \(question)\nStatute: \(source.name)\n\nPassages:\n\(passages)"
    }

    // MARK: Writing

    static func write(
        question: String,
        questionEn: String,
        sources: [Source],
        links: [CodeLink],
        respond: (_ instructions: String, _ prompt: String) async throws -> String = { try await GreekLegalDocumentSummarizer.onDeviceResponse(instructions: $0, prompt: $1) },
        translate: (String) async throws -> String = { try await LocalNeuralTranslator.shared.translateEnglishToGreekPreservingCitations($0) }
    ) async throws -> Opinion {
        let passages = sources.flatMap { $0.passages.map(\.chunk.content) }
        let statuteKeys = sources.compactMap(\.statuteKey) + [labourCodeKey]
        let combined = combination(links)
        // The articles the links name are cited by the passages' headings ("Τροποποίηση ... άρθρου 194").
        let linked = links.map { "ART:" + $0.codeArticle.uppercased() } + links.compactMap { $0.article.map { "ART:" + $0 } }
        func checked(_ text: String) -> (text: String, dropped: [String]) {
            GreekLegalDocumentSummarizer.droppingUnsupported(
                text, passages: passages + combined, articles: [], statuteKeys: statuteKeys, alsoSupported: Set(linked))
        }

        var dropped: [String] = []
        var sections: [(source: Source, text: String)] = []
        for source in sources {
            let draft = try await respond(sectionInstructions(statute: source.name), sectionPrompt(question: questionEn, source: source))
            let trimmed = cleanedSection(draft)
            guard !trimmed.isEmpty else { continue }
            let result = checked(trimmed)
            dropped += result.dropped
            if !result.text.isEmpty { sections.append((source, result.text)) }
        }
        let sectionText = sections.map { "\($0.source.name):\n\($0.text)" }.joined(separator: "\n\n")
        // A link is stated when its document has a section that cites the amending article (a
        // decision's link: any section of it); links of documents that didn't address the question
        // stay out (dev opinion 1 listed Law 5278's mediation articles).
        let usedLinks = links.filter { link in
            sections.contains { section in
                section.source.statuteKey == link.statuteKey
                    && (link.article.map { section.text.range(of: #"\bArticle\s+\#($0)\b"#, options: .regularExpression) != nil } ?? true)
            }
        }
        let usedCombination = combination(usedLinks)
        var conclusion = ""
        if !sections.isEmpty {
            let prompt = "Question: \(questionEn)\n\n" + sectionText + (usedCombination.isEmpty ? "" : "\n\nHow they combine:\n" + usedCombination.joined(separator: "\n"))
            let result = checked(cleanedConclusion(try await respond(conclusionInstructions, prompt)))
            dropped += result.dropped
            conclusion = result.text
        }
        if conclusion.isEmpty {
            return Opinion(greek: "", english: "", sources: sources, links: links, dropped: dropped,
                           refusal: sections.isEmpty ? "no document of the library addresses the question" : "the conclusion had no supported sentence")
        }

        let applicable = sources.filter { source in sections.contains { $0.source.document == source.document } }
        let lawSources = applicable.map { source -> String in
            let articles = source.passages.compactMap { LegalCrossReferences.definedArticle(of: $0.chunk) }
                .map { String($0.dropFirst("ART:".count)) }
            let unique = articles.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            return source.name + (unique.isEmpty ? "" : ", Article " + unique.joined(separator: ", Article "))
        }
        let lawText = lawSources.joined(separator: "; ") + (lawSources.isEmpty ? "" : ".")
        let englishParts: [(title: String, text: String)] = [
            ("Applicable law", lawText),
            ("What each provides", sections.map(\.text).joined(separator: "\n\n")),
            ("How they combine", usedCombination.joined(separator: " ")),
            ("Conclusion", conclusion),
        ].filter { !$0.text.isEmpty }
        let english = (["Question: " + questionEn] + englishParts.map { "\($0.title):\n\($0.text)" }).joined(separator: "\n\n")

        let greekTitles = ["Applicable law": "Εφαρμοστέο δίκαιο", "What each provides": "Τι προβλέπει κάθε κείμενο",
                           "How they combine": "Πώς συνδυάζονται", "Conclusion": "Συμπέρασμα"]
        var greekParts = ["Ερώτημα\n" + question]
        for part in englishParts {
            let text = (try? await translate(part.text)) ?? part.text
            greekParts.append((greekTitles[part.title] ?? part.title) + "\n" + text)
        }
        greekParts.append("Σημείωση\n" + disclaimerGreek)
        return Opinion(greek: greekParts.joined(separator: "\n\n"), english: english, sources: sources, links: usedLinks,
                       dropped: dropped, refusal: nil)
    }
}

// MARK: - Retrieval

extension RAGService {
    /// Thesis fork (PoC capability 3): an opinion on a Greek question from the documents of a
    /// library. Each document is searched on its own (`RAGQueryScope`), with the English
    /// translation of the question.
    func greekLegalOpinion(question: String, containerId: UUID) async throws -> GreekLegalOpinionWriter.Opinion {
        typealias Writer = GreekLegalOpinionWriter
        let questionEn = await Self.greekQueryTranslation(question) ?? question
        let documents = await MainActor.run { self.documentsForContainer(containerId) }
        let database = try await dbForContainer(containerId)
        // Every document's passages, for its statute and the Code articles it amends (from all its
        // articles' headings, not only the retrieved ones).
        var allPassages: [String: [DocumentChunk]] = [:]
        var links: [Writer.CodeLink] = []
        var candidates: [Writer.Source] = []
        for document in documents {
            let chunks = try await database.chunks(forDocument: document.id).sorted { $0.metadata.chunkIndex < $1.metadata.chunkIndex }
            let statuteKey = chunks.lazy.compactMap { $0.legal?.documentStatuteKey }.first
            allPassages[document.filename] = chunks
            links += Writer.codeLinks(statuteKey: statuteKey, passages: chunks)
            let passages = try await RAGQueryScope.$documentIds.withValue([document.id]) {
                try await self.searchDocumentsRaw(query: questionEn, topK: 8, containerId: containerId)
            }
            // Ranked by score; the title page and contents state no rule (`droppingFrontMatter`).
            let ranked = LegalCrossReferences.droppingFrontMatter(passages, pool: chunks).sorted { $0.similarityScore > $1.similarityScore }
            candidates.append(.init(document: document.filename, statuteKey: statuteKey, passages: ranked))
        }
        // The Code's passages are cut to its best before the amended ones are replaced.
        candidates = candidates.map { .init(document: $0.document, statuteKey: $0.statuteKey, passages: Array($0.passages.prefix(Writer.passagesPerSource))) }
        candidates = Writer.replacingAmendedCodePassages(candidates, links: links, documents: allPassages)
        let sources = Writer.selectSources(candidates, links: links)
        let keptLinks = links.filter { link in
            sources.contains { source in
                source.statuteKey == link.statuteKey && (link.article == nil || source.passages.contains { passage in
                    LegalCrossReferences.definedArticle(of: passage.chunk).map { Writer.sameArticle($0, link.article ?? "") } ?? false
                })
            }
        }
        Log.info("[LegalOpinion] Sources: \(sources.map { "\($0.document) \(String(format: "%.2f", $0.bestScore)) \($0.passages.compactMap { LegalCrossReferences.definedArticle(of: $0.chunk) })" }); links: \(Writer.combination(keptLinks))", category: .retrieval)
        return try await Writer.write(question: question, questionEn: questionEn, sources: sources, links: keptLinks)
    }
}
