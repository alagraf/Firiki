//
//  GreekLegalQAChunker.swift
//  Firiki
//
//  Thesis fork: structure-aware chunking for Question & Answer (Q&A / FAQ) documents.
//  Each passage keeps the question together with its answer. If a long answer must be split,
//  the question is repeated at the head of every piece.
//

import Foundation

nonisolated enum GreekLegalQAChunker {
    struct Passage: Sendable {
        let text: String
        let question: String
        let answer: String
        let range: Range<String.Index>
    }

    private static let qaPrefixPattern = try? NSRegularExpression(
        pattern: #"(?i)^\s*(?:Ερώτηση\s*\d*|Ερώτημα\s*\d*|Question\s*\d*|Q\s*\d*|Ε\s*\d*)\s*[:\.\-]\s*(.*)$"#)

    private static let answerPrefixPattern = try? NSRegularExpression(
        pattern: #"(?i)^\s*(?:Απάντηση\s*\d*|Answer\s*\d*|A\s*\d*|Α\s*\d*)\s*[:\.\-]\s*(.*)$"#)

    private static func isQuestionLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return false }
        let ns = trimmed as NSString
        let range = NSRange(location: 0, length: ns.length)
        if qaPrefixPattern?.firstMatch(in: trimmed, range: range) != nil {
            return true
        }
        if (trimmed.hasSuffix("?") || trimmed.hasSuffix(";")) && trimmed.count >= 8 && trimmed.count <= 250 {
            return true
        }
        return false
    }

    private static func isAnswerPrefix(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let ns = trimmed as NSString
        let range = NSRange(location: 0, length: ns.length)
        return answerPrefixPattern?.firstMatch(in: trimmed, range: range) != nil
    }

    /// Extracts passages from a Q&A document.
    static func passages(in text: String, maxWords: Int = 200, minWords: Int = 40) -> [Passage] {
        var rawLines: [(line: String, range: Range<String.Index>)] = []
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.byLines, .substringNotRequired]) { _, range, _, _ in
            rawLines.append((String(text[range]), range))
        }
        guard !rawLines.isEmpty else { return [] }

        struct QAItem {
            var questionLines: [String] = []
            var answerLines: [String] = []
            var startRange: Range<String.Index>
            var endRange: Range<String.Index>
        }

        var items: [QAItem] = []
        var currentItem: QAItem? = nil
        var inAnswer = false

        for (line, range) in rawLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                if inAnswer && currentItem != nil {
                    currentItem?.answerLines.append("")
                }
                continue
            }

            if isQuestionLine(trimmed) {
                if var finished = currentItem {
                    items.append(finished)
                }
                currentItem = QAItem(questionLines: [trimmed], answerLines: [], startRange: range, endRange: range)
                inAnswer = false
            } else if isAnswerPrefix(trimmed) {
                inAnswer = true
                currentItem?.answerLines.append(trimmed)
                if currentItem != nil {
                    currentItem!.endRange = range
                }
            } else {
                if inAnswer {
                    currentItem?.answerLines.append(trimmed)
                    if currentItem != nil {
                        currentItem!.endRange = range
                    }
                } else if currentItem != nil {
                    // Could be continuation of multi-line question or start of answer
                    if trimmed.hasSuffix("?") || trimmed.hasSuffix(";") {
                        currentItem?.questionLines.append(trimmed)
                        currentItem?.endRange = range
                    } else {
                        inAnswer = true
                        currentItem?.answerLines.append(trimmed)
                        currentItem?.endRange = range
                    }
                } else {
                    // Text before first question
                    continue
                }
            }
        }

        if let last = currentItem {
            items.append(last)
        }

        guard !items.isEmpty else {
            // Fallback: entire text as single passage
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return [Passage(text: trimmed, question: "", answer: trimmed, range: text.startIndex..<text.endIndex)]
        }

        var passages: [Passage] = []
        for item in items {
            let questionText = item.questionLines.joined(separator: " ")
            let answerText = item.answerLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            let qWords = wordCount(questionText)
            let aWords = wordCount(answerText)
            let totalWords = qWords + aWords

            let fullRange = item.startRange.lowerBound..<item.endRange.upperBound

            if totalWords <= maxWords {
                let combined = answerText.isEmpty ? questionText : "\(questionText)\n\n\(answerText)"
                passages.append(Passage(
                    text: combined,
                    question: questionText,
                    answer: answerText,
                    range: fullRange
                ))
            } else {
                // Split long answer, prepending question header to every piece
                let budget = max(minWords, maxWords - qWords)
                let answerPieces = GreekLegalStructureChunker.split(answerText, maxWords: budget)
                for (index, piece) in answerPieces.enumerated() {
                    let header = index == 0 ? questionText : "\(questionText) (συνέχεια)"
                    let combined = "\(header)\n\n\(piece)"
                    passages.append(Passage(
                        text: combined,
                        question: questionText,
                        answer: piece,
                        range: fullRange
                    ))
                }
            }
        }

        return passages
    }

    /// Splits a passage if it exceeds the model's token limit, repeating the question on each part.
    static func pieces(of passage: Passage, fitting fits: (String) -> Bool) -> [String] {
        guard !fits(passage.text) else { return [passage.text] }
        let questionHeader = passage.question.isEmpty ? "" : "\(passage.question)\n\n"
        let body = passage.answer.isEmpty ? passage.text : passage.answer
        var words = max(8, body.split(whereSeparator: { $0.isWhitespace }).count / 2)
        while true {
            let parts = GreekLegalStructureChunker.split(body, maxWords: words).map { part in
                "\(questionHeader)\(part)"
            }
            if parts.allSatisfy(fits) || words <= 8 { return parts }
            words = max(8, words * 2 / 3)
        }
    }

    private static func wordCount(_ str: String) -> Int {
        str.split(whereSeparator: { $0.isWhitespace }).count
    }
}
