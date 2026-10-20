import AppKit

enum AppTheme: String, CaseIterable {
    case system = "system"
    case light = "light"
    case dark = "dark"
}

enum SoundManager {
    static var isSoundEnabled: Bool {
        get { return false }
        set { }
    }

    static func playTick() { }
    static func playPop() { }
    static func playDismiss() { }
}

enum WheelMode: String, CaseIterable {
    case conversions = "Convert"
    case tools = "Tools"
    case actions = "Actions"

    var title: String { rawValue }

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

    /// The full pool of items for the current mode/file (may be more than 8).
    var allItems: [SliceItem] = []
    /// The 8 items currently visible in the wheel (window into allItems).
    var items: [SliceItem] = []
    /// Current side/page index (0-based: 0 is Side 1, 1 is Side 2, etc.)
    private var currentSideIndex: Int = 0

    /// Total number of sides (each side has up to 8 tools).
    var totalSides: Int {
        max(1, (allItems.count + 7) / 8)
    }

    // MARK: - Smooth Rotation Animation
    /// The visual rotation angle (degrees) applied to petal drawing, smoothly animated.
    private var wheelRotationAngle: CGFloat = 0
    /// The target angle we're animating toward.
    private var targetRotationAngle: CGFloat = 0
    /// Timer firing at ~60 fps to animate the rotation.
    private var rotationTimer: Timer?
    /// Accumulated scroll delta used for momentum-style physics.
    private var scrollVelocity: CGFloat = 0
    /// Scratch accumulator so small scrolls snap to item boundaries.
    private var scrollAccumulator: CGFloat = 0
    /// Locks further side flips within the same scroll gesture to guarantee stopping cleanly at the target side.
    private var isGestureLocked: Bool = false
    /// Debounce timer for when scroll gestures settle or discrete mouse wheel stops.
    private var gestureSettleTimer: Timer?

    var hoveredIndex: Int = -1
    var isHubHovered: Bool = false
    var isClearHovered: Bool = false
    var hoveredTopBarIndex: Int = -1 // 0: Convert, 1: Tools, 2: Actions
    var isCloseHovered: Bool = false
    var currentPaths: [String] = []
    var mode: WheelMode = .conversions

    var onSelectSlice: ((SliceItem, [String]?) -> Void)?
    var onHubClicked: (() -> Void)?
    var onClearFiles: (() -> Void)?
    var onFilesDropped: (([String]) -> Void)?
    var onModeChanged: ((WheelMode) -> Void)?

    // Window dragging & mouse interaction state
    private var dragStartMouseScreen: NSPoint?
    private var dragStartWindowOrigin: NSPoint?
    private var isDraggingWindow: Bool = false
    private var mouseDownHit: Int = -1

    // MARK: - Rotation Helpers

    /// Recomputes `items` from `allItems` using the current `currentSideIndex`.
    private func syncDisplayedItems() {
        guard !allItems.isEmpty else { items = []; return }
        if allItems.count <= 8 {
            currentSideIndex = 0
            items = allItems
            return
        }
        let total = totalSides
        currentSideIndex = ((currentSideIndex % total) + total) % total
        let start = currentSideIndex * 8
        let end = min(start + 8, allItems.count)
        items = Array(allItems[start..<end])
    }

    /// True when we have more items than the 8 visible slots (multiple sides to rotate between).
    var hasMoreItems: Bool { allItems.count > 8 }

    // MARK: - Scroll-to-rotate
    override func scrollWheel(with event: NSEvent) {
        // Only allow rotation if there are multiple sides (> 8 items)
        guard allItems.count > 8 else { return }

        // Reset settle timer on every scroll event (fires 260ms after events stop)
        gestureSettleTimer?.invalidate()
        gestureSettleTimer = Timer.scheduledTimer(withTimeInterval: 0.26, repeats: false) { [weak self] _ in
            self?.handleGestureSettled()
        }

        // Handle trackpad gesture phases
        if event.phase == .began {
            isGestureLocked = false
            scrollAccumulator = 0
            rotationTimer?.invalidate()
            rotationTimer = nil
        } else if event.phase == .ended || event.phase == .cancelled {
            handleGestureEnded()
            return
        }

        let delta = event.scrollingDeltaX != 0 ? event.scrollingDeltaX : -event.scrollingDeltaY
        if abs(delta) < 0.0001 { return }

        // If this gesture has already switched to the target side, stay locked at that side!
        // Absorb remaining inertia / momentum events so it does not cycle back or overshoot.
        if isGestureLocked {
            return
        }

        // Track live rotation interactively with physical gesture
        scrollAccumulator += delta
        wheelRotationAngle += delta * 0.95
        // Elastic resistance clamp before threshold
        wheelRotationAngle = max(-42.0, min(42.0, wheelRotationAngle))
        needsDisplay = true

        // Once threshold is crossed, commit to the target side and lock
        let step: CGFloat = 26.0
        if abs(scrollAccumulator) >= step || abs(wheelRotationAngle) >= 30.0 {
            let forward = scrollAccumulator > 0 || wheelRotationAngle > 0
            scrollAccumulator = 0
            isGestureLocked = true // Lock: prevents returning to the same side during this gesture!

            let oldSide = currentSideIndex
            let total = totalSides
            currentSideIndex = forward ? (currentSideIndex + 1) % total : (currentSideIndex - 1 + total) % total

            if currentSideIndex != oldSide {
                SoundManager.playTick()
                syncDisplayedItems()
                hoveredIndex = -1

                // Smoothly spin and settle at 0 on the new side (e.g. Side 2)
                wheelRotationAngle = forward ? -75.0 : 75.0
                targetRotationAngle = 0
                startRotationAnimation()
            } else {
                targetRotationAngle = 0
                startRotationAnimation()
            }
            needsDisplay = true
        }
    }

    private func handleGestureEnded() {
        if !isGestureLocked && wheelRotationAngle != 0 {
            // Did not cross threshold before lifting: spring back to 0 on current side
            targetRotationAngle = 0
            startRotationAnimation()
        }
    }

    private func handleGestureSettled() {
        gestureSettleTimer?.invalidate()
        gestureSettleTimer = nil
        isGestureLocked = false
        scrollAccumulator = 0
        if rotationTimer == nil && wheelRotationAngle != 0 {
            targetRotationAngle = 0
            startRotationAnimation()
        }
    }

