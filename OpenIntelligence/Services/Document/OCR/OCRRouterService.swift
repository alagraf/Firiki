//
//  OCRRouterService.swift
//  OpenIntelligence
//
//  Thesis fork, plan stage 2: Apple's Vision recognizes no Greek (0% recall on rendered Greek
//  pages). Every ingestion path that turns an image into text (StructuredDocumentParser's page
//  reader, DocumentProcessor.performOCR, LayoutAwareExtractor's multi-column pass,
//  IntelligentDocumentProcessor.rescuePageRegions and ImageUnderstandingService) asks this router,
//  passing its own Vision call as a closure. The router decides whether that Vision text is kept
//  or the page is read again by `GreekPaddleOCRService` (PP-OCRv5 det + el rec on ONNX Runtime).
//

import CoreGraphics
import Foundation

/// One recognized line of text, with its box in normalized image coordinates (origin top-left).
nonisolated struct OCRTextLine: Sendable, Equatable {
    var text: String
    var box: CGRect
    var confidence: Float
}

/// An engine that reads text lines from an image.
nonisolated protocol OCREngineProtocol: Sendable {
    var name: String { get }
    var isAvailable: Bool { get }
    func recognizeLines(in image: CGImage) async throws -> [OCRTextLine]
}

nonisolated enum OCREngineMode: String, CaseIterable, Sendable {
    /// Apple Vision only (the original app).
    case vision
    /// Greek PaddleOCR for every image (falls back to Vision when the models are missing).
    case greekPaddleOCR
    /// Vision first; PaddleOCR when Vision's text doesn't look like readable English or the caller
    /// says the document is Greek. Both results are logged for the thesis benchmark.
    case autoBenchmark
}

