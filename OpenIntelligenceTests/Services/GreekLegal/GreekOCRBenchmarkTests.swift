//
//  GreekOCRBenchmarkTests.swift
//  OpenIntelligenceTests
//
//  Thesis fork: Greek OCR benchmark suite over clean, scanned and photographed pages
//  from Presidential Decree 62/2025 Labour Code (pd_62_2025_excerpt.pdf).
//  Measures CER, WER, bag-of-words recall/precision, legal identifier recall,
//  number recall, and seconds/page across Vision, PaddleOCR, and the app's own path.
//

import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import Testing
import Vision

@testable import OpenIntelligence

@Suite(
    "Greek OCR Benchmark",
    .enabled(if: ProcessInfo.processInfo.environment["TEST_RUNNER_OI_OCR_BENCH"] == "1"
        || ProcessInfo.processInfo.environment["OI_OCR_BENCH"] == "1")
)
struct GreekOCRBenchmarkTests {

    static let repositoryRoot: URL = {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // GreekLegal
            .deletingLastPathComponent()  // Services
            .deletingLastPathComponent()  // OpenIntelligenceTests
            .deletingLastPathComponent()  // Repository Root
    }()

    static let benchmarkFolder: URL = {
        repositoryRoot.appendingPathComponent("Benchmarks/GreekOCR")
    }()

    // MARK: - Metric Helpers

