# Technical Implementation Specification: Greek Labour Law RAG Architecture on OpenIntelligence (v5.7)

**Target Baseline:** OpenIntelligence Release 5.7 (commit `a7276983`, synced with upstream `main` through `90d78d6`)  
**Language & Compiler Mode:** Swift 5 language mode (`SWIFT_VERSION = 5.0`, `swiftLanguageModes: [.v5]`) on the Swift 6.4 compiler  
**Target Hardware:** Apple Intelligence–capable devices (M3 Pro or newer Mac with 12 GB+ unified memory; iPhone 16 Pro Max / 17 Pro / 18 Pro; M4+ iPad) with device system language set to an Apple Intelligence–supported locale (English).

---

## 0. Critical Corrections & Architectural Synthesis from Developer Correspondence

Before modifying any code, the coding agent must account for eight empirical findings established against commits `a7276983` and `90d78d6`:

1. **Apple Vision Framework Does Not Support Greek OCR:** `VNRecognizeTextRequest` and `RecognizeDocumentsRequest` yield $0\%$ recall on rendered Greek pages. Greek OCR must use PaddleOCR’s Greek recognition model (`PaddlePaddle/el_PP-OCRv5_mobile_rec_onnx`, as `PP-OCRv6` lacks Greek support) paired with `PP-OCRv5_mobile_det` running locally via **ONNX Runtime (`onnxruntime-objc`)**.
2. **Multiple Vision Call Sites in Ingestion:** OCR is not limited to `parsePageImage` (`StructuredDocumentParser.swift`) and `performOCR` (`DocumentProcessor.swift`). Vision text recognition is invoked in at least three additional ingestion paths that write text to the corpus:
   - `LayoutAwareExtractor.swift` (replaces parser paragraphs on multi-column pages rendered for Vision).
   - `rescuePageRegions` in `IntelligentDocumentProcessor.swift` (invoked on failed pages prior to `performOCR`).
   - `ImageUnderstandingService.swift` (appends recognized text to image imports).
3. **Silent Greek Text Dropping in Extraction & Validation:**
   - Digital Greek PDFs extracted via `PDFKit` require immediate **Unicode `NFKC` normalization** so the Greek small letter mu (`U+03BC`) is not misencoded as the micro sign (`U+00B5`).
   - Page language cleanup inspects only the first $2,000$ characters of a page; mixed English/Greek pages drop Greek lines unless Greek Unicode blocks (`U+0370`–`U+03FF`, `U+1F00`–`U+1FFF`) are explicitly whitelisted.
   - `validateAndCleanOCR` in `StructuredDocumentParser.swift` checks text against an English stopword list and marks valid Greek text as low quality, dropping it before translation.
   - Because digital Greek PDFs with embedded text layers skip OCR entirely, **pivot translation must execute after unified document text extraction**, not exclusively inside the OCR callback.
4. **Apple `Translation` Framework Lacks Greek Support:** `TranslationService.swift` uses Apple’s native `Translation` framework, which does not support Greek (`el`). When a language pair is missing, `TranslationService.swift` silently passes the Greek string through untranslated. It must be backed by a local offline neural machine translation model (`el` $\leftrightarrow$ `en`) running via ONNX Runtime / CTranslate2.
5. **FTS5 Keyword Search Bypasses Translation by Default:** In `HybridSearchService.swift` (lines `1235–1265`), FTS5 executes the *untranslated* query first and only falls back to `translatedQueryForEmbedding` when the untranslated query returns zero results. A Greek query containing numbers or statutory tokens (`"38"`, `"4808/2021"`) can match an FTS5 row directly, preventing the English translated query from running.
6. **Cross-Reference & Graph Indexers Ignore Legal Citations:** `GraphIndexService.swift` (ingestion) and `resolveCrossReferencesStandard` in `RAGService.swift` (query time) only parse technical manual references (`page`, `table`, `figure`, `section`, `§`, `chapter`, `appendix`, `step`). Neither `"Article 22"` nor `"Άρθρο 22 παρ. 1"` matches.
7. **Verification Gates Run Post-Streaming & Abstention Falls Back by Default:**
   - At `a7276983`, answers stream directly to the UI while being generated; Gates A–I execute *after* streaming completes (and in Deep Think and Maximum modes, Gates A–I only label the response without retracting it).
   - When evidence scores below $0.20$ and `ModelExecutionPlanner` abstains, `reliabilityMode` in `RAGService.swift` (lines `15985`, `17278–17297`, `17384`) catches the abstention and either triggers a second LLM generation attempt or displays raw passages.
   - Gate F in `VerificationGateService.swift` currently only verifies `"Term (ABBR)"` abbreviation expansions, not statutory identifiers.
   - Gate I (`DomainIsolationService.swift`) checks lab-science terms (`in vivo` vs. `in vitro`, `"human"`, `"trial"`), causing false-positive `DOMAIN ISOLATION BREACH` refusals on constitutional and labour law texts.
8. **Plain Text Generation Outperforms `@Generable` for Sensitive Legal Topics:** Requesting `@Generable` structured outputs from `SystemLanguageModel` triggers false-positive Apple guardrail refusals on legal topics such as maternity dismissal protection, whereas plain-text generation succeeds.

---

## 1. Architecture & Data Flow Specification

### 1.1 Offline Ingestion Pipeline (Stages 1–6)