nonisolated final class OCRRouterService: @unchecked Sendable {
    static let shared = OCRRouterService()

    static let modeDefaultsKey = "thesis.ocrEngineMode"

    private let greekEngine: OCREngineProtocol?
    private let defaults: UserDefaults
    private let modeOverride: OCREngineMode?

    init(greekEngine: OCREngineProtocol? = GreekPaddleOCRService.shared, defaults: UserDefaults = .standard, mode: OCREngineMode? = nil) {
        self.greekEngine = greekEngine
        self.defaults = defaults
        self.modeOverride = mode
    }

    var ocrEngineMode: OCREngineMode {
        if let modeOverride { return modeOverride }
        return defaults.string(forKey: Self.modeDefaultsKey).flatMap(OCREngineMode.init(rawValue:)) ?? .autoBenchmark
    }

    var isGreekEngineAvailable: Bool { greekEngine?.isAvailable == true }

    /// Whether the Greek engine should read this image before Vision is even tried.
    func prefersGreekEngine(languageHint: [String]? = nil) -> Bool {
        guard isGreekEngineAvailable else { return false }
        switch ocrEngineMode {
        case .vision: return false
        case .greekPaddleOCR: return true
        case .autoBenchmark: return languageHint?.contains(where: { $0.lowercased().hasPrefix("el") }) == true
        }
    }

    /// Whether text Vision returned should be read again by the Greek engine: it is long enough to
    /// judge and either already has Greek letters (Vision's Greek is unreliable) or is mostly
    /// words that are not English (Vision reads Greek as Latin lookalikes such as "Apepo").
    static func visionTextNeedsGreekEngine(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 20 else { return trimmed.isEmpty }
        if GreekLegalEntityMasker.containsGreek(trimmed) { return true }
        let words = trimmed.lowercased()
            .components(separatedBy: CharacterSet.letters.inverted)
            .filter { $0.count >= 2 }
        guard words.count >= 6 else { return false }
        let english = words.filter { englishProbe.contains($0) }.count
        return Double(english) / Double(words.count) < 0.08
    }

    private static let englishProbe: Set<String> = [
        "the", "and", "of", "to", "in", "is", "for", "on", "with", "as", "by", "at", "or", "be",
        "this", "that", "are", "from", "an", "it", "not", "was", "which", "all", "any", "may",
        "shall", "will", "can", "if", "no", "has", "have", "its", "their", "other", "page",
    ]

    /// Lines joined in reading order: top to bottom, left to right on a line, a tab where a line
    /// has a wide gap (table columns), a blank line where the vertical gap is wide (paragraphs).
    static func joinLines(_ lines: [OCRTextLine]) -> String {
        let sorted = lines.filter { !$0.text.isEmpty }.sorted { a, b in
            if abs(a.box.midY - b.box.midY) < min(a.box.height, b.box.height) * 0.5 { return a.box.minX < b.box.minX }
            return a.box.midY < b.box.midY
        }
        var rows: [[OCRTextLine]] = []
        for line in sorted {
            if let last = rows.last?.last, abs(last.box.midY - line.box.midY) < min(last.box.height, line.box.height) * 0.5 {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line])
            }
        }
        var output: [String] = []
        var previousBottom: CGFloat?
        for row in rows {
            let height = row.map(\.box.height).max() ?? 0
            let top = row.map(\.box.minY).min() ?? 0
            if let previousBottom, top - previousBottom > height * 0.8, !output.isEmpty {
                output.append("")
            }
            var text = ""
            var lastMaxX: CGFloat?
            for line in row {
                if let lastMaxX {
                    text += (line.box.minX - lastMaxX) > height * 2.5 ? "\t" : " "
                }
                text += line.text
                lastMaxX = line.box.maxX
            }
            output.append(text)
            previousBottom = row.map(\.box.maxY).max()
        }
        return output.joined(separator: "\n")
    }

    /// Reads `image` with the Greek engine when it should; otherwise returns `visionText()`.
    /// - Parameters:
    ///   - site: which call site asked, for the benchmark log.
    ///   - languageHint: the document's languages when the caller knows them.
    func recognizeText(
        in image: CGImage,
        site: String,
        languageHint: [String]? = nil,
        visionText: () async throws -> String
    ) async throws -> String {
        guard let greekEngine, greekEngine.isAvailable, ocrEngineMode != .vision else {
            return try await visionText()
        }
        if prefersGreekEngine(languageHint: languageHint) {
            let start = Date()
            let greek = Self.joinLines(try await greekEngine.recognizeLines(in: image))
            let keep = !greek.isEmpty || ocrEngineMode == .greekPaddleOCR
            log(site: site, engine: greekEngine.name, text: greek, start: start, used: keep)
            if keep { return greek }
            return try await visionText()
        }

        let visionStart = Date()
        let vision = try await visionText()
        log(site: site, engine: "vision", text: vision, start: visionStart)
        guard Self.visionTextNeedsGreekEngine(vision) else { return vision }

        let greekStart = Date()
        let greek: String
        do {
            greek = Self.joinLines(try await greekEngine.recognizeLines(in: image))
        } catch {
            Log.warning("[OCRRouter] \(site): \(greekEngine.name) failed, keeping Vision: \(error.localizedDescription)", category: .ingestion)
            return vision
        }
        let greekLetters = greek.unicodeScalars.filter(GreekLegalEntityMasker.isGreekScalar).count
        let keep = greekLetters >= OCRConfiguration.greekLetterMinimum || vision.isEmpty
        log(site: site, engine: greekEngine.name, text: greek, start: greekStart, used: keep)
        return keep ? greek : vision
    }

    /// The Greek engine's lines for `image`, or nil when it cannot run, the mode is `.vision`, or
    /// (unless `force`) the router would not pick it before trying Vision.
    func greekLines(in image: CGImage, site: String, languageHint: [String]? = nil, force: Bool = false) async -> [OCRTextLine]? {
        guard let greekEngine, greekEngine.isAvailable, ocrEngineMode != .vision else { return nil }
        guard force || prefersGreekEngine(languageHint: languageHint) else { return nil }
        let start = Date()
        do {
            let lines = try await greekEngine.recognizeLines(in: image)
            log(site: site, engine: greekEngine.name, text: Self.joinLines(lines), start: start, used: !lines.isEmpty)
            return lines
        } catch {
            Log.warning("[OCRRouter] \(site): \(greekEngine.name) failed: \(error.localizedDescription)", category: .ingestion)
            return nil
        }
    }

    private func log(site: String, engine: String, text: String, start: Date, used: Bool = true) {
        let greek = text.unicodeScalars.filter(GreekLegalEntityMasker.isGreekScalar).count
        let milliseconds = Int(Date().timeIntervalSince(start) * 1000)
        Log.info(
            "[OCRBenchmark] site=\(site) engine=\(engine) chars=\(text.count) greekLetters=\(greek) ms=\(milliseconds) used=\(used)",
            category: .ingestion
        )
        // The import's Processing Log says when PaddleOCR read something.
        if engine != "vision" {
            IngestionLogRecorder.current?.recordGreekOCR(
                engine: engine, site: site, characters: text.count, milliseconds: milliseconds, used: used)
        }
    }
}
