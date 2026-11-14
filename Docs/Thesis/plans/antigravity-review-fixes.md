# Plan: fixes from the review of Antigravity's work (14 Nov 2026)

Status: implemented 15 Nov 2026 (the owner asked to continue without approvals). Measurements in
`EXPERIMENTS.md` E20 and E21.

## Findings and what was done

1. **Library dev 15 → 14 of 24 in E17 (case 34) and no Labour Code rerun.**
   - Both builds were measured on the same library; the Labour Code difference is run variation
     from the sampled route planner (E20).
   - Case 34 fails on both builds. The named-statute refusal now needs the named article of the
     Constitution, not any mention of the Constitution (`GreekLegalAnswerService.swift`).
2. **Summaries 70% slower (E18).** The cap of 2 articles per call was measured against 3 and no
   cap (E21). The slowdown comes from reading 19 more passages, and no cap gives 6 of 6
   provisions, so the cap is removed (`GreekLegalDocumentSummarizer.articlesPerGroup = nil`).
3. **E18's contents-page cut used the last "Article 1"**, which would drop real articles before a
   quoted Article 1. It now uses the first one, with a test.
4. **The README results table misled.**
   - Each re-run figure is dated, and the opinion test figure is marked as measured before E17 and
     E18.
   - The "run-to-run variation" note now says which runs vary (Q&A, from the sampled planner) and
     which don't (greedy summaries and opinions).
   - The summary time is given.
5. **The full suite took 11 minutes.** The demo PDF tests are opt-in (`OI_DEMO_PDFS=1`), and
   `scripts/demo_check.sh` sets it.
6. **Nothing was checked in the Mac app:** the demo prompts and demo mode are checked there.

## Files

- `Firiki/Services/RAG/Safety/GreekLegalAnswerService.swift`
- `Firiki/Services/Legal/GreekLegalDocumentSummarizer.swift`
- `FirikiTests/Services/GreekLegal/GreekLegalPipelineTests.swift`
- `FirikiTests/Services/GreekLegal/GreekLegalSummaryTests.swift`
- `FirikiTests/Services/GreekLegal/GreekDemoPDFImportTests.swift`
- `scripts/demo_check.sh`
- `README.md`
- The records.
