//
//  GreekLegalModelCallTests.swift
//  FirikiTests
//
//  Thesis fork (demo deeper fixes 1 and 3): summaries and opinions survive model errors, and Stop
//  takes effect between passes. The model is a stand-in closure; no Apple Intelligence needed.
//

import Foundation
import FoundationModels
import Testing
@testable import Firiki

@Suite("Model calls of summaries and opinions")
struct GreekLegalModelCallTests {
    actor Recorder {
        var prompts: [String] = []
        var pauses = 0
        func add(_ prompt: String) { prompts.append(prompt) }
        func paused() { pauses += 1 }
    }

    static let tooLong = LanguageModelSession.GenerationError.exceededContextWindowSize(.init(debugDescription: "too long"))
    static let guardrail = LanguageModelSession.GenerationError.guardrailViolation(.init(debugDescription: "guardrail"))
    static let busy = LanguageModelSession.GenerationError.rateLimited(.init(debugDescription: "busy"))

    @Test func aShortenedPromptKeepsItsHeaderAndEndsAtALine() {
        let prompt = "Question: Q\nStatute: Law 1\n\nPassages:\n" + (1...20).map { "Line \($0) of the passage text." }.joined(separator: "\n")
        let short = GreekLegalModelCall.shortened(prompt, to: 0.5)
        #expect(short.hasPrefix("Question: Q\nStatute: Law 1\n\nPassages:\n"))
        #expect(short.count < prompt.count * 6 / 10)
        #expect(short.hasSuffix("of the passage text."), "cut at a line end: \(short.suffix(40))")
    }

