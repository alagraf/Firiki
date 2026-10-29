//
//  LegalVerificationPolicy.swift
//  OpenIntelligence
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
        var seen = Set<String>()
        return answerKeys.filter { !evidence.contains($0) && seen.insert($0).inserted }
    }

    // MARK: Gate I

    /// The statutes a passage belongs to or cites.
    static func statuteKeys(of chunk: DocumentChunk) -> Set<String> {
        var keys = Set<String>()
        if let primary = chunk.legal?.primaryStatuteKey { keys.insert(primary) }
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
        let anyRequested = citing.contains { !$0.isDisjoint(with: requested) }
        return anyRequested ? nil : requested.sorted().first
    }
}

/// English and Greek number words (accents removed, lower case) for
/// `LegalVerificationPolicy.annotatingSpelledNumbers`.
nonisolated enum SpelledNumber {
    static func fold(_ word: String) -> String {
        word.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).replacingOccurrences(of: "ς", with: "σ")
    }

    private static func forms(_ stems: [String: Int], endings: [String]) -> [String: Int] {
        var result: [String: Int] = [:]
        for (stem, value) in stems { for ending in endings { result[stem + ending] = value } }
        return result
    }

    private static let greekAdjectiveEndings = ["οσ", "η", "ο", "ου", "ησ", "ων", "ον", "οι", "εσ", "α", "ουσ", "ην"]

    static let units: [String: Int] = {
        var map: [String: Int] = [
            "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
            "second": 2, "third": 3, "fourth": 4, "fifth": 5, "sixth": 6, "seventh": 7, "eighth": 8, "ninth": 9,
            "δυο": 2, "τρεισ": 3, "τρια": 3, "τριων": 3, "τεσσερισ": 4, "τεσσερα": 4, "τεσσαρα": 4, "τεσσαρων": 4,
            "τεσσαρεσ": 4, "πεντε": 5, "εξι": 6, "επτα": 7, "εφτα": 7, "οκτω": 8, "οχτω": 8, "εννεα": 9, "εννια": 9,
        ]
        // Greek ordinals; "έκτος" is also "except" and "δεύτερον" an adverb, so those forms are left out.
        map.merge(forms(["δευτερ": 2, "τριτ": 3, "τεταρτ": 4, "πεμπτ": 5, "εκτ": 6, "εβδομ": 7, "ογδο": 8, "ενατ": 9],
                        endings: greekAdjectiveEndings)) { a, _ in a }
        for excluded in ["εκτοσ", "εβδομα", "δευτερον"] { map[excluded] = nil }
        return map
    }()

    static let teens: [String: Int] = {
        var map: [String: Int] = [
            "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16,
            "seventeen": 17, "eighteen": 18, "nineteen": 19, "tenth": 10, "eleventh": 11, "twelfth": 12,
            "thirteenth": 13, "fourteenth": 14, "fifteenth": 15, "sixteenth": 16, "seventeenth": 17,
            "eighteenth": 18, "nineteenth": 19,
            "δεκα": 10, "εντεκα": 11, "δωδεκα": 12, "δεκατρια": 13, "δεκατρεισ": 13, "δεκατεσσερα": 14,
            "δεκατεσσερισ": 14, "δεκαπεντε": 15, "δεκαεξι": 16, "δεκαεπτα": 17, "δεκαεφτα": 17, "δεκαοκτω": 18,
            "δεκαοχτω": 18, "δεκαεννεα": 19, "δεκαεννια": 19,
        ]
        map.merge(forms(["δεκατ": 10, "ενδεκατ": 11, "δωδεκατ": 12], endings: greekAdjectiveEndings)) { a, _ in a }
        return map
    }()

    static let tens: [String: Int] = {
        var map: [String: Int] = [
            "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80,
            "ninety": 90, "twentieth": 20, "thirtieth": 30, "fortieth": 40, "fiftieth": 50, "sixtieth": 60,
            "seventieth": 70, "eightieth": 80, "ninetieth": 90,
            "εικοσι": 20, "τριαντα": 30, "σαραντα": 40, "πενηντα": 50, "εξηντα": 60, "εβδομηντα": 70,
            "ογδοντα": 80, "ενενηντα": 90,
        ]
        map.merge(forms(["εικοστ": 20, "τριακοστ": 30, "τεσσαρακοστ": 40, "πεντηκοστ": 50, "εξηκοστ": 60,
                         "εβδομηκοστ": 70, "ογδοηκοστ": 80, "ενενηκοστ": 90], endings: greekAdjectiveEndings)) { a, _ in a }
        return map
    }()

    static let hundreds: [String: Int] = {
        var map: [String: Int] = ["εκατο": 100, "εκατον": 100, "hundredth": 100]
        let stems = ["διακοσι": 200, "τριακοσι": 300, "τετρακοσι": 400, "πεντακοσι": 500, "εξακοσι": 600,
                     "επτακοσι": 700, "εφτακοσι": 700, "οκτακοσι": 800, "εννιακοσι": 900, "εννεακοσι": 900]
        map.merge(forms(stems, endings: ["οι", "εσ", "α", "ων", "ουσ"])) { a, _ in a }
        let ordinalStems = Dictionary(uniqueKeysWithValues: stems.map { ($0.key + "οστ", $0.value) })
        map.merge(forms(ordinalStems, endings: greekAdjectiveEndings)) { a, _ in a }
        map.merge(forms(["εκατοστ": 100], endings: greekAdjectiveEndings)) { a, _ in a }
        return map
    }()

    static func isNumberWord(_ word: String) -> Bool {
        units[word] != nil || teens[word] != nil || tens[word] != nil || hundreds[word] != nil
            || word == "hundred" || compound(word) != nil
    }

    /// One-word Greek compounds: "εικοσιπεντε" is 25.
    static func compound(_ word: String) -> Int? {
        for (prefix, value) in tens where word.hasPrefix(prefix) && word.count > prefix.count {
            let rest = String(word.dropFirst(prefix.count))
            if let unit = units[rest] ?? (rest == "ενα" || rest == "ενασ" ? 1 : nil) { return value + unit }
        }
        return nil
    }

    /// The value of the number the words at the start of `words` write, and how many words it takes.
    static func parse(_ words: [String]) -> (Int, Int)? {
        var index = 0
        var total = 0
        func at(_ i: Int) -> String? { i < words.count ? words[i] : nil }
        // Hundreds: "διακόσιοι", "εκατόν", or an English unit followed by "hundred".
        if let word = at(0), let value = hundreds[word] {
            total = value
            index = 1
        } else if let word = at(0), let unit = units[word] ?? (word == "one" ? 1 : nil), at(1) == "hundred" || at(1) == "hundredth" {
            total = unit * 100
            index = 2
        }
        if index > 0, at(index) == "and" || at(index) == "και" { index += 1 }
        let afterHundreds = index
        if let word = at(index) {
            if let value = compound(word) {
                total += value
                index += 1
            } else if let value = tens[word] {
                total += value
                index += 1
                if let next = at(index), let unit = units[next] {
                    total += unit
                    index += 1
                }
            } else if let value = teens[word] ?? units[word] {
                total += value
                index += 1
            }
        }
        // A dangling "and" after hundreds is not part of the number.
        if index == afterHundreds, afterHundreds > 0, at(afterHundreds - 1) == "and" || at(afterHundreds - 1) == "και" {
            index -= 1
        }
        return index > 0 ? (total, index) : nil
    }
}
