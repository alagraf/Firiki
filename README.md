<p align="center">
  <h1 align="center">🍎 Firiki (Φιρίκι)</h1>
  <p align="center">
    <strong>On-Device Greek Legal AI Assistant for iOS</strong>
  </p>
  <p align="center">
    <em>A privacy-preserving, retrieval-augmented intelligence assistant for Greek labour law running entirely on-device.</em>
  </p>
</p>

<p align="center">
  <img alt="Platform" src="https://img.shields.io/badge/Platform-iOS%2018%2B%20%7C%20macOS%2015%2B-blue?style=flat-square&logo=apple">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-6.0-orange?style=flat-square&logo=swift">
  <img alt="Inference" src="https://img.shields.io/badge/Inference-100%25%20On--Device-success?style=flat-square">
  <img alt="License" src="https://img.shields.io/badge/License-MIT-purple?style=flat-square">
  <img alt="Fork of" src="https://img.shields.io/badge/Forked%20from-OpenIntelligence-informational?style=flat-square">
</p>

---

## 📖 Overview

**Firiki** (named after the historic, small Pelion apple variety *φιρίκι*) is an open-source, on-device legal intelligence assistant for iPhone and iPad. Developed as a Master's thesis proof of concept, Firiki adapts local Retrieval-Augmented Generation (RAG) to the complex domain of **Greek labour law**—operating across codified statutes (the Hellenic Labour Code Π.Δ. 62/2025), newer amending statutes, ministerial decisions, and constitutional provisions.

While commercial cloud LLMs transmit sensitive user documents to external servers and frequently stumble over Greek legal terminology, statutory numbering, and Greek-alphabet OCR, **Firiki operates under strict zero-egress local constraints**:
- **Zero Cloud Leakage:** Ingestion, OCR, translation, indexing, retrieval, multi-turn reasoning, and verification run 100% on Apple Silicon hardware.
- **No Fine-Tuning Required:** Bridges pretrained open weights (PaddleOCR PP-OCRv5, Helsinki-NLP Opus-MT) with Apple's on-device foundation model through an evaluation-driven, modular pipeline.
- **Strict Verification & Auditing:** Answers cite exact statutory articles and paragraphs, enforce numeric sanity, prune out-of-scope figures, and deterministically abstain when evidence is insufficient or points to unindexed jurisdictions.

---

## ⚡ Key Capabilities & Fork Features

