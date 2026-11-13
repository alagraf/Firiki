<h1 align="center">🍎 Firiki (Φιρίκι)</h1>

<p align="center">
  <strong>A private, on-device AI assistant for Greek labour law</strong><br>
  <em>Answers, summaries, legal opinions and contract templates from your own legal documents, on an iPhone or Mac, with every claim tied to an article.</em>
</p>

<p align="center">
  <img alt="Platforms" src="https://img.shields.io/badge/Platforms-iOS%2026%2B%20%7C%20macOS%2026%2B-blue?style=flat-square&logo=apple">
  <img alt="Model" src="https://img.shields.io/badge/Model-Apple%20Foundation%20Models%20(on--device)-black?style=flat-square">
  <img alt="Status" src="https://img.shields.io/badge/Status-Proof%20of%20concept-orange?style=flat-square">
  <img alt="License" src="https://img.shields.io/badge/License-MIT-purple?style=flat-square">
</p>

---

## Why Firiki

Lawyers and HR teams can't paste client files into a cloud chatbot, and general-purpose assistants
handle Greek legal text poorly: they misread Greek scans, confuse article numbers between statutes,
and answer confidently when the law doesn't say.

Firiki is built around those three problems:

| Problem | What Firiki does |
|---|---|
| **Confidential documents** | Import, OCR, translation, search and answering all run on the device. Private Cloud Compute is not enabled in this build, cloud sync and remote web import are blocked, and the local stores are excluded from backups. |
| **Greek-language documents** | Reads Greek PDFs, scans and photos with an on-device Greek OCR model (Apple's Vision OCR doesn't read Greek), and bridges to Apple's on-device model with on-device Greek↔English translation. |
| **Trust** | Every answer cites the article and paragraph it comes from. A set of verification checks removes sentences the sources don't support, and the app refuses, in Greek, rather than guess when the evidence is weak or the question is about a law it doesn't hold. |

