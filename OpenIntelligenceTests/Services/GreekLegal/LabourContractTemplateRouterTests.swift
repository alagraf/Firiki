//
//  LabourContractTemplateRouterTests.swift
//  OpenIntelligenceTests
//
//  Thesis fork (PoC capability 4): the template files and the keyword route as unit tests; the
//  routing set (`Benchmarks/LabourContractTemplates/routing_v1.jsonl`, 66 prompts labelled with a
//  template id or "none") through the whole router as an opt-in evaluation:
//  `TEST_RUNNER_OI_TEMPLATE_ROUTING=1`, with `TEST_RUNNER_OI_TEMPLATE_ROUTING_SPLIT` set to `dev`
//  (the default) or `test`. It prints one line a prompt, the accuracy of the model route and of the
//  keyword route, and a confusion table (expected → chosen). Tune on the dev split only.
//

import Foundation
import Testing
@testable import OpenIntelligence

@Suite("Labour contract templates")
struct LabourContractTemplateTests {
    @Test func tenTemplatesShipWithTheirFrontMatter() throws {
        let templates = LabourContractTemplateRouter.bundledTemplates()
        #expect(templates.map(\.number) == Array(1...10))
        #expect(Set(templates.map(\.id)).count == 10)
        for template in templates {
            #expect(!template.keywordsEl.isEmpty && !template.keywordsEn.isEmpty, "\(template.id)")
            #expect(!template.descriptionEn.isEmpty && !template.titleEl.isEmpty, "\(template.id)")
            #expect(template.body.hasPrefix("# "), "\(template.id)")
            #expect(template.body.contains("{{"), "\(template.id) has placeholders")
        }
    }

    /// A Greek answer shows a Greek reason built from the template, and the place of signing as a
    /// visible blank (9 Nov 2026: the model's English reason and «Στ{{place_of_signing}}»).
    @Test func greekAnswerHasAGreekReasonAndABlankPlace() throws {
        let telework = try #require(LabourContractTemplateRouter.bundledTemplates().first { $0.id == "telework" })
        let reason = LabourContractTemplateRouter.greekReason(for: telework)
        #expect(reason.hasPrefix("Το αίτημα ταιριάζει στο υπόδειγμα «Σύμβαση τηλεργασίας»: Εργασία που παρέχεται εξ αποστάσεως"))
        #expect(GreekLegalEntityMasker.greekLetterRatio(reason) > 0.9)
        let body = LabourContractTemplateRouter.displayedBody(telework)
        #expect(!body.contains("{{place_of_signing}}"))
        #expect(body.contains("Στ……… σήμερα, {{date_of_signing}}"))
        #expect(body.contains("Η εργασία παρέχεται στ………."), "the workplace too")
        #expect(body.contains("{{employer_name}}"), "a field with a space before it keeps its name")
    }

    @Test func frontMatterIsParsed() throws {
        let template = try #require(LabourContractTemplate(markdown: """
            ---
            id: "telework"
            number: 6
            title_el: "Σύμβαση τηλεργασίας"
            title_en: "Telework (remote work) contract"
            articles: ["Π.Δ. 62/2025 άρθρα 73, 130–134"]
            keywords_el: ["τηλεργασία", "από το σπίτι"]
            keywords_en: ["telework", "work from home"]
            description_en: "Work done remotely."
            ---

            # Σύμβαση τηλεργασίας
            """))
        #expect(template.id == "telework" && template.number == 6)
        #expect(template.keywordsEl == ["τηλεργασία", "από το σπίτι"])
        #expect(template.body == "# Σύμβαση τηλεργασίας")
        #expect(LabourContractTemplate(markdown: "# No front matter") == nil)
    }

    @Test func keywordsMatchWordStartsInBothLanguages() {
        let templates = LabourContractTemplateRouter.bundledTemplates()
        #expect(LabourContractTemplateRouter.keywordChoice(
            prompt: "Θα δουλεύει από το σπίτι με τηλεργασία.", templates: templates) == "telework")
        #expect(LabourContractTemplateRouter.keywordChoice(
            prompt: "A staffing agency is sending us a temp.", templates: templates) == "temporary_agency")
        // The age alone, as Greek writes it ("ένας 15χρονος"), points to apprenticeship.
        #expect(LabourContractTemplateRouter.keywordChoice(
            prompt: "Ένας 15χρονος θα μάθει τη δουλειά στο συνεργείο μας.", templates: templates) == "apprenticeship")
        #expect(LabourContractTemplateRouter.keywordChoice(
            prompt: "What is the minimum wage?", templates: templates) == nil)
    }

    @Test func instructionsListEveryTemplateAndNone() {
        let templates = LabourContractTemplateRouter.bundledTemplates()
        let instructions = LabourContractTemplateRouter.instructions(templates: templates)
        for template in templates { #expect(instructions.contains("- \(template.id):")) }
        #expect(instructions.contains("- none:"))
    }
}

/// One prompt of the routing set.
private struct RoutingCase: Decodable {
    let id: Int
    let lang: String
    let prompt: String
    let template: String
    let split: String
}

@Suite("Template routing evaluation", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["OI_TEMPLATE_ROUTING"] == "1"))
struct LabourContractTemplateRoutingEvaluation {
    @Test(.timeLimit(.minutes(30)))
    func routingSet() async throws {
        let split = ProcessInfo.processInfo.environment["OI_TEMPLATE_ROUTING_SPLIT"] ?? "dev"
        let file = GreekEvalCase.repository.appendingPathComponent("Benchmarks/LabourContractTemplates/routing_v1.jsonl")
        let cases = try String(contentsOf: file, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.hasPrefix("//") && !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { try JSONDecoder().decode(RoutingCase.self, from: Data($0.utf8)) }
            .filter { $0.split == split }
        let templates = LabourContractTemplateRouter.bundledTemplates()
        try #require(templates.count == 10)
        var modelRight = 0, keywordRight = 0, viaModel = 0
        var confusion: [String: Int] = [:]
        for routing in cases {
            let decision = await LabourContractTemplateRouter.route(routing.prompt, templates: templates)
            let chosen = decision.template?.id ?? LabourContractTemplateRouter.noTemplate
            let keyword = LabourContractTemplateRouter.keywordChoice(
                prompt: routing.prompt + "\n" + decision.promptEn, templates: templates) ?? LabourContractTemplateRouter.noTemplate
            if decision.method == .model { viaModel += 1 }
            if chosen == routing.template { modelRight += 1 }
            if keyword == routing.template { keywordRight += 1 }
            if chosen != routing.template { confusion["\(routing.template) → \(chosen)", default: 0] += 1 }
            print("[TemplateRouting] case \(routing.id) \(routing.lang) expected=\(routing.template) chosen=\(chosen) via=\(decision.method.rawValue) keywords=\(keyword) \(chosen == routing.template ? "PASS" : "FAIL") | en: \(decision.promptEn) | reason: \(decision.reason)")
        }
        print("[TemplateRouting] summary split=\(split): router \(modelRight) of \(cases.count) (\(viaModel) by the model), keywords alone \(keywordRight) of \(cases.count)")
        for (pair, count) in confusion.sorted(by: { $0.key < $1.key }) {
            print("[TemplateRouting] confusion \(pair): \(count)")
        }
        #expect(!cases.isEmpty)
    }
}
