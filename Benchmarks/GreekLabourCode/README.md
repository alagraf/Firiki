# Greek labour-law QA set (v1)

Evaluation set for the thesis fork's Greek legal assistant. It is test data only: nothing here is
read by the app, and no answer is put into the app.

## Source

- **Corpus:** the Labour Code, Π.Δ. 62/2025 «Κώδικας Εργατικού Δικαίου», ΦΕΚ Α' 121/11.07.2025
  (it replaced Π.Δ. 80/2022). The official Government Gazette PDF was provided by the owner.
- `pd_62_2025_fek_a121.pdf`: that PDF, unchanged (260 pages, sha1
  `03039d0415d086e1405ec7662e1cba38509fccaf`). Pages 1–17 are the table of contents; the articles
  (1 to 588) run from page 17; the correlation tables follow the last article.
- `pd_62_2025_excerpt.pdf`: 37 whole, unmodified pages of it, for fast iteration (an import of the
  full code takes far longer): pages 1, 17, 18, 29, 30, 31, 40, 47, 48, 49, 67, 71, 74, 75, 76, 84,
  85, 86, 87, 89, 90, 91, 92, 93, 94, 107, 113, 114, 115, 116, 117, 118, 150, 200, 214, 215, 240.
  Each article a question rests on is there whole (from its start page to the start of the next
  article); the neighbouring articles on those pages and pages 40, 150, 200 and 240 are
  distractors. Made with pypdf (`PdfWriter.add_page`).

## Questions (`labour_qa_v1.jsonl`)

69 cases: 61 answerable and 8 that must be refused. Fields as in `../GreekConstitution/
syntagma_qa_v1.jsonl` plus `topic`, `split` and `shouldAbstain`:

- `question` (Greek), `expectedAnswer` (Greek, citing «Άρθρο N παρ. M Π.Δ. 62/2025» with the
  code's own article numbers), `article` (the article the answer rests on; 0 for a refusal that
  names none).
- `keyFacts`: regular expressions over the answer after lower-casing and removing accents (final
  sigma as sigma). They accept digits or number words ("(11|εντεκα)") and inflections; every one
  must match. A case passes only if the app also did not abstain.
- `shouldAbstain: true`: the app must give its Greek abstention (an article the code does not have,
  another law, tax, pensions, unemployment benefit, another country, the Constitution).
- `split`: every third case is `test` (23), the rest `dev` (46); levels and topics are mixed in
  both. Iterate on `dev` only; run `test` once per round.

Topics: annual leave (221–226, 175), working time, breaks, rest and overtime (171–174, 187, 193,
194, 219), wages (3, 8, 9, 157), part-time (113), probation, notice and termination (2, 325, 331,
336, 341, 348), severance (333, 334, 337, 338), maternity, paternity and family leave including
dismissal protection during pregnancy (230, 236, 239, 241, 242, 250, 291), violence and harassment
(60, 65), digital work card (580); 6 cross-reference questions (336→2, 334→331, 348→331, 173→171,
193→187, 341→337) and 6 phrased without legal terms.

## Changes to the grading patterns

Recorded in `Docs/Thesis/FORK_CHANGES.md` 2.11.12, each after a correct answer was rejected: case
32 also accepts "γραπτώς" (in writing); case 31 also accepts «σοβαρός λόγος»; and every
"number then unit" fact (17 cases, changed before the test split was first run) accepts a few
words between the whole-word number and its unit ("δώδεκα πρώτους (12) μήνες").

## How the answers were drawn

The PDF's text was extracted page by page with pypdf; each answer was taken from the text of the
article it cites (read in full, from its heading to the next heading), quoted or closely
paraphrased. Where the code points to another article, both were read.

Start pages of the articles used: 2 p.17, 3 p.18, 8 p.18, 9 p.18, 60 p.29, 65 p.31, 113 p.47,
157 p.67, 171–175 p.71, 187 p.74, 193 p.75, 194 p.76, 219 p.84, 221 p.84, 222–224 p.85, 225–226
p.86, 230 p.87, 236 p.89, 239 p.91, 241–242 p.92, 250 p.93, 291 p.107, 325 p.113, 331 and 333
p.114, 334 p.115, 336–338 and 341 p.116, 348 p.118, 580 p.214.

## Running it

```bash
TEST_RUNNER_OI_GREEK_EVAL=1 TEST_RUNNER_OI_GREEK_EVAL_SET=GreekLabourCode TEST_RUNNER_OI_GREEK_EVAL_SPLIT=dev TEST_RUNNER_OI_GREEK_EVAL_CORPUS=excerpt scripts/thesis_run_tests.sh /private/tmp/oi-logs/labour.log -only-testing:OpenIntelligenceTests/GreekConstitutionEvaluationTests
```

`TEST_RUNNER_OI_GREEK_EVAL_CORPUS=full` uses the whole code (set `OI_TEST_TIMEOUT_SECONDS` above
the default 1800 for its import). Results are the `[GreekEval]` lines and the summary at the end.
