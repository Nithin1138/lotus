import AppKit
import Carbon

final class HotKeyManager {
    static let shared = HotKeyManager()
    private var hotKeys: [UInt32: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?

    func setup() {
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

        // ID 4: Cmd + Shift + L (keyCode 37) -> Toggle Lotus Wheel
        register(id: 4, keyCode: UInt32(kVK_ANSI_L), modifiers: UInt32(cmdKey | shiftKey))

        // ID 5: F10 (keyCode 109) -> Toggle Actions Wheel
        register(id: 5, keyCode: UInt32(kVK_F10), modifiers: 0)
    }

    private func register(id: UInt32, keyCode: UInt32, modifiers: UInt32) {
        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x4C545553), id: id) // 'LTUS'
        let err = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &hotKeyRef)
        if err == noErr, let ref = hotKeyRef {
            hotKeys[id] = ref
        }
    }

    private func handleHotKey(id: UInt32) {
        DispatchQueue.main.async {
            switch id {
            case 1:
                DropWheelWindowController.shared.toggleWheel(mode: .conversions)
            case 2:
                DropWheelWindowController.shared.toggleWheel(mode: .tools)
            case 5:
                DropWheelWindowController.shared.toggleWheel(mode: .actions)
            case 3, 4:
                DropWheelWindowController.shared.toggleWheel(mode: nil)
            default:
                break
            }
        }
    }
}

