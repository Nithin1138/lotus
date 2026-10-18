import AppKit

enum WheelMode: String, CaseIterable {
    case conversions = "Convert"
    case tools = "Tools"
    case actions = "Actions"

    var shortcutKey: String {
        switch self {
        case .conversions: return "⇧"
        case .tools: return "⌘"
        case .actions: return "⌃"
        }
    }

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
    var hoveredTopBarIndex: Int = -1 // 0: Convert, 1: Tools, 2: Actions
    var currentPaths: [String] = []
    var mode: WheelMode = .conversions

    var onSelectSlice: ((SliceItem, [String]?) -> Void)?
    var onHubClicked: (() -> Void)?
    var onFilesDropped: (([String]) -> Void)?

    let wheelCenter = CGPoint(x: 210, y: 200)
    let innerRadius: CGFloat = 66
    let outerRadius: CGFloat = 172
    let backdropRadius: CGFloat = 186
    let topBarRect = NSRect(x: 210 - 132, y: 390, width: 264, height: 38)

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
                SliceItem(id: "convert:png", title: "PNG", iconName: nil, isTool: false, isAction: false),
                SliceItem(id: "convert:webp", title: "WEBP", iconName: nil, isTool: false, isAction: false),
                SliceItem(id: "convert:heic", title: "HEIC", iconName: nil, isTool: false, isAction: false),
                SliceItem(id: "convert:tiff", title: "TIFF", iconName: nil, isTool: false, isAction: false),
                SliceItem(id: "convert:avif", title: "AVIF", iconName: nil, isTool: false, isAction: false),
                SliceItem(id: "convert:bmp", title: "BMP", iconName: nil, isTool: false, isAction: false),
                SliceItem(id: "convert:pdf", title: "PDF", iconName: nil, isTool: false, isAction: false),
                SliceItem(id: "convert:jpg", title: "JPG", iconName: nil, isTool: false, isAction: false)
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
        // 1. Check top pill bar
        if topBarRect.contains(point) {
            let btnW = (topBarRect.width - 8) / 3.0
            let localX = point.x - (topBarRect.minX + 4)
            let btnIdx = Int(localX / btnW)
            return -10 - max(0, min(2, btnIdx)) // -10: Convert, -11: Tools, -12: Actions
        }

        let dx = point.x - wheelCenter.x
        let dy = point.y - wheelCenter.y
        let dist = sqrt(dx * dx + dy * dy)

