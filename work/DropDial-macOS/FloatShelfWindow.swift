import AppKit

// MARK: - Float Shelf Item Card View (Draggable)
final class FloatShelfItemView: NSView, NSDraggingSource {
    let filePath: String
    var onRemove: (() -> Void)?

    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let sizeLabel = NSTextField(labelWithString: "")
    private let removeButton = NSButton()

    init(filePath: String, frame frameRect: NSRect) {
        self.filePath = filePath
        super.init(frame: frameRect)
        wantsLayer = true
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        layer?.backgroundColor = NSColor(white: 0.15, alpha: 0.85).cgColor
        layer?.cornerRadius = 8
        layer?.borderColor = NSColor(white: 1.0, alpha: 0.15).cgColor
        layer?.borderWidth = 1.0

        // File Icon
        iconView.frame = NSRect(x: 8, y: 10, width: 32, height: 32)
        iconView.image = NSWorkspace.shared.icon(forFile: filePath)
        addSubview(iconView)

        // File Name
        let name = URL(fileURLWithPath: filePath).lastPathComponent
        nameLabel.frame = NSRect(x: 46, y: 24, width: 110, height: 18)
        nameLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        nameLabel.textColor = .white
        nameLabel.stringValue = name
        nameLabel.lineBreakMode = .byTruncatingMiddle
        addSubview(nameLabel)

        // File Size
        var sizeText = ""
        if let attrs = try? FileManager.default.attributesOfItem(atPath: filePath),
           let sz = attrs[.size] as? Int64 {
            sizeText = ByteCountFormatter.string(fromByteCount: sz, countStyle: .file)
        }
        sizeLabel.frame = NSRect(x: 46, y: 8, width: 110, height: 14)
        sizeLabel.font = NSFont.systemFont(ofSize: 10)
        sizeLabel.textColor = NSColor(white: 0.75, alpha: 1.0)
        sizeLabel.stringValue = sizeText
        addSubview(sizeLabel)

        // Remove (X) Button
        removeButton.frame = NSRect(x: bounds.width - 24, y: bounds.height - 24, width: 18, height: 18)
        removeButton.title = "×"
        removeButton.isBordered = false
        removeButton.font = NSFont.systemFont(ofSize: 14, weight: .bold)
        removeButton.contentTintColor = NSColor(white: 0.6, alpha: 1.0)
        removeButton.target = self
        removeButton.action = #selector(removeClicked)
        addSubview(removeButton)
    }

    @objc private func removeClicked() {
        onRemove?()
    }

    // MARK: - Drag Out to Other Apps
    override func mouseDown(with event: NSEvent) {
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(URL(fileURLWithPath: filePath).absoluteString, forType: .fileURL)

        let dragItem = NSDraggingItem(pasteboardWriter: NSURL(fileURLWithPath: filePath))
        dragItem.setDraggingFrame(bounds, contents: self.bitmapImage())

        beginDraggingSession(with: [dragItem], event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return .copy
    }

    private func bitmapImage() -> NSImage {
        let rep = bitmapImageRepForCachingDisplay(in: bounds) ?? NSBitmapImageRep()
        cacheDisplay(in: bounds, to: rep)
        let img = NSImage(size: bounds.size)
        img.addRepresentation(rep)
        return img
    }
}

// MARK: - Floating Shelf Window Controller
final class FloatShelfWindowController: NSWindowController {
    static let shared = FloatShelfWindowController()

    private var floatedPaths: [String] = []
    private let titleLabel = NSTextField(labelWithString: "Floating Shelf")
    private let countBadge = NSTextField(labelWithString: "0")
    private let itemsStack = NSStackView()
    private let scrollView = NSScrollView()

