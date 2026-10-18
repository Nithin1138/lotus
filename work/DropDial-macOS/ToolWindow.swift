import AppKit

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

        // 3. Crisp Crop Border (DropDial Orange)
        let orangeColor = NSColor(srgbRed: 1.0, green: 0.384, blue: 0.031, alpha: 1.0)
        let borderPath = NSBezierPath(roundedRect: crop, xRadius: 2.0, yRadius: 2.0)
        orangeColor.setStroke()
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
            orangeColor.setStroke()
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
            orangeColor.setStroke()
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

    private var qualityLabel: NSTextField?
    private var qualitySlider: NSSlider?

    private var originalWidth: Int = 0
    private var originalHeight: Int = 0
    private var originalFileSize: Int64 = 0
    private var originalImage: NSImage?

    init(paths: [String], tool: Catalog.ToolOption) {
        self.paths = paths
        self.tool = tool

        let winH: CGFloat
        if tool.id == "editImage" {
            winH = 680
        } else if tool.id == "frameImage" || tool.id == "annotateImage" || tool.id == "createCollage" || tool.id == "splitVideo" {
            winH = 580
        } else {
            winH = 540
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: winH),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "DropDial · " + tool.label
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
        let previewH: CGFloat = (tool.id == "editImage") ? 220 : 250
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

        if tool.id == "cropImage" || tool.id == "cropVideo" {
            setupCropForm(in: formContainer)
        } else if tool.id == "redactImage" {
            setupRedactForm(in: formContainer)
        } else if tool.id == "compress" {
            setupCompressForm(in: formContainer)
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

        let saveButton = NSButton(frame: NSRect(x: 290, y: 16, width: 170, height: 32))
        saveButton.title = "Save New File"
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r" // Return
        saveButton.bezelColor = NSColor(srgbRed: 1.0, green: 0.384, blue: 0.031, alpha: 1.0)
        saveButton.contentTintColor = .white
        saveButton.target = self
        saveButton.action = #selector(saveClicked)
        container.addSubview(saveButton)
    }

    // MARK: - Crop Form with Free Style and Presets
    private func setupCropForm(in container: NSView) {
        let ratioLabel = NSTextField(labelWithString: "Aspect Ratio:")
        ratioLabel.frame = NSRect(x: 0, y: 92, width: 110, height: 20)
        ratioLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        ratioLabel.textColor = .white
        container.addSubview(ratioLabel)

        let ratioPopup = NSPopUpButton(frame: NSRect(x: 120, y: 90, width: 200, height: 26))
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
        alignLabel.frame = NSRect(x: 0, y: 56, width: 110, height: 20)
        alignLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        alignLabel.textColor = .white
        container.addSubview(alignLabel)

        let alignPopup = NSPopUpButton(frame: NSRect(x: 120, y: 54, width: 200, height: 26))
        alignPopup.addItem(withTitle: "Center (Auto)")
        alignPopup.addItem(withTitle: "Top / Left")
        alignPopup.addItem(withTitle: "Bottom / Right")
        alignPopup.target = self
        alignPopup.action = #selector(cropParamChanged)
        container.addSubview(alignPopup)
        fieldInputs["alignment"] = alignPopup

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

        cropOverlayView.applyRatioPreset(ratioVal, alignment: alignVal)
    }

    // MARK: - Compression Form
    private func setupCompressForm(in container: NSView) {
        let label = NSTextField(labelWithString: "Compression Quality:")
        label.frame = NSRect(x: 0, y: 84, width: 170, height: 20)
        label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .white
        container.addSubview(label)

        let qValLabel = NSTextField(labelWithString: "80%")
        qValLabel.frame = NSRect(x: 360, y: 84, width: 80, height: 20)
        qValLabel.alignment = .right
        qValLabel.font = NSFont.systemFont(ofSize: 14, weight: .bold)
        qValLabel.textColor = NSColor(srgbRed: 1.0, green: 0.384, blue: 0.031, alpha: 1.0)
        container.addSubview(qValLabel)
        self.qualityLabel = qValLabel

        let slider = NSSlider(value: 80, minValue: 10, maxValue: 100, target: self, action: #selector(sliderChanged(_:)))
        slider.frame = NSRect(x: 0, y: 50, width: 440, height: 26)
        slider.numberOfTickMarks = 10
        slider.allowsTickMarkValuesOnly = false
        slider.isContinuous = true
        container.addSubview(slider)
        self.qualitySlider = slider

        let presets = [("Low (50%)", 50), ("Med (75%)", 75), ("High (80%)", 80), ("Best (95%)", 95)]
        var xOffset: CGFloat = 0
        for (name, val) in presets {
            let btn = NSButton(frame: NSRect(x: xOffset, y: 12, width: 102, height: 28))
            btn.title = name
            btn.bezelStyle = .rounded
            btn.font = NSFont.systemFont(ofSize: 11, weight: .medium)
            btn.tag = val
            btn.target = self
            btn.action = #selector(presetClicked(_:))
            container.addSubview(btn)
            xOffset += 112
        }
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        let val = Int(sender.doubleValue)
        qualityLabel?.stringValue = "\(val)%"
        updateCompressInfo(quality: val)
    }

    @objc private func presetClicked(_ sender: NSButton) {
        let val = sender.tag
        qualitySlider?.integerValue = val
        qualitySlider?.doubleValue = Double(val)
        qualityLabel?.stringValue = "\(val)%"
        updateCompressInfo(quality: val)
    }

    private func updateCompressInfo(quality: Int) {
        guard originalFileSize > 0 else { return }
        let estimatedBytes = Int64(Double(originalFileSize) * (Double(quality) / 100.0) * 0.72)
        let origStr = ByteCountFormatter.string(fromByteCount: originalFileSize, countStyle: .file)
        let estStr = ByteCountFormatter.string(fromByteCount: max(1024, estimatedBytes), countStyle: .file)

        var parts: [String] = []
        if originalWidth > 0 && originalHeight > 0 {
            parts.append("\(originalWidth) × \(originalHeight)")
        }
        parts.append("Original: \(origStr)")
        parts.append("Est. Size: ~\(estStr)")
        self.infoLabel.stringValue = parts.joined(separator: "  ·  ")
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
        let styleLabel = NSTextField(labelWithString: "Redact Style:")
        styleLabel.frame = NSRect(x: 0, y: 88, width: 110, height: 20)
        styleLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        styleLabel.textColor = .white
        container.addSubview(styleLabel)

        let stylePopup = NSPopUpButton(frame: NSRect(x: 120, y: 86, width: 220, height: 26))
        stylePopup.addItem(withTitle: "Solid Blackout")
        stylePopup.addItem(withTitle: "Gaussian Blur")
        stylePopup.addItem(withTitle: "Mosaic (Pixelate)")
        container.addSubview(stylePopup)
        fieldInputs["style"] = stylePopup

        let blockLabel = NSTextField(labelWithString: "Mosaic Grid:")
        blockLabel.frame = NSRect(x: 0, y: 52, width: 110, height: 20)
        blockLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        blockLabel.textColor = .white
        container.addSubview(blockLabel)

        let blockSlider = NSSlider(value: 18, minValue: 4, maxValue: 50, target: self, action: #selector(toolSliderChanged(_:)))
        blockSlider.frame = NSRect(x: 120, y: 50, width: 220, height: 22)
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
    }

    @objc private func resetEditSliders() {
        for item in editSliders {
            item.slider.doubleValue = item.defVal
            item.badge.stringValue = formatEditVal(item.defVal, unit: item.unit)
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
        container.addSubview(posPopup)
        fieldInputs["position"] = posPopup
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
        container.addSubview(bgPopup)
        fieldInputs["background"] = bgPopup
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

        PreviewService.shared.loadPreview(for: firstPath) { [weak self] img in
            guard let self = self, let img = img else { return }
            self.originalImage = img
            self.previewImageView.image = img

            let rep = img.representations.first
            let w = rep?.pixelsWide ?? Int(img.size.width)
            let h = rep?.pixelsHigh ?? Int(img.size.height)
            self.originalWidth = w
            self.originalHeight = h

            self.cropOverlayView.imageSize = CGSize(width: w, height: h)
            self.cropOverlayView.applyRatioPreset("free")

            self.updateInfo(width: w, height: h, size: self.originalFileSize)

            if self.tool.id == "compress" {
                self.updateCompressInfo(quality: self.qualitySlider?.integerValue ?? 80)
            } else if self.tool.id == "cropImage" || self.tool.id == "cropVideo" {
                self.cropOverlayView.notifyCropChanged()
            } else if self.tool.id == "redactImage" {
                self.cropInfoLabel.stringValue = "Redaction Area: Drag handles on image to select area to redact"
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

        if tool.id == "cropImage" || tool.id == "cropVideo" {
            let px = cropOverlayView.currentPixelRect()
            params["x"] = "\(Int(px.origin.x))"
            params["y"] = "\(Int(px.origin.y))"
            params["width"] = "\(Int(px.width))"
            params["height"] = "\(Int(px.height))"
            params["ratio"] = cropOverlayView.currentRatioKey
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
