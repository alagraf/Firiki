//
//  GreekConstitutionEvaluationTests.swift
//  OpenIntelligenceTests
//
//  Thesis fork: the owner's Greek Constitution question set (`Benchmarks/GreekConstitution/
//  syntagma_qa_v1.jsonl`, 10 questions over `syntagma1_1.pdf`) run through the whole app path:
//  import of the PDF (OCR router, NFKC, look-alike repair, Opus-MT translation, indexing), then
//  `RAGService.query` for each Greek question (Greek legal mode: translation, retrieval, article
//  lookup, generation by Apple's on-device model, gates A–I, translation of the answer to Greek).
//
//  An answer passes when every key fact of its case is in it (regular expressions over the
//  lower-cased answer without accents). The table also says whether a passage holding the
//  expected article was retrieved and whether the answer names that article.
//
//  Opt-in, it takes several minutes: `TEST_RUNNER_OI_GREEK_EVAL=1` in the environment of
//  `xcodebuild test` (or of `scripts/thesis_run_tests.sh`). `TEST_RUNNER_OI_GREEK_EVAL_IDS=1,4`
//  runs some cases only.
//
//  A reusable harness since step 2 of the night plan: `TEST_RUNNER_OI_GREEK_EVAL_SET` picks the
//  dataset folder in `Benchmarks/` (`GreekConstitution`, the default, or `GreekLabourCode`),
//  `TEST_RUNNER_OI_GREEK_EVAL_SPLIT` the cases (`dev`, `test` or `all`, the default; a case without
//  a split is in every one), and `TEST_RUNNER_OI_GREEK_EVAL_CORPUS` the PDF of a set that has two
//  (`excerpt`, the default, or `full`). Each set and corpus has a library of its own. Reported
//  separately: retrieval hit (a retrieved passage holds the expected article), answer pass (every
//  key fact, no abstention) and abstention correctness for the cases marked `shouldAbstain`. The iOS 27 Simulator on this Mac generates with Apple's on-device model
//  when the engine is handed a model of its own, as `AnswerQualityEvaluationTests` does.
//

import Foundation
import FoundationModels
import Testing

@testable import OpenIntelligence

/// Apple's on-device model, called the way `AnswerQualityEvaluationTests` calls it.
@available(iOS 27.0, macOS 27.0, *)
final class GreekEvalOnDeviceModel: LLMService {
    var toolHandler: RAGToolHandler?
    var isAvailable: Bool { SystemLanguageModel.default.isAvailable }
    var modelName: String { "Apple on-device model (Greek evaluation)" }

    func generate(prompt: String, context: String?, config: InferenceConfig) async throws -> LLMResponse {
        let started = Date()
        let compiled = FoundationModelPromptCompiler.compilePrompt(
            prompt: prompt, context: context, systemPrompt: config.systemPrompt, disableTools: true)
        // The model the app's session factory would use (permissive guardrails in Greek legal mode).
        let model = greekLegalAwareOnDeviceModel()
        let session = config.systemPrompt.map { LanguageModelSession(model: model, instructions: $0) } ?? LanguageModelSession(model: model)
        // As `LLMService` does: greedy decoding in Greek legal mode.
        let options = GreekLegalAnswerContext.isActive
            ? GenerationOptions(samplingMode: .greedy)
            : GenerationOptions(temperature: Double(config.temperature))
        let text = try await session.respond(to: compiled, options: options).content
        let seconds = Date().timeIntervalSince(started)
        return LLMResponse(
            text: text, tokensGenerated: text.split(separator: " ").count, timeToFirstToken: seconds,
            totalTime: seconds, modelName: modelName, toolCallsMade: 0)
    }
}

/// One question of a set (`Benchmarks/<set>/*.jsonl`).
struct GreekEvalCase: Decodable {
    let id: Int
    let level: String
    let question: String
    let expectedAnswer: String
    let keyFacts: [String]
    let article: Int
    /// "dev" or "test"; nil puts the case in every split.
    let split: String?
    /// The app must refuse: the article or the law is not in the library.
    let shouldAbstain: Bool?

    var mustAbstain: Bool { shouldAbstain ?? false }

    static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

    /// Lower-cased, accents removed, final sigma as sigma.
    static func fold(_ text: String) -> String {
        GreekLegalEntityMasker.normalizeGreekText(text)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "el"))
            .replacingOccurrences(of: "ς", with: "σ")
    }

    func missingFacts(in answer: String) -> [String] {
        let folded = Self.fold(answer)
        return keyFacts.filter { fact in
            let pattern = Self.fold(fact)
            return folded.range(of: pattern, options: .regularExpression) == nil
        }
    }

    func namesArticle(_ answer: String) -> Bool {
        GreekLegalEntityMasker.canonicalKeys(in: answer).contains("ART:\(article)")
    }
}

