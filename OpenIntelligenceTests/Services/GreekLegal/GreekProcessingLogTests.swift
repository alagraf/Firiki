//
//  GreekProcessingLogTests.swift
//  OpenIntelligenceTests
//
//  Thesis fork: a scanned Greek PDF's Processing Log names PaddleOCR and Opus-MT, and suggested
//  questions are off.
//

import AppIntents
import CoreGraphics
import Foundation
import Testing

@testable import OpenIntelligence

@MainActor
@Suite("Greek engines in the Processing Log")
struct GreekProcessingLogTests {
    /// A one-page PDF with no text layer: the rendered Greek page as an image.
    private func scannedPDF() throws -> Data {
        let page = renderPage([
            "Άρθρο 66",
            "Καταγγελία σύμβασης εργασίας αορίστου χρόνου",
            "Η καταγγελία της σύμβασης εργασίας γίνεται εγγράφως.",
            "Ο εργοδότης καταβάλλει στον εργαζόμενο την αποζημίωση.",
        ])
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: page.width, height: page.height)
        let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
        let context = try #require(CGContext(consumer: consumer, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        context.draw(page, in: box)
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }

    @Test func scannedGreekPDFLogsPaddleOCRAndOpusMT() async throws {
        try #require(GreekPaddleOCRService.shared.isAvailable)
        try #require(LocalNeuralTranslator.isAvailable(.greekToEnglish))
        let saved = UserDefaults.standard.object(forKey: "entitlement.activeTier")
        UserDefaults.standard.set(WorkspaceTier.pro.rawValue, forKey: "entitlement.activeTier")
        defer { UserDefaults.standard.set(saved, forKey: "entitlement.activeTier") }

        let engine = IntentSupport.engine()
        let library = try engine.containerService.createContainer(name: "Greek log \(UUID().uuidString.prefix(6))")
        defer { engine.containerService.deleteContainer(id: library.id) }
        let filename = "scanned-greek-\(UUID().uuidString.prefix(6)).pdf"
        let add = AddToLibraryIntent()
        add.file = IntentFile(data: try scannedPDF(), filename: filename, type: .pdf)
        add.library = OILibraryEntityQuery.entity(for: library)
        _ = try await add.perform()

        var item: IngestionItem?
        for _ in 0..<1_800 {
            item = engine.ingestionItems.first { $0.filename == filename && $0.stage.isTerminal }
            if item != nil { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        // The last log lines are added on the main actor just after the stage changes.
        try await Task.sleep(for: .milliseconds(500))
        item = engine.ingestionItems.first { $0.filename == filename }
        let events = try #require(item?.events)
        let log = events.map { "\($0.title): \($0.detail ?? "")" }
        #expect(log.contains { $0.hasPrefix("Greek OCR: PaddleOCR PP-OCRv5") }, "\(log)")
        #expect(log.contains { $0.hasPrefix("Greek OCR: PaddleOCR (") && $0.contains("its text kept for") }, "\(log)")
        #expect(log.contains { $0.hasPrefix("Translation: Opus-MT (opus-mt-tc-big-el-en, on device) is translating") }, "\(log)")
        #expect(log.contains { $0.hasPrefix("Translation: Opus-MT translated") }, "\(log)")
    }

    @Test func suggestedQuestionsAreOff() async {
        #expect(!SuggestedQuestionsService.isEnabled)
    }
}
