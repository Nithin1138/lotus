import Foundation

// MARK: - Localization (Pure English)
enum L {
    static func T(_ text: String) -> String {
        return text
    }
}

// MARK: - Models
struct ConversionJob: Codable {
    let Paths: [String]
    let Action: String
    var Parameters: [String: String]?
}

struct JobProgress: Codable {
    let Phase: String?
    let Processed: Int?
    let Total: Int?
    let Current: String?
}

struct FileResult: Codable {
    let Input: String
    let Output: String?
    let Error: String?
}

struct BatchResult: Codable {
    let Files: [FileResult]
}

struct InspectResult: Codable {
    let Kind: String?
    let Preview: String?
    let Width: Double?
    let Height: Double?
    let Duration: Double?
    let FrameRate: Double?
    let Pages: Int?
}

// MARK: - Category & Operations Catalog
enum Catalog {
    static let imageExts: Set<String> = ["jpg", "jpeg", "png", "webp", "heic", "heif", "tif", "tiff", "svg", "avif", "bmp"]
    static let videoExts: Set<String> = ["mp4", "mov", "mkv", "webm", "avi", "wmv", "gif"]
    static let audioExts: Set<String> = ["mp3", "m4a", "wav", "flac", "ogg", "opus", "aiff", "aif", "wma"]
    static let docExts: Set<String> = ["pdf", "txt", "srt", "vtt", "md", "markdown"]
    static let officeExts: Set<String> = ["ppt", "pptx", "pptm", "pps", "ppsx", "odp", "doc", "docx", "docm", "rtf", "odt", "xls", "xlsx", "xlsm", "xlsb", "ods", "csv", "tsv", "pages", "key", "numbers"]
    static let archiveExts: Set<String> = ["zip", "tar", "gz", "tgz", "rar", "7z"]

    static func category(for path: String) -> String {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        if imageExts.contains(ext) { return "image" }
        if videoExts.contains(ext) { return "video" }
        if audioExts.contains(ext) { return "audio" }
        if officeExts.contains(ext) { return "office" }
        if docExts.contains(ext) { return "document" }
        return "archive"
    }

    static func targetFormats(for path: String) -> [String] {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        if ext == "md" || ext == "markdown" {
            // Markdown -> PDF, DOCX, HTML, TXT
            return ["pdf", "docx", "html", "txt"]
        }
        if ext == "pdf" {
            // PDF -> DOCX (Word), TXT, PNG, JPG
            return ["docx", "txt", "png", "jpg"]
        }
        if ext == "pages" {
            // Apple Pages -> PDF, DOCX (Word), TXT
            return ["pdf", "docx", "txt"]
        }
        if ext == "key" {
            // Apple Keynote -> PDF, PPTX
            return ["pdf", "pptx"]
        }
        if ext == "numbers" {
            // Apple Numbers -> PDF, XLSX, CSV
            return ["pdf", "xlsx", "csv"]
        }
        if ["docx", "doc", "odt", "rtf", "docm"].contains(ext) {
            // Word / DOCX -> PDF, TXT
            return ["pdf", "txt"]
        }
        if ["pptx", "ppt", "ppsx", "odp"].contains(ext) {
            return ["pdf", "txt"]
        }
        if ["xlsx", "xls", "ods", "csv", "tsv"].contains(ext) {
            return ["pdf", "csv", "xlsx"]
        }
        if ext == "txt" {
            return ["md", "pdf", "docx", "png"]
        }
        return targetFormats(forCategory: category(for: path))
    }

    static func targetFormats(forCategory category: String) -> [String] {
        switch category {
        case "image":
            return ["jpg", "png", "webp", "heic", "tiff", "avif", "bmp", "pdf"]
        case "video":
            return ["mp4", "mov", "mkv", "webm", "avi", "gif"]
        case "audio":
            return ["mp3", "m4a", "wav", "flac", "ogg", "opus", "aiff"]
        case "document":
            return ["pdf", "docx", "md", "txt", "png", "html"]
        case "office":
            return ["pdf", "docx", "pptx", "xlsx", "txt"]
        default:
            return ["zip", "tar", "gz", "7z"]
        }
    }

    struct ToolField {
        let name: String
        let label: String
        let defaultValue: String
        let kind: String
        let choices: [String]?
    }

    struct ActionOption {
        let id: String
        let title: String
        let label: String
        let iconName: String
        let description: String
    }