```text
[Greek PDF / Scan / DOCX / Image]
       │
       ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ STAGE 1: Document Intake & Strict Local Container Guard (R1.1 - R1.4)   │
│  • Disable iCloud Drive sync (CloudDocuments) & Web Page Fetching       │
│  • Store in local Application Support with isExcludedFromBackup = true  │
└─────────────────────────────────────────────────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ STAGE 2: Unified Text Extraction & Greek OCR Router                     │
│  • Digital PDF (PDFKit): Extract text → Apply Unicode NFKC Normalize    │
│    (converts U+00B5 → U+03BC) → Bypass 2,000-char English drop          │
│  • Scanned PDF / Image (OCRRouterService):                              │
│    Intercepts all 5 Vision call sites:                                  │
│    1. StructuredDocumentParser.parsePageImage                           │
│    2. DocumentProcessor.performOCR                                      │
│    3. LayoutAwareExtractor (multi-column Vision fallback)               │
│    4. IntelligentDocumentProcessor.rescuePageRegions                    │
│    5. ImageUnderstandingService                                         │
│    Routes Greek pages to ONNX Runtime (PP-OCRv5_mobile_det +            │
│    el_PP-OCRv5_mobile_rec_onnx) preserving table/list bounding boxes.   │
│  • Validation Hook: StructuredDocumentParser.validateAndCleanOCR        │
│    uses Greek character-ratio + Greek legal stopword heuristic.         │
└─────────────────────────────────────────────────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ STAGE 3: Structure-Aware Greek Chunking                                 │
│  • Chunk sizes: 260–310 target tokens (50 overlap, 380–510 hard cap)    │
│  • Respects Greek legal boundaries (Κεφάλαιο, Άρθρο, Παράγραφος, Πίνακας)│
│  • Produces sourceTextEl (immutable original Greek text for lawyer UI)  │
└─────────────────────────────────────────────────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ STAGE 4: Deterministic Legal Entity Masking & Pivot Translation (el→en) │
│  • Step 4a (GreekLegalEntityMasker): Regex extraction of Greek legal    │
│    citations (Ν. X/YYYY, ΠΔ, ΥΑ, Άρθρο X, παρ. Y, ΦΕΚ Α'/Β' ..., ΑΠ ...).│
│    Replaces citations with canonical placeholders (__LEX_ENT_001__)     │
│    and stores structured LegalEntity records.                           │
│  • Step 4b (LocalNeuralTranslator): 100% on-device translation (el→en)  │
│    via quantized ONNX/CoreML Opus-MT / EuroLLM model.                   │
│  • Step 4c (Unmasking to Canonical Dual-Tokens): Replaces placeholders  │
│    with canonical bilingual anchors in English text:                    │
│    e.g., "Article 38 [Άρθρο 38] of Law 4808/2021 [Ν. 4808/2021]".       │
└─────────────────────────────────────────────────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ STAGE 5: Embedding & Legal Graph Extraction                             │
│  • Bi-encoder: all-MiniLM-L6-v2 (384-d Float32) encodes translatedTextEn│
│  • GraphIndexService: Extended regex patterns extract cross-references  │
│    ("Article X", "Άρθρο X", "Law X/YYYY", "Ν. X/YYYY", "ΦΕΚ ...")       │
└─────────────────────────────────────────────────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ STAGE 6: Bilingual Dual-Index Persistence (SQLite FTS5 + Vector Store)  │
│  • FTS5 indexes translatedTextEn + canonicalized Greek/English entities │
│  • Chunk metadata table stores both sourceTextEl and translatedTextEn   │
│    plus JSON-serialized legalEntities array.                            │
└─────────────────────────────────────────────────────────────────────────┘
```

### 1.2 Online Query & Verification Pipeline (Phases A–F)

