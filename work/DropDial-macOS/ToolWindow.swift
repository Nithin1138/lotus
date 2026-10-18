import AppKit
import AVFoundation
import AVKit
import CoreImage

// MARK: - Interactive Crop Overlay View
final class CropOverlayView: NSView {
    enum DragHandle {
        case none
        case move
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight
        case top
        case bottom
        case left
        case right
        case create
    }

    var imageSize: CGSize = .zero {
        didSet {
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }

    var isRedactMode: Bool = false {
        didSet {
            needsDisplay = true
        }
    }

    // Normalized coordinates (0.0 ... 1.0) relative to image:
    // normX: 0.0 = left edge, 1.0 = right edge
    // normY: 0.0 = TOP edge of image, 1.0 = BOTTOM edge of image
    var normX: CGFloat = 0.05
    var normY: CGFloat = 0.05
    var normW: CGFloat = 0.90
    var normH: CGFloat = 0.90

    var currentRatioKey: String = "free"
    var onCropChanged: ((CGRect, String) -> Void)?

    private var activeHandle: DragHandle = .none
    private var dragStartMouse: CGPoint = .zero
    private var initialNormRect: CGRect = .zero

    private let hitTargetSize: CGFloat = 20.0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        autoresizingMask = [.width, .height]
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Display Rect of Aspect-Fitted Image
    var imageDisplayRect: CGRect {
        guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else {
            return bounds
        }
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let fitW = imageSize.width * scale
        let fitH = imageSize.height * scale
        let fitX = (bounds.width - fitW) / 2.0
        let fitY = (bounds.height - fitH) / 2.0
        return CGRect(x: fitX, y: fitY, width: fitW, height: fitH)
    }

    // View coordinate rect for the crop box (AppKit: 0,0 is bottom-left)
    var cropRectInView: CGRect {
        let disp = imageDisplayRect
        let viewW = max(10, normW * disp.width)
        let viewH = max(10, normH * disp.height)
        let viewX = disp.minX + normX * disp.width
        let viewY = (disp.maxY - normY * disp.height) - viewH
        return CGRect(x: viewX, y: viewY, width: viewW, height: viewH)
    }

    // MARK: - Drawing
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard imageSize.width > 0, imageSize.height > 0 else { return }

        let crop = cropRectInView

        if !isRedactMode {
            // 1. Semi-transparent dark scrim outside the crop rectangle
            NSGraphicsContext.saveGraphicsState()
            let scrimPath = NSBezierPath(rect: bounds)
            let cropPath = NSBezierPath(roundedRect: crop, xRadius: 2.0, yRadius: 2.0)
            scrimPath.append(cropPath)
            scrimPath.windingRule = .evenOdd
            NSColor(white: 0.0, alpha: 0.60).setFill()
            scrimPath.fill()
            NSGraphicsContext.restoreGraphicsState()

            // 2. Subtle rule-of-thirds grid
            let thirdW = crop.width / 3.0
            let thirdH = crop.height / 3.0
            let gridPath = NSBezierPath()
            gridPath.move(to: CGPoint(x: crop.minX, y: crop.minY + thirdH))
            gridPath.line(to: CGPoint(x: crop.maxX, y: crop.minY + thirdH))
            gridPath.move(to: CGPoint(x: crop.minX, y: crop.minY + thirdH * 2.0))
            gridPath.line(to: CGPoint(x: crop.maxX, y: crop.minY + thirdH * 2.0))

            gridPath.move(to: CGPoint(x: crop.minX + thirdW, y: crop.minY))
            gridPath.line(to: CGPoint(x: crop.minX + thirdW, y: crop.maxY))
            gridPath.move(to: CGPoint(x: crop.minX + thirdW * 2.0, y: crop.minY))
            gridPath.line(to: CGPoint(x: crop.minX + thirdW * 2.0, y: crop.maxY))

            NSColor(white: 1.0, alpha: 0.35).setStroke()
            gridPath.lineWidth = 1.0
            gridPath.stroke()
        }

        // 3. Crisp Border (DropDial Orange or Red for Redaction)
        let borderColor = isRedactMode ? NSColor(srgbRed: 1.0, green: 0.25, blue: 0.25, alpha: 0.95) : NSColor(srgbRed: 1.0, green: 0.384, blue: 0.031, alpha: 1.0)
        let borderPath = NSBezierPath(roundedRect: crop, xRadius: 2.0, yRadius: 2.0)
        borderColor.setStroke()
        borderPath.lineWidth = 2.0
        borderPath.stroke()

        // 4. 8 Interactive Handles
        let handleFill = NSColor.white
        let cornerSize: CGFloat = 11.0

        // Corner handles
        let corners: [CGPoint] = [
            CGPoint(x: crop.minX, y: crop.maxY), // Top-Left
            CGPoint(x: crop.maxX, y: crop.maxY), // Top-Right
            CGPoint(x: crop.minX, y: crop.minY), // Bottom-Left
            CGPoint(x: crop.maxX, y: crop.minY)  // Bottom-Right
        ]

        for pt in corners {
            let handleRect = CGRect(x: pt.x - cornerSize / 2, y: pt.y - cornerSize / 2, width: cornerSize, height: cornerSize)
            let path = NSBezierPath(roundedRect: handleRect, xRadius: 3.0, yRadius: 3.0)
            handleFill.setFill()
            path.fill()
            borderColor.setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }

        // Edge handles (pills)
        let edgeLong: CGFloat = 16.0
        let edgeThick: CGFloat = 5.0
        let edges: [(CGPoint, Bool)] = [
            (CGPoint(x: crop.midX, y: crop.maxY), true),  // Top
            (CGPoint(x: crop.midX, y: crop.minY), true),  // Bottom
            (CGPoint(x: crop.minX, y: crop.midY), false), // Left
            (CGPoint(x: crop.maxX, y: crop.midY), false)  // Right
        ]

        for (pt, isHorizontal) in edges {
            let w = isHorizontal ? edgeLong : edgeThick
            let h = isHorizontal ? edgeThick : edgeLong
            let handleRect = CGRect(x: pt.x - w / 2, y: pt.y - h / 2, width: w, height: h)
            let path = NSBezierPath(roundedRect: handleRect, xRadius: 2.0, yRadius: 2.0)
            handleFill.setFill()
            path.fill()
            borderColor.setStroke()
            path.lineWidth = 1.0
            path.stroke()
        }
    }

    // MARK: - Hit Testing
    private func hitTestHandle(at point: CGPoint) -> DragHandle {
        let crop = cropRectInView
        let half = hitTargetSize / 2.0

        // Corners
        if CGRect(x: crop.minX - half, y: crop.maxY - half, width: hitTargetSize, height: hitTargetSize).contains(point) { return .topLeft }
        if CGRect(x: crop.maxX - half, y: crop.maxY - half, width: hitTargetSize, height: hitTargetSize).contains(point) { return .topRight }
        if CGRect(x: crop.minX - half, y: crop.minY - half, width: hitTargetSize, height: hitTargetSize).contains(point) { return .bottomLeft }
        if CGRect(x: crop.maxX - half, y: crop.minY - half, width: hitTargetSize, height: hitTargetSize).contains(point) { return .bottomRight }

        // Edges
        if CGRect(x: crop.midX - half, y: crop.maxY - half, width: hitTargetSize, height: hitTargetSize).contains(point) { return .top }
        if CGRect(x: crop.midX - half, y: crop.minY - half, width: hitTargetSize, height: hitTargetSize).contains(point) { return .bottom }
        if CGRect(x: crop.minX - half, y: crop.midY - half, width: hitTargetSize, height: hitTargetSize).contains(point) { return .left }
        if CGRect(x: crop.maxX - half, y: crop.midY - half, width: hitTargetSize, height: hitTargetSize).contains(point) { return .right }

        // Inside crop rectangle
        if crop.contains(point) { return .move }

        // Inside image container -> start creating a new crop box
        if imageDisplayRect.contains(point) { return .create }

        return .none
    }

    // MARK: - Cursors
    override func resetCursorRects() {
        super.resetCursorRects()
        guard imageSize.width > 0, imageSize.height > 0 else { return }

        let crop = cropRectInView
        let half = hitTargetSize / 2.0

        addCursorRect(CGRect(x: crop.minX - half, y: crop.maxY - half, width: hitTargetSize, height: hitTargetSize), cursor: .crosshair)
        addCursorRect(CGRect(x: crop.maxX - half, y: crop.maxY - half, width: hitTargetSize, height: hitTargetSize), cursor: .crosshair)
        addCursorRect(CGRect(x: crop.minX - half, y: crop.minY - half, width: hitTargetSize, height: hitTargetSize), cursor: .crosshair)
        addCursorRect(CGRect(x: crop.maxX - half, y: crop.minY - half, width: hitTargetSize, height: hitTargetSize), cursor: .crosshair)

        addCursorRect(CGRect(x: crop.midX - half, y: crop.maxY - half, width: hitTargetSize, height: hitTargetSize), cursor: .resizeUpDown)
        addCursorRect(CGRect(x: crop.midX - half, y: crop.minY - half, width: hitTargetSize, height: hitTargetSize), cursor: .resizeUpDown)
        addCursorRect(CGRect(x: crop.minX - half, y: crop.midY - half, width: hitTargetSize, height: hitTargetSize), cursor: .resizeLeftRight)
        addCursorRect(CGRect(x: crop.maxX - half, y: crop.midY - half, width: hitTargetSize, height: hitTargetSize), cursor: .resizeLeftRight)

        addCursorRect(crop, cursor: .openHand)
    }

    // MARK: - Mouse Interaction
    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        dragStartMouse = pt
        initialNormRect = CGRect(x: normX, y: normY, width: normW, height: normH)
        activeHandle = hitTestHandle(at: pt)

