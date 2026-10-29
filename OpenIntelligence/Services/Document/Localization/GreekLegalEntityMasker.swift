//
//  GreekLegalEntityMasker.swift
//  OpenIntelligence
//
//  Thesis fork, plan stage 4a: a deterministic lexer for Greek and English statutory identifiers
//  (laws, presidential decrees, ministerial decisions, articles, paragraphs, Government Gazette
//  issues, court decisions, EU directives). Before neural translation each identifier is replaced
//  by a placeholder the translator copies through; afterwards the placeholder becomes a canonical
//  bilingual anchor ("Article 38 [Άρθρο 38]"), so English retrieval sees the English form, the
//  lawyer sees the Greek one, and the verification gates compare canonical keys ("ART:38").
//

import Foundation

nonisolated enum GreekLegalEntityType: String, Codable, Sendable, CaseIterable {
    case law = "LAW"                    // Ν. 4808/2021, Νόμος 4093/2012
    case presidentialDecree = "PD"      // Π.Δ. 80/2022
    case ministerialDecision = "MD"     // Υ.Α. 40331/Δ1.13521
    case article = "ARTICLE"            // Άρθρο 38
    case paragraph = "PARAGRAPH"        // παρ. 1, § 2, εδ. α'
    case governmentGazette = "FEK"      // ΦΕΚ Α' 101/19.06.2021
    case supremeCourtDecision = "AP"    // ΑΠ 123/2023, ΟλΑΠ 1/2022, ΣτΕ 456/2021
    case euDirective = "EU_DIR"         // Οδηγία (ΕΕ) 2019/1152
    case properName = "NAME"            // Ανδρέας Ζέρβας (two or more capitalized Greek words)
    case legalTerm = "TERM"             // πολίτευμα → "form of government" (GreekLegalGlossary)
}

nonisolated struct LegalEntityRecord: Codable, Hashable, Sendable {
    /// The placeholder that stood for this occurrence in the masked text ("__LEX_ENT_001__").
    let id: String
    let type: GreekLegalEntityType
    /// The identifier exactly as written in the source ("Άρθρου 38").
    let verbatimEl: String
    /// English canonical form ("Article 38").
    let canonicalEn: String
    /// Greek canonical form ("Άρθρο 38").
    let canonicalEl: String
    /// Language-independent key used by the gates and FTS5 ("ART:38").
    let canonicalKey: String

    /// Injected into the English text after translation.
    /// A legal term reads as its English rendering alone; it is vocabulary, not an identifier.
    var bilingualAnchor: String { type == .legalTerm ? canonicalEn : "\(canonicalEn) [\(canonicalEl)]" }

    /// The Greek form shown to the lawyer: the source wording when it was Greek, else canonical.
    var greekDisplay: String {
        GreekLegalEntityMasker.containsGreek(verbatimEl) ? verbatimEl : canonicalEl
    }
}

