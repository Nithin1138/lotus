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

        // 4. QuickLook Thumbnailing (Universal for Office docs, audio, archives, etc.)
        requestQuickLookThumbnail(for: url, targetSize: targetSize, completion: completion)
    }

    private func requestQuickLookThumbnail(for url: URL, targetSize: CGSize, completion: @escaping (NSImage?) -> Void) {
        let cacheKey = url.path as NSString
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let req = QLThumbnailGenerator.Request(fileAt: url, size: targetSize, scale: scale, representationTypes: .all)

        QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { [weak self] rep, _ in
            DispatchQueue.main.async {
                if let rep = rep {
                    let img = rep.nsImage
                    self?.cache.setObject(img, forKey: cacheKey)
                    completion(img)
                } else {
                    // Fallback to macOS system file icon
                    let icon = NSWorkspace.shared.icon(forFile: url.path)
                    icon.size = NSSize(width: 128, height: 128)
                    completion(icon)
                }
            }
        }
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
