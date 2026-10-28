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
    /// Article heading at the start of a text: "Article 66", "Άρθρο 66", "ΑΡΘΡΟ 66Α".
    private static let headingRegex = try? NSRegularExpression(
        pattern: #"^\s*(?:Article|Άρθρο|Αρθρο)\s+(\d{1,4}[\p{L}]?)(?![\p{L}\p{N}])"#,
        options: [.caseInsensitive]
    )

    /// The article a passage holds, from its section title, Greek source or English text.
    static func definedArticle(of chunk: DocumentChunk) -> String? {
        for text in [chunk.metadata.sectionTitle, chunk.sourceTextEl, chunk.content].compactMap({ $0 }) {
            let normalized = GreekLegalEntityMasker.normalizeGreekText(text)
            let ns = normalized as NSString
            guard let match = headingRegex?.firstMatch(in: normalized, range: NSRange(location: 0, length: ns.length)) else { continue }
            let key = GreekLegalEntityMasker.canonicalKeys(in: "Article " + ns.substring(with: match.range(at: 1)))
            if let article = key.first(where: { $0.hasPrefix("ART:") }) { return article }
        }
        return nil
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
        let held = Set(top.compactMap(definedArticle(of:)))
        var wanted = referencedArticles(in: query)
        for chunk in top {
            wanted.formUnion(referencedArticles(in: chunk.content))
            if let legal = chunk.legal { wanted.formUnion(legal.canonicalKeys.filter { $0.hasPrefix("ART:") }) }
        }
        wanted.subtract(held)
        guard !wanted.isEmpty else { return [] }
        let citingDocuments = Set(top.map(\.documentId))
        let candidates = pool.filter { !topIds.contains($0.id) }.compactMap { chunk -> (DocumentChunk, String)? in
            guard let article = definedArticle(of: chunk), wanted.contains(article) else { return nil }
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
