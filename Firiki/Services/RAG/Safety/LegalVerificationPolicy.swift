//
//  LegalVerificationPolicy.swift
//  Firiki
//
//  Thesis fork, plan phases C and E: the legal checks the verification gates and the answer path
//  share. Greek labour-law questions get the stricter thresholds (gate A 0.55, source-only 0.88);
//  gate C reads Greek number and date formats; gate F requires every statutory identifier in an
//  answer to appear in the passages it was drawn from; gate I refuses an answer built only on a
//  statute other than the one the question names; a refused answer is replaced by one fixed Greek
//  abstention message.
//

import Foundation

nonisolated enum LegalVerificationPolicy {
    /// Shown instead of an answer the gates reject or the retrieval can't support.
    static let greekAbstentionMessage = "Δεν βρέθηκαν επαρκή και επαληθευμένα στοιχεία στα έγγραφα της βιβλιοθήκης για να απαντηθεί με ασφάλεια αυτή η ερώτηση. Παρακαλώ ελέγξτε τις σχετικές διατάξεις ή διατυπώστε την ερώτηση διαφορετικά."

    static let englishAbstentionMessage = "The library's documents don't contain enough verified evidence to answer this question safely. Please check the relevant provisions or rephrase the question."

    /// Below this top passage score the question is not answered at all (no model call).
    static let minimumTopScore: Float = 0.20
    /// Below this, with no word or identifier of the question in the top passage.
    static let minimumTopScoreWithoutOverlap: Float = 0.30

    /// Labour-law terms, English words and Greek stems.
    static let labourLawTerms: [String] = [
        "legal", "law", "labor", "labour", "employment", "employer", "employee", "worker", "dismissal",
        "pregnant", "pregnancy", "maternity", "severance", "overtime", "statute", "article", "decree",
        "contract", "wage", "salary", "leave", "termination",
        "εργασ", "εργαζ", "εργοδ", "απόλυσ", "απολυ", "καταγγελ", "αποζημίωσ", "άδει", "υπερωρ",
        "μισθ", "σύμβασ", "νόμ", "άρθρ", "εγκυ", "κύησ", "μητρότητ", "διάταξ",
    ]

    /// Whether a question is about (labour) law: a statutory identifier, or a legal term as a
    /// whole English word ("illegal" doesn't count) or as a Greek stem.
    static func isLegalQuery(_ query: String) -> Bool {
        // A person's name is not a legal identifier.
        if GreekLegalEntityMasker.extractEntities(from: query).contains(where: { $0.type != .properName && $0.type != .legalTerm }) { return true }
        let lower = GreekLegalEntityMasker.normalizeGreekText(query).lowercased()
        let words = Set(lower.components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty })
        for term in labourLawTerms {
            if GreekLegalEntityMasker.containsGreek(term) {
                if words.contains(where: { $0.hasPrefix(term) }) { return true }
            } else if words.contains(term) {
                return true
            }
        }
        return false
    }

    // MARK: Gate C

    /// Greek number and date formats in a form the numeric gate reads: "19.06.2021" →
    /// "19/06/2021", "1.200,50" → "1200.50", and in Greek text "12,5" → "12.5".
    static func normalizeGreekNumerals(_ text: String) -> String {
        var s = text
        s = s.replacingOccurrences(of: #"(?<![\d.,])(\d{1,2})\.(\d{1,2})\.(\d{4})(?![\d])"#, with: "$1/$2/$3", options: .regularExpression)
        // Thousands with dots, optional decimal comma.
        if let regex = try? NSRegularExpression(pattern: #"(?<![\d.,])\d{1,3}(?:\.\d{3})+(?:,\d+)?(?![\d.,]*\d)"#) {
            let ns = s as NSString
            var output = ""
            var cursor = 0
            for match in regex.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
                output += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                output += ns.substring(with: match.range).replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
                cursor = match.range.location + match.range.length
            }
            output += ns.substring(from: cursor)
            s = output
        }
        if GreekLegalEntityMasker.containsGreek(s) {
            s = s.replacingOccurrences(of: #"(?<![\d.,])(\d+),(\d{1,2})(?![\d,])"#, with: "$1.$2", options: .regularExpression)
        }
        return s
    }

    /// The text with the value of every number it writes in words, from 2 to 999, added after the
    /// words in parentheses: "twenty-five" → "twenty-five (25)", "διακοσίους" → "διακοσίους (200)",
    /// "εικοστό πέμπτο" → "εικοστό πέμπτο (25)". Statutes write numbers in words ("δεν μπορεί να
    /// είναι μικρότερος από διακόσιους"), so an answer's "200" was unverified against them (gate C
    /// abstained on "25" for the Constitution's "εικοστό πέμπτο", run 8). Used on evidence only: a
    /// number the answer writes in words is not counted by gate C. "One"/"ένα" are left alone.
    static func annotatingSpelledNumbers(_ text: String) -> String {
        let ns = text as NSString
        guard let wordRegex = try? NSRegularExpression(pattern: #"\p{L}+"#) else { return text }
        let tokens = wordRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { match in
            (range: match.range, word: SpelledNumber.fold(ns.substring(with: match.range)))
        }
        guard tokens.contains(where: { SpelledNumber.isNumberWord($0.word) }) else { return text }
        var insertions: [(location: Int, value: Int)] = []
        var index = 0
        while index < tokens.count {
            // Words of one number are joined by a space or a hyphen only.
            var run: [String] = [tokens[index].word]
            var end = index
            while end + 1 < tokens.count {
                let gapStart = tokens[end].range.location + tokens[end].range.length
                let gap = ns.substring(with: NSRange(location: gapStart, length: tokens[end + 1].range.location - gapStart))
                guard gap.count <= 2, gap.allSatisfy({ $0 == " " || $0 == "-" || $0 == "\u{2010}" }) else { break }
                run.append(tokens[end + 1].word)
                end += 1
            }
            if let (value, used) = SpelledNumber.parse(Array(run.prefix(6))), used > 0 {
                let last = tokens[index + used - 1].range
                if value > 1 { insertions.append((last.location + last.length, value)) }
                index += used
            } else {
                index += 1
            }
        }
        var result = text
        for insertion in insertions.reversed() {
            let position = String.Index(utf16Offset: insertion.location, in: result)
            result.insert(contentsOf: " (\(insertion.value))", at: position)
        }
        return result
    }

    // MARK: Gate F

    /// Canonical keys of every identifier the passages contain: stored metadata, the English
    /// text with its anchors, and the Greek source.
    static func evidenceKeys(_ chunks: [RetrievedChunk]) -> Set<String> {
        var keys = Set<String>()
        for retrieved in chunks {
            let chunk = retrieved.chunk
            keys.formUnion(chunk.legal?.canonicalKeys ?? [])
            if let primary = chunk.legal?.primaryStatuteKey { keys.insert(primary) }
            if let document = chunk.legal?.documentStatuteKey { keys.insert(document) }
            keys.formUnion(GreekLegalEntityMasker.canonicalKeys(in: chunk.content))
            if let parent = chunk.parentContent { keys.formUnion(GreekLegalEntityMasker.canonicalKeys(in: parent)) }
            if let source = chunk.sourceTextEl { keys.formUnion(GreekLegalEntityMasker.canonicalKeys(in: source)) }
        }
        return keys
    }

    /// Statutory and case-law identifiers in `response` that no passage contains. Paragraph
    /// numbers alone are not checked (too generic: "paragraph 1" is in most articles).
    static func unsupportedLegalIdentifiers(response: String, chunks: [RetrievedChunk]) -> [String] {
        let answerKeys = GreekLegalEntityMasker.extractEntities(from: response)
            .filter { $0.type != .paragraph && $0.type != .properName && $0.type != .legalTerm }
            .map(\.canonicalKey)
        guard !answerKeys.isEmpty else { return [] }
        let evidence = evidenceKeys(chunks)
        func isSupported(_ key: String) -> Bool {
            if evidence.contains(key) { return true }
            if key.hasPrefix("LAW:") || key.hasPrefix("PD:") || key.hasPrefix("MD:") {
                return evidence.contains { ($0.hasPrefix("LAW:") || $0.hasPrefix("PD:") || $0.hasPrefix("MD:")) && sameStatute($0, key) }
            }
            return false
        }
        var seen = Set<String>()
        return answerKeys.filter { !isSupported($0) && seen.insert($0).inserted }
    }

    // MARK: Gate I

    /// The statutes a passage belongs to or cites.
    static func statuteKeys(of chunk: DocumentChunk) -> Set<String> {
        var keys = Set<String>()
        if let primary = chunk.legal?.primaryStatuteKey { keys.insert(primary) }
        if let document = chunk.legal?.documentStatuteKey { keys.insert(document) }
        let all = (chunk.legal?.canonicalKeys ?? []).union(GreekLegalEntityMasker.canonicalKeys(in: chunk.content))
            .union(chunk.sourceTextEl.map(GreekLegalEntityMasker.canonicalKeys(in:)) ?? [])
        keys.formUnion(all.filter { $0.hasPrefix("LAW:") || $0.hasPrefix("PD:") })
        return keys
    }

    /// When the question names one or more statutes and every passage that cites any statute
    /// cites only others (none of the requested ones), the requested statute key; nil otherwise.
    /// Passages that cite no statute don't count either way.
    static func statutoryIsolationViolation(query: String, chunks: [DocumentChunk]) -> String? {
        let requested = GreekLegalEntityMasker.canonicalKeys(in: query).filter { $0.hasPrefix("LAW:") || $0.hasPrefix("PD:") }
        guard !requested.isEmpty else { return nil }
        let citing = chunks.map(statuteKeys(of:)).filter { !$0.isEmpty }
        guard !citing.isEmpty else { return nil }
        let anyRequested = citing.contains { keys in keys.contains { key in requested.contains { sameStatute(key, $0) } } }
        return anyRequested ? nil : requested.sorted().first
    }

    /// Two statute keys name the same statute: the same kind and number, and the same year when
    /// both have one ("LAW:5239" is "LAW:5239/2025"; "PD:62/2025" is not "PD:62/2010").
    static func sameStatute(_ first: String, _ second: String) -> Bool {
        let a = first.split(separator: "/", maxSplits: 1)
        let b = second.split(separator: "/", maxSplits: 1)
        guard a.first == b.first else { return false }
        return a.count < 2 || b.count < 2 || a[1] == b[1]
    }
}
