//
//  GreekLegalChatRouterTests.swift
//  FirikiTests
//
//  Thesis fork: unit tests for chat capability routing (statute summary,
//  legal opinion, contract template routing vs standard Q&A).
//

import Foundation
import Testing
@testable import Firiki

@Suite("Greek Legal Chat Capability Router")
struct GreekLegalChatRouterTests {

    // MARK: - Intent Detection

    @Test func detectContractTemplateIntentInGreekAndEnglish() {
        let greekQueries = [
            "Ποιο υπόδειγμα σύμβασης ταιριάζει για μερική απασχόληση;",
            "Ποιο πρότυπο σύμβασης εργασίας να χρησιμοποιήσω;",
            "Χρειάζομαι ένα υπόδειγμα σύμβασης για τηλεργασία",
            "Υποδείγματα συμβάσεων για έκτακτες ανάγκες",
            // Typed without accents or in capitals (14 Nov 2026).
            "ποιο υποδειγμα συμβασης ταιριαζει για τηλεργασια;",
            "ΠΟΙΟ ΥΠΟΔΕΙΓΜΑ ΣΥΜΒΑΣΗΣ ΓΙΑ ΜΑΘΗΤΕΙΑ;",
        ]
        for query in greekQueries {
            let intent = GreekLegalChatRouter.detectIntent(query)
            if case .contractRouting = intent {
                // Pass
            } else {
                Issue.record("Expected .contractRouting for '\(query)', got \(intent)")
            }
        }

        let englishQueries = [
            "Which contract template should I use for a remote employee?",
            "Can you suggest a contract template for internship?",
            "What labour contract template fits unpredictable hours?"
        ]
        for query in englishQueries {
            let intent = GreekLegalChatRouter.detectIntent(query)
            if case .contractRouting = intent {
                // Pass
            } else {
                Issue.record("Expected .contractRouting for '\(query)', got \(intent)")
            }
        }
    }

    @Test func detectLegalOpinionIntentInGreekAndEnglish() {
        let greekQueries = [
            "Γνωμοδότηση για την καταβολή αποζημίωσης απόλυσης",
            "Θέλω μια νομική άποψη για τις υπερωρίες",
            "Γνωμοδοτικό σημείωμα σχετικά με το δικαίωμα αποσύνδεσης",
            "Νομική συμβουλή για την κατάτμηση της ετήσιας άδειας"
        ]
        for query in greekQueries {
            let intent = GreekLegalChatRouter.detectIntent(query)
            if case .legalOpinion = intent {
                // Pass
            } else {
                Issue.record("Expected .legalOpinion for '\(query)', got \(intent)")
            }
        }

        let englishQueries = [
            "Please provide a legal opinion on dismissal compensation",
            "Write a formal memorandum analyzing telework health and safety",
            "Legal opinion regarding probationary period termination"
        ]
        for query in englishQueries {
            let intent = GreekLegalChatRouter.detectIntent(query)
            if case .legalOpinion = intent {
                // Pass
            } else {
                Issue.record("Expected .legalOpinion for '\(query)', got \(intent)")
            }
        }
    }

    @Test func detectStatuteSummaryIntentInGreekAndEnglish() {
        let greekQueries = [
            "Σύνοψε το ν. 5278/2026",
            "Κάνε μια σύνοψη του εγγράφου",
            "Περίληψη του Π.Δ. 62/2025",
            "Συνοψίστε τις βασικές διατάξεις του νόμου"
        ]
        for query in greekQueries {
            let intent = GreekLegalChatRouter.detectIntent(query)
            if case .statuteSummary = intent {
                // Pass
            } else {
                Issue.record("Expected .statuteSummary for '\(query)', got \(intent)")
            }
        }

        let englishQueries = [
            "Summarize the document",
            "Give me a summary of law 5278/2026",
            "Digest of decree 62/2025"
        ]
        for query in englishQueries {
            let intent = GreekLegalChatRouter.detectIntent(query)
            if case .statuteSummary = intent {
                // Pass
            } else {
                Issue.record("Expected .statuteSummary for '\(query)', got \(intent)")
            }
        }
    }

    @Test func fallbackToStandardQA() {
        let queries = [
            "Πόσες ημέρες άδειας δικαιούμαι τον πρώτο χρόνο εργασίας;",
            "Τι ισχύει για την υπερεργασία;",
            "What is the statutory notice period for termination?",
            "Ποιο είναι το νόμιμο κατώτατο ημερομίσθιο;",
            // A question about what the law provides, not a template request (until 14 Nov 2026
            // this one opened a template).
            "Ποια σύμβαση εργασίας προβλέπεται για μαθητεία;",
        ]
        for query in queries {
            let intent = GreekLegalChatRouter.detectIntent(query)
            #expect(intent == .standardQA(query: query))
        }
    }

