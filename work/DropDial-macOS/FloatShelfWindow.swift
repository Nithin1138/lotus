import AppKit
import QuickLookThumbnailing

// MARK: - Custom Floating Shelf Window
final class FloatShelfWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC key
            FloatShelfWindowController.shared.hideShelf()
            return
        }
        super.keyDown(with: event)
    }
}

// MARK: - Flipped Container Views for Top-to-Bottom Flow
final class FlippedClipView: NSClipView {
    override var isFlipped: Bool { true }
}

final class FlippedStackView: NSStackView {
    override var isFlipped: Bool { true }
}

// MARK: - Drag All Master Button (Draggable Source + Click Copy)
final class FloatShelfDragAllButton: NSButton, NSDraggingSource {
    var getPaths: (() -> [String])?
    private var dragStartLocation: NSPoint = .zero
    private var isDraggingSessionActive = false

    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupStyle()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupStyle() {
        bezelStyle = .rounded
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor(srgbRed: 1.0, green: 0.42, blue: 0.1, alpha: 0.9).cgColor
        contentTintColor = .white
        font = NSFont.systemFont(ofSize: 11, weight: .bold)
        title = "Drag All"
    }

    override func mouseDown(with event: NSEvent) {
        dragStartLocation = event.locationInWindow
        isDraggingSessionActive = false
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        let current = event.locationInWindow
        let dist = hypot(current.x - dragStartLocation.x, current.y - dragStartLocation.y)
        if dist > 3 && !isDraggingSessionActive {
            let paths = getPaths?() ?? []
            guard !paths.isEmpty else { return }
            isDraggingSessionActive = true
            startDragAll(with: paths, event: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if !isDraggingSessionActive {
            // Click action: Copy all files to clipboard as convenient fallback
            let paths = getPaths?() ?? []
            if !paths.isEmpty {
                let urls = paths.map { URL(fileURLWithPath: $0) as NSURL }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects(urls)

                let originalTitle = title
                title = "Copied!"
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                    self?.title = originalTitle
                }
            }
        }
        isDraggingSessionActive = false
        super.mouseUp(with: event)
    }

    private func startDragAll(with paths: [String], event: NSEvent) {
        let dragItems = paths.enumerated().map { (index, path) -> NSDraggingItem in
            let url = URL(fileURLWithPath: path) as NSURL
            let item = NSDraggingItem(pasteboardWriter: url)
            let offset = CGFloat(min(index * 4, 20))
            let dragFrame = NSRect(x: bounds.origin.x + offset, y: bounds.origin.y - offset, width: bounds.width, height: bounds.height)
            item.setDraggingFrame(dragFrame, contents: bitmapBadge(count: paths.count))
            return item
        }
        beginDraggingSession(with: dragItems, event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return [.copy, .generic]
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        isDraggingSessionActive = false
    }

    private func bitmapBadge(count: Int) -> NSImage {
        let size = NSSize(width: 130, height: 36)
        let image = NSImage(size: size)
        image.lockFocus()

        let rect = NSRect(origin: .zero, size: size).insetBy(dx: 2, dy: 2)
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        NSColor(srgbRed: 0.12, green: 0.12, blue: 0.15, alpha: 0.95).setFill()
        path.fill()
        NSColor(srgbRed: 1.0, green: 0.42, blue: 0.1, alpha: 0.95).setStroke()
        path.lineWidth = 1.5
        path.stroke()

        let text = "\(count) Files"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let strSize = str.size()
        str.draw(at: NSPoint(x: (size.width - strSize.width) / 2, y: (size.height - strSize.height) / 2))

        image.unlockFocus()
        return image
    }
}

// MARK: - Float Shelf Item Card View (Draggable Source + Rich Actions)
final class FloatShelfItemView: NSView, NSDraggingSource {
    let filePath: String
    var onRemove: (() -> Void)?
    var onSelect: (() -> Void)?

    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let quickLookBtn = NSButton()
    private let revealBtn = NSButton()
    private let removeBtn = NSButton()
    private var trackingArea: NSTrackingArea?

    private var dragStartLocation: NSPoint = .zero
    private var isDraggingSessionActive = false

    override var mouseDownCanMoveWindow: Bool { false }

    init(filePath: String, frame frameRect: NSRect) {
        self.filePath = filePath
        super.init(frame: frameRect)
        wantsLayer = true
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        layer?.backgroundColor = NSColor(white: 0.14, alpha: 0.88).cgColor
        layer?.cornerRadius = 10
        layer?.borderColor = NSColor(white: 1.0, alpha: 0.12).cgColor
        layer?.borderWidth = 1.0

        // File Thumbnail / Icon
        iconView.frame = NSRect(x: 10, y: 10, width: 36, height: 36)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.wantsLayer = true
        iconView.layer?.cornerRadius = 6
        iconView.layer?.masksToBounds = true
        iconView.image = NSWorkspace.shared.icon(forFile: filePath)
        addSubview(iconView)

        // Asynchronously load real thumbnail via PreviewService
        PreviewService.shared.loadPreview(for: filePath, targetSize: CGSize(width: 72, height: 72)) { [weak self] preview in
            guard let self = self, let preview = preview else { return }
            self.iconView.image = preview
        }

        // File Name
        let name = URL(fileURLWithPath: filePath).lastPathComponent
        nameLabel.frame = NSRect(x: 54, y: 28, width: 116, height: 18)
        nameLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
        nameLabel.textColor = .white
        nameLabel.stringValue = name
        nameLabel.lineBreakMode = .byTruncatingMiddle
        addSubview(nameLabel)

        // File Details (Size + Type)
        var detailText = ""
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: filePath, isDirectory: &isDir), isDir.boolValue {
            let count = (try? FileManager.default.contentsOfDirectory(atPath: filePath))?.count ?? 0
            detailText = "Folder • \(count) \(count == 1 ? "item" : "items")"
        } else {
            var szStr = ""
            if let attrs = try? FileManager.default.attributesOfItem(atPath: filePath),
               let sz = attrs[.size] as? Int64 {
                szStr = ByteCountFormatter.string(fromByteCount: sz, countStyle: .file)
            }
            var ext = URL(fileURLWithPath: filePath).pathExtension.uppercased()
            if ext.isEmpty { ext = "FILE" }
            detailText = szStr.isEmpty ? ext : "\(szStr) • \(ext)"
        }

        detailLabel.frame = NSRect(x: 54, y: 10, width: 116, height: 16)
        detailLabel.font = NSFont.systemFont(ofSize: 10)
        detailLabel.textColor = NSColor(white: 0.65, alpha: 1.0)
        detailLabel.stringValue = detailText
        addSubview(detailLabel)

        // Quick Action Buttons (Quick Look, Reveal in Finder, Remove)
        // 1. Quick Look (Eye)
        quickLookBtn.frame = NSRect(x: bounds.width - 58, y: 18, width: 18, height: 18)
        quickLookBtn.isBordered = false
        quickLookBtn.wantsLayer = true
        quickLookBtn.toolTip = "Quick Look (Space)"
        if let eyeImg = NSImage(systemSymbolName: "eye", accessibilityDescription: "Quick Look") {
            let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .regular)
            quickLookBtn.image = eyeImg.withSymbolConfiguration(config)
            quickLookBtn.contentTintColor = NSColor(white: 0.7, alpha: 1.0)
        } else {
            quickLookBtn.title = "👁"
        }
        quickLookBtn.target = self
        quickLookBtn.action = #selector(quickLookClicked)
        quickLookBtn.isHidden = true
        addSubview(quickLookBtn)

        // 2. Reveal in Finder
        revealBtn.frame = NSRect(x: bounds.width - 38, y: 18, width: 18, height: 18)
        revealBtn.isBordered = false
        revealBtn.wantsLayer = true
        revealBtn.toolTip = "Reveal in Finder"
        if let folderImg = NSImage(systemSymbolName: "folder", accessibilityDescription: "Reveal in Finder") {
            let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .regular)
            revealBtn.image = folderImg.withSymbolConfiguration(config)
            revealBtn.contentTintColor = NSColor(white: 0.7, alpha: 1.0)
        } else {
            revealBtn.title = "📂"
        }
        revealBtn.target = self
        revealBtn.action = #selector(revealClicked)
        revealBtn.isHidden = true
        addSubview(revealBtn)