```text
[Lawyer Query in Greek (queryEl)]
       │
       ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ PHASE A: Pre-Search Entity Masking, Query Translation & Intent Routing  │
│  1. Extract & normalize Greek legal entities from queryEl.              │
│  2. Translate queryEl → queryEn locally via LocalNeuralTranslator       │
│     (plugged into RAGService.translatedQueryForEmbedding &              │
│     TranslationService.swift).                                          │
│  3. Resolve conversation memory (up to 3 relevant turns + summary over  │
│     8 turns in ConversationMemoryService.swift) in English.             │
│  4. Classify intent across all 8 intents in QueryEnhancementService     │
│     (lookup, table lookup, procedure, compare, summarize, investigate,  │
│     compute, findings) using queryEn + injected Greek legal keywords.   │
└─────────────────────────────────────────────────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ PHASE B: Bilingual Hybrid RRF Retrieval & Cross-Encoder Re-Ranking      │
│  1. Dense Arm: Embed queryEn with all-MiniLM-L6-v2 (384-d).             │
│  2. Lexical Arm (HybridSearchService.swift:1235-1265 Fix):              │
│     Execute FTS5 BM25 on queryEn + canonical legal entity tokens        │
│     (bypassing the untranslated-first short-circuit when Greek is active│
│     with field weights 10x title/header, 5x entities/keywords, 1x body).│
│  3. Fusion: Reciprocal Rank Fusion (k = 60, weights clamped 0.35–0.65). │
│  4. Re-ranking: ms-marco-TinyBERT-L2-v2 scores (queryEn, chunk.textEn). │
│  5. Diversification & Graph Packing: MMR (lambda = 0.8 High Precision) +│
│     extended resolveCrossReferencesStandard (resolving "Article X" /    │
│     "Άρθρο X" cross-references).                                        │
└─────────────────────────────────────────────────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ PHASE C: Strict Pre-Generation Abstention & Execution Routing           │
│  1. Relevance Gate (RAGService.swift:15340) & Planner Threshold:        │
│     If top re-ranked passage score < 0.20 (or < 0.30 with zero          │
│     lexical/entity overlap), HARD ABSTAIN immediately.                  │
│     Disable reliabilityMode fallback retry (RAGService.swift:15985,     │
│     17278-17297, 17384).                                                │
│  2. Optional SLM Enricher Hook (Professor's Benchmark Experiment):      │
│     Protocol hook (LegalSLMEnricherProtocol) allowing Speculative RAG   │
│     drafting or retrieval re-scoring while respecting token budget.     │
│  3. Execution Target Selection (ModelExecutionPlanner.swift):           │
│     • Default: On-device SystemLanguageModel (dynamic contextSize query)│
│     • Escalation: PrivateCloudComputeLanguageModel (32,768 tokens) ONLY │
│       if PCCEntitlementGuard.isAvailable == true AND user consents.     │
└─────────────────────────────────────────────────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ PHASE D: Buffered Plain-Text English Generation                         │
│  • Prompt packs chunk.translatedTextEn + canonical citations [C1, C2].  │
│  • Temperature capped at 0.2 (High Precision Legal Profile).            │
│  • Requests PLAIN TEXT with inline [C#] markers (NO @Generable struct   │
│    to avoid false-positive Apple safety refusals on labour law topics). │
│  • Output is held in an internal memory buffer (NOT streamed to UI yet).│
│  • Records model assetID ("instruct_3b" vs "instruct_server_v2").       │
└─────────────────────────────────────────────────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ PHASE E: Pre-Presentation Deterministic Verification (Gates A–I)        │
│  • Force sensitive-domain threshold elevation for all Greek Labour Law  │
│    queries (Gate A >= 0.55; SourceOnlyAnswerService >= 0.88).           │
│  • Gate C (Numeric Sanity): Normalizes Greek/English numerals & dates.  │
│  • Gate F (Quote & Legal Identifier Faithfulness): Verifies every       │
│    statutory/case-law identifier in the English draft exists in the     │
│    cited chunks' legalEntities metadata.                                │
│  • Gate I (Legal Statutory & Temporal Isolation): Replaces lab-science  │
│    in-vivo/in-vitro check with statutory conflict detection (prevents   │
│    mixing unaligned Law numbers or repealed vs. current articles).      │
│  • Enforcement across ALL modes (Standard, Deep Think, Maximum):        │
│    If any critical gate fails or composite confidence falls below the   │
│    threshold, discard the buffered draft and emit deterministic Greek   │
│    abstention message.                                                  │
└─────────────────────────────────────────────────────────────────────────┘
       │
       ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ PHASE F: Verified Response Translation (en→el) & Bilingual UI Rendering │
│  1. Mask canonical legal citations and [C#] markers in verified answer. │
│  2. Translate verified English answer → Greek via LocalNeuralTranslator.│
│  3. Restore Greek statutory identifiers (e.g., Ν. 4808/2021, Άρθρο 38). │
│  4. Render Greek response in UI; bind [C#] citation chips to            │
│     chunk.sourceTextEl so lawyers inspect verbatim Greek statutory text.│
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 2. File-by-File Modification Manifest

### 2.1 New Files to Create

| File Path | Responsibility |
| :--- | :--- |
| `OpenIntelligence/Services/Localization/GreekLegalEntityMasker.swift` | Deterministic regex lexer that detects Greek and English statutory identifiers (`Ν. XXXX/YYYY`, `ΠΔ`, `ΥΑ`, `Άρθρο`, `παρ.`, `εδ.`, `ΦΕΚ`, `ΑΠ`, `ΣτΕ`, `ΕφΑθ`), normalizes Unicode (`NFKC`), masks them prior to translation, and restores canonical bilingual anchors afterward. |
| `OpenIntelligence/Services/Localization/LocalNeuralTranslator.swift` | Offline bidirectional translation service (`el` $\leftrightarrow$ `en`) wrapping ONNX Runtime (`opus-mt-grk-en` and `opus-mt-en-el` INT8 quantized ONNX models) with LRU chunk/query caching, thread-safe actor isolation, and zero network access. |
| `OpenIntelligence/Services/OCR/GreekPaddleOCRService.swift` | ONNX Runtime wrapper executing `PP-OCRv5_mobile_det` + `el_PP-OCRv5_mobile_rec_onnx` on `CGImage` slices, returning recognized Greek text blocks with normalized bounding boxes for table/list reconstruction. |
| `OpenIntelligence/Services/OCR/OCRRouterService.swift` | Protocol-driven router (`OCREngineProtocol`) injected into all 5 OCR call sites. Routes images/pages to `GreekPaddleOCRService` when Greek OCR mode is enabled (or when Vision confidence/Greek character check fails), with side-by-side benchmark logging support. |
| `OpenIntelligence/Services/Security/StrictLocalControlGuard.swift` | Enforces Thesis Requirement 1 (R1.1–R1.4): disables iCloud Drive sync paths, sets `NSURLIsExcludedFromBackupKey` on SQLite/vector directories, blocks remote URL ingestion, and checks `PCCEntitlementGuard` before instantiating `PrivateCloudComputeLanguageModel`. |
| `OpenIntelligence/Services/Agentic/LegalSLMEnricherProtocol.swift` | Clean protocol boundary for the Professor's SLM experiment (Speculative RAG draft / legal domain re-ranker) so baseline AFM and SLM-augmented AFM can be toggled in benchmarks without modifying `RAGService.swift` internals. |
| `OpenIntelligenceTests/GreekLegalPipelineTests.swift` | Swift Testing suite (`@Test`) validating `NFKC` normalization, `GreekLegalEntityMasker`, `GreekPaddleOCRService`, bilingual SQLite storage, Gate C/F/I legal verification, and strict abstention. |

### 2.2 Existing Files & Exact Hook Points

| Existing File | Target Function / Line Reference (`a7276983` / `90d78d6`) | Exact Modification Required |
| :--- | :--- | :--- |
| `QuotaPolicy.swift` | Tier & document count constants | Raise free-tier document limit from `5` to `10_000` and remove IAP gates for local thesis evaluation. |
| `SharedInbox.swift`, `WidgetSnapshot.swift`, `IngestionLiveActivityWidget.swift` | App Group identifier strings | Replace upstream App Group identifier with your local developer App Group ID; guard shared container writes via `StrictLocalControlGuard`. |
| `StructuredDocumentParser.swift` | `parsePageImage(...)` & `validateAndCleanOCR(...)` | 1. In `parsePageImage`, route through `OCRRouterService.shared` when Greek mode is active.<br>2. In `validateAndCleanOCR`, check if text contains $\ge 15\%$ Greek Unicode scalars (`\u{0370}`–`\u{03FF}`, `\u{1F00}`–`\u{1FFF}`). If true, bypass the English common-word dictionary filter and validate against Greek legal stopwords (`και`, `του`, `της`, `άρθρο`, `νόμος`, `παρ`, `εργασία`). |
| `DocumentProcessor.swift` (~10,700 lines) | PDFKit text extraction, 2,000-char language detector, `performOCR(...)`, and pre-chunking stage | 1. Apply `.precomposedStringWithCompatibilityMapping` (`NFKC`) immediately to all `PDFPage.string` outputs.<br>2. In page language cleanup, scan the full page for Greek Unicode scalars rather than truncating detection at the first $2,000$ characters.<br>3. Route `performOCR` fallback through `OCRRouterService.shared`.<br>4. Insert `GreekLegalEntityMasker` + `LocalNeuralTranslator.translateToEnglish` after unified text extraction/chunking so both native PDF text and OCR text are translated. |
| `LayoutAwareExtractor.swift` | Vision multi-column paragraph replacement | Replace direct `VNRecognizeTextRequest` / `RecognizeDocumentsRequest` invocation with `OCRRouterService.shared.recognizeText(in:)`. |
| `IntelligentDocumentProcessor.swift` | `rescuePageRegions(...)` | Replace direct Vision text request with `OCRRouterService.shared.recognizeText(in:)`. |
| `ImageUnderstandingService.swift` | Image text extraction path | Route image OCR recognition through `OCRRouterService.shared.recognizeText(in:)`. |
| `TranslationService.swift` | Query & text translation dispatch | Add a fast-path check: if source or target language is `"el"` (Greek), delegate to `LocalNeuralTranslator.shared` instead of Apple’s `Translation` framework (which lacks Greek and silently returns untranslated text). |
| `QueryEnhancementService.swift` | Intent classification keyword rules (8 intents) | Ensure intent classification always evaluates `translatedQueryEn`. Add bilingual legal lookup patterns (`"article"`, `"law"`, `"decree"`, `"severance"`, `"dismissal"`, `"leave"`, `"άρθρο"`, `"νόμος"`, `"απόλυση"`, `"αποζημίωση"`, `"άδεια"`) so statutory queries route to `lookup` or `compare` rather than defaulting to `investigate`. |
| `HybridSearchService.swift` | Lines `1235–1265` (FTS5 keyword search dispatch) | Fix the untranslated-first FTS5 bug: when the query originates in Greek (`isGreekQuery == true`), execute FTS5 BM25 directly on `translatedQueryEn` combined with the extracted canonical legal entity tokens (`Ν. 4808/2021`, `Article 38`), rather than only running `translatedQueryForEmbedding` when the untranslated query returns $0$ hits. |
| `GraphIndexService.swift` | Ingestion reference regex patterns | Append legal cross-reference patterns (`(?:Article|Art\.|Άρθρο|Άρθρ\.|Αρ\.)\s*(\d+[Α-ΩA-Zα-ωa-z]?)`, `(?:Law|Ν\.|Νόμος|Π\.?Δ\.?)\s*(\d+\/\d{4})`, `ΦΕΚ\s*[ΑΒΓΔA-Z]'\s*\d+`) to the section/page reference extractors. |
| `RAGService.swift` (~22,800 lines) | • `translatedQueryForEmbedding` (~11,700)<br>• `resolveCrossReferencesStandard` (~13,200)<br>• Relevance Gate (`:15340`)<br>• Temperature selection (`:15721–15745`)<br>• Abstention fallback (`:15985`, `:17278–17297`, `:17384`)<br>• `requiresExactExtraction` (`:18515`)<br>• Streaming response emission | 1. Route Greek queries through `LocalNeuralTranslator` in `translatedQueryForEmbedding`.<br>2. Add `"Article X"` / `"Άρθρο X"` resolution to `resolveCrossReferencesStandard`.<br>3. Force plain-text generation (disable `@Generable` response struct for Greek legal mode).<br>4. Buffer generated English text until `VerificationGateService` completes.<br>5. Disable `reliabilityMode` second-try fallback and raw-passage dump at `:15985`, `:17278–17297`, and `:17384` when `strictLegalAbstention` is enabled.<br>6. Translate verified English response to Greek via `LocalNeuralTranslator` before emitting to the UI. |
| `DomainIsolationService.swift` | `strictModeEnabled` & domain taxonomy | Disable the clinical `in vivo` / `in vitro` keyword matcher (`"um"`, `"po"`, `"iv"`, `"human"`, `"trial"`). Replace with `LegalStatutoryIsolationMode` that flags cross-contamination only when retrieved passages exclusively cite a different primary statute (`Ν. XXXX/YYYY`) than the statute explicitly requested in the query. |
| `SourceOnlyAnswerService.swift` | Sensitive-domain keyword list & domain breach message | Add labour law terms (`"labor"`, `"labour"`, `"employment"`, `"dismissal"`, `"pregnant"`, `"maternity"`, `"severance"`, `"overtime"`, `"worker"`, `"employee"`, `"statute"`, `"article"`, `"εργασία"`, `"απόλυση"`) to the $0.88$ threshold trigger list. Update `DOMAIN ISOLATION BREACH` formatting for legal statutory conflicts. |
| `VerificationGateService.swift` | `runGateA`, `runGateC`, `runGateF`, `runGateI`, and mode enforcement | 1. **Gate A:** Trigger $0.55$ threshold on all legal container queries.<br>2. **Gate C:** Normalize Greek number formatting (`1.200,50` $\rightarrow$ `1200.50`) and date formats (`19.06.2021`) before numeric comparison.<br>3. **Gate F:** Extend beyond `"Term (ABBR)"` to verify that $100\%$ of statutory/case-law identifiers in the answer appear in the supporting chunks' `legalEntities`.<br>4. **Gate I:** Call the updated legal statutory isolation check.<br>5. Enforce gate rejection across Standard, Deep Think, and Maximum modes (not just labeling in Deep Think/Maximum). |
| `ModelExecutionPlanner.swift` | Context window query & PCC routing | Query `model.contextSize` dynamically from the device ($8,192$ on M3 Pro vs. $4,096$ fallback). Guard PCC instantiation with `StrictLocalControlGuard.canUsePCC()` and log `response.assetID` (`instruct_3b` vs. `instruct_server_v2`). |
| Citation / Evidence UI Views (`ChatResponseView` / `CitationPopoverView`) | Passage excerpt display | Render `chunk.sourceTextEl` (original Greek statutory text) when `sourceTextEl` is non-empty, while keeping `chunk.translatedTextEn` inspectable behind the existing "Technical Details" toggle. |

