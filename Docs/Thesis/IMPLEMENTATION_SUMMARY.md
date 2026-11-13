# Fork implementation summary

> Commit hashes below are from before the 13 Nov 2026 identity rewrite. Look up the current hash in
> `Docs/Thesis/COMMIT_HASH_MAP.md` (local, git-ignored) before `git show` or `git diff`.

Everything the thesis fork changes in OpenIntelligence, grouped for the implementation chapter:
from the document coming in to the answer going out, then the capabilities built on top. Each item
names its section in `Docs/Thesis/FORK_CHANGES.md`, where the reasons, files and verification are
recorded. Results are in `Docs/Thesis/METHODS_SUMMARY.md`.

Written 2026-10-30, at commit `ffff0241` on branch `thesis/greek-legal-rag`.

## 1. Starting point and fork setup (FORK_CHANGES 2.1–2.10)

The base is OpenIntelligence, an iOS retrieval-augmented question-answering app built on Apple's
on-device foundation model. Before any Greek work:

- **Own identity:** own bundle IDs and signing. The iCloud, Private Cloud Compute and
  background-GPU entitlements were removed until the thesis account has them (2.1).
- **No commercial limits:** the app defaults to an unlimited tier with no library, document or
  mode limits (2.2).
- **Removed features:** the Atlas tab (2.3), and the original medical domain-isolation guardrail.
  It was first replaced by a jurisdiction caveat, then removed altogether (2.5, 2.6, 2.10).
- **Upstream sync:** the original author's latest code was merged in (139 commits), keeping the
  fork's identity and guardrail changes (2.7).
- **Project workflow:** the author's agent rules and tooling were replaced by the thesis workflow
  (2.8, 2.9).

## 2. Privacy: strict local control (2.11.1)

A strict local mode, on by default, enforces requirements R1.1–R1.4:

- the database and vector store are excluded from device backups;
- iCloud workspace sync never starts;
- every web import is blocked before any request is made;
- Private Cloud Compute is allowed only with its signed entitlement and the user's consent.

## 3. Reading Greek documents (2.11.3, 2.11.8, 2.11.19, 2.11.22, 2.11.27)

- **Greek OCR:** Apple's Vision has no Greek model, so PaddleOCR (PP-OCRv5 detector and Greek
  recogniser, run with ONNX Runtime) reads scans, photos and images inside PDFs.
  - A router chooses Vision or PaddleOCR by document language. It also switches to PaddleOCR when
    Vision's output looks like misread Greek, such as Latin or Cyrillic look-alike letters.
- **Tilted pages:** each text line's box follows the line's angle instead of being an upright
  rectangle. Measured on scans: 48% → 96% of words found (2.11.22).
- **Text clean-up:**
  - Unicode normalisation;
  - repair of Latin look-alike letters in Greek words;
  - quality filters that keep Greek instead of discarding it as noise;
  - rejoining words broken across lines;
  - removal of the Government Gazette's running headers.
- **Reading order of digital PDFs (2.11.27):**
  - Word positions are looked up in the PDF's raw text. The normalised text is longer at every
    keraia ("Α΄"), so positions taken from it belonged to later words, and Law 5278 lost 8 of its
    16 article headings.
  - A page counts as one column when its typical line spans more than half its width.
- **Processing Log:** shows when PaddleOCR reads a file and when Opus-MT translates it (2.11.8).

## 4. Structure-aware chunking (2.11.11, 2.11.23, 2.11.25)

- Statutes are split along their own structure: one passage per numbered paragraph of each
  article, each starting with its article heading. Generic size-based chunking had cut provisions
  in half.
- Tables keep one row per line through chunking and translation.
- Each document records which statute it is (law, decree, ministerial decision or the
  Constitution), read from its title page and stored on every passage (2.11.25).

## 5. Translation as a bridge to an English-centred model (2.11.2, 2.11.4, 2.11.10, 2.11.17, 2.11.18)

The on-device model works best in English, so a Greek question is translated to English.
Retrieval, generation and verification run in English, and the verified answer is translated back
to Greek.

- **Models:** Opus-MT transformer-big in both directions, converted to INT8 ONNX.
  - A decoder key/value cache makes decoding about 3.5× faster, so whole documents can be
    translated on the device at import.
  - Only one direction is kept in memory, and none after an import.
- **Bilingual storage:** each passage keeps its Greek source text next to its English translation
  (2.11.2).
