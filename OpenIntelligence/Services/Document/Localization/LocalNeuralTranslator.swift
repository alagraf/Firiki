//
//  LocalNeuralTranslator.swift
//  OpenIntelligence
//
//  Thesis fork, plan stages 4b and F: on-device Greek↔English translation. Apple's Translation
//  framework has no Greek, so text is translated by Helsinki-NLP's Opus-MT Marian models
//  (`opus-mt-tc-big-el-en`, `opus-mt-tc-big-en-el`, CC-BY 4.0), exported to ONNX as an encoder, a
//  cross-attention graph and a one-token decoder step with a key/value cache, quantized to INT8
//  (`scripts/thesis_fetch_translation_models.sh`), run with ONNX Runtime. Nothing leaves the device.
//
//  Tokenization is SentencePiece unigram (Viterbi over the source model's pieces and scores), ids
//  from Marian's shared vocabulary. Decoding is greedy: the encoder runs once, `decoder_cross`
//  turns its output into each layer's cross-attention keys and values once, and `decoder_step`
//  reads one token at a time with the keys and values of the tokens before it, so a token costs
//  one token's work (3.5× faster than re-running the whole prefix, measured on the Constitution).
//
//  Legal identifiers never go through the model: `GreekLegalEntityMasker` replaces them with
//  placeholders first and restores them afterwards.
//

import Foundation
#if canImport(OnnxRuntimeBindings)
import OnnxRuntimeBindings
#endif

nonisolated enum TranslationDirection: String, Sendable, CaseIterable {
    case greekToEnglish = "opus-mt-tc-big-el-en"
    case englishToGreek = "opus-mt-tc-big-en-el"
}

// MARK: - SentencePiece unigram tokenizer

