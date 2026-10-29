//
//  GreekPaddleOCRService.swift
//  OpenIntelligence
//
//  Thesis fork, plan stage 2: Greek OCR with PaddleOCR's PP-OCRv5 mobile text detector and its
//  Greek recognizer (`PaddlePaddle/el_PP-OCRv5_mobile_rec_onnx`, Apache-2.0), run on device with
//  ONNX Runtime. Detection is DB (differentiable binarization): a probability map, thresholded,
//  split into connected regions, each region's box (along the region's principal axis, so a line
//  on a tilted page stays one line) grown by the unclip ratio. Each box is sampled level from the
//  full image, resized to 48 px high and read by the recognizer, whose output is decoded
//  greedily (CTC: best class per step, repeats merged, blanks dropped). Pre- and post-processing
//  constants are the ones in each model's `inference.yml`.
//
//  The models are in `Resources/MLModels/GreekOCR/`. A build without ONNX Runtime (the Swift
//  package build of the engine) or without the model files reports `isAvailable == false`, and
//  `OCRRouterService` keeps Vision.
//

import CoreGraphics
import Foundation
#if canImport(OnnxRuntimeBindings)
import OnnxRuntimeBindings
#endif

nonisolated final class GreekPaddleOCRService: OCREngineProtocol, @unchecked Sendable {
    static let shared = GreekPaddleOCRService()

    let name = "paddle-el-v5"

    enum OCRError: LocalizedError {
        case runtimeUnavailable
        case modelsMissing
        case imageConversionFailed
        case unexpectedOutput(String)

        var errorDescription: String? {
            switch self {
            case .runtimeUnavailable: return "ONNX Runtime is not linked into this build."
            case .modelsMissing: return "The Greek OCR models are not in the app bundle."
            case .imageConversionFailed: return "The image could not be converted for OCR."
            case .unexpectedOutput(let detail): return "Unexpected OCR model output: \(detail)"
            }
        }
    }

    // Constants from the models' inference.yml.
    static let detLongSide = 960
    static let detMean: [Float] = [0.485, 0.456, 0.406]
    static let detStd: [Float] = [0.229, 0.224, 0.225]
    static let detThreshold: Float = 0.3
    static let detBoxThreshold: Float = 0.6
    static let detUnclipRatio: Float = 1.5
    static let detMaxCandidates = 1000
    static let recHeight = 48
    static let recMinWidth = 320
    static let recMaxWidth = 3200

    static let detModelName = "PP-OCRv5_mobile_det"
    static let recModelName = "el_PP-OCRv5_mobile_rec"
    static let dictionaryName = "el_dict"

    private let lock = NSLock()
    private var loaded: Loaded?
    private var loadFailed = false

    private struct Loaded {
        #if canImport(OnnxRuntimeBindings)
        let env: ORTEnv
        let det: ORTSession
        let rec: ORTSession
        #endif
        let characters: [String]
    }

    static func resourceURL(_ name: String, _ ext: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext)
            ?? Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "GreekOCR")
            ?? OpenIntelligenceResourceBundle.url(forResource: name, withExtension: ext)
    }

    var isAvailable: Bool {
        #if canImport(OnnxRuntimeBindings)
        return Self.resourceURL(Self.detModelName, "onnx") != nil
            && Self.resourceURL(Self.recModelName, "onnx") != nil
            && Self.resourceURL(Self.dictionaryName, "txt") != nil
        #else
        return false
        #endif
    }

    private func load() throws -> Loaded {
        lock.lock()
        defer { lock.unlock() }
        if let loaded { return loaded }
        #if canImport(OnnxRuntimeBindings)
        guard !loadFailed,
              let detURL = Self.resourceURL(Self.detModelName, "onnx"),
              let recURL = Self.resourceURL(Self.recModelName, "onnx"),
              let dictURL = Self.resourceURL(Self.dictionaryName, "txt")
        else {
            throw OCRError.modelsMissing
        }
        do {
            let env = try ORTEnv(loggingLevel: .warning)
            let options = try ORTSessionOptions()
            try options.setGraphOptimizationLevel(.all)
            try options.setIntraOpNumThreads(2)
            let det = try ORTSession(env: env, modelPath: detURL.path, sessionOptions: options)
            let rec = try ORTSession(env: env, modelPath: recURL.path, sessionOptions: options)
            let dictionary = try String(contentsOf: dictURL, encoding: .utf8)
            var characters = dictionary.components(separatedBy: "\n")
            if characters.last == "" { characters.removeLast() }
            let result = Loaded(env: env, det: det, rec: rec, characters: characters)
            loaded = result
            Log.info("[GreekOCR] Loaded PP-OCRv5 det + el rec (\(characters.count) characters)", category: .ingestion)
            return result
        } catch {
            loadFailed = true
            throw error
        }
        #else
        throw OCRError.runtimeUnavailable
        #endif
    }

    // MARK: - Recognition

    func recognizeLines(in image: CGImage) async throws -> [OCRTextLine] {
        let models = try load()
        guard let pixels = RGBPixels(image: image) else { throw OCRError.imageConversionFailed }
        let boxes = try detect(pixels: pixels, models: models)
        let bounds = CGRect(x: 0, y: 0, width: pixels.width, height: pixels.height)
        var lines: [OCRTextLine] = []
        lines.reserveCapacity(boxes.count)
        for box in boxes {
            guard let (text, confidence) = try recognize(pixels: pixels, box: box, models: models) else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let rect = box.boundingRect.intersection(bounds)
            lines.append(OCRTextLine(
                text: trimmed,
                box: CGRect(
                    x: rect.minX / CGFloat(pixels.width), y: rect.minY / CGFloat(pixels.height),
                    width: rect.width / CGFloat(pixels.width), height: rect.height / CGFloat(pixels.height)
                ),
                confidence: confidence
            ))
        }
        return lines
    }

    /// Text boxes in pixel coordinates of `pixels`, top-left origin.
    private func detect(pixels: RGBPixels, models: Loaded) throws -> [TextLineBox] {
        #if canImport(OnnxRuntimeBindings)
        let scale = Double(Self.detLongSide) / Double(max(pixels.width, pixels.height))
        func roundTo32(_ value: Double) -> Int { max(32, Int((value / 32).rounded()) * 32) }
        let width = roundTo32(Double(pixels.width) * scale)
        let height = roundTo32(Double(pixels.height) * scale)
        let resized = pixels.resized(width: width, height: height)

        // NCHW, BGR channel order, (x/255 - mean) / std per channel as in NormalizeImage.
        var input = [Float](repeating: 0, count: 3 * width * height)
        let plane = width * height
        for y in 0..<height {
            for x in 0..<width {
                let (r, g, b) = resized.rgb(x: x, y: y)
                let index = y * width + x
                let bgr = [b, g, r]
                for c in 0..<3 {
                    input[c * plane + index] = (Float(bgr[c]) / 255 - Self.detMean[c]) / Self.detStd[c]
                }
            }
        }
        let output = try run(session: models.det, input: input, shape: [1, 3, height, width])
        guard output.values.count >= plane else { throw OCRError.unexpectedOutput("det \(output.shape)") }
        let probabilities = Array(output.values.suffix(plane))

        let scaleX = CGFloat(pixels.width) / CGFloat(width)
        let scaleY = CGFloat(pixels.height) / CGFloat(height)
        let bounds = CGRect(x: 0, y: 0, width: pixels.width, height: pixels.height)
        return Self.dbBoxes(probabilities: probabilities, width: width, height: height, scaleX: scaleX, scaleY: scaleY)
            .filter { box in
                let visible = box.boundingRect.intersection(bounds)
                return visible.width >= 3 && visible.height >= 3
            }
        #else
        throw OCRError.runtimeUnavailable
        #endif
    }

    /// A line that leans more than this is read straight: tilted pages lean by a few degrees, and a
    /// steeper principal axis is more likely a short or square region (a digit, a stamp) than text.
    static let maxLineAngle: CGFloat = 15 * .pi / 180

    /// A line whose rise from end to end is less than this share of its thickness is read straight,
    /// with the exact crop used before. The principal axis of a level line still leans by a few
    /// tenths of a degree (letter shapes), a rise of at most 0.23 of the thickness on the benchmark's
    /// clean pages, while lines on a page tilted by 0.5° rise by about a third of their thickness.
    static let minLineRise: CGFloat = 0.25

    /// DB post-processing: threshold, 4-connected regions, mean probability of each region against
    /// the box threshold. Each region becomes a rectangle along its principal axis (its length and
    /// thickness measured along and across that axis), grown on every side by
    /// area * unclip / perimeter as PaddleOCR's unclip does. A box along the line keeps a tilted
    /// line apart from its neighbours; an axis-aligned box around a line tilted by 1.5° is almost
    /// twice the line's height and took in parts of the lines above and below (FORK_CHANGES 2.11.22).
    /// `scaleX` and `scaleY` map the probability map's pixels to the image's.
    static func dbBoxes(probabilities: [Float], width: Int, height: Int,
                        scaleX: CGFloat = 1, scaleY: CGFloat = 1) -> [TextLineBox] {
        var visited = [Bool](repeating: false, count: probabilities.count)
        var boxes: [(box: TextLineBox, score: Float)] = []
        var stack: [Int] = []
        var region: [Int] = []
        for start in 0..<probabilities.count where !visited[start] && probabilities[start] > detThreshold {
            var minX = width, minY = height, maxX = 0, maxY = 0
            var sum: Float = 0
            region.removeAll(keepingCapacity: true)
            stack.append(start)
            visited[start] = true
            while let index = stack.popLast() {
                let x = index % width, y = index / width
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                sum += probabilities[index]
                region.append(index)
                for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
                where nx >= 0 && ny >= 0 && nx < width && ny < height {
                    let n = ny * width + nx
                    if !visited[n] && probabilities[n] > detThreshold {
                        visited[n] = true
                        stack.append(n)
                    }
                }
            }
            guard min(maxX - minX + 1, maxY - minY + 1) >= 3, region.count >= 4 else { continue }
            let score = sum / Float(region.count)
            guard score >= detBoxThreshold else { continue }

            // Pixel centres in image coordinates, their mean and covariance.
            func point(_ index: Int) -> (x: CGFloat, y: CGFloat) {
                ((CGFloat(index % width) + 0.5) * scaleX, (CGFloat(index / width) + 0.5) * scaleY)
            }
            var meanX: CGFloat = 0, meanY: CGFloat = 0
            for index in region { let p = point(index); meanX += p.x; meanY += p.y }
            meanX /= CGFloat(region.count); meanY /= CGFloat(region.count)
            var sxx: CGFloat = 0, syy: CGFloat = 0, sxy: CGFloat = 0
            for index in region {
                let p = point(index)
                let dx = p.x - meanX, dy = p.y - meanY
                sxx += dx * dx; syy += dy * dy; sxy += dx * dy
            }
            // Principal axis angle in (-90°, 90°], so the direction points right. Kept only for an
            // elongated region (eigenvalue ratio at least 4, i.e. twice as long as thick).
            var angle = 0.5 * atan2(2 * sxy, sxx - syy)
            let spread = ((sxx - syy) * (sxx - syy) + 4 * sxy * sxy).squareRoot()
            let major = (sxx + syy + spread) / 2, minor = (sxx + syy - spread) / 2
            if abs(angle) > maxLineAngle || major < 4 * minor { angle = 0 }

            // Extents along the direction (u) and across it (v), from the mean.
            func extents(_ d: CGVector) -> (minU: CGFloat, maxU: CGFloat, minV: CGFloat, maxV: CGFloat) {
                var minU = CGFloat.infinity, maxU = -CGFloat.infinity
                var minV = CGFloat.infinity, maxV = -CGFloat.infinity
                for index in region {
                    let p = point(index)
                    let dx = p.x - meanX, dy = p.y - meanY
                    let u = dx * d.dx + dy * d.dy
                    let v = -dx * d.dy + dy * d.dx
                    minU = min(minU, u); maxU = max(maxU, u); minV = min(minV, v); maxV = max(maxV, v)
                }
                return (minU, maxU, minV, maxV)
            }
            var direction = CGVector(dx: cos(angle), dy: sin(angle))
            var (minU, maxU, minV, maxV) = extents(direction)
            if angle != 0, (maxU - minU) * abs(direction.dy) < minLineRise * (maxV - minV + scaleY) {
                direction = CGVector(dx: 1, dy: 0)
                (minU, maxU, minV, maxV) = extents(direction)
            }
            // Each pixel centre stands for a whole pixel: add one pixel to each extent.
            let length = maxU - minU + scaleX, thickness = maxV - minV + scaleY
            let distance = length * thickness * CGFloat(detUnclipRatio) / (2 * (length + thickness))
            let midU = (minU + maxU) / 2, midV = (minV + maxV) / 2
            let center = CGPoint(x: meanX + midU * direction.dx - midV * direction.dy,
                                 y: meanY + midU * direction.dy + midV * direction.dx)
            boxes.append((TextLineBox(center: center, direction: direction,
                                      length: length + 2 * distance, thickness: thickness + 2 * distance), score))
        }
        return boxes.sorted { $0.score > $1.score }.prefix(detMaxCandidates).map(\.box)
    }

    private func recognize(pixels: RGBPixels, box: TextLineBox, models: Loaded) throws -> (String, Float)? {
        #if canImport(OnnxRuntimeBindings)
        // A level box is cut out exactly; a tilted one is sampled along the line.
        let crop = box.direction == CGVector(dx: 1, dy: 0) ? pixels.cropped(to: box.boundingRect.integral) : pixels.sampled(along: box)
        guard crop.width > 0, crop.height > 0 else { return nil }
        let targetWidth = min(Self.recMaxWidth, max(1, Int((Double(Self.recHeight) * Double(crop.width) / Double(crop.height)).rounded(.up))))
        let resized = crop.resized(width: targetWidth, height: Self.recHeight)
        let paddedWidth = max(Self.recMinWidth, targetWidth)
        let plane = Self.recHeight * paddedWidth
        // (x/255 - 0.5) / 0.5, zero padding on the right as in PaddleOCR's resize_norm_img.
        var input = [Float](repeating: 0, count: 3 * plane)
        for y in 0..<Self.recHeight {
            for x in 0..<targetWidth {
                let (r, g, b) = resized.rgb(x: x, y: y)
                let index = y * paddedWidth + x
                input[index] = (Float(b) / 255 - 0.5) / 0.5
                input[plane + index] = (Float(g) / 255 - 0.5) / 0.5
                input[2 * plane + index] = (Float(r) / 255 - 0.5) / 0.5
            }
        }
        let output = try run(session: models.rec, input: input, shape: [1, 3, Self.recHeight, paddedWidth])
        guard output.shape.count == 3 else { throw OCRError.unexpectedOutput("rec \(output.shape)") }
        return Self.ctcDecode(output.values, steps: output.shape[1], classes: output.shape[2], characters: models.characters)
        #else
        throw OCRError.runtimeUnavailable
        #endif
    }

    /// Greedy CTC: class 0 is the blank, classes 1...n the dictionary, n+1 the space.
    static func ctcDecode(_ values: [Float], steps: Int, classes: Int, characters: [String]) -> (String, Float) {
        var text = ""
        var confidences: [Float] = []
        var previous = -1
        for t in 0..<steps {
            let row = values[(t * classes)..<((t + 1) * classes)]
            var best = 0
            var bestValue = -Float.infinity
            for (offset, value) in row.enumerated() where value > bestValue {
                best = offset
                bestValue = value
            }
            defer { previous = best }
            guard best != 0, best != previous else { continue }
            let index = best - 1
            text += index < characters.count ? characters[index] : " "
            confidences.append(bestValue)
        }
        let confidence = confidences.isEmpty ? 0 : confidences.reduce(0, +) / Float(confidences.count)
        return (text, confidence)
    }

    #if canImport(OnnxRuntimeBindings)
    private func run(session: ORTSession, input: [Float], shape: [Int]) throws -> (values: [Float], shape: [Int]) {
        let data = input.withUnsafeBufferPointer { NSMutableData(bytes: $0.baseAddress, length: $0.count * MemoryLayout<Float>.size) }
        let tensor = try ORTValue(tensorData: data, elementType: .float, shape: shape.map { NSNumber(value: $0) })
        let inputName = try session.inputNames().first ?? "x"
        let outputName = try session.outputNames().first ?? "fetch_name_0"
        let outputs = try session.run(withInputs: [inputName: tensor], outputNames: [outputName], runOptions: nil)
        guard let value = outputs[outputName] else { throw OCRError.unexpectedOutput("no \(outputName)") }
        let outputShape = try value.tensorTypeAndShapeInfo().shape.map(\.intValue)
        let outputData = try value.tensorData() as Data
        let values = outputData.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        return (values, outputShape)
    }
    #endif
}

