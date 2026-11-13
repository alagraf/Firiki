# Greek legal assistant: methods summary

A high-level account of how the OpenIntelligence app was adapted to answer questions about Greek
legal texts (scope: Greek labour law) entirely on an iPhone. It is written for the thesis and kept
current as the work goes on. Technical detail, file names and per-run evidence are in
`Docs/Thesis/FORK_CHANGES.md` (sections 2.11.*); the work log is
`Docs/Thesis/plans/greek-legaltech-progress.md`.

**In one sentence:** a retrieval-augmented, translation-bridged pipeline built from pretrained
components (PaddleOCR, Opus-MT, Apple's on-device foundation model), refined through iterative,
evaluation-driven error analysis on Greek legal question sets with a held-out test split.

**No model was fine-tuned.** Apple's on-device language model and the translation and OCR models
are used as published. All improvement comes from the pipeline around them (ingestion,
translation, retrieval, prompting, verification), measured on question sets built from the
official texts. The loop: run the whole app on the question set; trace each wrong answer to the
stage where it went wrong (OCR, translation, chunking, retrieval, generation, verification);
fix that stage in a general way; run again and compare.

## 1. Reading Greek documents
- **On-device Greek OCR.** Apple's Vision OCR has no Greek model, so PaddleOCR (PP-OCRv5 text
  detector and Greek recogniser, run with ONNX Runtime) reads Greek scans, photos and images
  inside PDFs. A router sends each page or image to Vision or PaddleOCR depending on the
  document's language, or when Vision's output looks like misread Greek (Latin or Cyrillic
  look-alike letters, as Vision produces for a short Greek stamp). Every OCR path of the import
  (scanned pages, images and stamps inside PDFs, table regions, multi-column layouts) goes through
  this router.
- **Measured on scans and photos.** A test set of 10 Labour Code pages, each clean, as a simulated
  scan and as a simulated phone photo: PaddleOCR finds 96% of the words on clean pages and photos,
  Vision 5% (it reads no Greek). On scans PaddleOCR first found 48%, losing more the more the page
  was tilted (88% at 0.5°, 10% at 1.5°): each line's box was an upright rectangle, which on a tilted
  page takes in parts of the lines above and below. The boxes now follow each line's angle, and
  scans read like clean pages (96%). The angle rule was set on these pages, so it was checked on 13
  other tilted pages as well: 46% → 88% of the words, the same as untilted.
- **Checking a Greek text layer.** A PDF's own text is used when it matches the page, but some
  Greek PDFs (here, lecture notes exported from Word) map their font to the wrong letters, so the
  text reads «Ζ ζρέζε» for «Η σχέση». The original app checks a text layer by reading one page with
  Vision OCR, which reads no Greek, so Greek text was never checked. PaddleOCR now reads that page:
  if it shares under 15% of its words with the text layer, every page goes through OCR. The broken
  notes went from 0 to 38 passages about overtime (713 readable passages); a correct Labour Code
  excerpt kept its text layer (99% of words shared).
- **Text clean-up.** Unicode normalisation; repair of Latin letters that look Greek (a Latin "A"
  in "ΦΕΚ A'"); quality filters that recognise Greek instead of discarding it as noise; rejoining
  words broken across lines; removal of the Government Gazette's running headers.
- **Reading order of digital PDFs.** Each word's position on the page is looked up in the PDF's
  own text, not the normalised one: normalisation lengthens Greek text at every keraia ("Α΄"), and
  positions taken from it belonged to later words, so article headings ran into the lines around
  them and one law kept only 8 of its 16 articles. A page is read as one column when its typical
  line spans more than half its width (one-column Gazette pages measured 56–79%, two-column ones
  under 40%).

## 2. Structure-aware and context-aware chunking
- **Document typology classification:** Incoming documents are classified into four structural kinds via `GreekLegalDocumentClassifier`: statutory enactments, Q&A documents, lawyer's notes / legal memoranda, and general prose, using deterministic layout rules backed by schema-constrained foundation model inference.
- **Greek statutes:** Split along their own structure: one passage per numbered paragraph of each
  article, each starting with its article heading, long paragraphs split at sentence ends.
  Generic size-based chunking had cut provisions in half and separated paragraphs from their
  article.
