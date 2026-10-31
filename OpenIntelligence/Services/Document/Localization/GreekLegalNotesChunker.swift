//
//  GreekLegalNotesChunker.swift
//  OpenIntelligence
//
//  Thesis fork: structure-aware chunking for Lawyer's Notes, Legal Memos, and Legal Opinions.
//  Cuts along memo section headings (Facts, Question, Analysis, Conclusion, numbered points).
//  Article references inside paragraphs are treated as citations and NOT cut points.
//

import Foundation

nonisolated enum GreekLegalNotesChunker {
    struct Passage: Sendable {
        let text: String
        let header: String?
        let sectionPath: [String]
        let range: Range<String.Index>
    }

    private static let memoHeadingKeywords: [String] = [
        "ΙΣΤΟΡΙΚΟ", "ΠΡΑΓΜΑΤΙΚΑ ΠΕΡΙΣΤΑΤΙΚΑ", "Ιστορικό", "Πραγματικά Περιστατικά",
        "ΕΡΩΤΗΜΑ", "ΝΟΜΙΚΟ ΕΡΩΤΗΜΑ", "ΤΙΘΕΜΕΝΑ ΖΗΤΗΜΑΤΑ", "Ερώτημα", "Νομικό Ερώτημα",
        "ΕΦΑΡΜΟΣΤΕΟ ΔΙΚΑΙΟ", "ΝΟΜΙΚΟ ΠΛΑΙΣΙΟ", "ΣΧΕΤΙΚΕΣ ΔΙΑΤΑΞΕΙΣ", "Εφαρμοστέο Δίκαιο", "Νομικό Πλαίσιο",
        "ΝΟΜΙΚΗ ΥΠΑΓΩΓΗ", "ΝΟΜΙΚΗ ΑΝΑΛΥΣΗ", "ΑΞΙΟΛΟΓΗΣΗ", "Νομική Υπαγωγή", "Νομική Ανάλυση",
        "ΣΥΜΠΕΡΑΣΜΑ", "ΓΝΩΜΟΔΟΤΗΣΗ", "ΚΑΤΑΚΛΕΙΔΑ", "Συμπέρασμα", "Γνωμοδότηση", "Κατακλείδα",
        "FACTS", "BACKGROUND", "Facts", "Background",
        "LEGAL QUESTION", "QUESTION PRESENTED", "ISSUES", "Question", "Issues",
        "APPLICABLE LAW", "LEGAL FRAMEWORK", "Applicable Law", "Legal Framework",
        "LEGAL ANALYSIS", "ANALYSIS", "DISCUSSION", "Analysis", "Discussion",
        "CONCLUSION", "LEGAL OPINION", "MEMORANDUM", "Conclusion", "Legal Opinion", "Memorandum"
    ]

    private static let romanOrNumberedHeading = try? NSRegularExpression(
        pattern: #"^(?:[I|V|X]+\.|\d{1,2}\.|\b[Α-ΩA-Z]\.)\s+[A-Z\p{Lu}][\p{L}\p{N}\s]{2,60}$"#)

    static func isMemoHeading(_ line: String) -> (isHeading: Bool, title: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (false, "") }

        for kw in memoHeadingKeywords {
            if trimmed == kw || trimmed == "\(kw):" || trimmed.hasPrefix("\(kw) -") || trimmed.hasPrefix("\(kw)—") {
                return (true, kw)
            }
        }

        let ns = trimmed as NSString
        let range = NSRange(location: 0, length: ns.length)
        if romanOrNumberedHeading?.firstMatch(in: trimmed, range: range) != nil {
            return (true, trimmed)
        }

        return (false, "")
    }

    /// Extracts passages from a lawyer's notes or legal memorandum document.
    static func passages(in text: String, maxWords: Int = 200, minWords: Int = 40) -> [Passage] {
        var rawLines: [(line: String, range: Range<String.Index>)] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.byLines, .substringNotRequired]) { _, range, _, _ in
            rawLines.append((String(text[range]), range))
        }
        guard !rawLines.isEmpty else { return [] }

        struct SectionBlock {
            let header: String?
            var paragraphs: [(text: String, range: Range<String.Index>)] = []
        }

        var sections: [SectionBlock] = []
        var currentSection = SectionBlock(header: nil, paragraphs: [])

        for (line, range) in rawLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            let (isHeading, headingTitle) = isMemoHeading(trimmed)
            if isHeading {
                if !currentSection.paragraphs.isEmpty || currentSection.header != nil {
                    sections.append(currentSection)
                }
                currentSection = SectionBlock(header: headingTitle, paragraphs: [])
            } else {
                currentSection.paragraphs.append((trimmed, range))
            }
        }
        if !currentSection.paragraphs.isEmpty || currentSection.header != nil {
            sections.append(currentSection)
        }

        guard !sections.isEmpty else {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return [Passage(text: trimmed, header: nil, sectionPath: [], range: text.startIndex..<text.endIndex)]
        }

        var passages: [Passage] = []

        for section in sections {
            let headerText = section.header
            let headerWords = headerText.map(wordCount) ?? 0
            let budget = max(minWords, maxWords - headerWords)

            // Group paragraphs within this section into passages
            var currentGroup: [(text: String, range: Range<String.Index>)] = []
            var currentWords = 0

            func flushGroup() {
                guard let first = currentGroup.first, let last = currentGroup.last else { return }
                let body = currentGroup.map(\.text).joined(separator: "\n\n")
                let fullText = headerText.map { "**\($0)**\n\n\(body)" } ?? body
                let range = first.range.lowerBound..<last.range.upperBound
                let path = headerText.map { [$0] } ?? []
                passages.append(Passage(
                    text: fullText,
                    header: headerText,
                    sectionPath: path,
                    range: range
                ))
                currentGroup = []
                currentWords = 0
            }

            for p in section.paragraphs {
                let pWords = wordCount(p.text)
                if pWords > budget {
                    // Split long paragraph
                    flushGroup()
                    let parts = GreekLegalStructureChunker.split(p.text, maxWords: budget)
                    for (idx, part) in parts.enumerated() {
                        let subHeader = idx == 0 ? headerText : (headerText.map { "\($0) (συνέχεια)" } ?? nil)
                        let fullText = subHeader.map { "**\($0)**\n\n\(part)" } ?? part
                        let path = headerText.map { [$0] } ?? []
                        passages.append(Passage(
                            text: fullText,
                            header: headerText,
                            sectionPath: path,
                            range: p.range
                        ))
                    }
                } else {
                    if currentWords + pWords > budget && !currentGroup.isEmpty {
                        flushGroup()
                    }
                    currentGroup.append(p)
                    currentWords += pWords
                }
            }
            flushGroup()
        }

        return passages
    }

    /// Splits a passage if it exceeds the model's token limit, repeating the header on each part.
    static func pieces(of passage: Passage, fitting fits: (String) -> Bool) -> [String] {
        guard !fits(passage.text) else { return [passage.text] }
        let headerPrefix = passage.header.map { "**\($0)**\n\n" } ?? ""
        let body: String
        if let h = passage.header, passage.text.hasPrefix("**\(h)**\n\n") {
            body = String(passage.text.dropFirst("**\(h)**\n\n".count))
        } else {
            body = passage.text
        }
        var words = max(8, body.split(whereSeparator: { $0.isWhitespace }).count / 2)
        while true {
            let parts = GreekLegalStructureChunker.split(body, maxWords: words).map { part in
                "\(headerPrefix)\(part)"
            }
            if parts.allSatisfy(fits) || words <= 8 { return parts }
            words = max(8, words * 2 / 3)
        }
    }

    private static func wordCount(_ str: String) -> Int {
        str.split(whereSeparator: { $0.isWhitespace }).count
    }
}
