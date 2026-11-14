//
//  GreekLegalModelCall.swift
//  Firiki
//
//  Thesis fork (demo deeper fixes 1 and 3, POC_PROGRESS.md): one on-device model call of a
//  summary or opinion pass, made to survive what the model throws. It stops between passes when
//  the request is cancelled, retries a prompt that is too long for the window with a shorter one,
//  retries once when the model is busy, and tells the caller when the model declined, so the pass
//  can be skipped instead of failing the whole summary or opinion.
//

import Foundation
import FoundationModels

nonisolated enum GreekLegalModelCall {
    /// What went wrong in a model call, from either error family: `LanguageModelSession.GenerationError`
    /// (OS 26, deprecated in 27) or `LanguageModelError`, `SystemLanguageModel.Error` and
    /// `LanguageModelSession.Error` (OS 27).
    enum Failure: Equatable, Sendable {
        case contextTooLong, declined, busy, unavailable, unsupportedLanguage
    }

    /// The failure an error stands for; nil for cancellation and anything else.
    static func failure(of error: Error) -> Failure? {
        if let generationError = error as? LanguageModelSession.GenerationError {
            switch generationError {
            case .exceededContextWindowSize: return .contextTooLong
            case .guardrailViolation, .refusal: return .declined
            case .rateLimited, .concurrentRequests: return .busy
            case .assetsUnavailable: return .unavailable
            case .unsupportedLanguageOrLocale: return .unsupportedLanguage
            default: return nil
            }
        }
        if #available(iOS 27.0, macOS 27.0, *) {
            if let modelError = error as? LanguageModelError {
                switch modelError {
                case .contextSizeExceeded: return .contextTooLong
                case .guardrailViolation, .refusal: return .declined
                case .rateLimited, .timeout: return .busy
                case .unsupportedLanguageOrLocale: return .unsupportedLanguage
                default: return nil
                }
            }
            if let sessionError = error as? LanguageModelSession.Error, case .concurrentRequests = sessionError { return .busy }
            if error is SystemLanguageModel.Error { return .unavailable }
        }
        return nil
    }

    /// The model declined a pass: the caller skips it (a summary group, an opinion section).
    struct Declined: Error {}

    /// Shares of the prompt's body kept on each retry after "too long for the window".
    static let shrinkSteps: [Double] = [0.6, 0.35]

    /// The prompt with its body cut to `share` of its length: the header (everything before the
    /// first blank line: the question, the statute) is kept whole, and the body is cut after the
    /// last line or sentence that fits.
    static func shortened(_ prompt: String, to share: Double) -> String {
        guard let split = prompt.range(of: "\n\n") else {
            return String(prompt.prefix(max(1, Int(Double(prompt.count) * share))))
        }
        let header = String(prompt[..<split.upperBound])
        let body = String(prompt[split.upperBound...])
        let limit = max(1, Int(Double(body.count) * share))
        guard body.count > limit else { return prompt }
        let cut = String(body.prefix(limit))
        func farEnough(_ range: Range<String.Index>) -> Bool { cut.distance(from: cut.startIndex, to: range.lowerBound) > limit / 2 }
        if let line = cut.range(of: "\n", options: .backwards), farEnough(line) {
            return header + String(cut[..<line.lowerBound])
        }
        if let sentence = cut.range(of: ". ", options: .backwards), farEnough(sentence) {
            return header + String(cut[..<sentence.lowerBound]) + "."
        }
        return header + cut
    }

    /// One model call of a pass. Throws `CancellationError` before the call when the request was
    /// stopped (Stop took effect only after every pass had run), retries with `shortened` prompts
    /// when the prompt is too long, retries once after a second when the model is busy, and throws
    /// `Declined` when the model refused or a guardrail stopped it. Anything else is rethrown for
    /// `GreekLegalChatRouter.failureMessage`.
    static func respond(
        instructions: String,
        prompt: String,
        label: String,
        respond: (_ instructions: String, _ prompt: String) async throws -> String,
        pause: (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) async throws -> String {
        var attempt = prompt
        var shrinks = shrinkSteps[...]
        var waited = false
        while true {
            try Task.checkCancellation()
            do {
                return try await respond(instructions, attempt)
            } catch {
                if error is CancellationError { throw error }
                switch failure(of: error) {
                case .contextTooLong?:
                    guard let share = shrinks.popFirst() else { throw error }
                    attempt = shortened(prompt, to: share)
                    Log.warning("[ModelCall] \(label): too long for the window, retrying with \(Int(share * 100))% of the text", category: .llm)
                case .busy? where !waited:
                    waited = true
                    Log.warning("[ModelCall] \(label): model busy, retrying in 1 s", category: .llm)
                    try await pause(.seconds(1))
                case .declined?:
                    Log.warning("[ModelCall] \(label): the model declined; the pass is skipped", category: .llm)
                    throw Declined()
                default:
                    throw error
                }
            }
        }
    }
}