        // 3. Remove Button (Always subtly visible)
        removeBtn.frame = NSRect(x: bounds.width - 20, y: 18, width: 16, height: 16)
        removeBtn.title = "×"
        removeBtn.isBordered = false
        removeBtn.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        removeBtn.contentTintColor = NSColor(white: 0.5, alpha: 1.0)
        removeBtn.toolTip = "Remove from Shelf"
        removeBtn.target = self
        removeBtn.action = #selector(removeClicked)
        addSubview(removeBtn)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = trackingArea {
            removeTrackingArea(old)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect]
        let newArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(newArea)
        trackingArea = newArea
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = NSColor(white: 0.22, alpha: 0.95).cgColor
        layer?.borderColor = NSColor(srgbRed: 1.0, green: 0.42, blue: 0.1, alpha: 0.45).cgColor
        quickLookBtn.isHidden = false
        revealBtn.isHidden = false
        removeBtn.contentTintColor = NSColor(srgbRed: 1.0, green: 0.35, blue: 0.35, alpha: 1.0)
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor(white: 0.14, alpha: 0.88).cgColor
        layer?.borderColor = NSColor(white: 1.0, alpha: 0.12).cgColor
        quickLookBtn.isHidden = true
        revealBtn.isHidden = true
        removeBtn.contentTintColor = NSColor(white: 0.5, alpha: 1.0)
    }

    // MARK: - Actions
    @objc private func removeClicked() {
        onRemove?()
    }

    @objc private func quickLookClicked() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
        process.arguments = ["-p", filePath]
        try? process.run()
    }

    @objc private func revealClicked() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: filePath)])
    }

    @objc private func openFile() {
        NSWorkspace.shared.open(URL(fileURLWithPath: filePath))
    }

    @objc private func copyFileToPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([URL(fileURLWithPath: filePath) as NSURL])
    }

    @objc private func copyPathToPasteboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(filePath, forType: .string)
    }

    // MARK: - Context Menu
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu(title: "ItemMenu")

        let openItem = NSMenuItem(title: "Open", action: #selector(openFile), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        let qlItem = NSMenuItem(title: "Quick Look", action: #selector(quickLookClicked), keyEquivalent: " ")
        qlItem.target = self
        menu.addItem(qlItem)

        let revealItem = NSMenuItem(title: "Reveal in Finder", action: #selector(revealClicked), keyEquivalent: "")
        revealItem.target = self
        menu.addItem(revealItem)

        menu.addItem(NSMenuItem.separator())

        let copyItem = NSMenuItem(title: "Copy File", action: #selector(copyFileToPasteboard), keyEquivalent: "c")
        copyItem.target = self
        menu.addItem(copyItem)

        let copyPathItem = NSMenuItem(title: "Copy Path", action: #selector(copyPathToPasteboard), keyEquivalent: "")
        copyPathItem.target = self
        menu.addItem(copyPathItem)

        menu.addItem(NSMenuItem.separator())

        let removeItem = NSMenuItem(title: "Remove from Shelf", action: #selector(removeClicked), keyEquivalent: "")
        removeItem.target = self
        menu.addItem(removeItem)

        return menu
    }

    // MARK: - Drag Out to Other Apps / Finder
    override func mouseDown(with event: NSEvent) {
        dragStartLocation = event.locationInWindow
        isDraggingSessionActive = false
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        let current = event.locationInWindow
        let dist = hypot(current.x - dragStartLocation.x, current.y - dragStartLocation.y)
        if dist > 3 && !isDraggingSessionActive {
            isDraggingSessionActive = true
            startDrag(with: event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if !isDraggingSessionActive {
            if event.clickCount == 2 {
                openFile()
            } else {
                onSelect?()
            }
        }
        isDraggingSessionActive = false
        super.mouseUp(with: event)
    }

    private func startDrag(with event: NSEvent) {
        let fileURL = URL(fileURLWithPath: filePath)
        let pasteboardWriter = fileURL as NSURL
        let dragItem = NSDraggingItem(pasteboardWriter: pasteboardWriter)
        dragItem.setDraggingFrame(bounds, contents: self.bitmapImage())

        beginDraggingSession(with: [dragItem], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return [.copy, .generic]
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        isDraggingSessionActive = false
    }

    private func bitmapImage() -> NSImage {
        let rep = bitmapImageRepForCachingDisplay(in: bounds) ?? NSBitmapImageRep()
        cacheDisplay(in: bounds, to: rep)
        let img = NSImage(size: bounds.size)
        img.addRepresentation(rep)
        return img
    }
}

// MARK: - Drop Destination Content View (Accepts Incoming Drag & Drops)
final class FloatShelfContentView: NSView {
    var onFilesDropped: (([String]) -> Void)?

    private let dropOverlay = NSView()
    private let dropLabel = NSTextField(labelWithString: "Drop files here to add to shelf")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
        setupOverlay()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupOverlay() {
        dropOverlay.frame = bounds
        dropOverlay.autoresizingMask = [.width, .height]
        dropOverlay.wantsLayer = true
        dropOverlay.layer?.backgroundColor = NSColor(srgbRed: 1.0, green: 0.42, blue: 0.1, alpha: 0.22).cgColor
        dropOverlay.layer?.borderColor = NSColor(srgbRed: 1.0, green: 0.42, blue: 0.1, alpha: 0.95).cgColor
        dropOverlay.layer?.borderWidth = 2.0
        dropOverlay.layer?.cornerRadius = 14
        dropOverlay.isHidden = true

        dropLabel.font = NSFont.systemFont(ofSize: 13, weight: .bold)
        dropLabel.textColor = .white
        dropLabel.alignment = .center
        dropLabel.frame = NSRect(x: 10, y: bounds.midY - 12, width: bounds.width - 20, height: 24)
        dropLabel.autoresizingMask = [.width, .minYMargin, .maxYMargin]
        dropOverlay.addSubview(dropLabel)

        addSubview(dropOverlay, positioned: .above, relativeTo: nil)
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if hasFileURLs(sender) {
            dropOverlay.isHidden = false
            return .copy
        }
        return []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return hasFileURLs(sender) ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dropOverlay.isHidden = true
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return hasFileURLs(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropOverlay.isHidden = true
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] else {
            return false
        }
        let paths = urls.map { $0.path }.filter { FileManager.default.fileExists(atPath: $0) }
        guard !paths.isEmpty else { return false }
        onFilesDropped?(paths)
        return true
    }

    private func hasFileURLs(_ sender: NSDraggingInfo) -> Bool {
        if let types = sender.draggingPasteboard.types, types.contains(.fileURL) {
            return true
        }
        return false
    }
}

// MARK: - Empty State View
final class FloatShelfEmptyView: NSView {
    var onBrowseTapped: (() -> Void)?

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "Shelf is Empty")
    private let subtitleLabel = NSTextField(labelWithString: "Drop files here from Finder\nor send from DropDial wheel")
    private let browseButton = NSButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        layer?.cornerRadius = 12
        layer?.borderColor = NSColor(white: 1.0, alpha: 0.10).cgColor
        layer?.borderWidth = 1.0
        layer?.backgroundColor = NSColor(white: 0.10, alpha: 0.40).cgColor

        let iconSize: CGFloat = 36
        iconView.frame = NSRect(x: (bounds.width - iconSize) / 2, y: bounds.height - 70, width: iconSize, height: iconSize)
        if let img = NSImage(systemSymbolName: "tray.and.arrow.down", accessibilityDescription: "Drop files") {
            let config = NSImage.SymbolConfiguration(pointSize: 26, weight: .light)
            iconView.image = img.withSymbolConfiguration(config)
            iconView.contentTintColor = NSColor(srgbRed: 1.0, green: 0.42, blue: 0.1, alpha: 0.85)
        }
        addSubview(iconView)

        titleLabel.frame = NSRect(x: 10, y: bounds.height - 105, width: bounds.width - 20, height: 20)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.alignment = .center
        addSubview(titleLabel)

        subtitleLabel.frame = NSRect(x: 12, y: bounds.height - 152, width: bounds.width - 24, height: 36)
        subtitleLabel.font = NSFont.systemFont(ofSize: 11)
        subtitleLabel.textColor = NSColor(white: 0.65, alpha: 1.0)
        subtitleLabel.alignment = .center
        addSubview(subtitleLabel)

        browseButton.frame = NSRect(x: (bounds.width - 120) / 2, y: 22, width: 120, height: 28)
        browseButton.title = "+ Add Files..."
        browseButton.bezelStyle = .rounded
        browseButton.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        browseButton.target = self
        browseButton.action = #selector(browseClicked)
        addSubview(browseButton)
    }

    @objc private func browseClicked() {
        onBrowseTapped?()
    }
}

// MARK: - Floating Shelf Window Controller
final class FloatShelfWindowController: NSWindowController {
    static let shared = FloatShelfWindowController()

    private var floatedPaths: [String] = []

    private let titleLabel = NSTextField(labelWithString: "Floating Shelf")
    private let countBadge = NSTextField(labelWithString: "0")
    private let addHeaderBtn = NSButton()
    private let closeBtn = NSButton()

    private let itemsStack = FlippedStackView()
    private let scrollView = NSScrollView()
    private var emptyView: FloatShelfEmptyView?

    private let clearBtn = NSButton()
    private let shareBtn = NSButton()
    private let dragAllBtn = FloatShelfDragAllButton()

    init() {
        let width: CGFloat = 250
        let height: CGFloat = 400
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let rect = NSRect(x: screen.maxX - width - 20, y: screen.midY - height / 2, width: width, height: height)

        let window = FloatShelfWindow(
            contentRect: rect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true
        window.setFrameAutosaveName("DropDialFloatingShelfWindow")

        super.init(window: window)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        guard let window = window else { return }

        // Root drop-receiving view
        let dropContentView = FloatShelfContentView(frame: window.contentRect(forFrameRect: window.frame))
        dropContentView.autoresizingMask = [.width, .height]
        dropContentView.onFilesDropped = { [weak self] droppedPaths in
            self?.addFiles(droppedPaths)
        }
        window.contentView = dropContentView

        // Glassmorphism Visual Effect
        let effect = NSVisualEffectView(frame: dropContentView.bounds)
        effect.autoresizingMask = [.width, .height]
        effect.material = .hudWindow
        effect.blendingMode = .withinWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 14
        effect.layer?.masksToBounds = true
        effect.layer?.borderColor = NSColor(white: 1.0, alpha: 0.18).cgColor
        effect.layer?.borderWidth = 1.0
        dropContentView.addSubview(effect)

        // 1. Header (Title + Badge + Add + Close)
        titleLabel.frame = NSRect(x: 14, y: 366, width: 90, height: 20)
        titleLabel.font = NSFont.systemFont(ofSize: 12.5, weight: .bold)
        titleLabel.textColor = .white
        effect.addSubview(titleLabel)

        countBadge.frame = NSRect(x: 108, y: 368, width: 20, height: 16)
        countBadge.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        countBadge.alignment = .center
        countBadge.textColor = .white
        countBadge.wantsLayer = true
        countBadge.layer?.backgroundColor = NSColor(srgbRed: 1.0, green: 0.42, blue: 0.1, alpha: 1.0).cgColor
        countBadge.layer?.cornerRadius = 8
        countBadge.layer?.masksToBounds = true
        effect.addSubview(countBadge)

        // Header Add Button
        addHeaderBtn.frame = NSRect(x: 168, y: 367, width: 46, height: 18)
        addHeaderBtn.title = "+ Add"
        addHeaderBtn.bezelStyle = .inline
        addHeaderBtn.isBordered = false
        addHeaderBtn.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        addHeaderBtn.contentTintColor = NSColor(srgbRed: 1.0, green: 0.6, blue: 0.2, alpha: 1.0)
        addHeaderBtn.toolTip = "Add files from computer"
        addHeaderBtn.target = self
        addHeaderBtn.action = #selector(browseFilesManually)
        effect.addSubview(addHeaderBtn)

        // Header Close Button
        closeBtn.frame = NSRect(x: 222, y: 367, width: 18, height: 18)
        closeBtn.title = "×"
        closeBtn.isBordered = false
        closeBtn.font = NSFont.systemFont(ofSize: 15, weight: .bold)
        closeBtn.contentTintColor = NSColor(white: 0.7, alpha: 1.0)
        closeBtn.toolTip = "Hide Shelf (ESC)"
        closeBtn.target = self
        closeBtn.action = #selector(hideShelf)
        effect.addSubview(closeBtn)

        // 2. Scrollable Stack for items (Flipped so items flow from top to bottom)
        scrollView.frame = NSRect(x: 10, y: 56, width: 230, height: 298)
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true

        itemsStack.orientation = .vertical
        itemsStack.spacing = 8
        itemsStack.alignment = .leading
        itemsStack.translatesAutoresizingMaskIntoConstraints = false

        let clipView = FlippedClipView()
        clipView.drawsBackground = false
        clipView.documentView = itemsStack
        scrollView.contentView = clipView
        effect.addSubview(scrollView)

        // 3. Empty State View
        let empty = FloatShelfEmptyView(frame: NSRect(x: 10, y: 56, width: 230, height: 298))
        empty.onBrowseTapped = { [weak self] in
            self?.browseFilesManually()
        }
        effect.addSubview(empty)
        self.emptyView = empty

        // 4. Bottom Action Bar: Clear, AirDrop, Drag All
        clearBtn.frame = NSRect(x: 12, y: 14, width: 54, height: 28)
        clearBtn.title = "Clear"
        clearBtn.bezelStyle = .rounded
        clearBtn.font = NSFont.systemFont(ofSize: 11)
        clearBtn.target = self
        clearBtn.action = #selector(clearAll)
        effect.addSubview(clearBtn)

        shareBtn.frame = NSRect(x: 70, y: 14, width: 68, height: 28)
        shareBtn.title = "AirDrop"
        shareBtn.bezelStyle = .rounded
        shareBtn.font = NSFont.systemFont(ofSize: 11)
        shareBtn.target = self
        shareBtn.action = #selector(shareAll)
        effect.addSubview(shareBtn)

        dragAllBtn.frame = NSRect(x: 142, y: 14, width: 96, height: 28)
        dragAllBtn.getPaths = { [weak self] in
            return self?.floatedPaths ?? []
        }
        dragAllBtn.toolTip = "Drag this button to drop all files, or click to copy them"
        effect.addSubview(dragAllBtn)

        refreshList()
    }

    // MARK: - Public Management
    func addFiles(_ paths: [String]) {
        for p in paths {
            let valid = p.trimmingCharacters(in: .whitespacesAndNewlines)
            if !valid.isEmpty && FileManager.default.fileExists(atPath: valid) {
                if !floatedPaths.contains(valid) {
                    floatedPaths.insert(valid, at: 0) // Newest on top
                }
            }
        }
        refreshList()
        showShelf()
    }

    func showShelf() {
        showWindow(nil)
        window?.orderFrontRegardless()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func hideShelf() {
        window?.orderOut(nil)
    }

    @objc func clearAll() {
        floatedPaths.removeAll()
        refreshList()
    }

    @objc func shareAll() {
        let urls = floatedPaths.map { URL(fileURLWithPath: $0) }
        guard !urls.isEmpty else { return }
        if let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls) {
            service.perform(withItems: urls)
        } else {
            let picker = NSSharingServicePicker(items: urls)
            if let view = window?.contentView {
                picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
            }
        }
    }

    @objc func browseFilesManually() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Add to Shelf"
        panel.title = "Select Files or Folders for Floating Shelf"
        if panel.runModal() == .OK {
            let paths = panel.urls.map { $0.path }
            addFiles(paths)
        }
    }

    private func refreshList() {
        let count = floatedPaths.count
        countBadge.stringValue = "\(count)"

        let isEmpty = count == 0
        emptyView?.isHidden = !isEmpty
        scrollView.isHidden = isEmpty

        clearBtn.isEnabled = !isEmpty
        shareBtn.isEnabled = !isEmpty
        dragAllBtn.isEnabled = !isEmpty
        dragAllBtn.title = isEmpty ? "Drag All" : "Drag All (\(count))"

        itemsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let cardWidth: CGFloat = 228
        let cardHeight: CGFloat = 56

        for path in floatedPaths {
            let item = FloatShelfItemView(filePath: path, frame: NSRect(x: 0, y: 0, width: cardWidth, height: cardHeight))
            item.widthAnchor.constraint(equalToConstant: cardWidth).isActive = true
            item.heightAnchor.constraint(equalToConstant: cardHeight).isActive = true
            item.onRemove = { [weak self, weak item] in
                guard let self = self, let item = item else { return }
                self.floatedPaths.removeAll(where: { $0 == item.filePath })
                self.refreshList()
            }
            itemsStack.addArrangedSubview(item)
        }
    }
}