- **Q&A corpora:** Processed via `GreekLegalQAChunker`, keeping questions and answers atomically paired; when a long answer is split across token budgets, the question header is repeated at the head of every piece so grounding context is never severed.
- **Lawyer's notes / memos:** Segmented along memo section headings (`GreekLegalNotesChunker`: *Facts*, *Question*, *Applicable Law*, *Analysis*, *Conclusion*). Statutory references within paragraphs are preserved as citations without fragmenting the argument.
- **Tables:** Keep one row a line through chunking and translation, with a row the PDF reader splits
  in two put back together; joined into prose, a severance table was translated as "16 years and
  more than 12 months" and the model mixed its rows.

## 3. Translation as a bridge to an English-centred model
- **Translate, answer, translate back.** Apple's on-device model works best in English. A Greek
  question is translated to English; retrieval, generation and verification run in English; the
  verified answer is translated back to Greek.
- **Translation models.** Opus-MT (Helsinki-NLP's Greek↔English transformer-big models), converted
  to compact INT8 ONNX models with a key/value cache in the decoder (about 3.5× faster decoding),
  so whole documents can be translated at import time on the device. Only one direction is kept
  in memory, and none after an import. Translating several sentences at once was tried and
  dropped: with the compressed models it changed the translations and lowered accuracy.
- **File names kept.** Document names cited in an answer stay as written ("passage 3-2.txt" had
  become «διόδου 3-2.txt»), and "passage/excerpt" is rendered «απόσπασμα».
- **Protected legal identifiers.** Laws, decrees, articles, paragraphs, Gazette (ΦΕΚ) references
  and court decisions are recognised by rules, replaced by placeholders before translation and
  restored afterwards, so the translator cannot distort them. Personal names are transliterated
  (ELOT 743) instead of translated.
- **Legal glossary.** A small glossary gives each recurring legal term one fixed English rendering
  in documents and questions alike, and puts the official Greek term back into the Greek answer
  when the translator chose a synonym.
- **Known translator errors corrected.** Before translation, English the translator mishandles is
  reworded: dashes between words (it dropped them and glued the words), amounts written in words
  next to their figure, and "statute" (rendered as articles of association). After translation,
  opinions and summaries are post-edited for errors seen in practice: legal terms («νόμιμες
  υπερωρίες», «καταβαλλόμενο ωρομίσθιο», «πρακτικά» for minutes), article and statute forms, English
  article references left untranslated, and repeated phrases.

## 4. Retrieval
- **Hybrid search.** Semantic (embedding) search over the English text of each passage, combined
  with a keyword index over its original Greek text that ignores accents and case and matches word
  stems (Greek is highly inflected).
- **Article lookup.** A question that names an article gets that article's passages first.
- **Libraries of several documents.** A question that names a law of the library is searched in
  that law's document only, so a large code cannot crowd it out; a document's title page and
  contents, which list every article's title, are left out when it has articles.

## 5. Answer generation
- **Deterministic decoding** (greedy) so the same question gets the same answer, which also makes
  evaluation runs comparable.
- **Prompt instructions.** Answer only from the excerpts, using their own names; give every
  number, time limit, condition and exception they state and none they don't; say which case or
  person each number applies to.
- Apple's permissive content-transformation setting, so that ordinary legal topics (dismissal,
  pregnancy) are not refused by the model's guardrails.

## 6. Verification and refusal
- **Verification gates** check each English draft before it is shown: the evidence supports its
  claims; its numbers (also when the source writes them as words) and its legal citations appear
  in the retrieved passages; it relies on the law the question names. A source reference by file
  name and page is not counted as a number the answer states. When the number check is the only
  failure, sentences with a figure that share no topic word with the question are dropped and the
  rest is checked again, so an unrelated aside no longer refuses a correct answer.