    /// Ordinary questions that the first rules sent to a capability (POC_PROGRESS.md, 14 Nov 2026).
    @Test(arguments: [
        "Τι ισχύει για τη σύμβαση εργασίας για ορισμένο χρόνο;",
        "Ποια σύμβαση καταγγέλλεται χωρίς αποζημίωση;",
        "Can an employer change a labour contract unilaterally?",
        "In your opinion, how many days of paternity leave apply?",
        "Δώσε μου μια περίληψη των δικαιωμάτων της εγκύου εργαζόμενης",
        "Χρειάζεται γραπτή σύμβαση για μερική απασχόληση;",
        "Do I need a written contract for part-time work?",
    ])
    func ordinaryQuestionsStayQuestions(_ query: String) {
        #expect(GreekLegalChatRouter.detectIntent(query) == .standardQA(query: query))
    }

    @Test(arguments: [
        ("συνοψη του ν. 5278/2026", "5278/2026"),
        ("ΣΥΝΟΨΗ ΤΟΥ Ν. 5278/2026", "5278/2026"),
        ("περιληψη του π.δ. 62/2025", "62/2025"),
        ("Σύνοψε το ν. 5239", "5239"),
    ])
    func unaccentedSummaryRequests(_ query: String, _ target: String) {
        #expect(GreekLegalChatRouter.detectIntent(query) == .statuteSummary(documentQuery: target))
    }

    @Test(arguments: ["ΘΕΛΩ ΓΝΩΜΟΔΟΤΗΣΗ ΓΙΑ ΥΠΕΡΩΡΙΕΣ", "γνωμοδοτηση για την αποζημιωση απολυσης"])
    func unaccentedOpinionRequests(_ query: String) {
        #expect(GreekLegalChatRouter.detectIntent(query) == .legalOpinion(question: query))
    }

    /// Described hiring arrangements try the templates and fall back to Q&A when none fits.
    @Test(arguments: [
        "Θέλω να πάρω μια φοιτήτρια για τέσσερις ώρες κάθε απόγευμα στο κατάστημα.",
        "I need someone for six months to help with the end-of-year rush, then the job ends.",
        "Hybrid arrangement: three days at home, two at the office. Which contract?",
    ])
    func describedArrangementsTryTemplates(_ query: String) {
        #expect(GreekLegalChatRouter.detectIntent(query) == .possibleContractRouting(terms: query))
    }

    // MARK: - Question sets (dev splits only)