// MARK: - Pixels

/// A detected text line in image pixels, top-left origin: a rectangle centred on `center`, its
/// long side along `direction` (a unit vector pointing right along the text).
nonisolated struct TextLineBox: Equatable, Sendable {
    var center: CGPoint
    var direction: CGVector
    var length: CGFloat
    var thickness: CGFloat

    /// The axis-aligned rectangle around the box.
    var boundingRect: CGRect {
        let halfWidth = (abs(direction.dx) * length + abs(direction.dy) * thickness) / 2
        let halfHeight = (abs(direction.dy) * length + abs(direction.dx) * thickness) / 2
        return CGRect(x: center.x - halfWidth, y: center.y - halfHeight, width: 2 * halfWidth, height: 2 * halfHeight)
    }
}

/// An 8-bit RGBA bitmap, top-left origin.
nonisolated struct RGBPixels {
    let width: Int
    let height: Int
    var bytes: [UInt8]

    init(width: Int, height: Int, bytes: [UInt8]) {
        self.width = width
        self.height = height
        self.bytes = bytes
    }

    init?(image: CGImage) {
        self.init(image: image, width: image.width, height: image.height)
    }

    init?(image: CGImage, width: Int, height: Int) {
        guard width > 0, height > 0 else { return nil }
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return false }
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        self.init(width: width, height: height, bytes: bytes)
    }

    func rgb(x: Int, y: Int) -> (UInt8, UInt8, UInt8) {
        let i = (y * width + x) * 4
        return (bytes[i], bytes[i + 1], bytes[i + 2])
    }

    func cropped(to rect: CGRect) -> RGBPixels {
        let x0 = max(0, Int(rect.minX)), y0 = max(0, Int(rect.minY))
        let x1 = min(width, Int(rect.maxX)), y1 = min(height, Int(rect.maxY))
        guard x1 > x0, y1 > y0 else { return RGBPixels(width: 0, height: 0, bytes: []) }
        var out = [UInt8]()
        out.reserveCapacity((x1 - x0) * (y1 - y0) * 4)
        for y in y0..<y1 {
            let start = (y * width + x0) * 4
            out.append(contentsOf: bytes[start..<(start + (x1 - x0) * 4)])
        }
        return RGBPixels(width: x1 - x0, height: y1 - y0, bytes: out)
    }

    /// The box turned level: one output pixel per image pixel along and across the line, sampled
    /// bilinearly, with the image's edge pixels repeated where the box runs off the image. Runs on
    /// raw buffers: with array indexing a Debug build spent seconds per scanned page here.
    func sampled(along box: TextLineBox) -> RGBPixels {
        let outWidth = Int(box.length.rounded()), outHeight = Int(box.thickness.rounded())
        guard outWidth > 0, outHeight > 0, width > 1, height > 1 else { return RGBPixels(width: 0, height: 0, bytes: []) }
        let dx = Double(box.direction.dx), dy = Double(box.direction.dy)
        let cx = Double(box.center.x), cy = Double(box.center.y)
        let width = width, height = height
        var out = [UInt8](repeating: 255, count: outWidth * outHeight * 4)
        bytes.withUnsafeBufferPointer { srcBuffer in
            out.withUnsafeMutableBufferPointer { dstBuffer in
                guard let src = srcBuffer.baseAddress, let dst = dstBuffer.baseAddress else { return }
                for v in 0..<outHeight {
                    let across = Double(v) + 0.5 - Double(outHeight) / 2
                    for u in 0..<outWidth {
                        let along = Double(u) + 0.5 - Double(outWidth) / 2
                        // Source position, shifted by half a pixel to index pixel centres.
                        let fx = cx + along * dx - across * dy - 0.5
                        let fy = cy + along * dy + across * dx - 0.5
                        let x0 = min(width - 2, max(0, Int(fx.rounded(.down))))
                        let y0 = min(height - 2, max(0, Int(fy.rounded(.down))))
                        let wx = min(1, max(0, fx - Double(x0))), wy = min(1, max(0, fy - Double(y0)))
                        let i00 = (y0 * width + x0) * 4, i10 = i00 + 4
                        let i01 = i00 + width * 4, i11 = i01 + 4
                        let o = (v * outWidth + u) * 4
                        for c in 0..<3 {
                            let a = Double(src[i00 + c]), b = Double(src[i10 + c])
                            let e = Double(src[i01 + c]), f = Double(src[i11 + c])
                            let top = a + (b - a) * wx, bottom = e + (f - e) * wx
                            dst[o + c] = UInt8(max(0, min(255, (top + (bottom - top) * wy).rounded())))
                        }
                    }
                }
            }
        }
        return RGBPixels(width: outWidth, height: outHeight, bytes: out)
    }

    /// Bilinear resize.
    func resized(width newWidth: Int, height newHeight: Int) -> RGBPixels {
        guard newWidth != width || newHeight != height else { return self }
        var out = [UInt8](repeating: 0, count: newWidth * newHeight * 4)
        let sx = Double(width) / Double(newWidth), sy = Double(height) / Double(newHeight)
        for y in 0..<newHeight {
            let fy = max(0, (Double(y) + 0.5) * sy - 0.5)
            let y0 = min(height - 1, Int(fy)), y1 = min(height - 1, y0 + 1)
            let wy = fy - Double(y0)
            for x in 0..<newWidth {
                let fx = max(0, (Double(x) + 0.5) * sx - 0.5)
                let x0 = min(width - 1, Int(fx)), x1 = min(width - 1, x0 + 1)
                let wx = fx - Double(x0)
                for c in 0..<3 {
                    let a = Double(bytes[(y0 * width + x0) * 4 + c]), b = Double(bytes[(y0 * width + x1) * 4 + c])
                    let d = Double(bytes[(y1 * width + x0) * 4 + c]), e = Double(bytes[(y1 * width + x1) * 4 + c])
                    let top = a + (b - a) * wx, bottom = d + (e - d) * wx
                    out[(y * newWidth + x) * 4 + c] = UInt8(max(0, min(255, (top + (bottom - top) * wy).rounded())))
                }
                out[(y * newWidth + x) * 4 + 3] = 255
            }
        }
        return RGBPixels(width: newWidth, height: newHeight, bytes: out)
    }
}
