# Experiments record

Every experiment that can serve the thesis's evaluation chapter: what was tried, the hypothesis,
the runs, the numbers, and the outcome, including experiments whose hypothesis the measurement did
not support and changes that were dropped. The result lines of each run are kept in
`experiments/runs/` (`INDEX.md` lists them; regenerate with
`python3 scripts/thesis/collect_run_results.py`). Per-change detail (files, tests) is in
`FORK_CHANGES.md`; the high-level results table is in `METHODS_SUMMARY.md`.

**Conventions.**
- Commit hashes in this file are from before the 13 Nov 2026 identity rewrite; `COMMIT_HASH_MAP.md` (local, git-ignored) gives each one's current hash.
- All runs are in the iOS 27 Simulator (`iPhone 18 Pro`) on an M3 Pro Mac (18 GB), with Apple's on-device model (`AFM 3 Core Advanced`, 8,192-token window), greedy decoding.
- All benchmark numbers and run logs in `experiments/runs/` come from the 29–30 October 2026 runs (up to commit `e85ae0cc` / `ffff0241`), prior to the 31 October post-evaluation refinements (`2af92e2e`–`f10190e1`, which updated `Αρ.` entity masking, worker-origin foreign-jurisdiction checks, whole-word passage overlap, spelled-number fraction filtering, long-segment translation splitting, OCR benchmark line-end dehyphenation, and context-aware chunking / in-chat routing).
- "Dev" is tuned on; "test" is run once per milestone and never tuned on. The EU holdout is
  evaluation only (AGENTS.md step 5): only its counts are recorded.
- Run-to-run variation: on the Labour Code dev split (46), identical-code runs (`labour15` and `labour16`) differed on 1 question (Case 31), while across development iterations 2 to 8 questions flipped between pass and fail. On the 24-question library dev split, 2 to 3 flips per run were seen. A difference of 1–3 questions in one run is within this variation.
- A per-case table lists only the questions whose result changed.

## Earlier experiments (2026-10-28 to 2026-10-30, before the PoC capabilities)

Recorded in `FORK_CHANGES.md`; the run files are in `experiments/runs/`.

| Experiment | Section | Result |
|---|---|---|
| Constitution accuracy: article lookup, Greek keyword arm, whole provisions | 2.11.9 | 6 → 9 of 10 |
| Translator: tc-big both directions, decoder key/value cache | 2.11.10 | about 3.5× faster decoding |
| Structure-aware chunking of statutes | 2.11.11 | see 2.11.13 |
| Labour Code dev split, excerpt corpus, fixes | 2.11.12–2.11.13 | 24 → 31 of 46; test 14 of 23 |
| Out-of-scope refusals, glossary Greek, figures tied to their case | 2.11.14 | 37 of 46; refusals 5 of 5 |
| EU holdout before/after (bare model, original app, fork) | 2.11.15–2.11.16 | see the holdout section below |
| Faster translation; batch translation tried and dropped | 2.11.17 | batching changed translations and lowered accuracy (Constitution 6 of 10 at batch 4) |
| OCR benchmark: clean, scanned, photographed pages | 2.11.19 | PaddleOCR 96% / 48% / 96% of words; Vision 5% |
| OCR boxes follow tilted lines | 2.11.22 | scans 48% → 96%; 13 other tilted pages 46% → 88% |
| Table rows; off-topic figure no longer refuses | 2.11.23–2.11.24 | 36 and 35 of 46 (35 before) |
| Per-document statute key; named-statute refusal | 2.11.25 | Constitution 8 of 10; Labour dev 38 of 46 |
| Template routing | 2.11.26 | dev 43 of 44, test 20 of 22; keywords alone 26 of 44, 8 of 22 |

## E1. Five-document library: search the named law's document only (2026-10-30)

- **Observation (dev, baseline `library1`, 13 of 24):** 6 of the 11 failed questions name a law
  of the library ("σύμφωνα με τον ν. 5278/2026": 1, 8, 10, 13, 17, 19). Passages from the other
  laws, mostly the Labour Code's 4,200, took the slots that reach the model.
- **Change:** when a Greek question names a statute that is a document of the library, retrieval
  runs only in that document (the app's existing per-question document scope, used by the
  Shortcuts action "Ask About a Document"; article lookup draws from the same narrowed pool). A
  question naming no statute, or one outside the library, is unchanged (the latter is still
  refused, 2.11.25).
- **Hypothesis:** the six failed questions that name a law improve; the four that don't (11, 16,
  30, 32) don't change.
- **Run `library2`:** 11 of 24.

| Case | `library1` | `library2` |
|---|---|---|
| 2 | PASS | FAIL |
| 36 | PASS | FAIL |

- **Outcome: not supported.** None of the six law-naming questions changed. Of the six, 1 passed in
  `library3` and failed again in `library4`/`library5`; 10 passed only after the import fix (E4);
  8, 13, 17, 19 still fail in the final run. Case 2 failed because of the extractive shortcut (E2).

