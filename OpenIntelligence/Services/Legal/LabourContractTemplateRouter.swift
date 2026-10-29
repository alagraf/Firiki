//
//  LabourContractTemplateRouter.swift
//  OpenIntelligence
//
//  Thesis fork (PoC capability 4): picks which of the ten drafted labour contract templates
//  (Resources/LabourContractTemplates) a request needs, or none. A Greek request is translated to
//  English by Opus-MT; Apple's on-device model then chooses one template id, or "none", from the
//  templates' descriptions, constrained by a generation schema to the valid ids. Without the model
//  the templates' keywords decide.
//

import Foundation
import FoundationModels

/// One of the drafted labour contract templates: its front matter and the contract.
nonisolated struct LabourContractTemplate: Sendable, Hashable {
    let id: String
    let number: Int
    let titleEl: String
    let titleEn: String
    let articles: [String]
    let keywordsEl: [String]
    let keywordsEn: [String]
    let descriptionEl: String
    let descriptionEn: String
    /// The contract with its `{{placeholders}}`, after the front matter.
    let body: String

    /// A template file: front matter between two `---` lines, one `key: value` a line with the
    /// value written as JSON (`"text"`, `["a", "b"]`, `6`), then the contract.
    init?(markdown: String) {
        let lines = markdown.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else { return nil }
        var fields: [String: Any] = [:]
        for line in lines[1..<end] {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let raw = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            fields[key] = raw.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0, options: .fragmentsAllowed) }
        }
        guard let id = fields["id"] as? String, let number = fields["number"] as? Int,
              let titleEl = fields["title_el"] as? String, let titleEn = fields["title_en"] as? String,
              let descriptionEn = fields["description_en"] as? String else { return nil }
        self.id = id
        self.number = number
        self.titleEl = titleEl
        self.titleEn = titleEn
        articles = fields["articles"] as? [String] ?? []
        keywordsEl = fields["keywords_el"] as? [String] ?? []
        keywordsEn = fields["keywords_en"] as? [String] ?? []
        descriptionEl = fields["description_el"] as? String ?? ""
        self.descriptionEn = descriptionEn
        body = lines[(end + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

nonisolated enum LabourContractTemplateRouter {
    /// The answer when no template fits (a question about pay or leave, another kind of contract).
    static let noTemplate = "none"

    /// The templates shipped in the app (`NN_<id>.md`), in their numbered order.
    static func bundledTemplates(bundle: Bundle = .main) -> [LabourContractTemplate] {
        let urls = (bundle.urls(forResourcesWithExtension: "md", subdirectory: nil) ?? [])
            + (bundle.urls(forResourcesWithExtension: "md", subdirectory: "LabourContractTemplates") ?? [])
        var seen = Set<String>()
        return urls
            .filter { $0.lastPathComponent.range(of: #"^\d\d_[a-z_]+\.md$"#, options: .regularExpression) != nil }
            .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
            .compactMap(LabourContractTemplate.init(markdown:))
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.number < $1.number }
    }

    enum Method: String, Sendable {
        case model
        case keywords
    }

    struct Decision: Sendable {
        /// The chosen template, nil for none.
        let template: LabourContractTemplate?
        let method: Method
        /// The request as the model read it (the English translation of a Greek request).
        let promptEn: String
        /// The model's one-sentence reading of the request; empty for the keyword route.
        let reason: String
    }

    /// The template for `prompt`, by the on-device model when it is available and by keywords
    /// otherwise (or when the model fails).
    static func route(
        _ prompt: String,
        templates: [LabourContractTemplate] = bundledTemplates(),
        translate: (String) async throws -> String = { try await LocalNeuralTranslator.shared.translate($0, direction: .greekToEnglish) }
    ) async -> Decision {
        let isGreek = GreekLegalEntityMasker.greekLetterRatio(prompt) >= 0.3
        let promptEn = isGreek ? ((try? await translate(prompt)) ?? prompt) : prompt
        if SystemLanguageModel.default.isAvailable {
            do {
                let (id, reason) = try await modelChoice(promptEn: promptEn, templates: templates)
                Log.info("[TemplateRouter] Model chose \(id): \(reason)", category: .llm)
                return Decision(template: templates.first { $0.id == id }, method: .model, promptEn: promptEn, reason: reason)
            } catch {
                Log.warning("[TemplateRouter] Model choice failed: \(error.localizedDescription)", category: .llm)
                // A request about employing a minor can trip the default guardrails (apprenticeship
                // prompts of the dev split): ask again for plain text under the permissive ones.
                if let generationError = error as? LanguageModelSession.GenerationError, case .guardrailViolation = generationError,
                   let id = try? await textChoice(promptEn: promptEn, templates: templates) {
                    Log.info("[TemplateRouter] Model chose \(id) as plain text", category: .llm)
                    return Decision(template: templates.first { $0.id == id }, method: .model, promptEn: promptEn, reason: "")
                }
            }
        }
        let id = keywordChoice(prompt: prompt + "\n" + promptEn, templates: templates)
        return Decision(template: templates.first { $0.id == id }, method: .keywords, promptEn: promptEn, reason: "")
    }

    // MARK: On-device model

    static func instructions(templates: [LabourContractTemplate], idOnly: Bool = false) -> String {
        let list = templates.map { "- \($0.id): \($0.titleEn). \($0.descriptionEn)" }.joined(separator: "\n")
        return """
            You choose which Greek employment contract template an employer's request needs. The templates:
            \(list)
            - \(noTemplate): the request does not ask for an employment contract, for example a question about wages, leave, dismissal or tax, or a contract that is not about employing someone.
            \(idOnly ? "Reply with the id of the one template that fits the request best, and nothing else." : "First say in one sentence what work arrangement the request describes, then give the id of the one template that fits it best.")
            """
    }

    static func modelChoice(promptEn: String, templates: [LabourContractTemplate]) async throws -> (id: String, reason: String) {
        let ids = templates.map(\.id) + [noTemplate]
        let root = DynamicGenerationSchema(name: "TemplateChoice", properties: [
            .init(name: "reason", description: "One sentence: the work arrangement the request describes",
                  schema: DynamicGenerationSchema(type: String.self)),
            .init(name: "templateId", description: "The id of the template that fits",
                  schema: DynamicGenerationSchema(name: "TemplateId", anyOf: ids)),
        ])
        let schema = try GenerationSchema(root: root, dependencies: [])
        let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions(templates: templates))
        let response = try await session.respond(
            to: "Request: \(promptEn)", schema: schema, options: GenerationOptions(samplingMode: .greedy))
        let id = try response.content.value(String.self, forProperty: "templateId")
        let reason = (try? response.content.value(String.self, forProperty: "reason")) ?? ""
        return (id, reason)
    }

    /// The model's choice as plain text under the permissive guardrails, which apply to text replies:
    /// the first template id the reply names, or nil.
    static func textChoice(promptEn: String, templates: [LabourContractTemplate]) async throws -> String? {
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        let session = LanguageModelSession(model: model, instructions: instructions(templates: templates, idOnly: true))
        let reply = try await session.respond(to: "Request: \(promptEn)", options: GenerationOptions(samplingMode: .greedy)).content.lowercased()
        return (templates.map(\.id) + [noTemplate])
            .compactMap { id in reply.range(of: id).map { (id: id, at: $0.lowerBound) } }
            .min { $0.at < $1.at }?.id
    }

    // MARK: Keywords

    /// How many of each template's keywords (Greek and English) are in the text: a keyword counts
    /// when each of its words starts a word of the text, endings ignored ("φοιτήτρια" for
    /// "φοιτητής" doesn't count, "remotely" for "remote" does).
    static func keywordScores(text: String, templates: [LabourContractTemplate]) -> [String: Int] {
        let words = Set(searchWords(text))
        var scores: [String: Int] = [:]
        for template in templates {
            scores[template.id] = (template.keywordsEl + template.keywordsEn).filter { keyword in
                let parts = searchWords(keyword)
                return !parts.isEmpty && parts.allSatisfy { part in
                    let stem = part.count > 5 ? String(part.dropLast(2)) : part
                    return words.contains { $0.hasPrefix(stem) }
                }
            }.count
        }
        return scores
    }

    /// The template with the most keywords in the text, nil when none has any or two tie.
    static func keywordChoice(prompt: String, templates: [LabourContractTemplate]) -> String? {
        let ranked = keywordScores(text: prompt, templates: templates).sorted { $0.value > $1.value }
        guard let best = ranked.first, best.value > 0 else { return nil }
        if ranked.count > 1, ranked[1].value == best.value { return nil }
        return best.key
    }

    private static func searchWords(_ text: String) -> [String] {
        SQLiteFullTextService.greekSearchFold(text)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 }
    }
}
