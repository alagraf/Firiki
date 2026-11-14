//
//  GreekLegalOpinionWriter.swift
//  Firiki
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

        /// The refusal reason in Greek, for the user; `refusal` stays English for the evaluation logs.
        var refusalGreek: String? {
            switch refusal {
            case nil: return nil
            case "no document of the library addresses the question":
                return "κανένα έγγραφο της βιβλιοθήκης δεν αφορά το ερώτημα"
            case "the conclusion had no supported sentence":
                return "το συμπέρασμα δεν στηρίζεται σε καμία πρόταση των πηγών"
            case "the model declined to write the conclusion":
                return "το μοντέλο της συσκευής αρνήθηκε να γράψει το συμπέρασμα"
            default:
                return "οι πηγές της βιβλιοθήκης δεν επαρκούν για τεκμηριωμένη απάντηση"
            }
        }
    }

    /// The Labour Code's statute key: the base text the other documents amend or apply.
    static let labourCodeKey = "PD:62/2025"
    /// Sources an opinion draws on, and passages per source.
    static let maxSources = 3
    static let passagesPerSource = 3
    /// A document is kept when its best passage scores at least this share of the best document's.
    static let relativeScore: Float = 0.68

    static let disclaimerGreek = "Η γνωμοδότηση αυτή συντάχθηκε αυτόματα από εφαρμογή επίδειξης (proof of concept) με βάση μόνο τα έγγραφα της βιβλιοθήκης. Δεν αποτελεί νομική συμβουλή και πρέπει να ελεγχθεί από δικηγόρο."

    // MARK: Sources

    /// Strips conversational opinion-request framing ("Θέλω γνωμοδότηση:", "Γνωμοδότηση παρακαλώ.")
    /// before translation and retrieval so embeddings and prompts stay focused on the legal issue.
    static func strippedOpinionFraming(_ question: String) -> String {
        var s = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = [
            #"(?i)^\s*(?:(?:θέλω|θελω|χρειάζομαι|χρειαζομαι)\s+)?γνωμοδ[όο]τηση(?:\s+παρακαλ[ώω])?\s*[:;,.!?\-–—]*\s*"#,
            #"(?i)\s*(?:(?:θέλω|θελω|χρειάζομαι|χρειαζομαι)\s+)?γνωμοδ[όο]τηση(?:\s+παρακαλ[ώω])?\s*[.!?;]*\s*$"#,
        ]
        for pattern in patterns {
            s = s.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        let cleaned = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? question : cleaned
    }

    /// The documents an opinion draws on: those whose best passage scores at least `relativeScore`
    /// of the best one's, at most `maxSources`; the Labour Code joins when a kept document amends
    /// or applies it. Later amending or implementing statutes come before the codified Labour Code.
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
        let ordered = kept.sorted { ($0.statuteKey == labourCodeKey ? 1 : 0) < ($1.statuteKey == labourCodeKey ? 1 : 0) }
        return ordered.map { Source(document: $0.document, statuteKey: $0.statuteKey, passages: Array($0.passages.prefix(passagesPerSource))) }
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

    /// Characters of passages a section may read when it holds a whole amending article: the
    /// summarizer's group size, about 45% of the phone's 4,096-token window.
    static var sectionCharacters: Int { GreekLegalDocumentSummarizer.groupCharacters }

    /// A source whose passages include an article that amends or adds a Labour Code article reads
    /// that whole article, in order, then its other passages, within `sectionCharacters`. The
    /// amending article restates the amended paragraphs in full («… διαμορφώνονται ως εξής»); its
    /// three best passages did not include them. The overtime opinion in the Mac app read Article 7
    /// of Law 5239/2025 as only "«three (3)» is replaced by «four (4)»" and the new weekly limits,
    /// not «έως τέσσερις (4) ώρες ημερησίως», and concluded four hours a day were not allowed
    /// (14 Nov 2026). Other sources are unchanged. `documents` holds every document's passages by
    /// file name.
    static func withWholeAmendingArticles(_ sources: [Source], links: [CodeLink], documents: [String: [DocumentChunk]]) -> [Source] {
        let changes = links.filter { $0.kind != .appliesUnder && $0.article != nil }
        guard !changes.isEmpty else { return sources }
        return sources.map { source in
            guard let chunks = documents[source.document] else { return source }
            let articleOf = enclosingArticles(chunks)
            // Expand the top-scoring amending article found in the retrieved passages first, so a
            // secondary snippet of a large neighbouring article does not crowd out the primary hit.
            let orderedPassages = source.passages.sorted { $0.similarityScore > $1.similarityScore }
            guard let primary = orderedPassages.compactMap({ passage -> String? in
                guard let enclosed = articleOf[passage.chunk.id],
                      let link = changes.first(where: { $0.statuteKey == source.statuteKey && ($0.article.map { sameArticle(enclosed, $0) } ?? false) })
                else { return nil }
                return link.article
            }).first else { return source }
            let score = source.bestScore
            let ordered = chunks.sorted { $0.metadata.chunkIndex < $1.metadata.chunkIndex }
            var passages: [RetrievedChunk] = []
            for chunk in ordered where (articleOf[chunk.id].map { sameArticle($0, primary) } ?? false)
                && !passages.contains(where: { $0.chunk.id == chunk.id }) {
                passages.append(RetrievedChunk(
                    chunk: chunk, similarityScore: score, rank: passages.count + 1,
                    sourceDocument: source.document, pageNumber: chunk.metadata.pageNumber))
            }
            passages += source.passages.filter { passage in !passages.contains { $0.chunk.id == passage.chunk.id } }
            var kept: [RetrievedChunk] = []
            var characters = 0
            for passage in passages {
                characters += passage.chunk.content.count
                if !kept.isEmpty && characters > sectionCharacters { break }
                kept.append(passage)
            }
            return Source(document: source.document, statuteKey: source.statuteKey, passages: kept)
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

    // MARK: Greek wording written by the program

    /// A statute's short Greek name, as Greek legal text cites it: "ν. 5239/2025", "π.δ. 62/2025",
    /// "Υ.Α. 8934". The translator turned these into «της Ν. 5239/2025» (a law is masculine).
    static func greekStatuteName(_ key: String) -> String {
        if key == "CONST" { return "Σύνταγμα" }
        if key == labourCodeKey { return "Κώδικας Εργατικού Δικαίου (π.δ. 62/2025)" }
        let names = ["LAW:": "ν. ", "PD:": "π.δ. ", "MD:": "Υ.Α. "]
        for (prefix, name) in names where key.hasPrefix(prefix) { return name + key.dropFirst(prefix.count) }
        return key
    }

    /// The Greek article before a statute's name: "του ν." and "του π.δ.", but "της Υ.Α.".
    private static func greekGenitive(_ key: String) -> String {
        if key == labourCodeKey { return "του Κώδικα Εργατικού Δικαίου" }
        return (key.hasPrefix("MD:") ? "της " : "του ") + greekStatuteName(key)
    }

    /// The "how they combine" sentences in Greek, written by the program like the English ones.
    /// Translated, "Article 7 of Law 5239/2025 amended Article 194" came back with the English
    /// "modified" in the middle of the Greek (9 Nov 2026).
    static func combinationGreek(_ links: [CodeLink]) -> [String] {
        links.map { link in
            let genitive = greekGenitive(link.statuteKey)
            switch link.kind {
            case .amends:
                return "Το άρθρο \(link.article ?? "") \(genitive) τροποποίησε το άρθρο \(link.codeArticle) του Κώδικα Εργατικού Δικαίου· εφαρμόζεται το τροποποιημένο κείμενο."
            case .adds:
                return "Το άρθρο \(link.article ?? "") \(genitive) πρόσθεσε το άρθρο \(link.codeArticle) στον Κώδικα Εργατικού Δικαίου."
            case .appliesUnder:
                let subject = link.statuteKey.hasPrefix("MD:") ? "Η " : "Ο "
                return subject + greekStatuteName(link.statuteKey) + " εκδόθηκε κατ’ εξουσιοδότηση του άρθρου \(link.codeArticle) του Κώδικα Εργατικού Δικαίου και το εφαρμόζει."
            }
        }
    }

    /// The applicable law: each document with a section and the articles its passages head, then
    /// each Labour Code article a used link amends or adds (its passages were replaced by the
    /// amending article's, so it had no section of its own and was missing from the list).
    static func applicableLaw(_ sources: [Source], links: [CodeLink]) -> (english: String, greek: String) {
        var english: [String] = []
        var greek: [String] = []
        var codeArticles: [String] = []
        for source in sources {
            let articles = source.passages.compactMap { LegalCrossReferences.definedArticle(of: $0.chunk) }
                .map { String($0.dropFirst("ART:".count)) }
            let unique = articles.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            english.append(source.name + (unique.isEmpty ? "" : ", Article " + unique.joined(separator: ", Article ")))
            let greekName = source.statuteKey.map(greekStatuteName) ?? source.document
            let greekArticles = unique.isEmpty ? "" : (unique.count == 1 ? ", άρθρο " : ", άρθρα ") + unique.joined(separator: ", ")
            greek.append(greekName + greekArticles)
            if source.statuteKey == labourCodeKey { codeArticles += unique }
        }
        for link in links where link.kind != .appliesUnder && !codeArticles.contains(where: { sameArticle($0, link.codeArticle) }) {
            codeArticles.append(link.codeArticle)
            let verbEn = link.kind == .amends ? "as amended" : "as added"
            let verbEl = link.kind == .amends ? "όπως τροποποιήθηκε" : "όπως προστέθηκε"
            english.append("the Labour Code (Presidential Decree 62/2025), Article \(link.codeArticle) \(verbEn)")
            greek.append(greekStatuteName(labourCodeKey) + ", άρθρο \(link.codeArticle), \(verbEl)")
        }
        let english_ = english.joined(separator: "; ") + (english.isEmpty ? "" : ".")
        let greek_ = greek.joined(separator: "· ") + (greek.isEmpty ? "" : ".")
        return (english_, greek_)
    }

    /// Fixes the translator leaves in Greek legal text: a law's article («της Ν. 5239/2025» for
    /// «του ν. 5239/2025»), a repeated anchor («Άρθρο 7 (Άρθρο 7)»), a capital «Άρθρο» in the
    /// middle of a sentence, the nominative after «του» («του άρθρο 194»), English anchors, and
    /// mistranslated terms. Also applied to the statute summary.
    static func repairedGreek(_ text: String) -> String {
        var s = text
        let rules: [(String, String)] = [
            (#"(Άρθρ(?:ο|ου)\s+(\d{1,4}[Α-Ωα-ω]?))\s*\(\s*Άρθρ(?:ο|ου)\s+\2\s*\)"#, "$1"),
            (#"(?<![\p{L}])(?:της|η)\s+Ν\.\s*(\d{1,5}/\d{4})"#, "του ν. $1"),
            (#"(?<![\p{L}])(?:την|τη)\s+Ν\.\s*(\d{1,5}/\d{4})"#, "τον ν. $1"),
            (#"(?<![\p{L}])(στη|στην|στο)\s+Ν\.\s*(\d{1,5}/\d{4})"#, "στον ν. $2"),
            (#"(?<=[\p{Ll}\d,·;)]\s)Άρθρ(ο|ου|α|ων)(?=\s+\d)"#, "άρθρ$1"),
            (#"(?<=\()Άρθρ(ο|ου|α|ων)(?=\s+\d)"#, "άρθρ$1"),
            (#"(?<![\p{L}])(του|τον|στον|ο)\s+Ν\.\s*(\d{1,5}/\d{4})"#, "$1 ν. $2"),
            (#"(?<![\p{L}])(του|στου)\s+[Άά]ρθρο\s+(\d)"#, "$1 άρθρου $2"),
            // An English anchor the translator left: «υπό Article 141Α» (9 Nov 2026, the opinion
            // over three documents). "Under" a Code article is «κατ’ εξουσιοδότηση του άρθρου».
            (#"(?<![\p{L}])υπό\s+(?:το\s+)?Articles?\s+(\d{1,4}[\p{L}]?)(?![\p{L}\d])"#, "κατ’ εξουσιοδότηση του άρθρου $1"),
            (#"(?<![\p{L}])(του|στου)\s+Articles?\s+(\d{1,4}[\p{L}]?)(?![\p{L}\d])"#, "$1 άρθρου $2"),
            (#"(?m)(?:^|(?<=[.:]\s))Articles?\s+(?=\d)"#, "Άρθρο "),
            (#"(?<![\p{L}])Articles\s+(?=\d)"#, "άρθρα "),
            (#"(?<![\p{L}])Article\s+(?=\d)"#, "άρθρο "),
            // "The hourly wage" came back «ωριαίο ποσοστό» and «ωριαίο επιτόκιο» (an interest
            // rate); the Labour Code's term is «καταβαλλόμενο ωρομίσθιο» (9 Nov 2026). A participle
            // before it is absorbed: "the paid hourly wage" came back «καταβεβλημένο καταβαλλόμενο
            // ωρομίσθιο».
            (#"(?:\p{L}+(?:μένο|μενο)\s+)?ωριαίο\s+(?:ποσοστό|επιτόκιο|μισθό|ποσό)"#, "καταβαλλόμενο ωρομίσθιο"),
            (#"\p{L}+(?:μένο|μενο)\s+(?=καταβαλλόμενο\s+ωρομίσθιο)"#, ""),
            // The feminine variants: «με ισοτιμία ίση με την πληρωμένη ωριαία τιμή».
            (#"(?<![\p{L}])(?:την\s+)?(?:\p{L}+(?:μένη|μενη)\s+)?ωριαία\s+(?:τιμή|αμοιβή|αποζημίωση)(?![\p{L}])"#, "το καταβαλλόμενο ωρομίσθιο"),
            (#"(?<![\p{L}])με\s+ισοτιμία\s+ίση\s+με(?![\p{L}])"#, "με αμοιβή ίση με"),
            // «ο οποίος τροποποιεί άρθρο 194»: the article needs its «το».
            (#"(?<![\p{L}])(τροποποιεί|τροποποίησε|αντικαθιστά|αντικατέστησε|σύμφωνα\s+με|υπό)\s+άρθρο(?=\s+\d)"#, "$1 το άρθρο"),
            // "This increased rate" (of pay) came back «αυτό το αυξημένο τέλος», a fee.
            (#"(?<![\p{L}])αυτό\s+το\s+αυξημένο\s+τέλος(?![\p{L}])"#, "αυτή την αυξημένη αμοιβή"),
            (#"(?<![\p{L}])το\s+αυξημένο\s+τέλος(?![\p{L}])"#, "την αυξημένη αμοιβή"),
            // "Legal overtime" (the lawful kind) came back «νομικές υπερωρίες»: «νόμιμες».
            (#"(?<![\p{L}])([Νν])ομική(?=\s+υπερωρ)"#, "$1όμιμη"),
            (#"(?<![\p{L}])([Νν])ομικής(?=\s+υπερωρ)"#, "$1όμιμης"),
            (#"(?<![\p{L}])([Νν])ομικές(?=\s+υπερωρ)"#, "$1όμιμες"),
            (#"(?<![\p{L}])([Νν])ομικών(?=\s+υπερωρ)"#, "$1όμιμων"),
            // "The minutes" of a vote or count (Law 5278/2026, Article 7) came back «λεπτού» (a
            // minute of time) in its summary: «πρακτικά».
            (#"(?<![\p{L}])(?:του|των)\s+λεπτ(?:ού|ών)(?=\s+(?:του|της|των)\s+(?:ψηφοδελτ|ψηφοφορ|διαλογ|καταμέτρησ|συνεδρίασ|εκλογ))"#, "των πρακτικών"),
            (#"(?<![\p{L}])(?:Το|Τα)\s+λεπτ(?:ό|ά)(?=\s+(?:του|της|των)\s+(?:ψηφοδελτ|ψηφοφορ|διαλογ|καταμέτρησ|συνεδρίασ|εκλογ))"#, "Τα πρακτικά"),
            (#"(?<![\p{L}])(?:το|τα)\s+λεπτ(?:ό|ά)(?=\s+(?:του|της|των)\s+(?:ψηφοδελτ|ψηφοφορ|διαλογ|καταμέτρησ|συνεδρίασ|εκλογ))"#, "τα πρακτικά"),
            // "Election minutes" came back «εκλογικών λεπτών» in the rerun of the same summary.
            (#"(?<![\p{L}])(εκλογικ(?:ών|ού))\s+λεπτ(?:ών|ού)(?![\p{L}])"#, "εκλογικών πρακτικών"),
            (#"(?<![\p{L}])(εκλογικ(?:ά|ό))\s+λεπτ(?:ά|ό)(?![\p{L}])"#, "εκλογικά πρακτικά"),
            // "Expiry or termination" (of a contract) came back «τη λήξη ή τη λήξη»: termination
            // is «λύση».
            (#"(?<![\p{L}])(τη|της)\s+λήξη(ς?)\s+ή\s+(τη|της)\s+λήξη(ς?)(?![\p{L}])"#, "$1 λήξη$2 ή $3 λύση$4"),
            // "Normative (regulatory) terms" of a collective agreement are «κανονιστικοί όροι»; the
            // translator wrote «ρυθμιστικών όρων».
            (#"(?<![\p{L}])ρυθμιστικ(οί|ών|ούς)(?=\s+όρ)"#, "κανονιστικ$1"),
            (#"(?<![\p{L}])Ρυθμιστικ(οί|ών|ούς)(?=\s+όρ)"#, "Κανονιστικ$1"),
            // A phrase repeated around «και»: «τους εργαζόμενους και τους εργαζόμενους» (two English
            // words for employees came back as one Greek word).
            (#"(?<![\p{L}])((?:\p{L}+\s+){0,3}\p{L}+)\s+και\s+\1(?![\p{L}])"#, "$1"),
            // A limit on overtime came back «προθεσμία», a deadline.
            (#"Η\s+προθεσμία(?=\s+(?:για|των)\s+(?:τις\s+)?υπερωρ)"#, "Το όριο"),
            (#"(?<![\p{L}])η\s+προθεσμία(?=\s+(?:για|των)\s+(?:τις\s+)?υπερωρ)"#, "το όριο"),
        ]
        for (pattern, template) in rules {
            s = s.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        return capitalizingSentenceStarts(s)
    }

    /// A Greek sentence the translator started in lower case («… του Κώδικα. ισχύει ο …») gets its
    /// capital. Only after a word of four letters or more, so abbreviations («επ. του», «παρ.»,
    /// «π.χ.») are left alone.
    static func capitalizingSentenceStarts(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"(?<=\p{Ll}{4}[.!]\s)(\p{Ll})"#) else { return text }
        let ns = NSMutableString(string: text)
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
            let letter = ns.substring(with: match.range(at: 1))
            guard letter.unicodeScalars.allSatisfy({ (0x0370...0x03FF).contains($0.value) || (0x1F00...0x1FFF).contains($0.value) }) else { continue }
            ns.replaceCharacters(in: match.range(at: 1), with: letter.uppercased())
        }
        return ns as String
    }

    // MARK: Model calls

    /// The section call's instructions for one statute. A document without articles (a ministerial
    /// decision) is cited by its name alone.
    static func sectionInstructions(statute: String, hasArticles: Bool = true) -> String {
        let citation = hasArticles
            ? "Cite each rule as (Article N of \(statute)), with N from the passage's \"Article N\" heading."
            : "Cite each rule as (\(statute)); it has no articles, so do not write an article number."
        return """
        You help a Greek lawyer write a legal opinion. Use only the passages given, which come from \(statute). In two to four sentences, state what they provide on the question: the rules, any permitted limit or prohibition, their figures (amounts of money included) and time limits, and who and what situation they apply to. Do not extrapolate rules to people or situations the passages do not mention, and if a passage concerns a specific arrangement (such as work without Saturdays, the sixth day of the week, or minors), state that condition without extending it to general overtime. Do not refer to "the provisions in force" or "the applicable provisions" without naming them. \(citation) If the passages do not address the question, write only: Not addressed.
        """
    }

    /// Whether a source's passages carry article headings (a decision's are cut into parts).
    static func hasArticles(_ source: Source) -> Bool {
        source.passages.contains { LegalCrossReferences.definedArticle(of: $0.chunk) != nil }
    }

    /// A section of a document without articles, without the article numbers the model gave it:
    /// "(Article 1 of Ministerial Decision 8934)" → "(Ministerial Decision 8934)". The decision has
    /// no Article 1, so the article check dropped both its sentences, the €920 minimum wage with
    /// them (9 Nov 2026, the opinion over three documents).
    static func withoutInventedArticles(_ text: String, statute: String) -> String {
        let name = NSRegularExpression.escapedPattern(for: statute)
        let withoutNumbers = text.replacingOccurrences(
            of: #"\b(?:Article|Art\.)\s+\d{1,4}[A-Za-zΑ-Ω]?(?:\s*\([^)]*\))?\s*,?\s+of\s+(?:the\s+)?(?="# + name + ")",
            with: "", options: .regularExpression)
        // A sentence that starts with its citation, "(Ministerial Decision 8934) sets …", gets it
        // as its subject: it came back «(Υπουργική Απόφαση 8934) ορίζει».
        return withoutNumbers.replacingOccurrences(
            of: #"(?m)(^|(?<=[.!?]\s))\((\#(name))\)\s+(?=\p{Ll})"#, with: "$1$2 ", options: .regularExpression)
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

    /// The conclusion without its sentences that only restate a link ("The amended text of Article
    /// 194 of the Labour Code, as in force"): "How they combine" states each link in the program's
    /// own words, and the restatement came back from the translator without its verb (9 Nov 2026).
    /// A sentence is a restatement when it speaks of an amendment and has no figure other than the
    /// link's article and statute numbers. The conclusion is kept whole if nothing else would remain.
    static func withoutRestatedLinks(_ conclusion: String, links: [CodeLink]) -> String {
        guard !links.isEmpty else { return conclusion }
        var allowed = Set<String>()
        for link in links {
            allowed.formUnion(link.codeArticle.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty })
            allowed.formUnion((link.article ?? "").components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty })
            allowed.formUnion(link.statuteKey.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty })
        }
        allowed.formUnion(["62", "2025"])  // the Labour Code, Presidential Decree 62/2025
        let sentences = LocalNeuralTranslator.segments(conclusion)
        let kept = sentences.filter { sentence in
            guard sentence.lowercased().contains("amend") else { return true }
            let numbers = sentence.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
            return !numbers.allSatisfy { allowed.contains($0) }
        }
        return kept.isEmpty ? conclusion : kept.joined(separator: " ")
    }

    static let conclusionInstructions = """
        You write the conclusion of a Greek legal opinion. Use only the sections given. In two or three complete sentences, answer the question directly, citing the articles the sections cite. Where a later law amended an article of the Labour Code, apply the amended rule. When a statute provides for legal overtime or another act "up to" a stated daily limit and the question's amount does not exceed that limit, conclude that it is permitted up to that limit (and its stated annual limit); do not treat a ceiling for a different arrangement or special case (such as daily-hour shifting without Saturdays, the sixth day of the week, or minors) as overriding or prohibiting that general limit unless the question asks about that special case. Do not add advice or anything the sections don't say.
        """

    /// The passages are separated by a line, not numbered: numbered "[6]", the sixth passage of
    /// Article 7 of Law 5239/2025 was cited as "Article 6", and the article check dropped its four
    /// hours a day (EXPERIMENTS E14). Each passage starts with its own "Article N" heading.
    static func sectionPrompt(question: String, source: Source) -> String {
        let passages = source.passages.map(\.chunk.content).joined(separator: "\n\n---\n\n")
        return "Question: \(question)\nStatute: \(source.name)\n\nPassages:\n\(passages)"
    }

    // MARK: Writing

    static func write(
        question: String,
        questionEn: String,
        sources: [Source],
        links: [CodeLink],
        respond: (_ instructions: String, _ prompt: String) async throws -> String = { try await GreekLegalDocumentSummarizer.onDeviceResponse(instructions: $0, prompt: $1) },
        translate: (_ text: String, _ documentNames: [String]) async throws -> String = {
            try await LocalNeuralTranslator.shared.translateEnglishToGreekPreservingCitations($0, documentNames: $1)
        }
    ) async throws -> Opinion {
        // The sources' file names are kept as written through translation: without them only a
        // name without spaces is recognised, and «ΑΤΟΜΙΚΟ ΕΡΓΑΤΙΚΟ ΔΙΚΑΙΟ.pdf» came back «ΔΙΚΑΙΟ.pdf».
        let documentNames = sources.map(\.document)
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
            let articles = hasArticles(source)
            // A section the model declines is skipped, like a source that doesn't address the question.
            guard let draft = try await GreekLegalDocumentSummarizer.declinedAsNil({
                try await GreekLegalModelCall.respond(
                    instructions: sectionInstructions(statute: source.name, hasArticles: articles),
                    prompt: sectionPrompt(question: questionEn, source: source), label: "opinion section \(source.document)", respond: respond)
            }) else { continue }
            let trimmed = articles ? cleanedSection(draft) : withoutInventedArticles(cleanedSection(draft), statute: source.name)
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
            // A declined conclusion refuses the opinion with its own reason.
            guard let written = try await GreekLegalDocumentSummarizer.declinedAsNil({
                try await GreekLegalModelCall.respond(instructions: conclusionInstructions, prompt: prompt, label: "opinion conclusion", respond: respond)
            }) else {
                return Opinion(greek: "", english: "", sources: sources, links: links, dropped: dropped,
                               refusal: "the model declined to write the conclusion")
            }
            let draft = sections.map(\.source).filter { !hasArticles($0) }.reduce(cleanedConclusion(written)) {
                withoutInventedArticles($0, statute: $1.name)
            }
            let result = checked(withoutRestatedLinks(draft, links: usedLinks))
            dropped += result.dropped
            conclusion = result.text
        }
        if conclusion.isEmpty {
            return Opinion(greek: "", english: "", sources: sources, links: links, dropped: dropped,
                           refusal: sections.isEmpty ? "no document of the library addresses the question" : "the conclusion had no supported sentence")
        }

        let applicable = sources.filter { source in sections.contains { $0.source.document == source.document } }
        let law = applicableLaw(applicable, links: usedLinks)
        let lawText = law.english
        let englishParts: [(title: String, text: String)] = [
            ("Applicable law", lawText),
            ("What each provides", sections.map(\.text).joined(separator: "\n\n")),
            ("How they combine", usedCombination.joined(separator: " ")),
            ("Conclusion", conclusion),
        ].filter { !$0.text.isEmpty }
        let english = (["Question: " + questionEn] + englishParts.map { "\($0.title):\n\($0.text)" }).joined(separator: "\n\n")
        // The English and the dropped sentences are logged so a figure missing from the Greek
        // (the €920 minimum wage, 9 Nov 2026) can be traced to drafting, checking or translation.
        Log.info("[LegalOpinion] English opinion (\(english.count) chars): \(english.prefix(2_500))", category: .llm)
        if !dropped.isEmpty {
            Log.info("[LegalOpinion] Dropped \(dropped.count) sentence(s): \(dropped.joined(separator: " | "))", category: .llm)
        }

        let greekTitles = ["Applicable law": "Εφαρμοστέο δίκαιο", "What each provides": "Τι προβλέπει κάθε κείμενο",
                           "How they combine": "Πώς συνδυάζονται", "Conclusion": "Συμπέρασμα"]
        var greekParts = ["Ερώτημα\n" + question]
        for part in englishParts {
            // The applicable law and the links are the program's own sentences, written in Greek;
            // only the model's sections and conclusion go through the translator.
            let text: String
            switch part.title {
            case "Applicable law": text = law.greek
            case "How they combine": text = combinationGreek(usedLinks).joined(separator: " ")
            default:
                try Task.checkCancellation()
                text = repairedGreek((try? await translate(part.text, documentNames)) ?? part.text)
            }
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
        let searchQuestion = Writer.strippedOpinionFraming(question)
        let questionEn = await Self.greekQueryTranslation(searchQuestion) ?? searchQuestion
        let documents = await MainActor.run { self.documentsForContainer(containerId) }
        let database = try await dbForContainer(containerId)
        // Every document's passages, for its statute and the Code articles it amends (from all its
        // articles' headings, not only the retrieved ones).
        var allPassages: [String: [DocumentChunk]] = [:]
        var links: [Writer.CodeLink] = []
        var candidates: [Writer.Source] = []
        for document in documents {
            try Task.checkCancellation()
            let chunks = try await database.chunks(forDocument: document.id).sorted { $0.metadata.chunkIndex < $1.metadata.chunkIndex }
            let statuteKey = chunks.lazy.compactMap { $0.legal?.documentStatuteKey }.first
            allPassages[document.filename] = chunks
            links += Writer.codeLinks(statuteKey: statuteKey, passages: chunks)
            let passages = try await RAGQueryScope.$documentIds.withValue([document.id]) {
                try await self.searchDocumentsRaw(query: questionEn, originalQuery: searchQuestion, topK: 8, containerId: containerId)
            }
            // Ranked by score; the title page and contents state no rule (`droppingFrontMatter`).
            let ranked = LegalCrossReferences.droppingFrontMatter(passages, pool: chunks).sorted { $0.similarityScore > $1.similarityScore }
            candidates.append(.init(document: document.filename, statuteKey: statuteKey, passages: ranked))
        }
        // The Code's passages are cut to its best before the amended ones are replaced.
        candidates = candidates.map { .init(document: $0.document, statuteKey: $0.statuteKey, passages: Array($0.passages.prefix(Writer.passagesPerSource))) }
        candidates = Writer.replacingAmendedCodePassages(candidates, links: links, documents: allPassages)
        let sources = Writer.withWholeAmendingArticles(Writer.selectSources(candidates, links: links), links: links, documents: allPassages)
        let keptLinks = links.filter { link in
            sources.contains { source in
                source.statuteKey == link.statuteKey && (link.article == nil || source.passages.contains { passage in
                    LegalCrossReferences.definedArticle(of: passage.chunk).map { Writer.sameArticle($0, link.article ?? "") } ?? false
                })
            }
        }
        Log.info("[LegalOpinion] Sources: \(sources.map { "\($0.document) \(String(format: "%.2f", $0.bestScore)) \($0.passages.compactMap { LegalCrossReferences.definedArticle(of: $0.chunk) })" }); links: \(Writer.combination(keptLinks))", category: .retrieval)
        for source in sources {
            for passage in source.passages {
                Log.info("[LegalOpinion] Passage \(source.document) #\(passage.chunk.metadata.chunkIndex) \(String(format: "%.2f", passage.similarityScore)): \(passage.chunk.content.prefix(300).replacingOccurrences(of: "\n", with: " "))", category: .retrieval)
            }
        }
        return try await Writer.write(question: question, questionEn: questionEn, sources: sources, links: keptLinks)
    }
}
