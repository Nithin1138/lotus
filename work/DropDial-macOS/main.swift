import AppKit
import Carbon

func getFinderSelectedFiles() -> [String] {
    let script = """
    tell application "Finder"
        set sel to selection as alias list
        set res to {}
        repeat with anItem in sel
            set end of res to POSIX path of anItem
        end repeat
        set AppleScript's text item delimiters to linefeed
        return res as text
    end tell
    """
    guard let appleScript = NSAppleScript(source: script) else { return [] }
    var errorInfo: NSDictionary?
    let descriptor = appleScript.executeAndReturnError(&errorInfo)
    if let output = descriptor.stringValue, !output.isEmpty {
        let paths = output.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && FileManager.default.fileExists(atPath: $0) }
        return paths
    }
    return []
}

final class EventTapManager {
    static let shared = EventTapManager()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    func setup() {
        guard eventTap == nil, AXIsProcessTrusted() else { return }
        let mask = (1 << CGEventType.keyDown.rawValue)
        let observer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                if type == .keyDown {
                    let flags = event.flags
                    let hasCmd = flags.contains(.maskCommand)
                    let hasShift = flags.contains(.maskShift)
                    let hasNoOther = !flags.contains(.maskAlternate) && !flags.contains(.maskControl)
                    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)

                    // kVK_ANSI_D = 2, kVK_ANSI_L = 37
                    if hasCmd && hasShift && hasNoOther && (keyCode == 2 || keyCode == 37) {
                        DispatchQueue.main.async {
                            let files = getFinderSelectedFiles()
                            if !files.isEmpty {
                                DropWheelWindowController.shared.loadFiles(files)
                            } else {
                                DropWheelWindowController.shared.toggleWheel(mode: nil)
                            }
                        }
                        return nil
                    }
                }
                return Unmanaged.passRetained(event)
            },
            userInfo: observer
        ) else { return }

        self.eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
    }
}

final class HotKeyManager {
    static let shared = HotKeyManager()
    private var hotKeys: [UInt32: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?

    func setup() {
        guard eventHandler == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetEventDispatcherTarget(),
            { (nextHandler, theEvent, userData) -> OSStatus in
                var hkID = EventHotKeyID()
                let status = GetEventParameter(
                    theEvent,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hkID
                )
                if status == noErr {
                    HotKeyManager.shared.handleHotKey(id: hkID.id)
                }
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandler
        )

        // ID 1: F8 (keyCode 100) -> Toggle Formats Wheel
        register(id: 1, keyCode: UInt32(kVK_F8), modifiers: 0)

        // ID 2: F9 (keyCode 101) -> Toggle Tools Wheel
        register(id: 2, keyCode: UInt32(kVK_F9), modifiers: 0)

        // ID 3: Option + Space (keyCode 49) -> Quick Toggle Wheel
        register(id: 3, keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey))

        // ID 4: Cmd + Shift + L (keyCode 37) -> Toggle DropDial Wheel
        register(id: 4, keyCode: UInt32(kVK_ANSI_L), modifiers: UInt32(cmdKey | shiftKey))

        // ID 5: F10 (keyCode 109) -> Toggle Actions Wheel
        register(id: 5, keyCode: UInt32(kVK_F10), modifiers: 0)

        // ID 6: Cmd + Shift + D (keyCode 2) -> Toggle DropDial Wheel
        register(id: 6, keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(cmdKey | shiftKey))
    }

    private func register(id: UInt32, keyCode: UInt32, modifiers: UInt32) {
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4C545553), id: id) // 'LTUS'
        let err = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &hotKeyRef)
        if err == noErr, let ref = hotKeyRef {
            hotKeys[id] = ref
        }
    }

    func handleHotKey(id: UInt32) {
        DispatchQueue.main.async {
            switch id {
            case 1:
                let files = getFinderSelectedFiles()
                if !files.isEmpty {
                    DropWheelWindowController.shared.loadFiles(files, mode: .conversions)
                } else {
                    DropWheelWindowController.shared.toggleWheel(mode: .conversions)
                }
            case 2:
                let files = getFinderSelectedFiles()
                if !files.isEmpty {
                    DropWheelWindowController.shared.loadFiles(files, mode: .tools)
                } else {
                    DropWheelWindowController.shared.toggleWheel(mode: .tools)
                }
            case 5:
                let files = getFinderSelectedFiles()
                if !files.isEmpty {
                    DropWheelWindowController.shared.loadFiles(files, mode: .actions)
                } else {
                    DropWheelWindowController.shared.toggleWheel(mode: .actions)
                }
            case 3, 4, 6:
                let files = getFinderSelectedFiles()
                if !files.isEmpty {
                    DropWheelWindowController.shared.loadFiles(files)
                } else {
                    DropWheelWindowController.shared.toggleWheel(mode: nil)
                }
            default:
                break
            }
        }
    }
}