- Each imported statute records which statute it is, read from its title page. A question that names
  a statute (a law, a decree, a ministerial decision, the Constitution) that no retrieved passage
  comes from or cites is refused before generation, rather than answered from another statute's
  article with the same number.
- **Refusal instead of guessing.** A fixed Greek refusal is shown when the evidence is weak, when
  the question is about another country's law that no passage covers (named as a country or by
  its adjective, "German labour law"), when the draft itself says
  the sources do not answer the question, or when a gate fails.
- The answer's details show the verification outcome, the English draft and the models used, so
  every answer can be audited.

## 6a. Choosing a contract template (PoC capability)
- Ten Greek labour contract templates, drafted from the Labour Code and the laws of the library and
  marked as drafts that are not legal advice, ship with the app.
- A request is translated to English if it is Greek; the on-device model then chooses one
  template, or none, from their descriptions. The choice is constrained to the valid template
  names, and the model first states in one sentence what work arrangement the request describes.
- The model's default safety filter blocks some requests about employing minors (apprenticeship
  for ages 15–18). Such a request is asked again as a plain-text classification under the
  filter's setting for transforming user content; keywords decide when the model can't.

## 6b. Summarising one statute (PoC capability)
- The statute is read in pieces that fit the phone's 4,096-token window, each marked with its
  articles; the model notes each piece's rules with their article numbers (map).
- The list of main provisions is built from the notes by the program, one bullet an article, and
  the model writes only the opening sentences (reduce): left to write the list, it renumbered
  articles and took figures from one article into another.
- A text without articles, such as a ministerial decision, is read in parts of similar size.
- Every sentence is checked against the whole document (its figures and article references) and
  dropped if unsupported, then translated to Greek.

## 6c. Legal opinion from several documents (PoC capability)
- Passages are retrieved from each document separately, and the documents closest to the
  question are kept (up to three).
- Which later law amends or adds which Labour Code article is read from the amending articles'
  headings, not asked of the model; an amended article is read from the amending law, since the
  Code's own text is the old version.
- The model drafts one section a document and then a conclusion, each within the phone's window;
  every sentence is checked as for summaries, and the opinion is refused when its conclusion has
  no supported sentence. The Greek opinion has the parts question, applicable law, what each text
  provides, how they combine, conclusion, and a note that it is not legal advice.
- A document without articles, such as a ministerial decision, is cited by its name; an article
  number the model gives it anyway is removed before the check. Before this, the invented number
  made the check drop the decision's sentences, and with them the €920 minimum wage.
- The applicable law and how the documents combine are written in Greek by the program; only the
  model's sections and conclusion are translated.