    private func startRotationAnimation() {
        guard rotationTimer == nil else { return }
        rotationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tickRotation()
        }
        rotationTimer?.tolerance = 0.004
    }

    private func tickRotation() {
        let diff = targetRotationAngle - wheelRotationAngle
        if abs(diff) < 0.05 {
            wheelRotationAngle = targetRotationAngle
            rotationTimer?.invalidate()
            rotationTimer = nil
        } else {
            // Spring-follow: easing factor 0.18 gives a smooth, physical feel.
            wheelRotationAngle += diff * 0.18
        }
        needsDisplay = true
    }

    /// Resets rotation state when mode/files change.
    func resetRotation() {
        rotationTimer?.invalidate()
        rotationTimer = nil
        gestureSettleTimer?.invalidate()
        gestureSettleTimer = nil
        isGestureLocked = false
        currentSideIndex = 0
        wheelRotationAngle = 0
        targetRotationAngle = 0
        scrollAccumulator = 0
        scrollVelocity = 0
    }

    let wheelCenter = CGPoint(x: 170, y: 155)
    let innerRadius: CGFloat = 52
    let outerRadius: CGFloat = 138
    let backdropRadius: CGFloat = 144
    let hubRadius: CGFloat = 46
    let topBarRect = NSRect(x: 170 - 110, y: 308, width: 220, height: 32)
    let closeButtonRect = NSRect(x: 170 - 110 + 220 + 8, y: 308, width: 32, height: 32)

    var hubClearButtonRect: NSRect {
        // Small into (x) button centered inside top of middle circle, just above the file
        let size: CGFloat = 16
        return NSRect(x: wheelCenter.x - size / 2, y: wheelCenter.y + 24, width: size, height: size)
    }

    var isDarkMode: Bool {
        let t = UserDefaults.standard.string(forKey: "DROPDIAL_THEME") ?? "system"
        if t == "dark" { return true }
        if t == "light" { return false }
        return NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    private var trackingArea: NSTrackingArea?
    private var hubThumbnail: NSImage?
    private var tintedIconCache: [String: NSImage] = [:]

    func reloadTheme() {
        tintedIconCache.removeAll()
        needsDisplay = true
    }

    private func tintedSymbol(name: String, color: NSColor, size: CGFloat) -> NSImage? {
        let key = "\(name)_\(color.hash)_\(size)"
        if let cached = tintedIconCache[key] {
            return cached
        }
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        let img = NSImage(size: NSSize(width: size, height: size))
        img.lockFocus()
        color.set()
        NSRect(origin: .zero, size: img.size).fill()
        base.draw(in: NSRect(origin: .zero, size: img.size), from: .zero, operation: .destinationIn, fraction: 1.0)
        img.unlockFocus()
        img.isTemplate = false
        tintedIconCache[key] = img
        return img
    }

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
        resetRotation()
        switch mode {
        case .actions:
            allItems = Catalog.fileActions.map {
                SliceItem(id: $0.id, title: $0.title, iconName: $0.iconName, isTool: false, isAction: true)
            }
        case .tools:
            // Full default image tool palette – scroll to reveal more
            allItems = [
                SliceItem(id: "compress",    title: "Compress",  iconName: "arrow.down.circle",                   isTool: true, isAction: false),
                SliceItem(id: "resizeImage", title: "Resize",     iconName: "arrow.up.left.and.arrow.down.right", isTool: true, isAction: false),
                SliceItem(id: "cropImage",   title: "Crop",       iconName: "crop",                               isTool: true, isAction: false),
                SliceItem(id: "editImage",   title: "Adjust",     iconName: "slider.horizontal.3",                isTool: true, isAction: false),
                SliceItem(id: "frameImage",  title: "Frame",      iconName: "square.dashed",                      isTool: true, isAction: false),
                SliceItem(id: "watermark",   title: "Watermark",  iconName: "text.bubble",                        isTool: true, isAction: false),
                SliceItem(id: "redactImage", title: "Redact",     iconName: "eye.slash.fill",                     isTool: true, isAction: false),
                SliceItem(id: "ocrImage",    title: "OCR",        iconName: "doc.text.viewfinder",                isTool: true, isAction: false),
                SliceItem(id: "annotateImage", title: "Annotate", iconName: "pencil.tip.crop.circle",             isTool: true, isAction: false),
                SliceItem(id: "makeIcon",    title: "Make Icon",  iconName: "app.dashed",                         isTool: true, isAction: false)
            ]
        case .conversions:
            allItems = [
                SliceItem(id: "convert:png",  title: "PNG",  iconName: nil, isTool: false, isAction: false),
                SliceItem(id: "convert:webp", title: "WEBP", iconName: nil, isTool: false, isAction: false),
                SliceItem(id: "convert:heic", title: "HEIC", iconName: nil, isTool: false, isAction: false),
                SliceItem(id: "convert:tiff", title: "TIFF", iconName: nil, isTool: false, isAction: false),
                SliceItem(id: "convert:avif", title: "AVIF", iconName: nil, isTool: false, isAction: false),
                SliceItem(id: "convert:bmp",  title: "BMP",  iconName: nil, isTool: false, isAction: false),
                SliceItem(id: "convert:pdf",  title: "PDF",  iconName: nil, isTool: false, isAction: false),
                SliceItem(id: "convert:jpg",  title: "JPG",  iconName: nil, isTool: false, isAction: false)
            ]
        }
        syncDisplayedItems()
        hubThumbnail = nil
        hoveredIndex = -1
        needsDisplay = true
    }

    func configure(paths: [String], mode: WheelMode) {
        self.currentPaths = paths
        self.mode = mode
        resetRotation()

        guard let first = paths.first else {
            loadDefaultItems()
            return
        }

        switch mode {
        case .actions:
            allItems = Catalog.fileActions.map {
                SliceItem(id: $0.id, title: $0.title, iconName: $0.iconName, isTool: false, isAction: true)
            }
        case .tools:
            if paths.count > 1 {
                let multi = Catalog.multiFileTools(for: paths)
                if !multi.isEmpty {
                    allItems = multi.map {
                        SliceItem(id: $0.id, title: $0.label, iconName: $0.iconName, isTool: true, isAction: false)
                    }
                } else {
                    let cat = Catalog.category(for: first)
                    allItems = Catalog.tools(for: cat).map {
                        SliceItem(id: $0.id, title: $0.label, iconName: $0.iconName, isTool: true, isAction: false)
                    }
                }
            } else {
                let cat = Catalog.category(for: first)
                allItems = Catalog.tools(for: cat).map {
                    SliceItem(id: $0.id, title: $0.label, iconName: $0.iconName, isTool: true, isAction: false)
                }
            }
        case .conversions:
            let formats = Catalog.targetFormats(for: first)
            allItems = formats.map {
                SliceItem(id: "convert:\($0)", title: $0.uppercased(), iconName: nil, isTool: false, isAction: false)
            }
        }

        syncDisplayedItems()
        hoveredIndex = -1

        PreviewService.shared.loadPreview(for: first, targetSize: CGSize(width: 80, height: 80)) { [weak self] img in
            self?.hubThumbnail = img
            self?.needsDisplay = true
        }

        needsDisplay = true
    }

    func setMode(_ newMode: WheelMode) {
        guard self.mode != newMode else { return }
        self.mode = newMode
        onModeChanged?(newMode)
        SoundManager.playPop()
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
                SoundManager.playTick()
                needsDisplay = true
            }
            return
        }
        if code == 124 || code == 125 { // Right or Down arrow
            if !items.isEmpty {
                hoveredIndex = (hoveredIndex + 1) % items.count
                SoundManager.playTick()
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
        if closeButtonRect.contains(point) {
            return -20 // Close button
        }

        // 1. Check top pill bar
        if topBarRect.contains(point) {
            let btnW = (topBarRect.width - 6) / 3.0
            let localX = point.x - (topBarRect.minX + 3)
            let btnIdx = Int(localX / btnW)
            return -10 - max(0, min(2, btnIdx)) // -10: Convert, -11: Tools, -12: Actions
        }

        // 1.5 Check center clear file button (Small into (x) mark)
        if !currentPaths.isEmpty && hubClearButtonRect.contains(point) {
            return -4 // Clear file from middle
        }

        let dx = point.x - wheelCenter.x
        let dy = point.y - wheelCenter.y
        let dist = sqrt(dx * dx + dy * dy)

        if dist <= hubRadius {
            return -2 // Center Hub
        }
        if dist < innerRadius {
            return -3 // Gap between hub and petals
        }
        if dist > outerRadius {
            return -1 // Outside
        }

        let rad = atan2(dy, dx)
        var deg = rad * 180.0 / .pi
        // Subtract the live rotation angle so hit-testing tracks the visual wheel.
        deg = 90.0 - deg - wheelRotationAngle
        // Normalise to [0, 360)
        deg = deg.truncatingRemainder(dividingBy: 360.0)
        if deg < 0 { deg += 360.0 }

        if items.count == 1 {
            return 0
        }
        let angle = sliceAngle()
        let idx = Int(deg / angle)
        return (idx >= 0 && idx < items.count) ? idx : -1
    }

    // MARK: - Hit Testing
    override func hitTest(_ point: NSPoint) -> NSView? {
        let dx = point.x - wheelCenter.x
        let dy = point.y - wheelCenter.y
        let dist = sqrt(dx * dx + dy * dy)
        let inCircle = (dist <= backdropRadius)
        let inTopBar = topBarRect.contains(point)
        let inCloseBtn = closeButtonRect.contains(point)
        if !inCircle && !inTopBar && !inCloseBtn {
            return nil
        }
        return super.hitTest(point)
    }

    // MARK: - Mouse & Dragging Events
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        mouseDownHit = indexForPoint(pt)
        dragStartMouseScreen = NSEvent.mouseLocation
        dragStartWindowOrigin = window?.frame.origin
        isDraggingWindow = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startMouse = dragStartMouseScreen,
              let startOrigin = dragStartWindowOrigin,
              let win = window else { return }

        let currentMouse = NSEvent.mouseLocation
        let dx = currentMouse.x - startMouse.x
        let dy = currentMouse.y - startMouse.y

        if !isDraggingWindow && (abs(dx) > 2 || abs(dy) > 2) {
            isDraggingWindow = true
            NSCursor.closedHand.set()
        }

        if isDraggingWindow {
            win.setFrameOrigin(NSPoint(x: startOrigin.x + dx, y: startOrigin.y + dy))
        }
    }

    override func mouseUp(with event: NSEvent) {
        if isDraggingWindow {
            isDraggingWindow = false
            dragStartMouseScreen = nil
            dragStartWindowOrigin = nil
            let pt = convert(event.locationInWindow, from: nil)
            updateCursor(for: pt)
            return
        }
        dragStartMouseScreen = nil
        dragStartWindowOrigin = nil

        let pt = convert(event.locationInWindow, from: nil)
        let hit = indexForPoint(pt)

        if hit == -20 {
            SoundManager.playPop()
            DropWheelWindowController.shared.hideWheel()
            return
        }

        if hit <= -10 {
            // Clicked top bar button
            let btnIdx = -hit - 10
            let targetMode: WheelMode = (btnIdx == 0) ? .conversions : (btnIdx == 1) ? .tools : .actions
            setMode(targetMode)
            updateCursor(for: pt)
            return
        }

        if hit == -4 {
            // Clicked small into (x) button -> Remove file from middle without changing mode!
            onClearFiles?()
            updateCursor(for: pt)
            return
        }

        if hit == -2 {
            onHubClicked?()
        } else if hit >= 0 && hit < items.count {
            onSelectSlice?(items[hit], currentPaths)
        }
        updateCursor(for: pt)
    }

    override func rightMouseDown(with event: NSEvent) {
        SoundManager.playPop()
        DropWheelWindowController.shared.hideWheel()
    }

    override func mouseMoved(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        updateCursor(for: pt)

        let hit = indexForPoint(pt)
        let newHub = (hit == -2)
        let newClear = (hit == -4)
        let newIndex = (hit >= 0) ? hit : -1
        let newTopBar = (hit <= -10) ? (-hit - 10) : -1
        let newClose = (hit == -20)

        if newIndex != hoveredIndex || newHub != isHubHovered || newClear != isClearHovered || newTopBar != hoveredTopBarIndex || newClose != isCloseHovered {
            if (newIndex != hoveredIndex && newIndex >= 0) || (newTopBar != hoveredTopBarIndex && newTopBar >= 0) || (newClose != isCloseHovered && newClose) || (newClear != isClearHovered && newClear) {
                SoundManager.playTick()
            }
            hoveredIndex = newIndex
            isHubHovered = newHub
            isClearHovered = newClear
            hoveredTopBarIndex = newTopBar
            isCloseHovered = newClose
            needsDisplay = true
        }
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
        hoveredIndex = -1
        isHubHovered = false
        isClearHovered = false
        hoveredTopBarIndex = -1
        isCloseHovered = false
        needsDisplay = true
    }

    private func updateCursor(for point: NSPoint) {
        let hit = indexForPoint(point)
        if hit == -20 || hit == -4 {
            NSCursor.pointingHand.set()
        } else if hit <= -10 {
            NSCursor.pointingHand.set()
        } else if hit >= 0 && hit < items.count {
            NSCursor.pointingHand.set()
        } else if hit == -2 {
            NSCursor.pointingHand.set()
        } else if topBarRect.contains(point) {
            NSCursor.openHand.set()
        } else {
            NSCursor.arrow.set()
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
            let targetMode: WheelMode = (newTopBar == 0) ? .conversions : (newTopBar == 1) ? .tools : .actions
            setMode(targetMode)
        }

        if newIndex != hoveredIndex || newHub != isHubHovered || newTopBar != hoveredTopBarIndex {
            if (newIndex != hoveredIndex && newIndex >= 0) || (newTopBar != hoveredTopBarIndex && newTopBar >= 0) {
                SoundManager.playTick()
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

    // MARK: - Smooth Rounded Cushion Petal Path Generator
    private func makeCushionPetal(center: CGPoint, innerR: CGFloat, outerR: CGFloat, startDeg: CGFloat, endDeg: CGFloat, outerCornerRadius: CGFloat = 16.0, innerCornerRadius: CGFloat = 8.0) -> CGPath {
        let path = CGMutablePath()
        let crOuter = outerCornerRadius
        let crInner = innerCornerRadius

        // Radians
        let sRad = startDeg * .pi / 180.0
        let eRad = endDeg * .pi / 180.0

        // Angular offset for corner radius along outer and inner concentric arcs
        let dOuter = crOuter / outerR
        let dInner = crInner / innerR

        // Points along the petal:
        let midR = (innerR + outerR) / 2.0
        let p_start_mid = CGPoint(x: center.x + midR * cos(sRad), y: center.y + midR * sin(sRad))

        // Outer-start vertex & tangent point
        let v_os = CGPoint(x: center.x + outerR * cos(sRad), y: center.y + outerR * sin(sRad))
        let p_os_arc = CGPoint(x: center.x + outerR * cos(sRad - dOuter), y: center.y + outerR * sin(sRad - dOuter))

        // Outer-end vertex & tangent point
        let v_oe = CGPoint(x: center.x + outerR * cos(eRad), y: center.y + outerR * sin(eRad))
        let p_oe_radial = CGPoint(x: center.x + (outerR - crOuter) * cos(eRad), y: center.y + (outerR - crOuter) * sin(eRad))

        // Inner-end vertex & tangent point
        let v_ie = CGPoint(x: center.x + innerR * cos(eRad), y: center.y + innerR * sin(eRad))
        let p_ie_arc = CGPoint(x: center.x + innerR * cos(eRad + dInner), y: center.y + innerR * sin(eRad + dInner))

        // Inner-start vertex & tangent point
        let v_is = CGPoint(x: center.x + innerR * cos(sRad), y: center.y + innerR * sin(sRad))
        let p_is_radial = CGPoint(x: center.x + (innerR + crInner) * cos(sRad), y: center.y + (innerR + crInner) * sin(sRad))

        // Start path at p_start_mid
        path.move(to: p_start_mid)

        // 1. Line towards outer-start vertex, curve smoothly into outer arc
        path.addArc(tangent1End: v_os, tangent2End: p_os_arc, radius: crOuter)

        // 2. Outer arc clockwise to (eRad + dOuter)
        path.addArc(center: center, radius: outerR, startAngle: sRad - dOuter, endAngle: eRad + dOuter, clockwise: true)

        // 3. Curve smoothly around outer-end vertex into end radial line
        path.addArc(tangent1End: v_oe, tangent2End: p_oe_radial, radius: crOuter)

        // 4. Line along end radial edge towards inner-end vertex, curve into inner arc
        path.addArc(tangent1End: v_ie, tangent2End: p_ie_arc, radius: crInner)

        // 5. Inner arc counter-clockwise to (sRad - dInner)
        path.addArc(center: center, radius: innerR, startAngle: eRad + dInner, endAngle: sRad - dInner, clockwise: false)

        // 6. Curve smoothly around inner-start vertex back into start radial edge
        path.addArc(tangent1End: v_is, tangent2End: p_is_radial, radius: crInner)

        path.closeSubpath()
        return path
    }

    // MARK: - Drawing
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let dark = isDarkMode

        // 1. Soft Outer Halo / Backing Disc with Decreased Outer Shadow
        context.saveGState()
        let haloPath = CGPath(ellipseIn: CGRect(x: wheelCenter.x - backdropRadius, y: wheelCenter.y - backdropRadius, width: backdropRadius * 2, height: backdropRadius * 2), transform: nil)
        context.addPath(haloPath)
        if dark {
            context.setFillColor(NSColor(srgbRed: 0.14, green: 0.16, blue: 0.19, alpha: 0.85).cgColor)
            context.setShadow(offset: CGSize(width: 0, height: -2), blur: 8, color: NSColor.black.withAlphaComponent(0.18).cgColor)
        } else {
            context.setFillColor(NSColor(srgbRed: 0.90, green: 0.92, blue: 0.94, alpha: 0.40).cgColor)
            context.setShadow(offset: CGSize(width: 0, height: -2), blur: 8, color: NSColor.black.withAlphaComponent(0.05).cgColor)
        }
        context.fillPath()
        context.restoreGState()

        // 2. Draw Petals with Smooth Cushion Fillets & Gaps
        let angleStep = sliceAngle()
        let isDense = items.count > 8
        let gap: CGFloat = isDense ? 2.5 : 3.5
        let outerCR: CGFloat = isDense ? 10.0 : 14.0
        let innerCR: CGFloat = isDense ? 5.0 : 7.0

        for (i, item) in items.enumerated() {
            let isHovered = (i == hoveredIndex)

            // Apply the smooth rotation offset so the whole ring spins together.
            let s: CGFloat
            let e: CGFloat
            if items.count == 1 {
                s = 270.0 - gap / 2.0 + wheelRotationAngle
                e = s - (360.0 - gap)
            } else {
                s = 90.0 - CGFloat(i) * angleStep - gap / 2.0 + wheelRotationAngle
                e = s - (angleStep - gap)
            }
            let petal = makeCushionPetal(center: wheelCenter, innerR: innerRadius, outerR: outerRadius, startDeg: s, endDeg: e, outerCornerRadius: outerCR, innerCornerRadius: innerCR)

            // Fill & Shadow
            context.saveGState()
            context.addPath(petal)
            if isHovered {
                context.setFillColor(NSColor(srgbRed: 1.0, green: 0.33, blue: 0.0, alpha: 1.0).cgColor)
                context.setShadow(offset: CGSize(width: 0, height: -1), blur: 4, color: NSColor(srgbRed: 1.0, green: 0.33, blue: 0.0, alpha: 0.35).cgColor)
            } else if dark {
                context.setFillColor(NSColor(srgbRed: 0.20, green: 0.22, blue: 0.25, alpha: 0.98).cgColor)
                context.setShadow(offset: CGSize(width: 0, height: -1), blur: 2, color: NSColor.black.withAlphaComponent(0.15).cgColor)
            } else {
                context.setFillColor(NSColor(srgbRed: 0.94, green: 0.95, blue: 0.96, alpha: 0.98).cgColor)
                context.setShadow(offset: CGSize(width: 0, height: -1), blur: 2, color: NSColor.black.withAlphaComponent(0.04).cgColor)
            }
            context.fillPath()
            context.restoreGState()

            // Stroke Border
            context.saveGState()
            context.addPath(petal)
            if isHovered {
                context.setStrokeColor(NSColor(srgbRed: 0.90, green: 0.28, blue: 0.0, alpha: 0.8).cgColor)
            } else if dark {
                context.setStrokeColor(NSColor(white: 1.0, alpha: 0.10).cgColor)
            } else {
                context.setStrokeColor(NSColor(white: 1.0, alpha: 0.8).cgColor)
            }
            context.setLineWidth(1.0)
            context.strokePath()
            context.restoreGState()

            // Label & Icon  (midpoint of the petal arc, already includes rotationAngle)
            let midDeg = (s + e) / 2.0
            let midRad = midDeg * .pi / 180.0
            let midRadius = (innerRadius + outerRadius) / 2.0
            let tx = wheelCenter.x + midRadius * cos(midRad)
            let ty = wheelCenter.y + midRadius * sin(midRad)

            let textColor: NSColor
            if isHovered {
                textColor = .white
            } else if dark {
                textColor = NSColor(srgbRed: 0.92, green: 0.94, blue: 0.96, alpha: 1.0)
            } else {
                textColor = NSColor(srgbRed: 0.12, green: 0.13, blue: 0.15, alpha: 1.0)
            }

            if let iconName = item.iconName, let tinted = tintedSymbol(name: iconName, color: textColor, size: isDense ? 15 : 18) {
                let iconSize: CGFloat = isDense ? 15 : 18
                let fontSize: CGFloat = isDense ? 9.5 : 11.0
                let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
                let str = NSAttributedString(string: item.title, attributes: attrs)
                let sz = str.size()

                // Total height of the icon + gap + text, perfectly centered at (tx, ty)
                let totalHeight = iconSize + 3.0 + sz.height
                let textY = ty - totalHeight / 2.0
                let iconY = textY + sz.height + 3.0

                let iconRect = NSRect(x: tx - iconSize / 2.0, y: iconY, width: iconSize, height: iconSize)
                tinted.draw(in: iconRect)
                str.draw(at: NSPoint(x: tx - sz.width / 2.0, y: textY))
            } else {
                let font = NSFont.systemFont(ofSize: 13, weight: .bold)
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
                let str = NSAttributedString(string: item.title, attributes: attrs)
                let sz = str.size()
                str.draw(at: NSPoint(x: tx - sz.width / 2.0, y: ty - sz.height / 2.0))
            }
        }

        // 2b. Side indicator and scroll hint – only shown when allItems.count > 8
        if hasMoreItems {
            let dotCount = totalSides
            let indicatorRadius = outerRadius + 14.0
            let arcSpan: CGFloat = CGFloat(max(1, dotCount - 1)) * 16.0 // compact dot indicator
            let anchorDeg: CGFloat = 270.0 // bottom of wheel
            context.saveGState()
            for di in 0..<dotCount {
                let fraction = dotCount > 1 ? (CGFloat(di) / CGFloat(dotCount - 1) - 0.5) : 0
                let dotDeg = anchorDeg + fraction * arcSpan
                let dotRad = dotDeg * .pi / 180.0
                let cx = wheelCenter.x + indicatorRadius * cos(dotRad)
                let cy = wheelCenter.y + indicatorRadius * sin(dotRad)
                let isCurrent = (di == currentSideIndex)
                let dotSize: CGFloat = isCurrent ? 5.5 : 3.5
                let dotColor = isCurrent
                    ? NSColor(srgbRed: 1.0, green: 0.384, blue: 0.031, alpha: 1.0)
                    : (dark ? NSColor(white: 1.0, alpha: 0.35) : NSColor(white: 0.0, alpha: 0.25))
                dotColor.setFill()
                let dotRect = CGRect(x: cx - dotSize / 2, y: cy - dotSize / 2, width: dotSize, height: dotSize)
                let dotPath = CGPath(ellipseIn: dotRect, transform: nil)
                context.addPath(dotPath)
                context.fillPath()
            }
            context.restoreGState()

            // Side X of Y · scroll to rotate hint
            if hoveredIndex < 0 {
                let hintFont = NSFont.systemFont(ofSize: 8.5, weight: .semibold)
                let hintColor = dark ? NSColor(white: 0.65, alpha: 0.95) : NSColor(white: 0.40, alpha: 0.85)
                let hintAttrs: [NSAttributedString.Key: Any] = [.font: hintFont, .foregroundColor: hintColor]
                let hintStr = NSAttributedString(string: "Side \(currentSideIndex + 1) of \(totalSides) · scroll to rotate", attributes: hintAttrs)
                let hSz = hintStr.size()
                hintStr.draw(at: NSPoint(x: wheelCenter.x - hSz.width / 2, y: wheelCenter.y - outerRadius - 28))
            }
        }

        // 3. Center Circle Hub: DropDial / Drag & Drop / Selected File Name / Hovered Slice
        let hubRect = NSRect(x: wheelCenter.x - hubRadius, y: wheelCenter.y - hubRadius, width: hubRadius * 2, height: hubRadius * 2)
        let hubPath = NSBezierPath(ovalIn: hubRect)

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -1), blur: 5, color: NSColor.black.withAlphaComponent(dark ? 0.25 : 0.06).cgColor)
        if dark {
            NSColor(srgbRed: 0.16, green: 0.18, blue: 0.21, alpha: 0.98).setFill()
        } else {
            NSColor(srgbRed: 0.98, green: 0.98, blue: 0.99, alpha: 0.98).setFill()
        }
        hubPath.fill()
        context.restoreGState()

        let orangeColor = NSColor(srgbRed: 1.0, green: 0.384, blue: 0.031, alpha: isHubHovered ? 1.0 : 0.85)
        orangeColor.setStroke()
        hubPath.lineWidth = isHubHovered ? 2.0 : 1.5
        hubPath.stroke()

        if hoveredIndex >= 0 && hoveredIndex < items.count {
            // Hovered Slice Preview inside Hub
            let item = items[hoveredIndex]
            let modeTitle = mode == .conversions ? "CONVERT" : (mode == .tools ? "TOOL" : "ACTION")
            let modeFont = NSFont.systemFont(ofSize: 8, weight: .bold)
            let modeAttrs: [NSAttributedString.Key: Any] = [.font: modeFont, .foregroundColor: orangeColor]
            let modeStr = NSAttributedString(string: modeTitle, attributes: modeAttrs)
            let mSz = modeStr.size()
            modeStr.draw(at: NSPoint(x: wheelCenter.x - mSz.width / 2, y: wheelCenter.y + 11))

            let titleFont = NSFont.systemFont(ofSize: 13, weight: .bold)
            let titleColor = dark ? NSColor.white : NSColor(srgbRed: 0.12, green: 0.13, blue: 0.15, alpha: 1.0)
            let titleAttrs: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: titleColor]
            let titleStr = NSAttributedString(string: item.title, attributes: titleAttrs)
            let tSz = titleStr.size()
            titleStr.draw(at: NSPoint(x: wheelCenter.x - tSz.width / 2, y: wheelCenter.y - tSz.height / 2 + 1))

            let subFont = NSFont.systemFont(ofSize: 8, weight: .medium)
            let subColor = dark ? NSColor(white: 0.65, alpha: 1.0) : NSColor(white: 0.50, alpha: 1.0)
            let subAttrs: [NSAttributedString.Key: Any] = [.font: subFont, .foregroundColor: subColor]
            let subStr = NSAttributedString(string: "Click or drop", attributes: subAttrs)
            let sSz = subStr.size()
            subStr.draw(at: NSPoint(x: wheelCenter.x - sSz.width / 2, y: wheelCenter.y - 18))
        } else if !currentPaths.isEmpty {
            // Showing Selected File Name & Thumbnail
            let first = currentPaths.first!
            let fileName = URL(fileURLWithPath: first).lastPathComponent
            let count = currentPaths.count

            let iconImage = hubThumbnail ?? NSWorkspace.shared.icon(forFile: first)
            let iconSize: CGFloat = count > 1 ? 20 : 22
            let iconRect = NSRect(x: wheelCenter.x - iconSize / 2, y: wheelCenter.y - 1, width: iconSize, height: iconSize)
            iconImage.draw(in: iconRect)

            if count > 1 {
                let badgeAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 8.5, weight: .bold),
                    .foregroundColor: orangeColor
                ]
                let badgeStr = NSAttributedString(string: "\(count) files", attributes: badgeAttrs)
                let bSz = badgeStr.size()
                badgeStr.draw(at: NSPoint(x: wheelCenter.x - bSz.width / 2, y: wheelCenter.y - 14))

                let subAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 7.5, weight: .medium),
                    .foregroundColor: dark ? NSColor(white: 0.65, alpha: 1.0) : NSColor(white: 0.50, alpha: 1.0)
                ]
                let subStr = NSAttributedString(string: "click to switch", attributes: subAttrs)
                let sSz = subStr.size()
                subStr.draw(at: NSPoint(x: wheelCenter.x - sSz.width / 2, y: wheelCenter.y - 25))
            } else {
                let nameFont = NSFont.systemFont(ofSize: 8.5, weight: .semibold)
                let nameColor = dark ? NSColor.white : NSColor(srgbRed: 0.12, green: 0.13, blue: 0.15, alpha: 1.0)
                let style = NSMutableParagraphStyle()
                style.lineBreakMode = .byTruncatingMiddle
                style.alignment = .center

                let nameAttrs: [NSAttributedString.Key: Any] = [
                    .font: nameFont,
                    .foregroundColor: nameColor,
                    .paragraphStyle: style
                ]
                let maxNameW: CGFloat = hubRadius * 1.6
                let nameRect = NSRect(x: wheelCenter.x - maxNameW / 2, y: wheelCenter.y - 15, width: maxNameW, height: 12)
                let nameStr = NSAttributedString(string: fileName, attributes: nameAttrs)
                nameStr.draw(in: nameRect)

                let subAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 7.5, weight: .medium),
                    .foregroundColor: orangeColor
                ]
                let subStr = NSAttributedString(string: mode.title.uppercased(), attributes: subAttrs)
                let sSz = subStr.size()
                subStr.draw(at: NSPoint(x: wheelCenter.x - sSz.width / 2, y: wheelCenter.y - 25))
            }

            // Small into (x) remove button inside top of middle circle (just above the file)
            let clearRect = hubClearButtonRect
            let isHover = isClearHovered
            let clearCircle = NSBezierPath(ovalIn: clearRect)

            context.saveGState()
            if isHover {
                NSColor(srgbRed: 0.95, green: 0.22, blue: 0.22, alpha: 0.95).setFill()
            } else {
                if dark {
                    NSColor(srgbRed: 0.22, green: 0.24, blue: 0.28, alpha: 0.90).setFill()
                } else {
                    NSColor(srgbRed: 0.88, green: 0.89, blue: 0.92, alpha: 0.92).setFill()
                }
            }
            clearCircle.fill()

            let strokeColor = isHover ? NSColor.white : (dark ? NSColor(white: 1.0, alpha: 0.25) : NSColor(white: 0.0, alpha: 0.15))
            strokeColor.setStroke()
            clearCircle.lineWidth = 1.0
            clearCircle.stroke()

            // Draw crisp cross lines (into mark)
            let crossPath = NSBezierPath()
            let pad: CGFloat = 4.8
            crossPath.move(to: NSPoint(x: clearRect.minX + pad, y: clearRect.minY + pad))
            crossPath.line(to: NSPoint(x: clearRect.maxX - pad, y: clearRect.maxY - pad))
            crossPath.move(to: NSPoint(x: clearRect.maxX - pad, y: clearRect.minY + pad))
            crossPath.line(to: NSPoint(x: clearRect.minX + pad, y: clearRect.maxY - pad))
            crossPath.lineWidth = 1.6
            crossPath.lineCapStyle = .round
            (isHover ? NSColor.white : (dark ? NSColor(white: 0.9, alpha: 1.0) : NSColor(srgbRed: 0.2, green: 0.2, blue: 0.2, alpha: 1.0))).setStroke()
            crossPath.stroke()
            context.restoreGState()
        } else {
            // Default: Name DropDial & Drag and Drop / Click
            let dropdialAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .bold),
                .foregroundColor: orangeColor
            ]
            let dropdialStr = NSAttributedString(string: "DropDial", attributes: dropdialAttrs)
            let lSz = dropdialStr.size()
            dropdialStr.draw(at: NSPoint(x: wheelCenter.x - lSz.width / 2, y: wheelCenter.y + 3))

            let subColor = dark ? NSColor(white: 0.65, alpha: 1.0) : NSColor(white: 0.50, alpha: 1.0)
            let subAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 8.5, weight: .medium),
                .foregroundColor: subColor
            ]
            let subStr = NSAttributedString(string: "Drop files\nor click", attributes: subAttrs)
            let sSz = subStr.size()
            subStr.draw(at: NSPoint(x: wheelCenter.x - sSz.width / 2, y: wheelCenter.y - 18))
        }

        // 4. Floating Pill Toolbar Above Wheel: [ ⇧ Convert ]  [ ⌘ Tools ]  [ ⌃ Actions ]
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -3), blur: 12, color: NSColor.black.withAlphaComponent(dark ? 0.35 : 0.12).cgColor)
        let barPath = NSBezierPath(roundedRect: topBarRect, xRadius: topBarRect.height / 2, yRadius: topBarRect.height / 2)
        if dark {
            NSColor(srgbRed: 0.14, green: 0.16, blue: 0.19, alpha: 0.95).setFill()
            barPath.fill()
            NSColor(white: 1.0, alpha: 0.12).setStroke()
        } else {
            NSColor(white: 0.96, alpha: 0.95).setFill()
            barPath.fill()
            NSColor(white: 1.0, alpha: 0.8).setStroke()
        }
        barPath.lineWidth = 1.0
        barPath.stroke()
        context.restoreGState()

        // 3 Buttons inside top bar
        let modes: [(key: String, title: String, mode: WheelMode)] = [
            ("⇧", "Convert", .conversions),
            ("⌘", "Tools", .tools),
            ("⌃", "Actions", .actions)
        ]
        let btnW = (topBarRect.width - 6) / 3.0

        for (mIdx, m) in modes.enumerated() {
            let isActive = (m.mode == self.mode)
            let isBtnHovered = (mIdx == hoveredTopBarIndex)
            let btnX = topBarRect.minX + 3 + CGFloat(mIdx) * btnW
            let btnRect = NSRect(x: btnX, y: topBarRect.minY + 2.5, width: btnW, height: topBarRect.height - 5)

            if isActive {
                let activePill = NSBezierPath(roundedRect: btnRect, xRadius: btnRect.height / 2, yRadius: btnRect.height / 2)
                context.saveGState()
                context.setShadow(offset: CGSize(width: 0, height: -1), blur: 4, color: NSColor.black.withAlphaComponent(dark ? 0.3 : 0.1).cgColor)
                if dark {
                    NSColor(srgbRed: 0.28, green: 0.30, blue: 0.35, alpha: 1.0).setFill()
                } else {
                    NSColor.white.setFill()
                }
                activePill.fill()
                context.restoreGState()
            } else if isBtnHovered {
                let hoverPill = NSBezierPath(roundedRect: btnRect, xRadius: btnRect.height / 2, yRadius: btnRect.height / 2)
                NSColor(white: dark ? 0.3 : 1.0, alpha: 0.4).setFill()
                hoverPill.fill()
            }

            // Draw Keycap
            let keyCapSize: CGFloat = 16
            let keyCapRect = NSRect(x: btnRect.minX + 6, y: btnRect.midY - keyCapSize / 2, width: keyCapSize, height: keyCapSize)
            let keyCapPath = NSBezierPath(roundedRect: keyCapRect, xRadius: 3.5, yRadius: 3.5)
            if dark {
                NSColor(white: 0.22, alpha: 0.85).setFill()
                keyCapPath.fill()
                NSColor(white: 0.35, alpha: 0.5).setStroke()
            } else {
                NSColor(white: 0.90, alpha: 0.85).setFill()
                keyCapPath.fill()
                NSColor(white: 0.75, alpha: 0.6).setStroke()
            }
            keyCapPath.lineWidth = 0.5
            keyCapPath.stroke()

            let keyFont = NSFont.systemFont(ofSize: 9, weight: .bold)
            let keyAttrs: [NSAttributedString.Key: Any] = [.font: keyFont, .foregroundColor: dark ? NSColor(white: 0.85, alpha: 1.0) : NSColor(white: 0.25, alpha: 1.0)]
            let keyStr = NSAttributedString(string: m.key, attributes: keyAttrs)
            let kSz = keyStr.size()
            keyStr.draw(at: NSPoint(x: keyCapRect.midX - kSz.width / 2, y: keyCapRect.midY - kSz.height / 2))

            // Draw Title
            let titleColor: NSColor
            if isActive {
                titleColor = dark ? .white : NSColor(srgbRed: 0.12, green: 0.13, blue: 0.15, alpha: 1.0)
            } else {
                titleColor = dark ? NSColor(white: 0.60, alpha: 1.0) : NSColor(white: 0.45, alpha: 1.0)
            }
            let titleFont = NSFont.systemFont(ofSize: 10.5, weight: isActive ? .bold : .medium)
            let titleAttrs: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: titleColor]
            let titleStr = NSAttributedString(string: m.title, attributes: titleAttrs)
            titleStr.draw(at: NSPoint(x: keyCapRect.maxX + 4, y: btnRect.midY - titleStr.size().height / 2))
        }

        // 5. Close Button (✕) Next to Floating Pill Bar
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -3), blur: 12, color: NSColor.black.withAlphaComponent(dark ? 0.35 : 0.12).cgColor)
        let closePath = NSBezierPath(roundedRect: closeButtonRect, xRadius: closeButtonRect.height / 2, yRadius: closeButtonRect.height / 2)
        if isCloseHovered {
            NSColor(srgbRed: 0.92, green: 0.28, blue: 0.28, alpha: 0.90).setFill()
            closePath.fill()
            NSColor(white: 1.0, alpha: 0.3).setStroke()
        } else if dark {
            NSColor(srgbRed: 0.14, green: 0.16, blue: 0.19, alpha: 0.95).setFill()
            closePath.fill()
            NSColor(white: 1.0, alpha: 0.12).setStroke()
        } else {
            NSColor(white: 0.96, alpha: 0.95).setFill()
            closePath.fill()
            NSColor(white: 1.0, alpha: 0.8).setStroke()
        }
        closePath.lineWidth = 1.0
        closePath.stroke()
        context.restoreGState()

        let xFont = NSFont.systemFont(ofSize: 12, weight: .bold)
        let xColor = isCloseHovered ? NSColor.white : (dark ? NSColor(white: 0.65, alpha: 1.0) : NSColor(white: 0.45, alpha: 1.0))
        let xAttrs: [NSAttributedString.Key: Any] = [.font: xFont, .foregroundColor: xColor]
        let xStr = NSAttributedString(string: "✕", attributes: xAttrs)
        let xSz = xStr.size()
        xStr.draw(at: NSPoint(x: closeButtonRect.midX - xSz.width / 2, y: closeButtonRect.midY - xSz.height / 2))
    }
}