    private static func devRows(_ path: String) throws -> [[String: Any]] {
        let file = GreekEvalCase.repository.appendingPathComponent(path)
        return try String(contentsOf: file, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.hasPrefix("//") && !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .compactMap { try JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
            .filter { $0["split"] as? String == "dev" }
    }

    /// Of the 40 template requests of the routing dev split, 38 reached a template in the
    /// prototype of 14 Nov 2026 (0 with the first rules); the 4 "none" questions stay Q&A.
    @Test func routingDevSplitIsRecognised() throws {
        let rows = try Self.devRows("Benchmarks/LabourContractTemplates/routing_v1.jsonl")
        try #require(rows.count == 44)
        var recognised = 0
        for row in rows {
            let prompt = try #require(row["prompt"] as? String)
            let intent = GreekLegalChatRouter.detectIntent(prompt)
            if row["template"] as? String == "none" {
                #expect(intent == .standardQA(query: prompt), "\(prompt)")
            } else if case .contractRouting = intent {
                recognised += 1
            } else if case .possibleContractRouting = intent {
                recognised += 1
            } else {
                print("[ChatRouter] not recognised: \(prompt)")
            }
        }
        print("[ChatRouter] routing dev: \(recognised) of 40 template requests recognised")
        #expect(recognised >= 38)
    }

    /// Every Labour Code, library and opinion dev question stays a question (or an opinion).
    @Test(arguments: [
        "Benchmarks/GreekLabourCode/labour_qa_v1.jsonl",
        "Benchmarks/GreekLabourLibrary/library_qa_v1.jsonl",
        "Benchmarks/GreekLabourLibrary/opinion_qa_v1.jsonl",
    ])
    func devQuestionsAreNotSentToCapabilities(_ path: String) throws {
        let rows = try Self.devRows(path)
        try #require(!rows.isEmpty)
        for row in rows {
            let question = try #require(row["question"] as? String)
            switch GreekLegalChatRouter.detectIntent(question) {
            case .standardQA, .legalOpinion: break
            case let other: Issue.record("\(path): \(question) → \(other)")
            }
        }
    }

    // MARK: - Messages

    @Test func failureMessagesNeverShowTheTechnicalError() {
        struct Opaque: LocalizedError { var errorDescription: String? { "FoundationModels internal 0x1F" } }
        let errors: [Error] = [
            Opaque(),
            CancellationError(),
            LocalNeuralTranslator.TranslatorError.modelsMissing(.englishToGreek),
            LocalNeuralTranslator.TranslatorError.unexpectedOutput("encoder"),
        ]
        for error in errors {
            for task in [GreekLegalChatRouter.CapabilityTask.summary, .opinion, .template] {
                let greek = GreekLegalChatRouter.failureMessage(for: error, greek: true, task: task)
                let english = GreekLegalChatRouter.failureMessage(for: error, greek: false, task: task)
                #expect(!greek.contains("0x1F") && !english.contains("0x1F"))
                #expect(!greek.contains("opus-mt") && !greek.contains("encoder"))
                #expect(GreekLegalEntityMasker.greekLetterRatio(greek) >= 0.3, "\(greek)")
                #expect(GreekLegalEntityMasker.greekLetterRatio(english) < 0.3, "\(english)")
            }
        }
    }

    @Test func opinionRefusalsHaveAGreekReason() {
        func opinion(_ refusal: String?) -> GreekLegalOpinionWriter.Opinion {
            GreekLegalOpinionWriter.Opinion(greek: "", english: "", sources: [], links: [], dropped: [], refusal: refusal)
        }
        #expect(opinion(nil).refusalGreek == nil)
        for reason in ["no document of the library addresses the question", "the conclusion had no supported sentence", "other"] {
            #expect(GreekLegalEntityMasker.greekLetterRatio(opinion(reason).refusalGreek ?? "") >= 0.3)
        }
    }

    // MARK: - Document Target Extraction

    @Test func extractDocumentTargetFromPrompt() {
        #expect(GreekLegalChatRouter.extractDocumentTarget(from: "Σύνοψε το ν. 5278/2026") == "5278/2026")
        #expect(GreekLegalChatRouter.extractDocumentTarget(from: "Σύνοψη του Π.Δ. 62/2025") == "62/2025")
        #expect(GreekLegalChatRouter.extractDocumentTarget(from: "Περίληψη του νόμου 4808/2021") == "4808/2021")
        #expect(GreekLegalChatRouter.extractDocumentTarget(from: "Summarize law 5278/2026") == "5278/2026")
        #expect(GreekLegalChatRouter.extractDocumentTarget(from: "Σύνοψε το έγγραφο") == nil)
        #expect(GreekLegalChatRouter.extractDocumentTarget(from: "σύνοψη του ν. 62/2025") == "62/2025")
        #expect(GreekLegalChatRouter.extractDocumentTarget(from: "σύνοψη του νόμου 5239") == "5239")
    }

    // MARK: - Document Matching

    /// A library of the demo documents: (filename, statute key read at import).
    private static func library(_ files: [(String, String?)]) -> (documents: [Document], keys: [UUID: String]) {
        let documents = files.map { Document(filename: $0.0, fileURL: URL(fileURLWithPath: "/tmp/" + $0.0), contentType: .pdf) }
        var keys: [UUID: String] = [:]
        for (document, file) in zip(documents, files) { keys[document.id] = file.1 }
        return (documents, keys)
    }

    /// The five demo documents under their real filenames.
    private static let demoFiles: [(String, String?)] = [
        ("pd_62_2025_fek_a121.pdf", "PD:62/2025"),
        ("n_5239_2025_fek_a178.pdf", "LAW:5239/2025"),
        ("n_5278_2026_fek_a22.pdf", "LAW:5278/2026"),
        ("n_5316_2026_fek_a105.pdf", "LAW:5316/2026"),
        ("ya_8934_2026_fek_b1759.pdf", "MD:8934"),
    ]

    /// The same documents saved under names without their numbers.
    private static let renamedFiles: [(String, String?)] = [
        ("Κώδικας Εργατικού Δικαίου.pdf", "PD:62/2025"),
        ("ΦΕΚ Α 178.pdf", "LAW:5239/2025"),
        ("ΦΕΚ Α 22.pdf", "LAW:5278/2026"),
        ("ΦΕΚ Α 105.pdf", "LAW:5316/2026"),
        ("ΦΕΚ Β 1759.pdf", "MD:8934"),
    ]

    private static func summaryTarget(_ request: String, _ files: [(String, String?)]) -> GreekLegalChatRouter.SummaryTarget {
        let (documents, keys) = library(files)
        return GreekLegalChatRouter.matchDocument(
            query: request,
            target: GreekLegalChatRouter.extractDocumentTarget(from: request),
            in: documents,
            statuteKeys: keys
        )
    }

    private static func matchedFile(_ request: String, _ files: [(String, String?)]) -> String? {
        if case .document(let document) = summaryTarget(request, files) { return document.filename }
        return nil
    }

    @Test(arguments: [
        ("σύνοψη του ν. 5278/2026", 2),
        ("Σύνοψη του Π.Δ. 62/2025", 0),
        ("περίληψη της Υ.Α. 8934/2026", 4),
        ("σύνοψη του νόμου 5239", 1),
        ("συνοψη του ν 5316/2026", 3),
        ("Summarize Law 5278/2026", 2),
        ("σύνοψη του ν. 62/2025", 0),
    ])
    func summaryFindsTheStatuteByItsKey(request: String, index: Int) {
        #expect(Self.matchedFile(request, Self.demoFiles) == Self.demoFiles[index].0)
        #expect(Self.matchedFile(request, Self.renamedFiles) == Self.renamedFiles[index].0)
    }

    @Test func theKindAskedForWinsOverTheSameNumber() {
        let files: [(String, String?)] = [("law.pdf", "LAW:62/2025"), ("decree.pdf", "PD:62/2025")]
        #expect(Self.matchedFile("Σύνοψη του Π.Δ. 62/2025", files) == "decree.pdf")
        #expect(Self.matchedFile("Σύνοψη του ν. 62/2025", files) == "law.pdf")
    }

    @Test func filenamesWithoutAKeyMatchWholeNumbersOnly() {
        let files: [(String, String?)] = [("ya_8934_2026_fek_b1762.pdf", nil), ("n_5316_2026_fek_a105.pdf", nil)]
        #expect(Self.matchedFile("σύνοψη του ν. 5316/2026", files) == "n_5316_2026_fek_a105.pdf")
        #expect(Self.matchedFile("σύνοψη του Π.Δ. 62", files) == nil)
        #expect(Self.summaryTarget("σύνοψη του Π.Δ. 62", files) == .notInLibrary(key: nil, number: "62"))
    }

    @Test func aStatuteNotInTheLibraryIsNeverSwappedForAnother() {
        let labourCodeOnly: [(String, String?)] = [("pd_62_2025_fek_a121.pdf", "PD:62/2025")]
        #expect(Self.summaryTarget("σύνοψη του ν. 5278/2026", labourCodeOnly)
            == .notInLibrary(key: "LAW:5278/2026", number: "5278/2026"))
        #expect(Self.summaryTarget("σύνοψη του ν. 9999/2026", Self.demoFiles)
            == .notInLibrary(key: "LAW:9999/2026", number: "9999/2026"))
    }