nonisolated struct SentencePieceUnigramTokenizer: Sendable {
    let scores: [String: Float]
    let maxPieceLength: Int
    let vocab: [String: Int]
    let idToPiece: [Int: String]
    let unkId: Int
    let eosId: Int
    let padId: Int
    let decoderStartId: Int
    /// Decoder shape, for the key/value cache.
    let decoderLayers: Int
    let attentionHeads: Int
    let headDim: Int
    private let unknownScore: Float

    private struct File: Decodable {
        struct Meta: Decodable {
            let pad_id: Int
            let eos_id: Int
            let unk_id: Int?
            let decoder_start_token_id: Int
            let decoder_layers: Int?
            let attention_heads: Int?
            let head_dim: Int?
        }
        let source_pieces: [[PieceField]]
        let vocab: [String: Int]
        let meta: Meta
    }

    private enum PieceField: Decodable {
        case text(String), score(Float)
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let text = try? container.decode(String.self) { self = .text(text) } else { self = .score(try container.decode(Float.self)) }
        }
    }

    init(jsonData: Data) throws {
        let file = try JSONDecoder().decode(File.self, from: jsonData)
        var scores: [String: Float] = [:]
        var maxLength = 1
        for entry in file.source_pieces {
            guard entry.count == 2, case let .text(piece) = entry[0], case let .score(score) = entry[1] else { continue }
            // Control pieces (<unk>, <s>, </s>) never match input text.
            if piece.hasPrefix("<") && piece.hasSuffix(">") { continue }
            scores[piece] = score
            maxLength = max(maxLength, piece.count)
        }
        self.scores = scores
        self.maxPieceLength = maxLength
        self.vocab = file.vocab
        self.idToPiece = Dictionary(file.vocab.map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        self.unkId = file.meta.unk_id ?? 1
        self.eosId = file.meta.eos_id
        self.padId = file.meta.pad_id
        self.decoderStartId = file.meta.decoder_start_token_id
        self.decoderLayers = file.meta.decoder_layers ?? 6
        self.attentionHeads = file.meta.attention_heads ?? 8
        self.headDim = file.meta.head_dim ?? 64
        self.unknownScore = (scores.values.min() ?? -20) - 10
    }

    /// SentencePiece's nmt_nfkc normalization: NFKC, whitespace collapsed, "▁" for spaces and in front.
    static func normalize(_ text: String) -> String {
        let collapsed = text.precomposedStringWithCompatibilityMapping
            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        return "▁" + collapsed.replacingOccurrences(of: " ", with: "▁")
    }

    /// Best segmentation by total piece score (Viterbi); a character no piece covers is `<unk>`,
    /// and consecutive unknown characters become one `<unk>`.
    func pieces(for text: String) -> [String] {
        let chars = Array(Self.normalize(text))
        let n = chars.count
        guard n > 0 else { return [] }
        var best = [Float](repeating: -.infinity, count: n + 1)
        var back = [(start: Int, piece: String?)](repeating: (0, nil), count: n + 1)
        best[0] = 0
        for end in 1...n {
            for length in 1...min(maxPieceLength, end) {
                let start = end - length
                guard best[start] > -.infinity else { continue }
                let candidate = String(chars[start..<end])
                if let score = scores[candidate], best[start] + score > best[end] {
                    best[end] = best[start] + score
                    back[end] = (start, candidate)
                }
            }
            if best[end] == -.infinity, best[end - 1] > -.infinity {
                best[end] = best[end - 1] + unknownScore
                back[end] = (end - 1, nil)
            }
        }
        var result: [String] = []
        var position = n
        var previousWasUnknown = false
        while position > 0 {
            let step = back[position]
            if let piece = step.piece {
                result.append(piece)
                previousWasUnknown = false
            } else if !previousWasUnknown {
                result.append("<unk>")
                previousWasUnknown = true
            }
            position = step.start
        }
        return result.reversed()
    }

    /// Token ids for the encoder, ending with `</s>`.
    func encode(_ text: String) -> [Int] {
        pieces(for: text).map { vocab[$0] ?? unkId } + [eosId]
    }

    func decode(_ ids: [Int]) -> String {
        let special: Set<Int> = [padId, eosId, unkId]
        let text = ids.filter { !special.contains($0) }.compactMap { idToPiece[$0] }.joined()
        return text.replacingOccurrences(of: "▁", with: " ").trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Translator

actor LocalNeuralTranslator {
    static let shared = LocalNeuralTranslator()

    enum TranslatorError: LocalizedError {
        case runtimeUnavailable
        case modelsMissing(TranslationDirection)
        case unexpectedOutput(String)

        var errorDescription: String? {
            switch self {
            case .runtimeUnavailable: return "ONNX Runtime is not linked into this build."
            case .modelsMissing(let direction): return "The \(direction.rawValue) translation model is not in the app bundle."
            case .unexpectedOutput(let detail): return "Unexpected translation model output: \(detail)"
            }
        }
    }

    /// Longest source segment in tokens; longer sentences are split at commas.
    static let maxSegmentTokens = 200
    static let cacheCapacity = 4096

    private struct Model {
        let tokenizer: SentencePieceUnigramTokenizer
        #if canImport(OnnxRuntimeBindings)
        let encoder: ORTSession
        let cross: ORTSession
        let step: ORTSession
        #endif
    }

    #if canImport(OnnxRuntimeBindings)
    private var env: ORTEnv?
    #endif
    private var models: [TranslationDirection: Model] = [:]
    private var cache: [String: String] = [:]
    private var cacheOrder: [String] = []

    static func resourceURL(_ name: String, _ ext: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext)
            ?? OpenIntelligenceResourceBundle.url(forResource: name, withExtension: ext)
    }

    nonisolated static func isAvailable(_ direction: TranslationDirection) -> Bool {
        #if canImport(OnnxRuntimeBindings)
        return resourceURL("\(direction.rawValue)_encoder", "onnx") != nil
            && resourceURL("\(direction.rawValue)_decoder_cross", "onnx") != nil
            && resourceURL("\(direction.rawValue)_decoder_step", "onnx") != nil
            && resourceURL("\(direction.rawValue)_tokenizer", "json") != nil
        #else
        return false
        #endif
    }

    private func model(_ direction: TranslationDirection) throws -> Model {
        if let model = models[direction] { return model }
        #if canImport(OnnxRuntimeBindings)
        guard let encoderURL = Self.resourceURL("\(direction.rawValue)_encoder", "onnx"),
              let crossURL = Self.resourceURL("\(direction.rawValue)_decoder_cross", "onnx"),
              let stepURL = Self.resourceURL("\(direction.rawValue)_decoder_step", "onnx"),
              let tokenizerURL = Self.resourceURL("\(direction.rawValue)_tokenizer", "json")
        else { throw TranslatorError.modelsMissing(direction) }
        let env = try self.env ?? ORTEnv(loggingLevel: .warning)
        self.env = env
        let options = try ORTSessionOptions()
        try options.setGraphOptimizationLevel(.all)
        try options.setIntraOpNumThreads(2)
        let model = Model(
            tokenizer: try SentencePieceUnigramTokenizer(jsonData: Data(contentsOf: tokenizerURL)),
            encoder: try ORTSession(env: env, modelPath: encoderURL.path, sessionOptions: options),
            cross: try ORTSession(env: env, modelPath: crossURL.path, sessionOptions: options),
            step: try ORTSession(env: env, modelPath: stepURL.path, sessionOptions: options)
        )
        models[direction] = model
        Log.info("[Translator] Loaded \(direction.rawValue)", category: .ingestion)
        return model
        #else
        throw TranslatorError.runtimeUnavailable
        #endif
    }

    // MARK: Plain translation

    /// Translates `text` line by line and sentence by sentence, keeping line breaks.
    func translate(_ text: String, direction: TranslationDirection) async throws -> String {
        var lines: [String] = []
        for line in Self.reflow(text).components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, trimmed.contains(where: \.isLetter) else {
                lines.append(line)
                continue
            }
            var translated: [String] = []
            for segment in Self.segments(trimmed) {
                translated.append(try translateSegment(segment, direction: direction))
            }
            lines.append(translated.joined(separator: " "))
        }
        return lines.joined(separator: "\n")
    }

    /// Whether a segment starts in mid-sentence: its first letter is lower-case.
    static func isSentenceFragment(_ segment: String) -> Bool {
        guard let first = segment.first(where: { $0.isLetter }) else { return false }
        return first.isLowercase && !segment.hasPrefix("__")
    }

    /// Rejoins lines a PDF wrapped in mid-sentence, so the model sees whole sentences: a fragment
    /// such as "προκλήσεις και προοπτικές" translated alone came back as an invented sentence about
    /// the European Commission. A line is joined to the next unless it ends a sentence (. ; ! ? :
    /// or the Greek question mark), is blank or a "[Part N]" label, or the next line is blank, a
    /// list item or a label.
    static func reflow(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        guard lines.count > 1 else { return text }
        func isBreak(_ line: String) -> Bool {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Blank lines, "[Part N]" labels, a line that is only a masked identifier (an article
            // heading such as "Άρθρο 1" once masked) and an article heading stay on their own.
            return trimmed.isEmpty || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]"))
                || trimmed.range(of: #"^(?:_+\s*)?LEX\s*_?\s*ENT\s*_?\s*\d{1,3}(?:\s*_+)?$"#, options: [.regularExpression, .caseInsensitive]) != nil
                || LegalCrossReferences.isArticleHeading(trimmed)
        }
        func startsItem(_ line: String) -> Bool {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.range(of: #"^(?:[-•*–]\s|\d{1,3}[.)]\s|\(?[α-ωa-z]\)\s)"#, options: .regularExpression) != nil
        }
        var output: [String] = []
        var current = ""
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if current.isEmpty {
                current = trimmed
            } else if isBreak(current) || isBreak(trimmed) || startsItem(trimmed)
                        || current.range(of: #"[.;;!?:·]["»)\]]?$"#, options: .regularExpression) != nil {
                output.append(current)
                current = trimmed
            } else {
                current += (current.hasSuffix("-") ? "" : " ") + trimmed
            }
            if trimmed.isEmpty {
                output.append(current)
                current = ""
            }
        }
        if !current.isEmpty { output.append(current) }
        return output.joined(separator: "\n")
    }

    /// Sentences of a line: split after ".", ";", "!", "?" (the Greek question mark is ";") when
    /// the next sentence starts with a capital, digit, quote, bracket or placeholder.
    static func segments(_ line: String) -> [String] {
        let pattern = #"(?<=[.;;!?])\s+(?=[\p{Lu}0-9"'(\[_])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [line] }
        let ns = line as NSString
        var result: [String] = []
        var cursor = 0
        for match in regex.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
            result.append(ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
            cursor = match.range.location + match.range.length
        }
        result.append(ns.substring(from: cursor))
        return result.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Whether a segment has no Greek to translate (placeholders aside): an English question with
    /// a Greek name in it ("Who is __LEX_ENT_001__") came out of the Greek model as nonsense.
    static func isWithoutGreek(_ segment: String) -> Bool {
        let unmasked = segment.replacingOccurrences(
            of: #"(?:_+\s*)?LEX\s*_?\s*ENT\s*_?\s*\d{1,3}(?:\s*_+)?"#, with: " ", options: [.regularExpression, .caseInsensitive])
        return GreekLegalEntityMasker.greekLetterRatio(unmasked) < 0.3
    }

    private func translateSegment(_ segment: String, direction: TranslationDirection) throws -> String {
        if direction == .greekToEnglish, Self.isWithoutGreek(segment) { return segment }
        let key = "\(direction.rawValue)\u{1}\(segment)"
        if let cached = cache[key] { return cached }
        let model = try model(direction)
        // A chunk can start in mid-sentence. Opus-MT, trained largely on EU proceedings, turns such
        // a fragment into an invented sentence ("The Commission has been able to…"); marked as a
        // continuation with "… " it translates the fragment, and the ellipsis is dropped again.
        let fragment = Self.isSentenceFragment(segment)
        var ids = model.tokenizer.encode(fragment ? "… " + segment : segment)
        var output: String
        if ids.count > Self.maxSegmentTokens, segment.contains(", ") {
            // A very long sentence: translate its comma-separated parts.
            output = try segment.components(separatedBy: ", ")
                .map { try translateSegment($0, direction: direction) }
                .joined(separator: ", ")
        } else {
            if ids.count > Self.maxSegmentTokens {
                ids = Array(ids.prefix(Self.maxSegmentTokens - 1)) + [model.tokenizer.eosId]
            }
            output = model.tokenizer.decode(try generate(ids: ids, model: model))
            if fragment {
                output = output.replacingOccurrences(of: #"^\s*(?:\.\.\.|…)\s*"#, with: "", options: .regularExpression)
            }
            output = Self.restoreCitationMarkers(source: segment, translation: output)
        }
        cache[key] = output
        cacheOrder.append(key)
        if cacheOrder.count > Self.cacheCapacity {
            cache.removeValue(forKey: cacheOrder.removeFirst())
        }
        return output
    }

    /// `[C1]`-style citation markers the model dropped are appended to the translated sentence.
    static func restoreCitationMarkers(source: String, translation: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\[C\d+\]"#) else { return translation }
        let ns = source as NSString
        var output = translation
        for match in regex.matches(in: source, range: NSRange(location: 0, length: ns.length)) {
            let marker = ns.substring(with: match.range)
            if !output.contains(marker) {
                output = output.trimmingCharacters(in: .whitespaces) + " " + marker
            }
        }
        return output
    }

    private func generate(ids: [Int], model: Model) throws -> [Int] {
        #if canImport(OnnxRuntimeBindings)
        let inputIds = try Self.int64Tensor(ids)
        let mask = try Self.int64Tensor([Int](repeating: 1, count: ids.count))
        let encoded = try model.encoder.run(
            withInputs: ["input_ids": inputIds, "attention_mask": mask],
            outputNames: ["last_hidden_state"], runOptions: nil
        )
        guard let hidden = encoded["last_hidden_state"] else { throw TranslatorError.unexpectedOutput("encoder") }

        // Cross-attention keys and values, once per sentence; the step graph reads them by name.
        let tokenizer = model.tokenizer
        let layers = 0..<tokenizer.decoderLayers
        let crossNames = layers.flatMap { ["cross_key_\($0)", "cross_value_\($0)"] }
        let cross = try model.cross.run(
            withInputs: ["encoder_hidden_states": hidden], outputNames: Set(crossNames), runOptions: nil)
        // The self-attention cache starts empty: [1, heads, 0, headDim] per layer.
        let pastNames = layers.flatMap { ["past_key_\($0)", "past_value_\($0)"] }
        let presentNames = layers.flatMap { ["present_key_\($0)", "present_value_\($0)"] }
        var past: [String: ORTValue] = [:]
        for name in pastNames {
            past[name] = try Self.emptyCacheTensor(heads: tokenizer.attentionHeads, headDim: tokenizer.headDim)
        }

        var output = [tokenizer.decoderStartId]
        let maxNew = min(512, ids.count * 2 + 10)
        for _ in 0..<maxNew {
            var inputs = cross.merging(past) { first, _ in first }
            inputs["decoder_input_ids"] = try Self.int64Tensor([output[output.count - 1]])
            let result = try model.step.run(
                withInputs: inputs, outputNames: Set(["logits"] + presentNames), runOptions: nil)
            for (index, name) in presentNames.enumerated() {
                guard let value = result[name] else { throw TranslatorError.unexpectedOutput("decoder step \(name)") }
                past[pastNames[index]] = value
            }
            guard let logitsValue = result["logits"] else { throw TranslatorError.unexpectedOutput("decoder step logits") }
            let data = try logitsValue.tensorData() as Data
            let next: Int = data.withUnsafeBytes { raw in
                let logits = raw.bindMemory(to: Float.self)
                var best = 0
                var bestValue = -Float.infinity
                for (index, value) in logits.enumerated() where index != model.tokenizer.padId && value > bestValue {
                    best = index
                    bestValue = value
                }
                return best
            }
            output.append(next)
            if next == model.tokenizer.eosId { break }
        }
        return Array(output.dropFirst())
        #else
        throw TranslatorError.runtimeUnavailable
        #endif
    }

    #if canImport(OnnxRuntimeBindings)
    /// A [1, heads, 0, headDim] float tensor: the key/value cache before the first token. The data
    /// buffer is a few bytes rather than none, as ONNX Runtime wants a buffer at least as large as
    /// the shape needs (zero here) and a non-null one.
    private static func emptyCacheTensor(heads: Int, headDim: Int) throws -> ORTValue {
        try ORTValue(
            tensorData: NSMutableData(bytes: [Float(0)], length: MemoryLayout<Float>.size), elementType: .float,
            shape: [1, NSNumber(value: heads), 0, NSNumber(value: headDim)])
    }

    private static func int64Tensor(_ values: [Int]) throws -> ORTValue {
        let int64 = values.map(Int64.init)
        let data = int64.withUnsafeBufferPointer { NSMutableData(bytes: $0.baseAddress, length: $0.count * MemoryLayout<Int64>.size) }
        return try ORTValue(tensorData: data, elementType: .int64, shape: [1, NSNumber(value: values.count)])
    }
    #endif

    // MARK: Entity-preserving translation

    /// Stage 4: mask the legal identifiers, translate el→en, put the identifiers back as bilingual
    /// anchors ("Article 38 [Άρθρο 38]").
    func translateGreekToEnglishPreservingLegalEntities(_ textEl: String) async throws -> (textEn: String, entities: [LegalEntityRecord]) {
        let (masked, entities) = GreekLegalEntityMasker.maskEntities(in: textEl)
        // Names: in Greek text the model translates them in context (a pair of capitalized words is
        // as often "Κοινοβουλευτική Δημοκρατία" as a person), and their ELOT 743 transliteration is
        // added after the text so the document and a question share one spelling ("Andreas
        // Zervas"). In a text that is not Greek apart from the names ("Who is Ανδρέας Ζέρβας") the
        // names stay masked, since the Greek model turns such a text into nonsense.
        let names = entities.filter { $0.type == .properName }
        var toTranslate = masked
        var keptMasked = entities
        var appendedNames: [LegalEntityRecord] = []
        if !names.isEmpty, !Self.isWithoutGreek(masked) {
            toTranslate = GreekLegalEntityMasker.unmaskEntities(in: masked, entities: names, mode: .greekVerbatim)
            keptMasked = entities.filter { $0.type != .properName }
            var seen = Set<String>()
            appendedNames = names.filter { seen.insert($0.canonicalKey).inserted }
        }
        let translated = try await translate(toTranslate, direction: .greekToEnglish)
        var restored = GreekLegalEntityMasker.unmaskEntities(in: translated, entities: keptMasked, mode: .bilingualAnchor)
        if !appendedNames.isEmpty {
            restored += "\n(" + appendedNames.prefix(5).map(\.bilingualAnchor).joined(separator: "; ") + ")"
        }
        return (restored, entities)
    }

    /// Phase F: translate a verified English answer to Greek. Bilingual anchors collapse to one
    /// identifier, identifiers and `[C#]` markers are kept out of the model, and identifiers come
    /// back in Greek (the source wording when `entities` has the same key).
    /// The text without markdown emphasis and heading marks: "**two (2)** months" → "two (2)
    /// months", "### Title" → "Title". List dashes and citation brackets stay.
    nonisolated static func withoutMarkdown(_ text: String) -> String {
        var s = text.replacingOccurrences(of: #"(?m)^\s{0,3}#{1,6}\s*"#, with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: "")
        s = s.replacingOccurrences(of: #"(?<![\w*])\*(?=\S)([^*\n]+?)(?<=\S)\*(?![\w*])"#, with: "$1", options: .regularExpression)
        return s
    }

    func translateEnglishToGreekPreservingCitations(_ textEn: String, entities: [LegalEntityRecord] = []) async throws -> String {
        // Numbers in words go to Greek as digits ("three hundred" came back "τρία εκατοντάδες"), and
        // the answer goes as plain text: the translator returned "**δώδεκα (12)** μήνες",
        // "8 (****) εβδομάδες" and "# #" headings from the draft's markdown (labour run 1).
        let collapsed = SpelledNumber.digitsForEnglishNumberWords(
            Self.withoutMarkdown(GreekLegalEntityMasker.collapseBilingualAnchors(textEn)))
        let (maskedWithTerms, allFound) = GreekLegalEntityMasker.maskEntities(in: collapsed)
        // Glossary terms go through the model in English: put back as written, the Greek keeps its
        // grammar ("για τα κακουργήματα"), which a restored lemma would not.
        let terms = allFound.filter { $0.type == .legalTerm }
        let masked = GreekLegalEntityMasker.unmaskEntities(in: maskedWithTerms, entities: terms, mode: .verbatim)
        let found = allFound.filter { $0.type != .legalTerm }
        var greekByKey: [String: String] = [:]
        for entity in entities where GreekLegalEntityMasker.containsGreek(entity.verbatimEl) {
            greekByKey[entity.canonicalKey] = greekByKey[entity.canonicalKey] ?? entity.verbatimEl
        }
        let resolved = found.map { entity -> LegalEntityRecord in
            guard let greek = greekByKey[entity.canonicalKey] else { return entity }
            return LegalEntityRecord(
                id: entity.id, type: entity.type, verbatimEl: greek,
                canonicalEn: entity.canonicalEn, canonicalEl: entity.canonicalEl, canonicalKey: entity.canonicalKey
            )
        }
        let translated = try await translate(masked, direction: .englishToGreek)
        let greek = GreekLegalEntityMasker.unmaskEntities(in: translated, entities: resolved, mode: .greekVerbatim)
        return await restoringGlossaryGreek(greek, terms: terms)
    }

    /// The model's renderings of glossary terms, by English term ("serious reason" → «σοβαρός λόγος»).
    private var termRenderings: [String: String] = [:]

    /// The Greek answer with each glossary term in the glossary's own words. A term goes through
    /// the model in English and comes back in whatever words the model knows («σοβαρός λόγος»
    /// where the Labour Code says «σπουδαίος λόγος», labour test case 42): when the glossary's
    /// Greek isn't in the answer, the model's rendering of the term alone is looked for, and each
    /// of its words gets the glossary word's stem with the ending the sentence gave it.
    func restoringGlossaryGreek(_ greek: String, terms: [LegalEntityRecord]) async -> String {
        var result = greek
        var seen = Set<String>()
        for term in terms where seen.insert(term.canonicalKey).inserted {
            if GreekLegalEntityMasker.extractEntities(from: result).contains(where: { $0.canonicalKey == term.canonicalKey && GreekLegalEntityMasker.containsGreek($0.verbatimEl) }) {
                continue
            }
            let rendering: String
            if let cached = termRenderings[term.canonicalEn] {
                rendering = cached
            } else {
                guard let fresh = try? await translate(term.canonicalEn, direction: .englishToGreek) else { continue }
                rendering = fresh.trimmingCharacters(in: CharacterSet.letters.inverted)
                termRenderings[term.canonicalEn] = rendering
            }
            result = Self.replacingRendering(rendering, with: term.canonicalEl, in: result)
        }
        return result
    }

    /// Greek noun and adjective endings, longest first.
    private static let greekEnding = #"(?:ους|ούς|εις|είς|εων|έων|ος|ός|ου|ού|οι|οί|ων|ών|ας|άς|ης|ής|ες|ές|α|ά|η|ή|ο|ό|ε|έ)$"#

    /// Every occurrence of `rendering` (word for word, any endings, any accents on the stems) in
    /// `text` replaced by `lemma`'s words with the endings found; unchanged when the two phrases
    /// have different word counts.
    nonisolated static func replacingRendering(_ rendering: String, with lemma: String, in text: String) -> String {
        let renderingWords = rendering.split(separator: " ").map(String.init)
        let lemmaWords = lemma.split(separator: " ").map(String.init)
        guard !renderingWords.isEmpty, renderingWords.count == lemmaWords.count,
              rendering.lowercased() != lemma.lowercased() else { return text }
        func stem(_ word: String) -> String {
            word.range(of: greekEnding, options: .regularExpression).map { String(word[..<$0.lowerBound]) } ?? word
        }
        let accents: [Character: String] = ["α": "αά", "ε": "εέ", "η": "ηή", "ι": "ιίϊΐ", "ο": "οό", "υ": "υύϋΰ", "ω": "ωώ"]
        let pattern = renderingWords.map { word -> String in
            let folded = stem(word).lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "el"))
            let stemPattern = folded.map { char in accents[char].map { "[\($0)\($0.uppercased())]" } ?? "[\(char)\(String(char).uppercased())]" }.joined()
            return "(\(stemPattern))(\\p{L}{0,4})"
        }.joined(separator: "\\s+")
        guard let regex = try? NSRegularExpression(pattern: "(?<!\\p{L})" + pattern + "(?!\\p{L})") else { return text }
        let ns = text as NSString
        var output = ""
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            output += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            var words: [String] = []
            for (index, lemmaWord) in lemmaWords.enumerated() {
                let found = ns.substring(with: match.range(at: index * 2 + 1))
                var ending = ns.substring(with: match.range(at: index * 2 + 2))
                let lemmaStem = stem(lemmaWord)
                // One accent per word: the glossary word's own when its stem has it.
                if lemmaStem.folding(options: .diacriticInsensitive, locale: nil) != lemmaStem {
                    ending = ending.folding(options: .diacriticInsensitive, locale: nil)
                }
                var word = lemmaStem + ending
                if found.first?.isUppercase == true { word = word.prefix(1).uppercased() + word.dropFirst() }
                words.append(word)
            }
            output += words.joined(separator: " ")
            cursor = match.range.location + match.range.length
        }
        output += ns.substring(from: cursor)
        return output
    }
}
