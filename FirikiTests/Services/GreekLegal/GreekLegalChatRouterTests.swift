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
            "Ποια σύμβαση εργασίας προβλέπεται για μαθητεία;",
            "Υποδείγματα συμβάσεων για έκτακτες ανάγκες"
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
            "Ποιο είναι το νόμιμο κατώτατο ημερομίσθιο;"
        ]
        for query in queries {
            let intent = GreekLegalChatRouter.detectIntent(query)
            #expect(intent == .standardQA(query: query))
        }
    }

    // MARK: - Document Target Extraction

    @Test func extractDocumentTargetFromPrompt() {
        #expect(GreekLegalChatRouter.extractDocumentTarget(from: "Σύνοψε το ν. 5278/2026") == "5278/2026")
        #expect(GreekLegalChatRouter.extractDocumentTarget(from: "Σύνοψη του Π.Δ. 62/2025") == "62/2025")
        #expect(GreekLegalChatRouter.extractDocumentTarget(from: "Περίληψη του νόμου 4808/2021") == "4808/2021")
        #expect(GreekLegalChatRouter.extractDocumentTarget(from: "Summarize law 5278/2026") == "5278/2026")
        #expect(GreekLegalChatRouter.extractDocumentTarget(from: "Σύνοψε το έγγραφο") == nil)
    }

    // MARK: - Document Matching

    @Test func matchDocumentInLibrary() {
        let url1 = URL(fileURLWithPath: "/tmp/law-5278-2026.pdf")
        let url2 = URL(fileURLWithPath: "/tmp/pd-62-2025-labour-code.pdf")
        let doc1 = Document(filename: "law-5278-2026.pdf", fileURL: url1, contentType: .pdf)
        let doc2 = Document(filename: "pd-62-2025-labour-code.pdf", fileURL: url2, contentType: .pdf)
        let library = [doc1, doc2]

        let matched5278 = GreekLegalChatRouter.matchDocument(target: "5278/2026", in: library)
        #expect(matched5278?.filename == "law-5278-2026.pdf")

        let matched62 = GreekLegalChatRouter.matchDocument(target: "62/2025", in: library)
        #expect(matched62?.filename == "pd-62-2025-labour-code.pdf")

        let matchedNone = GreekLegalChatRouter.matchDocument(target: "9999/2026", in: library)
        #expect(matchedNone == nil)
    }
}