        if activeHandle == .create {
            let disp = imageDisplayRect
            let clickNormX = max(0, min(1, (pt.x - disp.minX) / disp.width))
            let clickNormY = max(0, min(1, (disp.maxY - pt.y) / disp.height))
            normX = clickNormX
            normY = clickNormY
            normW = 0.02
            normH = 0.02
            initialNormRect = CGRect(x: normX, y: normY, width: normW, height: normH)
            activeHandle = .bottomRight
            currentRatioKey = "free"
            notifyCropChanged()
            needsDisplay = true
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard activeHandle != .none else { return }
        let pt = convert(event.locationInWindow, from: nil)
        let disp = imageDisplayRect
        guard disp.width > 0, disp.height > 0 else { return }

        let dNormX = (pt.x - dragStartMouse.x) / disp.width
        let dNormY = -(pt.y - dragStartMouse.y) / disp.height // Inverted because normY is 0 at top

        if activeHandle == .move {
            var newX = initialNormRect.origin.x + dNormX
            var newY = initialNormRect.origin.y + dNormY
            newX = max(0.0, min(1.0 - normW, newX))
            newY = max(0.0, min(1.0 - normH, newY))
            normX = newX
            normY = newY
            notifyCropChanged()
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
            return
        }

        var left = initialNormRect.origin.x
        var top = initialNormRect.origin.y
        var right = initialNormRect.maxX
        var bottom = initialNormRect.maxY

        let minSize: CGFloat = 0.03

        switch activeHandle {
        case .topLeft:
            left += dNormX
            top += dNormY
        case .topRight:
            right += dNormX
            top += dNormY
        case .bottomLeft:
            left += dNormX
            bottom += dNormY
        case .bottomRight:
            right += dNormX
            bottom += dNormY
        case .top:
            top += dNormY
        case .bottom:
            bottom += dNormY
        case .left:
            left += dNormX
        case .right:
            right += dNormX
        default: break
        }

        left = max(0.0, min(left, right - minSize))
        right = min(1.0, max(right, left + minSize))
        top = max(0.0, min(top, bottom - minSize))
        bottom = min(1.0, max(bottom, top + minSize))

        var curW = right - left
        var curH = bottom - top

        // If fixed ratio is active, preserve aspect ratio constraint
        if let targetAspect = targetAspectRatio() {
            let normRatio = targetAspect * (imageSize.height / imageSize.width)
            if activeHandle == .left || activeHandle == .right {
                curH = min(1.0 - top, curW / normRatio)
                bottom = top + curH
            } else {
                curW = min(1.0 - left, curH * normRatio)
                right = left + curW
            }
        }

        normX = left
        normY = top
        normW = curW
        normH = curH

        notifyCropChanged()
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    override func mouseUp(with event: NSEvent) {
        activeHandle = .none
        notifyCropChanged()
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    // MARK: - Presets & Ratios
    func targetAspectRatio() -> CGFloat? {
        if currentRatioKey == "free" { return nil }
        if currentRatioKey == "original" {
            return imageSize.height > 0 ? imageSize.width / imageSize.height : nil
        }
        let parts = currentRatioKey.split(separator: ":").compactMap { Double($0) }
        guard parts.count == 2, parts[0] > 0, parts[1] > 0 else { return nil }
        return CGFloat(parts[0] / parts[1])
    }

    func applyRatioPreset(_ ratioKey: String, alignment: String = "center") {
        self.currentRatioKey = ratioKey
        guard imageSize.width > 0, imageSize.height > 0 else { return }

        if ratioKey == "free" {
            if normW < 0.05 || normH < 0.05 {
                normX = 0.05; normY = 0.05; normW = 0.90; normH = 0.90
            }
            notifyCropChanged()
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
            return
        }

        guard let targetAspect = targetAspectRatio() else { return }

        let imgAspect = imageSize.width / imageSize.height
        var w: CGFloat = 1.0
        var h: CGFloat = 1.0

        if imgAspect > targetAspect {
            w = targetAspect / imgAspect
            h = 1.0
        } else {
            w = 1.0
            h = imgAspect / targetAspect
        }

        var x: CGFloat = 0.0
        var y: CGFloat = 0.0

        switch alignment {
        case "top_left", "left":
            x = 0.0
            y = 0.0
        case "bottom_right", "right":
            x = 1.0 - w
            y = 1.0 - h
        default: // center
            x = (1.0 - w) / 2.0
            y = (1.0 - h) / 2.0
        }

        normX = max(0.0, min(1.0 - w, x))
        normY = max(0.0, min(1.0 - h, y))
        normW = w
        normH = h

        notifyCropChanged()
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    func applyAlignment(_ alignment: String) {
        applyRatioPreset(currentRatioKey, alignment: alignment)
    }

    func currentPixelRect() -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let px = max(0, min(Int(imageSize.width) - 1, Int(round(normX * imageSize.width))))
        let py = max(0, min(Int(imageSize.height) - 1, Int(round(normY * imageSize.height))))
        let pw = max(1, min(Int(imageSize.width) - px, Int(round(normW * imageSize.width))))
        let ph = max(1, min(Int(imageSize.height) - py, Int(round(normH * imageSize.height))))
        return CGRect(x: px, y: py, width: pw, height: ph)
    }

    func notifyCropChanged() {
        let pixels = currentPixelRect()
        var desc = "Free Style"
        if currentRatioKey == "1:1" { desc = "1:1 Square" }
        else if currentRatioKey == "16:9" { desc = "16:9 Widescreen" }
        else if currentRatioKey == "4:3" { desc = "4:3 Standard" }
        else if currentRatioKey == "9:16" { desc = "9:16 Reel" }
        else if currentRatioKey == "3:2" { desc = "3:2 Classic" }
        else if currentRatioKey == "original" { desc = "Original Ratio" }
        onCropChanged?(pixels, desc)
    }
}

// MARK: - Image Rotation Helper
func rotateImage(_ image: NSImage, by degrees: CGFloat) -> NSImage {
    var deg = degrees.truncatingRemainder(dividingBy: 360)
    if deg < 0 { deg += 360 }
    if deg == 0 { return image }

    let srcSize = image.size
    var newSize = srcSize
    if deg == 90 || deg == 270 {
        newSize = NSSize(width: srcSize.height, height: srcSize.width)
    }

    let rotated = NSImage(size: newSize)
    rotated.lockFocus()
    let transform = NSAffineTransform()
    transform.translateX(by: newSize.width / 2.0, yBy: newSize.height / 2.0)
    transform.rotate(byDegrees: -deg)
    transform.translateX(by: -srcSize.width / 2.0, yBy: -srcSize.height / 2.0)
    transform.concat()
    image.draw(in: NSRect(origin: .zero, size: srcSize), from: .zero, operation: .copy, fraction: 1.0)
    rotated.unlockFocus()
    return rotated
}

// MARK: - Tool Window Controller
final class ToolWindowController: NSWindowController, NSWindowDelegate {
    let paths: [String]
    let tool: Catalog.ToolOption
    var onClose: (() -> Void)?

    private var fieldInputs: [String: NSControl] = [:]
    private var fieldSliders: [String: NSSlider] = [:]
    private var sliderLabels: [String: NSTextField] = [:]
    private var editSliders: [(key: String, label: String, minVal: Double, maxVal: Double, defVal: Double, unit: String, slider: NSSlider, badge: NSTextField)] = []

    private let previewImageView = NSImageView()
    private let cropOverlayView = CropOverlayView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let infoLabel = NSTextField(labelWithString: "")
    private let cropInfoLabel = NSTextField(labelWithString: "")
    private let watermarkInfoLabel = NSTextField(labelWithString: "")
    private let compressInfoLabel = NSTextField(labelWithString: "")

    private var qualityLabel: NSTextField?
    private var qualitySlider: NSSlider?

    // Video Player & Video Studio State
    private var player: AVPlayer?
    private var playerView: AVPlayerView?
    private var playerTimeObserver: Any?
    private var videoDuration: Double = 0.0
    private var currentPlayheadTime: Double = 0.0
    private var isPlayingTrimSelection: Bool = false

    private var activeVideoTab: Int = 0 // 0: Trim, 1: Crop, 2: Split
    private var videoTabControl: NSSegmentedControl?
    private var trimFormView: NSView?
    private var cropFormView: NSView?
    private var splitFormView: NSView?
    private var actionSaveButton: NSButton?

    // Trim Video Controls
    private var trimStartSlider: NSSlider?
    private var trimEndSlider: NSSlider?
    private var trimStartBadge: NSTextField?
    private var trimEndBadge: NSTextField?
    private let trimSummaryLabel = NSTextField(labelWithString: "")

    // Split Video Controls
    private var splitModeSegment: NSSegmentedControl?
    private var splitPoints: [Double] = []
    private var selectedSplitParts: Int = 2
    private var splitCutsStack: NSStackView?
    private var splitCutsListLabel: NSTextField?
    private var addSplitCutButton: NSButton?
    private var splitEqualSummaryLabel: NSTextField?
    private let splitSummaryLabel = NSTextField(labelWithString: "")
    private var splitCutModeContainer: NSView?
    private var splitEqualPartsContainer: NSView?

    private var originalWidth: Int = 0
    private var originalHeight: Int = 0
    private var originalFileSize: Int64 = 0
    private var originalImage: NSImage?
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var previewCIImage: CIImage?

    init(paths: [String], tool: Catalog.ToolOption) {
        self.paths = paths
        self.tool = tool

        let isVideoStudio = (tool.id == "trimVideo" || tool.id == "cropVideo" || tool.id == "splitVideo" || tool.id == "editVideo")
        let winH: CGFloat
        if tool.id == "editImage" {
            winH = 680
        } else if isVideoStudio {
            winH = 650
        } else if tool.id == "frameImage" || tool.id == "annotateImage" || tool.id == "createCollage" || tool.id == "watermark" || tool.id == "compress" {
            winH = 600
        } else {
            winH = 540
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: winH),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        if isVideoStudio {
            window.title = "DropDial · Video Studio"
        } else {
            window.title = "DropDial · " + tool.label
        }
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        super.init(window: window)

        window.delegate = self
        setupUI(winH: winH)
        loadFilePreview()
    }

    required init?(coder: NSCoder) { fatalError() }

    func windowWillClose(_ notification: Notification) {
        if let observer = playerTimeObserver {
            player?.removeTimeObserver(observer)
            playerTimeObserver = nil
        }
        player?.pause()
        player = nil
        NotificationCenter.default.removeObserver(self)
        onClose?()
    }

    private func setupUI(winH: CGFloat) {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true

        // 1. Background Visual Effect View
        let effect = NSVisualEffectView(frame: contentView.bounds)
        effect.autoresizingMask = [.width, .height]
        effect.material = .hudWindow
        effect.blendingMode = .withinWindow
        effect.state = .active
        contentView.addSubview(effect)

        // 2. Interactive Controls Container
        let container = NSView(frame: contentView.bounds)
        container.autoresizingMask = [.width, .height]
        container.wantsLayer = true
        contentView.addSubview(container)

        // Top File Header Card
        let topY = winH - 54
        let iconView = NSImageView(frame: NSRect(x: 20, y: topY, width: 32, height: 32))
        if let first = paths.first {
            iconView.image = NSWorkspace.shared.icon(forFile: first)
        } else {
            iconView.image = NSImage(systemSymbolName: "doc", accessibilityDescription: nil)
        }
        container.addSubview(iconView)

        let fileName = URL(fileURLWithPath: paths.first ?? "").lastPathComponent
        let countSuffix = paths.count > 1 ? " (+\(paths.count - 1) files)" : ""
        titleLabel.frame = NSRect(x: 60, y: topY + 12, width: 400, height: 20)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.stringValue = fileName + countSuffix
        titleLabel.lineBreakMode = .byTruncatingMiddle
        container.addSubview(titleLabel)

        infoLabel.frame = NSRect(x: 60, y: topY - 4, width: 400, height: 16)
        infoLabel.font = NSFont.systemFont(ofSize: 11)
        infoLabel.textColor = NSColor(white: 0.8, alpha: 1.0)
        infoLabel.stringValue = "Loading..."
        container.addSubview(infoLabel)

        // Preview Container Card
        let isVideoStudio = (tool.id == "trimVideo" || tool.id == "cropVideo" || tool.id == "splitVideo" || tool.id == "editVideo")
        let previewH: CGFloat = isVideoStudio ? 240 : ((tool.id == "editImage" || tool.id == "watermark" || tool.id == "compress") ? 220 : 250)
        let previewY = topY - previewH - 12
        let previewContainer = NSView(frame: NSRect(x: 20, y: previewY, width: 440, height: previewH))
        previewContainer.wantsLayer = true
        previewContainer.layer?.backgroundColor = NSColor(white: 0.08, alpha: 0.95).cgColor
        previewContainer.layer?.cornerRadius = 10
        previewContainer.layer?.borderColor = NSColor(white: 1.0, alpha: 0.15).cgColor
        previewContainer.layer?.borderWidth = 1.0

        let imageInset: CGFloat = 10.0
        let imageFrame = previewContainer.bounds.insetBy(dx: imageInset, dy: imageInset)

        previewImageView.frame = imageFrame
        previewImageView.autoresizingMask = [.width, .height]
        previewImageView.imageScaling = .scaleProportionallyUpOrDown
        previewImageView.wantsLayer = true
        previewImageView.layer?.cornerRadius = 6
        previewImageView.layer?.masksToBounds = true
        previewContainer.addSubview(previewImageView)

        // Crop overlay sits on top of image
        cropOverlayView.frame = imageFrame
        cropOverlayView.autoresizingMask = [.width, .height]
        cropOverlayView.isHidden = (tool.id != "cropImage" && tool.id != "cropVideo" && tool.id != "redactImage")
        previewContainer.addSubview(cropOverlayView)

        container.addSubview(previewContainer)

        // Settings Form Container
        let formY: CGFloat = 64
        let formH: CGFloat = previewY - formY - 10
        let formContainer = NSView(frame: NSRect(x: 20, y: formY, width: 440, height: formH))
        formContainer.wantsLayer = true
        container.addSubview(formContainer)

        if isVideoStudio {
            setupVideoStudioForm(in: formContainer)
        } else if tool.id == "cropImage" {
            setupCropForm(in: formContainer)
        } else if tool.id == "redactImage" {
            setupRedactForm(in: formContainer)
        } else if tool.id == "compress" {
            setupCompressForm(in: formContainer)
        } else if tool.id == "watermark" {
            setupWatermarkForm(in: formContainer)
        } else if tool.id == "resizeImage" {
            setupResizeForm(in: formContainer)
        } else if tool.id == "editImage" {
            setupEditImageForm(in: formContainer)
        } else if tool.id == "frameImage" {
            setupFrameForm(in: formContainer)
        } else if tool.id == "annotateImage" {
            setupAnnotateForm(in: formContainer)
        } else if tool.id == "createCollage" {
            setupCollageForm(in: formContainer)
        } else if tool.id == "splitVideo" {
            setupSplitVideoForm(in: formContainer)
        } else if tool.id == "audioToVideo" {
            setupAudioToVideoForm(in: formContainer)
        } else if tool.id == "redactAudio" {
            setupRedactAudioForm(in: formContainer)
        } else if tool.id == "organizePDF" {
            setupOrganizePDFForm(in: formContainer)
        } else {
            setupGenericForm(in: formContainer)
        }

        // Bottom Action Bar
        let cancelButton = NSButton(frame: NSRect(x: 20, y: 16, width: 110, height: 32))
        cancelButton.title = "Cancel"
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}" // Escape
        cancelButton.target = self
        cancelButton.action = #selector(cancelClicked)
        container.addSubview(cancelButton)

        let saveButton = NSButton(frame: NSRect(x: 270, y: 16, width: 190, height: 32))
        saveButton.title = isVideoStudio ? "Save Video" : "Save New File"
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r" // Return
        saveButton.bezelColor = NSColor(srgbRed: 1.0, green: 0.384, blue: 0.031, alpha: 1.0)
        saveButton.contentTintColor = .white
        saveButton.target = self
        saveButton.action = #selector(saveClicked)
        container.addSubview(saveButton)
        self.actionSaveButton = saveButton
    }

    // MARK: - Video Studio Form (Interactive Trim, Crop, Split)
    private func setupVideoStudioForm(in container: NSView) {
        let totalH = container.bounds.height
        let totalW = container.bounds.width

        // 1. Top Tab Segmented Control
        let tabLabels = ["✂️ Trim Clip", "⛶ Crop Frame", "➗ Split Video"]
        let tabs = NSSegmentedControl(labels: tabLabels, trackingMode: .selectOne, target: self, action: #selector(videoTabChanged(_:)))
        tabs.frame = NSRect(x: 0, y: totalH - 32, width: totalW, height: 28)
        tabs.segmentStyle = .texturedRounded

        if tool.id == "cropVideo" {
            tabs.selectedSegment = 1
            activeVideoTab = 1
        } else if tool.id == "splitVideo" {
            tabs.selectedSegment = 2
            activeVideoTab = 2
        } else {
            tabs.selectedSegment = 0
            activeVideoTab = 0
        }
        container.addSubview(tabs)
        self.videoTabControl = tabs

        // 2. Sub-views Container
        let subH = totalH - 42
        let subContainer = NSView(frame: NSRect(x: 0, y: 0, width: totalW, height: subH))
        container.addSubview(subContainer)

        let tView = NSView(frame: subContainer.bounds)
        let cView = NSView(frame: subContainer.bounds)
        let sView = NSView(frame: subContainer.bounds)

        subContainer.addSubview(tView)
        subContainer.addSubview(cView)
        subContainer.addSubview(sView)

        self.trimFormView = tView
        self.cropFormView = cView
        self.splitFormView = sView

        setupTrimVideoSubform(in: tView)
        setupCropVideoSubform(in: cView)
        setupSplitVideoSubform(in: sView)

        switchVideoStudioTab(to: activeVideoTab)
    }

    @objc private func videoTabChanged(_ sender: NSSegmentedControl) {
        switchVideoStudioTab(to: sender.selectedSegment)
    }

    private func switchVideoStudioTab(to tab: Int) {
        activeVideoTab = tab
        trimFormView?.isHidden = (tab != 0)
        cropFormView?.isHidden = (tab != 1)
        splitFormView?.isHidden = (tab != 2)
        cropOverlayView.isHidden = (tab != 1)

        if tab == 0 {
            actionSaveButton?.title = "Save Trimmed Video"
        } else if tab == 1 {
            actionSaveButton?.title = "Save Cropped Video"
            cropOverlayView.notifyCropChanged()
        } else if tab == 2 {
            let partsCount = (splitModeSegment?.selectedSegment == 0) ? (splitPoints.count + 1) : selectedSplitParts
            actionSaveButton?.title = "Export \(partsCount) Split Clips"
        }
    }

    // MARK: - Subform: Trim Video
    private func setupTrimVideoSubform(in container: NSView) {
        let totalH = container.bounds.height

        // Live Trim Summary
        trimSummaryLabel.frame = NSRect(x: 0, y: totalH - 22, width: 440, height: 20)
        trimSummaryLabel.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        trimSummaryLabel.textColor = NSColor(srgbRed: 1.0, green: 0.55, blue: 0.15, alpha: 1.0)
        trimSummaryLabel.stringValue = "Trim Selection: 00:00.0 → 00:10.0  ·  Length: 10.0s"
        container.addSubview(trimSummaryLabel)

        // Row 1: Start Time (In-Point)
        let row1Y = totalH - 56
        let inLabel = NSTextField(labelWithString: "Start (In):")
        inLabel.frame = NSRect(x: 0, y: row1Y, width: 68, height: 20)
        inLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        inLabel.textColor = .white
        container.addSubview(inLabel)

        let startSlider = NSSlider(value: 0.0, minValue: 0.0, maxValue: 10.0, target: self, action: #selector(trimStartSliderMoved(_:)))
        startSlider.frame = NSRect(x: 72, y: row1Y - 2, width: 206, height: 22)
        container.addSubview(startSlider)
        self.trimStartSlider = startSlider

        let startBadge = NSTextField(labelWithString: "00:00.0")
        startBadge.frame = NSRect(x: 286, y: row1Y, width: 66, height: 18)
        startBadge.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        startBadge.textColor = .white
        startBadge.alignment = .center
        startBadge.wantsLayer = true
        startBadge.layer?.backgroundColor = NSColor(white: 0.2, alpha: 0.8).cgColor
        startBadge.layer?.cornerRadius = 4
        container.addSubview(startBadge)
        self.trimStartBadge = startBadge

        let markInBtn = NSButton(title: "⤓ Mark In", target: self, action: #selector(markInClicked))
        markInBtn.frame = NSRect(x: 358, y: row1Y - 2, width: 82, height: 24)
        markInBtn.bezelStyle = .rounded
        markInBtn.font = NSFont.systemFont(ofSize: 11)
        container.addSubview(markInBtn)

        // Row 2: End Time (Out-Point)
        let row2Y = totalH - 90
        let outLabel = NSTextField(labelWithString: "End (Out):")
        outLabel.frame = NSRect(x: 0, y: row2Y, width: 68, height: 20)
        outLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        outLabel.textColor = .white
        container.addSubview(outLabel)

        let endSlider = NSSlider(value: 10.0, minValue: 0.0, maxValue: 10.0, target: self, action: #selector(trimEndSliderMoved(_:)))
        endSlider.frame = NSRect(x: 72, y: row2Y - 2, width: 206, height: 22)
        container.addSubview(endSlider)
        self.trimEndSlider = endSlider

        let endBadge = NSTextField(labelWithString: "00:10.0")
        endBadge.frame = NSRect(x: 286, y: row2Y, width: 66, height: 18)
        endBadge.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        endBadge.textColor = .white
        endBadge.alignment = .center
        endBadge.wantsLayer = true
        endBadge.layer?.backgroundColor = NSColor(white: 0.2, alpha: 0.8).cgColor
        endBadge.layer?.cornerRadius = 4
        container.addSubview(endBadge)
        self.trimEndBadge = endBadge

        let markOutBtn = NSButton(title: "⤓ Mark Out", target: self, action: #selector(markOutClicked))
        markOutBtn.frame = NSRect(x: 358, y: row2Y - 2, width: 82, height: 24)
        markOutBtn.bezelStyle = .rounded
        markOutBtn.font = NSFont.systemFont(ofSize: 11)
        container.addSubview(markOutBtn)

        // Row 3: Actions & Presets
        let row3Y = totalH - 128
        let playBtn = NSButton(title: "▶ Play Trim Selection", target: self, action: #selector(playTrimSelectionClicked))
        playBtn.frame = NSRect(x: 0, y: row3Y, width: 155, height: 26)
        playBtn.bezelStyle = .rounded
        playBtn.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        container.addSubview(playBtn)

        let p15Btn = NSButton(title: "First 15s", target: self, action: #selector(trimPreset15Clicked))
        p15Btn.frame = NSRect(x: 165, y: row3Y, width: 68, height: 26)
        p15Btn.bezelStyle = .rounded
        p15Btn.font = NSFont.systemFont(ofSize: 11)
        container.addSubview(p15Btn)

        let p30Btn = NSButton(title: "First 30s", target: self, action: #selector(trimPreset30Clicked))
        p30Btn.frame = NSRect(x: 237, y: row3Y, width: 68, height: 26)
        p30Btn.bezelStyle = .rounded
        p30Btn.font = NSFont.systemFont(ofSize: 11)
        container.addSubview(p30Btn)

        let pFullBtn = NSButton(title: "Full Video", target: self, action: #selector(trimPresetFullClicked))
        pFullBtn.frame = NSRect(x: 309, y: row3Y, width: 80, height: 26)
        pFullBtn.bezelStyle = .rounded
        pFullBtn.font = NSFont.systemFont(ofSize: 11)
        container.addSubview(pFullBtn)

        // Row 4: Helper tip
        let tip = NSTextField(labelWithString: "💡 Scrub the player above to any frame, then click 'Mark In' or 'Mark Out' to cut.")
        tip.frame = NSRect(x: 0, y: row3Y - 24, width: 440, height: 16)
        tip.font = NSFont.systemFont(ofSize: 10.5)
        tip.textColor = NSColor(white: 0.65, alpha: 1.0)
        container.addSubview(tip)
    }

    // MARK: - Subform: Crop Video
    private func setupCropVideoSubform(in container: NSView) {
        let totalH = container.bounds.height

        // Live Crop Info
        cropInfoLabel.frame = NSRect(x: 0, y: totalH - 22, width: 440, height: 20)
        cropInfoLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        cropInfoLabel.textColor = NSColor(srgbRed: 1.0, green: 0.55, blue: 0.15, alpha: 1.0)
        cropInfoLabel.stringValue = "Crop Area: Free Style · Drag orange handles on video above"
        container.addSubview(cropInfoLabel)

        // Presets Segment
        let row1Y = totalH - 58
        let rLabel = NSTextField(labelWithString: "Aspect Ratio:")
        rLabel.frame = NSRect(x: 0, y: row1Y, width: 85, height: 20)
        rLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        rLabel.textColor = .white
        container.addSubview(rLabel)

        let ratioSegment = NSSegmentedControl(labels: ["Free Style", "16:9", "9:16 Reel", "1:1 Square", "4:3"], trackingMode: .selectOne, target: self, action: #selector(cropPresetSegmentChanged(_:)))
        ratioSegment.frame = NSRect(x: 88, y: row1Y - 2, width: 352, height: 24)
        ratioSegment.segmentStyle = .texturedRounded
        ratioSegment.selectedSegment = 0
        container.addSubview(ratioSegment)

        // Alignment Row
        let row2Y = totalH - 94
        let aLabel = NSTextField(labelWithString: "Align Frame:")
        aLabel.frame = NSRect(x: 0, y: row2Y, width: 85, height: 20)
        aLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        aLabel.textColor = .white
        container.addSubview(aLabel)

        let centerBtn = NSButton(title: "Center", target: self, action: #selector(cropAlignCenterClicked))
        centerBtn.frame = NSRect(x: 88, y: row2Y - 2, width: 75, height: 24)
        centerBtn.bezelStyle = .rounded
        centerBtn.font = NSFont.systemFont(ofSize: 11)
        container.addSubview(centerBtn)

        let leftBtn = NSButton(title: "Left", target: self, action: #selector(cropAlignLeftClicked))
        leftBtn.frame = NSRect(x: 168, y: row2Y - 2, width: 68, height: 24)
        leftBtn.bezelStyle = .rounded
        leftBtn.font = NSFont.systemFont(ofSize: 11)
        container.addSubview(leftBtn)

        let rightBtn = NSButton(title: "Right", target: self, action: #selector(cropAlignRightClicked))
        rightBtn.frame = NSRect(x: 241, y: row2Y - 2, width: 68, height: 24)
        rightBtn.bezelStyle = .rounded
        rightBtn.font = NSFont.systemFont(ofSize: 11)
        container.addSubview(rightBtn)

        let resetBtn = NSButton(title: "Reset Full", target: self, action: #selector(cropResetClicked))
        resetBtn.frame = NSRect(x: 314, y: row2Y - 2, width: 85, height: 24)
        resetBtn.bezelStyle = .rounded
        resetBtn.font = NSFont.systemFont(ofSize: 11)
        container.addSubview(resetBtn)

        // Helper tip
        let tip = NSTextField(labelWithString: "💡 Handles & rule-of-thirds grid appear directly over the video player. Drag corners or edges to reframe.")
        tip.frame = NSRect(x: 0, y: row2Y - 32, width: 440, height: 28)
        tip.font = NSFont.systemFont(ofSize: 10.5)
        tip.textColor = NSColor(white: 0.65, alpha: 1.0)
        container.addSubview(tip)

        cropOverlayView.onCropChanged = { [weak self] (rect, modeDesc) in
            guard let self = self else { return }
            let w = Int(rect.width)
            let h = Int(rect.height)
            self.cropInfoLabel.stringValue = "Crop: \(w) × \(h) px (\(modeDesc)) · Drag handles on video"
        }
    }

    // MARK: - Subform: Split Video
    private func setupSplitVideoSubform(in container: NSView) {
        let totalH = container.bounds.height

        // Mode Switcher
        let modeSegment = NSSegmentedControl(labels: ["✂️ Split at Cuts", "➗ Equal Parts"], trackingMode: .selectOne, target: self, action: #selector(splitModeChanged(_:)))
        modeSegment.frame = NSRect(x: 0, y: totalH - 30, width: 440, height: 26)
        modeSegment.segmentStyle = .texturedRounded
        modeSegment.selectedSegment = 0
        container.addSubview(modeSegment)
        self.splitModeSegment = modeSegment

        let subH = totalH - 38
        let cutContainer = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: subH))
        let equalContainer = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: subH))
        container.addSubview(cutContainer)
        container.addSubview(equalContainer)
        equalContainer.isHidden = true
        self.splitCutModeContainer = cutContainer
        self.splitEqualPartsContainer = equalContainer

        // --- Cuts Mode UI ---
        let addCutBtn = NSButton(title: "+ Add Cut at Playhead (00:00.0)", target: self, action: #selector(addSplitCutClicked))
        addCutBtn.frame = NSRect(x: 0, y: subH - 34, width: 280, height: 28)
        addCutBtn.bezelStyle = .rounded
        addCutBtn.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        cutContainer.addSubview(addCutBtn)
        self.addSplitCutButton = addCutBtn

        let clearBtn = NSButton(title: "Clear Cuts", target: self, action: #selector(clearSplitCutsClicked))
        clearBtn.frame = NSRect(x: 290, y: subH - 34, width: 100, height: 28)
        clearBtn.bezelStyle = .rounded
        clearBtn.font = NSFont.systemFont(ofSize: 11)
        cutContainer.addSubview(clearBtn)

        let cutsLabel = NSTextField(labelWithString: "No cuts yet. Scrub video and click '+ Add Cut at Playhead'")
        cutsLabel.frame = NSRect(x: 0, y: subH - 62, width: 440, height: 20)
        cutsLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        cutsLabel.textColor = .white
        cutContainer.addSubview(cutsLabel)
        self.splitCutsListLabel = cutsLabel

        splitSummaryLabel.frame = NSRect(x: 0, y: subH - 92, width: 440, height: 24)
        splitSummaryLabel.font = NSFont.monospacedSystemFont(ofSize: 11.5, weight: .semibold)
        splitSummaryLabel.textColor = NSColor(srgbRed: 1.0, green: 0.55, blue: 0.15, alpha: 1.0)
        splitSummaryLabel.stringValue = "Output: 1 full clip (add cuts to split)"
        cutContainer.addSubview(splitSummaryLabel)

        let cutTip = NSTextField(labelWithString: "💡 Scrub video player above to any timestamp and click '+ Add Cut'. Output splits into separate video files.")
        cutTip.frame = NSRect(x: 0, y: subH - 124, width: 440, height: 28)
        cutTip.font = NSFont.systemFont(ofSize: 10.5)
        cutTip.textColor = NSColor(white: 0.65, alpha: 1.0)
        cutContainer.addSubview(cutTip)

        // --- Equal Parts Mode UI ---
        let pLabel = NSTextField(labelWithString: "Divide into:")
        pLabel.frame = NSRect(x: 0, y: subH - 32, width: 75, height: 20)
        pLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        pLabel.textColor = .white
        equalContainer.addSubview(pLabel)

        let partsSegment = NSSegmentedControl(labels: ["2 Parts", "3 Parts", "4 Parts", "5 Parts", "6 Parts"], trackingMode: .selectOne, target: self, action: #selector(splitPartsSegmentChanged(_:)))
        partsSegment.frame = NSRect(x: 80, y: subH - 34, width: 360, height: 26)
        partsSegment.segmentStyle = .texturedRounded
        partsSegment.selectedSegment = 0
        equalContainer.addSubview(partsSegment)

        let eqSum = NSTextField(labelWithString: "Output: 2 equal clips of ~0.0s each")
        eqSum.frame = NSRect(x: 0, y: subH - 70, width: 440, height: 24)
        eqSum.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
        eqSum.textColor = NSColor(srgbRed: 1.0, green: 0.55, blue: 0.15, alpha: 1.0)
        equalContainer.addSubview(eqSum)
        self.splitEqualSummaryLabel = eqSum

        let eqTip = NSTextField(labelWithString: "💡 Automatically calculates keyframe-accurate cuts to produce exactly equal duration clips.")
        eqTip.frame = NSRect(x: 0, y: subH - 104, width: 440, height: 28)
        eqTip.font = NSFont.systemFont(ofSize: 10.5)
        eqTip.textColor = NSColor(white: 0.65, alpha: 1.0)
        equalContainer.addSubview(eqTip)
    }

    // MARK: - Video Action Handlers
    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "00:00.0" }
        let totalSec = Int(seconds)
        let mins = totalSec / 60
        let secs = totalSec % 60
        let tenths = Int((seconds - Double(totalSec)) * 10)
        return String(format: "%02d:%02d.%01d", mins, secs, tenths)
    }

    private func seekPlayer(to seconds: Double) {
        let clamped = max(0, min(videoDuration, seconds))
        let cmTime = CMTime(seconds: clamped, preferredTimescale: 600)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func onPlayheadMoved(time: Double) {
        self.currentPlayheadTime = time
        if isPlayingTrimSelection {
            let endT = trimEndSlider?.doubleValue ?? videoDuration
            if time >= endT {
                player?.pause()
                isPlayingTrimSelection = false
            }
        }
        addSplitCutButton?.title = "+ Add Cut at Playhead (\(formatTime(time)))"
    }

    private func setupSliderRanges() {
        guard videoDuration > 0 else { return }
        trimStartSlider?.minValue = 0.0
        trimStartSlider?.maxValue = videoDuration
        trimStartSlider?.doubleValue = 0.0

        trimEndSlider?.minValue = 0.0
        trimEndSlider?.maxValue = videoDuration
        trimEndSlider?.doubleValue = videoDuration

        updateTrimUI()
        updateSplitUI()
    }

    @objc private func trimStartSliderMoved(_ sender: NSSlider) {
        if sender.doubleValue >= (trimEndSlider?.doubleValue ?? videoDuration) {
            trimEndSlider?.doubleValue = min(videoDuration, sender.doubleValue + 0.5)
        }
        seekPlayer(to: sender.doubleValue)
        updateTrimUI()
    }

    @objc private func trimEndSliderMoved(_ sender: NSSlider) {
        if sender.doubleValue <= (trimStartSlider?.doubleValue ?? 0.0) {
            trimStartSlider?.doubleValue = max(0.0, sender.doubleValue - 0.5)
        }
        seekPlayer(to: sender.doubleValue)
        updateTrimUI()
    }

    @objc private func markInClicked() {
        trimStartSlider?.doubleValue = currentPlayheadTime
        if currentPlayheadTime >= (trimEndSlider?.doubleValue ?? videoDuration) {
            trimEndSlider?.doubleValue = min(videoDuration, currentPlayheadTime + 1.0)
        }
        updateTrimUI()
    }

    @objc private func markOutClicked() {
        trimEndSlider?.doubleValue = currentPlayheadTime
        if currentPlayheadTime <= (trimStartSlider?.doubleValue ?? 0.0) {
            trimStartSlider?.doubleValue = max(0.0, currentPlayheadTime - 1.0)
        }
        updateTrimUI()
    }

    @objc private func playTrimSelectionClicked() {
        let start = trimStartSlider?.doubleValue ?? 0.0
        seekPlayer(to: start)
        isPlayingTrimSelection = true
        player?.play()
    }

    @objc private func trimPreset15Clicked() {
        trimStartSlider?.doubleValue = 0.0
        trimEndSlider?.doubleValue = min(videoDuration, 15.0)
        seekPlayer(to: 0.0)
        updateTrimUI()
    }

    @objc private func trimPreset30Clicked() {
        trimStartSlider?.doubleValue = 0.0
        trimEndSlider?.doubleValue = min(videoDuration, 30.0)
        seekPlayer(to: 0.0)
        updateTrimUI()
    }

    @objc private func trimPresetFullClicked() {
        trimStartSlider?.doubleValue = 0.0
        trimEndSlider?.doubleValue = videoDuration
        seekPlayer(to: 0.0)
        updateTrimUI()
    }

    private func updateTrimUI() {
        let start = trimStartSlider?.doubleValue ?? 0.0
        let end = trimEndSlider?.doubleValue ?? videoDuration
        let dur = max(0.0, end - start)
        trimStartBadge?.stringValue = formatTime(start)
        trimEndBadge?.stringValue = formatTime(end)
        trimSummaryLabel.stringValue = "Trim Selection: \(formatTime(start)) → \(formatTime(end))  ·  Length: \(String(format: "%.1fs", dur))"
    }

    @objc private func cropPresetSegmentChanged(_ sender: NSSegmentedControl) {
        let ratios = ["free", "16:9", "9:16", "1:1", "4:3"]
        guard sender.selectedSegment >= 0 && sender.selectedSegment < ratios.count else { return }
        cropOverlayView.applyRatioPreset(ratios[sender.selectedSegment])
    }

    @objc private func cropAlignCenterClicked() {
        cropOverlayView.applyAlignment("center")
    }

    @objc private func cropAlignLeftClicked() {
        cropOverlayView.applyAlignment("left")
    }

    @objc private func cropAlignRightClicked() {
        cropOverlayView.applyAlignment("right")
    }

    @objc private func cropResetClicked() {
        cropOverlayView.applyRatioPreset("original")
    }

    @objc private func splitModeChanged(_ sender: NSSegmentedControl) {
        splitCutModeContainer?.isHidden = (sender.selectedSegment != 0)
        splitEqualPartsContainer?.isHidden = (sender.selectedSegment != 1)
        updateSplitUI()
    }

    @objc private func addSplitCutClicked() {
        let t = round(currentPlayheadTime * 10) / 10.0
        if t > 0.5 && (videoDuration <= 0 || t < videoDuration - 0.5) && !splitPoints.contains(t) {
            splitPoints.append(t)
            splitPoints.sort()
            updateSplitUI()
        }
    }

    @objc private func clearSplitCutsClicked() {
        splitPoints.removeAll()
        updateSplitUI()
    }

    @objc private func splitPartsSegmentChanged(_ sender: NSSegmentedControl) {
        selectedSplitParts = sender.selectedSegment + 2
        updateSplitUI()
    }

    private func updateSplitUI() {
        if splitModeSegment?.selectedSegment == 0 {
            if splitPoints.isEmpty {
                splitCutsListLabel?.stringValue = "No cuts yet. Scrub video and click '+ Add Cut at Playhead'"
                splitSummaryLabel.stringValue = "Output: 1 full clip (add cuts to split)"
                if activeVideoTab == 2 { actionSaveButton?.title = "Export 1 Clip" }
            } else {
                let cutsStr = splitPoints.map { formatTime($0) }.joined(separator: ", ")
                splitCutsListLabel?.stringValue = "Cut points: \(cutsStr)"

                var parts: [String] = []
                var prev = 0.0
                for (i, p) in splitPoints.enumerated() {
                    parts.append("Clip \(i + 1): [\(formatTime(prev))-\(formatTime(p))]")
                    prev = p
                }
                parts.append("Clip \(splitPoints.count + 1): [\(formatTime(prev))-\(formatTime(videoDuration))]")
                splitSummaryLabel.stringValue = parts.joined(separator: "  ·  ")
                if activeVideoTab == 2 { actionSaveButton?.title = "Export \(splitPoints.count + 1) Split Clips" }
            }
        } else {
            let parts = selectedSplitParts
            let partLen = videoDuration > 0 ? (videoDuration / Double(parts)) : 0.0
            splitEqualSummaryLabel?.stringValue = "Output: \(parts) equal clips of ~\(String(format: "%.1fs", partLen)) each"
            if activeVideoTab == 2 { actionSaveButton?.title = "Export \(parts) Split Clips" }
        }
    }

    // MARK: - Crop Form with Free Style and Presets
    private func setupCropForm(in container: NSView) {
        let ratioLabel = NSTextField(labelWithString: "Aspect Ratio:")
        ratioLabel.frame = NSRect(x: 0, y: 92, width: 95, height: 20)
        ratioLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        ratioLabel.textColor = .white
        container.addSubview(ratioLabel)

        let ratioPopup = NSPopUpButton(frame: NSRect(x: 100, y: 90, width: 340, height: 26))
        let ratios = [
            ("Free Style (Custom Drag)", "free"),
            ("1:1 (Square)", "1:1"),
            ("16:9 (Widescreen)", "16:9"),
            ("4:3 (Standard)", "4:3"),
            ("9:16 (Story / Reel)", "9:16"),
            ("3:2 (Classic Photo)", "3:2"),
            ("Original Ratio", "original")
        ]
        for (label, _) in ratios {
            ratioPopup.addItem(withTitle: label)
        }
        ratioPopup.target = self
        ratioPopup.action = #selector(cropParamChanged)
        container.addSubview(ratioPopup)
        fieldInputs["ratio"] = ratioPopup

        let alignLabel = NSTextField(labelWithString: "Alignment:")
        alignLabel.frame = NSRect(x: 0, y: 56, width: 75, height: 20)
        alignLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        alignLabel.textColor = .white
        container.addSubview(alignLabel)

        let alignPopup = NSPopUpButton(frame: NSRect(x: 80, y: 54, width: 135, height: 26))
        alignPopup.addItem(withTitle: "Center (Auto)")
        alignPopup.addItem(withTitle: "Top / Left")
        alignPopup.addItem(withTitle: "Bottom / Right")
        alignPopup.target = self
        alignPopup.action = #selector(cropParamChanged)
        container.addSubview(alignPopup)
        fieldInputs["alignment"] = alignPopup

        let rotLabel = NSTextField(labelWithString: "Rotation:")
        rotLabel.frame = NSRect(x: 228, y: 56, width: 62, height: 20)
        rotLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        rotLabel.textColor = .white
        container.addSubview(rotLabel)

        let rotPopup = NSPopUpButton(frame: NSRect(x: 295, y: 54, width: 145, height: 26))
        rotPopup.addItem(withTitle: "0° (Normal)")
        rotPopup.addItem(withTitle: "90° (Clockwise)")
        rotPopup.addItem(withTitle: "180° (Flip)")
        rotPopup.addItem(withTitle: "270° (Counter-CW)")
        rotPopup.target = self
        rotPopup.action = #selector(cropParamChanged)
        container.addSubview(rotPopup)
        fieldInputs["rotation"] = rotPopup

        cropInfoLabel.frame = NSRect(x: 0, y: 16, width: 440, height: 20)
        cropInfoLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        cropInfoLabel.textColor = NSColor(srgbRed: 1.0, green: 0.384, blue: 0.031, alpha: 1.0)
        cropInfoLabel.stringValue = "Crop Preview: Free Style (Drag handles to adjust)"
        container.addSubview(cropInfoLabel)

        cropOverlayView.onCropChanged = { [weak self] (rect, modeDesc) in
            guard let self = self else { return }
            let w = Int(rect.width)
            let h = Int(rect.height)
            self.cropInfoLabel.stringValue = "Crop Area: \(w) × \(h) (\(modeDesc))  ·  Drag handles to adjust"
        }
    }

    @objc private func cropParamChanged() {
        guard let ratioPopup = fieldInputs["ratio"] as? NSPopUpButton,
              let alignPopup = fieldInputs["alignment"] as? NSPopUpButton else { return }

        let ratioTitle = ratioPopup.titleOfSelectedItem ?? ""
        let alignTitle = alignPopup.titleOfSelectedItem ?? ""

        var ratioVal = "free"
        if ratioTitle.contains("1:1") { ratioVal = "1:1" }
        else if ratioTitle.contains("16:9") { ratioVal = "16:9" }
        else if ratioTitle.contains("4:3") { ratioVal = "4:3" }
        else if ratioTitle.contains("9:16") { ratioVal = "9:16" }
        else if ratioTitle.contains("3:2") { ratioVal = "3:2" }
        else if ratioTitle.contains("Original") { ratioVal = "original" }

        var alignVal = "center"
        if alignTitle.contains("Top") { alignVal = "top_left" }
        else if alignTitle.contains("Bottom") { alignVal = "bottom_right" }

        updateCropRotation()
        cropOverlayView.applyRatioPreset(ratioVal, alignment: alignVal)
    }

    private func updateCropRotation() {
        guard let base = originalImage else { return }
        let rotPopup = fieldInputs["rotation"] as? NSPopUpButton
        let rotTitle = rotPopup?.titleOfSelectedItem ?? "0°"
        var deg: CGFloat = 0
        if rotTitle.contains("90") { deg = 90 }
        else if rotTitle.contains("180") { deg = 180 }
        else if rotTitle.contains("270") { deg = 270 }

        if deg == 0 {
            self.previewImageView.image = base
            self.cropOverlayView.imageSize = CGSize(width: originalWidth, height: originalHeight)
        } else {
            let rotated = rotateImage(base, by: deg)
            self.previewImageView.image = rotated
            let rep = rotated.representations.first
            let w = rep?.pixelsWide ?? Int(rotated.size.width)
            let h = rep?.pixelsHigh ?? Int(rotated.size.height)
            self.cropOverlayView.imageSize = CGSize(width: w, height: h)
        }
    }

    // MARK: - Compression Form
    private func setupCompressForm(in container: NSView) {
        // Row 1: Compression Quality Slider Header
        let label = NSTextField(labelWithString: "Compression Quality:")
        label.frame = NSRect(x: 0, y: 195, width: 180, height: 20)
        label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .white
        container.addSubview(label)

        let qValLabel = NSTextField(labelWithString: "80%")
        qValLabel.frame = NSRect(x: 350, y: 195, width: 90, height: 20)
        qValLabel.alignment = .right
        qValLabel.font = NSFont.systemFont(ofSize: 14, weight: .bold)
        qValLabel.textColor = NSColor(srgbRed: 1.0, green: 0.384, blue: 0.031, alpha: 1.0)
        container.addSubview(qValLabel)
        self.qualityLabel = qValLabel

        // Row 2: Quality Slider
        let slider = NSSlider(value: 80, minValue: 10, maxValue: 100, target: self, action: #selector(sliderChanged(_:)))
        slider.frame = NSRect(x: 0, y: 164, width: 440, height: 24)
        slider.numberOfTickMarks = 10
        slider.allowsTickMarkValuesOnly = false
        slider.isContinuous = true
        container.addSubview(slider)
        self.qualitySlider = slider

        // Row 3: Preset Buttons
        let presets = [("Low (50%)", 50), ("Med (75%)", 75), ("High (80%)", 80), ("Best (95%)", 95)]
        var xOffset: CGFloat = 0
        for (name, val) in presets {
            let btn = NSButton(frame: NSRect(x: xOffset, y: 128, width: 102, height: 26))
            btn.title = name
            btn.bezelStyle = .rounded
            btn.font = NSFont.systemFont(ofSize: 11, weight: .medium)
            btn.tag = val
            btn.target = self
            btn.action = #selector(presetClicked(_:))
            container.addSubview(btn)
            xOffset += 112
        }

        // Row 4: Max Target File Size (Size matters!)
        let targetSizeLabel = NSTextField(labelWithString: "Max Target Size:")
        targetSizeLabel.frame = NSRect(x: 0, y: 88, width: 125, height: 20)
        targetSizeLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        targetSizeLabel.textColor = .white
        container.addSubview(targetSizeLabel)

        let targetSizePopup = NSPopUpButton(frame: NSRect(x: 130, y: 84, width: 190, height: 26))
        let sizes = [
            "Auto (Quality Only)",
            "200 KB",
            "300 KB",
            "500 KB",
            "1 MB",
            "2 MB",
            "5 MB",
            "10 MB",
            "25 MB"
        ]
        for s in sizes { targetSizePopup.addItem(withTitle: s) }
        targetSizePopup.target = self
        targetSizePopup.action = #selector(compressSettingChanged)
        container.addSubview(targetSizePopup)
        fieldInputs["targetSize"] = targetSizePopup

        let targetHintLabel = NSTextField(labelWithString: "Iterative size cap")
        targetHintLabel.frame = NSRect(x: 326, y: 88, width: 114, height: 18)
        targetHintLabel.font = NSFont.systemFont(ofSize: 11)
        targetHintLabel.textColor = NSColor(white: 0.7, alpha: 1.0)
        container.addSubview(targetHintLabel)

        // Row 5: Max Dimensions / Scaling
        let dimLabel = NSTextField(labelWithString: "Max Dimension:")
        dimLabel.frame = NSRect(x: 0, y: 48, width: 125, height: 20)
        dimLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        dimLabel.textColor = .white
        container.addSubview(dimLabel)

        let dimPopup = NSPopUpButton(frame: NSRect(x: 130, y: 44, width: 190, height: 26))
        let dims = [
            "Original (100%)",
            "2560 px (2K)",
            "1920 px (Full HD)",
            "1280 px (Web Ready)",
            "800 px (Compact)"
        ]
        for d in dims { dimPopup.addItem(withTitle: d) }
        dimPopup.target = self
        dimPopup.action = #selector(compressSettingChanged)
        container.addSubview(dimPopup)
        fieldInputs["maxEdge"] = dimPopup

        let dimHintLabel = NSTextField(labelWithString: "Aspect-ratio kept")
        dimHintLabel.frame = NSRect(x: 326, y: 48, width: 114, height: 18)
        dimHintLabel.font = NSFont.systemFont(ofSize: 11)
        dimHintLabel.textColor = NSColor(white: 0.7, alpha: 1.0)
        container.addSubview(dimHintLabel)

        // Row 6: Live size & target feedback label
        compressInfoLabel.frame = NSRect(x: 0, y: 10, width: 440, height: 22)
        compressInfoLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        compressInfoLabel.textColor = NSColor(srgbRed: 1.0, green: 0.7, blue: 0.3, alpha: 1.0)
        container.addSubview(compressInfoLabel)
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        let val = Int(sender.doubleValue)
        qualityLabel?.stringValue = "\(val)%"
        updateCompressPreview(quality: val)
    }

    @objc private func presetClicked(_ sender: NSButton) {
        let val = sender.tag
        qualitySlider?.integerValue = val
        qualitySlider?.doubleValue = Double(val)
        qualityLabel?.stringValue = "\(val)%"
        updateCompressPreview(quality: val)
    }

    @objc private func compressSettingChanged() {
        let q = qualitySlider?.integerValue ?? 80
        updateCompressPreview(quality: q)
    }

    private func updateCompressPreview(quality: Int) {
        guard let base = originalImage else { return }

        var dimScale: Double = 1.0
        if let dimPopup = fieldInputs["maxEdge"] as? NSPopUpButton {
            let t = dimPopup.titleOfSelectedItem ?? ""
            let maxSide = max(originalWidth, originalHeight)
            if t.contains("2560") && maxSide > 2560 { dimScale = 2560.0 / Double(maxSide) }
            else if t.contains("1920") && maxSide > 1920 { dimScale = 1920.0 / Double(maxSide) }
            else if t.contains("1280") && maxSide > 1280 { dimScale = 1280.0 / Double(maxSide) }
            else if t.contains("800") && maxSide > 800 { dimScale = 800.0 / Double(maxSide) }
        }

        let targetW = max(10, Int(Double(originalWidth) * dimScale))
        let targetH = max(10, Int(Double(originalHeight) * dimScale))

        guard let tiffData = base.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiffData) else { return }

        let qFactor = max(0.05, min(1.0, Double(quality) / 100.0))
        let props: [NSBitmapImageRep.PropertyKey: Any] = [
            .compressionFactor: qFactor
        ]

        var compressedRep = rep
        if dimScale < 0.999 {
            if let scaled = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: targetW,
                pixelsHigh: targetH,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            ) {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: scaled)
                base.draw(in: NSRect(x: 0, y: 0, width: targetW, height: targetH))
                NSGraphicsContext.restoreGraphicsState()
                compressedRep = scaled
            }
        }

        if let jpegData = compressedRep.representation(using: .jpeg, properties: props) {
            if let compressedImage = NSImage(data: jpegData) {
                self.previewImageView.image = compressedImage
            }

            let actualSize = Int64(jpegData.count)
            let actualStr = ByteCountFormatter.string(fromByteCount: actualSize, countStyle: .file)
            let origStr = ByteCountFormatter.string(fromByteCount: originalFileSize, countStyle: .file)
            let percent = originalFileSize > 0 ? Int(round((1.0 - Double(actualSize) / Double(originalFileSize)) * 100.0)) : 0
            let savingsStr = percent > 0 ? " (-\(percent)%)" : ""

            var targetKB: Int64 = 0
            if let sizePopup = fieldInputs["targetSize"] as? NSPopUpButton {
                let t = sizePopup.titleOfSelectedItem ?? ""
                if t.contains("200 KB") { targetKB = 200 }
                else if t.contains("300 KB") { targetKB = 300 }
                else if t.contains("500 KB") { targetKB = 500 }
                else if t.contains("1 MB") { targetKB = 1024 }
                else if t.contains("2 MB") { targetKB = 2048 }
                else if t.contains("5 MB") { targetKB = 5120 }
                else if t.contains("10 MB") { targetKB = 10240 }
                else if t.contains("25 MB") { targetKB = 25600 }
            }

            var parts: [String] = []
            if dimScale < 0.999 {
                parts.append("\(originalWidth)×\(originalHeight) → \(targetW)×\(targetH)")
            } else {
                parts.append("\(originalWidth) × \(originalHeight)")
            }
            parts.append("Original: \(origStr)")
            if targetKB > 0 {
                parts.append("Target: ≤ \(ByteCountFormatter.string(fromByteCount: targetKB * 1024, countStyle: .file))")
            }
            parts.append("Est. Size: ~\(actualStr)\(savingsStr)")
            self.infoLabel.stringValue = parts.joined(separator: "  ·  ")
            self.compressInfoLabel.stringValue = parts.joined(separator: "  ·  ")
        }
    }

    // MARK: - Watermark Form
    private func setupWatermarkForm(in container: NSView) {
        // Row 1: Watermark Text
        let textLabel = NSTextField(labelWithString: "Watermark Text:")
        textLabel.frame = NSRect(x: 0, y: 195, width: 120, height: 20)
        textLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        textLabel.textColor = .white
        container.addSubview(textLabel)

        let textField = NSTextField(frame: NSRect(x: 125, y: 192, width: 315, height: 24))
        textField.stringValue = "CONFIDENTIAL"
        textField.placeholderString = "Enter watermark text..."
        textField.target = self
        textField.action = #selector(watermarkParamChanged)
        container.addSubview(textField)
        fieldInputs["text"] = textField

        NotificationCenter.default.addObserver(self, selector: #selector(watermarkTextDidChange(_:)), name: NSControl.textDidChangeNotification, object: textField)

        // Row 2: Repeats and Angle
        let repeatsLabel = NSTextField(labelWithString: "Repeats:")
        repeatsLabel.frame = NSRect(x: 0, y: 150, width: 65, height: 18)
        repeatsLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        repeatsLabel.textColor = .white
        container.addSubview(repeatsLabel)

        let repeatsPopup = NSPopUpButton(frame: NSRect(x: 70, y: 146, width: 155, height: 26))
        let repeatsList = [
            "Single (Center)",
            "Single (Bottom Right)",
            "4 (2×2 Grid)",
            "9 (3×3 Grid)",
            "16 (4×4 Dense Grid)",
            "Tiled Pattern (Full Page)"
        ]
        for r in repeatsList { repeatsPopup.addItem(withTitle: r) }
        repeatsPopup.target = self
        repeatsPopup.action = #selector(watermarkParamChanged)
        container.addSubview(repeatsPopup)
        fieldInputs["repeats"] = repeatsPopup

        let angleLabel = NSTextField(labelWithString: "Angle:")
        angleLabel.frame = NSRect(x: 235, y: 150, width: 50, height: 18)
        angleLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        angleLabel.textColor = .white
        container.addSubview(angleLabel)

        let anglePopup = NSPopUpButton(frame: NSRect(x: 290, y: 146, width: 150, height: 26))
        let angles = [
            "45° (Diagonal)",
            "0° (Horizontal)",
            "30° (Subtle Angle)",
            "-45° (Inverse Diagonal)",
            "90° (Vertical)"
        ]
        for a in angles { anglePopup.addItem(withTitle: a) }
        anglePopup.target = self
        anglePopup.action = #selector(watermarkParamChanged)
        container.addSubview(anglePopup)
        fieldInputs["angle"] = anglePopup

        // Row 3: Text Size and Opacity
        let sizeLabel = NSTextField(labelWithString: "Text Size:")
        sizeLabel.frame = NSRect(x: 0, y: 106, width: 65, height: 18)
        sizeLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        sizeLabel.textColor = .white
        container.addSubview(sizeLabel)

        let sizePopup = NSPopUpButton(frame: NSRect(x: 70, y: 102, width: 155, height: 26))
        let sizes = [
            "18 pt (Small)",
            "32 pt (Medium)",
            "48 pt (Large)",
            "72 pt (Extra Large)",
            "96 pt (Huge)"
        ]
        for s in sizes { sizePopup.addItem(withTitle: s) }
        sizePopup.selectItem(withTitle: "48 pt (Large)")
        sizePopup.target = self
        sizePopup.action = #selector(watermarkParamChanged)
        container.addSubview(sizePopup)
        fieldInputs["size"] = sizePopup

        let opacityLabel = NSTextField(labelWithString: "Opacity:")
        opacityLabel.frame = NSRect(x: 235, y: 106, width: 50, height: 18)
        opacityLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        opacityLabel.textColor = .white
        container.addSubview(opacityLabel)

        let opacityPopup = NSPopUpButton(frame: NSRect(x: 290, y: 102, width: 150, height: 26))
        let opacities = ["20%", "35%", "50%", "70%", "90%"]
        for o in opacities { opacityPopup.addItem(withTitle: o) }
        opacityPopup.selectItem(withTitle: "35%")
        opacityPopup.target = self
        opacityPopup.action = #selector(watermarkParamChanged)
        container.addSubview(opacityPopup)
        fieldInputs["opacity"] = opacityPopup

        // Row 4: Color
        let colorLabel = NSTextField(labelWithString: "Color:")
        colorLabel.frame = NSRect(x: 0, y: 62, width: 65, height: 18)
        colorLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        colorLabel.textColor = .white
        container.addSubview(colorLabel)

        let colorPopup = NSPopUpButton(frame: NSRect(x: 70, y: 58, width: 180, height: 26))
        let colors = [
            "White (#ffffff)",
            "Black (#000000)",
            "Orange (#ff6500)",
            "Red (#ef4444)",
            "Blue (#3b82f6)",
            "Green (#10b981)",
            "Gold (#f59e0b)"
        ]
        for c in colors { colorPopup.addItem(withTitle: c) }
        colorPopup.target = self
        colorPopup.action = #selector(watermarkParamChanged)
        container.addSubview(colorPopup)
        fieldInputs["color"] = colorPopup

        // Row 5: Info summary label
        watermarkInfoLabel.frame = NSRect(x: 0, y: 14, width: 440, height: 22)
        watermarkInfoLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        watermarkInfoLabel.textColor = NSColor(srgbRed: 1.0, green: 0.7, blue: 0.3, alpha: 1.0)
        watermarkInfoLabel.stringValue = "Watermark: CONFIDENTIAL  ·  Single (Center)  ·  45°  ·  48 pt"
        container.addSubview(watermarkInfoLabel)

        updateWatermarkPreview()
    }

    @objc private func watermarkTextDidChange(_ notification: Notification) {
        watermarkParamChanged()
    }

    @objc private func watermarkParamChanged() {
        let tf = fieldInputs["text"] as? NSTextField
        let text = tf?.stringValue.trimmingCharacters(in: .whitespaces) ?? "CONFIDENTIAL"
        let displayStr = text.isEmpty ? "CONFIDENTIAL" : text

        let rPopup = fieldInputs["repeats"] as? NSPopUpButton
        let rTitle = rPopup?.titleOfSelectedItem ?? "Single (Center)"

        let aPopup = fieldInputs["angle"] as? NSPopUpButton
        let aTitle = aPopup?.titleOfSelectedItem ?? "45°"

        let sPopup = fieldInputs["size"] as? NSPopUpButton
        let sTitle = sPopup?.titleOfSelectedItem ?? "48 pt"

        let oPopup = fieldInputs["opacity"] as? NSPopUpButton
        let oTitle = oPopup?.titleOfSelectedItem ?? "35%"

        watermarkInfoLabel.stringValue = "Watermark: \(displayStr)  ·  \(rTitle)  ·  \(aTitle)  ·  \(sTitle)  ·  \(oTitle)"
        updateWatermarkPreview()
    }

    private func updateWatermarkPreview() {
        guard let base = originalImage else { return }
        let tf = fieldInputs["text"] as? NSTextField
        let text = tf?.stringValue.trimmingCharacters(in: .whitespaces) ?? "CONFIDENTIAL"
        let displayStr = text.isEmpty ? "CONFIDENTIAL" : text

        let rPopup = fieldInputs["repeats"] as? NSPopUpButton
        let rTitle = rPopup?.titleOfSelectedItem ?? "Single (Center)"

        let aPopup = fieldInputs["angle"] as? NSPopUpButton
        let aTitle = aPopup?.titleOfSelectedItem ?? "45°"
        var angleDeg: CGFloat = 45
        if aTitle.contains("-45") { angleDeg = -45 }
        else if aTitle.contains("90") { angleDeg = 90 }
        else if aTitle.contains("30") { angleDeg = 30 }
        else if aTitle.contains("0") { angleDeg = 0 }

        let sPopup = fieldInputs["size"] as? NSPopUpButton
        let sTitle = sPopup?.titleOfSelectedItem ?? "48 pt"
        var ptSize: CGFloat = 48
        if sTitle.contains("18") { ptSize = 18 }
        else if sTitle.contains("32") { ptSize = 32 }
        else if sTitle.contains("72") { ptSize = 72 }
        else if sTitle.contains("96") { ptSize = 96 }

        let oPopup = fieldInputs["opacity"] as? NSPopUpButton
        let oTitle = oPopup?.titleOfSelectedItem ?? "35%"
        var alpha: CGFloat = 0.35
        if oTitle.contains("20") { alpha = 0.20 }
        else if oTitle.contains("50") { alpha = 0.50 }
        else if oTitle.contains("70") { alpha = 0.70 }
        else if oTitle.contains("90") { alpha = 0.90 }

        let cPopup = fieldInputs["color"] as? NSPopUpButton
        let cTitle = cPopup?.titleOfSelectedItem ?? "#ffffff"
        var fontColor = NSColor.white
        if cTitle.contains("#000000") { fontColor = .black }
        else if cTitle.contains("#ff6500") { fontColor = NSColor(srgbRed: 1.0, green: 0.384, blue: 0.031, alpha: 1.0) }
        else if cTitle.contains("#ef4444") { fontColor = NSColor(srgbRed: 0.937, green: 0.267, blue: 0.267, alpha: 1.0) }
        else if cTitle.contains("#3b82f6") { fontColor = NSColor(srgbRed: 0.231, green: 0.510, blue: 0.965, alpha: 1.0) }
        else if cTitle.contains("#10b981") { fontColor = NSColor(srgbRed: 0.063, green: 0.725, blue: 0.506, alpha: 1.0) }
        else if cTitle.contains("#f59e0b") { fontColor = NSColor(srgbRed: 0.961, green: 0.620, blue: 0.043, alpha: 1.0) }

        let rep = base.representations.first
        let w = CGFloat(rep?.pixelsWide ?? Int(base.size.width))
        let h = CGFloat(rep?.pixelsHigh ?? Int(base.size.height))
        guard w > 0, h > 0 else { return }

        // Scale font size proportionally for high resolution images
        let scaleFactor = max(1.0, min(w, h) / 800.0)
        let scaledFont = NSFont.boldSystemFont(ofSize: ptSize * scaleFactor)
        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: scaledFont,
            .foregroundColor: fontColor.withAlphaComponent(alpha)
        ]
        let attrStr = NSAttributedString(string: displayStr, attributes: textAttrs)
        let strSize = attrStr.size()

        let composed = NSImage(size: NSSize(width: w, height: h))
        composed.lockFocus()
        base.draw(in: NSRect(x: 0, y: 0, width: w, height: h))

        func drawRotatedText(at center: CGPoint) {
            let transform = NSAffineTransform()
            transform.translateX(by: center.x, yBy: center.y)
            transform.rotate(byDegrees: angleDeg)
            transform.concat()
            attrStr.draw(at: NSPoint(x: -strSize.width / 2.0, y: -strSize.height / 2.0))
            transform.invert()
            transform.concat()
        }

        if rTitle.contains("4") {
            // 2x2 grid
            for r in 0..<2 {
                for c in 0..<2 {
                    let cx = w * (CGFloat(c) + 0.5) / 2.0
                    let cy = h * (CGFloat(r) + 0.5) / 2.0
                    drawRotatedText(at: CGPoint(x: cx, y: cy))
                }
            }
        } else if rTitle.contains("9") {
            // 3x3 grid
            for r in 0..<3 {
                for c in 0..<3 {
                    let cx = w * (CGFloat(c) + 0.5) / 3.0
                    let cy = h * (CGFloat(r) + 0.5) / 3.0
                    drawRotatedText(at: CGPoint(x: cx, y: cy))
                }
            }
        } else if rTitle.contains("16") {
            // 4x4 grid
            for r in 0..<4 {
                for c in 0..<4 {
                    let cx = w * (CGFloat(c) + 0.5) / 4.0
                    let cy = h * (CGFloat(r) + 0.5) / 4.0
                    drawRotatedText(at: CGPoint(x: cx, y: cy))
                }
            }
        } else if rTitle.contains("Tiled") {
            let stepX = max(60, strSize.width * 1.5)
            let stepY = max(40, strSize.height * 2.2)
            var row = 0
            var y: CGFloat = 0
            while y < h + stepY {
                let xOffset = (row % 2 == 1) ? (stepX / 2.0) : 0
                var x: CGFloat = -stepX / 2.0 + xOffset
                while x < w + stepX {
                    drawRotatedText(at: CGPoint(x: x, y: y))
                    x += stepX
                }
                y += stepY
                row += 1
            }
        } else if rTitle.contains("Bottom Right") {
            let cx = max(strSize.width / 2.0, w - strSize.width / 2.0 - 40)
            let cy = max(strSize.height / 2.0, 40 + strSize.height / 2.0)
            drawRotatedText(at: CGPoint(x: cx, y: cy))
        } else {
            // Center
            drawRotatedText(at: CGPoint(x: w / 2.0, y: h / 2.0))
        }

        composed.unlockFocus()
        self.previewImageView.image = composed
    }

    // MARK: - Resize Form
    private func setupResizeForm(in container: NSView) {
        let wLabel = NSTextField(labelWithString: "Width (px):")
        wLabel.frame = NSRect(x: 0, y: 75, width: 100, height: 20)
        wLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        wLabel.textColor = .white
        container.addSubview(wLabel)

        let wField = NSTextField(frame: NSRect(x: 110, y: 73, width: 120, height: 24))
        wField.stringValue = "\(originalWidth > 0 ? originalWidth : 1920)"
        container.addSubview(wField)
        fieldInputs["width"] = wField

        let hLabel = NSTextField(labelWithString: "Height (px):")
        hLabel.frame = NSRect(x: 0, y: 35, width: 100, height: 20)
        hLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        hLabel.textColor = .white
        container.addSubview(hLabel)

        let hField = NSTextField(frame: NSRect(x: 110, y: 33, width: 120, height: 24))
        hField.stringValue = "\(originalHeight > 0 ? originalHeight : 1080)"
        container.addSubview(hField)
        fieldInputs["height"] = hField
    }

    // MARK: - Redact Form
    private func setupRedactForm(in container: NSView) {
        cropOverlayView.isRedactMode = true

        let styleLabel = NSTextField(labelWithString: "Redact Style:")
        styleLabel.frame = NSRect(x: 0, y: 88, width: 110, height: 20)
        styleLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        styleLabel.textColor = .white
        container.addSubview(styleLabel)

        let stylePopup = NSPopUpButton(frame: NSRect(x: 120, y: 86, width: 220, height: 26))
        stylePopup.addItem(withTitle: "Solid Blackout")
        stylePopup.addItem(withTitle: "Gaussian Blur")
        stylePopup.addItem(withTitle: "Mosaic (Pixelate)")
        stylePopup.target = self
        stylePopup.action = #selector(redactParamChanged)
        container.addSubview(stylePopup)
        fieldInputs["style"] = stylePopup

        let blockLabel = NSTextField(labelWithString: "Mosaic Grid:")
        blockLabel.frame = NSRect(x: 0, y: 52, width: 110, height: 20)
        blockLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        blockLabel.textColor = .white
        container.addSubview(blockLabel)

        let blockSlider = NSSlider(value: 18, minValue: 4, maxValue: 50, target: self, action: #selector(toolSliderChanged(_:)))
        blockSlider.frame = NSRect(x: 120, y: 50, width: 220, height: 22)
        blockSlider.isContinuous = true
        container.addSubview(blockSlider)
        fieldSliders["blockSize"] = blockSlider

        let badge = NSTextField(labelWithString: "18 px")
        badge.frame = NSRect(x: 350, y: 52, width: 80, height: 20)
        badge.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        badge.textColor = NSColor(srgbRed: 1.0, green: 0.384, blue: 0.031, alpha: 1.0)
        container.addSubview(badge)
        sliderLabels["blockSize"] = badge

        cropInfoLabel.frame = NSRect(x: 0, y: 14, width: 440, height: 20)
        cropInfoLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        cropInfoLabel.textColor = NSColor(srgbRed: 1.0, green: 0.384, blue: 0.031, alpha: 1.0)
        cropInfoLabel.stringValue = "Redaction Box: Drag handles on image to place blackout/blur box"
        container.addSubview(cropInfoLabel)

        cropOverlayView.onCropChanged = { [weak self] (rect, _) in
            guard let self = self else { return }
            let w = Int(rect.width)
            let h = Int(rect.height)
            self.cropInfoLabel.stringValue = "Redaction Area: \(w) × \(h) px · Drag handles to adjust"
            self.updateRedactPreview()
        }
    }

    @objc private func redactParamChanged() {
        updateRedactPreview()
    }

    private func updateRedactPreview() {
        guard let ciInput = previewCIImage ?? (originalImage?.cgImage(forProposedRect: nil, context: nil, hints: nil).map { CIImage(cgImage: $0) }) else { return }

        let stylePopup = fieldInputs["style"] as? NSPopUpButton
        let style = stylePopup?.titleOfSelectedItem ?? "Solid Blackout"
        let blockSize = CGFloat(fieldSliders["blockSize"]?.integerValue ?? 18)

        let px = cropOverlayView.currentPixelRect()
        guard px.width > 0, px.height > 0 else {
            self.previewImageView.image = originalImage
            return
        }

        let fullW = CGFloat(originalWidth > 0 ? originalWidth : Int(ciInput.extent.width))
        let fullH = CGFloat(originalHeight > 0 ? originalHeight : Int(ciInput.extent.height))

        let scaleX = ciInput.extent.width / fullW
        let scaleY = ciInput.extent.height / fullH

        // In CIImage, coordinate (0,0) is at bottom-left:
        let ciX = px.origin.x * scaleX
        let ciY = (fullH - (px.origin.y + px.size.height)) * scaleY
        let ciW = max(1.0, px.size.width * scaleX)
        let ciH = max(1.0, px.size.height * scaleY)
        let ciRect = CGRect(x: ciX, y: ciY, width: ciW, height: ciH)

        var compositedCI = ciInput

        if style.contains("Blur") {
            let clamped = ciInput.clampedToExtent()
            if let blurFilter = CIFilter(name: "CIGaussianBlur") {
                blurFilter.setValue(clamped, forKey: kCIInputImageKey)
                blurFilter.setValue(22.0, forKey: kCIInputRadiusKey)
                if let blurred = blurFilter.outputImage {
                    let effect = blurred.cropped(to: ciRect)
                    compositedCI = effect.composited(over: ciInput)
                }
            }
        } else if style.contains("Mosaic") || style.contains("Pixelate") {
            if let pixFilter = CIFilter(name: "CIPixellate") {
                pixFilter.setValue(ciInput, forKey: kCIInputImageKey)
                pixFilter.setValue(max(2.0, blockSize * scaleX), forKey: kCIInputScaleKey)
                pixFilter.setValue(CIVector(x: ciRect.midX, y: ciRect.midY), forKey: kCIInputCenterKey)
                if let pixellated = pixFilter.outputImage {
                    let effect = pixellated.cropped(to: ciRect)
                    compositedCI = effect.composited(over: ciInput)
                }
            }
        } else {
            // Solid Blackout
            let blackCI = CIImage(color: CIColor.black).cropped(to: ciRect)
            compositedCI = blackCI.composited(over: ciInput)
        }

        let extent = ciInput.extent
        if let cgOut = ciContext.createCGImage(compositedCI, from: extent) {
            let finalImg = NSImage(cgImage: cgOut, size: NSSize(width: extent.width, height: extent.height))
            self.previewImageView.image = finalImg
        }
    }

    // MARK: - Image Adjustments Form (editImage)
    private func setupEditImageForm(in container: NSView) {
        let specs: [(key: String, label: String, minVal: Double, maxVal: Double, defVal: Double, unit: String)] = [
            ("exposure", "Exposure", -2.0, 2.0, 0.0, "EV"),
            ("contrast", "Contrast", 0.0, 2.0, 1.0, "x"),
            ("saturation", "Saturation", 0.0, 2.0, 1.0, "x"),
            ("temperature", "Warmth", -100.0, 100.0, 0.0, ""),
            ("shadows", "Shadows", -100.0, 100.0, 0.0, "%"),
            ("highlights", "Highlights", -100.0, 100.0, 0.0, "%"),
            ("clarity", "Clarity", 0.0, 100.0, 0.0, "%")
        ]

        var y: CGFloat = 224
        for item in specs {
            let label = NSTextField(labelWithString: item.label + ":")
            label.frame = NSRect(x: 0, y: y, width: 85, height: 18)
            label.font = NSFont.systemFont(ofSize: 11, weight: .medium)
            label.textColor = .white
            container.addSubview(label)

            let slider = NSSlider(value: item.defVal, minValue: item.minVal, maxValue: item.maxVal, target: self, action: #selector(editSliderDragged(_:)))
            slider.frame = NSRect(x: 90, y: y - 2, width: 275, height: 20)
            slider.isContinuous = true
            container.addSubview(slider)
            fieldSliders[item.key] = slider

            let badge = NSTextField(labelWithString: formatEditVal(item.defVal, unit: item.unit))
            badge.frame = NSRect(x: 375, y: y, width: 60, height: 18)
            badge.alignment = .right
            badge.font = NSFont.systemFont(ofSize: 11, weight: .bold)
            badge.textColor = NSColor(srgbRed: 1.0, green: 0.384, blue: 0.031, alpha: 1.0)
            container.addSubview(badge)
            sliderLabels[item.key] = badge

            editSliders.append((item.key, item.label, item.minVal, item.maxVal, item.defVal, item.unit, slider, badge))
            y -= 31
        }

        let resetBtn = NSButton(frame: NSRect(x: 0, y: 0, width: 140, height: 24))
        resetBtn.title = "Reset Adjustments"
        resetBtn.bezelStyle = .inline
        resetBtn.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        resetBtn.target = self
        resetBtn.action = #selector(resetEditSliders)
        container.addSubview(resetBtn)
    }

    private func formatEditVal(_ val: Double, unit: String) -> String {
        if unit == "EV" {
            return String(format: "%+.2f EV", val)
        } else if unit == "x" {
            return String(format: "%.2fx", val)
        } else if unit == "%" {
            return String(format: "%+d%%", Int(val))
        } else {
            return String(format: "%+d", Int(val))
        }
    }

    @objc private func editSliderDragged(_ sender: NSSlider) {
        for item in editSliders {
            if item.slider === sender {
                item.badge.stringValue = formatEditVal(sender.doubleValue, unit: item.unit)
                break
            }
        }
        updateEditImagePreview()
    }

    @objc private func resetEditSliders() {
        for item in editSliders {
            item.slider.doubleValue = item.defVal
            item.badge.stringValue = formatEditVal(item.defVal, unit: item.unit)
        }
        updateEditImagePreview()
    }

    private func updateEditImagePreview() {
        guard let ciInput = previewCIImage ?? (originalImage?.cgImage(forProposedRect: nil, context: nil, hints: nil).map { CIImage(cgImage: $0) }) else { return }

        var currentCI = ciInput

        let expVal = fieldSliders["exposure"]?.doubleValue ?? 0.0
        let contVal = fieldSliders["contrast"]?.doubleValue ?? 1.0
        let satVal = fieldSliders["saturation"]?.doubleValue ?? 1.0
        let tempVal = fieldSliders["temperature"]?.doubleValue ?? 0.0
        let shadowVal = fieldSliders["shadows"]?.doubleValue ?? 0.0
        let highlightVal = fieldSliders["highlights"]?.doubleValue ?? 0.0
        let clarityVal = fieldSliders["clarity"]?.doubleValue ?? 0.0

        // 1. Exposure
        if abs(expVal) > 0.001 {
            if let filter = CIFilter(name: "CIExposureAdjust") {
                filter.setValue(currentCI, forKey: kCIInputImageKey)
                filter.setValue(expVal, forKey: kCIInputEVKey)
                if let out = filter.outputImage { currentCI = out }
            }
        }

        // 2. Contrast & Saturation (CIColorControls)
        if abs(contVal - 1.0) > 0.001 || abs(satVal - 1.0) > 0.001 {
            if let filter = CIFilter(name: "CIColorControls") {
                filter.setValue(currentCI, forKey: kCIInputImageKey)
                filter.setValue(contVal, forKey: kCIInputContrastKey)
                filter.setValue(satVal, forKey: kCIInputSaturationKey)
                if let out = filter.outputImage { currentCI = out }
            }
        }

        // 3. Warmth / Temperature (CITemperatureAndTint)
        if abs(tempVal) > 0.001 {
            if let filter = CIFilter(name: "CITemperatureAndTint") {
                filter.setValue(currentCI, forKey: kCIInputImageKey)
                let targetTemp = 6500.0 + (tempVal * 25.0)
                filter.setValue(CIVector(x: 6500, y: 0), forKey: "inputNeutral")
                filter.setValue(CIVector(x: CGFloat(targetTemp), y: 0), forKey: "inputTargetNeutral")
                if let out = filter.outputImage { currentCI = out }
            }
        }

        // 4. Shadows & Highlights (CIHighlightShadowAdjust)
        if abs(shadowVal) > 0.001 || abs(highlightVal) > 0.001 {
            if let filter = CIFilter(name: "CIHighlightShadowAdjust") {
                filter.setValue(currentCI, forKey: kCIInputImageKey)
                let sAmt = max(0.0, min(1.0, (shadowVal + 100.0) / 200.0))
                let hAmt = max(0.0, min(1.0, 1.0 - (highlightVal / 100.0)))
                filter.setValue(sAmt, forKey: "inputShadowAmount")
                filter.setValue(hAmt, forKey: "inputHighlightAmount")
                if let out = filter.outputImage { currentCI = out }
            }
        }

        // 5. Clarity (CISharpenLuminance)
        if clarityVal > 0.1 {
            if let filter = CIFilter(name: "CISharpenLuminance") {
                filter.setValue(currentCI, forKey: kCIInputImageKey)
                filter.setValue(clarityVal / 50.0, forKey: kCIInputSharpnessKey)
                if let out = filter.outputImage { currentCI = out }
            }
        }

        let extent = ciInput.extent
        if let cgOut = ciContext.createCGImage(currentCI, from: extent) {
            let finalImg = NSImage(cgImage: cgOut, size: NSSize(width: extent.width, height: extent.height))
            self.previewImageView.image = finalImg
        }
    }

    // MARK: - Image Frame / Background Form
    private func setupFrameForm(in container: NSView) {
        var y: CGFloat = 135

        let bgLabel = NSTextField(labelWithString: "Background:")
        bgLabel.frame = NSRect(x: 0, y: y, width: 110, height: 20)
        bgLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        bgLabel.textColor = .white
        container.addSubview(bgLabel)

        let bgPopup = NSPopUpButton(frame: NSRect(x: 120, y: y - 2, width: 220, height: 24))
        let colors = [
            "#F0EBFF (Soft Lilac)",
            "#FFFFFF (Pure White)",
            "#18181B (Dark Graphite)",
            "#FF6500 (DropDial Orange)",
            "#3B82F6 (Royal Blue)",
            "#10B981 (Emerald Green)"
        ]
        for c in colors { bgPopup.addItem(withTitle: c) }
        bgPopup.target = self
        bgPopup.action = #selector(frameParamChanged)
        container.addSubview(bgPopup)
        fieldInputs["background"] = bgPopup
        y -= 36

        let slidersConfig: [(key: String, label: String, min: Double, max: Double, def: Double, unit: String)] = [
            ("padding", "Padding:", 10, 200, 80, "px"),
            ("radius", "Corner Radius:", 0, 60, 24, "px"),
            ("shadow", "Shadow Blur:", 0, 50, 20, "px")
        ]
        for item in slidersConfig {
            let label = NSTextField(labelWithString: item.label)
            label.frame = NSRect(x: 0, y: y, width: 110, height: 20)
            label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            label.textColor = .white
            container.addSubview(label)

            let slider = NSSlider(value: item.def, minValue: item.min, maxValue: item.max, target: self, action: #selector(toolSliderChanged(_:)))
            slider.frame = NSRect(x: 120, y: y - 2, width: 220, height: 22)
            slider.isContinuous = true
            container.addSubview(slider)
            fieldSliders[item.key] = slider

            let badge = NSTextField(labelWithString: "\(Int(item.def)) \(item.unit)")
            badge.frame = NSRect(x: 350, y: y, width: 80, height: 20)
            badge.font = NSFont.systemFont(ofSize: 12, weight: .bold)
            badge.textColor = NSColor(srgbRed: 1.0, green: 0.384, blue: 0.031, alpha: 1.0)
            container.addSubview(badge)
            sliderLabels[item.key] = badge

            y -= 36
        }
    }

    @objc private func frameParamChanged() {
        updateFramePreview()
    }

    private func updateFramePreview() {
        guard let base = originalImage else { return }

        let bgPopup = fieldInputs["background"] as? NSPopUpButton
        let bgTitle = bgPopup?.titleOfSelectedItem ?? "#F0EBFF"
        var bgColor = NSColor(srgbRed: 0.941, green: 0.922, blue: 1.0, alpha: 1.0)
        if bgTitle.contains("#FFFFFF") { bgColor = .white }
        else if bgTitle.contains("#18181B") { bgColor = NSColor(srgbRed: 0.094, green: 0.094, blue: 0.106, alpha: 1.0) }
        else if bgTitle.contains("#FF6500") { bgColor = NSColor(srgbRed: 1.0, green: 0.384, blue: 0.031, alpha: 1.0) }
        else if bgTitle.contains("#3B82F6") { bgColor = NSColor(srgbRed: 0.231, green: 0.510, blue: 0.965, alpha: 1.0) }
        else if bgTitle.contains("#10B981") { bgColor = NSColor(srgbRed: 0.063, green: 0.725, blue: 0.506, alpha: 1.0) }

        let pad = CGFloat(fieldSliders["padding"]?.integerValue ?? 80)
        let radius = CGFloat(fieldSliders["radius"]?.integerValue ?? 24)
        let shadowBlur = CGFloat(fieldSliders["shadow"]?.integerValue ?? 20)

        let rep = base.representations.first
        let rawW = CGFloat(rep?.pixelsWide ?? Int(base.size.width))
        let rawH = CGFloat(rep?.pixelsHigh ?? Int(base.size.height))
        guard rawW > 0, rawH > 0 else { return }

        let scale = min(1.0, 1000.0 / max(rawW, rawH))
        let imgW = rawW * scale
        let imgH = rawH * scale
        let scaledPad = pad * scale
        let scaledRadius = radius * scale
        let scaledShadow = shadowBlur * scale

        let canvasW = imgW + scaledPad * 2
        let canvasH = imgH + scaledPad * 2
        let canvasSize = NSSize(width: canvasW, height: canvasH)

        let composed = NSImage(size: canvasSize)
        composed.lockFocus()

        // 1. Draw Background Canvas
        bgColor.setFill()
        NSRect(origin: .zero, size: canvasSize).fill()

        let imgRect = NSRect(x: scaledPad, y: scaledPad, width: imgW, height: imgH)

        // 2. Draw Drop Shadow
        if scaledShadow > 0 {
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowBlurRadius = scaledShadow
            shadow.shadowOffset = NSSize(width: 0, height: -scaledShadow * 0.35)
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.40)
            shadow.set()
            let shadowClip = NSBezierPath(roundedRect: imgRect, xRadius: scaledRadius, yRadius: scaledRadius)
            NSColor.black.setFill()
            shadowClip.fill()
            NSGraphicsContext.restoreGraphicsState()
        }

        // 3. Draw Clipped Image
        NSGraphicsContext.saveGraphicsState()
        let clipPath = NSBezierPath(roundedRect: imgRect, xRadius: scaledRadius, yRadius: scaledRadius)
        clipPath.addClip()
        base.draw(in: imgRect, from: NSRect(x: 0, y: 0, width: base.size.width, height: base.size.height), operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        composed.unlockFocus()
        self.previewImageView.image = composed
    }

    // MARK: - Image Annotate Form
    private func setupAnnotateForm(in container: NSView) {
        var y: CGFloat = 110

        let textLabel = NSTextField(labelWithString: "Stamp Text:")
        textLabel.frame = NSRect(x: 0, y: y, width: 110, height: 20)
        textLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        textLabel.textColor = .white
        container.addSubview(textLabel)

        let textField = NSTextField(frame: NSRect(x: 120, y: y, width: 240, height: 24))
        textField.stringValue = "APPROVED"
        textField.placeholderString = "Enter text..."
        textField.target = self
        textField.action = #selector(annotateParamChanged)
        NotificationCenter.default.addObserver(self, selector: #selector(annotateTextDidChange(_:)), name: NSControl.textDidChangeNotification, object: textField)
        container.addSubview(textField)
        fieldInputs["text"] = textField
        y -= 38

        let colorLabel = NSTextField(labelWithString: "Badge Color:")
        colorLabel.frame = NSRect(x: 0, y: y, width: 110, height: 20)
        colorLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        colorLabel.textColor = .white
        container.addSubview(colorLabel)

        let colorPopup = NSPopUpButton(frame: NSRect(x: 120, y: y - 2, width: 240, height: 24))
        let colors = [
            "#ff6500 (DropDial Orange)",
            "#ef4444 (Bold Red)",
            "#3b82f6 (Royal Blue)",
            "#10b981 (Forest Green)",
            "#ffffff (Pure White)",
            "#000000 (Black)"
        ]
        for c in colors { colorPopup.addItem(withTitle: c) }
        colorPopup.target = self
        colorPopup.action = #selector(annotateParamChanged)
        container.addSubview(colorPopup)
        fieldInputs["color"] = colorPopup
        y -= 38

        let posLabel = NSTextField(labelWithString: "Position:")
        posLabel.frame = NSRect(x: 0, y: y, width: 110, height: 20)
        posLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        posLabel.textColor = .white
        container.addSubview(posLabel)

        let posPopup = NSPopUpButton(frame: NSRect(x: 120, y: y - 2, width: 240, height: 24))
        posPopup.addItem(withTitle: "Bottom Right (Default)")
        posPopup.addItem(withTitle: "Bottom Left")
        posPopup.addItem(withTitle: "Top Right")
        posPopup.addItem(withTitle: "Top Left")
        posPopup.addItem(withTitle: "Center")
        posPopup.target = self
        posPopup.action = #selector(annotateParamChanged)
        container.addSubview(posPopup)
        fieldInputs["position"] = posPopup
    }

    @objc private func annotateTextDidChange(_ notification: Notification) {
        annotateParamChanged()
    }

    @objc private func annotateParamChanged() {
        updateAnnotatePreview()
    }

    private func updateAnnotatePreview() {
        guard let base = originalImage else { return }
        let tf = fieldInputs["text"] as? NSTextField
        let text = tf?.stringValue.trimmingCharacters(in: .whitespaces) ?? "APPROVED"
        let displayStr = text.isEmpty ? "APPROVED" : text

        let cPopup = fieldInputs["color"] as? NSPopUpButton
        let cTitle = cPopup?.titleOfSelectedItem ?? "#ff6500"
        var badgeBg = NSColor(srgbRed: 1.0, green: 0.384, blue: 0.031, alpha: 1.0)
        if cTitle.contains("#ef4444") { badgeBg = NSColor(srgbRed: 0.937, green: 0.267, blue: 0.267, alpha: 1.0) }
        else if cTitle.contains("#3b82f6") { badgeBg = NSColor(srgbRed: 0.231, green: 0.510, blue: 0.965, alpha: 1.0) }
        else if cTitle.contains("#10b981") { badgeBg = NSColor(srgbRed: 0.063, green: 0.725, blue: 0.506, alpha: 1.0) }
        else if cTitle.contains("#ffffff") { badgeBg = .white }
        else if cTitle.contains("#000000") { badgeBg = .black }

        let pPopup = fieldInputs["position"] as? NSPopUpButton
        let pTitle = pPopup?.titleOfSelectedItem ?? "Bottom Right"

        let rep = base.representations.first
        let w = CGFloat(rep?.pixelsWide ?? Int(base.size.width))
        let h = CGFloat(rep?.pixelsHigh ?? Int(base.size.height))
        guard w > 0, h > 0 else { return }

        let scale = max(1.0, min(w, h) / 700.0)
        let font = NSFont.boldSystemFont(ofSize: 22 * scale)
        let textColor = (badgeBg == .white) ? NSColor.black : NSColor.white
        let attrStr = NSAttributedString(string: displayStr, attributes: [.font: font, .foregroundColor: textColor])
        let strSize = attrStr.size()

        let padH: CGFloat = 20 * scale
        let padV: CGFloat = 10 * scale
        let badgeW = strSize.width + padH * 2
        let badgeH = strSize.height + padV * 2
        let margin: CGFloat = 35 * scale

        var badgeX = w - badgeW - margin
        var badgeY = margin
        if pTitle.contains("Bottom Left") {
            badgeX = margin
            badgeY = margin
        } else if pTitle.contains("Top Right") {
            badgeX = w - badgeW - margin
            badgeY = h - badgeH - margin
        } else if pTitle.contains("Top Left") {
            badgeX = margin
            badgeY = h - badgeH - margin
        } else if pTitle.contains("Center") {
            badgeX = (w - badgeW) / 2.0
            badgeY = (h - badgeH) / 2.0
        }

        let composed = NSImage(size: NSSize(width: w, height: h))
        composed.lockFocus()
        base.draw(in: NSRect(x: 0, y: 0, width: w, height: h))

        let badgeRect = NSRect(x: badgeX, y: badgeY, width: badgeW, height: badgeH)
        let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: badgeH / 2.0, yRadius: badgeH / 2.0)
        badgeBg.setFill()
        badgePath.fill()

        attrStr.draw(at: NSPoint(x: badgeX + padH, y: badgeY + padV))
        composed.unlockFocus()
        self.previewImageView.image = composed
    }

    // MARK: - Multi-Image Collage Form
    private func setupCollageForm(in container: NSView) {
        var y: CGFloat = 110

        let layoutLabel = NSTextField(labelWithString: "Layout Style:")
        layoutLabel.frame = NSRect(x: 0, y: y, width: 110, height: 20)
        layoutLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        layoutLabel.textColor = .white
        container.addSubview(layoutLabel)

        let layoutPopup = NSPopUpButton(frame: NSRect(x: 120, y: y - 2, width: 240, height: 24))
        layoutPopup.addItem(withTitle: "Grid (Auto Balance)")
        layoutPopup.addItem(withTitle: "Hero (Featured + Thumbnails)")
        layoutPopup.addItem(withTitle: "Horizontal Row")
        layoutPopup.addItem(withTitle: "Vertical Column")
        layoutPopup.target = self
        layoutPopup.action = #selector(collageParamChanged)
        container.addSubview(layoutPopup)
        fieldInputs["layout"] = layoutPopup
        y -= 38

        let gapLabel = NSTextField(labelWithString: "Tile Gap:")
        gapLabel.frame = NSRect(x: 0, y: y, width: 110, height: 20)
        gapLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        gapLabel.textColor = .white
        container.addSubview(gapLabel)

        let gapSlider = NSSlider(value: 16, minValue: 0, maxValue: 40, target: self, action: #selector(toolSliderChanged(_:)))
        gapSlider.frame = NSRect(x: 120, y: y - 2, width: 210, height: 22)
        gapSlider.isContinuous = true
        container.addSubview(gapSlider)
        fieldSliders["gap"] = gapSlider

        let gapBadge = NSTextField(labelWithString: "16 px")
        gapBadge.frame = NSRect(x: 340, y: y, width: 70, height: 20)
        gapBadge.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        gapBadge.textColor = NSColor(srgbRed: 1.0, green: 0.384, blue: 0.031, alpha: 1.0)
        container.addSubview(gapBadge)
        sliderLabels["gap"] = gapBadge
        y -= 38

        let bgLabel = NSTextField(labelWithString: "Background:")
        bgLabel.frame = NSRect(x: 0, y: y, width: 110, height: 20)
        bgLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        bgLabel.textColor = .white
        container.addSubview(bgLabel)

        let bgPopup = NSPopUpButton(frame: NSRect(x: 120, y: y - 2, width: 240, height: 24))
        bgPopup.addItem(withTitle: "#ffffff (White)")
        bgPopup.addItem(withTitle: "#18181b (Dark Graphite)")
        bgPopup.addItem(withTitle: "#f0ebff (Soft Lavender)")
        bgPopup.target = self
        bgPopup.action = #selector(collageParamChanged)
        container.addSubview(bgPopup)
        fieldInputs["background"] = bgPopup
    }

    @objc private func collageParamChanged() {
        updateCollagePreview()
    }

    private func updateCollagePreview() {
        guard let base = originalImage else { return }

        let bgPopup = fieldInputs["background"] as? NSPopUpButton
        let bgTitle = bgPopup?.titleOfSelectedItem ?? "#ffffff"
        var bgColor = NSColor.white
        if bgTitle.contains("#18181b") { bgColor = NSColor(srgbRed: 0.094, green: 0.094, blue: 0.106, alpha: 1.0) }
        else if bgTitle.contains("#f0ebff") { bgColor = NSColor(srgbRed: 0.941, green: 0.922, blue: 1.0, alpha: 1.0) }

        let gap = CGFloat(fieldSliders["gap"]?.integerValue ?? 16)
        let layoutPopup = fieldInputs["layout"] as? NSPopUpButton
        let layoutTitle = layoutPopup?.titleOfSelectedItem ?? "Grid"

        let targetSize = NSSize(width: 800, height: 600)
        let composed = NSImage(size: targetSize)
        composed.lockFocus()
        bgColor.setFill()
        NSRect(origin: .zero, size: targetSize).fill()

        let innerW = targetSize.width - gap * 3
        let innerH = targetSize.height - gap * 3

        if layoutTitle.contains("Hero") {
            let heroW = innerW * 0.58
            let rightW = innerW * 0.42
            let tileH = (innerH - gap) / 2.0

            let heroRect = NSRect(x: gap, y: gap, width: heroW, height: innerH + gap)
            base.draw(in: heroRect, from: .zero, operation: .copy, fraction: 1.0)

            let r1 = NSRect(x: gap * 2 + heroW, y: gap * 2 + tileH, width: rightW, height: tileH)
            base.draw(in: r1, from: .zero, operation: .copy, fraction: 1.0)

            let r2 = NSRect(x: gap * 2 + heroW, y: gap, width: rightW, height: tileH)
            base.draw(in: r2, from: .zero, operation: .copy, fraction: 1.0)
        } else if layoutTitle.contains("Row") {
            let tileW = (targetSize.width - gap * 4) / 3.0
            let tileH = targetSize.height - gap * 2
            for i in 0..<3 {
                let r = NSRect(x: gap + CGFloat(i) * (tileW + gap), y: gap, width: tileW, height: tileH)
                base.draw(in: r, from: .zero, operation: .copy, fraction: 1.0)
            }
        } else if layoutTitle.contains("Column") {
            let tileW = targetSize.width - gap * 2
            let tileH = (targetSize.height - gap * 4) / 3.0
            for i in 0..<3 {
                let r = NSRect(x: gap, y: gap + CGFloat(i) * (tileH + gap), width: tileW, height: tileH)
                base.draw(in: r, from: .zero, operation: .copy, fraction: 1.0)
            }
        } else {
            let tileW = (targetSize.width - gap * 3) / 2.0
            let tileH = (targetSize.height - gap * 3) / 2.0
            for row in 0..<2 {
                for col in 0..<2 {
                    let rx = gap + CGFloat(col) * (tileW + gap)
                    let ry = gap + CGFloat(row) * (tileH + gap)
                    base.draw(in: NSRect(x: rx, y: ry, width: tileW, height: tileH), from: .zero, operation: .copy, fraction: 1.0)
                }
            }
        }

        composed.unlockFocus()
        self.previewImageView.image = composed
    }

    // MARK: - Split Video Form
    private func setupSplitVideoForm(in container: NSView) {
        var y: CGFloat = 85

        let partsLabel = NSTextField(labelWithString: "Equal Parts:")
        partsLabel.frame = NSRect(x: 0, y: y, width: 110, height: 20)
        partsLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        partsLabel.textColor = .white
        container.addSubview(partsLabel)

        let partsPopup = NSPopUpButton(frame: NSRect(x: 120, y: y - 2, width: 220, height: 24))
        for i in 2...6 { partsPopup.addItem(withTitle: "\(i) Equal Parts") }
        container.addSubview(partsPopup)
        fieldInputs["parts"] = partsPopup
        y -= 36

        let pointsLabel = NSTextField(labelWithString: "Custom Points:")
        pointsLabel.frame = NSRect(x: 0, y: y, width: 110, height: 20)
        pointsLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        pointsLabel.textColor = .white
        container.addSubview(pointsLabel)

        let pointsField = NSTextField(frame: NSRect(x: 120, y: y, width: 220, height: 22))
        pointsField.placeholderString = "e.g. 10.0, 25.5 (Optional)"
        container.addSubview(pointsField)
        fieldInputs["splitPoints"] = pointsField
        y -= 28

        let note = NSTextField(labelWithString: "Splits video into standalone clips cleanly along keyframes.")
        note.frame = NSRect(x: 0, y: y, width: 440, height: 20)
        note.font = NSFont.systemFont(ofSize: 11)
        note.textColor = NSColor(white: 0.7, alpha: 1.0)
        container.addSubview(note)
    }

    // MARK: - Audio Visualizer Form
    private func setupAudioToVideoForm(in container: NSView) {
        let aspectLabel = NSTextField(labelWithString: "Video Aspect:")
        aspectLabel.frame = NSRect(x: 0, y: 70, width: 110, height: 20)
        aspectLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        aspectLabel.textColor = .white
        container.addSubview(aspectLabel)

        let aspectPopup = NSPopUpButton(frame: NSRect(x: 120, y: 68, width: 240, height: 24))
        aspectPopup.addItem(withTitle: "Landscape (16:9 Widescreen)")
        aspectPopup.addItem(withTitle: "Portrait (9:16 Reel / Story)")
        aspectPopup.addItem(withTitle: "Square (1:1 Social)")
        container.addSubview(aspectPopup)
        fieldInputs["aspect"] = aspectPopup

        let desc = NSTextField(labelWithString: "Generates an animated audio visualizer video synchronized with track.")
        desc.frame = NSRect(x: 0, y: 25, width: 440, height: 20)
        desc.font = NSFont.systemFont(ofSize: 11)
        desc.textColor = NSColor(srgbRed: 1.0, green: 0.384, blue: 0.031, alpha: 1.0)
        container.addSubview(desc)
    }

    // MARK: - Redact Audio (Bleep) Form
    private func setupRedactAudioForm(in container: NSView) {
        let startLabel = NSTextField(labelWithString: "Bleep Start (s):")
        startLabel.frame = NSRect(x: 0, y: 80, width: 110, height: 20)
        startLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        startLabel.textColor = .white
        container.addSubview(startLabel)

        let startField = NSTextField(frame: NSRect(x: 120, y: 78, width: 100, height: 24))
        startField.stringValue = "0.0"
        container.addSubview(startField)
        fieldInputs["start"] = startField

        let endLabel = NSTextField(labelWithString: "Bleep End (s):")
        endLabel.frame = NSRect(x: 230, y: 80, width: 90, height: 20)
        endLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        endLabel.textColor = .white
        container.addSubview(endLabel)

        let endField = NSTextField(frame: NSRect(x: 325, y: 78, width: 100, height: 24))
        endField.stringValue = "3.0"
        container.addSubview(endField)
        fieldInputs["end"] = endField

        let desc = NSTextField(labelWithString: "Silences the specified interval and replaces it with a soft 1 kHz tone.")
        desc.frame = NSRect(x: 0, y: 35, width: 440, height: 20)
        desc.font = NSFont.systemFont(ofSize: 11)
        desc.textColor = NSColor(srgbRed: 1.0, green: 0.384, blue: 0.031, alpha: 1.0)
        container.addSubview(desc)
    }

    // MARK: - Organize PDF Form
    private func setupOrganizePDFForm(in container: NSView) {
        let actLabel = NSTextField(labelWithString: "Page Action:")
        actLabel.frame = NSRect(x: 0, y: 70, width: 110, height: 20)
        actLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        actLabel.textColor = .white
        container.addSubview(actLabel)

        let actPopup = NSPopUpButton(frame: NSRect(x: 120, y: 68, width: 260, height: 24))
        let actions = [
            "Reverse All Pages",
            "Rotate All 90° Clockwise",
            "Rotate All 180°",
            "Rotate All 270°",
            "Extract Even Pages",
            "Extract Odd Pages",
            "Delete First Page",
            "Delete Last Page"
        ]
        for a in actions { actPopup.addItem(withTitle: a) }
        container.addSubview(actPopup)
        fieldInputs["action"] = actPopup

        let desc = NSTextField(labelWithString: "Rearranges or rotates pages cleanly without lossy re-rendering.")
        desc.frame = NSRect(x: 0, y: 25, width: 440, height: 20)
        desc.font = NSFont.systemFont(ofSize: 11)
        desc.textColor = NSColor(white: 0.8, alpha: 1.0)
        container.addSubview(desc)
    }

    @objc private func toolSliderChanged(_ sender: NSSlider) {
        for (key, slider) in fieldSliders {
            if slider === sender, let label = sliderLabels[key] {
                let unit = (key == "padding" || key == "radius" || key == "shadow" || key == "blockSize" || key == "gap") ? "px" : ""
                label.stringValue = "\(slider.integerValue) \(unit)"
                break
            }
        }
        if tool.id == "frameImage" {
            updateFramePreview()
        } else if tool.id == "redactImage" {
            updateRedactPreview()
        } else if tool.id == "createCollage" {
            updateCollagePreview()
        }
    }

    // MARK: - Generic Form
    private func setupGenericForm(in container: NSView) {
        var yOffset: CGFloat = 85
        for field in tool.fields {
            let label = NSTextField(labelWithString: field.label + ":")
            label.frame = NSRect(x: 0, y: yOffset, width: 140, height: 22)
            label.alignment = .right
            label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            label.textColor = .white
            container.addSubview(label)

            if let choices = field.choices {
                let popup = NSPopUpButton(frame: NSRect(x: 150, y: yOffset - 2, width: 220, height: 24))
                for c in choices {
                    popup.addItem(withTitle: c)
                }
                popup.selectItem(withTitle: field.defaultValue)
                container.addSubview(popup)
                fieldInputs[field.name] = popup
            } else {
                let textField = NSTextField(frame: NSRect(x: 150, y: yOffset, width: 220, height: 22))
                textField.stringValue = field.defaultValue
                container.addSubview(textField)
                fieldInputs[field.name] = textField
            }

            yOffset -= 34
        }
    }

    // MARK: - Preview Loading
    private func loadFilePreview() {
        guard let firstPath = paths.first else { return }

        if let attrs = try? FileManager.default.attributesOfItem(atPath: firstPath),
           let size = attrs[.size] as? Int64 {
            self.originalFileSize = size
        }

        self.infoLabel.stringValue = "Loading preview..."

        let ext = URL(fileURLWithPath: firstPath).pathExtension.lowercased()
        let isVideo = ["mp4", "mov", "mkv", "webm", "avi", "m4v"].contains(ext)
        let isVideoStudio = (tool.id == "trimVideo" || tool.id == "cropVideo" || tool.id == "splitVideo" || tool.id == "editVideo")

        if isVideoStudio || (isVideo && tool.id == "cropVideo") {
            let url = URL(fileURLWithPath: firstPath)
            let asset = AVURLAsset(url: url)

            let dur = CMTimeGetSeconds(asset.duration)
            if dur.isFinite && dur > 0 {
                self.videoDuration = dur
            }

            var naturalW = 1280
            var naturalH = 720
            if let track = asset.tracks(withMediaType: .video).first {
                let size = track.naturalSize.applying(track.preferredTransform)
                naturalW = max(10, abs(Int(size.width)))
                naturalH = max(10, abs(Int(size.height)))
            }
            self.originalWidth = naturalW
            self.originalHeight = naturalH
            self.cropOverlayView.imageSize = CGSize(width: naturalW, height: naturalH)
            self.cropOverlayView.applyRatioPreset("free")
            self.updateInfo(width: naturalW, height: naturalH, size: self.originalFileSize)

            let playerItem = AVPlayerItem(url: url)
            let p = AVPlayer(playerItem: playerItem)
            self.player = p

            let pv = AVPlayerView(frame: self.previewImageView.frame)
            pv.autoresizingMask = [.width, .height]
            pv.controlsStyle = .inline
            pv.showsFullScreenToggleButton = false
            pv.wantsLayer = true
            pv.layer?.cornerRadius = 6
            pv.layer?.masksToBounds = true
            pv.player = p
            self.playerView = pv

            self.previewImageView.isHidden = true
            self.previewImageView.superview?.addSubview(pv, positioned: .below, relativeTo: self.cropOverlayView)

            let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
            self.playerTimeObserver = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
                guard let self = self else { return }
                let sec = CMTimeGetSeconds(time)
                guard sec.isFinite else { return }
                self.onPlayheadMoved(time: sec)
            }

            if self.videoDuration > 0 {
                self.setupSliderRanges()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    guard let self = self else { return }
                    let d = CMTimeGetSeconds(playerItem.duration)
                    if d.isFinite && d > 0 {
                        self.videoDuration = d
                        self.setupSliderRanges()
                    }
                }
            }

            self.cropOverlayView.notifyCropChanged()
            return
        }

        PreviewService.shared.loadPreview(for: firstPath) { [weak self] img in
            guard let self = self, let img = img else { return }
            self.originalImage = img
            self.previewImageView.image = img

            let rep = img.representations.first
            let w = rep?.pixelsWide ?? Int(img.size.width)
            let h = rep?.pixelsHigh ?? Int(img.size.height)
            self.originalWidth = w
            self.originalHeight = h

            if let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                let maxEdge = max(cg.width, cg.height)
                let ciFull = CIImage(cgImage: cg)
                if maxEdge > 1200 {
                    let scale = 1200.0 / CGFloat(maxEdge)
                    self.previewCIImage = ciFull.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                } else {
                    self.previewCIImage = ciFull
                }
            }

            self.cropOverlayView.imageSize = CGSize(width: w, height: h)
            self.cropOverlayView.applyRatioPreset("free")

            self.updateInfo(width: w, height: h, size: self.originalFileSize)

            if self.tool.id == "compress" {
                self.updateCompressPreview(quality: self.qualitySlider?.integerValue ?? 80)
            } else if self.tool.id == "watermark" {
                self.updateWatermarkPreview()
            } else if self.tool.id == "editImage" {
                self.updateEditImagePreview()
            } else if self.tool.id == "frameImage" {
                self.updateFramePreview()
            } else if self.tool.id == "redactImage" {
                self.cropOverlayView.normX = 0.15
                self.cropOverlayView.normY = 0.25
                self.cropOverlayView.normW = 0.70
                self.cropOverlayView.normH = 0.20
                self.cropOverlayView.needsDisplay = true
                self.updateRedactPreview()
            } else if self.tool.id == "annotateImage" {
                self.updateAnnotatePreview()
            } else if self.tool.id == "createCollage" {
                self.updateCollagePreview()
            } else if self.tool.id == "cropImage" || self.tool.id == "cropVideo" {
                self.cropOverlayView.notifyCropChanged()
            } else if self.tool.id == "resizeImage" {
                if let wf = self.fieldInputs["width"] as? NSTextField { wf.stringValue = "\(w)" }
                if let hf = self.fieldInputs["height"] as? NSTextField { hf.stringValue = "\(h)" }
            }
        }
    }

    private func updateInfo(width: Int, height: Int, size: Int64) {
        var parts: [String] = []
        if width > 0 && height > 0 {
            parts.append("\(width) × \(height)")
        }
        if size > 0 {
            parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
        }
        if !parts.isEmpty {
            self.infoLabel.stringValue = parts.joined(separator: "  ·  ")
        } else {
            self.infoLabel.stringValue = "Ready"
        }
    }

    @objc private func cancelClicked() {
        window?.close()
        onClose?()
    }

    @objc private func saveClicked() {
        var params: [String: String] = [:]

        let isVideoStudio = (tool.id == "trimVideo" || tool.id == "cropVideo" || tool.id == "splitVideo" || tool.id == "editVideo")
        if isVideoStudio {
            player?.pause()
            var finalAction = "trimVideo"
            if activeVideoTab == 0 {
                finalAction = "trimVideo"
                let start = trimStartSlider?.doubleValue ?? 0.0
                var end = trimEndSlider?.doubleValue ?? videoDuration
                if end <= start { end = min(videoDuration, start + 1.0) }
                params["start"] = String(format: "%.2f", start)
                params["end"] = String(format: "%.2f", end)
            } else if activeVideoTab == 1 {
                finalAction = "cropVideo"
                let px = cropOverlayView.currentPixelRect()
                params["x"] = "\(Int(px.origin.x))"
                params["y"] = "\(Int(px.origin.y))"
                params["width"] = "\(Int(px.width))"
                params["height"] = "\(Int(px.height))"
                params["ratio"] = cropOverlayView.currentRatioKey
            } else if activeVideoTab == 2 {
                finalAction = "splitVideo"
                if splitModeSegment?.selectedSegment == 0 {
                    if !splitPoints.isEmpty {
                        params["splitPoints"] = splitPoints.map { String(format: "%.2f", $0) }.joined(separator: ", ")
                    } else {
                        params["parts"] = "2"
                    }
                } else {
                    params["parts"] = "\(selectedSplitParts)"
                }
            }

            let job = ConversionJob(Paths: paths, Action: finalAction, Parameters: params)
            let card = TaskIndicatorManager.shared.addJob(job)

            window?.close()
            onClose?()

            BackendBridge.shared.execute(
                job: job,
                onStart: { process in
                    card.process = process
                },
                progressHandler: { prog in
                    card.updateProgress(prog)
                },
                completion: { result in
                    switch result {
                    case .success(let batch):
                        card.markCompleted(result: batch)
                    case .failure(let err):
                        card.markFailed(error: err)
                    }
                }
            )
            return
        }

        if tool.id == "cropImage" || tool.id == "cropVideo" {
            let px = cropOverlayView.currentPixelRect()
            params["x"] = "\(Int(px.origin.x))"
            params["y"] = "\(Int(px.origin.y))"
            params["width"] = "\(Int(px.width))"
            params["height"] = "\(Int(px.height))"
            params["ratio"] = cropOverlayView.currentRatioKey
            if let rotPopup = fieldInputs["rotation"] as? NSPopUpButton {
                let rotTitle = rotPopup.titleOfSelectedItem ?? "0°"
                if rotTitle.contains("90") { params["rotation"] = "90" }
                else if rotTitle.contains("180") { params["rotation"] = "180" }
                else if rotTitle.contains("270") { params["rotation"] = "270" }
                else { params["rotation"] = "0" }
            }
        } else if tool.id == "redactImage" {
            let px = cropOverlayView.currentPixelRect()
            params["x"] = "\(Int(px.origin.x))"
            params["y"] = "\(Int(px.origin.y))"
            params["width"] = "\(Int(px.width))"
            params["height"] = "\(Int(px.height))"
            if let stylePopup = fieldInputs["style"] as? NSPopUpButton {
                let title = stylePopup.titleOfSelectedItem?.lowercased() ?? "solid"
                if title.contains("blur") { params["style"] = "blur" }
                else if title.contains("pixel") { params["style"] = "pixelate" }
                else { params["style"] = "solid" }
            }
            if let slider = fieldSliders["blockSize"] {
                params["blockSize"] = "\(slider.integerValue)"
            }
        } else if tool.id == "editImage" {
            for (name, slider) in fieldSliders {
                params[name] = String(format: "%.2f", slider.doubleValue)
            }
        } else if tool.id == "frameImage" {
            if let bgPopup = fieldInputs["background"] as? NSPopUpButton {
                let title = bgPopup.titleOfSelectedItem ?? "#F0EBFF"
                let hex = title.split(separator: " ").first.map(String.init) ?? "#F0EBFF"
                params["background"] = hex
            }
            if let pSlider = fieldSliders["padding"] { params["padding"] = "\(pSlider.integerValue)" }
            if let rSlider = fieldSliders["radius"] { params["radius"] = "\(rSlider.integerValue)" }
            if let sSlider = fieldSliders["shadow"] { params["shadow"] = "\(sSlider.integerValue)" }
        } else if tool.id == "annotateImage" {
            if let tf = fieldInputs["text"] as? NSTextField { params["text"] = tf.stringValue }
            if let cPopup = fieldInputs["color"] as? NSPopUpButton {
                let title = cPopup.titleOfSelectedItem ?? "#ff6500"
                let hex = title.split(separator: " ").first.map(String.init) ?? "#ff6500"
                params["color"] = hex
            }
            if let pPopup = fieldInputs["position"] as? NSPopUpButton {
                let title = pPopup.titleOfSelectedItem?.lowercased() ?? "bottom_right"
                if title.contains("top") && title.contains("left") { params["position"] = "top_left" }
                else if title.contains("top") && title.contains("right") { params["position"] = "top_right" }
                else if title.contains("bottom") && title.contains("left") { params["position"] = "bottom_left" }
                else if title.contains("center") { params["position"] = "center" }
                else { params["position"] = "bottom_right" }
            }
        } else if tool.id == "createCollage" {
            if let lPopup = fieldInputs["layout"] as? NSPopUpButton {
                let title = lPopup.titleOfSelectedItem?.lowercased() ?? "grid"
                if title.contains("hero") || title.contains("featured") { params["layout"] = "featured" }
                else if title.contains("row") { params["layout"] = "row" }
                else if title.contains("column") { params["layout"] = "column" }
                else { params["layout"] = "grid" }
            }
            if let gSlider = fieldSliders["gap"] { params["gap"] = "\(gSlider.integerValue)" }
            if let bgPopup = fieldInputs["background"] as? NSPopUpButton {
                let title = bgPopup.titleOfSelectedItem ?? "#ffffff"
                let hex = title.split(separator: " ").first.map(String.init) ?? "#ffffff"
                params["background"] = hex
            }
        } else if tool.id == "splitVideo" {
            if let partsPopup = fieldInputs["parts"] as? NSPopUpButton {
                let title = partsPopup.titleOfSelectedItem ?? "2"
                let num = title.components(separatedBy: CharacterSet.decimalDigits.inverted).first { !$0.isEmpty } ?? "2"
                params["parts"] = num
            }
            if let tf = fieldInputs["splitPoints"] as? NSTextField, !tf.stringValue.trimmingCharacters(in: .whitespaces).isEmpty {
                params["splitPoints"] = tf.stringValue
            }
        } else if tool.id == "audioToVideo" {
            if let aPopup = fieldInputs["aspect"] as? NSPopUpButton {
                let title = aPopup.titleOfSelectedItem?.lowercased() ?? "landscape"
                if title.contains("portrait") { params["aspect"] = "portrait" }
                else if title.contains("square") { params["aspect"] = "square" }
                else { params["aspect"] = "landscape" }
            }
        } else if tool.id == "redactAudio" {
            if let sField = fieldInputs["start"] as? NSTextField { params["start"] = sField.stringValue }
            if let eField = fieldInputs["end"] as? NSTextField { params["end"] = eField.stringValue }
        } else if tool.id == "organizePDF" {
            if let aPopup = fieldInputs["action"] as? NSPopUpButton {
                params["action"] = aPopup.titleOfSelectedItem ?? "Reverse All Pages"
            }
        } else if tool.id == "compress" {
            let q = qualitySlider?.integerValue ?? 80
            params["quality"] = "\(q)"
            if let sizePopup = fieldInputs["targetSize"] as? NSPopUpButton {
                let title = sizePopup.titleOfSelectedItem ?? "Auto"
                if title.contains("200 KB") { params["targetKB"] = "200" }
                else if title.contains("300 KB") { params["targetKB"] = "300" }
                else if title.contains("500 KB") { params["targetKB"] = "500" }
                else if title.contains("1 MB") { params["targetKB"] = "1024" }
                else if title.contains("2 MB") { params["targetKB"] = "2048" }
                else if title.contains("5 MB") { params["targetKB"] = "5120" }
                else if title.contains("10 MB") { params["targetKB"] = "10240" }
                else if title.contains("25 MB") { params["targetKB"] = "25600" }
                else if title.contains("50 MB") { params["targetKB"] = "51200" }
                else if title.contains("100 MB") { params["targetKB"] = "102400" }
            }
            if let edgePopup = fieldInputs["maxEdge"] as? NSPopUpButton {
                let title = edgePopup.titleOfSelectedItem ?? "Original"
                if title.contains("2560") { params["maxEdge"] = "2560" }
                else if title.contains("2000") { params["maxEdge"] = "2000" }
                else if title.contains("1920") { params["maxEdge"] = "1920" }
                else if title.contains("1500") { params["maxEdge"] = "1500" }
                else if title.contains("1280") { params["maxEdge"] = "1280" }
                else if title.contains("1000") { params["maxEdge"] = "1000" }
                else if title.contains("854") { params["maxEdge"] = "854" }
                else if title.contains("800") { params["maxEdge"] = "800" }
            }
        } else if tool.id == "watermark" {
            if let tf = fieldInputs["text"] as? NSTextField {
                let t = tf.stringValue.trimmingCharacters(in: .whitespaces)
                params["text"] = t.isEmpty ? "CONFIDENTIAL" : t
            }
            if let rPopup = fieldInputs["repeats"] as? NSPopUpButton {
                let title = rPopup.titleOfSelectedItem ?? ""
                if title.contains("Tiled") {
                    params["layout"] = "tiled"
                    params["repeats"] = "0"
                } else if title.contains("16") {
                    params["layout"] = "grid"
                    params["repeats"] = "16"
                } else if title.contains("9") {
                    params["layout"] = "grid"
                    params["repeats"] = "9"
                } else if title.contains("4") {
                    params["layout"] = "grid"
                    params["repeats"] = "4"
                } else if title.contains("Bottom Right") {
                    params["layout"] = "single"
                    params["repeats"] = "1"
                    params["position"] = "bottomRight"
                } else {
                    params["layout"] = "single"
                    params["repeats"] = "1"
                    params["position"] = "center"
                }
            }
            if let aPopup = fieldInputs["angle"] as? NSPopUpButton {
                let title = aPopup.titleOfSelectedItem ?? "45"
                if title.contains("-45") { params["angle"] = "-45"; params["rotation"] = "-45" }
                else if title.contains("90") { params["angle"] = "90"; params["rotation"] = "90" }
                else if title.contains("30") { params["angle"] = "30"; params["rotation"] = "30" }
                else if title.contains("0") { params["angle"] = "0"; params["rotation"] = "0" }
                else { params["angle"] = "45"; params["rotation"] = "45" }
            }
            if let sPopup = fieldInputs["size"] as? NSPopUpButton {
                let title = sPopup.titleOfSelectedItem ?? "48"
                if title.contains("18") { params["textSize"] = "18"; params["fontSize"] = "18" }
                else if title.contains("32") { params["textSize"] = "32"; params["fontSize"] = "32" }
                else if title.contains("72") { params["textSize"] = "72"; params["fontSize"] = "72" }
                else if title.contains("96") { params["textSize"] = "96"; params["fontSize"] = "96" }
                else { params["textSize"] = "48"; params["fontSize"] = "48" }
            }
            if let oPopup = fieldInputs["opacity"] as? NSPopUpButton {
                let title = oPopup.titleOfSelectedItem ?? "35"
                let digits = title.filter { $0.isNumber }
                params["opacity"] = digits.isEmpty ? "35" : digits
            }
            if let cPopup = fieldInputs["color"] as? NSPopUpButton {
                let title = cPopup.titleOfSelectedItem ?? "#ffffff"
                if let hex = title.split(separator: "(").last?.replacingOccurrences(of: ")", with: "").trimmingCharacters(in: .whitespaces), hex.hasPrefix("#") {
                    params["color"] = hex
                } else {
                    params["color"] = "#ffffff"
                }
            }
        } else if tool.id == "resizeImage" {
            if let wField = fieldInputs["width"] as? NSTextField {
                params["width"] = wField.stringValue
            }
            if let hField = fieldInputs["height"] as? NSTextField {
                params["height"] = hField.stringValue
            }
        } else {
            for (name, control) in fieldInputs {
                if let popup = control as? NSPopUpButton {
                    params[name] = popup.titleOfSelectedItem ?? ""
                } else if let textField = control as? NSTextField {
                    params[name] = textField.stringValue
                }
            }
        }

        let job = ConversionJob(Paths: paths, Action: tool.id, Parameters: params)
        let card = TaskIndicatorManager.shared.addJob(job)

        window?.close()
        onClose?()

        BackendBridge.shared.execute(
            job: job,
            onStart: { process in
                card.process = process
            },
            progressHandler: { prog in
                card.updateProgress(prog)
            },
            completion: { result in
                switch result {
                case .success(let batch):
                    card.markCompleted(result: batch)
                case .failure(let err):
                    card.markFailed(error: err)
                }
            }
        )
    }
}
