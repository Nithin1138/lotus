import AppKit

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
    }

    var items: [SliceItem] = []
    var hoveredIndex: Int = -1
    var isHubHovered: Bool = false
    var currentPaths: [String] = []
    var isToolsMode: Bool = false

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
        if isToolsMode {
            items = [
                SliceItem(id: "compress", title: "Compress", iconName: "arrow.down.circle", isTool: true),
                SliceItem(id: "resizeImage", title: "Resize", iconName: "arrow.up.left.and.arrow.down.right", isTool: true),
                SliceItem(id: "cropImage", title: "Crop", iconName: "crop", isTool: true),
                SliceItem(id: "rotateImage", title: "Rotate", iconName: "rotate.right", isTool: true),
                SliceItem(id: "ocrImage", title: "OCR", iconName: "doc.text.viewfinder", isTool: true),
                SliceItem(id: "watermark", title: "Watermark", iconName: "text.bubble", isTool: true),
                SliceItem(id: "removeMetadata", title: "Metadata", iconName: "eye.slash", isTool: true),
                SliceItem(id: "createPDF", title: "To PDF", iconName: "doc.on.doc", isTool: true)
            ]
        } else {
            items = [
                SliceItem(id: "convert:jpg", title: "JPG", iconName: nil, isTool: false),
                SliceItem(id: "convert:png", title: "PNG", iconName: nil, isTool: false),
                SliceItem(id: "convert:webp", title: "WEBP", iconName: nil, isTool: false),
                SliceItem(id: "convert:pdf", title: "PDF", iconName: nil, isTool: false),
                SliceItem(id: "convert:mp4", title: "MP4", iconName: nil, isTool: false),
                SliceItem(id: "convert:mp3", title: "MP3", iconName: nil, isTool: false),
                SliceItem(id: "convert:zip", title: "ZIP", iconName: nil, isTool: false),
                SliceItem(id: "convert:gif", title: "GIF", iconName: nil, isTool: false)
            ]
        }
        hubThumbnail = nil
        needsDisplay = true
    }

    func configure(paths: [String], toolsMode: Bool) {
        self.currentPaths = paths
        self.isToolsMode = toolsMode

        guard let first = paths.first else {
            loadDefaultItems()
            return
        }

        let cat = Catalog.category(for: first)
        if toolsMode {
            let tools = Catalog.tools(for: cat)
            items = tools.prefix(8).map { SliceItem(id: $0.id, title: $0.label, iconName: $0.iconName, isTool: true) }
        } else {
            let formats = Catalog.targetFormats(for: first)
            items = formats.prefix(8).map { SliceItem(id: "convert:\($0)", title: $0.uppercased(), iconName: nil, isTool: false) }
        }
        hoveredIndex = -1

        PreviewService.shared.loadPreview(for: first, targetSize: CGSize(width: 88, height: 88)) { [weak self] img in
            self?.hubThumbnail = img
            self?.needsDisplay = true
        }

        needsDisplay = true
    }

    // MARK: - Keyboard Controls
    override func keyDown(with event: NSEvent) {
        let code = event.keyCode
        if code == 53 { // Escape
            DropWheelWindowController.shared.hideWheel()
            return
        }
        if code == 100 { // F8 -> Formats Mode
            DropWheelWindowController.shared.toggleWheel(toolsMode: false)
            return
        }
        if code == 101 { // F9 -> Tools Mode
            DropWheelWindowController.shared.toggleWheel(toolsMode: true)
            return
        }
        if code == 48 { // Tab -> Switch Modes
            isToolsMode.toggle()
            if !currentPaths.isEmpty {
                configure(paths: currentPaths, toolsMode: isToolsMode)
            } else {
                loadDefaultItems()
            }
            return
        }
        if code == 123 || code == 126 { // Left or Up arrow
            if !items.isEmpty {
                hoveredIndex = (hoveredIndex - 1 + items.count) % items.count
                needsDisplay = true
            }
            return
        }
        if code == 124 || code == 125 { // Right or Down arrow
            if !items.isEmpty {
                hoveredIndex = (hoveredIndex + 1) % items.count
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
            configure(paths: paths, toolsMode: isToolsMode)
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
            // Dropped directly onto a specific format or tool slice
            let slice = self.items[hit]
            onSelectSlice?(slice, paths)
        } else {
            // Dropped on the center hub or wheel body -> load file options
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

        // 1. Solid Dark Backing Disc (100% blocks background desktop & Finder windows from showing through!)
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

            // Draw Label
            let midDeg = (startDeg + endDeg) / 2.0
            let midRad = midDeg * .pi / 180.0
            let midRadius = (innerRadius + outerRadius) / 2.0
            let tx = center.x + midRadius * cos(midRad)
            let ty = center.y + midRadius * sin(midRad)

            let textColor = NSColor.white
            let font = NSFont.systemFont(ofSize: 13, weight: .semibold)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: textColor
            ]

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
        if let first = currentPaths.first {
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

            let name = URL(fileURLWithPath: first).lastPathComponent
            let nameFont = NSFont.systemFont(ofSize: 10, weight: .semibold)
            let nameAttrs: [NSAttributedString.Key: Any] = [.font: nameFont, .foregroundColor: NSColor.white]
            let nameStr = NSAttributedString(string: name, attributes: nameAttrs)
            let nRect = NSRect(x: center.x - 45, y: center.y - 18, width: 90, height: 14)
            nameStr.draw(in: nRect)

            let modeFont = NSFont.systemFont(ofSize: 9, weight: .bold)
            let modeText = isToolsMode ? "TOOLS (Tab)" : "FORMATS (Tab)"
            let modeAttrs: [NSAttributedString.Key: Any] = [.font: modeFont, .foregroundColor: lotusOrange]
            let modeStr = NSAttributedString(string: modeText, attributes: modeAttrs)
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
        }
    }
}