/// A dataset: its folder, question file and PDFs.
struct GreekEvalSet {
    let name: String
    let questions: String
    /// Corpus name → PDF file name.
    let corpora: [String: String]
    let defaultCorpus: String
    /// The library name of the first set is the one runs 1–8 used, so its import is reused.
    let libraryPrefix: String

    static let all: [String: GreekEvalSet] = [
        "GreekConstitution": GreekEvalSet(
            name: "GreekConstitution", questions: "syntagma_qa_v1.jsonl", corpora: ["full": "syntagma1_1.pdf"],
            defaultCorpus: "full", libraryPrefix: "Greek Constitution evaluation"),
        "GreekLabourCode": GreekEvalSet(
            name: "GreekLabourCode", questions: "labour_qa_v1.jsonl",
            corpora: ["excerpt": "pd_62_2025_excerpt.pdf", "full": "pd_62_2025_fek_a121.pdf"],
            defaultCorpus: "excerpt", libraryPrefix: "Greek Labour Code evaluation"),
    ]

    var folder: URL { GreekEvalCase.repository.appendingPathComponent("Benchmarks/\(name)") }

    func libraryName(corpus: String) -> String {
        corpora.count == 1 ? libraryPrefix : "\(libraryPrefix) (\(corpus))"
    }

    func cases() -> [GreekEvalCase] {
        guard let text = try? String(contentsOf: folder.appendingPathComponent(questions), encoding: .utf8) else { return [] }
        return text.split(separator: "\n")
            .filter { !$0.hasPrefix("//") && !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .compactMap { try? JSONDecoder().decode(GreekEvalCase.self, from: Data($0.utf8)) }
    }
}

@Suite(
    "Greek legal QA, whole app path",
    .enabled(if: ProcessInfo.processInfo.environment["OI_GREEK_EVAL"] == "1"))
@MainActor
struct GreekConstitutionEvaluationTests {
    @available(iOS 27.0, macOS 27.0, *)
    @Test(.timeLimit(.minutes(150)))
    func questionSet() async throws {
        let environment = ProcessInfo.processInfo.environment
        let set = try #require(GreekEvalSet.all[environment["OI_GREEK_EVAL_SET"] ?? "GreekConstitution"])
        let corpus = environment["OI_GREEK_EVAL_CORPUS"].flatMap { set.corpora[$0] == nil ? nil : $0 } ?? set.defaultCorpus
        let split = environment["OI_GREEK_EVAL_SPLIT"] ?? "all"
        let pdf = set.folder.appendingPathComponent(try #require(set.corpora[corpus]))
        print("[GreekEval] set=\(set.name) corpus=\(corpus) (\(pdf.lastPathComponent)) split=\(split)")

        for _ in 0..<60 where !SystemLanguageModel.default.isAvailable {
            try await Task.sleep(for: .seconds(5))
        }
        print("[GreekEval] model availability: \(SystemLanguageModel.default.availability)")
        try #require(LocalNeuralTranslator.isAvailable(.greekToEnglish) && LocalNeuralTranslator.isAvailable(.englishToGreek))

        let plan = UserDefaults(suiteName: "GreekConstitutionEvaluation.plan") ?? .standard
        plan.set(WorkspaceTier.pro.rawValue, forKey: "entitlement.activeTier")
        let store = EntitlementStore(billingService: StoreKitBillingService(), defaults: plan)
        let libraries = IntentSupport.libraries()
        let engine = RAGService(llmService: GreekEvalOnDeviceModel(), containerService: libraries, entitlementStore: store)
        for _ in 0..<100 where !engine.hasLoadedDocumentsFromDisk {
            try await Task.sleep(for: .milliseconds(100))
        }
        // The imported library is kept between runs (the import with translation takes minutes)
        // and reused when its document is there; TEST_RUNNER_OI_GREEK_EVAL_REIMPORT=1 imports it
        // again, which a change to ingestion needs.
        let libraryName = set.libraryName(corpus: corpus)
        let reimport = environment["OI_GREEK_EVAL_REIMPORT"] == "1"
        var library = libraries.containers.first { $0.name == libraryName }
        let hasDocument = library.map { existing in
            engine.documents.contains { $0.containerId == existing.id && $0.totalChunks > 0 }
        } ?? false
        if let existing = library, reimport || !hasDocument {
            for document in engine.documents where document.containerId == existing.id {
                try? await engine.removeDocument(document)
            }
            libraries.deleteContainer(id: existing.id)
            library = nil
        }
        if library == nil {
            let tierKey = "entitlement.activeTier"
            let savedTier = UserDefaults.standard.string(forKey: tierKey)
            UserDefaults.standard.set(WorkspaceTier.pro.rawValue, forKey: tierKey)
            let created = Result { try libraries.createContainer(name: libraryName) }
            if let savedTier { UserDefaults.standard.set(savedTier, forKey: tierKey) } else { UserDefaults.standard.removeObject(forKey: tierKey) }
            let made = try created.get()
            let importStart = Date()
            let imported = await engine.ingestDocuments([pdf], containerId: made.id)
            let chunks = engine.documents.filter { $0.containerId == made.id }.map(\.totalChunks).reduce(0, +)
            print("[GreekEval] imported \(imported.successCount) document (\(chunks) passages) in \(Int(Date().timeIntervalSince(importStart))) s")
            try #require(imported.successCount == 1)
            library = made
        } else {
            print("[GreekEval] reusing the imported library \(libraryName)")
        }
        let libraryId = try #require(library?.id)
        // Standard reuses a question's cached search until the documents or the app's version and
        // build change, so a reused library would get the passages an earlier build found: every
        // run searches afresh.
        let cleared = await SQLiteFullTextService.shared.deleteAllCachedQueries()
        print("[GreekEval] cleared \(cleared) cached searches")

        let wanted = environment["OI_GREEK_EVAL_IDS"]?
            .split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        let cases = set.cases().filter { evalCase in
            (wanted?.contains(evalCase.id) ?? true) && (split == "all" || evalCase.split == nil || evalCase.split == split)
        }
        try #require(!cases.isEmpty)

        var rows: [String] = []
        var answerPassed = 0, answerable = 0, retrievalHits = 0, abstainedCorrectly = 0, mustAbstain = 0, falseAbstentions = 0
        for evalCase in cases {
            let started = Date()
            let response: RAGResponse
            do {
                response = try await engine.query(evalCase.question, topK: 5, containerId: libraryId, qualityModeOverride: .standard)
            } catch {
                rows.append("| \(evalCase.id) | \(evalCase.level) | FAIL | error: \(error.localizedDescription) |")
                if evalCase.mustAbstain { mustAbstain += 1 } else { answerable += 1 }
                continue
            }
            let answer = response.generatedResponse
            let review = response.metadata.legalReview
            let abstained = (review?.abstained ?? false) || answer.hasPrefix(String(LegalVerificationPolicy.greekAbstentionMessage.prefix(40)))
            let retrievedArticle = response.retrievedChunks.contains {
                LegalCrossReferences.definedArticles(of: $0.chunk).contains("ART:\(evalCase.article)")
            }
            let missing = evalCase.missingFacts(in: answer)
            let ok: Bool
            if evalCase.mustAbstain {
                mustAbstain += 1
                ok = abstained
                if ok { abstainedCorrectly += 1 }
            } else {
                answerable += 1
                ok = missing.isEmpty && !abstained
                if ok { answerPassed += 1 }
                if retrievedArticle { retrievalHits += 1 }
                if abstained { falseAbstentions += 1 }
            }
            let kind = evalCase.mustAbstain ? "must abstain" : "article \(evalCase.article) retrieved: \(retrievedArticle ? "yes" : "no")"
            rows.append(
                "| \(evalCase.id) | \(evalCase.level) | \(evalCase.split ?? "-") | \(ok ? "PASS" : "FAIL") | \(kind) | abstained: \(abstained ? "yes" : "no") | named: \(evalCase.namesArticle(answer) || evalCase.namesArticle(review?.englishDraft ?? "") ? "yes" : "no") | missing: \(evalCase.mustAbstain ? [] : missing) | \(Int(Date().timeIntervalSince(started))) s |")
            print("[GreekEval] Q\(evalCase.id): \(evalCase.question)")
            print("[GreekEval]   question as run: \(review?.queryEn ?? "-")")
            print("[GreekEval]   passages: \(response.retrievedChunks.prefix(5).map { "\(LegalCrossReferences.definedArticles(of: $0.chunk)) \(String(format: "%.2f", $0.similarityScore))" })")
            print("[GreekEval]   English draft: \(review?.englishDraft ?? "-")")
            print("[GreekEval]   review: abstained=\(abstained) reason=\(review?.reason ?? "-") gates=\(review?.gates.filter { !$0.passed }.map(\.gate) ?? [])")
            print("[GreekEval]   answer: \(answer)")
            print("[GreekEval]   expected: \(evalCase.expectedAnswer)")
        }
        print("[GreekEval] | # | level | split | result | retrieval | abstained | article named | missing facts | time |")
        for row in rows { print("[GreekEval] \(row)") }
        print("[GreekEval] answer pass \(answerPassed) of \(answerable); retrieval hit \(retrievalHits) of \(answerable); false abstentions \(falseAbstentions); abstention correct \(abstainedCorrectly) of \(mustAbstain)")
        print("[GreekEval] summary set=\(set.name) corpus=\(corpus) split=\(split): passed \(answerPassed + abstainedCorrectly) of \(cases.count)")
        // Runs 1-8 printed this line; kept for comparison.
        print("[GreekEval] passed \(answerPassed + abstainedCorrectly) of \(cases.count)")
    }
}
