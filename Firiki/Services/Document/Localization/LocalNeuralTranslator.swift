//
//  LocalNeuralTranslator.swift
//  Firiki
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
//  The next token is picked with Accelerate: a Swift loop over the 58,829-word vocabulary was most
//  of the import time in Debug builds (Labour Code excerpt 307 s, now 131 s in the Simulator).
//  Models exported with a batch axis (`scripts/thesis/convert_opus_mt_batched.py`, an experiment)
//  can decode the sentences of many chunks together (`pretranslateGreekChunks`); the app ships the
//  one-sentence models, for which that is a no-op: the INT8 activations are quantized per batch,
//  so a batch rewords about a third of its sentences and the evaluations dropped, and the batched
//  step graph ran 2.7x slower at batch 1. Only one direction's sessions (about 360 MB) stay loaded,
//  and none after an import or a memory warning.
//
//  Legal identifiers never go through the model: `GreekLegalEntityMasker` replaces them with
//  placeholders first and restores them afterwards.
//

import Accelerate
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
        /// The step graph takes `encoder_attention_mask`, i.e. batches of sentences (models exported
        /// before batching take one sentence at a time).
        let batched: Bool
    }

    /// Sentences decoded together at import: one, since batches change the translations (see the
    /// file comment). Kept as a setting for a device test, where batches may pay off.
    static let importBatchSize = 1
    /// Batch translation since the last release: sentences, seconds, seconds inside ONNX Runtime.
    private var batchStats: (sentences: Int, seconds: Double, modelSeconds: Double) = (0, 0, 0)
    private var modelSeconds = 0.0
    /// `translate` calls since the last release, for the Xcode console: calls, segments, segments
    /// answered from the cache, segments decoded by the model, wall-clock seconds. Until 2026-10-31
    /// the translator printed only when a model loaded or was released, so a question's or an
    /// answer's translation left no line in the console (owner, 2026-10-31).
    private var callStats: (calls: Int, segments: Int, cached: Int, decoded: Int, seconds: Double) = (0, 0, 0, 0, 0)

    /// The short name of a direction in log lines.
    nonisolated static func logName(_ direction: TranslationDirection) -> String {
        direction == .greekToEnglish ? "el→en" : "en→el"
    }

    /// A one-line preview of a text for the console.
    nonisolated static func logPreview(_ text: String, limit: Int = 80) -> String {
        let line = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return line.count > limit ? String(line.prefix(limit)) + "…" : line
    }

    /// Forgets every translated sentence (benchmarks).
    func clearCache() {
        cache.removeAll()
        cacheOrder.removeAll()
    }
    /// ONNX Runtime threads per session: one sentence at a time ran as fast with 4 threads as with 2.
    static let threadCount = 2

    #if canImport(OnnxRuntimeBindings)
    private var env: ORTEnv?
    #endif
    private var models: [TranslationDirection: Model] = [:]
    private var cache: [String: String] = [:]
    private var cacheOrder: [String] = []

    static func resourceURL(_ name: String, _ ext: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext)
            ?? FirikiResourceBundle.url(forResource: name, withExtension: ext)
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

    /// Releases the translation sessions (about 360 MB per direction); the next translation loads
    /// them again (about 0.3 s per direction on an M3). Called after an import and on a memory
    /// warning.
    func releaseModels() {
        if batchStats.sentences > 0 {
            Log.info(String(format: "[Translator] Batch-translated %d sentences in %.1f s (ONNX Runtime %.1f s)",
                            batchStats.sentences, batchStats.seconds, batchStats.modelSeconds), category: .ingestion)
            batchStats = (0, 0, 0)
        }
        if callStats.calls > 0 {
            Log.info(String(format: "[Opus-MT] Since the last release: %d translation(s), %d segment(s) (%d from the cache, %d decoded) in %.1f s",
                            callStats.calls, callStats.segments, callStats.cached, callStats.decoded, callStats.seconds), category: .ingestion)
            callStats = (0, 0, 0, 0, 0)
        }
        guard !models.isEmpty else { return }
        models.removeAll()
        Log.info("[Translator] Released translation models", category: .ingestion)
    }

    /// Whether the installed models of `direction` translate batches (exported with
    /// `encoder_attention_mask`).
    func takesBatches(_ direction: TranslationDirection) throws -> Bool {
        try model(direction).batched
    }

    private func model(_ direction: TranslationDirection) throws -> Model {
        if let model = models[direction] { return model }
        // One direction at a time: a question loads el→en, its answer en→el.
        models.removeAll()
        #if canImport(OnnxRuntimeBindings)
        guard let encoderURL = Self.resourceURL("\(direction.rawValue)_encoder", "onnx"),
              let crossURL = Self.resourceURL("\(direction.rawValue)_decoder_cross", "onnx"),
              let stepURL = Self.resourceURL("\(direction.rawValue)_decoder_step", "onnx"),
              let tokenizerURL = Self.resourceURL("\(direction.rawValue)_tokenizer", "json")
        else {
            Log.error("[Opus-MT] \(direction.rawValue) model files are missing from the app bundle", category: .ingestion)
            throw TranslatorError.modelsMissing(direction)
        }
        let loadStart = Date()
        // ONNX Runtime's own log stays at warning: at info it prints every graph optimisation pass.
        let env = try self.env ?? ORTEnv(loggingLevel: .warning)
        self.env = env
        let options = try ORTSessionOptions()
        try options.setGraphOptimizationLevel(.all)
        try options.setIntraOpNumThreads(Int32(Self.threadCount))
        let step = try ORTSession(env: env, modelPath: stepURL.path, sessionOptions: options)
        let model = Model(
            tokenizer: try SentencePieceUnigramTokenizer(jsonData: Data(contentsOf: tokenizerURL)),
            encoder: try ORTSession(env: env, modelPath: encoderURL.path, sessionOptions: options),
            cross: try ORTSession(env: env, modelPath: crossURL.path, sessionOptions: options),
            step: step,
            batched: (try? step.inputNames())?.contains("encoder_attention_mask") ?? false
        )
        models[direction] = model
        Log.info(String(format: "[Translator] Loaded %@ (%@) in %.2f s, %d ONNX Runtime thread(s), %@",
                        direction.rawValue, Self.logName(direction), Date().timeIntervalSince(loadStart), Self.threadCount,
                        model.batched ? "batched step graph" : "one sentence at a time"), category: .ingestion)
        return model
        #else
        throw TranslatorError.runtimeUnavailable
        #endif
    }

    // MARK: Plain translation

    /// Translates `text` line by line and sentence by sentence, keeping line breaks.
    /// The segments `translate` sends to the model, in order.
    static func translatableSegments(_ text: String) -> [String] {
        reflow(text).components(separatedBy: "\n").flatMap { line -> [String] in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, trimmed.contains(where: \.isLetter) else { return [] }
            return segments(trimmed)
        }
    }

    func translate(_ text: String, direction: TranslationDirection) async throws -> String {
        let started = Date()
        let before = (cached: callStats.cached, decoded: callStats.decoded)
        var segmentCount = 0
        var lines: [String] = []
        for line in Self.reflow(text).components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, trimmed.contains(where: \.isLetter) else {
                lines.append(line)
                continue
            }
            var translated: [String] = []
            for segment in Self.segments(trimmed) {
                segmentCount += 1
                translated.append(try translateSegment(segment, direction: direction))
            }
            lines.append(translated.joined(separator: " "))
        }
        let output = lines.joined(separator: "\n")
        let seconds = Date().timeIntervalSince(started)
        let cached = callStats.cached - before.cached
        let decoded = callStats.decoded - before.decoded
        callStats.calls += 1
        callStats.segments += segmentCount
        callStats.seconds += seconds
        // One line per call that ran the model; calls answered from the cache alone (most of an
        // import after `pretranslateGreekChunks`) are only counted, so an import doesn't print
        // thousands of lines. Debug level: printed in Debug builds, never in Release.
        if decoded > 0 {
            Log.debug(String(format: "[Opus-MT] %@ %d chars, %d segment(s) (%d decoded, %d cached) in %.0f ms: '%@' → '%@'",
                             Self.logName(direction), text.count, segmentCount, decoded, cached, seconds * 1000,
                             Self.logPreview(text), Self.logPreview(output)), category: .ingestion)
        }
        return output
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
    /// list item or a label. The rows of a table (`GreekLegalStructureChunker.tableLineIndices`)
    /// keep their own lines, so each row is translated on its own.
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
        let table = GreekLegalStructureChunker.tableLineIndices(lines)
        var output: [String] = []
        var current = ""
        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if current.isEmpty {
                current = trimmed
            } else if isBreak(current) || isBreak(trimmed) || startsItem(trimmed)
                        || table.contains(index) || table.contains(index - 1)
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

    private static func cacheKey(_ segment: String, _ direction: TranslationDirection) -> String {
        "\(direction.rawValue)\u{1}\(segment)"
    }

    /// Splits a segment that exceeds the token budget into sub-segments along punctuation or word boundaries.
    private static func splitLongSegment(_ segment: String) -> [String] {
        if segment.contains(", ") {
            return segment.components(separatedBy: ", ")
        }
        if segment.contains("; ") {
            return segment.components(separatedBy: "; ")
        }
        if segment.contains("· ") {
            return segment.components(separatedBy: "· ")
        }
        if segment.contains(": ") {
            return segment.components(separatedBy: ": ")
        }
        let words = segment.components(separatedBy: " ")
        if words.count > 1 {
            let mid = words.count / 2
            let left = words.prefix(mid).joined(separator: " ")
            let right = words.dropFirst(mid).joined(separator: " ")
            return [left, right].filter { !$0.isEmpty }
        }
        return [segment]
    }

    /// The model input of a segment, or nil for a very long sentence, which is translated as its
    /// split parts.
    private static func modelInput(_ segment: String, tokenizer: SentencePieceUnigramTokenizer) -> [Int]? {
        // A chunk can start in mid-sentence. Opus-MT, trained largely on EU proceedings, turns such
        // a fragment into an invented sentence ("The Commission has been able to…"); marked as a
        // continuation with "… " it translates the fragment, and the ellipsis is dropped again.
        let ids = tokenizer.encode(isSentenceFragment(segment) ? "… " + segment : segment)
        guard ids.count > maxSegmentTokens else { return ids }
        let parts = splitLongSegment(segment)
        if parts.count > 1 { return nil }
        Log.warning("[Opus-MT] An unsplittable segment of \(ids.count) tokens exceeds \(maxSegmentTokens); cut to \(maxSegmentTokens - 1) tokens: '\(logPreview(segment))'", category: .ingestion)
        return Array(ids.prefix(maxSegmentTokens - 1)) + [tokenizer.eosId]
    }

    private static func finished(_ segment: String, tokens: [Int], tokenizer: SentencePieceUnigramTokenizer) -> String {
        var output = tokenizer.decode(tokens)
        if isSentenceFragment(segment) {
            output = output.replacingOccurrences(of: #"^\s*(?:\.\.\.|…)\s*"#, with: "", options: .regularExpression)
        }
        return restoreCitationMarkers(source: segment, translation: output)
    }

    private func store(_ output: String, key: String) {
        cache[key] = output
        cacheOrder.append(key)
        if cacheOrder.count > Self.cacheCapacity {
            cache.removeValue(forKey: cacheOrder.removeFirst())
        }
    }

    private func translateSegment(_ segment: String, direction: TranslationDirection) throws -> String {
        if direction == .greekToEnglish, Self.isWithoutGreek(segment) { return segment }
        let key = Self.cacheKey(segment, direction)
        if let cached = cache[key] {
            callStats.cached += 1
            return cached
        }
        let model = try model(direction)
        let output: String
        if let ids = Self.modelInput(segment, tokenizer: model.tokenizer) {
            callStats.decoded += 1
            output = Self.finished(segment, tokens: try generate(batch: [ids], model: model)[0], tokenizer: model.tokenizer)
        } else {
            // A very long sentence: translate its parts.
            let parts = Self.splitLongSegment(segment)
            let sep = segment.contains(", ") ? ", " : (segment.contains("; ") ? "; " : (segment.contains("· ") ? "· " : (segment.contains(": ") ? ": " : " ")))
            output = try parts
                .map { try translateSegment($0, direction: direction) }
                .joined(separator: sep)
        }
        store(output, key: key)
        return output
    }

    /// Import: translates the Greek sentences of `texts` (chunks as `translateGreekToEnglish…`
    /// receives them) in batches into the cache, so the per-chunk calls that follow only assemble
    /// them. Does nothing with models that take one sentence at a time.
    func pretranslateGreekChunks(_ texts: [String], batchSize: Int = importBatchSize) {
        guard let model = try? model(.greekToEnglish), model.batched else { return }
        let started = Date()
        modelSeconds = 0
        var pending: [(segment: String, ids: [Int])] = []
        var seen = Set<String>()
        func collect(_ segment: String) {
            guard !Self.isWithoutGreek(segment), cache[Self.cacheKey(segment, .greekToEnglish)] == nil,
                  seen.insert(segment).inserted else { return }
            if let ids = Self.modelInput(segment, tokenizer: model.tokenizer) {
                pending.append((segment, ids))
            } else {
                Self.splitLongSegment(segment).forEach(collect)
            }
        }
        for text in texts {
            Self.translatableSegments(Self.greekInput(text).text).forEach(collect)
        }
        // Stable by length, so batches pad little and follow the text.
        let ordered = pending.enumerated().sorted { ($0.element.ids.count, $0.offset) < ($1.element.ids.count, $1.offset) }.map(\.element)
        var start = 0
        while start < ordered.count {
            let batch = Array(ordered[start..<min(start + max(1, batchSize), ordered.count)])
            start += batch.count
            do {
                let tokens = try generate(batch: batch.map(\.ids), model: model)
                for (item, output) in zip(batch, tokens) {
                    store(Self.finished(item.segment, tokens: output, tokenizer: model.tokenizer),
                          key: Self.cacheKey(item.segment, .greekToEnglish))
                }
            } catch {
                // The per-chunk calls translate these one at a time.
                Log.warning("[Translator] Batch translation failed: \(error.localizedDescription)", category: .ingestion)
            }
        }
        batchStats.sentences += ordered.count
        batchStats.seconds += Date().timeIntervalSince(started)
        batchStats.modelSeconds += modelSeconds
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

    /// Greedy decoding of each sentence of `batch` (one sentence unless `model.batched`); shorter
    /// sentences are padded, and the encoder mask keeps attention off the padding.
    private func generate(batch: [[Int]], model: Model) throws -> [[Int]] {
        #if canImport(OnnxRuntimeBindings)
        let tokenizer = model.tokenizer
        let rows = batch.count
        let width = batch.map(\.count).max() ?? 0
        var flatIds: [Int] = []
        var flatMask: [Int] = []
        for ids in batch {
            flatIds += ids + [Int](repeating: tokenizer.padId, count: width - ids.count)
            flatMask += [Int](repeating: 1, count: ids.count) + [Int](repeating: 0, count: width - ids.count)
        }
        let inputIds = try Self.int64Tensor(flatIds, shape: [rows, width])
        let mask = try Self.int64Tensor(flatMask, shape: [rows, width])
        // Time inside ONNX Runtime: the whole decoding less the Swift work after each step.
        let modelStart = Date()
        var swiftSeconds = 0.0
        defer { modelSeconds += Date().timeIntervalSince(modelStart) - swiftSeconds }
        let encoded = try model.encoder.run(
            withInputs: ["input_ids": inputIds, "attention_mask": mask],
            outputNames: ["last_hidden_state"], runOptions: nil
        )
        guard let hidden = encoded["last_hidden_state"] else { throw TranslatorError.unexpectedOutput("encoder") }

        // Cross-attention keys and values, once per sentence; the step graph reads them by name.
        let layers = 0..<tokenizer.decoderLayers
        let crossNames = layers.flatMap { ["cross_key_\($0)", "cross_value_\($0)"] }
        let cross = try model.cross.run(
            withInputs: ["encoder_hidden_states": hidden], outputNames: Set(crossNames), runOptions: nil)
        // The self-attention cache starts empty: [rows, heads, 0, headDim] per layer.
        let pastNames = layers.flatMap { ["past_key_\($0)", "past_value_\($0)"] }
        let presentNames = layers.flatMap { ["present_key_\($0)", "present_value_\($0)"] }
        var past: [String: ORTValue] = [:]
        for name in pastNames {
            past[name] = try Self.emptyCacheTensor(rows: rows, heads: tokenizer.attentionHeads, headDim: tokenizer.headDim)
        }

        var outputs = [[Int]](repeating: [], count: rows)
        let limits = batch.map { min(512, $0.count * 2 + 10) }
        var done = [Bool](repeating: false, count: rows)
        // The batch's rows. Finished sentences stay in the batch, fed padding: taking them out
        // changes the INT8 activation scales the other sentences are decoded with (a sentence of
        // the masker test then ended after half its words), so batches are kept to sentences of
        // about the same length instead (`pretranslateGreekChunks` sorts by length).
        let active = Array(0..<rows)
        var last = [Int](repeating: tokenizer.decoderStartId, count: rows)
        for step in 0..<(limits.max() ?? 0) {
            var inputs = cross.merging(past) { first, _ in first }
            inputs["decoder_input_ids"] = try Self.int64Tensor(active.map { last[$0] }, shape: [active.count, 1])
            if model.batched { inputs["encoder_attention_mask"] = mask }
            let result = try model.step.run(
                withInputs: inputs, outputNames: Set(["logits"] + presentNames), runOptions: nil)
            let swiftStart = Date()
            defer { swiftSeconds += Date().timeIntervalSince(swiftStart) }
            for (index, name) in presentNames.enumerated() {
                guard let value = result[name] else { throw TranslatorError.unexpectedOutput("decoder step \(name)") }
                past[pastNames[index]] = value
            }
            guard let logitsValue = result["logits"] else { throw TranslatorError.unexpectedOutput("decoder step logits") }
            // The best token of each row, never padding (vDSP_maxvi takes the first of equal maxima,
            // as the loop it replaced did).
            let logits = try logitsValue.tensorData()
            let vocabulary = logits.length / MemoryLayout<Float>.size / active.count
            let scores = logits.mutableBytes.assumingMemoryBound(to: Float.self)
            for (position, row) in active.enumerated() where !done[row] {
                let rowScores = scores + position * vocabulary
                rowScores[tokenizer.padId] = -.infinity
                var best: Float = 0
                var index: vDSP_Length = 0
                vDSP_maxvi(rowScores, 1, &best, &index, vDSP_Length(vocabulary))
                outputs[row].append(Int(index))
                last[row] = Int(index)
                done[row] = Int(index) == tokenizer.eosId || step + 1 >= limits[row]
            }
            // A finished sentence is fed padding until it leaves the batch; its output is complete.
            for row in active where done[row] { last[row] = tokenizer.padId }
            if !done.contains(false) { break }
        }
        return outputs
        #else
        throw TranslatorError.runtimeUnavailable
        #endif
    }

    #if canImport(OnnxRuntimeBindings)
    /// A [rows, heads, 0, headDim] float tensor: the key/value cache before the first token. The
    /// data buffer is a few bytes rather than none, as ONNX Runtime wants a buffer at least as large
    /// as the shape needs (zero here) and a non-null one.
    private static func emptyCacheTensor(rows: Int, heads: Int, headDim: Int) throws -> ORTValue {
        try ORTValue(
            tensorData: NSMutableData(bytes: [Float(0)], length: MemoryLayout<Float>.size), elementType: .float,
            shape: [NSNumber(value: rows), NSNumber(value: heads), 0, NSNumber(value: headDim)])
    }

    private static func int64Tensor(_ values: [Int], shape: [Int]) throws -> ORTValue {
        let int64 = values.map(Int64.init)
        let data = int64.withUnsafeBufferPointer { NSMutableData(bytes: $0.baseAddress, length: $0.count * MemoryLayout<Int64>.size) }
        return try ORTValue(tensorData: data, elementType: .int64, shape: shape.map { NSNumber(value: $0) })
    }
    #endif

    // MARK: Entity-preserving translation

    /// Stage 4: mask the legal identifiers, translate el→en, put the identifiers back as bilingual
    /// anchors ("Article 38 [Άρθρο 38]").
    func translateGreekToEnglishPreservingLegalEntities(_ textEl: String) async throws -> (textEn: String, entities: [LegalEntityRecord]) {
        let input = Self.greekInput(textEl)
        let translated = try await translate(input.text, direction: .greekToEnglish)
        var restored = GreekLegalEntityMasker.unmaskEntities(in: translated, entities: input.keptMasked, mode: .bilingualAnchor)
        if !input.appendedNames.isEmpty {
            restored += "\n(" + input.appendedNames.prefix(5).map(\.bilingualAnchor).joined(separator: "; ") + ")"
        }
        return (restored, input.entities)
    }

    /// The text the Greek→English model receives for `textEl`, and how its identifiers come back.
    nonisolated static func greekInput(_ textEl: String)
        -> (text: String, entities: [LegalEntityRecord], keptMasked: [LegalEntityRecord], appendedNames: [LegalEntityRecord]) {
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
        return (toTranslate, entities, keptMasked, appendedNames)
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

    /// English words the translator renders wrongly in a legal text, reworded before translation.
    /// "Quarter" (three months, from a passage's «τρίμηνο») came back «τέταρτο», a fourth, in the
    /// summary of Law 5278/2026 (9 Nov 2026); "a quarter of …" (a fraction) is left as it is.
    /// "Statute" (a law) came back «καταστατικό» (articles of association) in the same summary:
    /// it becomes "law", except in "statute of limitations".
    nonisolated static func legalEnglishPreEdited(_ text: String) -> String {
        let rules: [(String, String)] = [
            (#"(?i)\b(?:a|one)\s+quarter\b(?!\s+of\b)"#, "three months"),
            (#"(?i)\bquarters\b(?!\s+of\b)"#, "three-month periods"),
            (#"(?i)\bquarter\b(?!\s+of\b)"#, "three-month period"),
            (#"\bStatutes\b"#, "Laws"),
            (#"\bstatutes\b"#, "laws"),
            (#"\bStatute\b(?!\s+of\s+limitations?)"#, "Law"),
            (#"\bstatute\b(?!\s+of\s+limitations?)"#, "law"),
            // An em dash between words ("overtime—up to four hours daily—is paid") was dropped by
            // the translator and the words around it glued («υπερωρίαςέως», 9 Nov 2026): commas.
            // A range ("Articles 130–134") keeps its en dash.
            (#"\s*—\s*"#, ", "),
            (#"(?<=\p{L})\s+–\s+(?=\p{L})"#, ", "),
        ]
        var s = text
        for (pattern, template) in rules {
            s = s.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        return s.replacingOccurrences(of: spelledAmount, with: "$1 €", options: .regularExpression)
    }

    /// An amount in words followed by its figure, "forty-one euros and nine cents (41.09 €)" or
    /// "nine hundred and twenty euros (920,00 €)": only the figure is kept. The model wrote "nine
    /// minutes" for the cents, and the words came back «40-ένα ευρώ και 9 λεπτά» in the opinion over
    /// three documents (9 Nov 2026). Runs after the number words became digits ("40-one").
    private static let spelledAmount: String = {
        let word = "(?:\\d+|zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety|hundred|thousand)"
        let number = "\(word)(?:(?:[\\s-]+|\\s+and\\s+)\(word))*"
        return "(?i)\\b\(number)\\s+euros?(?:\\s+and\\s+\(number)\\s+(?:cents?|minutes?))?\\s*\\(\\s*([\\d.,]+)\\s*€\\s*\\)"
    }()

    func translateEnglishToGreekPreservingCitations(_ textEn: String, entities: [LegalEntityRecord] = [], documentNames: [String] = []) async throws -> String {
        // Numbers in words go to Greek as digits ("three hundred" came back "τρία εκατοντάδες"), and
        // the answer goes as plain text: the translator returned "**δώδεκα (12)** μήνες",
        // "8 (****) εβδομάδες" and "# #" headings from the draft's markdown (labour run 1).
        let collapsed = Self.legalEnglishPreEdited(SpelledNumber.digitsForEnglishNumberWords(
            Self.withoutMarkdown(GreekLegalEntityMasker.collapseBilingualAnchors(textEn))))
        // File names stay as written: "passage 3-2.txt" came back «διόδου 3-2.txt».
        let (withoutNames, names) = GreekLegalEntityMasker.maskDocumentNames(in: collapsed, names: documentNames)
        let (maskedWithTerms, allFound) = GreekLegalEntityMasker.maskEntities(in: withoutNames)
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
        let withTerms = await restoringGlossaryGreek(greek, terms: terms)
        let result = GreekLegalEntityMasker.unmaskEntities(in: withTerms, entities: names, mode: .verbatim)
        // Answers, summaries and opinions are translated once each, so this line is at info.
        Log.info("[Opus-MT] en→el answer: \(textEn.count) → \(result.count) chars, \(found.count) identifier(s) and \(terms.count) glossary term(s) kept, \(names.count) file name(s) masked: '\(Self.logPreview(result))'", category: .llm)
        return result
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