    /// Character error rate: edit distance over normalized text without whitespace.
    static func characterErrorRate(reference: String, hypothesis: String) -> Double {
        let r = Array(GreekLegalEntityMasker.normalizeGreekText(reference).filter { !$0.isWhitespace })
        let h = Array(GreekLegalEntityMasker.normalizeGreekText(hypothesis).filter { !$0.isWhitespace })
        guard !r.isEmpty else { return h.isEmpty ? 0 : 1 }
        var previous = Array(0...h.count)
        for i in 1...r.count {
            var current = [i] + Array(repeating: 0, count: h.count)
            for j in 1...max(1, h.count) where h.count > 0 {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (r[i - 1] == h[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return Double(previous[h.count]) / Double(r.count)
    }

    /// Word error rate: word-level Levenshtein distance over normalized lower-cased tokens.
    static func wordErrorRate(reference: String, hypothesis: String) -> Double {
        let fold: (String) -> [String] = { text in
            GreekLegalEntityMasker.normalizeGreekText(text).lowercased()
                .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        }
        let r = fold(reference), h = fold(hypothesis)
        guard !r.isEmpty else { return h.isEmpty ? 0 : 1 }
        var previous = Array(0...h.count)
        for i in 1...r.count {
            var current = [i] + Array(repeating: 0, count: h.count)
            for j in 1...max(1, h.count) where h.count > 0 {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (r[i - 1] == h[j - 1] ? 0 : 1))
            }
            previous = current
        }
        return Double(previous[h.count]) / Double(r.count)
    }

    /// Bag of words frequency map with line-end hyphenation re-joined to align with reference text.
    static func bagOfWords(from text: String) -> [String: Int] {
        let dehyphenated = text.replacingOccurrences(of: #"(\p{L})-\s*\n\s*(\p{L})"#, with: "$1$2", options: .regularExpression)
        let normalized = GreekLegalEntityMasker.normalizeGreekText(dehyphenated).lowercased()
        let words = normalized.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        var bag: [String: Int] = [:]
        for w in words { bag[w, default: 0] += 1 }
        return bag
    }

    /// Order-free word recall and precision.
    static func bagOfWordsMetrics(reference: String, hypothesis: String) -> (recall: Double, precision: Double) {
        let rBag = bagOfWords(from: reference)
        let hBag = bagOfWords(from: hypothesis)
        let rTotal = rBag.values.reduce(0, +)
        let hTotal = hBag.values.reduce(0, +)
        guard rTotal > 0 else { return (recall: 1.0, precision: hTotal == 0 ? 1.0 : 0.0) }
        var matched = 0
        for (word, rCount) in rBag {
            if let hCount = hBag[word] {
                matched += min(rCount, hCount)
            }
        }
        let recall = Double(matched) / Double(rTotal)
        let precision = hTotal > 0 ? Double(matched) / Double(hTotal) : 0.0
        return (recall, precision)
    }

    /// Share of reference canonical legal keys found in OCR text.
    static func legalIdentifierRecall(reference: String, hypothesis: String) -> Double {
        let rKeys = GreekLegalEntityMasker.canonicalKeys(in: reference)
        guard !rKeys.isEmpty else { return 1.0 }
        let hKeys = GreekLegalEntityMasker.canonicalKeys(in: hypothesis)
        let intersection = rKeys.intersection(hKeys)
        return Double(intersection.count) / Double(rKeys.count)
    }

    /// Bag of numbers frequency map.
    static func bagOfNumbers(from text: String) -> [String: Int] {
        guard let regex = try? NSRegularExpression(pattern: "\\d+") else { return [:] }
        let nsString = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
        var bag: [String: Int] = [:]
        for match in matches {
            let num = nsString.substring(with: match.range)
            bag[num, default: 0] += 1
        }
        return bag
    }

    /// Share of reference numbers found in OCR text.
    static func numberRecall(reference: String, hypothesis: String) -> Double {
        let rBag = bagOfNumbers(from: reference)
        let rTotal = rBag.values.reduce(0, +)
        guard rTotal > 0 else { return 1.0 }
        let hBag = bagOfNumbers(from: hypothesis)
        var matched = 0
        for (num, rCount) in rBag {
            if let hCount = hBag[num] {
                matched += min(rCount, hCount)
            }
        }
        return Double(matched) / Double(rTotal)
    }

    // MARK: - Readers

    static func runVisionOnly(on cgImage: CGImage) async throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = OCRConfiguration.recognitionLanguages
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        guard let observations = request.results else { return "" }
        let sorted = observations.sorted { obs1, obs2 in
            let b1 = obs1.boundingBox
            let b2 = obs2.boundingBox
            if abs(b1.midY - b2.midY) > 0.05 {
                return b1.midY > b2.midY
            }
            return b1.minX < b2.minX
        }
        return sorted.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    static func runPaddleOnly(on cgImage: CGImage) async throws -> String {
        let engine = GreekPaddleOCRService.shared
        guard engine.isAvailable else { return "" }
        let lines = try await engine.recognizeLines(in: cgImage)
        let joined = OCRRouterService.joinLines(lines)
        return GreekLegalEntityMasker.repairGreekHomoglyphs(joined)
    }

    @MainActor
    static func runAppPath(on ciImage: CIImage) async -> String {
        await ImageUnderstandingService.shared.extractTextFromImage(ciImage) ?? ""
    }

    // MARK: - Benchmark Case Models

    struct ManifestItem: Decodable {
        let page: Int
        let version: String
        let file: String
        let reference_text_file: String
        let rotation_degrees: Double
        let jpeg_quality: Int
        let dpi: Int
    }

    struct Manifest: Decodable {
        let description: String
        let source: String
        let pages: [Int]
        let items: [ManifestItem]
    }

    struct MeasurementResult {
        let page: Int
        let version: String
        let reader: String
        let cer: Double
        let wer: Double
        let wordRecall: Double
        let wordPrecision: Double
        let idRecall: Double
        let numberRecall: Double
        let seconds: Double
    }

    // MARK: - Step 3: Per-Image OCR Benchmark Test

    @Test("Benchmark OCR on Clean, Scanned, and Photographed Pages", .timeLimit(.minutes(30)))
    func benchmarkGreekOCR() async throws {
        let folder = Self.benchmarkFolder
        let manifestFile = folder.appendingPathComponent("manifest.json")
        try #require(FileManager.default.fileExists(atPath: manifestFile.path), "manifest.json must exist in Benchmarks/GreekOCR")

        let data = try Data(contentsOf: manifestFile)
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)

        try #require(GreekPaddleOCRService.shared.isAvailable, "PaddleOCR Greek model must be available")

        var measurements: [MeasurementResult] = []

        // 1. Process Manifest Items
        for item in manifest.items {
            let imageURL = folder.appendingPathComponent(item.file)
            let refURL = folder.appendingPathComponent(item.reference_text_file)
            guard FileManager.default.fileExists(atPath: imageURL.path),
                  FileManager.default.fileExists(atPath: refURL.path) else {
                continue
            }

            let refText = try String(contentsOf: refURL, encoding: .utf8)

            guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                continue
            }
            let ciImage = CIImage(cgImage: cgImage)

            // Reader 1: Vision Only
            let vStart = Date()
            let visionText = (try? await Self.runVisionOnly(on: cgImage)) ?? ""
            let vElapsed = Date().timeIntervalSince(vStart)
            let vMetrics = calculateMetrics(
                page: item.page, version: item.version, reader: "vision",
                ref: refText, hyp: visionText, elapsed: vElapsed
            )
            measurements.append(vMetrics)
            printLine(vMetrics)

            // Reader 2: PaddleOCR Only
            let pStart = Date()
            let paddleText = (try? await Self.runPaddleOnly(on: cgImage)) ?? ""
            let pElapsed = Date().timeIntervalSince(pStart)
            let pMetrics = calculateMetrics(
                page: item.page, version: item.version, reader: "paddle",
                ref: refText, hyp: paddleText, elapsed: pElapsed
            )
            measurements.append(pMetrics)
            printLine(pMetrics)

            // Reader 3: App Path (ImageUnderstandingService)
            let aStart = Date()
            let appText = await Self.runAppPath(on: ciImage)
            let aElapsed = Date().timeIntervalSince(aStart)
            let aMetrics = calculateMetrics(
                page: item.page, version: item.version, reader: "app_path",
                ref: refText, hyp: appText, elapsed: aElapsed
            )
            measurements.append(aMetrics)
            printLine(aMetrics)
        }

        // 2. Process Real Owner Photos in photos/ if any exist
        let photosDir = folder.appendingPathComponent("photos")
        if let contents = try? FileManager.default.contentsOfDirectory(at: photosDir, includingPropertiesForKeys: nil) {
            let photoFiles = contents.filter { $0.pathExtension.lowercased() == "jpg" || $0.pathExtension.lowercased() == "jpeg" }
            for file in photoFiles {
                let name = file.lastPathComponent
                // Match pattern: p<page>_<n>.jpg
                guard let match = try? NSRegularExpression(pattern: "^p(\\d+)_.*").firstMatch(
                    in: name, range: NSRange(location: 0, length: (name as NSString).length)
                ) else { continue }
                let pageStr = (name as NSString).substring(with: match.range(at: 1))
                guard let pageNum = Int(pageStr) else { continue }

                let refURL = folder.appendingPathComponent(String(format: "ref/page_%02d_ref.txt", pageNum))
                guard let refText = try? String(contentsOf: refURL, encoding: .utf8),
                      let source = CGImageSourceCreateWithURL(file as CFURL, nil),
                      let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { continue }
                let ciImage = CIImage(cgImage: cgImage)

                let vStart = Date()
                let vText = (try? await Self.runVisionOnly(on: cgImage)) ?? ""
                let vM = calculateMetrics(page: pageNum, version: "owner_photo", reader: "vision", ref: refText, hyp: vText, elapsed: Date().timeIntervalSince(vStart))
                measurements.append(vM)
                printLine(vM)

                let pStart = Date()
                let pText = (try? await Self.runPaddleOnly(on: cgImage)) ?? ""
                let pM = calculateMetrics(page: pageNum, version: "owner_photo", reader: "paddle", ref: refText, hyp: pText, elapsed: Date().timeIntervalSince(pStart))
                measurements.append(pM)
                printLine(pM)

                let aStart = Date()
                let aText = await Self.runAppPath(on: ciImage)
                let aM = calculateMetrics(page: pageNum, version: "owner_photo", reader: "app_path", ref: refText, hyp: aText, elapsed: Date().timeIntervalSince(aStart))
                measurements.append(aM)
                printLine(aM)
            }
        }

        // 3. Print Summary Table per version and reader
        let versions = Array(Set(measurements.map(\.version))).sorted()
        let readers = ["vision", "paddle", "app_path"]

        print("=== [OCRBench] SUMMARY TABLE ===")
        for v in versions {
            for r in readers {
                let group = measurements.filter { $0.version == v && $0.reader == r }
                guard !group.isEmpty else { continue }
                let count = Double(group.count)
                let meanCER = group.map(\.cer).reduce(0, +) / count
                let meanWER = group.map(\.wer).reduce(0, +) / count
                let meanRecall = group.map(\.wordRecall).reduce(0, +) / count
                let meanPrecision = group.map(\.wordPrecision).reduce(0, +) / count
                let meanIdRecall = group.map(\.idRecall).reduce(0, +) / count
                let meanNumRecall = group.map(\.numberRecall).reduce(0, +) / count
                let meanSeconds = group.map(\.seconds).reduce(0, +) / count

                print(String(
                    format: "[OCRBench] SUMMARY version=%@ reader=%@ n=%d CER=%.4f WER=%.4f wordRecall=%.4f wordPrec=%.4f idRecall=%.4f numRecall=%.4f s/page=%.2f",
                    v, r, group.count, meanCER, meanWER, meanRecall, meanPrecision, meanIdRecall, meanNumRecall, meanSeconds
                ))
            }
        }
        #expect(!measurements.isEmpty, "Benchmark should produce measurements")
    }

    private func calculateMetrics(page: Int, version: String, reader: String, ref: String, hyp: String, elapsed: Double) -> MeasurementResult {
        let cer = Self.characterErrorRate(reference: ref, hypothesis: hyp)
        let wer = Self.wordErrorRate(reference: ref, hypothesis: hyp)
        let (recall, prec) = Self.bagOfWordsMetrics(reference: ref, hypothesis: hyp)
        let idRecall = Self.legalIdentifierRecall(reference: ref, hypothesis: hyp)
        let numRecall = Self.numberRecall(reference: ref, hypothesis: hyp)
        return MeasurementResult(
            page: page, version: version, reader: reader,
            cer: cer, wer: wer, wordRecall: recall, wordPrecision: prec,
            idRecall: idRecall, numberRecall: numRecall, seconds: elapsed
        )
    }

    private func printLine(_ m: MeasurementResult) {
        print(String(
            format: "[OCRBench] page %02d %@ %@ CER %.4f WER %.4f wordRecall %.4f wordPrec %.4f idRecall %.4f numRecall %.4f s %.2f",
            m.page, m.version, m.reader, m.cer, m.wer, m.wordRecall, m.wordPrecision, m.idRecall, m.numberRecall, m.seconds
        ))
    }

    // MARK: - Step 4: Whole-Import Check of scan_pages.pdf

    @MainActor
    @Test("Whole Document Ingestion of Scanned Pages", .timeLimit(.minutes(15)))
    func wholeImportScanPages() async throws {
        let scanPdfURL = Self.benchmarkFolder.appendingPathComponent("scan_pages.pdf")
        try #require(FileManager.default.fileExists(atPath: scanPdfURL.path), "scan_pages.pdf must exist")

        let libraries = IntentSupport.libraries()
        let engine = RAGService(containerService: libraries)

        for _ in 0..<100 where !engine.hasLoadedDocumentsFromDisk {
            try await Task.sleep(for: .milliseconds(100))
        }

        let libraryName = "Greek OCR Scanned Document Ingestion"
        // Clean existing
        if let existing = libraries.containers.first(where: { $0.name == libraryName }) {
            for doc in engine.documents where doc.containerId == existing.id {
                try? await engine.removeDocument(doc)
            }
            libraries.deleteContainer(id: existing.id)
        }

        let library = try libraries.createContainer(name: libraryName)

        let started = Date()
        let importResult = await engine.ingestDocuments([scanPdfURL], containerId: library.id)
        let elapsed = Date().timeIntervalSince(started)
        print("[OCRBench] WHOLE-IMPORT imported \(importResult.successCount) document in \(String(format: "%.1f", elapsed)) s")
        try #require(importResult.successCount == 1, "scan_pages.pdf must import successfully")

        // Inspect Processing Log events
        var ocrEngineReported = "None"
        for item in engine.ingestionItems {
            for event in item.events {
                if event.title == "Greek OCR" {
                    ocrEngineReported = event.detail ?? "None"
                    print("[OCRBench] WHOLE-IMPORT Processing Log [Greek OCR]: \(event.detail ?? "None")")
                }
            }
        }

        // Retrieve chunks and compare stored Greek source text
        guard let doc = engine.documents.first(where: { $0.containerId == library.id }) else {
            Issue.record("Document not found after ingestion")
            return
        }

        let legalMap = await SQLiteFullTextService.shared.legalChunkMetadata(for: doc.id)
        let greekTexts = legalMap.values.compactMap(\.sourceTextEl)
        let combinedExtracted = greekTexts.joined(separator: "\n\n")

        // Load reference texts of all 10 pages
        var combinedRef = ""
        let manifestFile = Self.benchmarkFolder.appendingPathComponent("manifest.json")
        if let data = try? Data(contentsOf: manifestFile),
           let manifest = try? JSONDecoder().decode(Manifest.self, from: data) {
            let scanItems = manifest.items.filter { $0.version == "scan" }
            for item in scanItems {
                let refURL = Self.benchmarkFolder.appendingPathComponent(item.reference_text_file)
                if let t = try? String(contentsOf: refURL, encoding: .utf8) {
                    combinedRef += t + "\n\n"
                }
            }
        }

        let (recall, prec) = Self.bagOfWordsMetrics(reference: combinedRef, hypothesis: combinedExtracted)
        let idRecall = Self.legalIdentifierRecall(reference: combinedRef, hypothesis: combinedExtracted)
        let numRecall = Self.numberRecall(reference: combinedRef, hypothesis: combinedExtracted)

        print(String(
            format: "[OCRBench] WHOLE-IMPORT SUMMARY chunks=%d greekChunks=%d bagRecall=%.4f bagPrec=%.4f idRecall=%.4f numRecall=%.4f engine='%@'",
            doc.totalChunks, greekTexts.count, recall, prec, idRecall, numRecall, ocrEngineReported
        ))
    }
}