final class DropWheelWindowController: NSWindowController {
    static let shared = DropWheelWindowController()

    private let wheelView = RadialWheelView()
    private var currentPaths: [String] = []
    private var isToolsMode = false
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
                self.isToolsMode.toggle()
                self.wheelView.configure(paths: self.currentPaths, toolsMode: self.isToolsMode)
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
        showAtCursor(toolsMode: isToolsMode)
    }

    func showAtCursor(toolsMode: Bool) {
        let mouse = NSEvent.mouseLocation
        let size: CGFloat = 380
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main ?? NSScreen()
        let frame = screen.visibleFrame

        // Outer line of the wheel at the cursor so the file in Finder is NOT covered
        // The outer disc has radius 175 inside window size 380 (16px margin to outer rim)
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
        self.isToolsMode = toolsMode
        if !currentPaths.isEmpty {
            wheelView.configure(paths: currentPaths, toolsMode: toolsMode)
        } else {
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

    func toggleWheel(toolsMode: Bool? = nil) {
        if window?.isVisible == true {
            if let tools = toolsMode, tools != self.isToolsMode {
                // User is switching modes (e.g. from Formats to Tools or vice-versa)
                self.isToolsMode = tools
                if !currentPaths.isEmpty {
                    wheelView.configure(paths: currentPaths, toolsMode: tools)
                } else {
                    wheelView.loadDefaultItems()
                }
            } else {
                // Same mode or general toggle -> close wheel
                hideWheel()
            }
        } else {
            showAtCursor(toolsMode: toolsMode ?? false)
        }
    }

    func loadFiles(_ paths: [String]) {
        self.currentPaths = paths
        self.isToolsMode = false
        wheelView.configure(paths: paths, toolsMode: false)
        showAtCursor(toolsMode: false)
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
        // Listen to mouseUp outside window frame so dragging files from Finder is never interrupted by mouseDown
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

        if item.isTool {
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

        let job = ConversionJob(Paths: activePaths, Action: item.id, Parameters: nil)
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
