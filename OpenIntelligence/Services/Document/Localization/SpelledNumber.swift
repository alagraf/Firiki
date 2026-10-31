//
//  SpelledNumber.swift
//  OpenIntelligence
//
//  Thesis fork: English and Greek number words. Statutes write numbers in words ("δεν μπορεί να
//  είναι μικρότερος από διακόσιους"); the gates read them as their values
//  (`LegalVerificationPolicy.annotatingSpelledNumbers`) and an English answer has them as digits
//  before its translation to Greek (`digitsForEnglishNumberWords`).
//

import Foundation

/// English and Greek number words (accents removed, lower case).
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

    /// An English text with every cardinal number word from 2 to 999 as digits: "not more than
    /// three hundred" → "not more than 300". Done before an answer is translated to Greek: the
    /// translator wrote "three hundred" as "τρία εκατοντάδες" (Constitution run 9). Ordinals
    /// ("twenty-fifth") and Greek words are left as they are.
    static func digitsForEnglishNumberWords(_ text: String) -> String {
        let ns = text as NSString
        guard let wordRegex = try? NSRegularExpression(pattern: #"[A-Za-z]+"#) else { return text }
        let tokens = wordRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map {
            (range: $0.range, word: ns.substring(with: $0.range).lowercased())
        }
        var replacements: [(range: NSRange, value: Int)] = []
        var index = 0
        while index < tokens.count {
            var run: [String] = [tokens[index].word]
            var end = index
            while end + 1 < tokens.count, run.count < 6 {
                let gapStart = tokens[end].range.location + tokens[end].range.length
                let gap = ns.substring(with: NSRange(location: gapStart, length: tokens[end + 1].range.location - gapStart))
                guard gap.count <= 2, gap.allSatisfy({ $0 == " " || $0 == "-" }) else { break }
                run.append(tokens[end + 1].word)
                end += 1
            }
            // A fraction stays words: "two-thirds" became "2-τρίτων" (Constitution run 10).
            let next = index + run.count < tokens.count ? tokens[index + run.count].word : nil
            if let (value, used) = parse(run), used > 0, value > 1,
               !run.prefix(used).contains(where: { isOrdinal($0) }),
               !(run.count > used ? isFraction(run[used]) : next.map(isFraction) ?? false) {
                let first = tokens[index].range, last = tokens[index + used - 1].range
                replacements.append((NSRange(location: first.location, length: last.location + last.length - first.location), value))
                index += used
            } else {
                index += 1
            }
        }
        var result = text
        for replacement in replacements.reversed() {
            guard let range = Range(replacement.range, in: result) else { continue }
            result.replaceSubrange(range, with: String(replacement.value))
        }
        // The draft writes "twenty-six (26)" as the code does; once a digit, it is "26".
        return result.replacingOccurrences(of: #"\b(\d+) \(\1\)"#, with: "$1", options: .regularExpression)
    }

    private static let nonFractionOrOrdinalWords: Set<String> = [
        "month", "months", "length", "lengths", "width", "widths", "depth", "depths",
        "birth", "births", "growth", "growths", "youth", "youths", "faith", "faiths",
        "truth", "truths", "south", "north", "path", "paths", "math", "maths",
        "breath", "breaths", "death", "deaths", "strength", "strengths",
    ]

    private static func isFraction(_ word: String) -> Bool {
        guard !nonFractionOrOrdinalWords.contains(word) else { return false }
        return isOrdinal(word) || word.hasSuffix("ths") || ["thirds", "quarter", "quarters", "half", "halves"].contains(word)
    }

    private static func isOrdinal(_ word: String) -> Bool {
        guard !nonFractionOrOrdinalWords.contains(word) else { return false }
        return word.hasSuffix("th") || ["second", "third", "first"].contains(word)
    }
}
