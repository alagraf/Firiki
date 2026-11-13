//
//  EUHoldoutEvaluationTests.swift
//  OpenIntelligenceTests
//
//  Thesis fork: the holdout before/after evaluation (Chapter 6). The app developer's EU labour-law
//  test (`/Users/alagra/Documents/thesis/rag-tests/eu_data.json`: 11 articles of three EU directives
//  in the official English and Greek, 16 questions, 13 answered by the text and 3 not) run through
//  the whole app: each passage is imported as a document of its own, and each question goes through
//  `RAGService.query` the way a user's question does (a Greek question in Greek legal mode, i.e.
//  translated to English and the verified answer translated back).
//
//  HOLDOUT (AGENTS.md step 5): a measurement only. The data file is read where it is, never copied
//  into the repository; nothing in the app is changed because of what these answers say.
//
//  Conditions, as in the developer's `ragtests.swift`: English passages with English questions,
//  Greek passages with English questions, Greek passages with Greek questions (`q_el`, graded by
//  `any_el`). Graded the same way: an answer is right when it holds one of the question's `any`
//  terms as a whole word (`any_el` as a term for Greek answers); a question with no answer in the
//  text (`passage` 0) counts as declined when the app abstains. Also reported: the right passage
//  among the retrieved ones, and answerable questions the app declined.
//
//  Opt-in: `TEST_RUNNER_OI_EU_HOLDOUT=1`; `TEST_RUNNER_OI_EU_HOLDOUT_REIMPORT=1` imports the
//  passages again; `TEST_RUNNER_OI_EU_HOLDOUT_DATA` points at another copy of the data file.
//

import Foundation
import FoundationModels
import Testing

@testable import OpenIntelligence

private struct EUHoldoutData: Decodable {
    struct Question: Decodable {
        let q: String
        let passage: Int
        let any: [String]?
        let q_el: String?
        let any_el: [String]?
    }
    let passages_en: [String]
    let passages_el: [String]
    let questions: [Question]
}

@Suite(
    "EU labour-law holdout, whole app path",
    .enabled(if: ProcessInfo.processInfo.environment["OI_EU_HOLDOUT"] == "1"))
@MainActor
struct EUHoldoutEvaluationTests {
    static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

    /// The developer's whole-word check: "4" does not match "24".
    static func hasWord(_ text: String, _ word: String) -> Bool {
        let pattern = "(?<![0-9A-Za-z])" + NSRegularExpression.escapedPattern(for: word.lowercased()) + "(?![0-9A-Za-z])"
        return text.lowercased().range(of: pattern, options: .regularExpression) != nil
    }