    static let fileActions: [ActionOption] = [
        ActionOption(id: "action:airDrop", title: "AIRDROP", label: "AirDrop", iconName: "airplayaudio", description: "Share files through macOS recipient picker"),
        ActionOption(id: "action:float", title: "FLOAT", label: "Float", iconName: "pin.fill", description: "Keep files in a floating shelf at screen edge"),
        ActionOption(id: "action:copy", title: "COPY", label: "Copy", iconName: "doc.on.doc", description: "Copy files to clipboard, ready to paste in Finder"),
        ActionOption(id: "action:move", title: "MOVE", label: "Move", iconName: "folder", description: "Choose a destination folder and move originals there"),
        ActionOption(id: "action:copyPath", title: "COPY PATH", label: "Copy Path", iconName: "doc.text", description: "Copy full file paths as text to clipboard"),
        ActionOption(id: "action:openTerminal", title: "TERMINAL", label: "Terminal", iconName: "terminal", description: "Open folder in Terminal or iTerm2")
    ]

    static func multiFileTools(for paths: [String]) -> [ToolOption] {
        guard paths.count > 1 else { return [] }
        let exts = Set(paths.map { URL(fileURLWithPath: $0).pathExtension.lowercased() })
        var options: [ToolOption] = []
        if exts.allSatisfy({ imageExts.contains($0) }) {
            options.append(ToolOption(id: "createPDF", label: "Combine to PDF", iconName: "doc.on.doc", fields: []))
            options.append(ToolOption(id: "createCollage", label: "Make Collage", iconName: "rectangle.3.group", fields: []))
            options.append(ToolOption(id: "compress", label: "Compress All", iconName: "arrow.down.circle", fields: []))
        } else if exts.allSatisfy({ videoExts.contains($0) }) {
            options.append(ToolOption(id: "joinVideos", label: "Join Videos", iconName: "film.stack", fields: []))
            options.append(ToolOption(id: "compress", label: "Compress All", iconName: "arrow.down.circle", fields: []))
        } else if exts.allSatisfy({ $0 == "pdf" }) {
            options.append(ToolOption(id: "mergePDF", label: "Merge PDFs", iconName: "doc.on.doc", fields: []))
            options.append(ToolOption(id: "compress", label: "Compress All", iconName: "arrow.down.circle", fields: []))
        }
        options.append(ToolOption(id: "packArchive", label: "Pack Archive", iconName: "archivebox", fields: []))
        return options
    }

    struct ToolOption {
        let id: String
        let label: String
        let iconName: String
        let fields: [ToolField]
    }

