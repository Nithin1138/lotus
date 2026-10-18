import AppKit

enum WheelMode: String, CaseIterable {
    case conversions = "CONVERT (⇧)"
    case tools = "TOOLS (⌘)"
    case actions = "ACTIONS (⌃)"

    var next: WheelMode {
        switch self {
        case .conversions: return .tools
        case .tools: return .actions
        case .actions: return .conversions
        }
    }
}

final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        DropWheelWindowController.shared.hideWheel()
    }
}

final class RadialWheelView: NSView {
    struct SliceItem {
        let id: String
        let title: String
        let iconName: String?
        let isTool: Bool
        let isAction: Bool
    }

    var items: [SliceItem] = []
    var hoveredIndex: Int = -1
    var isHubHovered: Bool = false
    var currentPaths: [String] = []
    var mode: WheelMode = .conversions

    var onSelectSlice: ((SliceItem, [String]?) -> Void)?
    var onHubClicked: (() -> Void)?
    var onFilesDropped: (([String]) -> Void)?

    private let centerRadius: CGFloat = 58
    private let innerRadius: CGFloat = 66
    private let outerRadius: CGFloat = 175
    private var trackingArea: NSTrackingArea?
    private var hubThumbnail: NSImage?

    override var acceptsFirstResponder: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([
            .fileURL,
            .URL,
            NSPasteboard.PasteboardType("NSFilenamesPboardType"),
            NSPasteboard.PasteboardType("public.file-url")
        ])
        loadDefaultItems()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        self.trackingArea = area
    }

    func loadDefaultItems() {
        switch mode {
        case .actions:
            items = Catalog.fileActions.map {
                SliceItem(id: $0.id, title: $0.title, iconName: $0.iconName, isTool: false, isAction: true)
            }
        case .tools:
            items = [
                SliceItem(id: "compress", title: "Compress", iconName: "arrow.down.circle", isTool: true, isAction: false),
                SliceItem(id: "resizeImage", title: "Resize", iconName: "arrow.up.left.and.arrow.down.right", isTool: true, isAction: false),
                SliceItem(id: "cropImage", title: "Crop", iconName: "crop", isTool: true, isAction: false),
                SliceItem(id: "rotateImage", title: "Rotate", iconName: "rotate.right", isTool: true, isAction: false),
                SliceItem(id: "ocrImage", title: "OCR", iconName: "doc.text.viewfinder", isTool: true, isAction: false),
                SliceItem(id: "watermark", title: "Watermark", iconName: "text.bubble", isTool: true, isAction: false),
                SliceItem(id: "removeMetadata", title: "Metadata", iconName: "eye.slash", isTool: true, isAction: false),
                SliceItem(id: "createPDF", title: "To PDF", iconName: "doc.on.doc", isTool: true, isAction: false)
            ]
        case .conversions:
            items = [
                SliceItem(id: "convert:jpg", title: "JPG", iconName: nil, isTool: false, isAction: false),
                SliceItem(id: "convert:png", title: "PNG", iconName: nil, isTool: false, isAction: false),
                SliceItem(id: "convert:webp", title: "WEBP", iconName: nil, isTool: false, isAction: false),
                SliceItem(id: "convert:pdf", title: "PDF", iconName: nil, isTool: false, isAction: false),
                SliceItem(id: "convert:mp4", title: "MP4", iconName: nil, isTool: false, isAction: false),
                SliceItem(id: "convert:mp3", title: "MP3", iconName: nil, isTool: false, isAction: false),
                SliceItem(id: "convert:zip", title: "ZIP", iconName: nil, isTool: false, isAction: false),
                SliceItem(id: "convert:gif", title: "GIF", iconName: nil, isTool: false, isAction: false)
            ]
        }
        hubThumbnail = nil
        hoveredIndex = -1
        needsDisplay = true
    }

    func configure(paths: [String], mode: WheelMode) {
        self.currentPaths = paths
        self.mode = mode

        guard let first = paths.first else {
            loadDefaultItems()
            return
        }

        switch mode {
        case .actions:
            items = Catalog.fileActions.map {
                SliceItem(id: $0.id, title: $0.title, iconName: $0.iconName, isTool: false, isAction: true)
            }
        case .tools:
            if paths.count > 1 {
                let multi = Catalog.multiFileTools(for: paths)
                if !multi.isEmpty {
                    items = multi.prefix(8).map {
                        SliceItem(id: $0.id, title: $0.label, iconName: $0.iconName, isTool: true, isAction: false)
                    }
                } else {
                    let cat = Catalog.category(for: first)
                    items = Catalog.tools(for: cat).prefix(8).map {
                        SliceItem(id: $0.id, title: $0.label, iconName: $0.iconName, isTool: true, isAction: false)
                    }
                }
            } else {
                let cat = Catalog.category(for: first)
                let tools = Catalog.tools(for: cat)
                items = tools.prefix(8).map {
                    SliceItem(id: $0.id, title: $0.label, iconName: $0.iconName, isTool: true, isAction: false)
                }
            }
        case .conversions:
            let formats = Catalog.targetFormats(for: first)
            items = formats.prefix(8).map {
                SliceItem(id: "convert:\($0)", title: $0.uppercased(), iconName: nil, isTool: false, isAction: false)
            }
        }

        hoveredIndex = -1

        PreviewService.shared.loadPreview(for: first, targetSize: CGSize(width: 88, height: 88)) { [weak self] img in
            self?.hubThumbnail = img
            self?.needsDisplay = true
        }

        needsDisplay = true
    }

    func setMode(_ newMode: WheelMode) {
        guard self.mode != newMode else { return }
        self.mode = newMode
        NSSound(named: "Pop")?.play()
        if !currentPaths.isEmpty {
            configure(paths: currentPaths, mode: newMode)
        } else {
            loadDefaultItems()
        }
    }

    // MARK: - Keyboard & Modifier Controls
    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        if event.modifierFlags.contains(.control) {
            setMode(.actions)
        } else if event.modifierFlags.contains(.command) {
            setMode(.tools)
        } else if event.modifierFlags.contains(.shift) {
            setMode(.conversions)
        }
    }

    override func keyDown(with event: NSEvent) {
        let code = event.keyCode
        if code == 53 { // Escape
            DropWheelWindowController.shared.hideWheel()
            return
        }
        if code == 100 { // F8 -> Formats Mode
            DropWheelWindowController.shared.toggleWheel(mode: .conversions)
            return
        }
        if code == 101 { // F9 -> Tools Mode
            DropWheelWindowController.shared.toggleWheel(mode: .tools)
            return
        }
        if code == 109 { // F10 -> Actions Mode
            DropWheelWindowController.shared.toggleWheel(mode: .actions)
            return
        }
        if code == 48 { // Tab -> Cycle Modes
            setMode(mode.next)
            return
        }
        if code == 123 || code == 126 { // Left or Up arrow
            if !items.isEmpty {
                hoveredIndex = (hoveredIndex - 1 + items.count) % items.count
                NSSound(named: "Tink")?.play()
                needsDisplay = true
            }
            return
        }
        if code == 124 || code == 125 { // Right or Down arrow
            if !items.isEmpty {
                hoveredIndex = (hoveredIndex + 1) % items.count
                NSSound(named: "Tink")?.play()
                needsDisplay = true
            }
            return
        }
        if code == 36 || code == 49 { // Return or Space
            if hoveredIndex >= 0 && hoveredIndex < items.count {
                onSelectSlice?(items[hoveredIndex], currentPaths)
            } else {
                onHubClicked?()
            }
            return
        }

        // Quick numbers 1..9
        let numKeyMap: [UInt16: Int] = [18: 0, 19: 1, 20: 2, 21: 3, 23: 4, 22: 5, 26: 6, 28: 7, 25: 8]
        if let idx = numKeyMap[code], idx < items.count {
            onSelectSlice?(items[idx], currentPaths)
            return
        }

        super.keyDown(with: event)
    }

    // MARK: - Geometry & Hit Testing
    private func sliceAngle() -> CGFloat {
        guard !items.isEmpty else { return 360 }
        return 360.0 / CGFloat(items.count)
    }

    private func indexForPoint(_ point: NSPoint) -> Int {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let dx = point.x - center.x
        let dy = point.y - center.y
        let dist = sqrt(dx * dx + dy * dy)

        if dist < centerRadius {
            return -2 // Hub
        }
        if dist < innerRadius || dist > outerRadius {
            return -1 // Outside
        }

        let rad = atan2(dy, dx)
        var deg = rad * 180.0 / .pi
        deg = 90.0 - deg
        if deg < 0 { deg += 360.0 }

        let angle = sliceAngle()
        let idx = Int(deg / angle)
        return (idx >= 0 && idx < items.count) ? idx : -1
    }

    // MARK: - Mouse Events
    override func mouseMoved(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        let hit = indexForPoint(pt)
        let newHub = (hit == -2)
        let newIndex = (hit >= 0) ? hit : -1

        if newIndex != hoveredIndex || newHub != isHubHovered {
            if (newIndex != hoveredIndex && newIndex >= 0) || (newHub != isHubHovered && newHub) {
                NSSound(named: "Tink")?.play()
            }
            hoveredIndex = newIndex
            isHubHovered = newHub
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        hoveredIndex = -1
        isHubHovered = false
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        let hit = indexForPoint(pt)
        if hit == -2 {
            onHubClicked?()
        } else if hit >= 0 && hit < items.count {
            onSelectSlice?(items[hit], currentPaths)
        }
    }

    // MARK: - Drag & Drop Extraction
    func extractPaths(from sender: NSDraggingInfo) -> [String] {
        let pboard = sender.draggingPasteboard
        var paths: [String] = []

        if let urls = pboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            paths.append(contentsOf: urls.filter { $0.isFileURL }.map { $0.path })
        }
        if paths.isEmpty, let plist = pboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] {
            paths.append(contentsOf: plist.filter { FileManager.default.fileExists(atPath: $0) })
        }
        if paths.isEmpty, let pasteboardItems = pboard.pasteboardItems {
            for item in pasteboardItems {
                if let str = item.string(forType: .fileURL), let u = URL(string: str), u.isFileURL {
                    paths.append(u.path)
                }
            }
        }
        var seen = Set<String>()
        var unique: [String] = []
        for p in paths {
            if !seen.contains(p) {
                seen.insert(p)
                unique.append(p)
            }
        }
        return unique
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let paths = extractPaths(from: sender)
        if !paths.isEmpty {
            self.currentPaths = paths
            configure(paths: paths, mode: mode)
            DropWheelWindowController.shared.setLoadedPaths(paths)
        }
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pt = convert(sender.draggingLocation, from: nil)
        let hit = indexForPoint(pt)
        let newHub = (hit == -2)
        let newIndex = (hit >= 0) ? hit : -1

        if newIndex != hoveredIndex || newHub != isHubHovered {
            if (newIndex != hoveredIndex && newIndex >= 0) || (newHub != isHubHovered && newHub) {
                NSSound(named: "Tink")?.play()
            }
            hoveredIndex = newIndex
            isHubHovered = newHub
            needsDisplay = true
        }
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        hoveredIndex = -1
        isHubHovered = false
        needsDisplay = true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pt = convert(sender.draggingLocation, from: nil)
        let hit = indexForPoint(pt)

        hoveredIndex = -1
        isHubHovered = false
        needsDisplay = true

        let paths = extractPaths(from: sender)
        guard !paths.isEmpty else { return false }

        self.currentPaths = paths
        DropWheelWindowController.shared.setLoadedPaths(paths)

        if hit >= 0 && hit < self.items.count {
            let slice = self.items[hit]
            onSelectSlice?(slice, paths)
        } else {
            onFilesDropped?(paths)
        }
        return true
    }

    // MARK: - Drawing
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let angleStep = sliceAngle()

        // 1. Solid Dark Backing Disc (prevents background bleed)
        context.saveGState()
        let backingPath = CGPath(ellipseIn: CGRect(x: center.x - outerRadius, y: center.y - outerRadius, width: outerRadius * 2, height: outerRadius * 2), transform: nil)
        context.addPath(backingPath)
        context.setFillColor(NSColor(srgbRed: 0.11, green: 0.12, blue: 0.14, alpha: 0.98).cgColor)
        context.setShadow(offset: CGSize(width: 0, height: -6), blur: 24, color: NSColor.black.withAlphaComponent(0.6).cgColor)
        context.fillPath()
        context.restoreGState()

        // 2. Draw Slices (Petals)
        let lotusOrange = NSColor(srgbRed: 1.0, green: 0.384, blue: 0.031, alpha: 1.0) // #FF6208
        let normalSliceBg = NSColor(srgbRed: 0.16, green: 0.17, blue: 0.20, alpha: 0.98)
        let sliceBorderColor = NSColor(white: 1.0, alpha: 0.14)

        for (i, item) in items.enumerated() {
            let isHovered = (i == hoveredIndex)

            let startDeg = 90.0 - CGFloat(i) * angleStep
            let endDeg = startDeg - angleStep

            let slicePath = NSBezierPath()
            slicePath.appendArc(withCenter: center, radius: outerRadius, startAngle: startDeg, endAngle: endDeg, clockwise: true)
            slicePath.appendArc(withCenter: center, radius: innerRadius, startAngle: endDeg, endAngle: startDeg, clockwise: false)
            slicePath.close()

            if isHovered {
                lotusOrange.setFill()
            } else {
                normalSliceBg.setFill()
            }
            slicePath.fill()

            sliceBorderColor.setStroke()
            slicePath.lineWidth = 1.0
            slicePath.stroke()

            // Draw Icon + Label
            let midDeg = (startDeg + endDeg) / 2.0
            let midRad = midDeg * .pi / 180.0
            let midRadius = (innerRadius + outerRadius) / 2.0
            let tx = center.x + midRadius * cos(midRad)
            let ty = center.y + midRadius * sin(midRad)

            if let iconName = item.iconName, let symbol = NSImage(systemSymbolName: iconName, accessibilityDescription: nil) {
                let iconSize: CGFloat = 16
                let iconRect = NSRect(x: tx - iconSize / 2, y: ty + 2, width: iconSize, height: iconSize)
                let tinted = symbol.copy() as! NSImage
                tinted.isTemplate = true
                NSColor.white.set()
                tinted.draw(in: iconRect)

                let font = NSFont.systemFont(ofSize: 11, weight: .semibold)
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
                let str = NSAttributedString(string: item.title, attributes: attrs)
                let sz = str.size()
                str.draw(at: NSPoint(x: tx - sz.width / 2, y: ty - sz.height - 2))
            } else {
                let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
                let titleStr = NSAttributedString(string: item.title, attributes: attrs)
                let strSize = titleStr.size()
                let strRect = NSRect(
                    x: tx - strSize.width / 2.0,
                    y: ty - strSize.height / 2.0,
                    width: strSize.width,
                    height: strSize.height
                )
                titleStr.draw(in: strRect)
            }
        }

        // 3. Center Hub (Circle)
        let hubRect = NSRect(x: center.x - centerRadius, y: center.y - centerRadius, width: centerRadius * 2, height: centerRadius * 2)
        let hubPath = NSBezierPath(ovalIn: hubRect)

        let hubBg = isHubHovered ? NSColor(srgbRed: 0.18, green: 0.19, blue: 0.22, alpha: 1.0) : NSColor(srgbRed: 0.12, green: 0.13, blue: 0.15, alpha: 1.0)
        hubBg.setFill()
        hubPath.fill()

        lotusOrange.setStroke()
        hubPath.lineWidth = 2.0
        hubPath.stroke()

        // Hub Content
        if hoveredIndex >= 0 && hoveredIndex < items.count {
            // Hovered Slice Preview / Title
            let hoveredItem = items[hoveredIndex]
            let hFont = NSFont.systemFont(ofSize: 13, weight: .bold)
            let hAttrs: [NSAttributedString.Key: Any] = [.font: hFont, .foregroundColor: lotusOrange]
            let hStr = NSAttributedString(string: hoveredItem.title, attributes: hAttrs)
            let hSize = hStr.size()
            hStr.draw(at: NSPoint(x: center.x - hSize.width / 2, y: center.y + 4))

            let subFont = NSFont.systemFont(ofSize: 9, weight: .medium)
            let subText: String
            if hoveredItem.isAction {
                subText = Catalog.fileActions.first(where: { $0.id == hoveredItem.id })?.label ?? "File Action"
            } else if hoveredItem.isTool {
                subText = "Tool"
            } else {
                subText = "Convert to \(hoveredItem.title)"
            }
            let subAttrs: [NSAttributedString.Key: Any] = [.font: subFont, .foregroundColor: NSColor(white: 0.8, alpha: 1.0)]
            let subStr = NSAttributedString(string: subText, attributes: subAttrs)
            let sSize = subStr.size()
            subStr.draw(at: NSPoint(x: center.x - sSize.width / 2, y: center.y - 16))

            let modeFont = NSFont.systemFont(ofSize: 9, weight: .bold)
            let modeAttrs: [NSAttributedString.Key: Any] = [.font: modeFont, .foregroundColor: NSColor(white: 0.5, alpha: 1.0)]
            let modeStr = NSAttributedString(string: mode.rawValue, attributes: modeAttrs)
            let mSize = modeStr.size()
            modeStr.draw(at: NSPoint(x: center.x - mSize.width / 2, y: center.y - 34))

        } else if let first = currentPaths.first {
            let thumbRect = NSRect(x: center.x - 18, y: center.y + 4, width: 36, height: 36)
            if let thumb = hubThumbnail {
                let thumbPath = NSBezierPath(ovalIn: thumbRect)
                context.saveGState()
                thumbPath.addClip()
                thumb.draw(in: thumbRect)
                context.restoreGState()
                lotusOrange.setStroke()
                thumbPath.lineWidth = 1.5
                thumbPath.stroke()
            } else {
                let icon = NSWorkspace.shared.icon(forFile: first)
                icon.draw(in: thumbRect)
            }

            let name: String
            if currentPaths.count > 1 {
                name = "\(currentPaths.count) items"
            } else {
                name = URL(fileURLWithPath: first).lastPathComponent
            }
            let nameFont = NSFont.systemFont(ofSize: 10, weight: .semibold)
            let nameAttrs: [NSAttributedString.Key: Any] = [.font: nameFont, .foregroundColor: NSColor.white]
            let nameStr = NSAttributedString(string: name, attributes: nameAttrs)
            let nRect = NSRect(x: center.x - 45, y: center.y - 18, width: 90, height: 14)
            nameStr.draw(in: nRect)

            let modeFont = NSFont.systemFont(ofSize: 9, weight: .bold)
            let modeAttrs: [NSAttributedString.Key: Any] = [.font: modeFont, .foregroundColor: lotusOrange]
            let modeStr = NSAttributedString(string: mode.rawValue, attributes: modeAttrs)
            let mSize = modeStr.size()
            modeStr.draw(at: NSPoint(x: center.x - mSize.width / 2, y: center.y - 34))
        } else {
            let titleFont = NSFont.systemFont(ofSize: 14, weight: .bold)
            let lotusAttrs: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: lotusOrange]
            let lotusStr = NSAttributedString(string: "Lotus", attributes: lotusAttrs)
            let lSize = lotusStr.size()
            lotusStr.draw(at: NSPoint(x: center.x - lSize.width / 2, y: center.y + 8))

            let subFont = NSFont.systemFont(ofSize: 10, weight: .medium)
            let subAttrs: [NSAttributedString.Key: Any] = [.font: subFont, .foregroundColor: NSColor(white: 0.75, alpha: 1.0)]
            let subStr = NSAttributedString(string: "Drop files\nor click", attributes: subAttrs)
            let sSize = subStr.size()
            subStr.draw(at: NSPoint(x: center.x - sSize.width / 2, y: center.y - 22))

            let modeFont = NSFont.systemFont(ofSize: 9, weight: .bold)
            let modeAttrs: [NSAttributedString.Key: Any] = [.font: modeFont, .foregroundColor: NSColor(white: 0.5, alpha: 1.0)]
            let modeStr = NSAttributedString(string: mode.rawValue, attributes: modeAttrs)
            let mSize = modeStr.size()
            modeStr.draw(at: NSPoint(x: center.x - mSize.width / 2, y: center.y - 42))
        }
    }
}