---

## 3. Legal Identifier & Metadata Preservation Schema

To allow the English bi-encoder (`all-MiniLM-L6-v2`), English FTS5 Porter stemmer, and English cross-encoder (`ms-marco-TinyBERT-L2-v2`) to operate on English text while the lawyer reads verbatim Greek laws and verified Greek citations, store a bilingual payload in SQLite.

### 3.1 Canonical Greek Legal Entity Data Model

```swift
// OpenIntelligence/Services/Localization/GreekLegalEntityMasker.swift
import Foundation

public enum GreekLegalEntityType: String, Codable, Sendable {
    case law = "LAW"                   // e.g., Ν. 4808/2021, Νόμος 4093/2012
    case presidentialDecree = "PD"     // e.g., Π.Δ. 80/2022, ΠΔ 62/2025
    case ministerialDecision = "MD"    // e.g., Υ.Α. 40331/Δ1.13521
    case article = "ARTICLE"           // e.g., Άρθρο 38, Άρθρ. 656 ΑΚ
    case paragraph = "PARAGRAPH"       // e.g., παρ. 1, § 2, εδ. α'
    case governmentGazette = "FEK"     // e.g., ΦΕΚ Α' 101/19.06.2021
    case supremeCourtDecision = "AP"   // e.g., ΑΠ 123/2023, ΟλΑΠ 1/2022, ΣτΕ 456/2021
    case euDirective = "EU_DIR"        // e.g., Οδηγία (ΕΕ) 2019/1152
}

public struct LegalEntityRecord: Codable, Hashable, Sendable {
    public let id: String              // Deterministic placeholder: "__LEX_LAW_4808_2021__"
    public let type: GreekLegalEntityType
    public let verbatimEl: String      // "Ν. 4808/2021"
    public let canonicalEn: String     // "Law 4808/2021"
    public let canonicalKey: String    // "LAW:4808/2021" (used by Gate F and FTS5)
    
    /// Injected into translatedTextEn after neural translation completes
    public var bilingualAnchor: String {
        "\(canonicalEn) [\(verbatimEl)]"
    }
}
```