final class StatusBarDropView: NSView {
    var onClick: (() -> Void)?
    var onRightClick: (() -> Void)?
    var onDrop: (([String]) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            onRightClick?()
            return
        }
        onClick?()
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] else {
            return false
        }
        let paths = items.filter { $0.isFileURL }.map { $0.path }
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
    private var globalFlagsMonitor: Any?
    private var globalDragMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupShortcuts()

        let args = Array(CommandLine.arguments.dropFirst())
        let files = args.filter { FileManager.default.fileExists(atPath: $0) && !$0.hasPrefix("-") }
        if !files.isEmpty {
            DropWheelWindowController.shared.loadFiles(files)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                DropWheelWindowController.shared.showWheel()
            }
        }
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        DropWheelWindowController.shared.loadFiles(filenames)
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: 28)

        if let button = statusItem.button {
            dropView = StatusBarDropView(frame: button.bounds)
            dropView.autoresizingMask = [.width, .height]
            dropView.onClick = { [weak self] in
                self?.statusItemClicked()
            }
            dropView.onRightClick = { [weak self] in
                self?.showContextMenu()
            }
            dropView.onDrop = { paths in
                DropWheelWindowController.shared.loadFiles(paths)
            }
            button.addSubview(dropView)

            if let iconImage = NSImage(named: "AppIcon") ?? NSImage(contentsOfFile: Bundle.main.bundlePath + "/Contents/Resources/AppIcon.icns") {
                iconImage.size = NSSize(width: 18, height: 18)
                button.image = iconImage
            } else {
                let symbol = NSImage(systemSymbolName: "circle.circle.fill", accessibilityDescription: "Lotus")
                button.image = symbol
            }
            button.imagePosition = .imageOnly
        }

        rebuildMenu()
    }

    private func statusItemClicked() {
        DropWheelWindowController.shared.toggleWheel()
    }

    private func showContextMenu() {
        rebuildMenu()
        statusItem.menu?.popUp(positioning: nil, at: NSPoint(x: 0, y: statusItem.button?.bounds.height ?? 22), in: statusItem.button)
    }

    private func setupShortcuts() {
        // 1. Carbon Global HotKeys (No Accessibility permissions required!)
        HotKeyManager.shared.setup()

        // 2. Global Monitor for Key Down (fallback when Accessibility is active)
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            self?.handleKeyEvent(event)
        }

        // 3. Local Monitor for Key Down (when Lotus has focus)
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if self?.handleKeyEvent(event) == true {
                return nil
            }
            return event
        }

        // 4. Flags monitor (Shift, Command, or Control while dragging)
        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged]) { event in
            let isMouseDown = (NSEvent.pressedMouseButtons & 1) != 0
            guard isMouseDown else { return }

            if event.modifierFlags.contains(.control) {
                DropWheelWindowController.shared.showAtCursor(mode: .actions)
            } else if event.modifierFlags.contains(.command) {
                DropWheelWindowController.shared.showAtCursor(mode: .tools)
            } else if event.modifierFlags.contains(.shift) {
                DropWheelWindowController.shared.showAtCursor(mode: .conversions)
            }
        }

        // 5. Drag monitor
        globalDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { event in
            if event.modifierFlags.contains(.control) {
                DropWheelWindowController.shared.showAtCursor(mode: .actions)
            } else if event.modifierFlags.contains(.command) {
                DropWheelWindowController.shared.showAtCursor(mode: .tools)
            } else if event.modifierFlags.contains(.shift) {
                DropWheelWindowController.shared.showAtCursor(mode: .conversions)
            }
        }
    }

    @discardableResult
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        let code = event.keyCode

        // F8 (keyCode 100) -> Show Formats Wheel
        if code == 100 {
            DropWheelWindowController.shared.toggleWheel(mode: .conversions)
            return true
        }

        // F9 (keyCode 101) -> Show Tools Wheel
        if code == 101 {
            DropWheelWindowController.shared.toggleWheel(mode: .tools)
            return true
        }

        // F10 (keyCode 109) -> Show Actions Wheel
        if code == 109 {
            DropWheelWindowController.shared.toggleWheel(mode: .actions)
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

        // Cmd + Shift + L or Cmd + Shift + D -> Toggle Wheel
        if event.modifierFlags.contains([.command, .shift]) {
            if let chars = event.charactersIgnoringModifiers?.lowercased(), chars == "l" || chars == "d" {
                DropWheelWindowController.shared.toggleWheel()
                return true
            }
        }

        // Option + Space -> Toggle Wheel
        if event.modifierFlags.contains(.option) && code == 49 {
            DropWheelWindowController.shared.toggleWheel()
            return true
        }

        return false
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        // 1. Formats Wheel (F8 / ⇧)
        let f8Item = NSMenuItem(title: "Formats Wheel (F8 / ⇧)", action: #selector(showFormatsWheel(_:)), keyEquivalent: "")
        f8Item.target = self
        f8Item.isEnabled = true
        f8Item.image = NSImage(systemSymbolName: "circle.grid.cross", accessibilityDescription: nil)
        menu.addItem(f8Item)

        // 2. Tools Wheel (F9 / ⌘)
        let f9Item = NSMenuItem(title: "Tools Wheel (F9 / ⌘)", action: #selector(showToolsWheel(_:)), keyEquivalent: "")
        f9Item.target = self
        f9Item.isEnabled = true
        f9Item.image = NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: nil)
        menu.addItem(f9Item)

        // 3. Actions Wheel (F10 / ⌃)
        let f10Item = NSMenuItem(title: "File Actions Wheel (F10 / ⌃)", action: #selector(showActionsWheel(_:)), keyEquivalent: "")
        f10Item.target = self
        f10Item.isEnabled = true
        f10Item.image = NSImage(systemSymbolName: "hand.tap", accessibilityDescription: nil)
        menu.addItem(f10Item)

        // 4. Floating Shelf (Show)
        let shelfItem = NSMenuItem(title: "Floating Shelf", action: #selector(showFloatingShelf(_:)), keyEquivalent: "")
        shelfItem.target = self
        shelfItem.isEnabled = true
        shelfItem.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: nil)
        menu.addItem(shelfItem)

        menu.addItem(NSMenuItem.separator())

        // 5. Quick Toggle (⌥Space)
        let toggleItem = NSMenuItem(title: "Quick Toggle Wheel (⌥Space / ⌘⇧L)", action: #selector(toggleWheelTapped(_:)), keyEquivalent: "")
        toggleItem.target = self
        toggleItem.isEnabled = true
        toggleItem.image = NSImage(systemSymbolName: "command", accessibilityDescription: nil)
        menu.addItem(toggleItem)

        // 6. Select files (⌘O)
        let openItem = NSMenuItem(title: "Select Files to Convert...", action: #selector(selectFilesTapped(_:)), keyEquivalent: "o")
        openItem.target = self
        openItem.isEnabled = true
        openItem.image = NSImage(systemSymbolName: "plus.rectangle.on.rectangle", accessibilityDescription: nil)
        menu.addItem(openItem)

        menu.addItem(NSMenuItem.separator())

        // 7. Theme Submenu (System / Light / Dark)
        let currentTheme = UserDefaults.standard.string(forKey: "LOTUS_THEME") ?? "system"
        let themeMenu = NSMenu()
        themeMenu.autoenablesItems = false

        let sysItem = NSMenuItem(title: "Follow System (Default)", action: #selector(setThemeSystem(_:)), keyEquivalent: "")
        sysItem.target = self
        sysItem.isEnabled = true
        sysItem.state = (currentTheme == "system") ? .on : .off
        themeMenu.addItem(sysItem)

        let lightItem = NSMenuItem(title: "Light Theme", action: #selector(setThemeLight(_:)), keyEquivalent: "")
        lightItem.target = self
        lightItem.isEnabled = true
        lightItem.state = (currentTheme == "light") ? .on : .off
        themeMenu.addItem(lightItem)

        let darkItem = NSMenuItem(title: "Dark Theme", action: #selector(setThemeDark(_:)), keyEquivalent: "")
        darkItem.target = self
        darkItem.isEnabled = true
        darkItem.state = (currentTheme == "dark") ? .on : .off
        themeMenu.addItem(darkItem)

        let themeMenuItem = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
        themeMenuItem.submenu = themeMenu
        themeMenuItem.isEnabled = true
        themeMenuItem.image = NSImage(systemSymbolName: "circle.lefthalf.filled", accessibilityDescription: nil)
        menu.addItem(themeMenuItem)

        // Sound Effects toggle
        let soundItem = NSMenuItem(title: "Sound Effects", action: #selector(toggleSoundEffects(_:)), keyEquivalent: "")
        soundItem.target = self
        soundItem.isEnabled = true
        soundItem.state = SoundManager.isSoundEnabled ? .on : .off
        soundItem.image = NSImage(systemSymbolName: "speaker.wave.2", accessibilityDescription: nil)
        menu.addItem(soundItem)

        // 8. Output Folder menu
        let currentOut = UserDefaults.standard.string(forKey: "LOTUS_OUTPUT_DIR") ?? ""
        let outMenu = NSMenu()
        outMenu.autoenablesItems = false

        let sameItem = NSMenuItem(title: "Same as Source File (Default)", action: #selector(setOutputSame(_:)), keyEquivalent: "")
        sameItem.target = self
        sameItem.isEnabled = true
        sameItem.state = currentOut.isEmpty ? .on : .off
        outMenu.addItem(sameItem)

        let customItem = NSMenuItem(title: "Custom Folder...", action: #selector(chooseOutputFolder(_:)), keyEquivalent: "")
        customItem.target = self
        customItem.isEnabled = true
        customItem.state = currentOut.isEmpty ? .off : .on
        outMenu.addItem(customItem)

        outMenu.addItem(NSMenuItem.separator())
        let openFolderItem = NSMenuItem(title: "Open Output Folder in Finder", action: #selector(openOutputFolder(_:)), keyEquivalent: "")
        openFolderItem.target = self
        openFolderItem.isEnabled = true
        outMenu.addItem(openFolderItem)

        let outMenuItem = NSMenuItem(title: "Output Folder", action: nil, keyEquivalent: "")
        outMenuItem.submenu = outMenu
        outMenuItem.isEnabled = true
        outMenuItem.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
        menu.addItem(outMenuItem)

        menu.addItem(NSMenuItem.separator())

        // 8. About
        let aboutItem = NSMenuItem(title: "About Lotus", action: #selector(aboutTapped(_:)), keyEquivalent: "")
        aboutItem.target = self
        aboutItem.isEnabled = true
        menu.addItem(aboutItem)

        // 9. Quit
        let quitItem = NSMenuItem(title: "Quit Lotus", action: #selector(quitTapped(_:)), keyEquivalent: "q")
        quitItem.target = self
        quitItem.isEnabled = true
        menu.addItem(quitItem)

        statusItem.menu = menu
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
        UserDefaults.standard.removeObject(forKey: "LOTUS_OUTPUT_DIR")
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
            UserDefaults.standard.set(url.path, forKey: "LOTUS_OUTPUT_DIR")
            rebuildMenu()
        }
    }

    @objc func setThemeSystem(_ sender: Any? = nil) {
        UserDefaults.standard.set("system", forKey: "LOTUS_THEME")
        DropWheelWindowController.shared.reloadTheme()
        rebuildMenu()
    }

    @objc func setThemeLight(_ sender: Any? = nil) {
        UserDefaults.standard.set("light", forKey: "LOTUS_THEME")
        DropWheelWindowController.shared.reloadTheme()
        rebuildMenu()
    }

    @objc func setThemeDark(_ sender: Any? = nil) {
        UserDefaults.standard.set("dark", forKey: "LOTUS_THEME")
        DropWheelWindowController.shared.reloadTheme()
        rebuildMenu()
    }

    @objc func toggleSoundEffects(_ sender: Any? = nil) {
        SoundManager.isSoundEnabled.toggle()
        rebuildMenu()
    }

    @objc func openOutputFolder(_ sender: Any? = nil) {
        if let customOut = UserDefaults.standard.string(forKey: "LOTUS_OUTPUT_DIR"),
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
        alert.messageText = "Lotus 1.0.0 (macOS Native)"
        alert.informativeText = "Drag. Drop. Convert.\nUniversal desktop file conversion, media tools, and file actions.\nRunning natively on macOS with Python and Apple Vision OCR.\n\n3 Wheels:\n• ⇧ Shift / F8: Formats Wheel\n• ⌘ Command / F9: Tools Wheel\n• ⌃ Control / F10: Universal File Actions (AirDrop, Float Shelf, Copy, Move, Copy Path, Terminal)\n\nControls:\n• Tab: Cycle Wheels\n• Esc: Close Wheel\n• Numbers 1-8: Quick select slice\n• Audio Tick feedback on hover"
        alert.alertStyle = .informational
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
