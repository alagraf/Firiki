//
//  GreekLegalDocumentSummarizer.swift
//  Firiki
//
//  Thesis fork (PoC capability 2): a Greek summary of one imported statute. Its passages (English
//  translations with bilingual anchors) are grouped by article into pieces that fit the on-device
//  model's window; the model notes each group's rules with their article numbers (map). The
//  "Main provisions" list is built from the notes, one bullet an article, and the model writes
//  only the opening sentences from them (reduce). Sentences whose figures no passage of the document
//  states, or that cite an article the document neither has nor cites, are dropped. The rest is
//  translated to Greek with the citation-preserving English→Greek path.
//

import Foundation
import FoundationModels

nonisolated enum GreekLegalDocumentSummarizer {
    struct Summary: Sendable {
        /// The summary in Greek; the English one when translation failed.
        let greek: String
        let english: String
        /// Sentences of the English summary removed because a figure or article was unsupported.
        let dropped: [String]
        /// Map calls (article groups) and the characters of notes the summary was written from.
        let groups: Int
        let noteCharacters: Int
    }

    /// One article's text: its heading ("Article 8") and the passages' text without the heading
    /// each repeats.
    struct ArticleText: Equatable, Sendable {
        let heading: String
        let text: String
    }

    /// The window the groups are sized for: the iPhone's 4,096 tokens even where the model reports
    /// more (a Mac reports 8,192), so the Simulator behaves as the phone.
    static let windowTokens = 4_096
    /// English characters of passages a map call reads: about 45% of the window at 4 characters a
    /// token, leaving room for the instructions and the notes.
    static var groupCharacters: Int { windowTokens * 4 * 45 / 100 }

    // MARK: Articles

    private static let articleHeading = try? NSRegularExpression(pattern: #"^\s*Article\s+(\d{1,4}[A-Za-zΑ-Ωα-ω]?)\b(?:\s*\[[^\]\n]*\])?"#)

    /// The document's articles in order, built from its passages (in chunk order). A passage that
    /// starts with no article heading belongs to the title page or the contents and is left out,
    /// and so is a passage of headings only (a table of contents lists "Article 289 … Article 306").
    static func articles(from passages: [String]) -> [ArticleText] {
        var result: [ArticleText] = []
        for passage in passages {
            let ns = passage as NSString
            guard let match = articleHeading?.firstMatch(in: passage, range: NSRange(location: 0, length: ns.length)) else { continue }
            let heading = "Article " + ns.substring(with: match.range(at: 1))
            let body = ns.substring(from: match.range.location + match.range.length).trimmingCharacters(in: .whitespacesAndNewlines)
            let headings = passage.components(separatedBy: "Article ").count - 1
            let words = body.split(whereSeparator: \.isWhitespace).count
            guard words >= 12, headings < 3 || words / (headings + 1) >= 15 else { continue }
            if let last = result.last, last.heading == heading {
                result[result.count - 1] = ArticleText(heading: heading, text: last.text + "\n" + strippingTitle(body, after: last.text))
            } else {
                result.append(ArticleText(heading: heading, text: body))
            }
        }
        return result
    }

    /// A later piece of an article repeats its title line ("Maternity protection"): dropped when the
    /// article's text already starts with it.
    private static func strippingTitle(_ body: String, after existing: String) -> String {
        guard let firstLine = body.components(separatedBy: "\n").first, firstLine.count <= 140,
              existing.hasPrefix(firstLine), body.count > firstLine.count else { return body }
        return String(body.dropFirst(firstLine.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Characters of a part of a document without articles: about three parts a group.
    static var partCharacters: Int { groupCharacters / 3 }

    /// A document without article headings (a ministerial decision: its preamble, then numbered
    /// points) as consecutive parts ("Part 1", "Part 2", …) of about `partCharacters`, cut between
    /// passages, so it is noted and listed like a statute's articles. Decision 8934/2026 had no
    /// article, and its summary was empty.
    static func parts(from passages: [String]) -> [ArticleText] {
        var parts: [ArticleText] = []
        var current = ""
        func close() {
            guard !current.isEmpty else { return }
            parts.append(ArticleText(heading: "Part \(parts.count + 1)", text: current))
            current = ""
        }
        for passage in passages {
            let text = passage.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if !current.isEmpty, current.count + text.count + 1 > partCharacters { close() }
            current += (current.isEmpty ? "" : "\n") + text
        }
        close()
        return parts
    }

    /// The number of an article's or a part's heading: "8" of "Article 8", "2" of "Part 2".
    static func number(of heading: String) -> String {
        heading.split(separator: " ", maxSplits: 1).last.map(String.init) ?? heading
    }

    /// An article's heading line in a group: "=== Article 8 ===". Set apart from the text, so the
    /// model labels its notes with the statute's own article and not with an article the text
    /// amends or quotes ("Article 404 of the Labour Code is replaced as follows", dev summary 1).
    static func marker(_ heading: String, continued: Bool = false) -> String {
        "=== \(heading)\(continued ? " (continued)" : "") ==="
    }

    /// Consecutive articles grouped so each group's text stays within `limit` characters; an
    /// article longer than that is cut at a line or sentence end, each piece under its heading.
    static func groups(of articles: [ArticleText], limit: Int = groupCharacters) -> [String] {
        var groups: [String] = []
        var current = ""
        func add(_ block: String) {
            if !current.isEmpty, current.count + block.count + 2 > limit {
                groups.append(current)
                current = ""
            }
            current += (current.isEmpty ? "" : "\n\n") + block
        }
        for article in articles {
            let block = marker(article.heading) + "\n" + article.text
            if block.count <= limit {
                add(block)
                continue
            }
            var rest = Substring(article.text)
            var continued = false
            while !rest.isEmpty {
                let header = marker(article.heading, continued: continued) + "\n"
                let room = max(1, limit - header.count)
                var piece = rest.prefix(room)
                if piece.count < rest.count, let cut = piece.lastIndex(where: { $0 == "\n" || $0 == "." }), piece.distance(from: piece.startIndex, to: cut) > room / 2 {
                    piece = rest[rest.startIndex...cut]
                }
                add(header + piece)
                rest = rest[piece.endIndex...].drop { $0.isWhitespace }
                continued = true
            }
        }
        if !current.isEmpty { groups.append(current) }
        return groups
    }

    // MARK: Model calls

    /// The map call's instructions, allowing `lines` lines of notes for its group.
    static func mapInstructions(lines: Int, parts: Bool = false) -> String {
        if parts {
            return """
            You take notes on a Greek legal text without articles (a ministerial decision) for a lawyer. Use only the text given. It is cut into parts, each starting with a line like "=== Part 2 ===". Write at most \(lines) lines, the most important rules first, each under 35 words: "Part N: " with N from the === line, then the rule, with its figures, dates and who it applies to. Leave out the list of legal bases the text relies on and its signatures.
            """
        }
        return """
        You take notes on articles of a Greek law for a lawyer. Use only the text given. Each article starts with a line like "=== Article 8 ===". Write at most \(lines) lines, the most important rules first, each under 35 words: "Article N: " with N from the === line, then the rule, with its figures, time limits and who it applies to. When an article amends or replaces an article of another law, still use N from the === line and say what the rule now provides. Leave out articles that only state the purpose or repeal provisions.
        """
    }

    /// A note line is about 35 words, some 230 characters.
    static let noteLineCharacters = 230
    /// A line is kept whole up to this length; a longer one is cut at a sentence or clause end. Cut
    /// at 230 characters, Article 7 of Law 5278/2026 ended mid-phrase in «… και φυλάσσονται στην …»
    /// (9 Nov 2026).
    static let maxNoteLineCharacters = 320

    /// A note line of at most `maxNoteLineCharacters`: cut after its last sentence end, or else at
    /// its last clause end (closed with a full stop), or else at a word with "…".
    static func shortenedNoteLine(_ line: String) -> String {
        guard line.count > maxNoteLineCharacters else { return line }
        let head = line.prefix(maxNoteLineCharacters)
        func offset(_ index: Substring.Index) -> Int { head.distance(from: head.startIndex, to: index) }
        if let end = head.indices.last(where: { index in
            head[index] == "." && offset(index) >= noteLineCharacters / 2
                && head.index(after: index) < head.endIndex && head[head.index(after: index)] == " "
                && !(offset(index) > 0 && head[head.index(before: index)].isNumber)
        }) {
            return String(head[...end])
        }
        if let cut = head.lastIndex(where: { ",;".contains($0) }), offset(cut) >= noteLineCharacters / 2 {
            return String(head[..<cut]) + "."
        }
        let word = head.lastIndex(of: " ").map { head[..<$0] } ?? head
        return String(word) + "…"
    }
    /// "Main provisions" has at most this many bullets, one an article, each from at most
    /// `linesPerBullet` of the article's note lines.
    static let maxBullets = 12
    static let linesPerBullet = 2

    /// Lines of notes a group may have: two an article, from three to eight.
    static func linesPerGroup(articles: Int) -> Int {
        min(8, max(3, 2 * articles))
    }

    /// One line of notes, with the article it is about ("8", "414Α").
    struct Note: Equatable, Sendable {
        let article: String
        let text: String
    }

    private static let noteArticle = try? NSRegularExpression(pattern: #"^(?:[-•*]\s*)?(?:\*\*)?(?:Article|Part)\s+(\d{1,4}[A-Za-zΑ-Ωα-ω]?)\b(?:\*\*)?\s*[:.\-–]?\s*(?:\*\*)?\s*"#)
    private static let markerLine = try? NSRegularExpression(pattern: #"^=+\s*(?:Article|Part)\s+(\d{1,4}[A-Za-zΑ-Ωα-ω]?)(?:\s*\(continued\))?\s*=+\s*:?\s*"#)

    /// A group's notes as lines about the group's articles, at most `lines` of at most
    /// `noteLineCharacters` characters (cut after a clause). A line labelled with another article
    /// (one the text amends: "Article 404" in Article 9 of Law 5278, dev summary 1) or with none
    /// takes the article of the line before it, or the group's first; a "=== Article 8 ===" line
    /// the model echoed sets the article (dev summary 2 lost Articles 8 and 9 when those lines
    /// were skipped).
    static func cleanedNotes(_ notes: String, headings: [String], lines: Int) -> [Note] {
        let own = headings.map(number(of:))
        guard var current = own.first else { return [] }
        var kept: [Note] = []
        for raw in notes.components(separatedBy: "\n") {
            var line = raw.trimmingCharacters(in: .whitespaces)
            for regex in [markerLine, noteArticle] {
                let ns = line as NSString
                guard let match = regex?.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { continue }
                let number = ns.substring(with: match.range(at: 1))
                if own.contains(number) { current = number }
                line = ns.substring(from: match.range.location + match.range.length)
            }
            line = line.trimmingCharacters(in: .whitespaces)
            guard line.count >= 12 else { continue }
            line = shortenedNoteLine(line)
            kept.append(Note(article: current, text: line))
            if kept.count == lines { break }
        }
        return kept
    }

    /// The headings of the articles in a group, from its === lines.
    static func headings(inGroup group: String) -> [String] {
        var seen: [String] = []
        for line in group.components(separatedBy: "\n") where line.hasPrefix("=== ") {
            let heading = (line.dropFirst(4).components(separatedBy: " ===").first ?? "")
                .replacingOccurrences(of: " (continued)", with: "")
            if !heading.isEmpty, !seen.contains(heading) { seen.append(heading) }
        }
        return seen
    }

    /// The "Main provisions" bullets, written from the notes rather than by the model: one an
    /// article, from its first `linesPerBullet` lines, in the document's order. With more than
    /// `maxBullets` articles, those with the most notes are kept. Asked for at most twelve bullets
    /// with their article numbers, the model wrote forty (dev summary 1) or took the numbers of
    /// articles the notes mention (dev summary 2).
    /// `label` names the unit ("Article"); nil for parts, whose numbers mean nothing to a reader.
    static func provisions(from notes: [Note], label: String? = "Article") -> [String] {
        var order: [String] = []
        var lines: [String: [String]] = [:]
        for note in notes {
            if lines[note.article] == nil { order.append(note.article) }
            lines[note.article, default: []].append(note.text)
        }
        let weight = lines.mapValues { $0.reduce(0) { $0 + $1.count } }
        let chosen = Set(order.sorted { (weight[$0] ?? 0) > (weight[$1] ?? 0) }.prefix(maxBullets))
        return order.filter(chosen.contains).map { article in
            let text = (lines[article] ?? []).prefix(linesPerBullet).map { line in
                line.last.map { ".…!?".contains($0) } == true ? line : line + "."
            }
            return (label.map { "**\($0) \(article):** " } ?? "") + text.joined(separator: " ")
        }
    }

    /// "Law", not "statute": the opening began "This statute …", which the translator rendered
    /// «Το καταστατικό αυτό» (articles of association) in the summary of Law 5278/2026 (9 Nov 2026).
    static let reduceInstructions = """
        You write the opening of a summary of a Greek law for a lawyer, from notes on its articles. Use only the notes. In one or two sentences, say what the law is about and what it mainly changes. Do not list the articles, and do not add advice or anything the notes don't say.
        """

    /// Characters of notes the opening is written from: the first note of each article.
    static var openingNotesCharacters: Int { groupCharacters }

    /// The permissive guardrails: a summary transforms the user's own document (Article 120 of the
    /// Constitution, "by force", was refused under the default ones; see `greekLegalAwareOnDeviceModel`).
    static func onDeviceResponse(instructions: String, prompt: String) async throws -> String {
        let session = LanguageModelSession(model: SystemLanguageModel(guardrails: .permissiveContentTransformations), instructions: instructions)
        return try await session.respond(to: prompt, options: GenerationOptions(samplingMode: .greedy)).content
    }

    // MARK: Checking the summary

    /// The summary without the sentences that state a figure no passage states or cite an article
    /// the document neither has nor cites (gates C and F against the whole document), and the
    /// sentences dropped. The document's own statute number is neither. Headings and the "Main provisions:" line are kept.
    /// `statuteKeys` are further statutes the text may name (an opinion's sources) and
    /// `alsoSupported` further identifier keys it may cite ("ART:194").
    static func droppingUnsupported(
        _ english: String, passages: [String], articles: [ArticleText], statuteKey: String? = nil,
        statuteKeys: [String] = [], alsoSupported: Set<String> = []
    ) -> (text: String, dropped: [String]) {
        let evidence = NumericValueExtractor.evidence(from: passages)
        let chunks = passages.enumerated().map { index, passage in
            RetrievedChunk(chunk: DocumentChunk(documentId: UUID(), content: passage, embedding: [], metadata: ChunkMetadata(chunkIndex: index)), similarityScore: 1, rank: index + 1)
        }
        let own = Set(articles.map { "ART:" + $0.heading.dropFirst("Article ".count).uppercased() }).union(alsoSupported)
        let statutes = (statuteKey.map { [$0] } ?? []) + statuteKeys
        // The document's own number ("5278/2026") is not a figure: its year comes from the title
        // page's date, which no passage writes after the number.
        let ownNumbers = statutes.compactMap { $0.split(separator: ":").last?.split(separator: "/").first }
            .map { #"\b"# + NSRegularExpression.escapedPattern(for: String($0)) + #"(?:/\d{2,4})?\b"# }
        var dropped: [String] = []
        var lines: [String] = []
        for line in english.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isLabel = trimmed.hasSuffix(":") && trimmed.count <= 40
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#"), !isLabel else {
                lines.append(line)
                continue
            }
            let marker = trimmed.range(of: #"^(?:[-•*]\s+|\d{1,2}[.)]\s+)"#, options: .regularExpression).map { String(trimmed[$0]) } ?? ""
            let kept = LocalNeuralTranslator.segments(String(trimmed.dropFirst(marker.count))).filter { sentence in
                let figures = ownNumbers.reduce(sentence) { $0.replacingOccurrences(of: $1, with: "", options: .regularExpression) }
                let figure = NumericValueExtractor.firstUnsupportedMention(in: figures, evidence: evidence) { mention in
                    !NumericValueExtractor.isCountedByGate(mention)
                }
                let article = LegalVerificationPolicy.unsupportedLegalIdentifiers(response: sentence, chunks: chunks)
                    .filter { key in !own.contains(key) && !statutes.contains { LegalVerificationPolicy.sameStatute(key, $0) } }
                if figure != nil || !article.isEmpty {
                    dropped.append(sentence)
                    return false
                }
                return true
            }
            guard !kept.isEmpty else { continue }
            lines.append(marker + kept.joined(separator: " "))
        }
        return (lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines), dropped)
    }

    // MARK: Summary

    /// The summary of a document from its passages in chunk order (`DocumentChunk.content`, the
    /// English translation). `statuteKey` is the document's own statute (`documentStatuteKey`),
    /// named for the model ("Law 5278/2026"); `respond` and `translate` are the model and the
    /// translator, replaceable in tests.
    static func summarize(
        passages: [String],
        statuteKey: String?,
        respond: (_ instructions: String, _ prompt: String) async throws -> String = { try await onDeviceResponse(instructions: $0, prompt: $1) },
        translate: (String) async throws -> String = { try await LocalNeuralTranslator.shared.translateEnglishToGreekPreservingCitations($0) }
    ) async throws -> Summary {
        let statute = statuteKey.map(GreekLegalAnswerFinalizer.statuteName) ?? "the document"
        let articles = articles(from: passages)
        // A document without articles is summarized by parts; its own articles are then none.
        let byParts = articles.isEmpty
        let groups = groups(of: byParts ? parts(from: passages) : articles)
        var notes: [Note] = []
        var noteCharacters = 0
        for (index, group) in groups.enumerated() {
            let headings = headings(inGroup: group)
            let lines = linesPerGroup(articles: headings.count)
            let note = try await respond(mapInstructions(lines: lines, parts: byParts), "Statute: \(statute)\n\n\(group)")
            let cleaned = cleanedNotes(note, headings: headings, lines: lines)
            Log.info("[LegalSummary] Notes for group \(index + 1) of \(groups.count): \(note.count) characters, \(cleaned.count) line(s) kept", category: .llm)
            noteCharacters += note.count
            notes += cleaned
        }
        let bullets = provisions(from: notes, label: byParts ? nil : "Article")
        var seen = Set<String>()
        let firstNotes = notes.filter { seen.insert($0.article).inserted }.map { "\(byParts ? "Part" : "Article") \($0.article): \($0.text)" }
        var openingNotes = ""
        for line in firstNotes where openingNotes.count + line.count + 1 <= openingNotesCharacters {
            openingNotes += line + "\n"
        }
        let opening = try await respond(reduceInstructions, "Statute: \(statute)\n\nNotes:\n\(openingNotes)")
        // The opening's first two sentences, without any list the model added.
        let openingText = LocalNeuralTranslator.segments(
            opening.components(separatedBy: "\n").first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
        ).prefix(2).joined(separator: " ")
        let draft = openingText + (bullets.isEmpty ? "" : "\n\nMain provisions:\n\n" + bullets.joined(separator: "\n\n"))
        let (english, dropped) = droppingUnsupported(draft, passages: passages, articles: articles, statuteKey: statuteKey)
        if !dropped.isEmpty {
            Log.info("[LegalSummary] Dropped \(dropped.count) sentence(s) with an unsupported figure or article", category: .llm)
        }
        // The English is logged so a wrong Greek word can be traced to its source sentence (the
        // summary has no Response Details card).
        Log.info("[LegalSummary] English summary (\(english.count) chars): \(english.prefix(1_500))", category: .llm)
        let greek = (try? await translate(english)).map(GreekLegalOpinionWriter.repairedGreek) ?? english
        return Summary(greek: greek, english: english, dropped: dropped, groups: groups.count,
                       noteCharacters: noteCharacters)
    }
}
