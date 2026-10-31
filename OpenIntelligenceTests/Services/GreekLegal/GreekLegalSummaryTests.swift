//
//  GreekLegalSummaryTests.swift
//  OpenIntelligenceTests
//
//  Thesis fork (PoC capability 2): the summariser's grouping and checking with a stubbed model, and
//  an opt-in evaluation over `Benchmarks/GreekLabourLibrary/summary_v1.jsonl`:
//  `TEST_RUNNER_OI_GREEK_SUMMARY=1`, with `TEST_RUNNER_OI_GREEK_SUMMARY_SPLIT` `dev` (the default)
//  or `test`. It reads the documents from the five-document library that
//  `GreekConstitutionEvaluationTests` imports (`TEST_RUNNER_OI_GREEK_EVAL_SET=GreekLabourLibrary`),
//  so that run must have imported it. Reported per document: provisions covered, cited articles
//  present, sentences dropped as unsupported, time.
//

import Foundation
import FoundationModels
import Testing
@testable import OpenIntelligence

@Suite("Greek legal summary")
struct GreekLegalSummaryTests {
    static let filler = "The provision applies to every employer and employee of the sector covered by the agreement concerned."

    static let passages = [
        "LAW NO. 5278 National Social Agreement for collective labour agreements.",
        "Article 1 [Άρθρο 1]\nArticle 2 [Άρθρο 2]\nArticle 3 [Άρθρο 3]\nArticle 8 [Άρθρο 8]\nArticle 9 [Άρθρο 9]",
        "Article 8 [Άρθρο 8]\nAfter-effect of collective agreements\nThe normative terms of an expired agreement continue to apply for three (3) months. " + filler,
        "Article 8 [Άρθρο 8]\nAfter-effect of collective agreements\nAfter the three months all normative terms continue until a new agreement replaces them. " + filler,
        "Article 9 [Άρθρο 9]\nExtension of agreements\nAn agreement may be extended when the employers bound employ more than forty per cent (40%) of the employees of the sector. " + filler,
    ]

    @Test func articlesAreBuiltFromPassagesWithoutContentsOrTitlePage() {
        let articles = GreekLegalDocumentSummarizer.articles(from: Self.passages)
        #expect(articles.map(\.heading) == ["Article 8", "Article 9"])
        // The two passages of Article 8 make one text, its title once.
        let article8 = articles[0].text
        #expect(article8.components(separatedBy: "After-effect of collective agreements").count == 2, "\(article8)")
        #expect(article8.contains("three (3) months") && article8.contains("all normative terms continue"))
    }

    @Test func groupsFitTheLimitAndKeepTheOrder() {
        let articles = (1...12).map { GreekLegalDocumentSummarizer.ArticleText(heading: "Article \($0)", text: Array(repeating: Self.filler, count: 3).joined(separator: " ")) }
        let groups = GreekLegalDocumentSummarizer.groups(of: articles, limit: 1_000)
        #expect(groups.count >= 4)
        #expect(groups.allSatisfy { $0.count <= 1_000 })
        let order = groups.joined(separator: "\n\n").components(separatedBy: "\n").filter { $0.hasPrefix("=== Article ") }
        #expect(order == articles.map { "=== \($0.heading) ===" })
        // An article longer than the limit is cut into pieces that fit.
        let long = GreekLegalDocumentSummarizer.ArticleText(heading: "Article 99", text: Array(repeating: Self.filler, count: 30).joined(separator: " "))
        let pieces = GreekLegalDocumentSummarizer.groups(of: [long], limit: 1_000)
        #expect(pieces.allSatisfy { $0.count <= 1_000 })
        #expect(pieces.count > 1 && pieces.dropFirst().allSatisfy { $0.hasPrefix("=== Article 99 (continued) ===\n") })
        #expect(GreekLegalDocumentSummarizer.headings(inGroup: pieces[1]) == ["Article 99"])
    }

