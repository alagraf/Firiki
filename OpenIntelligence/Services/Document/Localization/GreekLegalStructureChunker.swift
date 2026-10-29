//
//  GreekLegalStructureChunker.swift
//  OpenIntelligence
//
//  Thesis fork, plan stage 3: passages of a Greek statute cut along its own structure. The
//  general chunker cut through provisions and its overlapping pieces separated an article's
//  paragraphs (Constitution Article 120 §4 was three passages after its heading, so the question
//  about it never saw §4; the exception in Article 6 §4 was split from its rule). Here every
//  passage is one numbered paragraph of one article, or a few short ones of the same article, or
//  one short article, and starts with the article's heading line ("Άρθρο 5", then its title), so
//  each passage says which article it belongs to and `LegalCrossReferences.articleHeadings` finds
//  it. A paragraph longer than the word cap is split at sentence ends.
//
//  It applies to a text that is mostly Greek and has at least three article headings, each on a
//  line of its own (a table of contents line "Άρθρο 16 Σκοπός" is not one); every other document
//  keeps the general chunker. Government Gazette (ΦΕΚ) pages are two-column with hyphenated line
//  ends ("υπο -\nχρέωση") and running headers ("ΕΦΗΜΕΡΙΔΑ ΤΗΣ ΚΥΒΕΡΝΗΣΕΩΣ", the issue line, the
//  page number): the headers are dropped and broken words joined.
//

import Foundation