- **Legal identifier masker:** laws, decrees, articles, paragraphs, Gazette references and court
  decisions are replaced by placeholders before translation and restored afterwards, so the
  translator can't distort them. Personal names are transliterated (ELOT 743), not translated.
- **Legal glossary:** recurring legal terms get one fixed English rendering, and the official
  Greek term is put back in the answer.
- **Document names:** kept as written in Greek answers (2.11.18).

## 6. Retrieval (2.11.4, 2.11.9, 2.11.27)

- **Hybrid search:**
  - semantic search over the English text;
  - a Greek keyword index over the original text that ignores accents and case and matches word
    stems.
- **Article lookup:** a question naming an article gets that article's passage first.
- **Several documents:**
  - A question naming a law of the library is searched only in that law's document.
  - A document's title page and contents are left out when it has articles.

## 7. Answer generation (2.11.5, 2.11.14)

- **Greek legal mode:** switched on for a question with at least 30% Greek letters. It applies on
  every answer path (Standard, Deep Think, Maximum).
- **Buffered, plain-text output:** no unverified token reaches the screen, and the answer appears
  once, after review.
- **Decoding:** greedy (deterministic), which also makes evaluation runs comparable.
- **Prompt rules:** answer only from the passages; give every figure, deadline, condition and
  exception they state; say which case or person each figure applies to.
- **Model settings:** the model's permissive content-transformation setting, so that ordinary
  legal topics (dismissal, pregnancy) aren't refused.

## 8. Verification and refusal (2.11.5, 2.11.14, 2.11.20, 2.11.24, 2.11.25)

Gates A–I check each English draft:

- **Gate A:** the evidence supports the claims, with a stricter threshold in legal mode.
- **Gate C:** every figure is in the passages, including figures the source writes as Greek
  numbers or as words.
- **Gate F:** every legal citation is in the passages.
- **Gate I (new):** the answer relies on the law the question names.

Refusal is preferred to guessing. A fixed Greek refusal is shown when:

- retrieval is weak (before any model call);
- the question names a statute that no passage comes from or cites;
- it is about another country's law that no passage covers;
- the draft itself says the passages don't answer it;
- a critical gate fails.

Two refinements stop correct answers being refused:

- an off-topic figure is dropped and the rest is checked again (2.11.24);
- a file-name source reference isn't treated as a figure (2.11.20).

## 9. User-interface changes (2.11.6, 2.11.8)

- **Review card under Response Details:** each gate's result, the English draft, the translated
  question and the models used, so every answer can be audited.
- **No suggested questions:** suggested and follow-up questions are switched off.

## 10. Proof-of-concept capabilities (2.11.26–2.11.29)

- **Template routing (2.11.26):**
  - Ten Greek labour contract templates are drafted from the Labour Code and marked as not legal
    advice.
  - The on-device model picks one, or none, from their descriptions. Its output is constrained to
    the valid template ids.
  - Keywords decide when the model is unavailable or blocked.
- **Five-document Q&A (2.11.27):** the Labour Code plus three labour laws and a ministerial
  decision, imported together, using the scope rules in section 6.
- **Summary of one statute (2.11.28):**
  - map notes per article group sized for the 4,096-token window;
  - provisions listed by the program, one per article;
  - the model writes only the opening;
  - unsupported sentences dropped;
  - documents without articles read in parts.
- **Legal opinion (2.11.29):**
  - retrieval per document;
  - links to amended Labour Code articles read from the amending laws' headings;
  - one model call per document plus a conclusion;
  - every sentence checked;
  - Greek output under fixed headings.

## 11. Evaluation infrastructure (2.11.12, 2.11.15, 2.11.16, 2.11.19, 2.11.30)

- **Harness:** imports documents through the real pipeline and asks each question as a user would.
- **Question sets, each with dev and test splits:**
  - Constitution (10);
  - Labour Code (69: 46 dev, 23 test);
  - five-document library (36);
  - summary set;
  - opinion set (10);
  - template routing (66).
- **OCR benchmark:** clean, scanned and photographed pages (2.11.19).
- **EU holdout:** a harness for both the fork and the original app, plus a regrading script.

## 12. Tried and dropped

- Translating several sentences at once: it changed translations and lowered accuracy (2.11.17).
- In the summary, letting the model write the provisions list: it renumbered articles (2.11.28).
- A glossary entry for «τρίμηνο»: it traded one dev question for another (2.11.27).

## Relation to the thesis proposal

These records contain no separate small legal language model (the <1B legal SLM stage) and no
fine-tuning. All components are used as published, and the improvements come from the pipeline
around them.
