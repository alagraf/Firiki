//
//  LocalNeuralTranslator.swift
//  OpenIntelligence
//
//  Thesis fork, plan stages 4b and F: on-device Greek↔English translation. Apple's Translation
//  framework has no Greek, so text is translated by Helsinki-NLP's Opus-MT Marian models
//  (`opus-mt-grk-en`, `opus-mt-en-el`, CC-BY 4.0 / Apache-2.0), exported to ONNX as an encoder and a
//  decoder-with-LM-head and quantized to INT8 (`scripts/thesis_fetch_translation_models.sh`), run
//  with ONNX Runtime. Nothing leaves the device.
//
//  Tokenization is SentencePiece unigram (Viterbi over the source model's pieces and scores), ids
//  from Marian's shared vocabulary; decoding is greedy, one decoder pass per output token (no
//  key/value cache: simpler, and sentence-length inputs keep it fast enough for ingestion).
//
//  Legal identifiers never go through the model: `GreekLegalEntityMasker` replaces them with
//  placeholders first and restores them afterwards.
//

import Foundation
#if canImport(OnnxRuntimeBindings)
import OnnxRuntimeBindings
#endif

nonisolated enum TranslationDirection: String, Sendable, CaseIterable {
    case greekToEnglish = "opus-mt-grk-en"
    case englishToGreek = "opus-mt-en-el"
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
    private let unknownScore: Float

    private struct File: Decodable {
        struct Meta: Decodable {
            let pad_id: Int
            let eos_id: Int
            let unk_id: Int?
            let decoder_start_token_id: Int
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
        let decoder: ORTSession
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
            && resourceURL("\(direction.rawValue)_decoder", "onnx") != nil
            && resourceURL("\(direction.rawValue)_tokenizer", "json") != nil
        #else
        return false
        #endif
    }

    private func model(_ direction: TranslationDirection) throws -> Model {
        if let model = models[direction] { return model }
        #if canImport(OnnxRuntimeBindings)
        guard let encoderURL = Self.resourceURL("\(direction.rawValue)_encoder", "onnx"),
              let decoderURL = Self.resourceURL("\(direction.rawValue)_decoder", "onnx"),
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
            decoder: try ORTSession(env: env, modelPath: decoderURL.path, sessionOptions: options)
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
        for line in text.components(separatedBy: "\n") {
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

    private func translateSegment(_ segment: String, direction: TranslationDirection) throws -> String {
        let key = "\(direction.rawValue)\u{1}\(segment)"
        if let cached = cache[key] { return cached }
        let model = try model(direction)
        var ids = model.tokenizer.encode(segment)
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
        var output = [model.tokenizer.decoderStartId]
        let maxNew = min(512, ids.count * 2 + 10)
        for _ in 0..<maxNew {
            let logitsValue = try model.decoder.run(
                withInputs: [
                    "decoder_input_ids": try Self.int64Tensor(output),
                    "encoder_hidden_states": hidden,
                    "encoder_attention_mask": mask,
                ],
                outputNames: ["logits"], runOptions: nil
            )["logits"]
            guard let logitsValue else { throw TranslatorError.unexpectedOutput("decoder") }
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
        let translated = try await translate(masked, direction: .greekToEnglish)
        let restored = GreekLegalEntityMasker.unmaskEntities(in: translated, entities: entities, mode: .bilingualAnchor)
        return (restored, entities)
    }

    /// Phase F: translate a verified English answer to Greek. Bilingual anchors collapse to one
    /// identifier, identifiers and `[C#]` markers are kept out of the model, and identifiers come
    /// back in Greek (the source wording when `entities` has the same key).
    func translateEnglishToGreekPreservingCitations(_ textEn: String, entities: [LegalEntityRecord] = []) async throws -> String {
        let collapsed = GreekLegalEntityMasker.collapseBilingualAnchors(textEn)
        let (masked, found) = GreekLegalEntityMasker.maskEntities(in: collapsed)
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
        return GreekLegalEntityMasker.unmaskEntities(in: translated, entities: resolved, mode: .greekVerbatim)
    }
}