## 7. Evaluation method
- **Question sets** written from the official texts, each with a reference answer citing article
  and paragraph and key-fact patterns for automatic grading:
  - Greek Constitution: 10 questions (the owner's set).
  - Labour Code, Π.Δ. 62/2025 (ΦΕΚ Α' 121/2025): 69 questions over leave, working time, wages,
    part-time work, dismissal and notice, severance, maternity and paternity protection,
    harassment and the digital work card, including cross-reference questions, questions in
    everyday language and 8 questions that must be refused. Split into development (46) and test
    (23) sets.
  - A library of five labour-law documents (the Labour Code, Laws 5239/2025, 5278/2026 and
    5316/2026, ministerial decision 8934/2026 on the minimum wage): 36 questions, development (24)
    and test (12); a summary set (one law for development, the decision for test) listing the
    provisions and articles each summary must state; an opinion set of 10 requests (6
    development, 4 test), each with the two documents and articles it must cite and its key facts.
- **Whole-app measurement.** Each run imports the document through the app's real pipeline and
  asks every question through the same path a user's question takes. Retrieval accuracy (was the
  right article found), answer accuracy (are the key facts in the answer) and refusal accuracy
  are reported separately.
- **Iteration discipline.** Each failure is traced to its stage (OCR, translation, retrieval,
  generation or verification) and fixed in the app, never by putting answers into the app.
  Changes are tuned on the development set; the test set is used for held-out measurement.

## 8. Results so far
Measured in the iOS 27 Simulator (`iPhone 18 Pro`) on an M3 Pro Mac (18 GB) with Apple's on-device model (`AFM 3 Core Advanced`, 8,192-token window); not yet checked on a physical iPhone. All numbers below except the 13–14 November rows were recorded on 28–30 October 2026 (up to commit `e85ae0cc` / `ffff0241`), prior to the 31 October code commits (`2af92e2e`–`f10190e1`), which refined import/chunking, translation, and refusal rules after the evaluation runs. (Commit hashes are from before the 13 Nov 2026 identity rewrite; `COMMIT_HASH_MAP.md` (local, git-ignored) gives the current ones.)

| Date | Question set | Result |
|---|---|---|
| 2026-10-28 | Constitution (10) | 6 of 10 at the start |
| 2026-10-29 | Constitution (10) | 9 of 10; right article retrieved for 10 of 10 |
| 2026-10-29 | Labour Code, development (46), 37-page excerpt | 24 → 31 of 46 |
| 2026-10-29 | Labour Code, test (23), excerpt / full 260-page Code | 14 of 23 / 11 of 23 |
| 2026-10-29 | Labour Code, development (46), excerpt, after the out-of-scope refusals | 37 of 46; all 5 questions that must be refused were refused |
| 2026-10-29 | EU holdout (16), Greek passages and Greek questions, graded by hand | original app 0 of 13 in Greek (9 right but in English), 0 of 3 refused; this fork 13 of 13, 3 of 3 refused |
| 2026-10-29 | After faster translation, file names kept, citation fix: Labour dev / Constitution / Labour test excerpt / full Code | 35 of 46 / 8 of 10 / 16 of 23 / 12 of 23 |
| 2026-10-29 | OCR, 10 pages × clean / scan / photo, share of words found | PaddleOCR 96% / 48% / 96%; Vision 5% |
| 2026-10-29 | OCR after the boxes follow tilted lines: scans / whole scanned PDF / 13 other tilted pages | 48% → 96% / 62% → 98% / 46% → 88% (untilted 88%) |
| 2026-10-29 | Labour Code, development (46), excerpt, after table rows and the off-topic figure repair (two runs) | 36 and 35 of 46 (35 before) |
| 2026-10-29 | Constitution (10) and Labour Code development (46), after the per-document statute check | 8 of 10 (8 before); 38 of 46, refusals 5 of 5 |
| 2026-10-30 | Contract template routing (66 requests, half Greek): development (44) / test (22), on-device model; keywords alone | 43 of 44 / 20 of 22; 26 of 44 / 8 of 22 |
| 2026-10-30 | Five-document library, development (24): start / after search by named law, contents left out, reading-order fixes | 13 of 24 / 14 of 24 |
| 2026-10-30 | Five-document library, test (12), once | 6 of 12 |
| 2026-10-30 | Labour Code, development (46), after the reading-order fixes | 38 of 46 (38 before) |
| 2026-10-30 | Summary of Law 5278/2026 (development): key provisions, articles cited | 5 of 6, 3 of 3 (2 of 6, 0 of 3 before the reading-order fixes) |
| 2026-10-30 | Summary of decision 8934/2026 (test): key provisions | 0 of 5 held out (no articles, empty summary); 4 of 5 after reading by parts (not held out) |
| 2026-10-30 | Legal opinion, development (6) / test (4): citations, key facts, refused | 10 of 12, 11 of 20, 0 / 3 of 8, 7 of 10, 0 |
| 2026-10-30 | EU holdout, this fork, rerun after the PoC work (automatic corrected grading) | unchanged: 12 of 12 graded right, 3 of 3 refused in each condition |
| 2026-10-30 | EU holdout, same rerun, graded by hand (final) | English 13 of 13; Greek passages, English questions 13 of 13; all Greek 12 of 13 (1 wrong); 3 of 3 refused in each (2026-10-29: 13, 12, 13 of 13) |
| 2026-10-30 | Labour Code, test (23), full 260-page Code, once | 15 of 23 (12 before); 3 of 3 refused, including the question about the Constitution's Article 16; 1 wrong refusal |
| 2026-11-13 | Re-measured after the rename to Firiki, billing removal and the Greek text-layer check: contract templates dev / test | 44 of 44 / 20 of 22 (43 of 44 / 20 of 22 before) |
| 2026-11-13 | Same build: OCR, share of words found, clean / scan / photo; whole scanned PDF | 95% / 95% / 95%; 97% (same OCR text as 29 Oct; the word scoring rejoins hyphenated line ends since 31 Oct) |
| 2026-11-14 | Same build: summary dev / test; opinion dev / test (citations, key facts, refused) | 5 of 6 / 4 of 5; 10 of 12, 11 of 20, 0 / 5 of 8, 7 of 10, 0 (test citations 3 of 8 before) |
| 2026-11-13 | Lecture notes with a wrong-letter Greek font, before / after the PaddleOCR text-layer check: passages about overtime | 0 / 38 of 713; a correct Labour Code excerpt kept its text layer |

Import of the full 260-page Labour Code in the Simulator: about 29 minutes (4,218 passages), 15
minutes after the faster translation.

The answers vary from run to run: on the same passages, the model's drafts differ (one cites a
source as "[S2]", another by file name and page), and 2 to 8 of the 46 development questions flip
between pass and fail across runs. Each figure above is one run, so differences of 2–3 questions
are within this variation.