    @Test func aPromptTooLongIsRetriedShorter() async throws {
        let recorder = Recorder()
        let prompt = "Statute: Law 1\n\n" + String(repeating: "A rule of the law applies here. ", count: 200)
        let answer = try await GreekLegalModelCall.respond(instructions: "I", prompt: prompt, label: "test", respond: { _, sent in
            await recorder.add(sent)
            if await recorder.prompts.count == 1 { throw Self.tooLong }
            return "ok"
        })
        let prompts = await recorder.prompts
        #expect(answer == "ok" && prompts.count == 2)
        #expect(prompts[1].hasPrefix("Statute: Law 1\n\n") && prompts[1].count < prompts[0].count * 7 / 10)

        // Still too long after both shorter tries: the error reaches the caller.
        let always = Recorder()
        await #expect(throws: LanguageModelSession.GenerationError.self) {
            _ = try await GreekLegalModelCall.respond(instructions: "I", prompt: prompt, label: "test", respond: { _, sent in
                await always.add(sent)
                throw Self.tooLong
            })
        }
        #expect(await always.prompts.count == 1 + GreekLegalModelCall.shrinkSteps.count)
    }

    @Test func aBusyModelIsAskedAgainOnce() async throws {
        let recorder = Recorder()
        let answer = try await GreekLegalModelCall.respond(
            instructions: "I", prompt: "P", label: "test",
            respond: { _, sent in
                await recorder.add(sent)
                if await recorder.prompts.count == 1 { throw Self.busy }
                return "ok"
            },
            pause: { _ in await recorder.paused() })
        #expect(answer == "ok")
        #expect(await recorder.pauses == 1)

        await #expect(throws: LanguageModelSession.GenerationError.self) {
            _ = try await GreekLegalModelCall.respond(instructions: "I", prompt: "P", label: "test",
                                                      respond: { _, _ in throw Self.busy }, pause: { _ in })
        }
    }

    @Test func aRefusalIsDeclined() async {
        await #expect(throws: GreekLegalModelCall.Declined.self) {
            _ = try await GreekLegalModelCall.respond(instructions: "I", prompt: "P", label: "test", respond: { _, _ in throw Self.guardrail })
        }
    }

    /// Three articles long enough for one group each.
    static let longArticles: [String] = (1...3).map { number in
        "Article \(number) [Άρθρο \(number)]\nRule \(number)\n" + String(repeating: "The rule of this article applies to every employee. ", count: 80)
    }

    @Test func aDeclinedSummaryGroupIsSkipped() async throws {
        let summary = try await GreekLegalDocumentSummarizer.summarize(
            passages: Self.longArticles, statuteKey: "LAW:5278/2026",
            respond: { instructions, prompt in
                if instructions == GreekLegalDocumentSummarizer.reduceInstructions { return "The law sets three rules." }
                if prompt.contains("=== Article 2 ===") { throw Self.guardrail }
                let number = prompt.contains("=== Article 1 ===") ? 1 : 3
                return "Article \(number): rule \(number) applies to every employee."
            },
            translate: { $0 })
        #expect(summary.groups == 3)
        #expect(summary.english.contains("rule 1 applies") && summary.english.contains("rule 3 applies"))
        #expect(!summary.english.contains("rule 2"))
    }

    @Test func stopTakesEffectBeforeTheNextPass() async throws {
        let recorder = Recorder()
        let task = Task {
            try await GreekLegalDocumentSummarizer.summarize(
                passages: Self.longArticles, statuteKey: "LAW:5278/2026",
                respond: { _, prompt in
                    await recorder.add(prompt)
                    // Stop pressed while the first group is being written.
                    withUnsafeCurrentTask { $0?.cancel() }
                    return "Article 1: rule 1 applies to every employee."
                },
                translate: { $0 })
        }
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(await recorder.prompts.count == 1, "no pass after Stop")
    }

    @Test func aDeclinedOpinionSectionIsSkippedAndADeclinedConclusionRefuses() async throws {
        let sources = [
            GreekLegalOpinionWriter.Source(document: "law.pdf", statuteKey: "LAW:5239/2025", passages: [GreekLegalOpinionTests.overtime]),
            GreekLegalOpinionWriter.Source(document: "other.pdf", statuteKey: "LAW:5316/2026", passages: [GreekLegalOpinionTests.unrelated]),
        ]
        let section = "Overtime is allowed up to four (4) hours a day (Article 7 of Law 5239/2025)."
        let opinion = try await GreekLegalOpinionWriter.write(
            question: "Επιτρέπονται τέσσερις ώρες υπερωρία;", questionEn: "Are four hours of overtime allowed?",
            sources: sources, links: [],
            respond: { instructions, prompt in
                if prompt.contains("Law 5316/2026") { throw Self.guardrail }
                return instructions == GreekLegalOpinionWriter.conclusionInstructions ? "Yes: " + section : section
            },
            translate: { text, _ in text })
        #expect(opinion.refusal == nil)
        #expect(opinion.english.contains("Law 5239/2025") && !opinion.english.contains("Law 5316/2026:"))

        let refused = try await GreekLegalOpinionWriter.write(
            question: "Επιτρέπονται τέσσερις ώρες υπερωρία;", questionEn: "Are four hours of overtime allowed?",
            sources: sources, links: [],
            respond: { instructions, _ in
                if instructions == GreekLegalOpinionWriter.conclusionInstructions { throw Self.guardrail }
                return section
            },
            translate: { text, _ in text })
        #expect(refused.refusal == "the model declined to write the conclusion")
        #expect(refused.refusalGreek == "το μοντέλο της συσκευής αρνήθηκε να γράψει το συμπέρασμα")
    }

    /// The OS 27 error types get their own messages, not the generic «Δοκιμάστε ξανά.».
    @Test func bothErrorFamiliesGetTheirMessages() {
        func greek(_ error: Error) -> String { GreekLegalChatRouter.failureReason(for: error, greek: true) }
        #expect(greek(Self.tooLong).contains("πολύ μεγάλο"))
        #expect(greek(GreekLegalModelCall.Declined()).contains("δεν απάντησε"))
        if #available(iOS 27.0, macOS 27.0, *) {
            #expect(greek(LanguageModelError.contextSizeExceeded(.init(contextSize: 4_096, tokenCount: 5_000, debugDescription: "x"))).contains("πολύ μεγάλο"))
            #expect(greek(LanguageModelError.refusal(.init(explanation: "no", debugDescription: "x"))).contains("δεν απάντησε"))
            #expect(greek(LanguageModelError.guardrailViolation(.init(debugDescription: "x"))).contains("δεν απάντησε"))
            #expect(greek(LanguageModelError.rateLimited(.init(resetDate: nil, debugDescription: "x"))).contains("απασχολημένο"))
            #expect(greek(LanguageModelSession.Error.concurrentRequests).contains("απασχολημένο"))
        }
    }
}