    static func tools(for category: String) -> [ToolOption] {
        switch category {
        case "image":
            return [
                ToolOption(id: "compress", label: "Compress", iconName: "arrow.down.circle", fields: [
                    ToolField(name: "quality", label: "Quality (1-100)", defaultValue: "80", kind: "number", choices: nil)
                ]),
                ToolOption(id: "resizeImage", label: "Resize", iconName: "arrow.up.left.and.arrow.down.right", fields: [
                    ToolField(name: "width", label: "Width (px)", defaultValue: "1920", kind: "number", choices: nil),
                    ToolField(name: "height", label: "Height (px)", defaultValue: "", kind: "number", choices: nil)
                ]),
                ToolOption(id: "cropImage", label: "Crop", iconName: "crop", fields: [
                    ToolField(name: "ratio", label: "Aspect Ratio", defaultValue: "Free Style (Custom Drag)", kind: "select", choices: ["Free Style (Custom Drag)", "1:1 (Square)", "16:9 (Widescreen)", "4:3 (Standard)", "9:16 (Story / Reel)", "3:2 (Classic Photo)", "Original Ratio"])
                ]),
                ToolOption(id: "rotateImage", label: "Rotate", iconName: "rotate.right", fields: [
                    ToolField(name: "angle", label: "Rotation Angle", defaultValue: "90", kind: "select", choices: ["90", "180", "270"])
                ]),
                ToolOption(id: "ocrImage", label: "OCR", iconName: "doc.text.viewfinder", fields: [
                    ToolField(name: "language", label: "Language", defaultValue: "en", kind: "select", choices: ["en", "auto", "zh"]),
                    ToolField(name: "output", label: "Output Format", defaultValue: "pdf", kind: "select", choices: ["pdf", "txt"])
                ]),
                ToolOption(id: "watermark", label: "Watermark", iconName: "text.bubble", fields: [
                    ToolField(name: "text", label: "Watermark Text", defaultValue: "CONFIDENTIAL", kind: "text", choices: nil)
                ]),
                ToolOption(id: "removeMetadata", label: "Metadata", iconName: "eye.slash", fields: []),
                ToolOption(id: "createPDF", label: "To PDF", iconName: "doc.on.doc", fields: [])
            ]
        case "video":
            return [
                ToolOption(id: "compress", label: "Compress", iconName: "arrow.down.circle", fields: [
                    ToolField(name: "crf", label: "CRF (18-32)", defaultValue: "26", kind: "number", choices: nil)
                ]),
                ToolOption(id: "trimVideo", label: "Trim", iconName: "timeline.selection", fields: [
                    ToolField(name: "start", label: "Start (s)", defaultValue: "0", kind: "number", choices: nil),
                    ToolField(name: "end", label: "End (s)", defaultValue: "10", kind: "number", choices: nil)
                ]),
                ToolOption(id: "videoToGif", label: "To GIF", iconName: "photo.on.rectangle.angled", fields: [
                    ToolField(name: "fps", label: "FPS", defaultValue: "15", kind: "select", choices: ["10", "15", "24"]),
                    ToolField(name: "width", label: "Width (px)", defaultValue: "480", kind: "number", choices: nil)
                ]),
                ToolOption(id: "muteVideo", label: "Mute", iconName: "speaker.slash", fields: []),
                ToolOption(id: "changeVideoSpeed", label: "Speed", iconName: "gauge.with.needle", fields: [
                    ToolField(name: "speed", label: "Multiplier", defaultValue: "1.5", kind: "select", choices: ["0.5", "0.75", "1.25", "1.5", "2.0"])
                ]),
                ToolOption(id: "videoSnapshots", label: "Frames", iconName: "photo.stack", fields: [
                    ToolField(name: "count", label: "Frame Count", defaultValue: "5", kind: "number", choices: nil)
                ])
            ]
        case "audio":
            return [
                ToolOption(id: "trimAudio", label: "Trim", iconName: "scissors", fields: [
                    ToolField(name: "start", label: "Start (s)", defaultValue: "0", kind: "number", choices: nil),
                    ToolField(name: "end", label: "End (s)", defaultValue: "30", kind: "number", choices: nil)
                ]),
                ToolOption(id: "normalizeAudio", label: "Normalize", iconName: "waveform", fields: []),
                ToolOption(id: "audioChannels", label: "Channels", iconName: "hifispeaker.2", fields: [
                    ToolField(name: "channels", label: "Channels", defaultValue: "2", kind: "select", choices: ["1 (Mono)", "2 (Stereo)"])
                ]),
                ToolOption(id: "ringtone", label: "Ringtone", iconName: "bell", fields: [])
            ]
        case "document":
            return [
                ToolOption(id: "compress", label: "Compress", iconName: "arrow.down.circle", fields: []),
                ToolOption(id: "splitPDF", label: "Split PDF", iconName: "square.split.2x1", fields: []),
                ToolOption(id: "mergePDF", label: "Merge PDF", iconName: "doc.on.doc", fields: []),
                ToolOption(id: "ocrPDF", label: "OCR", iconName: "doc.text.viewfinder", fields: [
                    ToolField(name: "language", label: "Language", defaultValue: "en", kind: "select", choices: ["en", "auto", "zh"]),
                    ToolField(name: "output", label: "Output Format", defaultValue: "pdf", kind: "select", choices: ["pdf", "txt"])
                ])
            ]
        case "office":
            return [
                ToolOption(id: "createPDF", label: "To PDF", iconName: "doc.on.doc", fields: []),
                ToolOption(id: "removeMetadata", label: "Metadata", iconName: "eye.slash", fields: [])
            ]
        default:
            return [
                ToolOption(id: "extractArchive", label: "Extract", iconName: "archivebox.arrow.up", fields: []),
                ToolOption(id: "packArchive", label: "Pack", iconName: "archivebox", fields: [
                    ToolField(name: "format", label: "Format", defaultValue: "zip", kind: "select", choices: ["zip", "7z", "tar.gz"])
                ])
            ]
        }
    }
}