nonisolated enum GreekLegalStructureChunker {
    struct Passage {
        /// The passage: heading line, title line, then its paragraphs, one per line.
        let text: String
        /// The heading and title lines that start `text` (nil before the first article).
        var header: String? = nil
        /// "Άρθρο 5", nil for text before the first article.
        let article: String?
        /// Book/part/chapter headings above the article, then the article heading.
        let sectionPath: [String]
        /// The numbered paragraphs the passage holds (empty for an unnumbered article).
        let paragraphs: [Int]
        /// Where the passage's text is in the original text (from its first line to its last).
        let range: Range<String.Index>
    }

    static let minimumGreekRatio = 0.3
    static let minimumHeadings = 3

    /// Whether the text is a Greek statute this chunker cuts.
    static func applies(to text: String) -> Bool {
        guard GreekLegalEntityMasker.greekLetterRatio(String(text.prefix(200_000))) >= minimumGreekRatio else { return false }
        return acceptedHeadings(in: lines(of: text)).count >= minimumHeadings
    }

    // MARK: Lines

    struct Line {
        let raw: String
        /// Normalized (NFKC, Latin look-alikes repaired) and trimmed.
        let text: String
        let range: Range<String.Index>
        let kind: Kind
    }

    enum Kind: Equatable { case text, noise, heading(number: Double, label: String), structure }

    private static let issueLine = try? NSRegularExpression(
        pattern: #"^Τεύχος\s+\S{1,4}\s*\d{1,4}/\d{1,2}\.\d{1,2}\.\d{4}$"#)
    private static let gazetteLine = try? NSRegularExpression(
        pattern: #"^ΕΦΗΜΕΡΙ[ΔΑ]+\s+ΤΗΣ\s+ΚΥΒΕΡΝΗΣ[ΕΩΣ]+$"#, options: [.caseInsensitive])
    /// A line that is only an article heading, as `LegalCrossReferences.isArticleHeading` reads it.
    private static let headingLine = try? NSRegularExpression(
        pattern: #"^\s*(?:Article|Άρθρο|Αρθρο)\s+(\d{1,4}[\p{L}]?)(?![\p{L}\p{N}])\s*$"#, options: [.caseInsensitive])
    private static let headingNumber = try? NSRegularExpression(pattern: #"(\d{1,4})\s*(\p{L})?\s*$"#)
    private static let closingLine = try? NSRegularExpression(
        pattern: #"^(?:(?:Αθήνα|Athens),?\s+\d{1,2}\s+\p{L}+\s+\d{4}|Πίνακας\s|ΠΙΝΑΚΑΣ\s)"#)
    private static let structureWords = ["ΒΙΒΛΙΟ", "ΜΕΡΟΣ", "ΤΜΗΜΑ", "ΚΕΦΑΛΑΙΟ", "ΕΝΟΤΗΤΑ", "ΤΙΤΛΟΣ", "ΤΕΛΙΚΕΣ", "ΜΕΤΑΒΑΤΙΚΕΣ"]

    static func lines(of text: String) -> [Line] {
        var result: [Line] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.byLines, .substringNotRequired]) { _, range, _, _ in
            let raw = String(text[range])
            let normalized = GreekLegalEntityMasker.normalizeGreekText(raw).trimmingCharacters(in: .whitespaces)
            result.append(Line(raw: raw, text: normalized, range: range, kind: kind(of: normalized)))
        }
        return result
    }

    private static func matches(_ regex: NSRegularExpression?, _ text: String) -> Bool {
        regex?.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
    }

    private static func kind(of line: String) -> Kind {
        if line.isEmpty { return .noise }
        if line.allSatisfy(\.isNumber) && line.count <= 5 { return .noise }
        if matches(issueLine, line) || matches(gazetteLine, line) { return .noise }
        if matches(headingLine, line),
           let match = headingNumber?.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)),
           let number = Double((line as NSString).substring(with: match.range(at: 1))) {
            // "Άρθρο 5Α" comes after 5 and before 6.
            let suffix = match.range(at: 2).location != NSNotFound ? 0.5 : 0
            return .heading(number: number + suffix, label: "Άρθρο " + (line as NSString).substring(with: match.range).replacingOccurrences(of: " ", with: ""))
        }
        let letters = line.filter(\.isLetter)
        if letters.count >= 3, line == line.uppercased(),
           structureWords.contains(where: { line.hasPrefix($0) }) || letters.count >= 8 {
            return .structure
        }
        return .text
    }

    /// The article headings that start the code's articles: of the headings in increasing order,
    /// the chain with the most text under its headings. A table of contents can have headings on
    /// lines of their own too (PDFKit reads the Labour Code's contents that way, each with its title
    /// on the next line): taking headings first come, first served accepted the contents up to
    /// "Άρθρο 588" and rejected every real heading after it, so every passage was headed "Άρθρο 588"
    /// (labour run 1). A quoted article or a correlation table after the last article, with a lower
    /// number, stays text of the article it is in.
    static func acceptedHeadings(in lines: [Line]) -> [Int] {
        var candidates: [(index: Int, number: Double, weight: Int)] = []
        let headingIndices = lines.indices.filter { if case .heading = lines[$0].kind { return true } else { return false } }
        for (position, index) in headingIndices.enumerated() {
            guard case .heading(let number, _) = lines[index].kind else { continue }
            let next = position + 1 < headingIndices.count ? headingIndices[position + 1] : lines.count
            let letters = lines[(index + 1)..<next].filter { $0.kind == .text }.reduce(0) { $0 + $1.text.filter(\.isLetter).count }
            guard letters >= 20 else { continue }
            candidates.append((index, number, letters))
        }
        guard !candidates.isEmpty else { return [] }
        // Heaviest increasing chain (weighted longest increasing subsequence).
        var best = candidates.map(\.weight)
        var previous = [Int](repeating: -1, count: candidates.count)
        for i in candidates.indices {
            for j in 0..<i where candidates[j].number < candidates[i].number && best[j] + candidates[i].weight > best[i] {
                best[i] = best[j] + candidates[i].weight
                previous[i] = j
            }
        }
        var chain: [Int] = []
        var cursor = best.indices.max { best[$0] < best[$1] } ?? -1
        while cursor >= 0 {
            chain.append(candidates[cursor].index)
            cursor = previous[cursor]
        }
        return chain.reversed()
    }

    // MARK: Passages

    private static let paragraphStart = try? NSRegularExpression(pattern: #"^(\d{1,2})\.\s+\S"#)
    private static let sentenceEnd = try? NSRegularExpression(pattern: #"(?<=[.;·])\s+(?=[\p{Lu}\d«"(])|[ \t]*\n\s*"#)

    static func passages(in text: String, maxWords: Int = 200, minWords: Int = 40) -> [Passage] {
        let lines = lines(of: text)
        let headings = acceptedHeadings(in: lines)
        guard !headings.isEmpty else { return [] }
        var result: [Passage] = []

        // Text before the first article (title page, table of contents), packed by lines.
        let preamble = lines[0..<headings[0]].filter { $0.kind != .noise }
        result += pack(units: preamble.map { (text: $0.text, range: $0.range, number: nil as Int?) },
                       header: nil, article: nil, path: [], maxWords: maxWords, minWords: minWords)

        // The last article ends where the text after the articles starts: a sign-off ("Αθήνα, 27
        // Ιουνίου 2008"), a block in capitals ("Ο ΠΡΟΕΔΡΟΣ ΤΗΣ ΒΟΥΛΗΣ") or a table ("Πίνακας …").
        // The Constitution's Article 120 §4 ran on into the signatures and resolutions after it,
        // and the answer about §4 was drafted from those (run 11).
        var tailStart = lines.count
        if let last = headings.last {
            tailStart = lines.indices.dropFirst(last + 2).first { index in
                lines[index].kind == .structure || matches(closingLine, lines[index].text)
            } ?? lines.count
        }

        var structure: [String] = []
        var pendingStructure: [String] = []
        for (position, start) in headings.enumerated() {
            let end = position + 1 < headings.count ? headings[position + 1] : tailStart
            guard case .heading(_, let label) = lines[start].kind else { continue }
            var body = lines[(start + 1)..<end].filter { $0.kind != .noise }
            if !pendingStructure.isEmpty { structure = pendingStructure; pendingStructure = [] }
            // Part and chapter headings at the end of an article belong to the next one.
            var trailing: [String] = []
            while let last = body.last, last.kind == .structure {
                trailing.insert(last.text, at: 0)
                body.removeLast()
            }
            if !trailing.isEmpty { pendingStructure = trailing }

            // A title of one or two lines: no sentence punctuation at its end, and the line after it
            // starts a sentence.
            var title: String?
            for count in [1, 2] where title == nil && body.count > count {
                let candidate = joined(body.prefix(count).map(\.text))
                let following = body[count].text
                if candidate.count <= 140, !matches(paragraphStart, body[0].text),
                   let lastCharacter = candidate.last, !".,;:·-".contains(lastCharacter),
                   let first = following.first, first.isUppercase || first.isNumber || first == "«" || first == "\"" {
                    title = candidate
                    body.removeFirst(count)
                }
            }
            let header = [label, title].compactMap { $0 }.joined(separator: "\n")

            // Numbered paragraphs: "1. ", "2. ", … in order.
            var units: [(text: String, range: Range<String.Index>, number: Int?)] = []
            var current: [Line] = []
            var currentNumber: Int?
            var expected = 1
            func flush() {
                guard let first = current.first, let last = current.last else { return }
                units.append((joined(current.map(\.text)), first.range.lowerBound..<last.range.upperBound, currentNumber))
                current = []
            }
            for line in body {
                if let match = paragraphStart?.firstMatch(in: line.text, range: NSRange(location: 0, length: (line.text as NSString).length)),
                   Int((line.text as NSString).substring(with: match.range(at: 1))) == expected {
                    flush()
                    currentNumber = expected
                    expected += 1
                }
                current.append(line)
            }
            flush()
            if units.isEmpty {
                units = [(label, lines[start].range, nil)]
            }
            let path = structure + [label]
            result += pack(units: units, header: header, article: label, path: path, maxWords: maxWords, minWords: minWords,
                           headingRange: lines[start].range)
        }
        // The text after the last article, packed by lines like the text before the first.
        let tail = lines[tailStart...].filter { $0.kind != .noise }
        result += pack(units: tail.map { (text: $0.text, range: $0.range, number: nil as Int?) },
                       header: nil, article: nil, path: [], maxWords: maxWords, minWords: minWords)
        return result
    }

    // MARK: Tables

    /// A table cell as PDFKit reads a Gazette table: a short line (a prose line of a two-column
    /// page is about 50 characters).
    static func isTableCell(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && trimmed.count <= 34 && wordCount(trimmed) <= 5
    }

    /// The lines that are rows of a table: runs of at least four short lines, at least half of them
    /// with a digit ("16 έτη συμπληρωμένα και άνω", "12 μηνών αποζημίωση"). Joined into one
    /// sentence, the rows of Article 333's severance table were translated as "16 years completed
    /// and more than 12 months compensation", and the model mixed them with the article's second
    /// table (labour dev case 34). A wrapped prose line is as short only now and then, and rarely
    /// has a number. A longer row next to the run that starts with a number ("1 έτος συμπληρωμένο
    /// έως 4 έτη 2 μηνών αποζημίωση", both cells on one line) is a row too; a numbered paragraph
    /// ("1. Εργοδότης …") is not. Three or more such rows in a row, each with a second number, are
    /// a table on their own: the rows as `joined` leaves them, a cell per row each.
    static func tableLineIndices(_ lines: [String]) -> Set<Int> {
        func startsRow(_ line: String) -> Bool {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.first?.isNumber == true && trimmed.range(of: #"^\d{1,2}\.\s"#, options: .regularExpression) == nil
        }
        func isFullRow(_ line: String) -> Bool {
            startsRow(line) && line.matches(of: #/\d+/#).count >= 2
        }
        var result = Set<Int>()
        var rowStart = 0
        while rowStart < lines.count {
            var rowEnd = rowStart
            while rowEnd < lines.count, isFullRow(lines[rowEnd]) { rowEnd += 1 }
            if rowEnd - rowStart >= 3 { result.formUnion(rowStart..<rowEnd) }
            rowStart = rowEnd + 1
        }
        var start = 0
        while start < lines.count {
            guard isTableCell(lines[start]) else { start += 1; continue }
            var end = start
            while end < lines.count, isTableCell(lines[end]) { end += 1 }
            let run = lines[start..<end]
            if run.count >= 4, run.filter({ $0.contains(where: \.isNumber) }).count * 2 >= run.count {
                var first = start, last = end
                while first > 0, startsRow(lines[first - 1]) { first -= 1 }
                while last < lines.count, startsRow(lines[last]) { last += 1 }
                result.formUnion(first..<last)
            }
            start = end
        }
        return result
    }

    /// Table lines that are the second cell of a row PDFKit read as two lines: a cell with one
    /// number right after a cell whose numbers all have another unit ("10 έτη συμπληρωμένα" or
    /// "4 έτη συμπληρωμένα έως 6 έτη", then "6 μηνών αποζημίωση"). On lines of their own, a passage
    /// could end between the two cells, and the model read the next row's months as this row's
    /// (labour dev case 34).
    static func secondCells(_ lines: [String], table: Set<Int>) -> Set<Int> {
        /// The units of a table line's numbers: the first two letters of the word after each.
        func units(_ index: Int) -> [String] {
            guard table.contains(index) else { return [] }
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            return line.matches(of: #/\d+\s+(\w\w)/#).map {
                $0.output.1.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            }
        }
        var result = Set<Int>()
        for index in table.sorted() where !result.contains(index) {
            let first = units(index), second = units(index + 1)
            if !first.isEmpty, second.count == 1, !first.contains(second[0]) {
                result.insert(index + 1)
            }
        }
        return result
    }

    /// Lines of one paragraph as one line: a word broken at a line end ("υπο -" + "χρέωση") is
    /// joined, other lines are joined with a space. The rows of a table keep their own lines, with
    /// a row read as two lines put back on one.
    static func joined(_ lines: [String]) -> String {
        let table = tableLineIndices(lines)
        let second = secondCells(lines, table: table)
        var result = ""
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if result.isEmpty {
                result = trimmed
                continue
            }
            if second.contains(index) {
                result += " " + trimmed
                continue
            }
            if table.contains(index) || table.contains(index - 1) {
                result += "\n" + trimmed
                continue
            }
            var head = result
            var broken = false
            if head.hasSuffix("-") || head.hasSuffix("\u{2010}") || head.hasSuffix("\u{00AD}") {
                head.removeLast()
                while head.hasSuffix(" ") { head.removeLast() }
                if let before = head.last, before.isLetter, let after = trimmed.first, after.isLowercase {
                    broken = true
                } else {
                    head = result
                }
            }
            result = broken ? head + trimmed : head + " " + trimmed
        }
        return result.replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
    }

    private static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }

    /// One passage per paragraph (a paragraph under `minWords` joins the next one, within
    /// `maxWords`), a paragraph over `maxWords` split at sentence ends.
    private static func pack(
        units: [(text: String, range: Range<String.Index>, number: Int?)],
        header: String?, article: String?, path: [String], maxWords: Int, minWords: Int,
        headingRange: Range<String.Index>? = nil
    ) -> [Passage] {
        let headerWords = header.map(wordCount) ?? 0
        let budget = max(minWords, maxWords - headerWords)
        // Split long paragraphs first.
        var pieces: [(text: String, range: Range<String.Index>, number: Int?)] = []
        for unit in units {
            if wordCount(unit.text) <= budget {
                pieces.append(unit)
            } else {
                for part in split(unit.text, maxWords: budget) { pieces.append((part, unit.range, unit.number)) }
            }
        }
        var passages: [Passage] = []
        var group: [(text: String, range: Range<String.Index>, number: Int?)] = []
        var groupWords = 0
        func emit() {
            guard let first = group.first, let last = group.last else { return }
            let body = group.map(\.text).joined(separator: "\n")
            let text = [header, body].compactMap { $0 }.joined(separator: "\n")
            let lower = min(headingRange?.lowerBound ?? first.range.lowerBound, first.range.lowerBound)
            let range = (passages.isEmpty ? lower : first.range.lowerBound)..<max(first.range.upperBound, last.range.upperBound)
            var numbers: [Int] = []
            for number in group.compactMap(\.number) where !numbers.contains(number) { numbers.append(number) }
            passages.append(Passage(text: text, header: header, article: article, sectionPath: path, paragraphs: numbers, range: range))
            group = []
            groupWords = 0
        }
        for piece in pieces {
            let words = wordCount(piece.text)
            // One paragraph a passage; a paragraph under `minWords` takes the next one with it.
            if !group.isEmpty, groupWords >= minWords || groupWords + words > budget {
                emit()
            }
            group.append(piece)
            groupWords += words
        }
        emit()
        // A last passage under `minWords` joins the one before it when they fit together.
        if passages.count >= 2, let last = passages.last, wordCount(last.text) - headerWords < minWords {
            let previous = passages[passages.count - 2]
            let lastBody = header.map { String(last.text.dropFirst($0.count + 1)) } ?? last.text
            if wordCount(previous.text) + wordCount(lastBody) <= maxWords + minWords / 2 {
                passages.removeLast(2)
                var numbers = previous.paragraphs
                for number in last.paragraphs where !numbers.contains(number) { numbers.append(number) }
                passages.append(Passage(
                    text: previous.text + "\n" + lastBody, header: header, article: article, sectionPath: path, paragraphs: numbers,
                    range: previous.range.lowerBound..<max(previous.range.upperBound, last.range.upperBound)))
            }
        }
        return passages
    }

    /// The passage cut until every piece fits `fits` (the embedding model's token cap: a Greek word
    /// is about four and a half of its tokens, so a 100-word paragraph can be over it). Each piece
    /// keeps the passage's heading and title.
    static func pieces(of passage: Passage, fitting fits: (String) -> Bool) -> [String] {
        guard !fits(passage.text) else { return [passage.text] }
        let body = passage.header.map { String(passage.text.dropFirst($0.count)).trimmingCharacters(in: .whitespacesAndNewlines) } ?? passage.text
        var words = max(8, body.split(whereSeparator: { $0.isWhitespace }).count / 2)
        while true {
            let parts = split(body, maxWords: words).map { part in passage.header.map { $0 + "\n" + part } ?? part }
            if parts.allSatisfy(fits) || words <= 8 { return parts }
            words = max(8, words * 2 / 3)
        }
    }

    /// A paragraph cut into pieces of at most `maxWords` words at sentence ends and line breaks (a
    /// sentence longer than that is cut between words). Line breaks, the rows of a table, stay.
    static func split(_ text: String, maxWords: Int) -> [String] {
        let ns = text as NSString
        // Each sentence with the separator that followed it: a line break or a space.
        var sentences: [(text: String, separator: String)] = []
        var cursor = 0
        for match in sentenceEnd?.matches(in: text, range: NSRange(location: 0, length: ns.length)) ?? [] {
            let separator = ns.substring(with: match.range).contains("\n") ? "\n" : " "
            sentences.append((ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)), separator))
            cursor = match.range.location + match.range.length
        }
        sentences.append((ns.substring(from: cursor), " "))
        var pieces: [String] = []
        var current = ""
        var currentWords = 0
        func close() {
            if !current.isEmpty { pieces.append(current.trimmingCharacters(in: .whitespacesAndNewlines)) }
            current = ""
            currentWords = 0
        }
        for sentence in sentences {
            let words = sentence.text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            if words.count > maxWords {
                close()
                var start = 0
                while start < words.count {
                    pieces.append(words[start..<min(words.count, start + maxWords)].joined(separator: " "))
                    start += maxWords
                }
                continue
            }
            if currentWords + words.count > maxWords, !current.isEmpty { close() }
            current += sentence.text + sentence.separator
            currentWords += words.count
        }
        close()
        return pieces
    }
}