    @Test func theConstitutionIsFoundByItsKey() {
        let files = Self.demoFiles + [("syntagma.pdf", "CONST")]
        #expect(Self.matchedFile("Σύνοψη του Συντάγματος", files) == "syntagma.pdf")
    }

    @Test func aRequestNamingNoStatuteIsUnnamed() {
        #expect(Self.summaryTarget("Σύνοψε το έγγραφο", Self.demoFiles) == .unnamed)
    }

    @Test func statutesAreNamedTheWayReadersWriteThem() {
        #expect(GreekLegalChatRouter.greekStatuteName("LAW:5278/2026") == "ν. 5278/2026")
        #expect(GreekLegalChatRouter.greekStatuteName("PD:62/2025") == "π.δ. 62/2025")
        #expect(GreekLegalChatRouter.greekStatuteName("MD:8934") == "Υ.Α. 8934")
        #expect(GreekLegalChatRouter.greekStatuteName("CONST") == "Σύνταγμα")
        #expect(GreekLegalChatRouter.statuteName("LAW:5278/2026", greek: false) == "Law 5278/2026")

        let (documents, keys) = Self.library([("n_5278_2026_fek_a22.pdf", "LAW:5278/2026"), ("old.pdf", nil)])
        #expect(GreekLegalChatRouter.documentList(documents, statuteKeys: keys, greek: true)
            == "- ν. 5278/2026 (n_5278_2026_fek_a22.pdf)\n- old.pdf")
    }
}
