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
    private let statusTitleLabel = NSTextField(labelWithString: "")
    private let statusSubtitleLabel = NSTextField(labelWithString: "")
    private let pillBox = NSBox()
    private let pillLabel = NSTextField(labelWithString: "")
    private let actionButton = NSButton()
    private let refreshButton = NSButton()
    private let skipButton = NSButton()
    private var isGranted = false
    private var activeObservers: [NSObjectProtocol] = []

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 490, height: 540),
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
        visualEffect.material = .underWindowBackground
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow
        window.contentView?.addSubview(visualEffect)

        let container = FlippedView(frame: visualEffect.bounds)
        container.autoresizingMask = [.width, .height]
        visualEffect.addSubview(container)

        // 1. App Icon Hero (72x72)
        let iconView = NSImageView(frame: NSRect(x: (490 - 72) / 2, y: 22, width: 72, height: 72))
        let resPath = Bundle.main.bundlePath + "/Contents/Resources/"
        if let markImg = NSImage(contentsOfFile: resPath + "dropdial_mark_128.png") ??
                         NSImage(contentsOfFile: resPath + "dropdial.png") ??
                         NSImage(named: "AppIcon") {
            iconView.image = markImg
        }
        container.addSubview(iconView)

        // 2. Title
        let titleLabel = NSTextField(labelWithString: "Welcome to DropDial")
        titleLabel.frame = NSRect(x: 20, y: 98, width: 450, height: 26)
        titleLabel.alignment = .center
        titleLabel.font = NSFont.systemFont(ofSize: 22, weight: .bold)
        titleLabel.textColor = .labelColor
        container.addSubview(titleLabel)

        // 3. Subtitle
        let subLabel = NSTextField(labelWithString: "Instant File Conversions & Desktop Actions at Your Cursor")
        subLabel.frame = NSRect(x: 20, y: 126, width: 450, height: 18)
        subLabel.alignment = .center
        subLabel.font = NSFont.systemFont(ofSize: 12.5, weight: .medium)
        subLabel.textColor = .secondaryLabelColor
        container.addSubview(subLabel)

        // 4. Feature Card Box (440x198)
        let card = NSBox(frame: NSRect(x: 25, y: 154, width: 440, height: 198))
        card.boxType = .custom
        card.cornerRadius = 14
        card.borderWidth = 1.0
        card.borderColor = NSColor.separatorColor.withAlphaComponent(0.25)
        card.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.55)

        let cardContainer = FlippedView(frame: NSRect(x: 16, y: 8, width: 408, height: 182))
        cardContainer.autoresizingMask = [.width, .height]

        func createRow(y: CGFloat, symbol: String, badgeColor: NSColor, title: String, desc: String, trailingView: NSView? = nil) -> NSView {
            let row = FlippedView(frame: NSRect(x: 0, y: y, width: 408, height: 56))

            // Icon Badge (38x38 circle)
            let badge = NSBox(frame: NSRect(x: 0, y: 6, width: 38, height: 38))
            badge.boxType = .custom
            badge.cornerRadius = 19
            badge.borderWidth = 0
            badge.fillColor = badgeColor.withAlphaComponent(0.14)

            let img = NSImageView(frame: NSRect(x: 9, y: 9, width: 20, height: 20))
            img.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            img.contentTintColor = badgeColor
            badge.addSubview(img)
            row.addSubview(badge)

            // Text column
            let textWidth: CGFloat = trailingView != nil ? 272 : 354
            let titleText = NSTextField(labelWithString: title)
            titleText.frame = NSRect(x: 50, y: 4, width: textWidth, height: 18)
            titleText.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
            titleText.textColor = .labelColor
            row.addSubview(titleText)

            let descText = NSTextField(labelWithString: desc)
            descText.frame = NSRect(x: 50, y: 22, width: textWidth, height: 32)
            descText.font = NSFont.systemFont(ofSize: 11.5, weight: .regular)
            descText.textColor = .secondaryLabelColor
            descText.lineBreakMode = .byWordWrapping
            descText.maximumNumberOfLines = 2
            row.addSubview(descText)

            if let trailingView = trailingView {
                row.addSubview(trailingView)
            }

            return row
        }

        // Row 1: 3 Radial Wheels
        cardContainer.addSubview(createRow(
            y: 2,
            symbol: "circle.grid.cross.fill",
            badgeColor: NSColor.systemIndigo,
            title: "3 Radial Tool Wheels",
            desc: "Hold ⇧ Shift (Formats), ⌘ Cmd (Tools), or ⌃ Ctrl (Actions)."
        ))

        // Row 2: Drag & Drop Anywhere
        cardContainer.addSubview(createRow(
            y: 60,
            symbol: "hand.draw.fill",
            badgeColor: NSColor.systemOrange,
            title: "Drag & Drop Anywhere",
            desc: "Drag any file to summon the interactive dial directly at your cursor."
        ))

        // Row 3: Accessibility & Global Drag Detection with Live Pill
        pillBox.frame = NSRect(x: 322, y: 16, width: 80, height: 22)
        pillBox.boxType = .custom
        pillBox.cornerRadius = 11
        pillBox.borderWidth = 1.0

        pillLabel.frame = NSRect(x: 0, y: 3, width: 80, height: 16)
        pillLabel.alignment = .center
        pillLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        pillBox.contentView = pillLabel

        cardContainer.addSubview(createRow(
            y: 118,
            symbol: "lock.shield.fill",
            badgeColor: NSColor.systemTeal,
            title: "Accessibility Permission",
            desc: "Required by macOS to detect modifier keys while dragging files.",
            trailingView: pillBox
        ))

        card.contentView = cardContainer
        container.addSubview(card)

        // 5. Live Status Card (440x56)
        statusBox.frame = NSRect(x: 25, y: 364, width: 440, height: 56)
        statusBox.boxType = .custom
        statusBox.cornerRadius = 12
        statusBox.borderWidth = 1.0

        let statusInner = FlippedView(frame: NSRect(x: 14, y: 0, width: 412, height: 56))

        statusIcon.frame = NSRect(x: 2, y: 17, width: 22, height: 22)
        statusInner.addSubview(statusIcon)

        statusTitleLabel.frame = NSRect(x: 36, y: 9, width: 376, height: 18)
        statusTitleLabel.font = NSFont.systemFont(ofSize: 12.5, weight: .semibold)
        statusInner.addSubview(statusTitleLabel)

        statusSubtitleLabel.frame = NSRect(x: 36, y: 29, width: 376, height: 18)
        statusSubtitleLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        statusInner.addSubview(statusSubtitleLabel)

        statusBox.contentView = statusInner
        container.addSubview(statusBox)

        // 6. Action Button (Primary)
        actionButton.frame = NSRect(x: 45, y: 432, width: 400, height: 38)
        actionButton.bezelStyle = .rounded
        actionButton.controlSize = .large
        actionButton.target = self
        actionButton.action = #selector(actionButtonTapped)
        container.addSubview(actionButton)

        // 7. Helper Row (Check status & Skip for now)
        let bottomRow = FlippedView(frame: NSRect(x: 45, y: 478, width: 400, height: 26))

        refreshButton.frame = NSRect(x: 10, y: 2, width: 170, height: 22)
        refreshButton.bezelStyle = .inline
        refreshButton.isBordered = false
        refreshButton.title = "↻ Check Permission"
        refreshButton.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        refreshButton.contentTintColor = NSColor.linkColor
        refreshButton.alignment = .left
        refreshButton.target = self
        refreshButton.action = #selector(refreshButtonTapped)
        bottomRow.addSubview(refreshButton)

        skipButton.frame = NSRect(x: 190, y: 2, width: 200, height: 22)
        skipButton.bezelStyle = .inline
        skipButton.isBordered = false
        skipButton.title = "Skip for Now (Use Hotkeys)"
        skipButton.font = NSFont.systemFont(ofSize: 11.5, weight: .regular)
        skipButton.contentTintColor = .secondaryLabelColor
        skipButton.alignment = .right
        skipButton.target = self
        skipButton.action = #selector(skipButtonTapped)
        bottomRow.addSubview(skipButton)

        container.addSubview(bottomRow)

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

    private func updateStatus(forceNeeded: Bool = false) {
        let trusted = forceNeeded ? false : (CommandLine.arguments.contains("--show-permission-needed") ? false : isAccessibilityTrusted())
        self.isGranted = trusted

        if trusted {
            statusBox.fillColor = NSColor.systemGreen.withAlphaComponent(0.09)
            statusBox.borderColor = NSColor.systemGreen.withAlphaComponent(0.35)
            statusIcon.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)
            statusIcon.contentTintColor = NSColor(srgbRed: 0.15, green: 0.75, blue: 0.35, alpha: 1.0)
            statusTitleLabel.stringValue = "Accessibility Granted — Everything is Active!"
            statusTitleLabel.textColor = NSColor(srgbRed: 0.15, green: 0.75, blue: 0.35, alpha: 1.0)
            statusSubtitleLabel.stringValue = "DropDial is fully authorized. Drag any file or use hotkeys."
            statusSubtitleLabel.textColor = .secondaryLabelColor

            pillBox.fillColor = NSColor.systemGreen.withAlphaComponent(0.15)
            pillBox.borderColor = NSColor.systemGreen.withAlphaComponent(0.4)
            pillLabel.stringValue = "✓ Active"
            pillLabel.textColor = NSColor(srgbRed: 0.15, green: 0.75, blue: 0.35, alpha: 1.0)

            actionButton.title = "✓ Ready to Go! (Open DropDial)"
            actionButton.keyEquivalent = "\r"
            refreshButton.isHidden = true
            skipButton.isHidden = true
        } else {
            statusBox.fillColor = NSColor.systemOrange.withAlphaComponent(0.08)
            statusBox.borderColor = NSColor.systemOrange.withAlphaComponent(0.35)
            statusIcon.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)
            statusIcon.contentTintColor = NSColor.systemOrange
            statusTitleLabel.stringValue = "Accessibility Permission Required"
            statusTitleLabel.textColor = NSColor.systemOrange
            statusSubtitleLabel.stringValue = "Turn ON DropDial in System Settings → Accessibility"
            statusSubtitleLabel.textColor = .secondaryLabelColor

            pillBox.fillColor = NSColor.systemOrange.withAlphaComponent(0.12)
            pillBox.borderColor = NSColor.systemOrange.withAlphaComponent(0.35)
            pillLabel.stringValue = "Required"
            pillLabel.textColor = NSColor.systemOrange

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
            let prevTitle = statusTitleLabel.stringValue
            let prevSubtitle = statusSubtitleLabel.stringValue
            statusTitleLabel.stringValue = "Checking Settings…"
            statusSubtitleLabel.stringValue = "Make sure the toggle next to DropDial is turned ON."
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self = self else { return }
                if !self.isGranted {
                    self.statusTitleLabel.stringValue = prevTitle
                    self.statusSubtitleLabel.stringValue = prevSubtitle
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