    /// The developer's Greek check: the term starts a word (a number is a whole word).
    static func hasTerm(_ text: String, _ term: String) -> Bool {
        let closed = term.allSatisfy(\.isNumber)
        let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: term.lowercased()) + (closed ? "(?![\\p{L}\\p{N}])" : "")
        return text.lowercased().range(of: pattern, options: .regularExpression) != nil
    }

    /// The app declined: Greek legal review abstained, an abstention or not-found text, or no
    /// generation at all.
    static func declined(_ response: RAGResponse) -> Bool {
        let answer = response.generatedResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        return response.metadata.legalReview?.abstained == true
            || answer == LegalVerificationPolicy.greekAbstentionMessage
            || answer == LegalVerificationPolicy.englishAbstentionMessage
            || response.metadata.modelUsed == "none"
            || GreekLegalAnswerFinalizer.isPipelineFailureText(answer)
            || GreekLegalAnswerFinalizer.declaresMissingEvidence(answer)
            || answer.lowercased().hasPrefix("i want to stay grounded")
    }

    @available(iOS 27.0, macOS 27.0, *)
    @Test(.timeLimit(.minutes(90)))
    func euHoldout() async throws {
        for _ in 0..<60 where !SystemLanguageModel.default.isAvailable {
            try await Task.sleep(for: .seconds(5))
        }
        let model = SystemLanguageModel.default
        print("[EUHoldout] model: \(model.variant.displayName), window \(model.contextSize), availability \(model.availability)")

        let environment = ProcessInfo.processInfo.environment
        let dataURL = environment["OI_EU_HOLDOUT_DATA"].map(URL.init(fileURLWithPath:))
            ?? Self.repository.deletingLastPathComponent().appendingPathComponent("rag-tests/eu_data.json")
        let data = try JSONDecoder().decode(EUHoldoutData.self, from: Data(contentsOf: dataURL))
        try #require(data.passages_en.count == data.passages_el.count && !data.questions.isEmpty)

        let libraries = IntentSupport.libraries()
        let engine = RAGService(llmService: GreekEvalOnDeviceModel(), containerService: libraries)
        for _ in 0..<100 where !engine.hasLoadedDocumentsFromDisk {
            try await Task.sleep(for: .milliseconds(100))
        }

        // One library per passage language, one document per passage ("EU passage 3.txt").
        let reimport = environment["OI_EU_HOLDOUT_REIMPORT"] == "1"
        var libraryIds: [String: UUID] = [:]
        for (language, passages) in [("en", data.passages_en), ("el", data.passages_el)] {
            let name = "EU holdout (\(language))"
            var library = libraries.containers.first { $0.name == name }
            let complete = library.map { existing in
                engine.documents.filter { $0.containerId == existing.id && $0.totalChunks > 0 }.count == passages.count
            } ?? false
            if let existing = library, reimport || !complete {
                for document in engine.documents where document.containerId == existing.id {
                    try? await engine.removeDocument(document)
                }
                libraries.deleteContainer(id: existing.id)
                library = nil
            }
            if library == nil {
                let created = Result { try libraries.createContainer(name: name) }
                let made = try created.get()
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("eu-holdout-\(language)", isDirectory: true)
                try? FileManager.default.removeItem(at: folder)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let files = try passages.enumerated().map { index, text in
                    let url = folder.appendingPathComponent("EU passage \(index + 1).txt")
                    try text.write(to: url, atomically: true, encoding: .utf8)
                    return url
                }
                let started = Date()
                let imported = await engine.ingestDocuments(files, containerId: made.id)
                print("[EUHoldout] imported \(imported.successCount) \(language) passages in \(Int(Date().timeIntervalSince(started))) s")
                try #require(imported.successCount == passages.count)
                library = made
            }
            libraryIds[language] = try #require(library?.id)
        }
        let cleared = await SQLiteFullTextService.shared.deleteAllCachedQueries()
        print("[EUHoldout] cleared \(cleared) cached searches")

        let documentNames = Dictionary(engine.documents.map { ($0.id, $0.filename) }, uniquingKeysWith: { first, _ in first })
        var summary: [String] = []
        for (label, passageLanguage, greekQuestions) in [
            ("English passages, English questions", "en", false),
            ("Greek passages, English questions", "el", false),
            ("Greek passages, Greek questions", "el", true),
        ] {
            let libraryId = try #require(libraryIds[passageLanguage])
            var right = 0, answerable = 0, declinedNoAnswer = 0, unanswerable = 0, retrieved = 0, falseDeclines = 0, errors = 0
            for (index, item) in data.questions.enumerated() {
                let question = greekQuestions ? (item.q_el ?? item.q) : item.q
                let tag = String(format: "Q%02d", index + 1)
                if item.passage == 0 { unanswerable += 1 } else { answerable += 1 }
                let response: RAGResponse
                do {
                    response = try await engine.query(question, topK: 5, containerId: libraryId, qualityModeOverride: .standard)
                } catch {
                    errors += 1
                    print("[EUHoldout] \(label) \(tag) ERROR \(error.localizedDescription)")
                    continue
                }
                let answer = response.generatedResponse
                let didDecline = Self.declined(response)
                if item.passage == 0 {
                    if didDecline { declinedNoAnswer += 1 }
                    print("[EUHoldout] \(label) \(tag) no answer in the text: \(didDecline ? "declined" : "ANSWERED ANYWAY") | \(answer.replacingOccurrences(of: "\n", with: " "))")
                    continue
                }
                // The second library's files are renamed on import ("EU passage 3-2.txt").
                let wanted = #"^EU passage "# + String(item.passage) + #"(-\d+)?\.txt$"#
                let hit = response.retrievedChunks.contains {
                    (documentNames[$0.chunk.documentId] ?? $0.sourceDocument).range(of: wanted, options: .regularExpression) != nil
                }
                if hit { retrieved += 1 }
                if didDecline { falseDeclines += 1 }
                let terms = greekQuestions ? (item.any_el ?? []) : (item.any ?? [])
                let ok = !didDecline && (terms.isEmpty || terms.contains { greekQuestions ? Self.hasTerm(answer, $0) : Self.hasWord(answer, $0) })
                if ok { right += 1 }
                print("[EUHoldout] \(label) \(tag) passage \(hit ? "retrieved" : "NOT RETRIEVED") | answer \(ok ? "looks right" : didDecline ? "DECLINED" : "LOOKS WRONG") | \(answer.replacingOccurrences(of: "\n", with: " "))")
            }
            let line = "\(label): \(right) of \(answerable) answers look right, right passage retrieved \(retrieved) of \(answerable), declined \(declinedNoAnswer) of \(unanswerable) questions that have no answer, declined \(falseDeclines) answerable, errors \(errors)"
            summary.append(line)
            print("[EUHoldout] SUMMARY \(line)")
        }
        for line in summary { print("[EUHoldout] RESULT \(line)") }
    }
}