    @Test func notesKeepTheGroupsArticles() {
        // Dev summary 1: Article 9 of Law 5278 replaces Article 404 of the Labour Code, and the model
        // labelled the rule "Article 404". Dev summary 2: it echoed the === lines.
        let notes = """
            === Article 8 ===
            The normative terms continue for three (3) months after expiry.
            - Article 404: after the three months all normative terms continue until a new agreement.
            **Article 9:** extension needs employers employing more than forty per cent (40%) of the sector's employees, which is certified by the competent department of the Ministry, after a consultation of the parties before the Supreme Labour Council on competitiveness, employment and prices.
            Article 410: the mediator takes office within five days.
            """
        let cleaned = GreekLegalDocumentSummarizer.cleanedNotes(notes, headings: ["Article 8", "Article 9"], lines: 3)
        #expect(cleaned.map(\.article) == ["8", "8", "9"], "\(cleaned)")
        #expect(cleaned[0].text == "The normative terms continue for three (3) months after expiry.")
        #expect(cleaned[1].text == "after the three months all normative terms continue until a new agreement.")
        #expect(cleaned[2].text.hasPrefix("extension needs") && cleaned[2].text.count <= GreekLegalDocumentSummarizer.noteLineCharacters + 1)
        #expect(cleaned[2].text.hasSuffix("…") && cleaned[2].text.contains("(40%)"))
        #expect(GreekLegalDocumentSummarizer.linesPerGroup(articles: 1) == 3 && GreekLegalDocumentSummarizer.linesPerGroup(articles: 2) == 4
            && GreekLegalDocumentSummarizer.linesPerGroup(articles: 9) == 8)
    }

    @Test func provisionsAreOneBulletAnArticle() {
        typealias Note = GreekLegalDocumentSummarizer.Note
        let notes = [Note(article: "8", text: "Terms continue for three (3) months"), Note(article: "8", text: "Then all terms continue."),
                     Note(article: "8", text: "A third line left out."), Note(article: "9", text: "Extension above 40%.")]
        #expect(GreekLegalDocumentSummarizer.provisions(from: notes) == [
            "**Article 8:** Terms continue for three (3) months. Then all terms continue.",
            "**Article 9:** Extension above 40%.",
        ])
        // Twenty articles: the twelve with the most notes, in the document's order.
        let many = (1...20).map { Note(article: "\($0)", text: String(repeating: "word ", count: $0 % 7 + 3)) }
        let bullets = GreekLegalDocumentSummarizer.provisions(from: many)
        #expect(bullets.count == 12)
        let numbers = bullets.compactMap { Int($0.dropFirst("**Article ".count).prefix { $0.isNumber }) }
        #expect(numbers == numbers.sorted() && !numbers.contains(7) && numbers.contains(6))
    }

    /// A document without articles (a ministerial decision) is noted by parts, and its bullets
    /// carry no part label.
    @Test func aDocumentWithoutArticlesIsSummarizedByParts() async throws {
        let passages = (1...6).map { "Point \($0). " + String(repeating: "The minimum wage applies to every employee of the private sector. ", count: 18) }
        #expect(GreekLegalDocumentSummarizer.articles(from: passages).isEmpty)
        let parts = GreekLegalDocumentSummarizer.parts(from: passages)
        #expect(parts.count > 1 && parts.map(\.heading).first == "Part 1")
        #expect(parts.allSatisfy { $0.text.count <= GreekLegalDocumentSummarizer.partCharacters })
        // Every passage, trimmed, in order.
        #expect(parts.map(\.text).joined(separator: "\n") == passages.map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n"))
        let notes = GreekLegalDocumentSummarizer.cleanedNotes(
            "=== Part 2 ===\nPart 2: The minimum wage applies to every private-sector employee.", headings: ["Part 1", "Part 2"], lines: 4)
        #expect(notes == [.init(article: "2", text: "The minimum wage applies to every private-sector employee.")])
        #expect(GreekLegalDocumentSummarizer.provisions(from: notes, label: nil) == ["The minimum wage applies to every private-sector employee."])

        let summary = try await GreekLegalDocumentSummarizer.summarize(
            passages: passages, statuteKey: "MD:8934",
            respond: { instructions, prompt in
                instructions == GreekLegalDocumentSummarizer.mapInstructions(lines: 6, parts: true) && prompt.contains("=== Part 2 ===\n")
                    ? "Part 1: The minimum wage applies to every private-sector employee."
                    : "The decision sets the minimum wage."
            },
            translate: { $0 })
        #expect(summary.groups == 1)
        #expect(summary.english == "The decision sets the minimum wage.\n\nMain provisions:\n\nThe minimum wage applies to every private-sector employee.")
    }

    @Test func unsupportedFiguresAndForeignArticlesAreDropped() {
        let articles = GreekLegalDocumentSummarizer.articles(from: Self.passages)
        let draft = """
            Law 5278/2026 strengthens sector-wide collective agreements.
            Main provisions:
            - Article 8: the normative terms continue for three (3) months, then all of them until a new agreement.
            - Article 9: extension needs employers employing more than 40% of the sector's employees.
            - Article 9: the threshold was 55% before.
            - Article 77 of Law 1234/2020 is repealed.
            """
        let (text, dropped) = GreekLegalDocumentSummarizer.droppingUnsupported(
            draft, passages: Self.passages, articles: articles, statuteKey: "LAW:5278/2026")
        #expect(text.contains("Law 5278/2026 strengthens"), "the document's own statute is supported")
        #expect(text.contains("Main provisions:"))
        #expect(text.contains("more than 40%") && text.contains("three (3) months"), "\(text)")
        #expect(!text.contains("55%") && !text.contains("1234/2020"), "\(text)")
        #expect(dropped.count == 2, "\(dropped)")
    }

    @Test func mapThenReduceThenTranslate() async throws {
        actor Calls { var prompts: [(String, String)] = []; func add(_ i: String, _ p: String) { prompts.append((i, p)) } }
        let calls = Calls()
        let summary = try await GreekLegalDocumentSummarizer.summarize(
            passages: Self.passages, statuteKey: "LAW:5278/2026",
            respond: { instructions, prompt in
                await calls.add(instructions, prompt)
                return instructions == GreekLegalDocumentSummarizer.reduceInstructions
                    ? "Law 5278/2026 is about collective agreements.\nMain provisions:\n- Article 9: extension above 40%."
                    : "Article 8: terms continue for three (3) months.\nArticle 9: extension above 40%."
            },
            translate: { "EL " + $0 })
        let prompts = await calls.prompts
        #expect(prompts.count == 2, "one group and the summary")
        #expect(prompts[0].1.hasPrefix("Statute: Law 5278/2026") && prompts[0].1.contains("=== Article 9 ===\n"))
        #expect(prompts[0].0 == GreekLegalDocumentSummarizer.mapInstructions(lines: 4))
        #expect(prompts[1].0 == GreekLegalDocumentSummarizer.reduceInstructions && prompts[1].1.contains("Article 8: terms continue"))
        #expect(summary.greek.hasPrefix("EL Law 5278/2026") && summary.groups == 1 && summary.dropped.isEmpty)
        // The opening is the model's; the provisions come from the notes, not from its list.
        #expect(summary.english == """
            Law 5278/2026 is about collective agreements.

            Main provisions:

            **Article 8:** terms continue for three (3) months.

            **Article 9:** extension above 40%.
            """, "\(summary.english)")
    }
}

/// One document of the summary set.
private struct SummaryCase: Decodable {
    struct Provision: Decodable {
        let name: String
        let pattern: String
    }

    let id: Int
    let document: String
    let statute: String
    let split: String
    let provisions: [Provision]
    let articles: [Int]
}

@Suite("Greek legal summary evaluation", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["OI_GREEK_SUMMARY"] == "1"))
@MainActor
struct GreekLegalSummaryEvaluation {
    @available(iOS 27.0, macOS 27.0, *)
    @Test(.timeLimit(.minutes(60)))
    func summarySet() async throws {
        let split = ProcessInfo.processInfo.environment["OI_GREEK_SUMMARY_SPLIT"] ?? "dev"
        let file = GreekEvalCase.repository.appendingPathComponent("Benchmarks/GreekLabourLibrary/summary_v1.jsonl")
        let cases = try String(contentsOf: file, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.hasPrefix("//") && !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { try JSONDecoder().decode(SummaryCase.self, from: Data($0.utf8)) }
            .filter { $0.split == split }
        for _ in 0..<60 where !SystemLanguageModel.default.isAvailable {
            try await Task.sleep(for: .seconds(5))
        }
        try #require(LocalNeuralTranslator.isAvailable(.englishToGreek))

        let plan = UserDefaults(suiteName: "GreekConstitutionEvaluation.plan") ?? .standard
        let store = EntitlementStore(billingService: StoreKitBillingService(), defaults: plan)
        let libraries = IntentSupport.libraries()
        let engine = RAGService(llmService: GreekEvalOnDeviceModel(), containerService: libraries, entitlementStore: store)
        for _ in 0..<100 where !engine.hasLoadedDocumentsFromDisk {
            try await Task.sleep(for: .milliseconds(100))
        }
        let libraryName = try #require(GreekEvalSet.all["GreekLabourLibrary"]).libraryName(corpus: "library")
        let library = try #require(libraries.containers.first { $0.name == libraryName }, "import the library first")
        let database = try await engine.dbForContainer(library.id)

        var covered = 0, total = 0
        for summaryCase in cases {
            let document = try #require(engine.documents.first { $0.containerId == library.id && $0.filename == summaryCase.document })
            let chunks = try await database.chunks(forDocument: document.id).sorted { $0.metadata.chunkIndex < $1.metadata.chunkIndex }
            let statuteKey = chunks.lazy.compactMap { $0.legal?.documentStatuteKey }.first
            let started = Date()
            let summary = try await GreekLegalDocumentSummarizer.summarize(passages: chunks.map(\.content), statuteKey: statuteKey)
            let seconds = Int(Date().timeIntervalSince(started))
            let folded = GreekEvalCase.fold(summary.greek)
            let missing = summaryCase.provisions.filter { folded.range(of: GreekEvalCase.fold($0.pattern), options: .regularExpression) == nil }
            let cited = summaryCase.articles.filter { folded.range(of: #"αρθρ\w*\s+\#($0)\b"#, options: .regularExpression) != nil }
            covered += summaryCase.provisions.count - missing.count
            total += summaryCase.provisions.count
            print("[GreekSummary] document \(summaryCase.document) statute=\(statuteKey ?? "-") passages=\(chunks.count) groups=\(summary.groups) notes=\(summary.noteCharacters) chars, \(seconds) s")
            print("[GreekSummary]   English:\n\(summary.english)")
            print("[GreekSummary]   Greek:\n\(summary.greek)")
            print("[GreekSummary]   dropped: \(summary.dropped)")
            print("[GreekSummary] | \(summaryCase.id) | \(summaryCase.split) | provisions \(summaryCase.provisions.count - missing.count) of \(summaryCase.provisions.count) | articles cited \(cited.count) of \(summaryCase.articles.count) | dropped \(summary.dropped.count) | missing: \(missing.map(\.name)) |")
        }
        print("[GreekSummary] summary split=\(split): provisions covered \(covered) of \(total)")
        #expect(!cases.isEmpty)
    }
}
