//
//  GreekLegalIngestion.swift
//  Firiki
//
//  Thesis fork, plan stage 4: after extraction and chunking (native PDF text and OCR text alike),
//  each Greek chunk keeps its Greek text as `LegalChunkMetadata.sourceTextEl` and is replaced, for
//  embedding, FTS5 and the model, by its English translation with bilingual legal anchors
//  ("Article 38 [Άρθρο 38] of Law 4808/2021 [Ν. 4808/2021]").
//

import Foundation

nonisolated enum GreekLegalIngestion {
    /// A chunk with at least this share of Greek letters is translated.
    static let greekChunkThreshold = 0.3

    static func isGreekChunk(_ text: String) -> Bool {
        GreekLegalEntityMasker.greekLetterRatio(text) >= greekChunkThreshold
    }

    /// The legal metadata of a chunk that is not translated: its identifiers and primary statute,
    /// so gates F and I work on English documents too.
    static func untranslatedMetadata(for text: String) -> LegalChunkMetadata? {
        let entities = GreekLegalEntityMasker.extractEntities(from: text)
        guard !entities.isEmpty else { return nil }
        return LegalChunkMetadata(
            sourceTextEl: nil, sourceLanguage: "en", legalEntities: entities,
            primaryStatuteKey: GreekLegalEntityMasker.primaryStatuteKey(for: entities)
        )
    }

    /// Greek chunks whose sentences are translated together, ahead of the chunks themselves: enough
    /// that sorting by length gives batches of sentences of about the same length.
    static let pretranslationWindow = 256

    /// One result per text: the English text and the metadata for a Greek chunk, the text itself
    /// and identifier-only metadata (or nil) otherwise. A translation failure keeps the Greek text.
    /// Every `pretranslationWindow` Greek chunks are first batch-translated by `pretranslate`; the
    /// translator's sessions are released at the end (`finish`).
    static func translateChunks(
        _ texts: [String],
        translate: (String) async throws -> (textEn: String, entities: [LegalEntityRecord]) = {
            try await LocalNeuralTranslator.shared.translateGreekToEnglishPreservingLegalEntities($0)
        },
        pretranslate: ([String]) async -> Void = { await LocalNeuralTranslator.shared.pretranslateGreekChunks($0) },
        finish: () async -> Void = { await LocalNeuralTranslator.shared.releaseModels() }
    ) async -> [(text: String, legal: LegalChunkMetadata?)] {
        var results: [(text: String, legal: LegalChunkMetadata?)] = []
        results.reserveCapacity(texts.count)
        var translatedCount = 0
        let greekIndices = texts.indices.filter { isGreekChunk(texts[$0]) }
        var windowStarts = Set(stride(from: 0, to: greekIndices.count, by: pretranslationWindow).map { greekIndices[$0] })
        for (index, text) in texts.enumerated() {
            if windowStarts.remove(index) != nil, let position = greekIndices.firstIndex(of: index) {
                let window = greekIndices[position..<min(position + pretranslationWindow, greekIndices.count)]
                await pretranslate(window.map { GreekLegalEntityMasker.normalizeGreekText(texts[$0]) })
            }
            guard isGreekChunk(text) else {
                results.append((text, untranslatedMetadata(for: text)))
                continue
            }
            let sourceEl = GreekLegalEntityMasker.normalizeGreekText(text)
            do {
                let (english, entities) = try await translate(sourceEl)
                guard !english.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw LocalNeuralTranslator.TranslatorError.unexpectedOutput("empty translation")
                }
                results.append((english, LegalChunkMetadata(
                    sourceTextEl: sourceEl, sourceLanguage: "el", legalEntities: entities,
                    primaryStatuteKey: GreekLegalEntityMasker.primaryStatuteKey(for: entities)
                )))
                translatedCount += 1
            } catch {
                Log.warning("[GreekIngestion] Chunk translation failed, keeping Greek: \(error.localizedDescription)", category: .ingestion)
                let entities = GreekLegalEntityMasker.extractEntities(from: sourceEl)
                results.append((sourceEl, LegalChunkMetadata(
                    sourceTextEl: sourceEl, sourceLanguage: "el", legalEntities: entities,
                    primaryStatuteKey: GreekLegalEntityMasker.primaryStatuteKey(for: entities)
                )))
            }
        }
        if translatedCount > 0 {
            Log.info("[GreekIngestion] Translated \(translatedCount)/\(texts.count) Greek chunks to English (Opus-MT)", category: .ingestion)
        }
        await finish()
        return results
    }

    // MARK: The document's own statute

    /// The statute a document is, read from its title page: "PD:62/2025" (ΠΡΟΕΔΡΙΚΟ ΔΙΑΤΑΓΜΑ ΥΠ'
    /// ΑΡΙΘΜ. 62), "LAW:5239/2025" (ΝΟΜΟΣ ΥΠ' ΑΡΙΘΜ. 5239), "MD:8934" (ΑΠΟΦΑΣΕΙΣ Αριθμ. 8934),
    /// "CONST" (ΣΥΝΤΑΓΜΑ ΤΗΣ ΕΛΛΑΔΑΣ), or nil. A law or decree takes the year of the Government
    /// Gazette's date when the page has one. Only the opening is read, so a statute the preamble
    /// cites is not taken for the document's own.
    static func documentStatuteKey(opening text: String) -> String? {
        let folded = SQLiteFullTextService.greekSearchFold(String(text.prefix(openingLength)))
        func number(_ pattern: String) -> String? {
            guard let match = folded.firstMatch(of: try! Regex(pattern)), let value = match.output[1].substring else { return nil }
            return String(value)
        }
        let year = number(#"\b\d{1,2}\s+(?:ιανουαριου|φεβρουαριου|μαρτιου|απριλιου|μαιου|ιουνιου|ιουλιου|αυγουστου|σεπτεμβριου|οκτωβριου|νοεμβριου|δεκεμβριου)\s+((?:19|20)\d\d)\b"#)
        let withYear = { (key: String) in year.map { key + "/" + $0 } ?? key }
        if let decree = number(#"προεδρικο\s+διαταγμα\s+υπ'?\s*αριθμ\.?\s*(\d+)"#) { return withYear("PD:" + decree) }
        if let law = number(#"\bνομοσ\s+υπ'?\s*αριθμ\.?\s*(\d+)"#) { return withYear("LAW:" + law) }
        if let decision = number(#"\bαποφασ(?:η|εισ)\s+αριθμ\.?\s*(\d+)"#) { return "MD:" + decision }
        if folded.contains(try! Regex(#"\bσυνταγμα\s+τησ\s+ελλαδασ\b"#)) { return "CONST" }
        return nil
    }

    /// Characters of a document's opening that `documentStatuteKey` reads.
    static let openingLength = 1_500

    /// The chunks' legal metadata with `documentStatuteKey` set to the statute the document's
    /// opening names; unchanged when it names none. A chunk without metadata gets one carrying
    /// only the key.
    static func withDocumentStatute(_ legal: [LegalChunkMetadata?], opening: String) -> [LegalChunkMetadata?] {
        guard let statute = documentStatuteKey(opening: opening) else { return legal }
        return legal.map { metadata in
            var metadata = metadata ?? LegalChunkMetadata()
            metadata.documentStatuteKey = statute
            return metadata
        }
    }
}