Firiki extends the upstream [OpenIntelligence](https://github.com/Gunnarguy/OpenIntelligence) engine with domain-specific legal intelligence capabilities and specialized architectural components:

```
[Greek Legal PDF / Photo / Scan]
               │
               ▼
   [OCR Router & Deskewing]    ──────► (PaddleOCR PP-OCRv5 + Oriented TextLineBox Sampling)
               │
               ▼
  [Structure-Aware Chunking]   ──────► (Statutory articles, numbered paragraphs & table rows)
               │
               ▼
[Masker & Terminology Engine]  ──────► (Protects laws, ΦΕΚ citations, ELOT 743 names)
               │
               ▼
   [On-Device Translation]     ──────► (INT8 Opus-MT el ↔ en with KV cache & Accelerate)
               │
               ▼
   [Bilingual Hybrid Index]    ──────► (Dense vector on EN text + Greek BM25 keywords)
               │
               ▼
 [Reasoning & Verification]    ──────► (Apple Foundation Model + Statutory Isolation Gates)
               │
               ▼
    [Four PoC Capabilities]    ──────► (Q&A · Statute Summary · Legal Opinion · Contract Routing)
```

### 1. Four Core Proof-of-Concept Capabilities

Firiki implements four specialized legal workflows designed to assist legal professionals and HR administrators:

1. **Multi-Document Statutory Q&A (5-Document Library)**:
   - Query across multiple interacting statutes simultaneously: the Labour Code (Π.Δ. 62/2025), Law 5239/2025, Law 5278/2026, Law 5316/2026, and Ministerial Decision 8934/2026 (minimum wage).
   - Features automatic named-statute query scoping, front-matter skipping, Gazette spatial reading order, and single-column vs. multi-column layout detection.
2. **Legislative Statute Summarization (`GreekLegalDocumentSummarizer`)**:
   - Generates structured, faithful summaries of entire statutes or decrees, detailing key provisions, deadlines, and figures with article citations.
   - Built with a map-reduce architecture strictly sized for on-device 4,096-token windows. Article provisions are assembled deterministically in code (preventing LLM renumbering hallucinations), with each claim verified against statutory evidence. Handles texts without article divisions (such as ministerial decisions) via content partition chunks.
3. **Multi-Document Legal Opinion Drafting (`GreekLegalOpinionWriter`)**:
   - Synthesizes formal legal opinions analyzing how newer statutes interact with or supersede the Labour Code.
   - Automatically detects statutory amendments ("τροποποιεί / αντικαθιστά άρθρο στον Κώδικα Εργατικού Δικαίου") directly from headings to prioritize latest statutory amendments over historical text.
   - Structured into: *Question, Applicable Law, Statutory Provisions, Synthesis/Harmonization, and Conclusion* (with non-advice disclaimer).
4. **Labour Contract Template Routing (`LabourContractTemplateRouter`)**:
   - Given a natural-language hiring prompt in Greek or English (e.g., *"Χρειαζόμαστε σερβιτόρο μόνο για τη θερινή σεζόν"* or *"part-time teleworking accountant"*), dynamically matches the requirement to one of 10 bundled Greek labour contract templates (or abstains with `none`).
   - Employs dynamic JSON schema decoding, safety guardrail retries (for minor/apprenticeship regulations), and dual-language keyword fallbacks.
5. **Native App Intents & Siri Shortcuts**:
   - Exposes `RouteLabourContractIntent`, `SummarizeStatuteIntent`, and `GreekLegalOpinionIntent` directly to iOS Shortcuts and Spotlight.

---

### 2. Specialized Engine & Infrastructure Components

#### Hybrid On-Device Greek OCR Router & Tilted Scan Deskewing
Apple Vision OCR natively lacks support for the Greek alphabet. Firiki incorporates `OCRRouterService` and `GreekPaddleOCRService`:
- Runs **PaddleOCR PP-OCRv5** (DB text detector and Greek recognizer via ONNX Runtime) directly on the device.
- **Oriented Line Bounding Boxes (`TextLineBox`)**: Rather than axis-aligned rectangles that take in parts of adjacent lines on crooked scans, Firiki computes bounding boxes along the line's principal axis and uses bilinear sampling. On tilted scans (±1.5°–2.5°), word recall improves from **48% to 96%**, matching clean pages (and reaching **98%** on full scanned PDFs).
- Automated pre- and post-processing: NFKC Unicode normalization, Greek homoglyph repair (correcting Latin look-alikes like `ΦΕΚ A'`), hyphenation rejoining across line wraps, and Gazette running header removal.

#### Legislative Structure-Aware Chunking & Table Preservation
Generic token-based chunking breaks legal articles arbitrarily across token bounds. Firiki implements a specialized legal parser:
- **Statutory Article & Paragraph Chunking**: Splits statutes strictly along legal boundaries (one chunk per numbered paragraph), embedding the parent article title into every chunk to preserve legislative context.
- **Table Row Preservation**: Detects tabular schedules (such as severance pay brackets in Labour Code Art. 333) and keeps rows intact without line concatenation, preventing cross-row figure mixing during translation and retrieval.

#### Translation-Bridged Bilingual Architecture
Apple's on-device foundation model operates with highest accuracy in English. Firiki provides a bidirectional translation bridge:
- **Quantized Opus-MT**: Compact INT8 `el↔en` and `en↔el` models with a decoder key/value cache and Accelerate-backed argmax, reducing full 260-page Code import times from 29 minutes to 15 minutes.
- **Legal Entity & Citation Masking**: Protects statutory citations (laws, presidential decrees, Gazette / ΦΕΚ issues, court decisions) with canonical placeholders before translation to prevent corruption.
- **ELOT 743 Transliteration**: Greek proper names are systematically transliterated rather than mistakenly translated.
- **Bilingual Legal Glossary**: Enforces consistent terminology during indexing and restores authentic Greek statutory wording (e.g., ensuring official phrasing in dismissal or leave provisions).

#### Statutory Verification Gates & Strict Abstention
- **Document Statutory Identity (`documentStatuteKey`)**: Passages record their statutory origin (e.g., `PD:62/2025`, `CONST`, `LAW:5278/2026`). Questions asking about unindexed statutes (e.g., asking about Article 16 of the Constitution in a Labour Code library) are refused prior to generation.
- **Verification Gates (A–I)**: Every draft answer is audited for numeric sanity (Gate C), statutory citations (Gate F), and source alignment (Gate B).
- **Off-Topic Figure Pruning**: If an extraneous figure from an adjacent passage appears, it is pruned without rejecting the valid cited answer.
- **Deterministic Greek Abstention**: Refuses gracefully when evidence is weak or out of scope.
- **Auditable Response Details**: Full transparency into intermediate English drafts, active models, and gate telemetry.

#### Strict Local Privacy Guardrails
- Enforces thesis requirements R1.1–R1.4 via `StrictLocalControlGuard`: excludes local stores from device backup (`isExcludedFromBackup`), disables cloud sync (`WorkspaceSyncService`), and blocks outbound remote web fetching.

---

## 🛠️ Installation Instructions

### Prerequisites
- **macOS Sequoia (15.0+)** with **Xcode 16.0+**
- **iOS 18+** / iOS Simulator (Apple Silicon Mac recommended)
- **Python 3.10+** (used once to prepare quantized ONNX translation weights)

### Step 1: Clone the Repository
```bash
git clone https://github.com/alagraf/Firiki.git
cd Firiki
```

### Step 2: Fetch and Prepare Translation Weights
Firiki uses quantized INT8 Helsinki-NLP Opus-MT models for on-device translation. Run the automated setup script:
```bash
chmod +x scripts/thesis_fetch_translation_models.sh
./scripts/thesis_fetch_translation_models.sh
```
*This downloads `opus-mt-tc-big-el-en` and `opus-mt-tc-big-en-el`, applies INT8 quantization with KV-cache export, and places the compiled assets in `OpenIntelligence/Resources/MLModels/Translation/` (~730 MB).*

### Step 3: Verify Model Assets
Ensure the Greek OCR and translation models exist in the resources directory:
```bash
ls -la OpenIntelligence/Resources/MLModels/GreekOCR/
# Expected: PP-OCRv5_mobile_det.onnx, el_PP-OCRv5_mobile_rec.onnx, el_dict.txt

ls -la OpenIntelligence/Resources/MLModels/Translation/
# Expected: encoder, decoder_step, decoder_cross, and tokenizer files
```

### Step 4: Build the Project
To run a headless smoke build on the simulator:
```bash
bash scripts/build_simulator_smoke.sh
```
Or open in Xcode:
```bash
open OpenIntelligence.xcodeproj
```
Select the **OpenIntelligence** scheme and target your connected iOS device or iOS Simulator.

---

## 🚀 Usage

### 1. Ingesting Greek Legal Documents
1. Launch Firiki on your device or simulator.
2. Tap **Add to Library** to import Greek statutory texts (Labour Code PDF, Gazette issues, or scanned contracts).
3. The live pipeline will display:
   - Dynamic routing to **PaddleOCR** with line-angle deskewing for scans.
   - Statutory article/paragraph chunking and table row preservation.
   - Background translation via **Opus-MT**.

### 2. Querying Legal Provisions & Statutes
Ask questions in natural Greek:
- *"Ποιες είναι οι προϋποθέσεις για τη χορήγηση άδειας πατρότητας;"*
- *"Ποια είναι η νόμιμη προθεσμία προειδοποίησης για απόλυση υπαλλήλου με 5 έτη υπηρεσίας;"*
- *"Τι προβλέπει ο ν. 5278/2026 για την ψηφιακή κάρτα εργασίας;"*

Answers cite exact articles and paragraphs, with clickable excerpts.

### 3. Summaries, Opinions & Contract Routing
- **Statute Summarization**: Select a statute and trigger "Summarize Statute" (or use Shortcuts) to receive an article-by-article synthesis of rules, deadlines, and figures.
- **Legal Opinion Drafting**: Submit a multi-statute scenario to receive a structured memorandum analyzing applicable laws, statutory conflicts, and legal conclusions.
- **Contract Template Routing**: Submit a prompt (e.g., *"Θέλουμε να προσλάβουμε υπάλληλο γραφείου για 3 ημέρες την εβδομάδα με τηλεργασία"*) to receive the recommended contract template from the 10 bundled templates.

### 4. Running Thesis Benchmarks & Evaluations
Firiki contains automated evaluation suites across all capabilities:
```bash
# Greek legal unit tests
./scripts/thesis_run_tests.sh /tmp/thesis_test.log -only-testing:OpenIntelligenceTests/GreekLegalPipelineTests

# Tilted OCR benchmark (clean, scan, photo)
TEST_RUNNER_OI_OCR_BENCH=1 ./scripts/thesis_run_tests.sh /tmp/ocr_bench.log -only-testing:OpenIntelligenceTests/GreekOCRBenchmarkTests

# Labour contract template routing evaluation (dev/test splits)
TEST_RUNNER_OI_TEMPLATE_ROUTING=1 TEST_RUNNER_OI_TEMPLATE_ROUTING_SPLIT=test ./scripts/thesis_run_tests.sh /tmp/routing.log -only-testing:OpenIntelligenceTests/LabourContractTemplateRoutingEvaluation

# Legislative statute summarization evaluation
TEST_RUNNER_OI_GREEK_SUMMARY=1 TEST_RUNNER_OI_GREEK_SUMMARY_SPLIT=dev ./scripts/thesis_run_tests.sh /tmp/summary.log -only-testing:OpenIntelligenceTests/GreekLegalSummaryEvaluation

# Multi-document legal opinion evaluation
TEST_RUNNER_OI_GREEK_OPINION=1 TEST_RUNNER_OI_GREEK_OPINION_SPLIT=dev ./scripts/thesis_run_tests.sh /tmp/opinion.log -only-testing:OpenIntelligenceTests/GreekLegalOpinionEvaluation
```

---

## 📊 Empirical Evaluation (Thesis Summary)

Tested on official Greek statutory corpora (Labour Code Π.Δ. 62/2025, Greek Constitution, amending laws, and parallel EU directives) in the iOS Simulator with Apple's on-device foundation model:

| Task / Metric | Baseline (Upstream) | Firiki (This Fork) | Notes |
|---|---|---|---|
| **OCR Word Recall (Clean & Photo)** | 5.0% (Vision) | **96.0%** (PaddleOCR) | Evaluated on Greek statute pages |
| **OCR Word Recall (Tilted Scans)** | 5.0% (Vision) | **96.0%** (PaddleOCR) | Improved from 48% with oriented bounding boxes |
| **OCR Recall on Full Scanned PDF** | ~5% | **98.0%** (words), **96.0%** (citations) | Whole-document import |
| **Constitution QA (10 Qs)** | 6 / 10 | **9 / 10** (10/10 retrieval) | Single-statute legal questions |
| **Labour Code Full Code (260 pages, 23 Qs)** | 11 / 23 (excerpt: 24/46) | **15 / 23** | Answerable: 12/20; right article retrieved 18/20 |
| **Statutory Abstention / Refusal** | 0% (answers hallucinatory) | **3 / 3 (100%)** on Full Code | Correctly refuses off-statute questions (e.g. Case 69) |
| **Contract Template Routing (66 prompts)** | N/A | **43 / 44** dev (97.7%), **20 / 22** test (90.9%) | Bilingual prompts; keywords alone: 26/44, 8/22 |
| **5-Document Library Q&A (36 Qs)** | N/A | **14 / 24** dev, **6 / 12** test | Multi-statute cross-retrieval |
| **Statute Summary (Law 5278/2026)** | N/A | **5 / 6** provisions, **3 / 3** articles | 0 dropped sentences |
| **Legal Opinion Citations & Facts** | N/A | Dev: **10 / 12** citations, **11 / 20** facts | Test: 3/8 citations, 7/10 facts |
| **EU Directives Holdout (Final Hand Grade)** | 0 / 13 in Greek (9 in EN) | **38 / 39 (97.4%)** correct, **9 / 9 (100%)** refused | Evaluated over two hand-graded runs across all conditions |

*For full experimental records, ablations, and error analyses, refer to [`Docs/Thesis/EXPERIMENTS.md`](Docs/Thesis/EXPERIMENTS.md), [`Docs/Thesis/METHODS_SUMMARY.md`](Docs/Thesis/METHODS_SUMMARY.md), and [`Docs/Thesis/FORK_CHANGES.md`](Docs/Thesis/FORK_CHANGES.md).*

---

## ⚖️ Credits & Acknowledgements

Firiki is developed by **Alexandros Agrafiotis** as part of an academic thesis exploring privacy-preserving, on-device Retrieval-Augmented Generation for specialized legal domains.

### Upstream Foundation
Firiki is built upon and extends **[OpenIntelligence](https://github.com/Gunnarguy/OpenIntelligence)**, originally created by **[Gunnar Hostettler](https://github.com/Gunnarguy)**. We gratefully acknowledge OpenIntelligence's pioneering architecture for on-device vector indexing, hybrid BM25 search, and offline Apple Silicon execution.

### Pretrained Models & Frameworks
- **[PaddlePaddle / PaddleOCR](https://github.com/PaddlePaddle/PaddleOCR)**: Lightweight text detection and Greek character recognition models (PP-OCRv5).
- **[Helsinki-NLP (Opus-MT)](https://huggingface.co/Helsinki-NLP)**: Bilingual Greek↔English transformer models.
- **[ONNX Runtime](https://onnxruntime.ai/)**: High-performance mobile neural network execution engine.

---

## 📜 Disclaimer

Firiki is an academic research proof of concept and is intended for research and informational purposes only. It does not provide certified legal advice. Always consult official publications of the Hellenic Government Gazette (*Εφημερίδα της Κυβερνήσεως*) and qualified legal counsel for binding legal interpretations.