## 9. Known limitations
- Refusal of off-topic questions: 5 of 5 on the development set and 3 of 3 on the held-out set
  over the full Code. These are few questions.
- With the right article retrieved, the model still sometimes picks a figure for the wrong case,
  or adds figures from another part of the same article (the severance question now gets 12
  months right but also quotes rows of the article's second table). The number check doesn't
  catch this, because the passage does state those figures.
- OCR is measured on simulated scans and photos only; real scans and phone photos are not yet
  measured. Constitution pages read worse than Labour Code pages even untilted (61–79% of the
  words, not yet investigated).
- No device measurements yet (speed, memory, answer quality on an iPhone).
- Template routing: the safety filter can block a request about a 15-year-old under both
  settings, and the keywords then may not recognise it; a student's practicum was once taken for
  an apprenticeship. The templates themselves are drafts that a lawyer must check.
- Five-document library: half of the held-out questions are answered (6 of 12), against 14 of 24
  in development. Failures are mostly refusals after the wrong documents were retrieved, and
  answers that miss a fact or name the Code's article instead of the law asked about. The model
  also misreads a passage now and then ("within five paragraphs" for "within two months"), which
  the checks cannot catch when the passage does contain the figure.
- Legal opinions state most key facts but often cite other articles of the same laws than a
  lawyer would (3 of 8 expected citations on the held-out requests). The sets are small (six
  development and four test requests), so these figures are indicative.
- A law named without its year ("Law 5239") is not recognised as a law of the library.

## Holdout evaluation (before/after)
A second, never-tuned test set is kept for the before/after comparison (Chapter 6): 16 questions
on 11 articles of EU labour directives, published officially in Greek and English (13 answered by
the text, 3 not, to measure hallucination). Nothing in the app was changed because of it. Each
passage is a document; each question goes through the whole app as a user's question would.
Every answer was read and graded by hand (the automatic grading, the app developer's, missed
refusals and accepted only Greek answers to Greek questions, so it was used only as a first pass).
Right answers of 13, and how many of the 3 unanswerable questions were refused (refusing is right):

| System | English passages, English questions | Greek passages, English questions | Greek passages, Greek questions |
|---|---|---|---|
| Original app | 13, 3 refused | 7 (3 wrong, 3 refused although answerable), 3 refused | 0 in Greek (9 right but in English, 4 wrong), 0 refused |
| This fork | 13, 3 refused | 12 (1 wrong), 3 refused | 13, 3 refused |

The original app does well in English and fails in all-Greek use: it answers a Greek question in
English and answers every question the text can't answer. The fork's translation bridge,
Greek-aware retrieval and refusals close that gap. Nothing in the app was changed because of these
questions. The grading was not blind (the grader knew which app wrote each answer).
The set is small (16 questions) and its library tiny (11 passages), so finding the passage is easy;
the larger Labour Code sets remain the main accuracy measure.

**Run again on 2026-10-30**, after the PoC capabilities and the reading-order fixes, with the same
automatic grading (the corrected one): the fork's result is unchanged, 12 of the 12 graded
answerable questions right and 3 of 3 unanswerable refused in each condition, all Greek answers in
Greek, the right passage retrieved every time (the same as the 2026-10-29 run under this grading).
Graded by hand, every answer read: English passages and English questions 13 of 13; Greek
passages and English questions 13 of 13; Greek passages and Greek questions 12 of 13 (1 wrong); 3
of 3 refused in each condition. Over both hand-graded runs the fork gets 38 of 39 answerable
questions right and refuses 9 of 9 unanswerable each time; the one wrong answer falls in a different
condition in each run, which is within the run-to-run variation.

## Revision history
- 2026-11-14 (later): chat recognition of capability requests ignores accents and case; ordinary
  questions are no longer sent to a template, opinion or summary; a described hiring arrangement
  tries the templates and falls back to Q&A. Template requests recognised from the chat: 0 → 38 of
  40 (dev), 13 of 20 (test, once). Capability failures show fixed messages.
- 2026-11-14: contract templates, summaries, opinions and OCR re-measured on the renamed app;
  unchanged within run variation.
- 2026-11-13: a Greek PDF's text layer is checked with PaddleOCR; one with wrong-letter fonts is
  read by OCR instead (lecture notes 0 → 38 overtime passages; Labour Code text kept).
- 2026-11-09: Greek wording of summaries, opinions and template answers repaired; a ministerial
  decision's figures kept in opinions; foreign law named by adjective refused (checked in the Mac
  app; Chapter 6 figures not re-measured).