### 3.2 Regex Rules for `GreekLegalEntityMasker`

All input strings must first pass through `text.precomposedStringWithCompatibilityMapping` (`NFKC`):

| Entity Type | Regex Pattern (Case-Insensitive, Unicode-Aware) | Canonical Key Template | Bilingual Anchor Output |
| :--- | :--- | :--- | :--- |
| **Statute (`LAW`)** | `\b(?:Ν\.|Νόμος|Νόμου|ΝΟΜΟΣ)\s*(\d{1,5})\s*\/\s*(\d{4})\b` | `LAW:$1/$2` | `Law $1/$2 [Ν. $1/$2]` |
| **Presidential Decree (`PD`)** | `\b(?:Π\.?\s*Δ\.?|ΠΡΟΕΔΡΙΚΟ\s+ΔΙΑΤΑΓΜΑ)\s*(\d{1,4})\s*\/\s*(\d{4})\b` | `PD:$1/$2` | `Presidential Decree $1/$2 [Π.Δ. $1/$2]` |
| **Article (`ARTICLE`)** | `\b(?:Άρθρο|Άρθρου|Άρθρα|Αρθρο|Άρθρ\.|Αρ\.)\s*(\d{1,4}[Α-Ωα-ωA-Za-z]?)\b` | `ART:$1` | `Article $1 [Άρθρο $1]` |
| **Paragraph (`PARAGRAPH`)** | `\b(?:παρ\.|παράγραφος|παραγράφου|§)\s*(\d{1,3}[Α-Ωα-ωa-z]?)\b` | `PAR:$1` | `paragraph $1 [παρ. $1]` |
| **Government Gazette (`FEK`)** | `\bΦ\.?Ε\.?Κ\.?\s*([ΑΒΓΔA-Z]'?)\s*(?:τ\.?\s*)?(\d{1,5})\s*\/\s*(\d{1,2}[\.\/-]\d{1,2}[\.\/-]\d{2,4})\b` | `FEK:$1:$2:$3` | `FEK $1 $2/$3 [ΦΕΚ $1' $2/$3]` |
| **Areios Pagos / Court (`AP`)** | `\b(Ολ\.?\s*Α\.?Π\.?|Α\.?Π\.?|Σ\.?τ\.?Ε\.?|Εφ\.?\s*Αθ\.?)\s*(\d{1,5})\s*\/\s*(\d{4})\b` | `COURT:$1:$2/$3` | `Decision $1 $2/$3 [$1 $2/$3]` |

### 3.3 Non-Destructive SQLite Schema Migration

To avoid breaking existing OpenIntelligence migrations or the $832$ existing unit tests, add nullable bilingual columns to the existing chunks metadata table and include canonical entity keys in the FTS5 index:

```sql
-- Migration: Add bilingual & legal provenance columns to document_chunks
ALTER TABLE document_chunks ADD COLUMN source_text_el TEXT DEFAULT NULL;
ALTER TABLE document_chunks ADD COLUMN source_language TEXT DEFAULT 'en';
ALTER TABLE document_chunks ADD COLUMN legal_entities_json TEXT DEFAULT '[]';
ALTER TABLE document_chunks ADD COLUMN primary_statute_key TEXT DEFAULT NULL;

-- Index on primary_statute_key for fast Gate I statutory domain isolation checks
CREATE INDEX IF NOT EXISTS idx_chunks_primary_statute 
ON document_chunks(primary_statute_key);
```

**Column Semantics:**
- `content` (existing column): Stores `translatedTextEn` enriched with `bilingualAnchor` tokens (e.g., `"According to Article 38 [Άρθρο 38] of Law 4808/2021 [Ν. 4808/2021], the employer..."`). Both `all-MiniLM-L6-v2` embeddings and `chunks_fts` (SQLite FTS5) read from `content`, so existing retrieval and re-ranking code paths require zero schema changes.
- `source_text_el`: Stores the exact, unmodified Greek text of the chunk (post-`NFKC` normalization) for UI citation popovers and legal provenance inspection.
- `legal_entities_json`: Stores the JSON-encoded `[LegalEntityRecord]` array extracted during Stage 4a. Gate F reads this array directly in memory to verify $100\%$ identifier faithfulness without re-parsing text.
- `primary_statute_key`: Stores the dominant `LAW:XXXX/YYYY` or `PD:XXX/YYYY` key of the document/section for Gate I legal isolation checks.

---

## 4. Phased Agent Task Breakdown

Hand the following instructions directly to your coding agent (Claude Code / Antigravity / Cursor).

### Pre-Flight Agent Hygiene Rules (Update `CLAUDE.md` / `AGENTS.md` First)

> **Instruction to Coding Agent:**
> 1. Replace the repository's existing `CLAUDE.md`, `AGENTS.md`, and `GEMINI.md` workflow instructions so you do **not** run external Notion sync scripts or read the entirety of `RAGService.swift` (~22,800 lines) or `DocumentProcessor.swift` (~10,700 lines) into context at once.
> 2. Always consult `Docs/ai/codemap/INDEX.md` first and use targeted line-range reads (`sed -n 'X,Yp'` or narrow `grep`) around the exact functions listed in this specification.
> 3. After every phase, run the build and targeted test suite via `xcodebuild` and display the raw terminal output before proceeding to the next phase.

---

### Phase 1: Fork Sync, Entitlement Sanitization & Strict Local Data Control (R1.1–R1.4)

**Objective:** Sync with upstream `main` (`90d78d6`), configure signing/quotas, and enforce strict local storage with zero unattested network egress.

1. **Sync & Identifier Configuration:**
   - Merge upstream `main` (`90d78d6`) while preserving your local Team ID, Bundle Identifier (across the main app, Share Extension, and Lock Screen Capture Extension), and App Group ID in `SharedInbox.swift`, `WidgetSnapshot.swift`, and `IngestionLiveActivityWidget.swift`.
   - Remove `com.apple.developer.icloud-services` (`CloudDocuments`) and `com.apple.developer.private-cloud-compute` from the `.entitlements` files until your Apple Developer account has the approved PCC entitlement.
   - In `QuotaPolicy.swift`, set the free-tier document limit to `10_000`.
2. **Create `StrictLocalControlGuard.swift`:**
   - Implement `StrictLocalControlGuard.enforceLocalStorage(for url: URL)` which sets `URLResourceValues.isExcludedFromBackup = true` on the local SQLite database and vector store directory in `Application Support`.
   - Disable iCloud Drive container resolution (`FileManager.default.url(forUbiquityContainerIdentifier:)`) when `StrictLocalControlGuard.isStrictLocalModeEnabled == true`.
   - Block the `"Save a Web Page"` remote URL ingestion action when `isStrictLocalModeEnabled == true`.
   - Implement `StrictLocalControlGuard.canUsePCC() -> Bool` using `SecTaskCopyValueForEntitlement` (on macOS) or bundle entitlement inspection + user consent verification so `ModelExecutionPlanner.swift` never instantiates `PrivateCloudComputeLanguageModel` when the entitlement is absent.
3. **Verification Step:**
   ```bash
   xcodebuild test -scheme OpenIntelligence -destination 'platform=macOS' -only-testing:OpenIntelligenceTests
   ```
   Verify all existing unit tests compile and pass, and confirm via unit test that `isExcludedFromBackup == true` on the container directory.

---

### Phase 2: Deterministic Greek Legal Entity Masker & Bilingual SQLite Schema

**Objective:** Build the deterministic statutory identifier lexer (`GreekLegalEntityMasker.swift`) and add the non-destructive bilingual columns to SQLite.

1. **Implement `GreekLegalEntityMasker.swift`:**
   - Implement `normalizeGreekText(_ text: String) -> String` applying `NFKC` normalization (`.precomposedStringWithCompatibilityMapping`) and normalizing Greek guillemets (`«`, `»`) and prime signs (`ʹ` $\rightarrow$ `'`).
   - Implement `maskEntities(in text: String) -> (maskedText: String, entities: [LegalEntityRecord])` matching Greek laws (`Ν. 4808/2021`), presidential decrees (`Π.Δ. 80/2022`), ministerial decisions, articles (`Άρθρο 38`), paragraphs (`παρ. 1`), Government Gazettes (`ΦΕΚ Α' 101/19.06.2021`), and court rulings (`ΑΠ`, `ΟλΑΠ`, `ΣτΕ`).
   - Implement `unmaskEntities(in translatedText: String, entities: [LegalEntityRecord], mode: UnmaskMode) -> String` supporting `.bilingualAnchor` (for indexing: `"Article 38 [Άρθρο 38]"`) and `.greekVerbatim` (for UI output: `"Άρθρο 38"`).