    init() {
        let width: CGFloat = 200
        let height: CGFloat = 360
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let rect = NSRect(x: screen.maxX - width - 16, y: screen.midY - height / 2, width: width, height: height)

        let window = NSWindow(
            contentRect: rect,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true

        super.init(window: window)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true

        let effect = NSVisualEffectView(frame: contentView.bounds)
        effect.autoresizingMask = [.width, .height]
        effect.material = .hudWindow
        effect.blendingMode = .withinWindow
        effect.state = .active
        effect.layer?.cornerRadius = 12
        effect.layer?.masksToBounds = true
        effect.layer?.borderColor = NSColor(white: 1.0, alpha: 0.2).cgColor
        effect.layer?.borderWidth = 1.0
        contentView.addSubview(effect)

        // Header
        titleLabel.frame = NSRect(x: 14, y: 326, width: 110, height: 20)
        titleLabel.font = NSFont.systemFont(ofSize: 12, weight: .bold)
        titleLabel.textColor = .white
        effect.addSubview(titleLabel)

        countBadge.frame = NSRect(x: 128, y: 327, width: 22, height: 16)
        countBadge.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        countBadge.alignment = .center
        countBadge.textColor = .white
        countBadge.wantsLayer = true
        countBadge.layer?.backgroundColor = NSColor(srgbRed: 1.0, green: 0.384, blue: 0.031, alpha: 1.0).cgColor
        countBadge.layer?.cornerRadius = 8
        countBadge.layer?.masksToBounds = true
        effect.addSubview(countBadge)

        let closeBtn = NSButton(frame: NSRect(x: 170, y: 326, width: 20, height: 20))
        closeBtn.title = "×"
        closeBtn.isBordered = false
        closeBtn.font = NSFont.systemFont(ofSize: 15, weight: .bold)
        closeBtn.contentTintColor = NSColor(white: 0.7, alpha: 1.0)
        closeBtn.target = self
        closeBtn.action = #selector(hideShelf)
        effect.addSubview(closeBtn)

        // Scrollable Stack for items
        scrollView.frame = NSRect(x: 10, y: 44, width: 180, height: 272)
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true

        itemsStack.orientation = .vertical
        itemsStack.spacing = 8
        itemsStack.alignment = .leading
        itemsStack.translatesAutoresizingMaskIntoConstraints = false

        let clipView = NSClipView()
        clipView.drawsBackground = false
        clipView.documentView = itemsStack
        scrollView.contentView = clipView
        effect.addSubview(scrollView)

        // Bottom Action Bar: Clear & AirDrop
        let clearBtn = NSButton(frame: NSRect(x: 10, y: 10, width: 85, height: 26))
        clearBtn.title = "Clear"
        clearBtn.bezelStyle = .rounded
        clearBtn.font = NSFont.systemFont(ofSize: 11)
        clearBtn.target = self
        clearBtn.action = #selector(clearAll)
        effect.addSubview(clearBtn)

        let shareBtn = NSButton(frame: NSRect(x: 105, y: 10, width: 85, height: 26))
        shareBtn.title = "AirDrop"
        shareBtn.bezelStyle = .rounded
        shareBtn.font = NSFont.systemFont(ofSize: 11)
        shareBtn.target = self
        shareBtn.action = #selector(shareAll)
        effect.addSubview(shareBtn)
    }

    func addFiles(_ paths: [String]) {
        for p in paths {
            if !floatedPaths.contains(p) {
                floatedPaths.append(p)
            }
        }
        refreshList()
        showShelf()
    }

    func showShelf() {
        window?.orderFront(nil)
    }

    @objc func hideShelf() {
        window?.orderOut(nil)
    }

    @objc func clearAll() {
        floatedPaths.removeAll()
        refreshList()
        hideShelf()
    }

    @objc func shareAll() {
        let urls = floatedPaths.map { URL(fileURLWithPath: $0) }
        if let service = NSSharingService(named: .sendViaAirDrop) {
            service.perform(withItems: urls)
        }
    }

    private func refreshList() {
        countBadge.stringValue = "\(floatedPaths.count)"
        itemsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        for path in floatedPaths {
            let item = FloatShelfItemView(filePath: path, frame: NSRect(x: 0, y: 0, width: 176, height: 50))
            item.widthAnchor.constraint(equalToConstant: 176).isActive = true
            item.heightAnchor.constraint(equalToConstant: 50).isActive = true
            item.onRemove = { [weak self, weak item] in
                guard let self = self, let item = item else { return }
                self.floatedPaths.removeAll(where: { $0 == item.filePath })
                self.refreshList()
                if self.floatedPaths.isEmpty {
                    self.hideShelf()
                }
            }
            itemsStack.addArrangedSubview(item)
        }
    }
}
