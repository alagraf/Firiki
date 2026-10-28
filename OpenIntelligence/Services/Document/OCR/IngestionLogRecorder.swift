//
//  IngestionLogRecorder.swift
//  OpenIntelligence
//
//  Thesis fork: puts the Greek engines in the import's Processing Log. OCR runs deep inside
//  DocumentProcessor, which doesn't know the import's queue item, so the import hands a recorder
//  down as a task-local value; `OCRRouterService` reports each PaddleOCR run to it, and the import
//  writes the first use and a summary as log lines. The Opus-MT translation step writes its own.
//

import Foundation

nonisolated final class IngestionLogRecorder: @unchecked Sendable {
    /// The recorder of the import running in this task, if any.
    @TaskLocal static var current: IngestionLogRecorder?

    /// Adds a line (stage, title, detail) to the import's Processing Log.
    private let emit: @Sendable (IngestionStage, String, String) -> Void
    private let lock = NSLock()
    private var ocrRuns = 0
    private var ocrUsed = 0
    private var ocrCharacters = 0
    private var ocrMilliseconds = 0
    private var ocrEngine: String?
    private var announcedOCR = false

    init(emit: @escaping @Sendable (IngestionStage, String, String) -> Void) {
        self.emit = emit
    }

    func log(_ stage: IngestionStage, title: String, detail: String) {
        emit(stage, title, detail)
    }

    /// One run of the Greek OCR engine. `used` is false when Vision's text was kept instead.
    func recordGreekOCR(engine: String, site: String, characters: Int, milliseconds: Int, used: Bool) {
        lock.lock()
        ocrRuns += 1
        if used {
            ocrUsed += 1
            ocrCharacters += characters
        }
        ocrMilliseconds += milliseconds
        ocrEngine = engine
        let first = !announcedOCR
        announcedOCR = true
        lock.unlock()
        if first {
            emit(.extracting, "Greek OCR", "PaddleOCR PP-OCRv5 (Greek model, on device) is reading this file's images; Vision recognizes no Greek")
        }
    }

    /// "PaddleOCR read 12 of 12 images …", or nil when it didn't run.
    var greekOCRSummary: String? {
        lock.lock()
        defer { lock.unlock() }
        guard ocrRuns > 0 else { return nil }
        return "PaddleOCR (\(ocrEngine ?? "PP-OCRv5")) read \(ocrRuns) image\(ocrRuns == 1 ? "" : "s"), "
            + "its text kept for \(ocrUsed), \(ocrCharacters) characters, in "
            + String(format: "%.1f s", Double(ocrMilliseconds) / 1000)
    }
}
