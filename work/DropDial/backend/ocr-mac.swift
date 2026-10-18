import Foundation
import Vision
import AppKit
import CoreGraphics
import ImageIO

struct OCRLine: Codable {
    let text: String
    let x: Double
    let y: Double
    let w: Double
    let h: Double
}

struct OCRPage: Codable {
    let width: Double
    let height: Double
    let lines: [OCRLine]
}

final class FastOCR {
    let language: String

    init(language: String) {
        self.language = language
    }

    func recognize(cgImage: CGImage) -> OCRPage {
        let width = Double(cgImage.width)
        let height = Double(cgImage.height)
        var lines: [OCRLine] = []

        let request = VNRecognizeTextRequest { req, err in
            guard let observations = req.results as? [VNRecognizedTextObservation] else { return }
            for obs in observations {
                guard let candidate = obs.topCandidates(1).first else { continue }
                let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                if text.isEmpty { continue }

                let box = obs.boundingBox
                // Vision normalized coordinates (origin at bottom-left) to image pixels (origin top-left)
                let px = box.origin.x * width
                let py = (1.0 - (box.origin.y + box.size.height)) * height
                let pw = box.size.width * width
                let ph = box.size.height * height

                lines.append(OCRLine(text: candidate.string, x: px, y: py, w: pw, h: ph))
            }
        }

        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let lang = language.lowercased()
        if lang == "zh" || lang.starts(with: "zh") {
            request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]
        } else if lang == "en" || lang.starts(with: "en") {
            request.recognitionLanguages = ["en-US"]
        } else if lang != "auto" && !lang.isEmpty {
            request.recognitionLanguages = [language, "en-US"]
        } else {
            // For auto: default English first, then Chinese/system
            if #available(macOS 13.0, *) {
                request.automaticallyDetectsLanguage = true
            }
            request.recognitionLanguages = ["en-US", "zh-Hans"]
        }

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])

        // Natural reading order sorting:
        // Sort top-to-bottom by Y, and for lines on approximately the same horizontal band, left-to-right by X.
        lines.sort { (a, b) -> Bool in
            let yDiff = abs(a.y - b.y)
            let threshold = max(a.h, b.h) * 0.5
            if yDiff < threshold {
                return a.x < b.x
            }
            return a.y < b.y
        }

        return OCRPage(width: width, height: height, lines: lines)
    }

    func loadCGImage(from path: String) -> CGImage? {
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    func renderPDF(from path: String) -> [CGImage] {
        let url = URL(fileURLWithPath: path)
        guard let doc = CGPDFDocument(url as CFURL) else { return [] }
        let pageCount = doc.numberOfPages
        guard pageCount > 0 else { return [] }

        var images: [CGImage] = []
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        for pageIndex in 1...pageCount {
            guard let page = doc.page(at: pageIndex) else { continue }
            let box = page.getBoxRect(.mediaBox)
            let scale: CGFloat = 2.0 // ~144 DPI (fast and crisp)
            let width = max(1, Int(box.width * scale))
            let height = max(1, Int(box.height * scale))

            guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                continue
            }

            // Fill pure white background
            ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

            // Adjust coordinates: PDF origin is bottom-left, CGBitmapContext origin is bottom-left
            ctx.scaleBy(x: scale, y: scale)
            ctx.drawPDFPage(page)

            if let img = ctx.makeImage() {
                images.append(img)
            }
        }
        return images
    }
}

func main() {
    var outPath = ""
    var language = "auto"
    var inputPaths: [String] = []

    var i = 1
    let args = CommandLine.arguments
    while i < args.count {
        let arg = args[i]
        if arg == "-Out" && i + 1 < args.count {
            outPath = args[i + 1]
            i += 2
        } else if arg == "-Language" && i + 1 < args.count {
            language = args[i + 1]
            i += 2
        } else {
            inputPaths.append(arg)
            i += 1
        }
    }

    guard !outPath.isEmpty else {
        fputs("Usage: ocr-mac -Out <path> [-Language <lang>] <file1> <file2>...\n", stderr)
        exit(1)
    }

    let ocr = FastOCR(language: language)
    var imageItems: [CGImage] = []

    for path in inputPaths {
        if path.lowercased().hasSuffix(".pdf") {
            let pdfImages = ocr.renderPDF(from: path)
            imageItems.append(contentsOf: pdfImages)
        } else {
            if let img = ocr.loadCGImage(from: path) {
                imageItems.append(img)
            }
        }
    }

    guard !imageItems.isEmpty else {
        // Output empty array
        let empty: [OCRPage] = []
        if let data = try? JSONEncoder().encode(empty) {
            try? data.write(to: URL(fileURLWithPath: outPath))
        }
        exit(0)
    }

    var pages: [OCRPage?] = Array(repeating: nil, count: imageItems.count)
    let group = DispatchGroup()
    let queue = DispatchQueue(label: "com.dropdial.ocr", attributes: .concurrent)

    for index in 0..<imageItems.count {
        group.enter()
        queue.async {
            let img = imageItems[index]
            let page = ocr.recognize(cgImage: img)
            pages[index] = page
            group.leave()
        }
    }

    group.wait()

    let nonNilPages = pages.compactMap { $0 }
    let encoder = JSONEncoder()
    if let data = try? encoder.encode(nonNilPages) {
        try? data.write(to: URL(fileURLWithPath: outPath))
    }
    exit(0)
}

main()
