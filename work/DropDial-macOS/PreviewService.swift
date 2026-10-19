import AppKit
import QuickLookThumbnailing
import PDFKit
import AVFoundation

final class PreviewService {
    static let shared = PreviewService()
    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 100
    }

    /// Fetches or generates a preview for any file type (Images, Videos, PDFs, Audio, Office, Archives)
    func loadPreview(for path: String, targetSize: CGSize = CGSize(width: 880, height: 520), completion: @escaping (NSImage?) -> Void) {
        let cacheKey = path as NSString
        if let cached = cache.object(forKey: cacheKey) {
            completion(cached)
            return
        }

        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()

        // 1. Direct Image loading (JPEG, PNG, WebP, HEIC, TIFF, GIF, BMP, SVG)
        if Catalog.imageExts.contains(ext) {
            if let img = NSImage(contentsOf: url) {
                cache.setObject(img, forKey: cacheKey)
                completion(img)
                return
            }
            if let src = CGImageSourceCreateWithURL(url as CFURL, nil),
               let cgImg = CGImageSourceCreateImageAtIndex(src, 0, nil) {
                let img = NSImage(cgImage: cgImg, size: NSSize(width: cgImg.width, height: cgImg.height))
                cache.setObject(img, forKey: cacheKey)
                completion(img)
                return
            }
        }

        // 2. PDF Document First Page Rendering (Instant & Sharp via PDFKit)
        if ext == "pdf" {
            if let doc = PDFDocument(url: url), let page = doc.page(at: 0) {
                let thumb = page.thumbnail(of: targetSize, for: .mediaBox)
                cache.setObject(thumb, forKey: cacheKey)
                completion(thumb)
                return
            }
        }

        // 3. Video Frame Extraction (AVFoundation)
        if Catalog.videoExts.contains(ext) {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = targetSize

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let time = CMTime(seconds: 1.0, preferredTimescale: 60)
                if let cgImg = try? generator.copyCGImage(at: time, actualTime: nil) {
                    let img = NSImage(cgImage: cgImg, size: NSSize(width: cgImg.width, height: cgImg.height))
                    self?.cache.setObject(img, forKey: cacheKey)
                    DispatchQueue.main.async {
                        completion(img)
                    }
                    return
                }

                // If 1.0s failed (e.g. video shorter than 1s), try 0.0s
                let zeroTime = CMTime.zero
                if let cgImg = try? generator.copyCGImage(at: zeroTime, actualTime: nil) {
                    let img = NSImage(cgImage: cgImg, size: NSSize(width: cgImg.width, height: cgImg.height))
                    self?.cache.setObject(img, forKey: cacheKey)
                    DispatchQueue.main.async {
                        completion(img)
                    }
                    return
                }

                // Fallback to QLThumbnail
                self?.requestQuickLookThumbnail(for: url, targetSize: targetSize, completion: completion)
            }
            return
        }

        // 4. Text & Code Documents (Instant Monospace Preview Card)
        let textExts: Set<String> = ["txt", "md", "markdown", "json", "csv", "tsv", "py", "js", "ts", "html", "htm", "css", "xml", "yaml", "yml", "sh", "bash", "swift", "c", "cpp", "h", "cs", "log", "rtf", "sql"]
        if textExts.contains(ext) {
            let img = renderDocumentPreview(for: url, targetSize: targetSize)
            cache.setObject(img, forKey: cacheKey)
            completion(img)
            return
        }

        // 5. QuickLook Thumbnailing with Rich Universal Card Fallback
        requestQuickLookThumbnail(for: url, targetSize: targetSize, completion: completion)
    }

    private func requestQuickLookThumbnail(for url: URL, targetSize: CGSize, completion: @escaping (NSImage?) -> Void) {
        let cacheKey = url.path as NSString
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let req = QLThumbnailGenerator.Request(fileAt: url, size: targetSize, scale: scale, representationTypes: .all)

        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { [weak self] rep, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let rep = rep {
                    let img = rep.nsImage
                    self.cache.setObject(img, forKey: cacheKey)
                    completion(img)
                } else {
                    let card = self.renderUniversalCard(for: url, targetSize: targetSize)
                    self.cache.setObject(card, forKey: cacheKey)
                    completion(card)
                }
            }
        }
    }

    private func renderDocumentPreview(for url: URL, targetSize: CGSize) -> NSImage {
        let img = NSImage(size: targetSize)
        img.lockFocus()

        let bgRect = NSRect(origin: .zero, size: targetSize)
        NSColor(red: 0.11, green: 0.12, blue: 0.15, alpha: 1.0).setFill()
        bgRect.fill()

        let topBarRect = NSRect(x: 0, y: targetSize.height - 44, width: targetSize.width, height: 44)
        NSColor(red: 0.16, green: 0.18, blue: 0.22, alpha: 1.0).setFill()
        topBarRect.fill()

        let dotColors: [NSColor] = [
            NSColor(red: 1.0, green: 0.38, blue: 0.35, alpha: 1.0),
            NSColor(red: 1.0, green: 0.75, blue: 0.25, alpha: 1.0),
            NSColor(red: 0.28, green: 0.82, blue: 0.40, alpha: 1.0)
        ]
        for (i, c) in dotColors.enumerated() {
            c.setFill()
            let dot = NSBezierPath(ovalIn: NSRect(x: 18 + CGFloat(i) * 18, y: targetSize.height - 28, width: 10, height: 10))
            dot.fill()
        }

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor(white: 0.9, alpha: 1.0)
        ]
        let titleStr = NSString(string: "\(url.pathExtension.uppercased())  •  \(url.lastPathComponent)")
        titleStr.draw(at: NSPoint(x: 80, y: targetSize.height - 30), withAttributes: titleAttrs)

        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let sz = attrs[.size] as? Int64 {
            let szStr = ByteCountFormatter.string(fromByteCount: sz, countStyle: .file)
            let szAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor(white: 0.65, alpha: 1.0)
            ]
            let str = NSString(string: szStr)
            str.draw(at: NSPoint(x: targetSize.width - 120, y: targetSize.height - 29), withAttributes: szAttrs)
        }

        let textFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let numFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let lineAttrs: [NSAttributedString.Key: Any] = [
            .font: textFont,
            .foregroundColor: NSColor(red: 0.85, green: 0.88, blue: 0.92, alpha: 1.0)
        ]
        let numAttrs: [NSAttributedString.Key: Any] = [
            .font: numFont,
            .foregroundColor: NSColor(red: 0.45, green: 0.48, blue: 0.55, alpha: 1.0)
        ]

        if let data = try? Data(contentsOf: url, options: .mappedIfSafe),
           let text = String(data: data.prefix(16384), encoding: .utf8) ?? String(data: data.prefix(16384), encoding: .ascii) {
            let lines = text.components(separatedBy: .newlines)
            var y = targetSize.height - 68
            for (idx, line) in lines.prefix(25).enumerated() {
                let numStr = NSString(string: String(format: "%2d", idx + 1))
                numStr.draw(at: NSPoint(x: 20, y: y), withAttributes: numAttrs)
                let contentStr = NSString(string: String(line.prefix(110)))
                contentStr.draw(at: NSPoint(x: 52, y: y), withAttributes: lineAttrs)
                y -= 17
            }
        }

        img.unlockFocus()
        return img
    }

    private func renderUniversalCard(for url: URL, targetSize: CGSize) -> NSImage {
        let img = NSImage(size: targetSize)
        img.lockFocus()

        let bgRect = NSRect(origin: .zero, size: targetSize)
        NSColor(red: 0.12, green: 0.14, blue: 0.17, alpha: 1.0).setFill()
        bgRect.fill()

        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 96, height: 96)
        icon.draw(in: NSRect(x: targetSize.width / 2 - 48, y: targetSize.height / 2 + 10, width: 96, height: 96))

        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let nameStr = NSString(string: url.lastPathComponent)
        let nameSize = nameStr.size(withAttributes: nameAttrs)
        nameStr.draw(at: NSPoint(x: (targetSize.width - nameSize.width) / 2, y: targetSize.height / 2 - 30), withAttributes: nameAttrs)

        var sub = "\(url.pathExtension.uppercased()) File"
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let sz = attrs[.size] as? Int64 {
            sub += " • \(ByteCountFormatter.string(fromByteCount: sz, countStyle: .file))"
        }
        let subAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor(white: 0.65, alpha: 1.0)
        ]
        let subStr = NSString(string: sub)
        let subSize = subStr.size(withAttributes: subAttrs)
        subStr.draw(at: NSPoint(x: (targetSize.width - subSize.width) / 2, y: targetSize.height / 2 - 54), withAttributes: subAttrs)

        img.unlockFocus()
        return img
    }

    // MARK: - Live Crop Transformation
    func crop(image: NSImage, ratio: String, alignment: String) -> NSImage {
        guard ratio != "free" && !ratio.isEmpty else { return image }
        let parts = ratio.split(separator: ":").compactMap { Double($0) }
        guard parts.count == 2, parts[0] > 0, parts[1] > 0 else { return image }

        let targetAspect = parts[0] / parts[1]
        let rep = image.representations.first
        let srcW = Double(rep?.pixelsWide ?? Int(image.size.width))
        let srcH = Double(rep?.pixelsHigh ?? Int(image.size.height))

        guard srcW > 0, srcH > 0 else { return image }

        var cropW = srcW
        var cropH = srcH

        if (srcW / srcH) > targetAspect {
            cropW = srcH * targetAspect
        } else {
            cropH = srcW / targetAspect
        }

        var x: Double = 0
        var y: Double = 0

        switch alignment {
        case "top_left", "left":
            x = 0
            y = srcH - cropH
        case "bottom_right", "right":
            x = srcW - cropW
            y = 0
        default: // center
            x = (srcW - cropW) / 2.0
            y = (srcH - cropH) / 2.0
        }

        let resultSize = NSSize(width: cropW, height: cropH)
        let cropped = NSImage(size: resultSize)
        cropped.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: resultSize),
            from: NSRect(x: x, y: y, width: cropW, height: cropH),
            operation: .copy,
            fraction: 1.0
        )
        cropped.unlockFocus()
        return cropped
    }

    // MARK: - Live Compression Simulation
    func compress(image: NSImage, quality: Int) -> (NSImage, Int64)? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            return nil
        }

        let factor = max(0.1, min(1.0, Double(quality) / 100.0))
        guard let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: factor]) else {
            return nil
        }

        if let compressedImg = NSImage(data: jpegData) {
            return (compressedImg, Int64(jpegData.count))
        }
        return nil
    }
}
