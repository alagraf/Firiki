//
//  LegalCrossReferences.swift
//  OpenIntelligence
//
//  Thesis fork, plan stage 5 and phase B: the cross-reference code knew pages, tables, figures,
//  sections, chapters, appendices and steps, so neither "Article 22" nor "Άρθρο 22 παρ. 1"
//  resolved. A passage that cites an article now brings in the passage that holds it: the one
//  whose text (English or its Greek source) or section title starts with that article's heading.
//

import Foundation

nonisolated enum LegalCrossReferences {
    /// A line that is an article heading and nothing else: "Άρθρο 1", "Article 1 [Άρθρο 1]".
    private static let headingLineRegex = try? NSRegularExpression(
        pattern: #"^\s*(?:Article|Άρθρο|Αρθρο)\s+(\d{1,4}[\p{L}]?)(?![\p{L}\p{N}])\s*(?:\[[^\]\n]{0,40}\])?\s*$"#,
        options: [.caseInsensitive, .anchorsMatchLines]
    )

    static func isArticleHeading(_ line: String) -> Bool {
        let normalized = GreekLegalEntityMasker.normalizeGreekText(line)
        let ns = normalized as NSString
        return headingLineRegex?.firstMatch(in: normalized, range: NSRange(location: 0, length: ns.length)) != nil
    }

    private static func articleKey(_ number: String) -> String? {
        GreekLegalEntityMasker.canonicalKeys(in: "Article " + number).first { $0.hasPrefix("ART:") }
    }

    /// The articles whose heading is a line of its own in the passage's section title, Greek
    /// source or English text, each with where its heading starts (0 = start of the text, 1 = end).
    /// A table-of-contents line ("Άρθρο 1. Μορφή του πολιτεύματος ..... 19") is not a heading.
    static func articleHeadings(of chunk: DocumentChunk) -> [(article: String, position: Double)] {
        var result: [(article: String, position: Double)] = []
        for text in [chunk.metadata.sectionTitle, chunk.sourceTextEl, chunk.content].compactMap({ $0 }) {
            let normalized = GreekLegalEntityMasker.normalizeGreekText(text)
            let ns = normalized as NSString
            let length = Double(max(1, ns.length))
            for match in headingLineRegex?.matches(in: normalized, range: NSRange(location: 0, length: ns.length)) ?? [] {
                guard let key = articleKey(ns.substring(with: match.range(at: 1))) else { continue }
                let position = Double(match.range.location) / length
                if let index = result.firstIndex(where: { $0.article == key }) {
                    result[index].position = min(result[index].position, position)
                } else {
                    result.append((key, position))
                }
            }
        }
        return result
    }

    /// Every article a passage holds (a passage of the Constitution can hold Articles 1, 2 and 3).
    static func definedArticles(of chunk: DocumentChunk) -> [String] {
        articleHeadings(of: chunk).map(\.article)
    }

    /// Where the heading of one of `articles` starts in the passage, or nil.
    private static func headingPosition(of chunk: DocumentChunk, among articles: Set<String>) -> Double? {
        articleHeadings(of: chunk).filter { articles.contains($0.article) }.map(\.position).min()
    }

    /// The first article a passage holds.
    static func definedArticle(of chunk: DocumentChunk) -> String? {
        definedArticles(of: chunk).first
    }

    /// For a question that names an article ("What does Article 1 say?"), the passages holding
    /// that article come first, ahead of passages that only cite it ("article 86 paragraph 1").
    /// Holders among `candidates` keep their order; when none is there, the holder is taken from
    /// `pool`, from a document the candidates come from if possible. Unchanged when the question
    /// names no article or no passage holds it.
    static func pinningRequestedArticle(
        query: String,
        candidates: [RetrievedChunk],
        pool: [DocumentChunk],
        sourceDocument: (DocumentChunk) -> String
    ) -> [RetrievedChunk] {
        let requested = referencedArticles(in: query)
        guard !requested.isEmpty else { return candidates }
        // The passage whose heading comes earliest holds most of the article: a passage that ends
        // with the heading (a page break before the article's text) comes after one that starts with it.
        let position: (DocumentChunk) -> Double? = { headingPosition(of: $0, among: requested) }
        var holders = candidates.filter { position($0.chunk) != nil }
            .sorted { (position($0.chunk) ?? 1) < (position($1.chunk) ?? 1) }
        if holders.isEmpty {
            let documentOrder = candidates.map(\.chunk.documentId)
            let found = pool.filter { position($0) != nil }.sorted { a, b in
                let ai = documentOrder.firstIndex(of: a.documentId) ?? Int.max
                let bi = documentOrder.firstIndex(of: b.documentId) ?? Int.max
                if ai != bi { return ai < bi }
                return (position(a) ?? 1) < (position(b) ?? 1)
            }
            guard let best = found.first else { return candidates }
            let sameDocument = found.filter { $0.documentId == best.documentId }.prefix(max(2, requested.count))
            holders = sameDocument.map {
                RetrievedChunk(chunk: $0, similarityScore: 0, rank: 1, sourceDocument: sourceDocument($0), pageNumber: $0.metadata.pageNumber)
            }
        }
        // An article's later paragraphs can be in the passages after its heading (a page break, or
        // the overlapping pieces a long passage is cut into): up to four following passages of the
        // same document, up to the next article heading, come along.
        var continued: [RetrievedChunk] = []
        for holder in holders {
            continued.append(holder)
            for offset in 1...4 {
                guard let next = pool.first(where: {
                    $0.documentId == holder.chunk.documentId && $0.metadata.chunkIndex == holder.chunk.metadata.chunkIndex + offset
                }), definedArticles(of: next).isEmpty else { break }
                let existing = candidates.first { $0.chunk.id == next.id }
                continued.append(existing ?? RetrievedChunk(
                    chunk: next, similarityScore: 0, rank: 1, sourceDocument: sourceDocument(next), pageNumber: next.metadata.pageNumber))
            }
        }
        holders = continued
        let topScore = candidates.map(\.similarityScore).max() ?? 0
        let pinned = holders.map {
            RetrievedChunk(
                chunk: $0.chunk, similarityScore: max($0.similarityScore, topScore), rank: 1,
                sourceDocument: $0.sourceDocument, pageNumber: $0.pageNumber
            )
        }
        let pinnedIds = Set(pinned.map(\.chunk.id))
        return pinned + candidates.filter { !pinnedIds.contains($0.chunk.id) }
    }

    /// Article keys ("ART:22") cited in a text.
    static func referencedArticles(in text: String) -> Set<String> {
        GreekLegalEntityMasker.canonicalKeys(in: text).filter { $0.hasPrefix("ART:") }
    }

    /// Passages from `pool` that hold an article cited by the `top` passages or by the query (an
    /// article a top passage itself holds is not followed). Passages in the same document as a
    /// citing passage come first; at most `limit`.
    static func resolve(top: [DocumentChunk], query: String, pool: [DocumentChunk], limit: Int = 3) -> [DocumentChunk] {
        let topIds = Set(top.map(\.id))
        let held = Set(top.flatMap(definedArticles(of:)))
        var wanted = referencedArticles(in: query)
        for chunk in top {
            wanted.formUnion(referencedArticles(in: chunk.content))
            if let legal = chunk.legal { wanted.formUnion(legal.canonicalKeys.filter { $0.hasPrefix("ART:") }) }
        }
        wanted.subtract(held)
        guard !wanted.isEmpty else { return [] }
        let citingDocuments = Set(top.map(\.documentId))
        let candidates = pool.filter { !topIds.contains($0.id) }.compactMap { chunk -> (DocumentChunk, String)? in
            guard let article = definedArticles(of: chunk).first(where: wanted.contains) else { return nil }
            return (chunk, article)
        }
        let ordered = candidates.sorted { a, b in
            let aSame = citingDocuments.contains(a.0.documentId), bSame = citingDocuments.contains(b.0.documentId)
            if aSame != bSame { return aSame }
            return a.0.metadata.chunkIndex < b.0.metadata.chunkIndex
        }
        var seenArticles = Set<String>()
        var result: [DocumentChunk] = []
        for (chunk, article) in ordered where !seenArticles.contains(article) {
            seenArticles.insert(article)
            result.append(chunk)
            if result.count == limit { break }
        }
        return result
    }
}
