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

        // 3. Crisp Crop Border (Lotus Orange)
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

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 530),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Lotus · " + tool.label
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        super.init(window: window)

        window.delegate = self
        setupUI()
        loadFilePreview()
    }

    required init?(coder: NSCoder) { fatalError() }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    private func setupUI() {
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
        let iconView = NSImageView(frame: NSRect(x: 20, y: 476, width: 32, height: 32))
        if let first = paths.first {
            iconView.image = NSWorkspace.shared.icon(forFile: first)
        } else {
            iconView.image = NSImage(systemSymbolName: "doc", accessibilityDescription: nil)
        }
        container.addSubview(iconView)

        let fileName = URL(fileURLWithPath: paths.first ?? "").lastPathComponent
        let countSuffix = paths.count > 1 ? " (+\(paths.count - 1) files)" : ""
        titleLabel.frame = NSRect(x: 60, y: 488, width: 400, height: 20)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.stringValue = fileName + countSuffix
        titleLabel.lineBreakMode = .byTruncatingMiddle
        container.addSubview(titleLabel)

        infoLabel.frame = NSRect(x: 60, y: 472, width: 400, height: 16)
        infoLabel.font = NSFont.systemFont(ofSize: 11)
        infoLabel.textColor = NSColor(white: 0.8, alpha: 1.0)
        infoLabel.stringValue = "Loading..."
        container.addSubview(infoLabel)

        // Preview Container Card
        let previewContainer = NSView(frame: NSRect(x: 20, y: 200, width: 440, height: 260))
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
        cropOverlayView.isHidden = (tool.id != "cropImage")
        previewContainer.addSubview(cropOverlayView)

        container.addSubview(previewContainer)

        // Settings Form Container
        let formContainer = NSView(frame: NSRect(x: 20, y: 64, width: 440, height: 125))
        formContainer.wantsLayer = true
        container.addSubview(formContainer)

        if tool.id == "cropImage" {
            setupCropForm(in: formContainer)
        } else if tool.id == "compress" {
            setupCompressForm(in: formContainer)
        } else if tool.id == "resizeImage" {
            setupResizeForm(in: formContainer)
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

    // MARK: - Generic Form
    private func setupGenericForm(in container: NSView) {
        var yOffset: CGFloat = 75
        for field in tool.fields.prefix(3) {
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
            } else if self.tool.id == "cropImage" {
                self.cropOverlayView.notifyCropChanged()
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

        if tool.id == "cropImage" {
            let px = cropOverlayView.currentPixelRect()
            params["x"] = "\(Int(px.origin.x))"
            params["y"] = "\(Int(px.origin.y))"
            params["width"] = "\(Int(px.width))"
            params["height"] = "\(Int(px.height))"
            params["ratio"] = cropOverlayView.currentRatioKey
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
