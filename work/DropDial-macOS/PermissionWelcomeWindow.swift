import AppKit
import ApplicationServices

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class PermissionWelcomeWindowController: NSWindowController {
    static let shared = PermissionWelcomeWindowController()

    private var pollTimer: Timer?
    private let statusBox = NSBox()
    private let statusIcon = NSImageView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let actionButton = NSButton()
    private let refreshButton = NSButton()
    private let skipButton = NSButton()
    private var isGranted = false
    private var activeObservers: [NSObjectProtocol] = []

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 530),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "Welcome to DropDial"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.level = .floating

        super.init(window: window)
        setupUI()
        setupNotificationObservers()
    }

    required init?(coder: NSCoder) { fatalError() }

    deinit {
        pollTimer?.invalidate()
        for obs in activeObservers {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    private func setupUI() {
        guard let window = window else { return }

        let visualEffect = NSVisualEffectView(frame: window.contentView!.bounds)
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.material = .popover
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow
        window.contentView?.addSubview(visualEffect)

        let container = FlippedView(frame: visualEffect.bounds)
        container.autoresizingMask = [.width, .height]
        visualEffect.addSubview(container)

        // 1. App Icon Hero (76x76)
        let iconView = NSImageView(frame: NSRect(x: (480 - 76) / 2, y: 26, width: 76, height: 76))
        let resPath = Bundle.main.bundlePath + "/Contents/Resources/"
        if let markImg = NSImage(contentsOfFile: resPath + "dropdial_mark_128.png") ??
                         NSImage(contentsOfFile: resPath + "dropdial.png") ??
                         NSImage(named: "AppIcon") {
            iconView.image = markImg
        }
        container.addSubview(iconView)

        // 2. Title
        let titleLabel = NSTextField(labelWithString: "Welcome to DropDial")
        titleLabel.frame = NSRect(x: 20, y: 110, width: 440, height: 28)
        titleLabel.alignment = .center
        titleLabel.font = NSFont.systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = .labelColor
        container.addSubview(titleLabel)

        // 3. Subtitle
        let subLabel = NSTextField(labelWithString: "Drag. Drop. Convert. • Universal Desktop Actions")
        subLabel.frame = NSRect(x: 20, y: 140, width: 440, height: 18)
        subLabel.alignment = .center
        subLabel.font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        subLabel.textColor = .secondaryLabelColor
        container.addSubview(subLabel)

        // 4. Feature Card Box (424x192)
        let card = NSBox(frame: NSRect(x: 28, y: 168, width: 424, height: 192))
        card.boxType = .custom
        card.cornerRadius = 14
        card.borderWidth = 1.0
        card.borderColor = NSColor.separatorColor.withAlphaComponent(0.4)
        card.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.55)

        let cardContainer = FlippedView(frame: NSRect(x: 16, y: 12, width: 392, height: 168))
        cardContainer.autoresizingMask = [.width, .height]

        func createRow(y: CGFloat, symbol: String, title: String, desc: String) -> NSView {
            let row = FlippedView(frame: NSRect(x: 0, y: y, width: 392, height: 48))

            // Icon Badge
            let badge = NSBox(frame: NSRect(x: 0, y: 4, width: 36, height: 36))
            badge.boxType = .custom
            badge.cornerRadius = 18
            badge.borderWidth = 0
            badge.fillColor = NSColor(srgbRed: 1.0, green: 0.38, blue: 0.03, alpha: 0.12)

            let img = NSImageView(frame: NSRect(x: 8, y: 8, width: 20, height: 20))
            img.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            img.contentTintColor = NSColor(srgbRed: 1.0, green: 0.38, blue: 0.03, alpha: 1.0)
            badge.addSubview(img)
            row.addSubview(badge)

            // Text
            let titleText = NSTextField(labelWithString: title)
            titleText.frame = NSRect(x: 48, y: 4, width: 344, height: 18)
            titleText.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
            titleText.textColor = .labelColor
            row.addSubview(titleText)

            let descText = NSTextField(labelWithString: desc)
            descText.frame = NSRect(x: 48, y: 24, width: 344, height: 20)
            descText.font = NSFont.systemFont(ofSize: 11.5, weight: .regular)
            descText.textColor = .secondaryLabelColor
            row.addSubview(descText)

            return row
        }

        cardContainer.addSubview(createRow(
            y: 4,
            symbol: "circle.grid.cross",
            title: "3 Radial Tool Wheels",
            desc: "Hold ⇧ Shift (Formats), ⌘ Cmd (Tools), or ⌃ Ctrl (Actions)."
        ))

        cardContainer.addSubview(createRow(
            y: 58,
            symbol: "hand.draw.fill",
            title: "Drag & Drop Anywhere",
            desc: "Drag any file to summon the interactive dial directly at your cursor."
        ))

        cardContainer.addSubview(createRow(
            y: 112,
            symbol: "lock.shield.fill",
            title: "Accessibility & File Permissions",
            desc: "Required by macOS to detect modifier keys while dragging files."
        ))

        card.contentView = cardContainer
        container.addSubview(card)

        // 5. Live Status Box (424x34)
        statusBox.frame = NSRect(x: 28, y: 372, width: 424, height: 34)
        statusBox.boxType = .custom
        statusBox.cornerRadius = 8
        statusBox.borderWidth = 1.0

        let statusInner = FlippedView(frame: NSRect(x: 10, y: 0, width: 404, height: 34))
        statusIcon.frame = NSRect(x: 10, y: 8, width: 18, height: 18)
        statusInner.addSubview(statusIcon)

        statusLabel.frame = NSRect(x: 34, y: 8, width: 360, height: 18)
        statusLabel.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        statusInner.addSubview(statusLabel)

        statusBox.contentView = statusInner
        container.addSubview(statusBox)

        // 6. Action Button (Primary)
        actionButton.frame = NSRect(x: 90, y: 418, width: 300, height: 36)
        actionButton.bezelStyle = .rounded
        actionButton.controlSize = .large
        actionButton.target = self
        actionButton.action = #selector(actionButtonTapped)
        container.addSubview(actionButton)

        // 7. Refresh / Re-check Link
        refreshButton.frame = NSRect(x: 120, y: 462, width: 240, height: 20)
        refreshButton.bezelStyle = .inline
        refreshButton.isBordered = false
        refreshButton.title = "↻ Check Permission Status"
        refreshButton.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        refreshButton.contentTintColor = NSColor.linkColor
        refreshButton.target = self
        refreshButton.action = #selector(refreshButtonTapped)
        container.addSubview(refreshButton)

        // 8. Skip Button
        skipButton.frame = NSRect(x: 60, y: 488, width: 360, height: 22)
        skipButton.bezelStyle = .inline
        skipButton.isBordered = false
        skipButton.title = "Skip for Now (Use HotKeys & Menu Bar)"
        skipButton.font = NSFont.systemFont(ofSize: 11.5, weight: .regular)
        skipButton.contentTintColor = .secondaryLabelColor
        skipButton.target = self
        skipButton.action = #selector(skipButtonTapped)
        container.addSubview(skipButton)

        updateStatus()
    }

    private func setupNotificationObservers() {
        let obs1 = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.checkStatusLive()
        }

        let obs2 = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.checkStatusLive()
        }

        activeObservers = [obs1, obs2]
    }

    func show(isFirstLaunch: Bool = false) {
        checkStatusLive()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        startPolling()
    }

    private func isAccessibilityTrusted() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    private func checkStatusLive() {
        let trusted = isAccessibilityTrusted()
        if trusted != self.isGranted {
            self.isGranted = trusted
            updateStatus()

            if trusted {
                NotificationCenter.default.post(name: NSNotification.Name("DropDialAccessibilityGranted"), object: nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                    self?.close()
                    DropWheelWindowController.shared.showWheel()
                }
            }
        }
    }

    private func updateStatus() {
        let trusted = isAccessibilityTrusted()
        self.isGranted = trusted

        if trusted {
            statusBox.fillColor = NSColor.systemGreen.withAlphaComponent(0.12)
            statusBox.borderColor = NSColor.systemGreen.withAlphaComponent(0.4)
            statusIcon.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
            statusIcon.contentTintColor = NSColor(srgbRed: 0.15, green: 0.75, blue: 0.35, alpha: 1.0)
            statusLabel.stringValue = "Accessibility Granted — All features active!"
            statusLabel.textColor = NSColor(srgbRed: 0.15, green: 0.75, blue: 0.35, alpha: 1.0)

            actionButton.title = "✓ Ready to Go! (Open DropDial)"
            actionButton.keyEquivalent = "\r"
            refreshButton.isHidden = true
            skipButton.isHidden = true
        } else {
            statusBox.fillColor = NSColor.systemOrange.withAlphaComponent(0.12)
            statusBox.borderColor = NSColor.systemOrange.withAlphaComponent(0.4)
            statusIcon.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
            statusIcon.contentTintColor = NSColor.systemOrange
            statusLabel.stringValue = "Accessibility Needed: Enable DropDial in Settings"
            statusLabel.textColor = NSColor.systemOrange

            actionButton.title = "Open System Settings & Grant"
            actionButton.keyEquivalent = "\r"
            refreshButton.isHidden = false
            skipButton.isHidden = false
        }
    }

    private func startPolling() {
        pollTimer?.invalidate()
        let timer = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.checkStatusLive()
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    @objc private func actionButtonTapped() {
        let trusted = isAccessibilityTrusted()
        if trusted {
            close()
            DropWheelWindowController.shared.showWheel()
            return
        }

        // 1. Prompt macOS system dialog to register com.dropdial.mac in Accessibility list
        let promptOptions = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(promptOptions)

        // 2. Open System Settings directly to Privacy & Security -> Accessibility
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }

        // 3. Immediately re-check and keep polling
        checkStatusLive()
    }

    @objc private func refreshButtonTapped() {
        checkStatusLive()
        if !isGranted {
            // Flash status to show it checked
            let previous = statusLabel.stringValue
            statusLabel.stringValue = "Checking... Make sure DropDial is ON in Settings"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self = self else { return }
                if !self.isGranted {
                    self.statusLabel.stringValue = previous
                } else {
                    self.updateStatus()
                }
            }
        }
    }

    @objc private func skipButtonTapped() {
        close()
        DropWheelWindowController.shared.showWheel()
    }

    override func close() {
        pollTimer?.invalidate()
        pollTimer = nil
        super.close()
    }
}