It's an academic thesis proof of concept (scope: Greek labour law), built by extending the
open-source [OpenIntelligence](https://github.com/Gunnarguy/OpenIntelligence) on-device RAG app.

---

## What it does

| Capability | Example request | Result |
|---|---|---|
| **Questions over a legal library** | «Πόσες ημέρες άδεια πατρότητας δικαιούται ο εργαζόμενος;» | A Greek answer citing article and paragraph, searched across several statutes at once (Labour Code π.δ. 62/2025, Laws 5239/2025, 5278/2026, 5316/2026, Ministerial Decision 8934/2026). A question that names a law is searched in that law. |
| **Statute summary** | «Σύνοψε το ν. 5278/2026» | An article-by-article summary of one imported law: purpose, key provisions, deadlines and amounts, each with its article. |
| **Legal opinion** | «Θέλω γνωμοδότηση: ο εργοδότης ζητά τέσσερις ώρες υπερωρία την ημέρα. Επιτρέπεται;» | A structured opinion over several documents (question, applicable law, what each text provides, how they combine, conclusion), with amendments to the Labour Code detected automatically, and a not-legal-advice note. |
| **Contract template** | «Ποιο υπόδειγμα σύμβασης ταιριάζει για τηλεργασία;» | The best of 10 bundled Greek employment-contract templates (indefinite, fixed-term, part-time, telework, apprenticeship…), with the reason and the relevant Labour Code articles, or "none fits". |

All four work by typing in the normal chat (the request is recognised automatically), from the
**Greek Legal AI** sheet in the chat, and from Siri / Shortcuts (`RouteLabourContractIntent`,
`SummarizeStatuteIntent`, `GreekLegalOpinionIntent`).

---

## How it works

```
 Greek PDF · scan · photo
          │
          ▼
 ① Read        Greek OCR (PaddleOCR PP-OCRv5 via ONNX Runtime), tilt-aware line boxes,
               Gazette layout and reading order, header removal, hyphen rejoining
          │
          ▼
 ② Structure   One passage per article paragraph, article title kept with each passage,
               table rows kept intact, the document's statute identity recorded (e.g. LAW:5278/2026)
          │
          ▼
 ③ Translate   Citations and names protected, then Greek→English with Opus-MT (INT8, on-device),
               a legal glossary keeps terms consistent
          │
          ▼
 ④ Search      Hybrid search: meaning (embeddings of the English text) + Greek keywords
          │
          ▼
 ⑤ Answer      Apple's on-device foundation model drafts in English from the cited passages
          │
          ▼
 ⑥ Verify      Checks A–I: sources, numbers, article citations, statute identity, foreign law;
               unsupported sentences dropped, or a fixed Greek refusal
          │
          ▼
 ⑦ Deliver     English→Greek translation, Greek wording repairs, official Greek terms restored;
               the details card shows the English draft, models used and each check's result
```

---

## What this fork added

Built on OpenIntelligence (upstream commit `a7276983`). The full record of every change, with the
reason and how it was verified, is in [`Docs/Thesis/FORK_CHANGES.md`](Docs/Thesis/FORK_CHANGES.md).

**New components**

| Area | Component | Role |
|---|---|---|
| Legal capabilities | `Services/Legal/GreekLegalChatRouter` | Recognises a summary, opinion or template request in the chat and runs it |
| | `GreekLegalDocumentSummarizer` | Statute summary in passes sized to the on-device context window |
| | `GreekLegalOpinionWriter` | Opinion across several documents, amendment detection, Greek post-editing |
| | `LabourContractTemplateRouter` + 10 templates in `Resources/LabourContractTemplates/` | Picks a contract template (model, with keyword fallback) |
| Greek OCR | `Services/Document/OCR/GreekPaddleOCRService`, `OCRRouterService` | On-device Greek OCR and the choice between it and Apple Vision |
| Greek ingestion | `Services/Document/Localization/GreekLegalStructureChunker`, `GreekLegalNotesChunker`, `GreekLegalQAChunker`, `GreekLegalDocumentClassifier`, `GreekLegalIngestion`, `PDFPage+Greek` | Statute structure, document type, statute identity, Greek PDF text |
| Translation | `LocalNeuralTranslator`, `GreekLegalEntityMasker`, `SpelledNumber` | On-device Opus-MT el↔en with citation masking, glossary and pre/post-edits |
| Verification | `Services/RAG/Safety/LegalVerificationPolicy`, `GreekLegalAnswerService`, `Retrieval/LegalCrossReferences` | Legal checks, Greek refusals, cross-references between articles |
| Privacy | `Infrastructure/Configuration/StrictLocalControlGuard` | Blocks backups, cloud sync, web import and Private Cloud Compute |
| Interface | `Features/Chat/Response/GreekLegalAssistantSheet`, `GreekLegalReviewCard` | The Greek Legal AI sheet and the answer's legal review card |
| Evaluation | `OpenIntelligenceTests/Services/GreekLegal/` (10 suites), `Benchmarks/Greek*`, `Benchmarks/LabourContractTemplates`, `scripts/thesis/` | Unit tests, benchmark sets and the evaluation harness |

**Changes to the original app**

- **Ingestion** (`DocumentProcessor`, `StructuredDocumentParser`): Greek pages routed to the Greek
  OCR, Greek legal chunking, translation at import, table rows kept, single-column detection.
- **Retrieval and answering** (`RAGService`, `QueryRuntimeCoordinator`, `VerificationGateService`):
  Greek legal mode, search by named law, on-device context budget whenever cloud compute is off,
  the original medical domain-isolation rules replaced by the legal statute-isolation check.
- **Chat and app** (`ChatScreen`, `GroundedAnswerView`, `ResponseDetailsView`, `RAGAppIntents`):
  in-chat routing of the four capabilities, legal review card, three new App Intents.
- **Repository**: the original author's release process, agent rules and Notion sync removed;
  thesis agent rules in `AGENTS.md`.

---

## Results

Measured on official Greek texts, 28–30 October 2026, in the iOS 27 Simulator on an M3 Pro Mac with
Apple's on-device model (AFM 3 Core Advanced, 8,192-token window).

| Task | Result | Starting point |
|---|---|---|
| Greek OCR, share of words read (10 pages: clean / scanned / photographed) | **96% / 96% / 96%** | Apple Vision 5%; scans 48% before tilt-aware line boxes |
| Greek OCR, whole scanned PDF | **98%** of words | 62% |
| Greek Constitution, 10 questions | **9 of 10** (right article found 10 of 10); 8 of 10 in later runs | 6 of 10 |
| Labour Code, development set (46 questions) | **38 of 46**; 5 of 5 out-of-scope questions refused | 24 of 46 |
| Labour Code, test set (23 questions, full 260-page Code) | **15 of 23**; 3 of 3 refused | 11 of 23 |
| Five-document library (development 24 / test 12) | **14 of 24 / 6 of 12** | 13 of 24 |
| Contract template choice (development 44 / test 22, half in Greek) | **43 of 44 / 20 of 22** | keywords alone: 26 of 44 / 8 of 22 |
| Statute summary, Law 5278/2026 | **5 of 6** key provisions, 3 of 3 articles cited | 2 of 6, 0 of 3 |
| Legal opinion (development 6 / test 4) | citations **10 of 12 / 3 of 8**; key facts **11 of 20 / 7 of 10** | — |
| Independent EU labour-law set, never tuned on (16 questions × 3 language conditions, graded by hand, two runs) | **38 of 39** answerable right and **9 of 9** unanswerable refused, in each run | Original app, all-Greek condition: 0 of 13 answered in Greek, 0 of 3 refused |

How to read these numbers:
- Each figure is a single run. The model's drafts vary between runs: 2 to 8 of the 46 Labour Code
  development questions flip between runs, so a difference of 1–3 questions isn't meaningful.
- "Starting point" is the first measurement of this fork, except where it names Apple Vision or the
  original app.
- A few Labour Code test questions shaped refusal rules during development, so it's a test split
  rather than a clean held-out set. [`Docs/Thesis/EXPERIMENTS.md`](Docs/Thesis/EXPERIMENTS.md)
  lists which.
- Later refinements (31 October, 9 November 2026: chunking, translation wording, refusals) were
  checked with unit tests and in the Mac app, but the figures above weren't re-measured.
- Nothing has been measured on a physical iPhone yet (speed, memory, answer quality).

Full records: [`EXPERIMENTS.md`](Docs/Thesis/EXPERIMENTS.md),
[`METHODS_SUMMARY.md`](Docs/Thesis/METHODS_SUMMARY.md), [`FORK_CHANGES.md`](Docs/Thesis/FORK_CHANGES.md).

---

## Setup

### Requirements

- An Apple-silicon Mac with **Xcode 27** (iOS 27 / macOS 27 SDK) and Python 3 (once, for the
  translation models).
- To get answers: **Apple Intelligence turned on**, on the Mac (macOS 26 or later) or an Apple
  Intelligence iPhone (iOS 26 or later). Apple Intelligence doesn't support Greek as the system
  language, so keep the device language English; documents and questions can be in Greek.
- About 3 GB of free disk space for the model preparation step.

### 1. Clone

```bash
git clone https://github.com/alagraf/Firiki.git
```

```bash
cd Firiki
```

### 2. Prepare the translation models (once)

The Greek↔English Opus-MT models (about 700 MB) aren't stored in git. This script downloads
`opus-mt-tc-big-el-en` and `opus-mt-tc-big-en-el` from Hugging Face, converts them to INT8 ONNX and
puts them in `OpenIntelligence/Resources/MLModels/Translation/`:

```bash
./scripts/thesis_fetch_translation_models.sh
```

The Greek OCR models (12 MB) are already in `OpenIntelligence/Resources/MLModels/GreekOCR/`.

### 3. Build and run

```bash
open OpenIntelligence.xcodeproj
```

Choose the **OpenIntelligence** scheme, then **My Mac** (recommended for demos) or a connected
iPhone, and run. No API keys or `.env` file are needed: nothing calls a server.

A command-line build check (iOS Simulator, iPhone 18 Pro by default; set
`OPENINTELLIGENCE_SIMULATOR_DESTINATION` to change it):

```bash
bash scripts/build_simulator_smoke.sh
```

If a build fails for no clear reason, check for iCloud duplicate files (the repository may live in
an iCloud-synced folder):

```bash
bash scripts/check_icloud_conflicts.sh
```

### 4. Try it

1. In **Documents**, import the Greek laws in `Benchmarks/GreekLabourLibrary/` and the Labour Code
   (`Benchmarks/GreekLabourCode/pd_62_2025_fek_a121.pdf`), or your own PDFs, scans or photos. Translation runs at import; import a large statute before a demo, since the
   full 260-page Labour Code takes about 15 minutes.
2. In **Chat**, ask a question in Greek, or a summary, opinion or template request like the
   examples in [What it does](#what-it-does).
3. Open an answer's details to see the sources, the English draft and the verification result.

---

## Tests and evaluations

The unit tests run in the iOS Simulator. `scripts/thesis_run_tests.sh` builds once, runs the
selected suites and stops `xcodebuild` cleanly. `-only-testing:` must name the suite struct (for
example `GreekLegalVerificationTests`), not the file (`GreekLegalPipelineTests.swift` holds several
suites), or the tests silently don't run.

```bash
./scripts/thesis_run_tests.sh /private/tmp/greek_tests.log -only-testing:OpenIntelligenceTests/GreekLegalVerificationTests -only-testing:OpenIntelligenceTests/StrictLocalControlGuardTests -only-testing:OpenIntelligenceTests/GreekLegalOpinionTests -only-testing:OpenIntelligenceTests/GreekLegalSummaryTests -only-testing:OpenIntelligenceTests/GreekLegalChatRouterTests -only-testing:OpenIntelligenceTests/LabourContractTemplateTests
```

The benchmark evaluations need Apple Intelligence on the Mac and are switched on by environment
variables, for example:

```bash
TEST_RUNNER_OI_TEMPLATE_ROUTING=1 TEST_RUNNER_OI_TEMPLATE_ROUTING_SPLIT=test ./scripts/thesis_run_tests.sh /private/tmp/routing.log -only-testing:OpenIntelligenceTests/LabourContractTemplateRoutingEvaluation
```

Others: `TEST_RUNNER_OI_OCR_BENCH=1` (`GreekOCRBenchmarkTests`), `TEST_RUNNER_OI_GREEK_SUMMARY=1`
(`GreekLegalSummaryEvaluation`), `TEST_RUNNER_OI_GREEK_OPINION=1` (`GreekLegalOpinionEvaluation`),
each with a `…_SPLIT=dev|test` variable.

---

## Known limitations

- Proof of concept for Greek labour law only. Not legal advice, and not a product.
- Not yet measured on a physical iPhone. The smaller on-device model of older iPhones (4,096-token
  window) wasn't used in any evaluation.
- Answers vary between runs, as the model's drafts do.
- Translation is the weakest stage: some Greek wording is repaired by fixed rules, and new phrasings
  can still read unnaturally.
- A question naming a law without its year («ν. 5239») may not be matched to that law.

More in [`METHODS_SUMMARY.md` §9](Docs/Thesis/METHODS_SUMMARY.md).

---

## Credits

Firiki is developed by **Alexandros Agrafiotis** as an academic thesis on private, on-device
retrieval-augmented generation for specialised legal domains.

- **[OpenIntelligence](https://github.com/Gunnarguy/OpenIntelligence)** by Gunnar Hostetler: the
  on-device RAG app this project extends (document import, vector index, hybrid search, answer
  verification).
- **[PaddleOCR](https://github.com/PaddlePaddle/PaddleOCR)**: PP-OCRv5 text detection and Greek
  recognition models.
- **[Helsinki-NLP Opus-MT](https://huggingface.co/Helsinki-NLP)**: Greek↔English translation models.
- **[ONNX Runtime](https://onnxruntime.ai/)**: on-device execution of the OCR and translation models.

Released under the MIT License (see [`LICENSE`](LICENSE)).

## Disclaimer

Firiki is a research prototype for research and information only. It doesn't give legal advice.
Rely on the official Government Gazette (*Εφημερίδα της Κυβερνήσεως*) and qualified counsel for any
legal decision.
