import Foundation
import Testing
#if canImport(FoundationModels)
import FoundationModels
#endif

@testable import Firiki

@Suite("Query execution planner determinism")
struct QueryExecutionPlannerDeterminismTests {
    @Test("Foundation Models route planner configures greedy sampling")
    func usesGreedySamplingOptions() {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            #expect(QueryExecutionPlannerService.foundationModelGenerationOptions.samplingMode == .greedy)
        }
        #endif
    }

    @Test("Repeated planning calls for identical queries produce identical routes")
    func repeatedBuildPlanIsConsistent() async {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *),
              SystemLanguageModel.default.availability == .available
        else { return }

        let planner = QueryExecutionPlannerService.shared
        let queries = [
            "What does Article 221 state about night work pay?",
            "Does Article 113 still apply under Law 5239/2025 or is it repealed?",
        ]

        for query in queries {
            let first = await planner.buildPlan(for: query, requestedQualityMode: .standard, allowToolCalling: true)
            let second = await planner.buildPlan(for: query, requestedQualityMode: .standard, allowToolCalling: true)
            #expect(first.needsRetrieval == second.needsRetrieval)
            #expect(first.executionMode == second.executionMode)
            #expect(first.preferLiteralQuery == second.preferLiteralQuery)
            #expect(first.useToolCalling == second.useToolCalling)
            #expect(first.useStructuredEvidenceLookup == second.useStructuredEvidenceLookup)
            #expect(first.searchQueries == second.searchQueries)
            #expect(first.subqueries == second.subqueries)
        }
        #endif
    }
}