        if dist < innerRadius {
            return -2 // Center Hole / Hub
        }
        if dist > outerRadius {
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
        let newTopBar = (hit <= -10) ? (-hit - 10) : -1

        if newIndex != hoveredIndex || newHub != isHubHovered || newTopBar != hoveredTopBarIndex {
            if (newIndex != hoveredIndex && newIndex >= 0) || (newTopBar != hoveredTopBarIndex && newTopBar >= 0) {
                NSSound(named: "Tink")?.play()
            }
            hoveredIndex = newIndex
            isHubHovered = newHub
            hoveredTopBarIndex = newTopBar
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        hoveredIndex = -1
        isHubHovered = false
        hoveredTopBarIndex = -1
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        let hit = indexForPoint(pt)

        if hit <= -10 {
            // Clicked top bar
            let btnIdx = -hit - 10
            let targetMode: WheelMode = (btnIdx == 0) ? .conversions : (btnIdx == 1) ? .tools : .actions
            setMode(targetMode)
            return
        }

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
        let newTopBar = (hit <= -10) ? (-hit - 10) : -1

        if newTopBar >= 0 && newTopBar != hoveredTopBarIndex {
            // Dragged over a top mode button -> auto switch mode!
            let targetMode: WheelMode = (newTopBar == 0) ? .conversions : (newTopBar == 1) ? .tools : .actions
            setMode(targetMode)
        }

        if newIndex != hoveredIndex || newHub != isHubHovered || newTopBar != hoveredTopBarIndex {
            if (newIndex != hoveredIndex && newIndex >= 0) || (newTopBar != hoveredTopBarIndex && newTopBar >= 0) {
                NSSound(named: "Tink")?.play()
            }
            hoveredIndex = newIndex
            isHubHovered = newHub
            hoveredTopBarIndex = newTopBar
            needsDisplay = true
        }
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        hoveredIndex = -1
        isHubHovered = false
        hoveredTopBarIndex = -1
        needsDisplay = true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pt = convert(sender.draggingLocation, from: nil)
        let hit = indexForPoint(pt)

        hoveredIndex = -1
        isHubHovered = false
        hoveredTopBarIndex = -1
        needsDisplay = true

        let paths = extractPaths(from: sender)
        guard !paths.isEmpty else { return false }

        self.currentPaths = paths
        DropWheelWindowController.shared.setLoadedPaths(paths)

        if hit <= -10 {
            let btnIdx = -hit - 10
            let targetMode: WheelMode = (btnIdx == 0) ? .conversions : (btnIdx == 1) ? .tools : .actions
            setMode(targetMode)
            return true
        }

        if hit >= 0 && hit < self.items.count {
            let slice = self.items[hit]
            onSelectSlice?(slice, paths)
        } else {
            onFilesDropped?(paths)
        }
        return true
    }

    // MARK: - Rounded Petal Path Generator
    private func createRoundedPetal(center: CGPoint, innerR: CGFloat, outerR: CGFloat, startDeg: CGFloat, endDeg: CGFloat, cornerRadius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let cr = cornerRadius

        let daOuter = (cr / outerR) * (180.0 / .pi)
        let daInner = (cr / innerR) * (180.0 / .pi)

        let radStart = startDeg * .pi / 180.0
        let radEnd = endDeg * .pi / 180.0

        let p1 = CGPoint(x: center.x + (innerR + cr) * cos(radStart), y: center.y + (innerR + cr) * sin(radStart))
        let c_os = CGPoint(x: center.x + outerR * cos(radStart), y: center.y + outerR * sin(radStart))
        let p_os_arc = CGPoint(x: center.x + outerR * cos((startDeg - daOuter) * .pi / 180), y: center.y + outerR * sin((startDeg - daOuter) * .pi / 180))

        path.move(to: p1)
        path.addArc(tangent1End: c_os, tangent2End: p_os_arc, radius: cr)
        path.addArc(center: center, radius: outerR, startAngle: (startDeg - daOuter) * .pi / 180, endAngle: (endDeg + daOuter) * .pi / 180, clockwise: true)

        let c_oe = CGPoint(x: center.x + outerR * cos(radEnd), y: center.y + outerR * sin(radEnd))
        let p_oe_radial = CGPoint(x: center.x + (outerR - cr) * cos(radEnd), y: center.y + (outerR - cr) * sin(radEnd))
        path.addArc(tangent1End: c_oe, tangent2End: p_oe_radial, radius: cr)

        let c_ie = CGPoint(x: center.x + innerR * cos(radEnd), y: center.y + innerR * sin(radEnd))
        let p_ie_arc = CGPoint(x: center.x + innerR * cos((endDeg + daInner) * .pi / 180), y: center.y + innerR * sin((endDeg + daInner) * .pi / 180))
        path.addArc(tangent1End: c_ie, tangent2End: p_ie_arc, radius: cr)

        path.addArc(center: center, radius: innerR, startAngle: (endDeg + daInner) * .pi / 180, endAngle: (startDeg - daInner) * .pi / 180, clockwise: false)

        let c_is = CGPoint(x: center.x + innerR * cos(radStart), y: center.y + innerR * sin(radStart))
        path.addArc(tangent1End: c_is, tangent2End: p1, radius: cr)
        path.closeSubpath()

        return path
    }

    // MARK: - Drawing
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // 1. Soft Outer Halo / Backing Disc
        context.saveGState()
        let haloPath = CGPath(ellipseIn: CGRect(x: wheelCenter.x - backdropRadius, y: wheelCenter.y - backdropRadius, width: backdropRadius * 2, height: backdropRadius * 2), transform: nil)
        context.addPath(haloPath)
        context.setFillColor(NSColor(srgbRed: 0.88, green: 0.90, blue: 0.92, alpha: 0.55).cgColor)
        context.setShadow(offset: CGSize(width: 0, height: -4), blur: 18, color: NSColor.black.withAlphaComponent(0.12).cgColor)
        context.fillPath()
        context.restoreGState()

        // 2. Draw Petals with Rounded Corners & Gaps
        let angleStep = sliceAngle()
        let gap: CGFloat = 4.0

        for (i, item) in items.enumerated() {
            let isHovered = (i == hoveredIndex)

            let s = 90.0 - CGFloat(i) * angleStep - gap / 2.0
            let e = s - (angleStep - gap)
            let petal = createRoundedPetal(center: wheelCenter, innerR: innerRadius, outerR: outerRadius, startDeg: s, endDeg: e, cornerRadius: 12)

            // Fill & Shadow
            context.saveGState()
            context.addPath(petal)
            if isHovered {
                context.setFillColor(NSColor(srgbRed: 1.0, green: 0.33, blue: 0.0, alpha: 1.0).cgColor)
                context.setShadow(offset: CGSize(width: 0, height: -2), blur: 6, color: NSColor(srgbRed: 1.0, green: 0.33, blue: 0.0, alpha: 0.4).cgColor)
            } else {
                context.setFillColor(NSColor(srgbRed: 0.94, green: 0.95, blue: 0.96, alpha: 0.98).cgColor)
                context.setShadow(offset: CGSize(width: 0, height: -1), blur: 3, color: NSColor.black.withAlphaComponent(0.06).cgColor)
            }
            context.fillPath()
            context.restoreGState()

            // Subtle Stroke Border
            context.saveGState()
            context.addPath(petal)
            if isHovered {
                context.setStrokeColor(NSColor(srgbRed: 0.90, green: 0.28, blue: 0.0, alpha: 0.8).cgColor)
            } else {
                context.setStrokeColor(NSColor(white: 1.0, alpha: 0.8).cgColor)
            }
            context.setLineWidth(1.0)
            context.strokePath()
            context.restoreGState()

            // Label & Icon
            let midDeg = (s + e) / 2.0
            let midRad = midDeg * .pi / 180.0
            let midRadius = (innerRadius + outerRadius) / 2.0
            let tx = wheelCenter.x + midRadius * cos(midRad)
            let ty = wheelCenter.y + midRadius * sin(midRad)

            let textColor = isHovered ? NSColor.white : NSColor(srgbRed: 0.12, green: 0.13, blue: 0.15, alpha: 1.0)

            if let iconName = item.iconName, let symbol = NSImage(systemSymbolName: iconName, accessibilityDescription: nil) {
                let iconSize: CGFloat = 16
                let iconRect = NSRect(x: tx - iconSize / 2, y: ty + 2, width: iconSize, height: iconSize)
                let tinted = symbol.copy() as! NSImage
                tinted.isTemplate = true
                textColor.set()
                tinted.draw(in: iconRect)

                let font = NSFont.systemFont(ofSize: 11, weight: .bold)
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
                let str = NSAttributedString(string: item.title, attributes: attrs)
                let sz = str.size()
                str.draw(at: NSPoint(x: tx - sz.width / 2, y: ty - sz.height - 2))
            } else {
                let font = NSFont.systemFont(ofSize: 15, weight: .bold)
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
                let str = NSAttributedString(string: item.title, attributes: attrs)
                let sz = str.size()
                str.draw(at: NSPoint(x: tx - sz.width / 2.0, y: ty - sz.height / 2.0))
            }
        }

        // 3. Center Hole: When hovered, display a floating pill badge; otherwise remain transparent so user sees desktop file!
        if hoveredIndex >= 0 && hoveredIndex < items.count {
            let item = items[hoveredIndex]
            let pillW: CGFloat = 86
            let pillH: CGFloat = 36
            let pillRect = NSRect(x: wheelCenter.x - pillW / 2, y: wheelCenter.y - pillH / 2, width: pillW, height: pillH)
            let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: pillH / 2, yRadius: pillH / 2)

            context.saveGState()
            context.setShadow(offset: CGSize(width: 0, height: -2), blur: 8, color: NSColor.black.withAlphaComponent(0.12).cgColor)
            NSColor.white.setFill()
            pillPath.fill()
            context.restoreGState()

            let font = NSFont.systemFont(ofSize: 14, weight: .bold)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(srgbRed: 0.12, green: 0.13, blue: 0.15, alpha: 1.0)]
            let str = NSAttributedString(string: item.title, attributes: attrs)
            let sz = str.size()
            str.draw(at: NSPoint(x: wheelCenter.x - sz.width / 2.0, y: wheelCenter.y - sz.height / 2.0))
        }

        // 4. Floating Pill Toolbar Above Wheel: [ ⇧ Convert ]  [ ⌘ Tools ]  [ ⌃ Actions ]
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -3), blur: 12, color: NSColor.black.withAlphaComponent(0.12).cgColor)
        let barPath = NSBezierPath(roundedRect: topBarRect, xRadius: topBarRect.height / 2, yRadius: topBarRect.height / 2)
        NSColor(white: 0.96, alpha: 0.95).setFill()
        barPath.fill()
        NSColor(white: 1.0, alpha: 0.8).setStroke()
        barPath.lineWidth = 1.0
        barPath.stroke()
        context.restoreGState()

        // 3 Buttons inside top bar
        let modes: [(key: String, title: String, mode: WheelMode)] = [
            ("⇧", "Convert", .conversions),
            ("⌘", "Tools", .tools),
            ("⌃", "Actions", .actions)
        ]
        let btnW = (topBarRect.width - 8) / 3.0

        for (mIdx, m) in modes.enumerated() {
            let isActive = (m.mode == self.mode)
            let isBtnHovered = (mIdx == hoveredTopBarIndex)
            let btnX = topBarRect.minX + 4 + CGFloat(mIdx) * btnW
            let btnRect = NSRect(x: btnX, y: topBarRect.minY + 3, width: btnW, height: topBarRect.height - 6)

            if isActive {
                let activePill = NSBezierPath(roundedRect: btnRect, xRadius: btnRect.height / 2, yRadius: btnRect.height / 2)
                context.saveGState()
                context.setShadow(offset: CGSize(width: 0, height: -1), blur: 4, color: NSColor.black.withAlphaComponent(0.1).cgColor)
                NSColor.white.setFill()
                activePill.fill()
                context.restoreGState()
            } else if isBtnHovered {
                let hoverPill = NSBezierPath(roundedRect: btnRect, xRadius: btnRect.height / 2, yRadius: btnRect.height / 2)
                NSColor(white: 1.0, alpha: 0.5).setFill()
                hoverPill.fill()
            }

            // Draw Keycap
            let keyCapSize: CGFloat = 18
            let keyCapRect = NSRect(x: btnRect.minX + 8, y: btnRect.midY - keyCapSize / 2, width: keyCapSize, height: keyCapSize)
            let keyCapPath = NSBezierPath(roundedRect: keyCapRect, xRadius: 4, yRadius: 4)
            NSColor(white: 0.90, alpha: 0.85).setFill()
            keyCapPath.fill()
            NSColor(white: 0.75, alpha: 0.6).setStroke()
            keyCapPath.lineWidth = 0.5
            keyCapPath.stroke()

            let keyFont = NSFont.systemFont(ofSize: 10, weight: .bold)
            let keyAttrs: [NSAttributedString.Key: Any] = [.font: keyFont, .foregroundColor: NSColor(white: 0.25, alpha: 1.0)]
            let keyStr = NSAttributedString(string: m.key, attributes: keyAttrs)
            let kSz = keyStr.size()
            keyStr.draw(at: NSPoint(x: keyCapRect.midX - kSz.width / 2, y: keyCapRect.midY - kSz.height / 2))

            // Draw Title
            let titleColor = isActive ? NSColor(srgbRed: 0.12, green: 0.13, blue: 0.15, alpha: 1.0) : NSColor(white: 0.45, alpha: 1.0)
            let titleFont = NSFont.systemFont(ofSize: 11, weight: isActive ? .bold : .medium)
            let titleAttrs: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: titleColor]
            let titleStr = NSAttributedString(string: m.title, attributes: titleAttrs)
            titleStr.draw(at: NSPoint(x: keyCapRect.maxX + 5, y: btnRect.midY - titleStr.size().height / 2))
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
        let width: CGFloat = 420
        let height: CGFloat = 480
        let panel = KeyPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
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
        let width: CGFloat = 420
        let height: CGFloat = 480
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main ?? NSScreen()
        let frame = screen.visibleFrame

        // Center hole of the wheel directly over the cursor & file
        var x = mouse.x - wheelView.wheelCenter.x
        var y = mouse.y - wheelView.wheelCenter.y

        // Clamp to screen bounds
        x = max(frame.minX + 10, min(frame.maxX - width - 10, x))
        y = max(frame.minY + 10, min(frame.maxY - height - 10, y))

        window?.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
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