- 2026-10-31: context-aware chunking (statute, lawyer's notes, Q&A, generic) with `GreekLegalDocumentClassifier`, `GreekLegalQAChunker`, and `GreekLegalNotesChunker`.
- 2026-10-31: direct in-chat capability execution (`GreekLegalChatRouter`), formatted legal text outputs without bullets, neutral contract template headers, and Opus-MT structured observability logging (`callStats`).
- 2026-10-30: EU holdout rerun graded by hand (38 of 39 right, 9 of 9 refused; as before).
- 2026-10-30: EU holdout run again (unchanged); every experiment recorded in `EXPERIMENTS.md`.
- 2026-10-30: Labour Code test split over the full Code (refusals, the Constitution question).
- 2026-10-30: five-document library (search by named law, contents left out), reading order of
  Gazette pages, summary of one statute and legal opinion (PoC capabilities), with development and
  test results; a glossary entry for «τρίμηνο» tried and dropped.
- 2026-10-30: contract template routing (PoC capability), with results.
- 2026-10-29: each statute knows which statute it is; a question naming another one is refused.
- 2026-10-29: tables keep one row a line; an off-topic figure no longer refuses a correct answer.
- 2026-10-29: OCR boxes follow tilted lines; scans read like clean pages (checked on other pages).
- 2026-10-29: OCR measured on scans and photos; faster translation at import, one direction in
  memory; batch translation tried and dropped; file names kept in Greek answers; source references
  not read as figures; run-to-run variation noted.
- 2026-10-29: EU holdout graded by hand (final numbers).
- 2026-10-29: EU holdout grading corrected for both apps (refusals, English answers to Greek
  questions, a question without expected terms).
- 2026-10-29: EU holdout before/after measured (bare model, original app, this fork).
- 2026-10-29: first version; one-sentence summary and the improvement loop; out-of-scope refusals,
  glossary Greek kept in answers, Cyrillic misreads of Greek stamps; holdout evaluation planned.
