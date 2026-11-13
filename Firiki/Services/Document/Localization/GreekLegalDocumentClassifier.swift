//
//  GreekLegalDocumentClassifier.swift
//  Firiki
//
//  Thesis fork: classifies imported legal and non-legal documents into:
//  1. statute (law, decree, ministerial decision, Code) -> GreekLegalStructureChunker
//  2. lawyerNotes (memo, notes, legal opinion, case analysis) -> GreekLegalNotesChunker
//  3. questionAnswer (FAQ, exam questions, client Q&A) -> GreekLegalQAChunker
//  4. generic (general prose/documents) -> generic chunking
//

import Foundation
import FoundationModels

enum LegalDocumentKind: String, Sendable, CaseIterable {
    case statute
    case lawyerNotes
    case questionAnswer
    case generic
}

struct ClassificationResult: Sendable, Equatable {
    let kind: LegalDocumentKind
    let reason: String
}

enum GreekLegalDocumentClassifier {

    // MARK: - Pattern Definitions

    private static let gazettePattern = try? NSRegularExpression(
        pattern: #"(?i)(?:ΕΦΗΜΕΡΙ[ΔΑ]+\s+ΤΗΣ\s+ΚΥΒΕΡΝΗΣ[ΕΩΣ]+|Τεύχος\s+\S{1,4}\s*\d{1,4}/\d{1,2}\.\d{1,2}\.\d{4}|ΦΕΚ\s+\d+)"#)

    private static let statuteTitlePattern = try? NSRegularExpression(
        pattern: #"(?i)\b(?:ΝΟΜΟΣ\s+ΥΠ['’]\s*ΑΡΙΘ|ΠΡΟΕΔΡΙΚΟ\s+ΔΙΑΤΑΓΜΑ\s+ΥΠ['’]\s*ΑΡΙΘ|ΥΠΟΥΡΓΙΚΗ\s+ΑΠΟΦΑΣΗ\s+ΥΠ['’]\s*ΑΡΙΘ|ΚΩΔΙΚΑΣ\s+ΕΡΓΑΤΙΚΟΥ\s+ΔΙΚΑΙΟΥ|ΣΥΝΤΑΓΜΑ\s+ΤΗΣ\s+ΕΛΛΑΔΑΣ)\b"#)

    private static let qaLabelsPattern = try? NSRegularExpression(
        pattern: #"(?im)^\s*(?:Ερώτηση\s*\d*|Ερώτημα\s*\d*|Απάντηση\s*\d*|Ε\s*\d*[:\.]|Α\s*\d*[:\.]|Question\s*\d*|Answer\s*\d*|Q\s*\d*[:\.]|A\s*\d*[:\.])\s*[:\.\-]"#)

    private static let questionLinePattern = try? NSRegularExpression(
        pattern: #"(?m)^\s*[\p{Lu}\d«"].{3,120}[;\?]\s*$"#)

    private static let notesHeadings = [
        "ΙΣΤΟΡΙΚΟ", "ΠΡΑΓΜΑΤΙΚΑ ΠΕΡΙΣΤΑΤΙΚΑ", "Ιστορικό", "Πραγματικά Περιστατικά",
        "ΕΡΩΤΗΜΑ", "ΝΟΜΙΚΟ ΕΡΩΤΗΜΑ", "ΤΙΘΕΜΕΝΑ ΖΗΤΗΜΑΤΑ", "Ερώτημα", "Νομικό Ερώτημα",
        "ΕΦΑΡΜΟΣΤΕΟ ΔΙΚΑΙΟ", "ΝΟΜΙΚΟ ΠΛΑΙΣΙΟ", "ΣΧΕΤΙΚΕΣ ΔΙΑΤΑΞΕΙΣ", "Εφαρμοστέο Δίκαιο", "Νομικό Πλαίσιο",
        "ΝΟΜΙΚΗ ΥΠΑΓΩΓΗ", "ΝΟΜΙΚΗ ΑΝΑΛΥΣΗ", "ΑΞΙΟΛΟΓΗΣΗ", "Νομική Υπαγωγή", "Νομική Ανάλυση",
        "ΣΥΜΠΕΡΑΣΜΑ", "ΓΝΩΜΟΔΟΤΗΣΗ", "ΚΑΤΑΚΛΕΙΔΑ", "Συμπέρασμα", "Γνωμοδότηση", "Κατακλείδα",
        "FACTS", "BACKGROUND", "Facts", "Background",
        "LEGAL QUESTION", "QUESTION PRESENTED", "ISSUES", "Question", "Issues",
        "APPLICABLE LAW", "LEGAL FRAMEWORK", "Applicable Law", "Legal Framework",
        "LEGAL ANALYSIS", "ANALYSIS", "DISCUSSION", "Analysis", "Discussion",
        "CONCLUSION", "LEGAL OPINION", "MEMORANDUM", "Conclusion", "Legal Opinion", "Memorandum"
    ]

    // MARK: - Program Rules Classification

    static func classifyByRules(text: String, filename: String = "") -> ClassificationResult? {
        let prefix = String(text.prefix(200_000))
        let nsPrefix = prefix as NSString
        let fullRange = NSRange(location: 0, length: nsPrefix.length)

        // 1. Check for Question & Answer (Q&A) document
        let qaMatches = qaLabelsPattern?.numberOfMatches(in: prefix, range: fullRange) ?? 0
        let questionLineMatches = questionLinePattern?.numberOfMatches(in: prefix, range: fullRange) ?? 0
        if qaMatches >= 4 || (qaMatches >= 2 && questionLineMatches >= 2) || questionLineMatches >= 6 {
            return ClassificationResult(
                kind: .questionAnswer,
                reason: "Found Q&A markers (labels: \(qaMatches), question lines: \(questionLineMatches))"
            )
        }

        // 2. Check for Lawyer's Notes / Legal Opinion
        var matchingHeadings: [String] = []
        let lines = prefix.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            for heading in notesHeadings {
                if trimmed == heading || trimmed == "\(heading):" || trimmed.hasPrefix("\(heading) -") || trimmed.hasPrefix("\(heading)—") {
                    if !matchingHeadings.contains(heading) {
                        matchingHeadings.append(heading)
                    }
                }
            }
        }
        if matchingHeadings.count >= 2 {
            return ClassificationResult(
                kind: .lawyerNotes,
                reason: "Found lawyer notes / legal memo headings (\(matchingHeadings.joined(separator: ", ")))"
            )
        }

        // 3. Check for Statute
        let isGreek = GreekLegalEntityMasker.greekLetterRatio(prefix) >= 0.3
        let hasGazette = gazettePattern?.firstMatch(in: prefix, range: fullRange) != nil
        let hasStatuteTitle = statuteTitlePattern?.firstMatch(in: prefix, range: fullRange) != nil
        let hasStatuteFilename = filename.lowercased().range(of: #"(?:law|nomos|fek|pd|ypap|syntagma|\b\d{4}/\d{4}\b)"#, options: .regularExpression) != nil

        let statuteLines = GreekLegalStructureChunker.lines(of: text)
        let headings = GreekLegalStructureChunker.acceptedHeadings(in: statuteLines)

        if isGreek && (hasGazette || hasStatuteTitle || hasStatuteFilename || headings.count >= 3) {
            if headings.count >= 3 {
                return ClassificationResult(
                    kind: .statute,
                    reason: "Statute structure verified with \(headings.count) sequential article headings"
                )
            } else if (hasGazette || hasStatuteTitle) && !headings.isEmpty {
                return ClassificationResult(
                    kind: .statute,
                    reason: "Statute title or Gazette header identified"
                )
            }
        }

        // 4. If neither Q&A, Notes, nor Statute criteria are met
        return ClassificationResult(
            kind: .generic,
            reason: "Standard prose without specialized legal statute, memo, or Q&A structure"
        )
    }

    // MARK: - On-Device Model Fallback

    static func classify(text: String, filename: String = "") async -> ClassificationResult {
        // Fast path: deterministic program rules first
        if let result = classifyByRules(text: text, filename: filename) {
            return result
        }

        // Fallback: On-device foundation model if available
        if SystemLanguageModel.default.isAvailable {
            do {
                let snippet = String(text.prefix(1500))
                let result = try await modelClassify(snippet: snippet)
                return result
            } catch {
                Log.warning("[DocumentClassifier] On-device model classification failed: \(error.localizedDescription)", category: .ingestion)
            }
        }

        return ClassificationResult(kind: .generic, reason: "Fallback default generic chunking")
    }

    /// Classifies the text, returning non-nil only if it is one of the specialized legal types
    /// (.statute, .questionAnswer, .lawyerNotes). Returns nil if classified as .generic.
    static func classifyIfSpecialized(text: String, filename: String = "") async -> ClassificationResult? {
        let result = await classify(text: text, filename: filename)
        return result.kind == .generic ? nil : result
    }

    private static func modelClassify(snippet: String) async throws -> ClassificationResult {
        let kinds = LegalDocumentKind.allCases.map(\.rawValue)
        let root = DynamicGenerationSchema(name: "DocumentClassification", properties: [
            .init(name: "reason", description: "Brief reason for the document type choice",
                  schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "kind", description: "One of: statute, lawyerNotes, questionAnswer, generic",
                  schema: DynamicGenerationSchema(name: "KindChoice", anyOf: kinds)),
        ])
        let schema = try GenerationSchema(root: root, dependencies: [])
        let instructions = """
        Classify the text into one of four categories:
        - statute: official law, decree, ministerial decision, or statutory code with numbered articles.
        - lawyerNotes: lawyer's notes, legal opinion, memorandum, or case analysis with headings like Facts, Question, Analysis, Conclusion.
        - questionAnswer: FAQ, exam questions, or Q&A interview pairs.
        - generic: general documents, reports, essays, or non-structured text.
        """
        let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
        let response = try await session.respond(
            to: "Document excerpt:\n\(snippet)",
            schema: schema,
            options: GenerationOptions(samplingMode: .greedy)
        )
        let kindStr = try response.content.value(String.self, forProperty: "kind")
        let reason = (try? response.content.value(String.self, forProperty: "reason")) ?? "Model classification"
        let chosenKind = LegalDocumentKind(rawValue: kindStr) ?? .generic
        return ClassificationResult(kind: chosenKind, reason: reason)
    }
}
