# Plan: Make the route planner greedy (E22)

**Status:** implemented 15 Nov 2026
**Goal:** Stop `QueryExecutionPlannerService.buildPlan` from sampling randomly in `buildFoundationModelPlan`, eliminating run-to-run route flips across `GreekLabourCode` and `GreekLabourLibrary` Q&A evaluations, and measure the `dev` splits before and after.

## Background

In E20 (`Docs/Thesis/EXPERIMENTS.md`), 2 of 6 `GreekLabourCode` `dev` rerun questions and ~8 of 24 `GreekLabourLibrary` `dev` questions varied between runs under identical inputs, and occasional questions escalated into 220–470 s agentic runs. Inspection of `Firiki/Services/Query/Analysis/QueryExecutionPlannerService.swift` shows that `buildFoundationModelPlan` calls `session.respond(to: prompt, generating: GuidedQueryExecutionPlan.self)` at line 382 without passing `GenerationOptions(samplingMode: .greedy)`, whereas the Q&A generator, classifier, summarizer, and template router already use greedy decoding.

## Planned changes

1. `Firiki/Services/Query/Analysis/QueryExecutionPlannerService.swift`:
   - Pass `options: Self.foundationModelGenerationOptions` (`GenerationOptions(samplingMode: .greedy)`) to `session.respond(to: prompt, generating: GuidedQueryExecutionPlan.self, options: ...)` in `buildFoundationModelPlan`.
2. `FirikiTests/Services/Query/QueryExecutionPlannerDeterminismTests.swift`:
   - Add Swift Testing unit tests verifying greedy `GenerationOptions` configuration (under `#if canImport(FoundationModels)`) and confirming that calling `QueryExecutionPlannerService.shared.buildPlan(...)` repeatedly on identical queries yields consistent plans when Apple Foundation Models are available.
3. Measure & verify on `dev` splits (using existing E20 `dev` runs at `HEAD` `57f2552e` as the "before" baseline, and running both `dev` sets + a rerun check after the edit):
   - `GreekLabourCode` (`corpus=excerpt`, `split=dev`) before E20 (`37 of 46`, `1381 s`) vs after E22.
   - `GreekLabourLibrary` (`corpus=library`, `split=dev`) before E20 (`14 of 24`, `1217 s`) vs after E22, plus a deterministic subset rerun check on the 6 Labour Code questions (`1,10,26,50,59,68`) or repeated library/code subset.
4. Record E22 in `Docs/Thesis/FORK_CHANGES.md`, `CHANGELOG.md`, `Docs/Thesis/METHODS_SUMMARY.md`, `Docs/Thesis/EXPERIMENTS.md`, `Docs/Thesis/experiments/runs/` (`.txt` + appended rows in `INDEX.md`), and `POC_PROGRESS.md`; commit added files by name and push to `origin main`.
