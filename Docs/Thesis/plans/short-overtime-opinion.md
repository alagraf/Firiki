# Plan: Short overtime question in legal opinions (Task 3)

**Status:** implemented 14 Nov 2026

## Baseline diagnosis (`Benchmarks/GreekLabourLibrary/opinion_qa_v1.jsonl` Q11, `dev`)

- Added Q11 (`split: "dev"`): «Θέλω γνωμοδότηση: ο εργοδότης ζητά τέσσερις ώρες υπερωρία την ημέρα. Επιτρέπεται;»
- Dev baseline (`firiki-opinion-dev8-short-baseline`):
  - Overall `split=dev`: `citations 12 of 14, key facts 15 of 22, refused 0 of 7`.
  - Q11 logged `[GreekOpinion] | 11 | dev | written | citations 2 of 2 | other articles cited [9, 12, 191, 192, 404] | facts 2 of 2 | dropped 0 | 26 s |`, **but the actual conclusion (`Συμπέρασμα`) was wrong**:
    - `Sources`: `pd_62_2025_fek_a121.pdf 0.58 ["ART:191", "ART:192"]`, `n_5239_2025_fek_a178.pdf 0.57 ["ART:7"]`, `n_5278_2026_fek_a22.pdf 0.37 ["ART:9"]`.
    - `PD:62/2025` retrieved sixth-day Articles 191–192 ahead of `Law 5239/2025` (`0.58` vs `0.57`), `n_5278_2026` at `0.37` (`0.64` of top) added unrelated collective agreement Article 9/404, and `Συμπέρασμα` concluded *"Ο εργοδότης δεν μπορεί να απαιτήσει 4 ώρες υπερωρίας την ημέρα"* (citing Article 192).

### Root causes

1. **Greek query dropped from scoped opinion retrieval**: `RAGService.greekLegalOpinion` called `searchDocumentsRaw(query: questionEn, ...)` without the Greek question, so `HybridSearchService.searchInsideScope` never ran `SQLiteFullTextService.shared.searchGreekChunks` (`source_text_el`) and never scored Greek stem matches.
2. **Question framing & standalone «Επιτρέπεται;»**: Leading `"Θέλω γνωμοδότηση:"` added embedding/prompt noise, and standalone `"Επιτρέπεται;"` translated as `"May I?"`.
3. **Source threshold, statutory ordering, multi-article expansion, and special-case scope**:
   - `relativeScore = 0.6` admitted `n_5278_2026` at `0.37 / 0.58 = 0.64`.
   - `PD:62/2025` (`0.58`) was ordered ahead of later amending law `Law 5239/2025` (`0.57`).
   - Expanding every amending article hit in `withWholeAmendingArticles` could append 12 chunks of a neighbouring article (`ART:8` / Art 202) behind `ART:7`.
   - `sectionInstructions` and `conclusionInstructions` did not tell the model that general limits (`"up to"`) permit requests within the limit and that special-case rules (daily-ceiling shifting without Saturdays, sixth day, minors) do not override general rules unless asked.

## Implemented changes (dev-split driven; general mechanisms only)

1. **`Firiki/Services/RAG/Orchestration/RAGService.swift`**:
   - Added `normalizedGreekQuery(_:)` in `greekQueryTranslation` replacing standalone impersonal `"Επιτρέπεται;"` with `"Επιτρέπεται αυτό;"` (`"Is that allowed?"` instead of `"May I?"`) while leaving clauses like `"Επιτρέπεται η υπερωρία;"` untouched.
   - Added optional `originalQuery: String? = nil` parameter to `searchDocumentsRaw` and forwarded `originalQuery ?? (translatedQuery.wasTranslated ? query : translatedQuery.text)` to `hybridSearch.search`.
2. **`Firiki/Services/Storage/SQLiteFullTextService.swift`**:
   - Extracted shared `greekQueryStems(_:)` helper reused by `greekFTSQuery(_:)` and scoped retrieval, and added `"επιτρεπεται"`, `"επιτρεπονται"`, `"επιτρεπτο"` to `greekQueryStopWords` so generic permissive phrasing does not match every statute article.
3. **`Firiki/Services/RAG/Retrieval/HybridSearchService.swift`**:
   - Updated `searchInsideScope` so Greek scoped queries (`Self.greekQuestion(originalQuery: boostQuery)`) query both English FTS5 (`searchChunks(query: query, ...)`) and Greek FTS5 (`SQLiteFullTextService.shared.searchGreekChunks`), and score English tokens against `chunk.content` plus `SQLiteFullTextService.greekQueryStems` against `greekSearchFold(chunk.sourceTextEl)`.
4. **`Firiki/Services/Legal/GreekLegalOpinionWriter.swift`**:
   - Added `strippedOpinionFraming(_:)` so opinion-request prefixes/suffixes are removed from the retrieval/translation/prompt query while keeping the user's question verbatim in `Ερώτημα`.
   - Passed `originalQuery: searchQuestion` into `searchDocumentsRaw`.
   - Raised `relativeScore` from `0.6` to `0.68`, and sorted `selectSources` so later amending/implementing statutes come ahead of `PD:62/2025`.
   - Updated `withWholeAmendingArticles` to expand the top-scoring amending article found in `source.passages` instead of flooding the prompt with secondary neighbouring articles.
   - Updated `sectionInstructions` and `conclusionInstructions` to separate special-case arrangements from general limits and state that an act within a statute's `"up to"` general limit is permitted unless the question asks about a special case.
5. **`FirikiTests/Services/GreekLegal/GreekLegalOpinionTests.swift`**:
   - Added `opinionFramingIsStrippedAndLaterLawsPrecedeTheCode()` verifying `strippedOpinionFraming`, `normalizedGreekQuery`, `selectSources` pruning/ordering, instruction wording, and `greekQueryStems`.
6. **Open question resolution**:
   - Chosen option (recommended): fix scoped bilingual retrieval + source pruning/ordering + general vs special-case instruction together rather than adding a one-off rule for Article 191/192 or Q11.

## Verification

- `GreekLegalOpinionTests` + `GreekLegalOpinionEvaluation` (`split=dev`, run `firiki-opinion-dev9-short-overtime`): `** TEST BUILD SUCCEEDED **`, `✔ Test run with 16 tests in 2 suites passed after 218.982 seconds.`, `[GreekOpinion] summary split=dev: citations 12 of 14, key facts 15 of 22, refused 0 of 7`; Q11: `citations 2 of 2 | other articles cited [12, 188, 191, 192] | facts 2 of 2 | dropped 0`, `Συμπέρασμα` now explicitly states *"επιτρέπονται 4 ώρες νόμιμης υπερωρίας ανά ημέρα, μέχρι συνολικά 150 ώρες ετησίως... καμία ειδική εξαίρεση για μια εβδομάδα εργασίας 6 ημερών δεν υπερισχύει"*.
- `GreekConstitutionEvaluationTests` (`GreekLabourLibrary`, `corpus=library`, `split=dev`, run `firiki-library-dev9-short-overtime`): `** TEST BUILD SUCCEEDED **`, `[GreekEval] summary set=GreekLabourLibrary corpus=library split=dev: passed 14 of 24` (`answer pass 13 of 21; retrieval hit 18 of 21; right documents retrieved 21 of 21; abstention correct 1 of 3`), `✔ Test run with 1 test in 1 suite passed after 1155.432 seconds.`
- `GreekKeywordArmTests` + `GreekTranslationRetrievalTests`: `✔ Test run with 15 tests in 2 suites passed after 3.169 seconds.`
