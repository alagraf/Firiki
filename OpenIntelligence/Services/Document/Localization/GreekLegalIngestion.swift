//
//  GreekLegalIngestion.swift
//  OpenIntelligence
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

    /// One result per text: the English text and the metadata for a Greek chunk, the text itself
    /// and identifier-only metadata (or nil) otherwise. A translation failure keeps the Greek text.
    static func translateChunks(
        _ texts: [String],
        translate: (String) async throws -> (textEn: String, entities: [LegalEntityRecord]) = {
            try await LocalNeuralTranslator.shared.translateGreekToEnglishPreservingLegalEntities($0)
        }
    ) async -> [(text: String, legal: LegalChunkMetadata?)] {
        var results: [(text: String, legal: LegalChunkMetadata?)] = []
        results.reserveCapacity(texts.count)
        var translatedCount = 0
        for text in texts {
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
        return results
    }
}