nonisolated enum GreekLegalEntityMasker {
    enum UnmaskMode: Sendable {
        /// "Article 38 [Άρθρο 38]": for the indexed English text.
        case bilingualAnchor
        /// "Άρθρο 38": for the Greek answer shown in the UI.
        case greekVerbatim
        /// "Article 38".
        case englishCanonical
        /// The text as it was matched.
        case verbatim
    }

    // MARK: - Normalization

    /// NFKC (so the micro sign U+00B5 becomes Greek mu U+03BC), Greek guillemets to plain quotes,
    /// and the prime-like marks used after Greek numerals and gazette series to an apostrophe.
    static func normalizeGreekText(_ text: String) -> String {
        var s = text
        // Done before NFKC: NFKC turns the tonos U+0384 into a space and a combining accent.
        for mark in ["\u{0384}", "\u{0374}", "\u{02B9}", "\u{2032}", "\u{2019}", "\u{02BC}", "\u{00B4}"] {
            s = s.replacingOccurrences(of: mark, with: "'")
        }
        s = s.precomposedStringWithCompatibilityMapping
        s = s.replacingOccurrences(of: "«", with: "\"").replacingOccurrences(of: "»", with: "\"")
        return repairGreekHomoglyphs(s)
    }

    private static let latinToGreek: [Character: Character] = [
        "A": "Α", "B": "Β", "E": "Ε", "H": "Η", "I": "Ι", "K": "Κ", "M": "Μ", "N": "Ν", "O": "Ο",
        "P": "Ρ", "T": "Τ", "X": "Χ", "Y": "Υ", "Z": "Ζ", "o": "ο", "v": "ν", "u": "υ", "k": "κ",
    ]

    /// OCR and some PDF fonts mix Latin look-alikes into Greek ("ΦΕK", "N. 4808/2021", "A'"). On a
    /// Greek line (mostly Greek letters, or some Greek in a text that is mostly Greek), a word that
    /// has Greek letters, or a short capital abbreviation ("N.", "A'"), gets its Latin look-alikes
    /// replaced by the Greek letters. Other lines are left alone, so English text is never changed.
    static func repairGreekHomoglyphs(_ text: String) -> String {
        guard containsGreek(text) else { return text }
        let textIsGreek = greekLetterRatio(text) >= 0.5
        return text.components(separatedBy: "\n").map { line -> String in
            let lineRatio = greekLetterRatio(line)
            guard lineRatio >= 0.5 || (textIsGreek && lineRatio > 0) else { return line }
            return line.split(separator: " ", omittingEmptySubsequences: false).map { token -> String in
                let word = String(token)
                let letters = word.filter(\.isLetter)
                let hasGreek = letters.unicodeScalars.contains(where: isGreekScalar)
                // A token written only in look-alike letters ("To", "o" in a PDF whose font draws
                // Greek with Latin glyphs) is Greek on a Greek line.
                let allLookAlikes = !letters.isEmpty && letters.allSatisfy { latinToGreek[$0] != nil }
                if allLookAlikes && lineRatio >= 0.5 {
                    return String(word.map { latinToGreek[$0] ?? $0 })
                }
                let isCapitalAbbreviation = !letters.isEmpty && letters.count <= 3
                    && letters.allSatisfy { latinToGreek[$0] != nil || isGreekScalar($0.unicodeScalars.first!) }
                    && word.count <= letters.count + 4
                guard hasGreek || isCapitalAbbreviation else { return word }
                return String(word.map { char -> Character in
                    // Lower-case look-alikes only inside a word that is already Greek.
                    if char.isLowercase && !hasGreek { return char }
                    return latinToGreek[char] ?? char
                })
            }.joined(separator: " ")
        }.joined(separator: "\n")
    }

    static func containsGreek(_ text: String) -> Bool {
        text.unicodeScalars.contains(where: isGreekScalar)
    }

    static func isGreekScalar(_ scalar: Unicode.Scalar) -> Bool {
        (0x0370...0x03FF).contains(scalar.value) || (0x1F00...0x1FFF).contains(scalar.value)
    }

    /// Share of letters that are Greek, 0...1.
    static func greekLetterRatio(_ text: String) -> Double {
        var letters = 0
        var greek = 0
        for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
            letters += 1
            if isGreekScalar(scalar) { greek += 1 }
        }
        return letters == 0 ? 0 : Double(greek) / Double(letters)
    }

    // MARK: - Patterns

    private struct Rule {
        let type: GreekLegalEntityType
        let regex: NSRegularExpression
        /// Builds (canonicalKey, canonicalEn, canonicalEl) from the capture groups.
        let canonicalize: ([String]) -> (key: String, en: String, el: String)?
    }

    private static let start = #"(?<![\p{L}\p{N}])"#
    private static let end = #"(?![\p{L}\p{N}])"#

    private static func regex(_ body: String) -> NSRegularExpression {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: start + body, options: [.caseInsensitive])
    }

    /// Order matters: earlier rules win when matches overlap.
    nonisolated(unsafe) private static let rules: [Rule] = [
        Rule(
            type: .governmentGazette,
            regex: regex(#"(?:Φ\.?\s*Ε\.?\s*Κ\.?|FEK|Government\s+Gazette)\s*([ΑΒΓΔABCDG])\s*'?\s*(?:τ\.?\s*|No\.?\s*)?(\d{1,5})\s*\/\s*(\d{1,2}[./-]\d{1,2}[./-]\d{2,4}|\d{4})"# + end),
            canonicalize: { g in
                let series = gazetteSeries(g[1])
                let date = g[3].replacingOccurrences(of: "/", with: ".").replacingOccurrences(of: "-", with: ".")
                let latin = latinSeries(series)
                return ("FEK:\(series):\(g[2]):\(date)", "FEK \(latin) \(g[2])/\(date)", "ΦΕΚ \(series)' \(g[2])/\(date)")
            }
        ),
        Rule(
            type: .supremeCourtDecision,
            regex: regex(#"(Ολ\.?\s*Α\.?\s*Π\.?|Α\.?\s*Π\.?|Σ\.?\s*τ\.?\s*Ε\.?|Εφ\.?\s*Αθ\.?|Plenary\s+of\s+(?:the\s+)?Areios\s+Pagos|Areios\s+Pagos|Council\s+of\s+State|Athens\s+Court\s+of\s+Appeal)\s*(?:No\.?\s*|αριθ\.?\s*)?(\d{1,5})\s*\/\s*(\d{4})"# + end),
            canonicalize: { g in
                guard let court = courtCode(g[1]) else { return nil }
                return ("COURT:\(court.code):\(g[2])/\(g[3])", "\(court.en) \(g[2])/\(g[3])", "\(court.code) \(g[2])/\(g[3])")
            }
        ),
        Rule(
            type: .euDirective,
            regex: regex(#"(?:Οδηγί(?:α|ας)|Directive)\s*(?:\((?:ΕΕ|ΕΚ|ΕΟΚ|EU|EC|EEC)\)\s*)?(?:(?:αριθ\.?|No\.?)\s*)?(\d{2,4})\/(\d{1,4})(?:\/(?:ΕΕ|ΕΚ|ΕΟΚ|EU|EC|EEC))?"# + end),
            canonicalize: { g in
                ("EU_DIR:\(g[1])/\(g[2])", "Directive \(g[1])/\(g[2])", "Οδηγία \(g[1])/\(g[2])")
            }
        ),
        Rule(
            type: .presidentialDecree,
            regex: regex(#"(?:Π\.?\s*Δ\.?|Προεδρικ(?:ό|ού)\s+Διατάγματ(?:ος|α)?|Presidential\s+Decree|P\.?\s*D\.?)\s*(?:(?:αριθ\.?|No\.?)\s*)?(\d{1,4})\s*\/\s*(\d{4})"# + end),
            canonicalize: { g in
                ("PD:\(g[1])/\(g[2])", "Presidential Decree \(g[1])/\(g[2])", "Π.Δ. \(g[1])/\(g[2])")
            }
        ),
        Rule(
            type: .law,
            regex: regex(#"(?:Ν\.?|Νόμο[ςυ]?|Νομου|Law|Act)\s*(?:(?:αριθ\.?|No\.?)\s*)?(\d{1,5})\s*\/\s*(\d{4})"# + end),
            canonicalize: { g in
                ("LAW:\(g[1])/\(g[2])", "Law \(g[1])/\(g[2])", "Ν. \(g[1])/\(g[2])")
            }
        ),
        Rule(
            type: .ministerialDecision,
            regex: regex(#"(?:Κ\.?\s*Υ\.?\s*Α\.?|Υ\.?\s*Α\.?|Υπουργικ(?:ή|ής)\s+Απόφασ(?:η|ης)|Ministerial\s+Decision)\s*(?:(?:αριθ\.?|No\.?)\s*)?(\d{1,6}(?:\/[0-9\p{L}]+(?:\.[0-9\p{L}]+)*)+)"#),
            canonicalize: { g in
                ("MD:\(g[1].uppercased())", "Ministerial Decision \(g[1])", "Υ.Α. \(g[1])")
            }
        ),
        Rule(
            type: .article,
            regex: regex(#"(?:Άρθρ(?:ο|ου|α|ων)|Αρθρ(?:ο|ου|α|ων)|Άρθρ\.|Αρθρ\.|Αρ\.|Articles?|Art\.)\s*(\d{1,4}[\p{L}]?)"# + end),
            canonicalize: { g in
                let number = articleNumber(g[1])
                return ("ART:\(number)", "Article \(number)", "Άρθρο \(number)")
            }
        ),
        Rule(
            type: .paragraph,
            regex: NSRegularExpression.unsafe(start + #"(?:παρ\.|παράγραφ(?:ος|ου|ο)|paragraph|para\.|§)\s*(\d{1,3}[α-ωa-z]?)"# + end),
            canonicalize: { g in
                ("PAR:\(g[1].lowercased())", "paragraph \(g[1].lowercased())", "παρ. \(g[1].lowercased())")
            }
        ),
        Rule(
            type: .paragraph,
            regex: regex(#"(?:εδ\.|εδάφιο|εδαφίου)\s*([α-ω]{1,2})\s*'"#),
            canonicalize: { g in
                let letter = g[1].lowercased()
                return ("SUBPAR:\(letter)", "subparagraph \(letter)'", "εδ. \(letter)'")
            }
        ),
    ]

    // MARK: Legal glossary

    /// Thesis fork: constitutional and labour-law terms the general-purpose translator renders
    /// wrongly or inconsistently ("πολίτευμα" became "sovereignty" and "constitution",
    /// "Ακροτελεύτια διάταξη" "CSCE provision"), given one fixed English rendering in documents and
    /// questions alike. Each entry: Greek forms, English forms (so an English answer's term is
    /// recognized too), English rendering, Greek lemma. Singular and plural are separate entries.
    static let glossary: [(greek: String, english: String, en: String, el: String)] = [
        ("πολίτευμ(?:α|ατος)", "form of government", "form of government", "πολίτευμα"),
        ("ακροτελεύτι(?:α|ας) διάταξ(?:η|ης)", "final provision", "final provision", "ακροτελεύτια διάταξη"),
        ("μεταβατικ(?:ή|ής) διάταξ(?:η|ης)", "transitional provision", "transitional provision", "μεταβατική διάταξη"),
        ("μεταβατικ(?:ές|ών) διατάξ(?:εις|εων)", "transitional provisions", "transitional provisions", "μεταβατικές διατάξεις"),
        ("προφυλάκισ(?:η|ης)", "pre-?trial detention", "pre-trial detention", "προφυλάκιση"),
        ("ανακριτ(?:ής|ή)", "investigating judge", "investigating judge", "ανακριτής"),
        ("πλημμέλημ(?:α|ατος)", "misdemeanou?r", "misdemeanour", "πλημμέλημα"),
        ("πλημμελήματ(?:α|ων)|πλημμελημάτων", "misdemeanou?rs", "misdemeanours", "πλημμελήματα"),
        ("κακούργημ(?:α|ατος)", "felony", "felony", "κακούργημα"),
        ("κακουργήματ(?:α|ων)|κακουργημάτων", "felonies", "felonies", "κακουργήματα"),
        ("θητεί(?:α|ας)", "term of office", "term of office", "θητεία"),
        ("[ΕΈεέ]ν[οό]πλ(?:ες|ων)\\s+[Δδ]υνάμ(?:εις|εων)", "armed forces", "Armed Forces", "Ένοπλες Δυνάμεις"),
        ("αναθεώρησ(?:η|ης) του Συντάγματος", "revision of the Constitution", "revision of the Constitution", "αναθεώρηση του Συντάγματος"),
        ("αποζημίωσ(?:η|ης) απόλυσης", "severance pay", "severance pay", "αποζημίωση απόλυσης"),
        ("καταγγελί(?:α|ας) της σύμβασης εργασίας", "termination of the employment contract", "termination of the employment contract", "καταγγελία της σύμβασης εργασίας"),
    ]

    nonisolated(unsafe) private static let glossaryRules: [Rule] = glossary.map { term in
        Rule(
            type: .legalTerm,
            regex: regex("(?:\(term.greek)|\(term.english))" + end),
            canonicalize: { _ in ("TERM:" + term.en, term.en, term.el) }
        )
    }

    private static func gazetteSeries(_ raw: String) -> String {
        switch raw.uppercased() {
        case "A", "Α": return "Α"
        case "B", "Β": return "Β"
        case "C", "G", "Γ": return "Γ"
        case "D", "Δ": return "Δ"
        default: return raw.uppercased()
        }
    }

    private static func latinSeries(_ greek: String) -> String {
        ["Α": "A", "Β": "B", "Γ": "C", "Δ": "D"][greek] ?? greek
    }

    private static func courtCode(_ raw: String) -> (code: String, en: String)? {
        let compact = raw.replacingOccurrences(of: ".", with: "")
            .components(separatedBy: .whitespaces).joined()
            .lowercased()
        switch compact {
        case "ολαπ", "plenaryofareiospagos", "plenaryoftheareiospagos":
            return ("ΟλΑΠ", "Plenary of Areios Pagos")
        case "απ", "areiospagos":
            return ("ΑΠ", "Areios Pagos")
        case "στε", "councilofstate":
            return ("ΣτΕ", "Council of State")
        case "εφαθ", "athenscourtofappeal":
            return ("ΕφΑθ", "Athens Court of Appeal")
        default:
            return nil
        }
    }

    /// "38Α" and "38A" are the same article; the suffix letter is kept in Latin capitals.
    private static func articleNumber(_ raw: String) -> String {
        let map: [Character: Character] = ["Α": "A", "Β": "B", "Γ": "C", "Δ": "D", "Ε": "E", "Ζ": "Z"]
        return String(raw.uppercased().map { map[$0] ?? $0 })
    }

    // MARK: - Matching

    private struct Match {
        let range: NSRange
        let type: GreekLegalEntityType
        let verbatim: String
        let key: String
        let en: String
        let el: String
    }

    private static func matches(in text: String) -> [Match] {
        let ns = text as NSString
        let whole = NSRange(location: 0, length: ns.length)
        var found: [Match] = []
        var taken = IndexSet()
        for rule in rules + glossaryRules {
            for result in rule.regex.matches(in: text, range: whole) {
                let range = result.range
                guard !taken.intersects(integersIn: range.location..<(range.location + range.length)) else { continue }
                var groups: [String] = []
                for index in 0..<result.numberOfRanges {
                    let r = result.range(at: index)
                    groups.append(r.location == NSNotFound ? "" : ns.substring(with: r))
                }
                guard let canonical = rule.canonicalize(groups) else { continue }
                taken.insert(integersIn: range.location..<(range.location + range.length))
                found.append(Match(
                    range: range, type: rule.type, verbatim: groups[0],
                    key: canonical.key, en: canonical.en, el: canonical.el
                ))
            }
        }
        // Proper names last, so a legal identifier always wins an overlap.
        let wholeNS = text as NSString
        for result in properNameRegex.matches(in: text, range: whole) {
            let words = wholeNS.substring(with: result.range).components(separatedBy: " ")
            // Leading function words ("Στην Ελλάδα", "Η Εσπεράντο") are not part of a name.
            var start = 0
            var location = result.range.location
            while start < words.count, nameStopWords.contains(words[start].lowercased()) {
                location += (words[start] as NSString).length + 1
                start += 1
            }
            let nameWords = Array(words[start...])
            guard nameWords.count >= 2 else { continue }
            let verbatim = nameWords.joined(separator: " ")
            let range = NSRange(location: location, length: (verbatim as NSString).length)
            guard !taken.intersects(integersIn: range.location..<(range.location + range.length)) else { continue }
            taken.insert(integersIn: range.location..<(range.location + range.length))
            let latin = transliterate(verbatim)
            found.append(Match(
                range: range, type: .properName, verbatim: verbatim,
                key: "NAME:" + latin.lowercased(), en: latin, el: verbatim
            ))
        }
        return found.sorted { $0.range.location < $1.range.location }
    }

    /// Two or more consecutive capitalized Greek words on one line ("Ανδρέας Ζέρβας"). A word
    /// in capitals throughout (a heading) is not a name word.
    nonisolated(unsafe) private static let properNameRegex = NSRegularExpression.unsafe(
        start + #"[\p{Lu}&&\p{Greek}][\p{Ll}\p{M}&&[\p{Greek}\p{M}]]+(?:[ ][\p{Lu}&&\p{Greek}][\p{Ll}\p{M}&&[\p{Greek}\p{M}]]+)+"# + end, options: []
    )

    /// Capitalized Greek words that start sentences but are never part of a name.
    private static let nameStopWords: Set<String> = [
        "ο", "η", "το", "οι", "τα", "τον", "την", "τη", "του", "της", "των", "τους", "τις", "στο",
        "στη", "στην", "στον", "στα", "στις", "στους", "σε", "από", "για", "με", "και", "ή", "να",
        "θα", "δεν", "μη", "μην", "ως", "κατά", "μετά", "πριν", "όταν", "εάν", "αν", "ένας", "μια",
        "μία", "ένα", "αυτό", "αυτή", "αυτός", "αυτά", "ποιος", "ποιός", "ποια", "ποιά", "ποιο",
        "ποιες", "ποιοι", "τι", "πώς", "πού", "πότε", "γιατί", "είναι", "είμαι", "ήταν", "επίσης",
        "όμως", "ενώ", "αλλά", "ότι", "όπως", "κάθε", "όλοι", "όλα", "πολλοί", "σύμφωνα",
    ]

    /// ELOT 743 Greek-to-Latin transliteration ("Ανδρέας Ζέρβας" → "Andreas Zervas"), so a name
    /// reads the same in every English text, whatever the translation model would have made of it.
    static func transliterate(_ text: String) -> String {
        let plain = text.folding(options: .diacriticInsensitive, locale: Locale(identifier: "el"))
        let lower = Array(plain.lowercased())
        let upper = Array(plain)
        let single: [Character: String] = [
            "α": "a", "β": "v", "γ": "g", "δ": "d", "ε": "e", "ζ": "z", "η": "i", "θ": "th", "ι": "i",
            "κ": "k", "λ": "l", "μ": "m", "ν": "n", "ξ": "x", "ο": "o", "π": "p", "ρ": "r", "σ": "s",
            "ς": "s", "τ": "t", "υ": "y", "φ": "f", "χ": "ch", "ψ": "ps", "ω": "o",
        ]
        let voiceless: Set<Character> = ["θ", "κ", "ξ", "π", "σ", "ς", "τ", "φ", "χ", "ψ"]
        var output = ""
        var i = 0
        while i < lower.count {
            let c = lower[i]
            let next: Character? = i + 1 < lower.count ? lower[i + 1] : nil
            let after: Character? = i + 2 < lower.count ? lower[i + 2] : nil
            let wordStart = i == 0 || !lower[i - 1].isLetter
            var piece: String
            var consumed = 1
            switch (c, next) {
            case ("ο", "υ"): piece = "ou"; consumed = 2
            case ("α", "υ"), ("ε", "υ"), ("η", "υ"):
                let vowel = c == "α" ? "a" : (c == "ε" ? "e" : "i")
                piece = vowel + ((after.map { voiceless.contains($0) || !$0.isLetter } ?? true) ? "f" : "v"); consumed = 2
            case ("μ", "π"): piece = wordStart ? "b" : "mp"; consumed = 2
            case ("ν", "τ"): piece = wordStart ? "d" : "nt"; consumed = 2
            case ("γ", "γ"): piece = "ng"; consumed = 2
            case ("γ", "κ"): piece = wordStart ? "g" : "gk"; consumed = 2
            case ("γ", "ξ"): piece = "nx"; consumed = 2
            case ("γ", "χ"): piece = "nch"; consumed = 2
            default: piece = single[c] ?? String(upper[i])
            }
            if upper[i].isUppercase, let first = piece.first {
                piece = first.uppercased() + piece.dropFirst()
            }
            output += piece
            i += consumed
        }
        return output
    }

    static func placeholder(_ index: Int) -> String {
        String(format: "__LEX_ENT_%03d__", index)
    }

    /// Replaces every identifier with a numbered placeholder. The text is normalized first.
    static func maskEntities(in text: String) -> (maskedText: String, entities: [LegalEntityRecord]) {
        let normalized = normalizeGreekText(text)
        let found = matches(in: normalized)
        guard !found.isEmpty else { return (normalized, []) }
        let ns = normalized as NSString
        var output = ""
        var cursor = 0
        var entities: [LegalEntityRecord] = []
        for (offset, match) in found.enumerated() {
            let id = placeholder(offset + 1)
            output += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            output += id
            cursor = match.range.location + match.range.length
            entities.append(LegalEntityRecord(
                id: id, type: match.type, verbatimEl: match.verbatim,
                canonicalEn: match.en, canonicalEl: match.el, canonicalKey: match.key
            ))
        }
        output += ns.substring(from: cursor)
        return (output, entities)
    }

    /// The identifiers in `text`, in order, without masking.
    static func extractEntities(from text: String) -> [LegalEntityRecord] {
        maskEntities(in: text).entities
    }

    /// The distinct canonical keys in `text`.
    static func canonicalKeys(in text: String) -> Set<String> {
        Set(extractEntities(from: text).map(\.canonicalKey))
    }

    /// Placeholders as a translator may return them: case changed, underscores dropped or spaced.
    nonisolated(unsafe) private static let placeholderPattern = NSRegularExpression.unsafe(
        #"(?:_+\s*)?LEX\s*_?\s*ENT\s*_?\s*(\d{1,3})(?:\s*_+)?"#, options: [.caseInsensitive]
    )

    /// Puts the identifiers back in place of their placeholders.
    static func unmaskEntities(in translatedText: String, entities: [LegalEntityRecord], mode: UnmaskMode) -> String {
        guard !entities.isEmpty else { return translatedText }
        var byNumber: [Int: LegalEntityRecord] = [:]
        for entity in entities {
            if let number = Int(entity.id.filter(\.isNumber)) { byNumber[number] = entity }
        }
        let ns = translatedText as NSString
        var output = ""
        var cursor = 0
        for result in placeholderPattern.matches(in: translatedText, range: NSRange(location: 0, length: ns.length)) {
            let number = Int(ns.substring(with: result.range(at: 1))) ?? -1
            guard let entity = byNumber[number] else { continue }
            output += ns.substring(with: NSRange(location: cursor, length: result.range.location - cursor))
            switch mode {
            case .bilingualAnchor: output += entity.bilingualAnchor
            case .greekVerbatim: output += entity.greekDisplay
            case .englishCanonical: output += entity.canonicalEn
            case .verbatim: output += entity.verbatimEl
            }
            cursor = result.range.location + result.range.length
        }
        output += ns.substring(from: cursor)
        return output
    }

    /// "Article 38 [Άρθρο 38]" → "Article 38": drops a bracket whose identifiers all repeat the
    /// identifier just before it, so an anchored English text has each identifier once.
    static func collapseBilingualAnchors(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\s*\[([^\[\]\n]{1,80})\]"#) else { return text }
        let ns = text as NSString
        var output = ""
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let inside = canonicalKeys(in: ns.substring(with: match.range(at: 1)))
            let beforeStart = max(cursor, match.range.location - 80)
            let before = extractEntities(from: ns.substring(with: NSRange(location: beforeStart, length: match.range.location - beforeStart)))
            guard !inside.isEmpty, let last = before.last, inside == [last.canonicalKey] else { continue }
            output += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            cursor = match.range.location + match.range.length
        }
        output += ns.substring(from: cursor)
        return output
    }

    /// The statute (law or presidential decree) cited most often; ties go to the first cited.
    static func primaryStatuteKey(for entities: [LegalEntityRecord]) -> String? {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for entity in entities where entity.type == .law || entity.type == .presidentialDecree {
            if counts[entity.canonicalKey] == nil { order.append(entity.canonicalKey) }
            counts[entity.canonicalKey, default: 0] += 1
        }
        // `max(by:)` keeps the first of equal elements.
        return order.max { (counts[$0] ?? 0) < (counts[$1] ?? 0) }
    }

    // MARK: - JSON

    static func encode(_ entities: [LegalEntityRecord]) -> String {
        guard let data = try? JSONEncoder().encode(entities) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    static func decode(_ json: String?) -> [LegalEntityRecord] {
        guard let json, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([LegalEntityRecord].self, from: data)) ?? []
    }
}

private extension NSRegularExpression {
    nonisolated static func unsafe(_ pattern: String, options: NSRegularExpression.Options = [.caseInsensitive]) -> NSRegularExpression {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: pattern, options: options)
    }
}