final class StatusBarDropView: NSView {
    var onDrop: (([String]) -> Void)?
    weak var statusItem: NSStatusItem?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {
        showMenu()
    }

    override func rightMouseDown(with event: NSEvent) {
        showMenu()
    }

    func showMenu() {
        guard let statusItem = statusItem, let menu = statusItem.menu, let button = statusItem.button else { return }
        button.isHighlighted = true
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
        button.isHighlighted = false
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] else {
            return false
        }
        var paths: [String] = []
        for u in items where u.isFileURL {
            let didAccess = u.startAccessingSecurityScopedResource()
            paths.append(u.path)
            if didAccess {
                u.stopAccessingSecurityScopedResource()
            }
        }
        guard !paths.isEmpty else { return false }
        onDrop?(paths)
        return true
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var dropView: StatusBarDropView!

    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var globalDragMonitor: Any?
    private var localDragMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupShortcuts()

        // 1. Listen for dynamic Accessibility permission changes
        NotificationCenter.default.addObserver(forName: NSNotification.Name("DropDialAccessibilityGranted"), object: nil, queue: .main) { [weak self] _ in
            self?.setupShortcuts()
            self?.rebuildMenu()
        }

        // 2. First launch onboarding & permissions check
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "DropDial_HasCompletedOnboarding")
        if !AXIsProcessTrusted() && !hasCompletedOnboarding {
            UserDefaults.standard.set(true, forKey: "DropDial_HasCompletedOnboarding")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                PermissionWelcomeWindowController.shared.show(isFirstLaunch: true)
            }
        }

        // 3. Setup update status listener & auto-check for updates
        UpdateService.shared.onUpdateStatusChanged = { [weak self] in
            self?.rebuildMenu()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            UpdateService.shared.checkForUpdates(isUserInitiated: false)
        }
        // Periodic background update check every 15 minutes
        Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { _ in
            UpdateService.shared.checkForUpdates(isUserInitiated: false)
        }

        // 4. Setup licensing & trial status listener
        LicenseManager.shared.initialize()
        LicenseManager.shared.onStatusChanged = { [weak self] in
            self?.rebuildMenu()
        }

        if LicenseManager.shared.shouldShowTrialExpiredPromptOnLaunch() {
            LicenseManager.shared.markTrialExpiredPromptShown()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                LicenseWindowController.shared.show(reason: "Your Free Trial Has Ended")
            }
        }

        if CommandLine.arguments.contains("--show-license") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                LicenseWindowController.shared.show()
            }
            return
        }
        if CommandLine.arguments.contains("--show-permission") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                PermissionWelcomeWindowController.shared.show()
            }
            return
        }

        let args = Array(CommandLine.arguments.dropFirst())
        let files = args.filter { FileManager.default.fileExists(atPath: $0) && !$0.hasPrefix("-") }
        if !files.isEmpty {
            DropWheelWindowController.shared.loadFiles(files)
        } else if hasCompletedOnboarding || AXIsProcessTrusted() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                DropWheelWindowController.shared.showWheel()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let update = UpdateService.shared.latestRelease {
            UpdateService.shared.showUpdateAvailableDialog(release: update)
        } else {
            UpdateService.shared.checkForUpdates(isUserInitiated: true)
        }
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        DropWheelWindowController.shared.loadFiles(filenames)
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: 28)

        if let button = statusItem.button {
            dropView = StatusBarDropView(frame: button.bounds)
            dropView.autoresizingMask = [.width, .height]
            dropView.statusItem = statusItem
            dropView.onDrop = { paths in
                DropWheelWindowController.shared.loadFiles(paths)
            }
            button.addSubview(dropView)

            button.image = createStatusBarIcon()
            button.imagePosition = .imageOnly
        }

        rebuildMenu()
    }

    private func createStatusBarIcon() -> NSImage {
        let resPath = Bundle.main.bundlePath + "/Contents/Resources/"
        if let img = NSImage(contentsOfFile: resPath + "StatusBarIcon.png") {
            img.isTemplate = true
            img.size = NSSize(width: 18, height: 18)
            return img
        }
        // Fallback: programmatic vector drawing of the 8-petal dial with 0 artifacts
        let size: CGFloat = 18.0
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            guard let c = NSGraphicsContext.current?.cgContext else { return false }
            let center = CGPoint(x: size / 2.0, y: size / 2.0)
            let scale = size / 36.0

            let innerR: CGFloat = 4.5 * scale
            let outerR: CGFloat = 14.5 * scale
            let crOuter: CGFloat = 1.6 * scale
            let crInner: CGFloat = 0.8 * scale
            let gap: CGFloat = 8.0

            let count = 8
            let angleStep: CGFloat = 360.0 / CGFloat(count)

            for i in 0..<count {
                let s = 90.0 - CGFloat(i) * angleStep - gap / 2.0
                let e = s - (angleStep - gap)
                let sRad = s * .pi / 180.0
                let eRad = e * .pi / 180.0
                let dOuter = crOuter / outerR
                let dInner = crInner / innerR
                let midR = (innerR + outerR) / 2.0

                let path = CGMutablePath()
                let p_start_mid = CGPoint(x: center.x + midR * cos(sRad), y: center.y + midR * sin(sRad))
                let v_os = CGPoint(x: center.x + outerR * cos(sRad), y: center.y + outerR * sin(sRad))
                let p_os_arc = CGPoint(x: center.x + outerR * cos(sRad - dOuter), y: center.y + outerR * sin(sRad - dOuter))
                let v_oe = CGPoint(x: center.x + outerR * cos(eRad), y: center.y + outerR * sin(eRad))
                let p_oe_radial = CGPoint(x: center.x + (outerR - crOuter) * cos(eRad), y: center.y + (outerR - crOuter) * sin(eRad))
                let v_ie = CGPoint(x: center.x + innerR * cos(eRad), y: center.y + innerR * sin(eRad))
                let p_ie_arc = CGPoint(x: center.x + innerR * cos(eRad + dInner), y: center.y + innerR * sin(eRad + dInner))
                let v_is = CGPoint(x: center.x + innerR * cos(sRad), y: center.y + innerR * sin(sRad))
                let p_is_radial = CGPoint(x: center.x + (innerR + crInner) * cos(sRad), y: center.y + (innerR + crInner) * sin(sRad))

                path.move(to: p_start_mid)
                path.addArc(tangent1End: v_os, tangent2End: p_os_arc, radius: crOuter)
                path.addArc(center: center, radius: outerR, startAngle: sRad - dOuter, endAngle: eRad + dOuter, clockwise: true)
                path.addArc(tangent1End: v_oe, tangent2End: p_oe_radial, radius: crOuter)
                path.addArc(tangent1End: v_ie, tangent2End: p_ie_arc, radius: crInner)
                path.addArc(center: center, radius: innerR, startAngle: eRad + dInner, endAngle: sRad - dInner, clockwise: false)
                path.addArc(tangent1End: v_is, tangent2End: p_is_radial, radius: crInner)
                path.closeSubpath()

                c.addPath(path)
                c.setFillColor(NSColor.black.cgColor)
                c.fillPath()
            }

            let hubR: CGFloat = 3.6 * scale
            c.addEllipse(in: CGRect(x: center.x - hubR, y: center.y - hubR, width: hubR * 2, height: hubR * 2))
            c.setStrokeColor(NSColor.black.cgColor)
            c.setLineWidth(1.6 * scale)
            c.strokePath()

            let pipR: CGFloat = 1.0 * scale
            c.addEllipse(in: CGRect(x: center.x - pipR, y: center.y - pipR, width: pipR * 2, height: pipR * 2))
            c.setFillColor(NSColor.black.cgColor)
            c.fillPath()

            return true
        }
        img.isTemplate = true
        return img
    }

    private func showContextMenu() {
        dropView?.showMenu()
    }

    private func getDraggedFiles() -> [String] {
        let pboard = NSPasteboard(name: .drag)

        let types = pboard.types?.map { $0.rawValue } ?? []
        let hasFileTypes = types.contains(where: {
            $0.contains("file") || $0.contains("finder") || $0.contains("pasteboard.promised")
        })
        guard hasFileTypes else {
            return []
        }

        // 1. Check if pasteboard explicitly contains file URLs
        if let urls = pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            let paths = urls.map { $0.path }.filter { FileManager.default.fileExists(atPath: $0) }
            if !paths.isEmpty { return paths }
        }

        // 2. Check legacy NSFilenamesPboardType
        if let files = pboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] {
            let paths = files.filter { FileManager.default.fileExists(atPath: $0) }
            if !paths.isEmpty { return paths }
        }

        // 3. Check public.file-url string
        if let string = pboard.string(forType: NSPasteboard.PasteboardType("public.file-url")), let url = URL(string: string) {
            if FileManager.default.fileExists(atPath: url.path) {
                return [url.path]
            }
        }

        // 4. Only if Finder is the active frontmost app AND a promised file drag is active, check Finder selection
        let isFinderFrontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder"
        if isFinderFrontmost && types.contains(where: { $0.contains("pasteboard.promised") || $0.contains("com.apple.finder.node") }) {
            let finderSelection = getFinderSelectedFiles()
            if !finderSelection.isEmpty {
                return finderSelection
            }
        }

        return []
    }

    private var dragStartPasteboardChangeCount: Int = -1
    private var isRealDragInProgress: Bool = false
    private var lastDragTriggerTime: TimeInterval = 0

    private func handleDragOrModifierEvent(_ event: NSEvent) {
        let isMouseDown = (NSEvent.pressedMouseButtons & 1) != 0

        // If mouse is released or event is leftMouseUp, drag has ended
        if !isMouseDown || event.type == .leftMouseUp {
            isRealDragInProgress = false
            dragStartPasteboardChangeCount = -1
            return
        }

        // On leftMouseDown, record pasteboard change count before any drag begins
        if event.type == .leftMouseDown {
            dragStartPasteboardChangeCount = NSPasteboard(name: .drag).changeCount
            isRealDragInProgress = false
            return
        }

        // If mouse is held down, detect if a real drag operation has been initiated
        let currentChangeCount = NSPasteboard(name: .drag).changeCount
        if dragStartPasteboardChangeCount == -1 {
            dragStartPasteboardChangeCount = currentChangeCount
        }

        if currentChangeCount != dragStartPasteboardChangeCount {
            isRealDragInProgress = true
        }

        // Under NO circumstances should the wheel open if there is no active file drag in progress!
        // During text selection, mouse clicks, window drags, etc., isRealDragInProgress is strictly false.
        guard isRealDragInProgress else {
            return
        }

        let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasShift = flags.contains(.shift)
        let hasCmd = flags.contains(.command)

        // Only open/switch if Shift, Command, or both are held during drag
        guard hasShift || hasCmd else {
            return
        }

        let targetMode: WheelMode
        if hasShift && hasCmd {
            targetMode = .actions
        } else if hasShift {
            targetMode = .conversions
        } else {
            targetMode = .tools
        }

        // If the wheel is already visible and active for this drag, switch mode seamlessly
        if DropWheelWindowController.shared.window?.isVisible == true {
            DropWheelWindowController.shared.setMode(targetMode)
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        if now - lastDragTriggerTime < 0.20 {
            return
        }
        lastDragTriggerTime = now

        let files = getDraggedFiles()
        guard !files.isEmpty else {
            return
        }

        DropWheelWindowController.shared.loadFiles(files, mode: targetMode)
    }

    private func setupShortcuts() {
        // 0. Remove any previous monitors to prevent duplicate triggers
        if let m = globalKeyMonitor { NSEvent.removeMonitor(m); globalKeyMonitor = nil }
        if let m = localKeyMonitor { NSEvent.removeMonitor(m); localKeyMonitor = nil }
        if let m = globalDragMonitor { NSEvent.removeMonitor(m); globalDragMonitor = nil }
        if let m = localDragMonitor { NSEvent.removeMonitor(m); localDragMonitor = nil }

        // 1. Carbon Global HotKeys (No Accessibility permissions required)
        HotKeyManager.shared.setup()

        // 2. Head-insert Event Tap for Shift + Command + D / L (intercepts before Finder Desktop shortcut)
        EventTapManager.shared.setup()

        // 3. Global & Local Monitor for Key Down
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handleKeyEvent(event)
        }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if self?.handleKeyEvent(event) == true {
                return nil
            }
            return event
        }

        // 4. Global & Local Monitor for Drag & Modifier events (Shift, Command, both)
        globalDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .leftMouseDragged, .leftMouseDown, .leftMouseUp]) { [weak self] event in
            self?.handleDragOrModifierEvent(event)
        }

        localDragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .leftMouseDragged, .leftMouseDown, .leftMouseUp]) { [weak self] event in
            self?.handleDragOrModifierEvent(event)
            return event
        }
    }

    @discardableResult
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        let code = event.keyCode
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // F8 (keyCode 100) -> Show Formats Wheel
        if code == 100 {
            let files = getFinderSelectedFiles()
            if !files.isEmpty {
                DropWheelWindowController.shared.loadFiles(files, mode: .conversions)
            } else {
                DropWheelWindowController.shared.toggleWheel(mode: .conversions)
            }
            return true
        }

        // F9 (keyCode 101) -> Show Tools Wheel
        if code == 101 {
            let files = getFinderSelectedFiles()
            if !files.isEmpty {
                DropWheelWindowController.shared.loadFiles(files, mode: .tools)
            } else {
                DropWheelWindowController.shared.toggleWheel(mode: .tools)
            }
            return true
        }

        // F10 (keyCode 109) -> Show Actions Wheel
        if code == 109 {
            let files = getFinderSelectedFiles()
            if !files.isEmpty {
                DropWheelWindowController.shared.loadFiles(files, mode: .actions)
            } else {
                DropWheelWindowController.shared.toggleWheel(mode: .actions)
            }
            return true
        }

        // Escape (keyCode 53) -> Dismiss Wheel only if wheel is visible
        if code == 53 {
            if DropWheelWindowController.shared.window?.isVisible == true {
                DropWheelWindowController.shared.hideWheel()
                return true
            }
            return false
        }

        // Cmd + Shift + D (keyCode 2) or Cmd + Shift + L (keyCode 37) -> Toggle Wheel
        let hasCmd = flags.contains(.command)
        let hasShift = flags.contains(.shift)
        let noOther = !flags.contains(.option) && !flags.contains(.control)

        if hasCmd && hasShift && noOther {
            let isD = (code == 2) || (event.charactersIgnoringModifiers?.lowercased() == "d")
            let isL = (code == 37) || (event.charactersIgnoringModifiers?.lowercased() == "l")
            if isD || isL {
                let files = getFinderSelectedFiles()
                if !files.isEmpty {
                    DropWheelWindowController.shared.loadFiles(files)
                } else {
                    DropWheelWindowController.shared.toggleWheel()
                }
                return true
            }
        }

        // Option + Space (keyCode 49) -> Toggle Wheel
        if flags.contains(.option) && code == 49 {
            let files = getFinderSelectedFiles()
            if !files.isEmpty {
                DropWheelWindowController.shared.loadFiles(files)
            } else {
                DropWheelWindowController.shared.toggleWheel()
            }
            return true
        }

        return false
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        // 1. Accessibility banner only when permission is missing
        if !AXIsProcessTrusted() {
            let permItem = NSMenuItem(title: "Grant Accessibility Permission...", action: #selector(showPermissionsWindow(_:)), keyEquivalent: "")
            permItem.target = self
            permItem.isEnabled = true
            menu.addItem(permItem)
            menu.addItem(NSMenuItem.separator())
        }

        // 2. Wheel Modes & Floating Shelf
        let f8Char = String(utf16CodeUnits: [UInt16(NSF8FunctionKey)], count: 1)
        let f8Item = NSMenuItem(title: "Formats Wheel", action: #selector(showFormatsWheel(_:)), keyEquivalent: f8Char)
        f8Item.keyEquivalentModifierMask = []
        f8Item.target = self
        f8Item.isEnabled = true
        f8Item.toolTip = "Hold ⇧ Shift while dragging files in Finder"
        menu.addItem(f8Item)

        let f9Char = String(utf16CodeUnits: [UInt16(NSF9FunctionKey)], count: 1)
        let f9Item = NSMenuItem(title: "Tools Wheel", action: #selector(showToolsWheel(_:)), keyEquivalent: f9Char)
        f9Item.keyEquivalentModifierMask = []
        f9Item.target = self
        f9Item.isEnabled = true
        f9Item.toolTip = "Hold ⌘ Command while dragging files in Finder"
        menu.addItem(f9Item)

        let f10Char = String(utf16CodeUnits: [UInt16(NSF10FunctionKey)], count: 1)
        let f10Item = NSMenuItem(title: "Actions Wheel", action: #selector(showActionsWheel(_:)), keyEquivalent: f10Char)
        f10Item.keyEquivalentModifierMask = []
        f10Item.target = self
        f10Item.isEnabled = true
        f10Item.toolTip = "Hold ⌃ Control while dragging files in Finder"
        menu.addItem(f10Item)

        let shelfItem = NSMenuItem(title: "Floating Shelf", action: #selector(showFloatingShelf(_:)), keyEquivalent: "")
        shelfItem.target = self
        shelfItem.isEnabled = true
        shelfItem.toolTip = "Temporarily hold and batch-drag files"
        menu.addItem(shelfItem)

        menu.addItem(NSMenuItem.separator())

        // 3. Quick Actions
        let toggleItem = NSMenuItem(title: "Toggle Wheel", action: #selector(toggleWheelTapped(_:)), keyEquivalent: " ")
        toggleItem.keyEquivalentModifierMask = [.option]
        toggleItem.target = self
        toggleItem.isEnabled = true
        menu.addItem(toggleItem)

        let openItem = NSMenuItem(title: "Choose Files...", action: #selector(selectFilesTapped(_:)), keyEquivalent: "o")
        openItem.keyEquivalentModifierMask = [.command]
        openItem.target = self
        openItem.isEnabled = true
        menu.addItem(openItem)

        menu.addItem(NSMenuItem.separator())

        // 4. Preferences (Theme, Sounds, Output)
        let currentTheme = UserDefaults.standard.string(forKey: "DROPDIAL_THEME") ?? "light"
        let themeMenu = NSMenu()
        themeMenu.autoenablesItems = false

        let sysItem = NSMenuItem(title: "System", action: #selector(setThemeSystem(_:)), keyEquivalent: "")
        sysItem.target = self
        sysItem.isEnabled = true
        sysItem.state = (currentTheme == "system") ? .on : .off
        themeMenu.addItem(sysItem)

        let lightItem = NSMenuItem(title: "Light", action: #selector(setThemeLight(_:)), keyEquivalent: "")
        lightItem.target = self
        lightItem.isEnabled = true
        lightItem.state = (currentTheme == "light") ? .on : .off
        themeMenu.addItem(lightItem)

        let darkItem = NSMenuItem(title: "Dark", action: #selector(setThemeDark(_:)), keyEquivalent: "")
        darkItem.target = self
        darkItem.isEnabled = true
        darkItem.state = (currentTheme == "dark") ? .on : .off
        themeMenu.addItem(darkItem)

        let themeMenuItem = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
        themeMenuItem.submenu = themeMenu
        themeMenuItem.isEnabled = true
        menu.addItem(themeMenuItem)

        let currentOut = UserDefaults.standard.string(forKey: "DROPDIAL_OUTPUT_DIR") ?? ""
        let outMenu = NSMenu()
        outMenu.autoenablesItems = false

        let sameItem = NSMenuItem(title: "Same as Source", action: #selector(setOutputSame(_:)), keyEquivalent: "")
        sameItem.target = self
        sameItem.isEnabled = true
        sameItem.state = currentOut.isEmpty ? .on : .off
        outMenu.addItem(sameItem)

        let customItem = NSMenuItem(title: "Choose Folder...", action: #selector(chooseOutputFolder(_:)), keyEquivalent: "")
        customItem.target = self
        customItem.isEnabled = true
        customItem.state = currentOut.isEmpty ? .off : .on
        if !currentOut.isEmpty {
            customItem.toolTip = currentOut
        }
        outMenu.addItem(customItem)

        outMenu.addItem(NSMenuItem.separator())
        let openFolderItem = NSMenuItem(title: "Reveal in Finder", action: #selector(openOutputFolder(_:)), keyEquivalent: "")
        openFolderItem.target = self
        openFolderItem.isEnabled = true
        outMenu.addItem(openFolderItem)

        let outMenuItem = NSMenuItem(title: "Output Folder", action: nil, keyEquivalent: "")
        outMenuItem.submenu = outMenu
        outMenuItem.isEnabled = true
        menu.addItem(outMenuItem)

        menu.addItem(NSMenuItem.separator())

        // 5. Licensing & Updates
        if let update = UpdateService.shared.latestRelease {
            let updateItem = NSMenuItem(title: "Update Available (\(UpdateService.formatVersion(update.tagName)))...", action: #selector(checkForUpdatesTapped(_:)), keyEquivalent: "")
            updateItem.target = self
            updateItem.isEnabled = true
            menu.addItem(updateItem)
        } else {
            let updateItem = NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdatesTapped(_:)), keyEquivalent: "")
            updateItem.target = self
            updateItem.isEnabled = true
            menu.addItem(updateItem)
        }

        let licStatus = LicenseManager.shared.status
        let licTitle: String
        switch licStatus {
        case .pro(let info):
            let plan = info.planDisplayName
            let userIdentifier = info.name.isEmpty ? info.email : info.name
            if let _ = info.expiresAt {
                let sec = info.secondsRemaining
                if sec <= 0 {
                    licTitle = "DropDial \(plan) (Expired)..."
                } else if sec < 60 {
                    licTitle = "DropDial \(plan) (\(userIdentifier)) • \(sec)s left"
                } else if sec < 3600 {
                    let m = sec / 60
                    licTitle = "DropDial \(plan) (\(userIdentifier)) • \(m)m left"
                } else {
                    let h = sec / 3600
                    licTitle = "DropDial \(plan) (\(userIdentifier)) • \(h)h left"
                }
            } else {
                licTitle = "DropDial \(plan) Plan (\(userIdentifier))"
            }
        case .trial(let days):
            if LicenseManager.shared.isWithinFirst24Hours {
                let sec = LicenseManager.shared.first24HoursRemainingSeconds
                let h = sec / 3600
                let m = (sec % 3600) / 60
                licTitle = "10% Off Early Bird (\(h)h \(m)m left) • Activate..."
            } else if days <= 0 {
                let timeStr = LicenseManager.formatTimeRemaining(LicenseManager.shared.trialRemainingSeconds)
                licTitle = "Activate Pro (Last day • \(timeStr) left)..."
            } else if days == 1 {
                let timeStr = LicenseManager.formatTimeRemaining(LicenseManager.shared.trialRemainingSeconds)
                licTitle = "Activate Pro (1 day left • \(timeStr))..."
            } else {
                licTitle = "Activate Pro (\(days) days left)..."
            }
        case .trialExpired:
            licTitle = "Activate DropDial Pro (Trial Expired)..."
        }
        let licItem = NSMenuItem(title: licTitle, action: #selector(showLicenseWindow(_:)), keyEquivalent: "")
        licItem.target = self
        licItem.isEnabled = true
        menu.addItem(licItem)

        menu.addItem(NSMenuItem.separator())

        // 6. About & Quit
        let aboutItem = NSMenuItem(title: "About DropDial", action: #selector(aboutTapped(_:)), keyEquivalent: "")
        aboutItem.target = self
        aboutItem.isEnabled = true
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "Quit DropDial", action: #selector(quitTapped(_:)), keyEquivalent: "q")
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = self
        quitItem.isEnabled = true
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc func showLicenseWindow(_ sender: Any? = nil) {
        LicenseWindowController.shared.show()
    }

    @objc func checkForUpdatesTapped(_ sender: Any? = nil) {
        if let update = UpdateService.shared.latestRelease {
            UpdateService.shared.showUpdateAvailableDialog(release: update)
        } else {
            UpdateService.shared.checkForUpdates(isUserInitiated: true)
        }
    }

    @objc func showPermissionsWindow(_ sender: Any? = nil) {
        PermissionWelcomeWindowController.shared.show()
    }

    @objc func showFormatsWheel(_ sender: Any? = nil) {
        DropWheelWindowController.shared.showAtCursor(mode: .conversions)
    }

    @objc func showToolsWheel(_ sender: Any? = nil) {
        DropWheelWindowController.shared.showAtCursor(mode: .tools)
    }

    @objc func showActionsWheel(_ sender: Any? = nil) {
        DropWheelWindowController.shared.showAtCursor(mode: .actions)
    }

    @objc func showFloatingShelf(_ sender: Any? = nil) {
        FloatShelfWindowController.shared.showWindow(nil)
        FloatShelfWindowController.shared.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func toggleWheelTapped(_ sender: Any? = nil) {
        DropWheelWindowController.shared.toggleWheel()
    }

    @objc func selectFilesTapped(_ sender: Any? = nil) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Choose"

        if panel.runModal() == .OK {
            let paths = panel.urls.map { $0.path }
            DropWheelWindowController.shared.loadFiles(paths)
        }
    }

    @objc func setOutputSame(_ sender: Any? = nil) {
        UserDefaults.standard.removeObject(forKey: "DROPDIAL_OUTPUT_DIR")
        rebuildMenu()
    }

    @objc func chooseOutputFolder(_ sender: Any? = nil) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"

        if panel.runModal() == .OK, let url = panel.url {
            UserDefaults.standard.set(url.path, forKey: "DROPDIAL_OUTPUT_DIR")
            rebuildMenu()
        }
    }

    @objc func setThemeSystem(_ sender: Any? = nil) {
        UserDefaults.standard.set("system", forKey: "DROPDIAL_THEME")
        DropWheelWindowController.shared.reloadTheme()
        rebuildMenu()
    }

    @objc func setThemeLight(_ sender: Any? = nil) {
        UserDefaults.standard.set("light", forKey: "DROPDIAL_THEME")
        DropWheelWindowController.shared.reloadTheme()
        rebuildMenu()
    }

    @objc func setThemeDark(_ sender: Any? = nil) {
        UserDefaults.standard.set("dark", forKey: "DROPDIAL_THEME")
        DropWheelWindowController.shared.reloadTheme()
        rebuildMenu()
    }

    @objc func openOutputFolder(_ sender: Any? = nil) {
        if let customOut = UserDefaults.standard.string(forKey: "DROPDIAL_OUTPUT_DIR"),
           !customOut.isEmpty,
           FileManager.default.fileExists(atPath: customOut) {
            NSWorkspace.shared.open(URL(fileURLWithPath: customOut))
        } else {
            let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
            NSWorkspace.shared.open(desktop)
        }
    }

    @objc func aboutTapped(_ sender: Any? = nil) {
        let alert = NSAlert()
        let ver = UpdateService.shared.currentVersion
        alert.messageText = "DropDial \(ver) (macOS Native)"
        alert.informativeText = "Drag. Drop. Convert.\nUniversal offline desktop file conversion, media tools, and file actions.\n\nCopyright © 2026 DropDial. All rights reserved.\nProprietary commercial software.\n\n3 Wheels:\n• ⇧ Shift / F8: Formats Wheel\n• ⌘ Command / F9: Tools Wheel\n• ⌃ Control / F10: Universal File Actions (AirDrop, Float Shelf, Copy, Move, Copy Path, Terminal)\n\nControls:\n• Tab: Cycle Wheels • Esc: Close Wheel • Numbers 1-8: Quick select slice"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc func openNoticesTapped(_ sender: Any? = nil) {
        if let noticesURL = Bundle.main.url(forResource: "THIRD-PARTY-NOTICES", withExtension: "txt") {
            NSWorkspace.shared.open(noticesURL)
            return
        }
        // Fallback: check workspace / project root if running unpackaged
        let fallbackPath = "/Users/nithin/Desktop/lotus/THIRD-PARTY-NOTICES.txt"
        if FileManager.default.fileExists(atPath: fallbackPath) {
            NSWorkspace.shared.open(URL(fileURLWithPath: fallbackPath))
            return
        }
        let alert = NSAlert()
        alert.messageText = "Third-Party Notices"
        alert.informativeText = "DropDial is proprietary commercial software.\nIncorporates third-party components under MIT, Apache 2.0, and BSD licenses.\nSee THIRD-PARTY-NOTICES.txt in the installation directory."
        alert.runModal()
    }

    @objc func quitTapped(_ sender: Any? = nil) {
        NSApp.terminate(nil)
    }
}

extension AppDelegate: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        return true
    }
}

// Main App Launcher
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