2. **Extend SQLite Chunk Persistence:**
   - Add `source_text_el`, `source_language`, `legal_entities_json`, and `primary_statute_key` columns to the SQLite schema migration and `DocumentChunk` model struct.
3. **Verification Step:**
   - Add `@Test func testGreekEntityMaskingAndNFKC()` in `OpenIntelligenceTests/GreekLegalPipelineTests.swift`:
     - Test that `"µισθός του Άρθρου 38 παρ. 1 του Ν. 4808/2021 (ΦΕΚ Α' 101/19.06.2021)"` normalizes `U+00B5` to `U+03BC`, masks all 4 legal entities deterministically, and unmasks them into exact bilingual anchors.
   - Run `xcodebuild test -scheme OpenIntelligence -destination 'platform=macOS' -only-testing:OpenIntelligenceTests/GreekLegalPipelineTests`.

---

### Phase 3: Greek OCR Integration (`el_PP-OCRv5_mobile_rec_onnx`) & Extraction Fixes

**Objective:** Replace Vision OCR with PaddleOCR v5 Greek ONNX models for Greek documents and eliminate silent Greek text dropping in `StructuredDocumentParser.swift` and `DocumentProcessor.swift`.

1. **Add ONNX Runtime & Bundle Greek OCR Models:**
   - Add `onnxruntime-objc` via Swift Package Manager (or link the existing runtime) and bundle `PP-OCRv5_mobile_det.onnx`, `el_PP-OCRv5_mobile_rec.onnx` (`PaddlePaddle/el_PP-OCRv5_mobile_rec_onnx`), and the Greek character dictionary `el_dict.txt`.
2. **Implement `GreekPaddleOCRService.swift` & `OCRRouterService.swift`:**
   - Implement text box detection (`PP-OCRv5_mobile_det`), crop perspective-corrected line images sorted in top-to-bottom, left-to-right reading order (preserving horizontal y-alignment for table rows and indentation for numbered legal paragraphs), and run CTC greedy/beam decoding via `el_PP-OCRv5_mobile_rec.onnx`.
   - Expose `OCRRouterService.shared` behind a setting (`ocrEngineMode: .vision | .greekPaddleOCR | .autoBenchmark`).
3. **Hook All 5 Ingestion OCR Call Sites & Fix Text Filters:**
   - Route `parsePageImage` (`StructuredDocumentParser.swift`), `performOCR` (`DocumentProcessor.swift`), multi-column OCR (`LayoutAwareExtractor.swift`), `rescuePageRegions` (`IntelligentDocumentProcessor.swift`), and `ImageUnderstandingService.swift` through `OCRRouterService.shared`.
   - In `StructuredDocumentParser.swift` $\rightarrow$ `validateAndCleanOCR`, bypass the English word list check when Greek Unicode character density is $\ge 15\%$.
   - In `DocumentProcessor.swift`, apply `GreekLegalEntityMasker.normalizeGreekText` (`NFKC`) to `PDFPage.string` and remove the $2,000$-character truncation on page language detection so mixed English/Greek pages retain all Greek paragraphs.
4. **Verification Step:**
   - Add `@Test func testGreekOCRAndValidationBypass()` in `GreekLegalPipelineTests.swift` that renders a test page of `Ν. 4808/2021` into a `CGImage`, runs `GreekPaddleOCRService`, verifies Word Error Rate (WER) is $< 5\%$, and confirms `validateAndCleanOCR` retains $100\%$ of the Greek paragraph.

---

### Phase 4: On-Device Neural Translation (`el` $\leftrightarrow$ `en`) in Ingestion & Query Pipelines

**Objective:** Integrate $100\%$ local bidirectional Greek-English translation across ingestion, query understanding, FTS5 hybrid search, and cross-reference resolution.

1. **Implement `LocalNeuralTranslator.swift`:**
   - Bundle quantized INT8 ONNX models (`opus-mt-grk-en` and `opus-mt-en-el`, or a quantized 4-bit local CTranslate2/GGUF translation model) inside the app's local model assets.
   - Implement `translateGreekToEnglishPreservingLegalEntities(_ textEl: String) async throws -> (textEn: String, entities: [LegalEntityRecord])`:
     1. Run `GreekLegalEntityMasker.maskEntities(in: textEl)`.
     2. Translate the masked sentences (`el` $\rightarrow$ `en`) locally on-device.
     3. Unmask placeholders into `.bilingualAnchor` format (`"Article 38 [Άρθρο 38]"`).
   - Implement `translateEnglishToGreekPreservingCitations(_ textEn: String, entities: [LegalEntityRecord]) async throws -> String` for Phase F response translation, preserving `[C1]`, `[C2]` markers and restoring `.greekVerbatim` statutory names.
2. **Hook Ingestion & Query Translation:**
   - **Ingestion (`DocumentProcessor.swift`):** After unified text extraction and structure-aware chunking (covering both native PDFKit text and OCR text), populate `chunk.sourceTextEl = rawChunkText`, run `translateGreekToEnglishPreservingLegalEntities`, and set `chunk.content = translatedTextEn`, `chunk.legalEntities = entities`.
   - **Query Translation (`TranslationService.swift` & `RAGService.swift`):** Route `"el"` queries in `TranslationService.swift` and `translatedQueryForEmbedding` in `RAGService.swift` to `LocalNeuralTranslator.shared`.
   - **FTS5 Fix (`HybridSearchService.swift:1235-1265`):** When the user query contains Greek characters, pass `translatedQueryEn` + extracted `canonicalKey` tokens directly to the primary FTS5 BM25 query instead of waiting for the untranslated Greek query to return $0$ results.
   - **Intent & Cross-References (`QueryEnhancementService.swift`, `GraphIndexService.swift`, `RAGService.swift`):** Add Greek/English legal article and statute regexes to `GraphIndexService.swift` and `resolveCrossReferencesStandard` in `RAGService.swift`.
