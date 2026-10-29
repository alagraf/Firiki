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
- **Text clean-up.** Unicode normalisation; repair of Latin letters that look Greek (a Latin "A"
  in "ΦΕΚ A'"); quality filters that recognise Greek instead of discarding it as noise; rejoining
  words broken across lines; removal of the Government Gazette's running headers.

## 2. Structure-aware chunking
- Greek statutes are split along their own structure: one passage per numbered paragraph of each
  article, each starting with its article heading, long paragraphs split at sentence ends.
  Generic size-based chunking had cut provisions in half and separated paragraphs from their
  article.

## 3. Translation as a bridge to an English-centred model
- **Translate, answer, translate back.** Apple's on-device model works best in English. A Greek
  question is translated to English; retrieval, generation and verification run in English; the
  verified answer is translated back to Greek.
- **Translation models.** Opus-MT (Helsinki-NLP's Greek↔English transformer-big models), converted
  to compact INT8 ONNX models with a key/value cache in the decoder (about 3.5× faster decoding),
  so whole documents can be translated at import time on the device.
- **Protected legal identifiers.** Laws, decrees, articles, paragraphs, Gazette (ΦΕΚ) references
  and court decisions are recognised by rules, replaced by placeholders before translation and
  restored afterwards, so the translator cannot distort them. Personal names are transliterated
  (ELOT 743) instead of translated.
- **Legal glossary.** A small glossary gives each recurring legal term one fixed English rendering
  in documents and questions alike, and puts the official Greek term back into the Greek answer
  when the translator chose a synonym.

## 4. Retrieval
- **Hybrid search.** Semantic (embedding) search over the English text of each passage, combined
  with a keyword index over its original Greek text that ignores accents and case and matches word
  stems (Greek is highly inflected).
- **Article lookup.** A question that names an article gets that article's passages first.

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
  in the retrieved passages; it relies on the law the question names.
- **Refusal instead of guessing.** A fixed Greek refusal is shown when the evidence is weak, when
  the question is about another country's law that no passage covers, when the draft itself says
  the sources do not answer the question, or when a gate fails.
- The answer's details show the verification outcome, the English draft and the models used, so
  every answer can be audited.

## 7. Evaluation method
- **Question sets** written from the official texts, each with a reference answer citing article
  and paragraph and key-fact patterns for automatic grading:
  - Greek Constitution: 10 questions (the owner's set).
  - Labour Code, Π.Δ. 62/2025 (ΦΕΚ Α' 121/2025): 69 questions over leave, working time, wages,
    part-time work, dismissal and notice, severance, maternity and paternity protection,
    harassment and the digital work card, including cross-reference questions, questions in
    everyday language and 8 questions that must be refused. Split into development (46) and test
    (23) sets.
- **Whole-app measurement.** Each run imports the document through the app's real pipeline and
  asks every question through the same path a user's question takes. Retrieval accuracy (was the
  right article found), answer accuracy (are the key facts in the answer) and refusal accuracy
  are reported separately.
- **Iteration discipline.** Each failure is traced to its stage (OCR, translation, retrieval,
  generation or verification) and fixed in the app, never by putting answers into the app.
  Changes are tuned on the development set; the test set is used for held-out measurement.

## 8. Results so far
Measured in the iOS 27 Simulator with Apple's on-device model; not yet checked on a device.

| Date | Question set | Result |
|---|---|---|
| 2026-10-28 | Constitution (10) | 6 of 10 at the start |
| 2026-10-29 | Constitution (10) | 9 of 10; right article retrieved for 10 of 10 |
| 2026-10-29 | Labour Code, development (46), 37-page excerpt | 24 → 31 of 46 |
| 2026-10-29 | Labour Code, test (23), excerpt / full 260-page Code | 14 of 23 / 11 of 23 |
| 2026-10-29 | Labour Code, development (46), excerpt, after the out-of-scope refusals | 37 of 46; all 5 questions that must be refused were refused |

Import of the full 260-page Labour Code in the Simulator: about 29 minutes (4,218 passages).

## 9. Known limitations
- Refusal of off-topic questions has been measured on the development set (5 of 5 refused) but
  not yet on the held-out test split or over the full Code, where more loosely related passages
  compete.
- With the right article retrieved, the model still sometimes picks a figure for the wrong case.
- A question naming a different law than the library holds (e.g. "Article 16 of the
  Constitution" in a Labour Code library) is not yet recognised when the article number exists in
  both.
- OCR quality has so far been measured on rendered pages; scanned PDFs and photographed pages are
  the next OCR test set.
- No device measurements yet (speed, memory, answer quality on an iPhone).

## Holdout evaluation (planned)
A second, never-tuned test set is kept for the final before/after comparison (Chapter 6): 16
questions on 11 articles of EU labour directives, published officially in Greek and English (13
answered by the text, 3 not, to measure hallucination). It will be run on the bare on-device
model, on the original app and on this fork, with and without translation to English, and only
as a final measurement.

## Revision history
- 2026-10-29: first version; one-sentence summary and the improvement loop; out-of-scope refusals,
  glossary Greek kept in answers, Cyrillic misreads of Greek stamps; holdout evaluation planned.