final class DropWheelWindowController: NSWindowController {
    static let shared = DropWheelWindowController()

    private let wheelView = RadialWheelView()
    private var currentPaths: [String] = []
    private var currentMode: WheelMode = .conversions
    private var activeToolControllers: [ToolWindowController] = []

    private var outsideClickMonitor: Any?
    private var localOutsideClickMonitor: Any?

    init() {
        let size: CGFloat = 380
        let panel = KeyPanel(
            contentRect: NSRect(x: 0, y: 0, width: size, height: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.registerForDraggedTypes([
            .fileURL,
            .URL,
            NSPasteboard.PasteboardType("NSFilenamesPboardType"),
            NSPasteboard.PasteboardType("public.file-url")
        ])
        panel.center()
        super.init(window: panel)

        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        wheelView.frame = contentView.bounds
        wheelView.autoresizingMask = [.width, .height]

        wheelView.onFilesDropped = { [weak self] paths in
            self?.loadFiles(paths)
        }

        wheelView.onHubClicked = { [weak self] in
            guard let self = self else { return }
            if self.currentPaths.isEmpty {
                self.pickFiles()
            } else {
                self.currentMode = self.currentMode.next
                self.wheelView.setMode(self.currentMode)
            }
        }

        wheelView.onSelectSlice = { [weak self] item, paths in
            self?.handleSliceSelected(item, paths: paths)
        }

        contentView.addSubview(wheelView)
    }

    func setLoadedPaths(_ paths: [String]) {
        self.currentPaths = paths
    }

    func showWheel() {
        showAtCursor(mode: currentMode)
    }

    func showAtCursor(mode: WheelMode) {
        let mouse = NSEvent.mouseLocation
        let size: CGFloat = 380
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main ?? NSScreen()
        let frame = screen.visibleFrame

        // Outer line of the wheel at the cursor so the file in Finder is NOT covered
        let outerRimInset: CGFloat = 16.0
        var x = mouse.x - outerRimInset

        // If placing to the right would overflow the screen, place to the left of the cursor
        if x + size > frame.maxX - 10 {
            x = mouse.x - size + outerRimInset
        }

        // Vertically center the wheel relative to the cursor
        var y = mouse.y - size / 2.0
        y = max(frame.minY + 10, min(frame.maxY - size - 10, y))
        x = max(frame.minX + 10, min(frame.maxX - size - 10, x))

        window?.setFrame(NSRect(x: x, y: y, width: size, height: size), display: true)
        self.currentMode = mode
        if !currentPaths.isEmpty {
            wheelView.configure(paths: currentPaths, mode: mode)
        } else {
            wheelView.mode = mode
            wheelView.loadDefaultItems()
        }
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(wheelView)
        NSApp.activate(ignoringOtherApps: true)
        installOutsideClickMonitors()
    }

    func hideWheel() {
        removeOutsideClickMonitors()
        window?.orderOut(nil)
    }

    func toggleWheel(mode: WheelMode? = nil) {
        if window?.isVisible == true {
            if let targetMode = mode, targetMode != self.currentMode {
                self.currentMode = targetMode
                wheelView.setMode(targetMode)
            } else {
                hideWheel()
            }
        } else {
            showAtCursor(mode: mode ?? currentMode)
        }
    }

    func loadFiles(_ paths: [String], mode: WheelMode = .conversions) {
        self.currentPaths = paths
        self.currentMode = mode
        wheelView.configure(paths: paths, mode: mode)
        showAtCursor(mode: mode)
    }

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Select"

        if panel.runModal() == .OK {
            let paths = panel.urls.map { $0.path }
            loadFiles(paths)
        }
    }

    private func installOutsideClickMonitors() {
        removeOutsideClickMonitors()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp, .rightMouseDown]) { [weak self] _ in
            guard let self = self, let win = self.window, win.isVisible else { return }
            let mouseLoc = NSEvent.mouseLocation
            if !win.frame.contains(mouseLoc) {
                DispatchQueue.main.async {
                    self.hideWheel()
                }
            }
        }
        localOutsideClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp, .rightMouseDown]) { [weak self] event in
            guard let self = self, let win = self.window, win.isVisible else { return event }
            let mouseLoc = NSEvent.mouseLocation
            if !win.frame.contains(mouseLoc) {
                DispatchQueue.main.async {
                    self.hideWheel()
                }
            }
            return event
        }
    }

    private func removeOutsideClickMonitors() {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
        if let monitor = localOutsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            localOutsideClickMonitor = nil
        }
    }

    private func handleSliceSelected(_ item: RadialWheelView.SliceItem, paths: [String]? = nil) {
        let activePaths: [String]
        if let paths = paths, !paths.isEmpty {
            activePaths = paths
            self.currentPaths = paths
        } else if !self.currentPaths.isEmpty {
            activePaths = self.currentPaths
        } else {
            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = true
            panel.prompt = "Choose files to \(item.title)"

            if panel.runModal() == .OK {
                activePaths = panel.urls.map { $0.path }
                self.currentPaths = activePaths
            } else {
                return
            }
        }

        guard !activePaths.isEmpty else { return }

        // 1. Check if Action (AirDrop, Float Shelf, Copy, Move, Copy Path, Terminal)
        if item.isAction || item.id.hasPrefix("action:") {
            executeFileAction(item.id, paths: activePaths)
            self.currentPaths = []
            self.wheelView.loadDefaultItems()
            hideWheel()
            return
        }

        // 2. Check if Tool
        if item.isTool {
            if activePaths.count > 1 {
                let multi = Catalog.multiFileTools(for: activePaths)
                if let matched = multi.first(where: { $0.id == item.id }), matched.fields.isEmpty {
                    // Tool runs grouped on all files without extra modal!
                    executeJob(action: item.id, paths: activePaths, params: nil)
                    return
                }
            }

            guard let first = activePaths.first else { return }
            let cat = Catalog.category(for: first)
            let tool = Catalog.tools(for: cat).first(where: { $0.id == item.id })

            if let tool = tool, !tool.fields.isEmpty {
                let toolCtrl = ToolWindowController(paths: activePaths, tool: tool)
                activeToolControllers.append(toolCtrl)
                toolCtrl.onClose = { [weak self, weak toolCtrl] in
                    self?.activeToolControllers.removeAll(where: { $0 === toolCtrl })
                }
                toolCtrl.showWindow(nil)
                toolCtrl.window?.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                self.currentPaths = []
                self.wheelView.loadDefaultItems()
                hideWheel()
                return
            }
        }

        // 3. Conversion or parameterless Tool
        executeJob(action: item.id, paths: activePaths, params: nil)
    }

    private func executeFileAction(_ actionId: String, paths: [String]) {
        switch actionId {
        case "action:airDrop":
            let urls = paths.map { URL(fileURLWithPath: $0) }
            if let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls) {
                service.perform(withItems: urls)
            } else {
                let picker = NSSharingServicePicker(items: urls)
                if let view = window?.contentView {
                    picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
                }
            }

        case "action:float":
            FloatShelfWindowController.shared.addFiles(paths)

        case "action:copy":
            let urls = paths.map { URL(fileURLWithPath: $0) as NSURL }
            let pboard = NSPasteboard.general
            pboard.clearContents()
            pboard.writeObjects(urls)

        case "action:move":
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.prompt = "Move Here"
            panel.title = "Choose Destination Folder"
            if panel.runModal() == .OK, let destDir = panel.url {
                for p in paths {
                    let src = URL(fileURLWithPath: p)
                    let dst = destDir.appendingPathComponent(src.lastPathComponent)
                    try? FileManager.default.moveItem(at: src, to: dst)
                }
            }

        case "action:copyPath":
            let pboard = NSPasteboard.general
            pboard.clearContents()
            pboard.setString(paths.joined(separator: "\n"), forType: .string)

        case "action:openTerminal":
            if let first = paths.first {
                let folder = URL(fileURLWithPath: first).deletingLastPathComponent().path
                let escaped = folder.replacingOccurrences(of: "\"", with: "\\\"")
                let script = "tell application \"Terminal\" to do script \"cd \\\"\(escaped)\\\"\""
                var error: NSDictionary?
                NSAppleScript(source: script)?.executeAndReturnError(&error)
            }

        default:
            break
        }
    }

    private func executeJob(action: String, paths: [String], params: [String: String]?) {
        let job = ConversionJob(Paths: paths, Action: action, Parameters: params)
        let card = TaskIndicatorManager.shared.addJob(job)
        self.currentPaths = []
        self.wheelView.loadDefaultItems()
        hideWheel()

        BackendBridge.shared.execute(
            job: job,
            onStart: { process in card.process = process },
            progressHandler: { prog in card.updateProgress(prog) },
            completion: { result in
                switch result {
                case .success(let batch): card.markCompleted(result: batch)
                case .failure(let err): card.markFailed(error: err)
                }
            }
        )
    }
}
