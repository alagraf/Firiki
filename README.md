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

**Firiki** (named after the historic, small Pelion apple variety *φιρίκι*) is an open-source, on-device legal question-answering assistant for iPhone. Developed as a Master's thesis proof of concept, Firiki adapts local Retrieval-Augmented Generation (RAG) to the challenging domain of **Greek labour law** (such as the Hellenic Labour Code Π.Δ. 62/2025 and constitutional provisions).

While general-purpose consumer LLMs rely on external cloud APIs and struggle with Greek legal terminology, statutory structure, and Greek-alphabet OCR, **Firiki operates under strict zero-egress local constraints**:
- **Zero Cloud Leakage:** Ingestion, OCR, translation, indexing, retrieval, reasoning, and verification run 100% on Apple Silicon hardware.
- **No Fine-Tuning Required:** Bridges pretrained open weights (PaddleOCR, Opus-MT) with Apple's on-device foundation model through an evaluation-driven, modular pipeline.
- **Auditable & Strict:** Answers cite exact statutory articles and paragraphs, enforce numeric consistency, and abstain gracefully when evidence is insufficient or inapplicable.

---

## ⚡ What is New in Firiki (Fork Highlights)

Firiki extends the upstream [OpenIntelligence](https://github.com/Gunnarguy/OpenIntelligence) engine with domain-specific components engineered specifically for the Greek legal system:

```
[Greek Legal PDF / Photo / Scan]
               │
               ▼
   [OCR Router & Text Repair]  ──────► (PaddleOCR PP-OCRv5 for Greek vs. Apple Vision)
               │
               ▼
  [Structure-Aware Chunking]   ──────► (Splits on statutory articles & numbered paragraphs)
               │
               ▼
[Masker & Terminology Engine]  ──────► (Protects laws, ΦΕΚ citations, ELOT 743 names)
               │
               ▼
   [On-Device Translation]     ──────► (INT8 Opus-MT el ↔ en with KV cache)
               │
               ▼
   [Bilingual Hybrid Index]    ──────► (Dense vector on EN text + Greek BM25 keywords)
               │
               ▼
   [Reasoning & Legal Gates]   ──────► (Apple Foundation Model + Statutory Isolation Gates)
               │
               ▼
   [Greek Verified Answer]     ──────► (Deterministic response with verified citations)
```

### 1. Hybrid On-Device Greek OCR Router
Apple Vision OCR natively lacks support for the Greek script. Firiki introduces an on-device `OCRRouterService` and `GreekPaddleOCRService`:
- Runs **PaddleOCR PP-OCRv5** (DB text detector and Greek recognizer via ONNX Runtime) directly on the device.
- Features dynamic page-language routing: routes images to Vision for Latin text and PaddleOCR for Greek text (achieving **96% word recall** on Greek scans and photos versus Vision's 5%).
- Automated pre- and post-processing: Unicode normalization, Greek homoglyph repair (correcting Latin look-alike characters in Gazette citations like `ΦΕΚ A'`), hyphenation rejoining across line wraps, and removal of Government Gazette running headers.

### 2. Legislative Structure-Aware Chunking
Generic chunking strategies cut statutory articles arbitrarily across token windows. Firiki implements a specialized legal parser:
- Chunks legal texts strictly along statutory boundaries (one passage per numbered paragraph of an article).
- Embeds parent article titles and context into every chunk so retrieval preserves the legislative hierarchy.

### 3. Translation-Bridged Bilingual Architecture
Apple's on-device foundation models perform with highest fidelity in English. Firiki introduces an on-device translation bridge:
- **Quantized Opus-MT:** Compact INT8 `el↔en` and `en↔el` models with key/value cache in the decoder for fast, low-memory inference on iOS devices.
- **Legal Entity & Citation Masking:** Custom rules identify legal citations (e.g., laws, presidential decrees, Government Gazette / ΦΕΚ references, court rulings) and mask them with protected tokens prior to translation, preventing distortion.
- **ELOT 743 Transliteration:** Proper Greek personal names are transliterated instead of erroneously translated.
- **Bilingual Legal Glossary:** Normalizes recurring Greek statutory terms to consistent English concepts during indexing and restores authoritative Greek legal vocabulary upon reverse translation.

### 4. Bilingual Hybrid Search & Article Lookup
- Combines semantic vector similarity search over translated English passages with token-level BM25 keyword search over original, unaccented, stem-matched Greek passages.
- Includes a dedicated statutory article index that matches direct citations (e.g., *"Άρθρο 65"*) directly to the target legal provision.

### 5. Legal Verification Gates & Refusal Policy
- Enforces strict factual consistency checks before showing an answer: checks that numbers, deadlines, conditions, and legal citations match the retrieved sources.
- **Strict Abstention:** Generates a deterministic, natural Greek refusal when questions touch out-of-scope jurisdictions, lack sufficient textual backing, or fail verification gates.
- **Full Audit Trail:** A "Response Details" inspector enables users to audit the English generation draft, verification gate telemetry, and active models.

### 6. Strict Local Privacy Guardrails
- Implements `StrictLocalControlGuard` enforcing thesis requirements R1.1–R1.4: excludes application data stores from device backups (`isExcludedFromBackup`), completely disables cloud sync (`WorkspaceSyncService`), and blocks outbound remote web fetching.

---

## 🛠️ Installation Instructions

### Prerequisites
- **macOS Sequoia (15.0+)** with **Xcode 16.0+**
- **iOS 18+** / iOS Simulator
- **Python 3.10+** (used once to prepare quantized ONNX translation weights)
- Apple Silicon Mac recommended for building and testing

### Step 1: Clone the Repository
```bash
git clone https://github.com/alagraf/Firiki.git
cd Firiki
```

### Step 2: Fetch and Prepare On-Device Translation Models
Firiki uses quantized INT8 Helsinki-NLP Opus-MT models for on-device translation. Run the automated fetch and conversion script:
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
Or open `OpenIntelligence.xcodeproj` directly in Xcode:
```bash
open OpenIntelligence.xcodeproj
```
Select the **OpenIntelligence** scheme and target your connected iOS device or iOS Simulator.

---

## 🚀 Usage

### 1. Ingesting Greek Legal Documents
1. Launch Firiki on your device or simulator.
2. Tap **Add to Library** to import Greek statutes (e.g., PDFs of the Labour Code, Government Gazette issues, or scanned contracts).
3. The live ingestion pipeline will display:
   - Greek language detection and text normalization.
   - Dynamic routing to **PaddleOCR** when processing scanned or photographed pages.
   - Statutory chunking and background translation via **Opus-MT**.

### 2. Querying Legal Provisions
Ask questions in natural Greek:
- *"Ποιες είναι οι προϋποθέσεις για τη χορήγηση άδειας πατρότητας;"*
- *"Ποια είναι η νόμιμη προθεσμία προειδοποίησης για απόλυση υπαλλήλου με 5 έτη υπηρεσίας;"*
- *"Τι προβλέπει το άρθρο 65 για το ωράριο εργασίας;"*

Answers are rendered deterministically in Greek with exact article and paragraph citations.

### 3. Inspecting Verification Details
- Tap inline citations to read the exact statutory excerpt behind each legal claim.
- Open **Response Details** to inspect the intermediate English draft, verification gate audit receipts, and OCR engine metrics.

### 4. Running the Thesis Test Suites
Firiki includes automated test harnesses and evaluation splits for Greek legal reasoning:
```bash
# Run the Greek legal unit test suite
./scripts/thesis_run_tests.sh /tmp/thesis_test.log -only-testing:OpenIntelligenceTests/GreekLegalPipelineTests

# Run the OCR benchmark tests
TEST_RUNNER_OI_OCR_BENCH=1 ./scripts/thesis_run_tests.sh /tmp/ocr_bench.log -only-testing:OpenIntelligenceTests/GreekOCRBenchmarkTests
```

---

## 📊 Empirical Evaluation (Thesis Summary)

Tested on official Greek statutory corpora (Hellenic Labour Code Π.Δ. 62/2025 and Greek Constitution):

| Metric / Benchmark | Baseline (Upstream) | Firiki (This Fork) | Notes |
|---|---|---|---|
| **Greek OCR Word Recall** | 5.0% (Vision) | **96.0%** (PaddleOCR) | Evaluated on clean & photographed Greek statute pages |
| **Greek QA Accuracy (Constitution)** | 6 / 10 | **9 / 10** (10/10 retrieval) | Measured on Greek legal query test set |
| **Labour Code Dev Set (46 Qs)** | 24 / 46 | **37 / 46** | Includes 100% correct refusal on out-of-scope questions |
| **EU Labour Directives Holdout (16 Qs)** | 0 / 13 in Greek (9 in EN) | **13 / 13 in Greek** (3/3 refused) | Evaluated on held-out parallel statutory corpus |

*For complete benchmarks, methodologies, and ablation details, refer to [`Docs/Thesis/METHODS_SUMMARY.md`](Docs/Thesis/METHODS_SUMMARY.md) and [`Docs/Thesis/FORK_CHANGES.md`](Docs/Thesis/FORK_CHANGES.md).*

---

## ⚖️ Credits & Acknowledgements

Firiki is developed by **Alexandros Agrafiotis** as part of an academic thesis exploring on-device, bilingual Retrieval-Augmented Generation for specialized legal domains.

### Upstream Project
Firiki is built upon and extends **[OpenIntelligence](https://github.com/Gunnarguy/OpenIntelligence)**, originally created by **[Gunnar Hostettler](https://github.com/Gunnarguy)**. We gratefully acknowledge the upstream project's foundational work in local, on-device vector indexing, hybrid BM25 retrieval, and privacy-preserving document architectures for Apple platforms.

### Third-Party Models & Libraries
- **[PaddlePaddle / PaddleOCR](https://github.com/PaddlePaddle/PaddleOCR)**: Lightweight text detection and Greek character recognition models.
- **[Helsinki-NLP (Opus-MT)](https://huggingface.co/Helsinki-NLP)**: Pretrained Greek–English bilingual transformer models.
- **[ONNX Runtime](https://onnxruntime.ai/)**: High-performance cross-platform inference engine for mobile neural network execution.

---

## 📜 Disclaimer

Firiki is an academic research proof of concept and is intended for informational and research purposes only. It does not provide certified legal advice. Always consult official publications of the Government Gazette (*Εφημερίδα της Κυβερνήσεως*) and qualified legal professionals for official legal matters.