3. **Verification Step:**
   - Add `@Test func testBilingualIngestionAndHybridRetrieval()` in `GreekLegalPipelineTests.swift`:
     - Ingest 3 Greek articles from `Ν. 4808/2021`, run a Greek query (`"Ποιες είναι οι προϋποθέσεις απόλυσης σύμφωνα με το Άρθρο 66 του Ν. 4808/2021;"`), and assert that:
       1. `QueryEnhancementService` classifies the intent as `lookup`.
       2. `HybridSearchService` ranks the target chunk at Rank 1 ($\text{R@1} = 1.0$).
       3. `chunk.sourceTextEl` contains the original Greek text while `chunk.content` contains the English translation with `[Ν. 4808/2021]`.

---

### Phase 5: Pre-Presentation Verification Gates (A–I), Strict Abstention & Plain-Text Generation (R2.1–R2.5)

**Objective:** Enforce pre-presentation verification across all modes, replace lab-science Gate I with legal statutory isolation, validate statutory identifiers in Gate F, and translate verified responses back to Greek.

1. **Switch Generation to Buffered Plain Text (`RAGService.swift`):**
   - When operating on a Greek Legal container, request **plain text** generation with `[C#]` inline citation markers instead of `@Generable` structs (preventing false-positive Apple safety refusals on pregnancy/dismissal labour law topics).
   - Buffer the generated English text in memory rather than streaming unverified tokens to the UI.
   - Record `response.assetID` (`instruct_3b` for on-device vs. `instruct_server_v2` for PCC) in the diagnostic log for thesis evaluation.
2. **Enforce Strict Abstention (`RAGService.swift:15340, 15985, 17278-17297, 17384`):**
   - If the top passage score is $< 0.20$ (or fails the relevance gate at `:15340`), immediately return the localized Greek abstention message without calling the language model.
   - Bypass the `reliabilityMode` fallback blocks at `:15985`, `:17278–17297`, and `:17384` so the app never makes an unverified second generation attempt or dumps raw unverified excerpts as an answer.
3. **Adapt Verification Gates (`VerificationGateService.swift`, `DomainIsolationService.swift`, `SourceOnlyAnswerService.swift`):**
   - **Elevated Legal Thresholds:** In `VerificationGateService.swift` and `SourceOnlyAnswerService.swift`, elevate Gate A to $0.55$ and the source-only threshold to $0.88$ whenever the container is marked as Legal or the query matches labour law keywords.
   - **Gate C (Numeric Sanity):** Normalize Greek thousand/decimal separators (`1.500,00` $\leftrightarrow$ `1,500.00`) and Greek dates (`DD.MM.YYYY`) before checking numeric fidelity.
   - **Gate F (Legal Identifier & Quote Faithfulness):** Extract all statutory/case-law identifiers (`LAW:...`, `ART:...`, `PD:...`, `FEK:...`, `COURT:...`) from the generated English draft using `GreekLegalEntityMasker` and verify that **every single identifier** appears in the union of `legalEntities` of the retrieved passages. If the model hallucinates an article or law number not present in the retrieved chunks, Gate F **fails immediately**.
   - **Gate I (`DomainIsolationService.swift`):** Disable the lab-science (`in vivo` / `in vitro`) matcher. Implement `checkLegalStatutoryIsolation(queryEntities:passageEntities:)`: if the user query explicitly specifies a statute (e.g., `LAW:4808/2021`) and $100\%$ of the retrieved passages belong to a *different* primary statute without cross-referencing `LAW:4808/2021`, fail Gate I with a statutory isolation refusal.
   - **Enforce Rejection in All Modes:** Ensure failed verification gates reject the buffered response in Standard, Deep Think, and Maximum modes alike.
4. **Response Translation & Bilingual Citation UI (`RAGService.swift` & Chat UI):**
   - Once Gates A–I pass, pass the buffered English answer through `LocalNeuralTranslator.translateEnglishToGreekPreservingCitations`, restoring Greek statutory citations (`Ν. 4808/2021`, `Άρθρο 38`) and `[C#]` tags, and emit the verified Greek response to the UI.
   - In the citation inspection view, display `chunk.sourceTextEl` as the primary excerpt so the lawyer reads the authentic Greek legal text, and display the gate confidence breakdown + `assetID` under the existing "Technical Details" toggle.
5. **Optional Hook for the Professor's SLM Experiment (`LegalSLMEnricherProtocol.swift`):**
   - Inject an optional `slmEnricher: LegalSLMEnricherProtocol?` into `RAGService.swift` right before Phase D prompt assembly (respecting the device `contextSize` token budget) so you can run A/B benchmarks between standalone Apple Foundation Models and Speculative RAG (`SLM + AFM`).
6. **Verification Step:**
   - Add `@Test func testGateFHallucinatedArticleRejection()`, `@Test func testGateILegalConstitutionNoFalseBreach()`, and `@Test func testStrictAbstentionBelowThreshold()` in `GreekLegalPipelineTests.swift`:
     - Verify the Greek Constitution query (`"What is the minimum and maximum allowable number of Members of Parliament?"` / `"Ποιος είναι ο ελάχιστος και μέγιστος αριθμός βουλευτών;"`) passes Gate I with zero `IN VIVO / IN VITRO` breach.
     - Verify that a draft citing `"Άρθρο 99 του Ν. 4808/2021"` when the retrieved chunk only contains `"Άρθρο 38 του Ν. 4808/2021"` is deterministically rejected by Gate F before reaching the UI.
     - Run the full test suite ($832$ baseline tests + new `GreekLegalPipelineTests`) to verify zero regressions.