## E2. Five-document library: contents left out, no extractive shortcut (2026-10-30)

- **Observation (`library2`):** inside the named document, its title page and contents (which list
  every article's title) outranked the articles. The extractive shortcut replaced two Greek legal
  answers with a sentence picked from a passage ("62/2025", cases 1 and 2).
- **Change:** passages before a document's first article heading are left out when the document
  has articles; the extractive override is off in Greek legal mode.
- **Run `library3`:** 12 of 24. Against `library1`: case 1 FAIL → PASS; 7 and 23 PASS → FAIL.
- **Outcome:** cases 1 and 2 answered by the model again; overall within the variation.

## E3. Import: one-column Gazette pages read as two columns (2026-10-30)

- **Observation:** a stored-chunk audit showed Law 5278/2026 with 8 of its 16 articles (1, 2, 3, 5,
  8, 9 missing). The column detector found two columns on every page of Laws 5278 and 5316 and of
  decision 8934, whose text runs the full width.
- **Hypothesis:** the false columns reorder the short lines and merge the article headings away.
- **Change:** a page whose median line is wider than half the page width is one column. Measured:
  one-column pages 0.56–0.79 of the width, two-column pages (Law 5239, the Code) 0.07–0.38. A
  first threshold of 60% would have misread one page of the decision (0.56).
- **Runs (reimported):** `library4` 12 of 24; `summary4` 2 of 6; `opinion3` citations 8 of 12,
  key facts 9 of 20. Stored articles: Law 5278 still 8 of 16; the Code 590 (articles 2, 72 and
  those from 589 on had been missing).
- **Outcome: partly supported.** The pages are now read as one column and the Code gained its
  missing articles, but Law 5278's headings were still lost: the diagnosis was incomplete (E4).

## E4. Import: word positions from the raw page text (2026-10-30)

- **Observation:** the stored text read "Άρθρο\n1 Σκοπός": the line broke after "Άρθρο", not
  before the title. The PDF itself has "Άρθρο 1" on one line. Run on the raw PDF text, the chunker
  found all 16 articles.
- **Cause (measured):** word positions were looked up with ranges taken from the NFKC-normalised
  page text, while the PDF reader counts the raw text. NFKC turns the keraia (U+0384, "Α΄") into two
  characters; page 2 of Law 5278 is 3,635 units raw and 3,641 normalised, and the range of "1"
  selected "κ" one line down.
- **Change:** ranges from the raw text; only the kept text is normalised (spatial extraction and
  the layout-aware extractor).
- **Runs (reimported):**

| Run | Result | Before (E3) |
|---|---|---|
| `library5` | 14 of 24 (cases 10 and 36 FAIL → PASS) | 12 of 24 |
| `summary5` | 5 of 6 provisions, 3 of 3 articles | 2 of 6, 0 of 3 |
| `opinion4` | citations 10 of 12, key facts 11 of 20, refused 0 of 6 | 8 of 12, 9 of 20 |
| `labour18` (Labour Code dev, regression check) | 38 of 46, refusals 5 of 5 | 38 of 46 |

  Stored articles: Law 5278 16 of 16; the Code 591.
- **Outcome: supported.** The largest single gain of the PoC work, on the summary and the opinion.
  The library Q&A gain over the baseline (13 → 14) is within the variation.

## E5. Glossary entry for «τρίμηνο» (2026-10-30, dropped)

- **Observation (`library5`, case 8):** the translator rendered «τρίμηνο» as "a quarter", which came
  back into Greek as «ένα τέταρτο» (one fourth).
- **Variant A, "three-month period":** `library6` 13 of 24 (case 8 FAIL → PASS; 7 and 23 PASS →
  FAIL); `labour19` 32 of 46. Labour Code case 4 came back as «πρώτη τρίμηνη περίοδο», which misses
  «πρώτο τρίμηνο»; cases 10, 11, 34, 46, 68 also flipped to FAIL, none involving the term.
- **Variant B, "three months":** `library7` 13 of 24 (case 8 PASS; 7 and 36 FAIL); `labour20` 36
  of 46. Case 4 came back as «τους τρεις πρώτους μήνες», correct but not the expected wording;
  case 8 of the Labour Code and 58 PASS, 10, 41, 50 FAIL.
- **Outcome: dropped.** Each variant traded one question for another; the general restoring step
  replaces a rendering only when it has the same number of words, which «τρίμηνη περίοδος» (two)
  against «τρίμηνο» (one) does not.

## E6. Summary of one statute: design iterations (dev, Law 5278/2026)

| Run | Design | Provisions | Articles cited |
|---|---|---|---|
| `summary1` | model writes the provisions list from all notes | 5 of 6 | 1 of 3; about 40 bullets, wrong article numbers ("404", "410") |
| `summary2` | article markers in each group | 1 of 6 | 1 of 3; articles 8 and 9 lost with their marker lines |
| `summary3` | provisions list built by the program, model writes the opening | 2 of 6 | 0 of 3 |
| `summary4` | + one-column pages (E3) | 2 of 6 | 0 of 3 |
| `summary5` | + raw-text positions (E4) | 5 of 6 | 3 of 3 |
| `summary8` | + reading by parts (E8; article path unchanged) | 5 of 6 | 3 of 3 |

- **Outcome:** with the model writing the list, the counts look good but the articles are wrong;
  the program-built list is right once the articles are imported (summaries 3–4 were limited by
  the import bug, not by the design).

## E7. Legal opinion: iterations (dev, 6 requests)

| Run | Change | Citations | Key facts | Refused |
|---|---|---|---|---|
| `opinion1` | first version | 9 of 12 | 12 of 20 | 1 of 6 |
| `opinion2` | per-document scoped search, contents left out | 9 of 12 | 9 of 20 | 0 of 6 |
| `opinion3` | + one-column pages (E3) | 8 of 12 | 9 of 20 | 0 of 6 |
| `opinion4` | + raw-text positions (E4) | 10 of 12 | 11 of 20 | 0 of 6 |

Request 5 (hiring for urgent needs) is answered from other articles in every run (0 of 2 citations).

## E8. Held-out test splits of the PoC capabilities (2026-10-30, once each)

| Run | Capability | Result | Dev |
|---|---|---|---|
| `librarytest1` | Five-document Q&A (12) | 6 of 12; right documents 6 of 11; refusals 1 of 1 | 14 of 24 |
| `summarytest1` | Summary, decision 8934 (5 provisions) | **0 of 5**: the decision has no articles, so no groups and an empty summary | 5 of 6 |
| `summarytest2` | Same, after reading a document without articles by parts | 4 of 5 (not held out: the fix answers what `summarytest1` showed) | 5 of 6 (`summary8`) |
| `opiniontest1` | Legal opinion (4) | citations 3 of 8, key facts 7 of 10, refused 0 of 4 | 10 of 12, 11 of 20 |

- Library test failures: 3 and 24 refused after the wrong documents were retrieved; 27 refused
  (Code article 244 not retrieved); 15 and 18 answered from the right article but missed a fact;
  31 answered from the Code's article without naming Law 5239.
- Opinion test: requests 7 and 8 cite other articles than the set expects; 9 misses one of its
  two; 10 cites both.

## E9. Labour Code test split over the full 260-page Code (2026-10-30, once)

- **Run `fullcodetest1`** (4,191 passages, imported in 862 s): **15 of 23** (12 of 23 on
  2026-10-29). Answerable 12 of 20, right article retrieved 18 of 20, 1 wrong refusal (33). Must
  refuse: 3 of 3, including case 69 (Article 16 *of the Constitution* asked of a Labour Code
  library, the named-statute refusal of 2.11.25).

## E10. EU holdout, current build (2026-10-30)

- **Run `holdout_fork4`** at `ffff0241`, passages reimported, 2,341 s. Graded with
  `scripts/thesis/holdout/regrade_holdout.py` (the grading of 2.11.16): right answers of the 12
  graded answerable questions (one has no expected terms), and refusals of the 3 unanswerable.

| Condition | `holdout_fork4` (2026-10-30) | `holdout_fork3` (2026-10-29) |
|---|---|---|
| English passages, English questions | 12 of 12, refused 3 of 3 | 12 of 12, 3 of 3 |
| Greek passages, English questions | 12 of 12, refused 3 of 3 | 12 of 12, 3 of 3 |
| Greek passages, Greek questions | 12 of 12, refused 3 of 3; all in Greek | 12 of 12, 3 of 3 |

  The right passage was retrieved for 13 of 13 in every condition, and no answerable question was
  refused. The developer's original grading (v1) gives 13 of 13 in each condition, with 1, 2 and 3
  of 3 declined. The owner's own grading sheet for this run is
  `rag-tests/results/2026-10-30/holdout_grading_sheet.csv` (outside the repository); the owner's
  grade is the final one.
- **Owner's hand grade (final), 2026-10-30:** every answer read, all 13 answerable questions
  graded (the automatic grading leaves one to a person). Sheet:
  `rag-tests/results/2026-10-30/holdout_grading_sheet_completed.csv` (outside the repository).

| Condition | `holdout_fork4`, hand grade | `holdout_fork3`, hand grade (2026-10-29) |
|---|---|---|
| English passages, English questions | 13 of 13, refused 3 of 3 | 13 of 13, 3 of 3 |
| Greek passages, English questions | 13 of 13, refused 3 of 3 | 12 of 13 (1 wrong), 3 of 3 |
| Greek passages, Greek questions | 12 of 13 (1 wrong), refused 3 of 3; all in Greek | 13 of 13, 3 of 3 |

- **Outcome:** the import changes and the PoC work left the holdout result unchanged within run
  variation: 38 of 39 answerable right in both runs, 9 of 9 unanswerable refused in both. One
  answer is graded wrong in each run, in a different condition. Following the holdout rule, the
  wrong answer was not examined and nothing was changed because of it.

## E11. Checking a Greek text layer with PaddleOCR (2026-11-13)

- **Observation:** in the Mac app, two Greek questions about the owner's 51-page labour-law
  lecture notes (a Word export, not in the repository) were both refused.
- **Cause (measured):** the PDF's Greek font maps to the wrong letters. The import checks a text
  layer against Vision OCR of a sample page, but skips pages in scripts Vision cannot read, so a
  Greek text layer is never checked. The notes were stored as 632 unreadable passages, 0 of them
  containing «υπερωρ», and PaddleOCR did not run (run `greektextlayer0`).
- **Change:** PaddleOCR reads the Greek sample page instead; under 15% shared words (the bar
  Vision's check uses) → every page through OCR.
- **Runs (simulator imports, `greektextlayer1`):**

| Document | Verdict | PaddleOCR | Passages | With «υπερωρ» |
|---|---|---|---|---|
| Lecture notes, before | not checked | 0 pages | 632 unreadable | 0 |
| Lecture notes, after | Jaccard 0.014, garbled | 54 images, 311 s | 713 Greek | 38 |
| Labour Code excerpt (control) | Jaccard 0.994, kept | 1 page (the check) | 692 | 19 |

- **Outcome: supported** for import. Not yet measured: the answers to the two questions (needs
  Apple Intelligence; the owner re-imports the notes in the Mac app). The notes contain no article
  58, so that question is rightly refused unless the Labour Code is in the library. The threshold
  was not tuned: 0.15 is the existing bar, and the two documents sit far from it.

## E12. Re-measurement after the rename to Firiki (2026-11-13/14, once each)

- **Why:** the owner asked for the full suite and every evaluation the README names before merging
  `firiki-rename` (rename, billing removal, Greek text-layer check, new icon) into `main`. Build
  `e3fcc368`. Nothing was changed because of these results.
- **Setup:** the new bundle ID started the Simulator's library empty, so the first summary and
  opinion runs stopped with "import the library first" (`firiki-summary-dev` and the three after
  it; no result). The five-document library was imported through the library question set limited
  to dev question 1 (`firiki-library-import`: 6,331 passages in 1,920 s; question 1 passed), then
  the four runs were repeated (`…2`). The last one was built in a fresh folder after macOS's
  overnight `/tmp` cleanup broke the package cache.

| Run | Result | Before |
|---|---|---|
| `firiki-full` (unit suite) | 1,291 XCTest, 8 skipped, 1 failure (Greek-region number format); 128 Swift Testing passed | 1,366, 11 skipped, 4 failures (2 billing tests since deleted, 1 window-scene test, the format one) |
| `firiki-readme-unit` (README's 6 suites) | 54 passed | — |
| `firiki-routing-dev` / `-test` | 44 of 44 (42 by the model) / 20 of 22 | 43 of 44 / 20 of 22 (`routing3`) |
| `firiki-ocrbench` | PaddleOCR 94.9% of words on clean, photo and scan; Vision 5%; whole scanned PDF 97.0% | 96.0% / 98.0% (`ocrbench4`); CER and WER identical, so the OCR text is the same: the bag-of-words scoring changed on 31 Oct (`4c234b5c`, line-end hyphens rejoined) |
| `firiki-summary-dev2` / `-test2` | 5 of 6 / 4 of 5 | 5 of 6 / 4 of 5 (`summary8`, `summarytest2`) |
| `firiki-opinion-dev2` / `-test2` | citations 10 of 12, key facts 11 of 20, refused 0 of 6 / citations 5 of 8, key facts 7 of 10, refused 0 of 4 | identical / citations 3 of 8 (`opinion6`, `opiniontest1`) |

- **Outcome:** no regression. The two gains (one template request, two opinion citations on the
  test split) are single runs and within run-to-run variation. This is the second run of the
  opinion and template test splits and the third of the summary test split.

## E13. Chat intent recognition, before and after the demo quick wins (2026-11-14)

- **Why:** the CEO-demo audit (`POC_PROGRESS.md`) found ordinary questions sent to a capability by
  the chat's rules. The README's template figures (43–44 of 44) measure the template router once
  called; this measures whether the chat calls it at all. No model is involved: the rules are
  regular expressions, checked by a Python prototype (same patterns, same folding) and then by
  `GreekLegalChatRouterTests` in Swift.
- **Design data:** dev splits only (routing, Labour Code, library, opinion). The routing **test**
  split and the test splits of the question sets were measured once after the rules were final;
  one observation there (an opinion test request that names a collective agreement and a request
  verb was taken for a template) is why the contract-noun-plus-verb rule runs after the opinion
  rule. No pattern was added or changed for a test prompt.

| Set | Want | Before (first rules) | After |
|---|---|---|---|
| Routing dev, 40 template requests | template | 0 | 38 |
| Routing dev, 4 "none" questions | Q&A | 4 | 4 |
| Labour Code dev, 46 / library dev, 24 / opinion dev, 6 | not a template or summary | all | all |
| 7 ordinary questions (audit misroutes + 2 yes/no) | Q&A | 1 | 7 |
| Routing test, 20 template requests (once) | template | — | 13 |
| Routing test, 2 "none" / Labour Code test 23 / library test 12 | Q&A | — | all but 1 library question flagged as a possible arrangement (it falls back to Q&A when the router finds no template) |
| Opinion test, 4 (once) | opinion | — | 4 after the rule order above |

- **Outcome:** the misroutes are gone and natural template requests reach the router from the
  chat (38 of 40 dev, 13 of 20 test: the rules generalise less well than on the set they were
  written from). A described arrangement that no template fits now goes to ordinary Q&A.

## Open failures known from dev (not fixed)

- Library dev 13 (pay information): the model answered "within five (5) paragraphs" where the law
  says two months; no gate catches a misread passage that contains the figure.
- Library dev 33 (e-ΕΦΚΑ employer contribution): the model answered with a buyback rule the
  passage does state ("one quarter of the pension"), so the figure check passed it; no general
  rule was found that would catch it without tuning to that question.
- Library dev 8 («τρίμηνο» → "a quarter"): see E5.
- Labour Code dev 41 and 68: not fixed by the owner's decision (2026-10-30).

## E14. An opinion reads the whole amending article; passages not numbered (2026-11-14, dev once each)

- **Hypothesis:** the demo's overtime opinion concludes "four hours a day not allowed" because the
  three passages kept for Law 5239/2025 leave out the end of its Article 7, which restates Article
  194 par. 3 («έως τέσσερις (4) ώρες ημερησίως … 150 … 40%»). Giving the model the whole amending
  article, in order, within 7,372 characters, lets it state the amended rule. Plan:
  `Docs/Thesis/plans/opinion-whole-amending-article.md`; diagnosis in `POC_PROGRESS.md`.
- **Runs:** opinion dev split (`firiki-opinion-dev3-wholearticle`) against `firiki-opinion-dev2`
  (14 Nov, same library and build otherwise); the demo prompt in the Mac app (7 documents,
  log saved).

| Case | Baseline citations / facts | Whole article citations / facts | Seconds |
|---|---|---|---|
| 1 overtime | 2 of 2 / 3 of 4 | 2 of 2 / 3 of 4 (1 dropped) | 34 → 41 |
| 2 | 2 of 2 / 3 of 4 | 2 of 2 / 3 of 4 (2 dropped) | 22 → 35 |
| 3 expired agreement | 2 of 2 / 2 of 3 | **1 of 2** / 2 of 3 (1 dropped) | 21 → 37 |
| 4 | 2 of 2 / 1 of 3 | 2 of 2 / **3 of 3** | 21 → 30 |
| 5 | 0 of 2 / 0 of 4 | 0 of 2 / 0 of 4 (1 dropped) | 24 → 31 |
| 6 | 2 of 2 / 2 of 2 | 2 of 2 / 2 of 2 | 20 → 26 |
| Total | 10 of 12 / 11 of 20 | 9 of 12 / 13 of 20 | |

- **What happened in case 1 and in the Mac app:** the law's source now holds Article 7's seven
  passages (#108–#114), and the model writes "workers are entitled … up to four (4) hours daily
  and up to … one hundred and fifty (150) hours per year … increased by forty percent (40%)", but
  cites it as "Article **6** of Law 5239/2025". The article check drops the sentence, and the
  conclusion again rests on the Code's Article 191 (sixth-day work, "overtime not allowed"). The
  sentence is the sixth passage of the prompt (`[6]`), so the model most likely took the passage
  number for the article number; it happened in both runs.
- **Case 3:** the lost citation is in Law 5278/2026, whose source this change does not alter (no
  link of its kept passages); the model cited "Article 5" instead of 8, and the sentence was
  dropped. Most likely run-to-run variation; not confirmed.
- **Second change (owner's approval):** the section prompt separates passages with a line
  instead of numbering them `[1]`, `[2]`… (`sectionPrompt`). Dev run
  `firiki-opinion-dev4-nonumbers`:

| Case | Baseline (dev2) | Whole article (dev3) | Whole article, no numbers (dev4) | Seconds (dev4) |
|---|---|---|---|---|
| 1 overtime | 2 of 2 / 3 of 4 | 2 of 2 / 3 of 4 | 2 of 2 / **4 of 4** | 46 |
| 2 | 2 of 2 / 3 of 4 | 2 of 2 / 3 of 4 | 2 of 2 / 3 of 4 | 35 |
| 3 expired agreement | 2 of 2 / 2 of 3 | 1 of 2 / 2 of 3 | 2 of 2 / **3 of 3** | 34 |
| 4 | 2 of 2 / 1 of 3 | 2 of 2 / 3 of 3 | 2 of 2 / **3 of 3** | 30 |
| 5 | 0 of 2 / 0 of 4 | 0 of 2 / 0 of 4 | 0 of 2 / 0 of 4 | 37 |
| 6 | 2 of 2 / 2 of 2 | 2 of 2 / 2 of 2 | 2 of 2 / 2 of 2 | 31 |
| Total | 10 of 12 / 11 of 20 | 9 of 12 / 13 of 20 | **10 of 12 / 15 of 20** | |

  Sentences dropped by the article check: 0 (6 in dev3). Refused 0 of 6 in all three.
- **Mac app (7 documents, dev4 build):**
  - the demo's short prompt («…τέσσερις ώρες υπερωρία την ημέρα. Επιτρέπεται;») now has a correct
    Law 5239 section (4 hours a day, 150 a year, 40%), but its conclusion still says the request is
    not allowed, mixing in the Code's sixth-day Article 191 (42 s);
  - case 1's wording («…υπάλληλο πενθήμερης εργασίας… πώς αμείβεται και μπορεί ο εργαζόμενος να
    αρνηθεί;») gets a correct conclusion (up to 4 hours a day and 150 a year, 40%, may refuse,
    Article 12 of Law 5239/2025). Its Greek still has a leftover placeholder («__ΕΧΝ.»), a garbled
    clause on dismissal, and "payment deadline … 186 hours a year", taken from "Articles 169 to 186".
- **Outcome:** kept. Dev key facts 11 → 15 of 20, citations unchanged (10 of 12), nothing dropped;
  opinions take 5–15 s longer. The test split was not run. Not solved: the Code's sixth-day
  articles retrieved for a short overtime question.

## E15. Translation placeholders repaired; the opinion test split (2026-11-14)

- **Hypothesis:** placeholders the translator mangled (`__LEX_005___`, `LEX_004___`,
  `__EX_ENT_003_`, …) stay in 7% of the stored English passages, reach the model's drafts and show
  in Greek answers («__ΕΧΝ.»). Recognising the mangled forms, removing what is left, and repairing
  stored passages when read removes them without a re-import. Plan:
  `Docs/Thesis/plans/placeholder-leftovers.md`.
- **Leftovers** (Simulator, all libraries, 8,022 English passages; the app's patterns ported to
  Python): 450 with a placeholder or debris before the repair, 0 after. All affected passages store
  their entity list.
- **Runs** (build with E14 and this change):

| Run | Before | After |
|---|---|---|
| Opinion dev (`firiki-opinion-dev5-placeholders`, rerun `-dev6-…` identical) | 10 of 12 citations, 15 of 20 facts (dev4) | 10 of 12, **13 of 20**, refused 0, dropped 0 |
| Library Q&A dev (`firiki-library-dev8-placeholders`) | 13 of 24 (`library7`; 14 in the README) | **15 of 24**; expected article retrieved 17 of 21 (14) |
| Opinion test, once (`firiki-opinion-test3`) | 5 of 8 citations, 7 of 10 facts (`firiki-opinion-test2`, before E14) | 4 of 8, **8 of 10**, refused 0 |

- **Opinion dev per case:** unchanged except case 3 (3 of 3 → 2 of 3: no longer says «**όλοι** οι
  κανονιστικοί όροι») and case 4 (3 of 3 → 2 of 3: no longer says «μεταγενέστερη»). The rerun was
  identical (greedy decoding), so this is the repaired text changing the drafts' wording, not run
  variation. Case 1 stays 4 of 4.
- **Opinion test per case** (against test2): case 7 1 → 0 citations; case 9 2 → 3 facts; case 10
  2 sentences dropped (1 before); the test split measures E14 and E15 together and was not used to
  change anything.
- **Mac app** (7 documents): the overtime opinion with the evaluation's wording has no placeholder
  and no "186 hours"; its conclusion: overtime beyond 45 hours a week, up to 4 hours a day and 150 a
  year, at plus 40%, and the employee may refuse.
- **Outcome:** kept. The leftovers were shown to readers and hid the text the model needed; library
  Q&A improved by 2, opinion dev lost 2 key-fact phrasings, opinion test gained 1 fact and lost 1
  citation.

## E16. Summaries and opinions survive model errors; Stop between passes (2026-11-14)

- **Hypothesis:** a summary or opinion fails as a whole when one model call is too long, declined
  or meets a busy model, and Stop only takes effect after the last pass. Wrapping each pass
  (`GreekLegalModelCall`: retry shorter, retry once when busy, skip a declined pass, check
  cancellation first) fixes both without changing results when nothing fails. Plan:
  `Docs/Thesis/plans/model-errors-and-stop.md`.
- **Unit tests** (stand-in model, `GreekLegalModelCallTests`, 8): all pass. They cover the shorter
  retry keeping the header, one busy retry, declined summary group and opinion section skipped, a
  declined conclusion refused with a Greek reason, no further model call after Stop, and the OS 27
  error types getting their messages.
- **Dev runs, no failure expected** (`firiki-opinion-dev7-modelcalls`, `firiki-summary-dev3`): no
  `[ModelCall]` retry or decline was logged in either.
  - Opinion dev: identical to E15 (10 of 12 citations, 13 of 20 key facts, same per case).
  - Summary dev (Law 5278/2026): 5 of 6 provisions as before, articles cited 2 of 3 (3 of 3 in
    `firiki-summary-dev2`), 12 groups instead of 13, 78 s. This is the first summary run after
    E15's placeholder repair, which changed the passages' text and so their grouping; no model
    call of this change differed. The missing provision is now "all normative terms continue after
    the three months (art. 8)", instead of "extension threshold 40% (art. 9)".
- **Mac app, Stop:** Stop pressed about 10 s into the overtime opinion. The bar went idle and
  "Ask again" appeared about 0.3 s later. The app's log shows the sources and passages, then
  `[ChatRouter] opinion failed: CancellationError()` and no English opinion: the remaining passes
  did not run.
- **Outcome:** kept.

## E17. Short daily overtime question in legal opinions (2026-11-14)

- **Hypothesis:** adding the short daily overtime request (case 11, dev: «Θέλω γνωμοδότηση: ο
  εργοδότης ζητά τέσσερις ώρες υπερωρία την ημέρα. Επιτρέπεται;») failed in the conclusion ("not
  allowed", citing sixth-day Article 192) because scoped opinion retrieval dropped the Greek query,
  `PD:62/2025` (sixth-day Articles 191–192, `0.58`) was ordered before later amending `Law
  5239/2025` Article 7 (`0.57`), `relativeScore = 0.6` let in noisy third document `Law 5278/2026`
  (`0.37`), standalone «Επιτρέπεται;» translated `"May I?"`, and the prompts did not distinguish
  general `"up to"` limits from special-case arrangements. Plan: `Docs/Thesis/plans/short-overtime-opinion.md`.
- **Baseline** (`firiki-opinion-dev8-short-baseline`): dev opinion set with Q11 appended scored
  `citations 12 of 14, key facts 15 of 22, refused 0 of 7`; Q11 itself matched the automated regexes
  (`citations 2 of 2`, `facts 2 of 2`, `other articles cited [9, 12, 191, 192, 404]`), **but its
  actual conclusion stated the opposite ("not allowed" under Article 192)**.
- **Change & dev measurement** (`firiki-opinion-dev9-short-overtime`, plus `firiki-library-dev9-short-overtime`
  and `GreekKeywordArmTests` / `GreekTranslationRetrievalTests` / `GreekLegalOpinionTests`):
  - Passed stripped Greek query as `originalQuery` in scoped opinion search (`searchDocumentsRaw` +
    `HybridSearchService.searchInsideScope` using Greek FTS5 and `SQLiteFullTextService.greekQueryStems`),
    filtered permissive modal stop words (`επιτρεπεται`), normalized standalone «Επιτρέπεται;» →
    «Επιτρέπεται αυτό;» (`"Is that allowed?"`), raised `relativeScore` (`0.6 → 0.68`), placed later
    statutes ahead of `PD:62/2025`, expanded only the top-scoring amending article per source in
    `withWholeAmendingArticles`, and added general-limit vs special-case guidance to the section and
    conclusion instructions.
  - **Opinion dev** (`firiki-opinion-dev9-short-overtime`): `16 tests in 2 suites passed` (`218.982 s`),
    `citations 12 of 14, key facts 15 of 22, refused 0 of 7`, Q11 (`2 of 2 citations`, `2 of 2 facts`,
    `other articles cited [12, 188, 191, 192]` with `n_5278` noise gone), and Q11 `Συμπέρασμα`
    now explicitly concludes that **4 hours daily overtime is permitted** (`επιτρέπονται 4 ώρες νόμιμης
    υπερωρίας ανά ημέρα, μέχρι συνολικά 150 ώρες ετησίως... καμία ειδική εξαίρεση για μια εβδομάδα
    εργασίας 6 ημερών δεν υπερισχύει`) under Law 5239/2025 Article 7 amending Labour Code Article 194.
  - **Library dev** (`firiki-library-dev9-short-overtime`, checking shared `searchDocumentsRaw` /
    `searchInsideScope` / `greekQueryTranslation` / `greekQueryStopWords`): `passed 14 of 24`
    (`answer pass 13 of 21`, `retrieval hit 18 of 21`, `right documents retrieved 21 of 21`).
  - **Translation & keyword unit suites**: `GreekKeywordArmTests` + `GreekTranslationRetrievalTests`
    (`15 tests in 2 suites passed in 3.169 s`).
- **Outcome:** kept.

## E18. Restore Article 3 citation and Article 8 full after-effect in statute summaries (2026-11-14)

- **Observation (`firiki-summary-dev3`, reproduced in `summary-dev-base.log`):** since E15, the
  Law 5278/2026 (`dev`) summary cited `2 of 3` expected articles (`Article 3` missing; its GSEE
  rule was attached under `Article 5`, which appeared first) and `5 of 6` provisions, missing
  `"after-effect: all normative terms continue after the three months (art. 8)"` (`12` groups).
- **Causes found on `n_5278_2026_fek_a22.pdf` (`dev`):**
  1. Table-of-contents chunk 4 (`"Article 5 [Άρθρο 5] ..."`) had >= 12 words and 1 `"Article"` match,
     placing `Article 5` before `Article 1` at the start of Group 1 and absorbing unlabelled /
     amended notes from Group 1 (`Article 3`).
  2. `passage.components(separatedBy: "Article ").count - 1` counted inline cross-references
     (`Article 404`, `Article 399`, `Article 396`), skipping 19 valid body chunks (Articles 4, 5, 6,
     5 chunks of Article 9, 10, 11, 12, and all of Article 15).
  3. After E15 removed placeholder strings (~150 chars), `Article 6 + Article 7 + Article 8` fell
     below the `7,372`-char limit and merged into one group, leaving `Article 8` with a single note
     line that omitted `"all normative terms continue after the three months"`.
  4. `markerLine` only stripped exact `=== Article N ===`, letting echoed headings like
     `=== Article 404: Accession and Application Extension ===` consume note lines.
- **Change (`Docs/Thesis/plans/summary-dev-article8.md`):**
  - Count line-start `Article` headings when filtering TOC blocks and drop leading entries before
    `Article 1` when present (`articles(from:)`).
  - Cap article groups at `maxArticles = 2` (`unlimited` when summarizing by parts).
  - Expand `markerLine` to strip `=== Article N: Title ===` headings and update `mapInstructions`
    to preserve exact scope words and state each distinct rule/time stage on its own line.
- **Verification (`firiki-summary-dev4-e18`):**
  - `GreekLegalSummaryTests`, `GreekLegalOpinionTests`, and `GreekLegalSummaryEvaluation` (`dev`):
    `** TEST BUILD SUCCEEDED **`, `✔ Test run with 24 tests in 3 suites passed after 134.919 seconds.`
  - **Law 5278/2026 (`dev`):** `passages=203 groups=15 notes=25717 chars, 134 s`, `provisions 5 of 6 | articles cited 3 of 3 | dropped 0` (`Άρθρο 3` restored with GSEE rule; `Άρθρο 8` now states both `"για ένα διάστημα 3 μηνών"` and `"εξακολουθούν να ισχύουν όλοι οι κανονιστικοί όροι..."`; echoed `=== Article N: ... ===` headings removed).
- **Outcome:** kept.

## E19. Five-document library held-out test run and README table update (2026-11-14)

- **Purpose:** re-measure the held-out `GreekLabourLibrary` `test` split (12 questions) once after
  E15–E18 without inspecting or tuning on `test` cases, and update `README.md` with E14–E19
  numbers and dates. Plan: `Docs/Thesis/plans/readme-results-update.md`.
- **Run (`firiki-library-test2-e19`):** `TEST_RUNNER_OI_GREEK_EVAL=1 TEST_RUNNER_OI_GREEK_EVAL_SET=GreekLabourLibrary TEST_RUNNER_OI_GREEK_EVAL_SPLIT=test OI_TEST_TIMEOUT_SECONDS=5400 ./scripts/thesis_run_tests.sh /private/tmp/oi-e19-logs/firiki-library-test2-e19.log -only-testing:FirikiTests/GreekConstitutionEvaluationTests`
  (`✔ Test run with 1 test in 1 suite passed after 333.466 seconds.`):
  - **`passed 5 of 12`** (`answer pass 4 of 11; retrieval hit 7 of 11; right documents retrieved 9 of 11; false abstentions 3; abstention correct 1 of 1`).
  - Compare `librarytest1` (2026-10-30): `6 of 12` (`right documents retrieved 6 of 11`). Document
    retrieval rose (`6 → 9 of 11`) while the total pass count (`5 vs 6 of 12`) is within the
    run-to-run variation.
- **Outcome:** measured once and recorded in `README.md`, `METHODS_SUMMARY.md`, and `FORK_CHANGES.md`.