final class DropWheelWindowController: NSWindowController {
    static let shared = DropWheelWindowController()

    private let wheelView = RadialWheelView()
    private var currentPaths: [String] = []
    private var currentMode: WheelMode = .conversions
    private var activeToolControllers: [ToolWindowController] = []

    private var localOutsideClickMonitor: Any?

    init() {
        let width: CGFloat = 340
        let height: CGFloat = 370
        let panel = KeyPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isMovableByWindowBackground = false
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

        wheelView.onModeChanged = { [weak self] newMode in
            self?.currentMode = newMode
        }

        wheelView.onFilesDropped = { [weak self] paths in
            self?.loadFiles(paths)
        }

        wheelView.onClearFiles = { [weak self] in
            guard let self = self else { return }
            SoundManager.playPop()
            self.currentPaths = []
            self.wheelView.currentPaths = []
            self.wheelView.configure(paths: [], mode: self.currentMode)
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

    func reloadTheme() {
        wheelView.reloadTheme()
    }

    func setLoadedPaths(_ paths: [String]) {
        self.currentPaths = paths
    }

    func showWheel() {
        showAtCursor(mode: currentMode)
    }

    func showAtCursor(mode: WheelMode) {
        let mouse = NSEvent.mouseLocation
        let width: CGFloat = 340
        let height: CGFloat = 370
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main ?? NSScreen()
        let frame = screen.visibleFrame

        // Outer line of the circular wheel placed at pointer (cursor) instead of center
        // so the wheel does not block the file underneath the cursor.
        let radius: CGFloat = wheelView.backdropRadius // 150 pt
        let canOpenRight = (mouse.x + radius + (width - wheelView.wheelCenter.x)) <= (frame.maxX - 10)
        let screenCenterX: CGFloat = canOpenRight ? (mouse.x + radius) : (mouse.x - radius)
        let screenCenterY: CGFloat = mouse.y

        var x = screenCenterX - wheelView.wheelCenter.x
        var y = screenCenterY - wheelView.wheelCenter.y

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

    func setMode(_ mode: WheelMode) {
        guard mode != self.currentMode else { return }
        self.currentMode = mode
        wheelView.setMode(mode)
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

    private var openTimestamp: TimeInterval = 0

    private func installOutsideClickMonitors() {
        removeOutsideClickMonitors()
        openTimestamp = ProcessInfo.processInfo.systemUptime

        localOutsideClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self, let win = self.window, win.isVisible else { return event }
            if ProcessInfo.processInfo.systemUptime - self.openTimestamp < 0.25 {
                return event
            }
            if event.window == win {
                let local = self.wheelView.convert(event.locationInWindow, from: nil)
                let dx = local.x - self.wheelView.wheelCenter.x
                let dy = local.y - self.wheelView.wheelCenter.y
                let dist = sqrt(dx * dx + dy * dy)
                let inCircle = (dist <= self.wheelView.backdropRadius)
                let inTopBar = self.wheelView.topBarRect.contains(local)
                let inCloseBtn = self.wheelView.closeButtonRect.contains(local)
                if !inCircle && !inTopBar && !inCloseBtn {
                    DispatchQueue.main.async {
                        self.hideWheel()
                    }
                }
            }
            return event
        }
    }

    private func removeOutsideClickMonitors() {
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

        // Check license / trial status
        guard LicenseManager.shared.canUseApp() else {
            hideWheel()
            LicenseWindowController.shared.show()
            return
        }

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
                if let matched = multi.first(where: { $0.id == item.id }) {
                    let zeroParamTools = ["removeMetadata", "muteVideo", "joinVideos", "joinAudio", "createPDF"]
                    if matched.fields.isEmpty && zeroParamTools.contains(matched.id) {
                        executeJob(action: item.id, paths: activePaths, params: nil)
                        return
                    } else {
                        let toolCtrl = ToolWindowController(paths: activePaths, tool: matched)
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
            }

            guard let first = activePaths.first else { return }
            let cat = Catalog.category(for: first)
            let tool = Catalog.findTool(id: item.id) ?? Catalog.tools(for: cat).first(where: { $0.id == item.id })

            if let tool = tool {
                let zeroParamTools = ["removeMetadata", "muteVideo", "joinVideos", "joinAudio", "createPDF"]
                if tool.fields.isEmpty && zeroParamTools.contains(tool.id) {
                    executeJob(action: item.id, paths: activePaths, params: nil)
                    return
                }

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

        case "action:metadata", "removeMetadata":
            executeJob(action: "removeMetadata", paths: paths, params: nil)

        default:
            break
        }
    }

    private func executeJob(action: String, paths: [String], params: [String: String]?) {
        guard LicenseManager.shared.canUseApp() else {
            hideWheel()
            LicenseWindowController.shared.show()
            return
        }

        let job = ConversionJob(Paths: paths, Action: action, Parameters: params)
        TaskIndicatorManager.shared.enqueue(job: job) { card in
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
        self.currentPaths = []
        self.wheelView.loadDefaultItems()
        hideWheel()
    }
}
