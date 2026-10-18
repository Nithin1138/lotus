import AppKit
import ApplicationServices

final class PermissionWelcomeWindowController: NSWindowController {
    static let shared = PermissionWelcomeWindowController()

    private var pollTimer: Timer?
    private let statusBadge = NSTextField(labelWithString: "")
    private let actionButton = NSButton()
    private let skipButton = NSButton()
    private var isGranted = false

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 440),
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
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        guard let window = window else { return }

        let visualEffect = NSVisualEffectView(frame: window.contentView!.bounds)
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.material = .popover
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow
        window.contentView?.addSubview(visualEffect)

        let container = NSView(frame: visualEffect.bounds)
        container.autoresizingMask = [.width, .height]
        visualEffect.addSubview(container)

        // 1. App Icon Hero (72x72)
        let iconView = NSImageView(frame: NSRect(x: (460 - 72) / 2, y: 340, width: 72, height: 72))
        let resPath = Bundle.main.bundlePath + "/Contents/Resources/"
        if let markImg = NSImage(contentsOfFile: resPath + "dropdial_mark_128.png") ?? NSImage(contentsOfFile: resPath + "dropdial.png") ?? NSImage(named: "AppIcon") {
            iconView.image = markImg
        }
        container.addSubview(iconView)

        // 2. Title
        let titleLabel = NSTextField(labelWithString: "Welcome to DropDial")
        titleLabel.frame = NSRect(x: 20, y: 300, width: 420, height: 28)
        titleLabel.alignment = .center
        titleLabel.font = NSFont.systemFont(ofSize: 20, weight: .bold)
        container.addSubview(titleLabel)

        // 3. Subtitle
        let subLabel = NSTextField(labelWithString: "Drag. Drop. Convert. • Universal Desktop Actions")
        subLabel.frame = NSRect(x: 20, y: 278, width: 420, height: 18)
        subLabel.alignment = .center
        subLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        subLabel.textColor = .secondaryLabelColor
        container.addSubview(subLabel)

        // 4. Feature Card Box
        let card = NSBox(frame: NSRect(x: 28, y: 125, width: 404, height: 140))
        card.boxType = .custom
        card.cornerRadius = 12
        card.borderWidth = 1.0
        card.borderColor = NSColor.separatorColor
        card.fillColor = NSColor.controlBackgroundColor.withAlphaComponent(0.4)

        let cardContent = NSStackView(frame: NSRect(x: 16, y: 10, width: 372, height: 120))
        cardContent.orientation = .vertical
        cardContent.alignment = .leading
        cardContent.spacing = 8

        func makeRow(icon: String, title: String, desc: String) -> NSView {
            let row = NSView(frame: NSRect(x: 0, y: 0, width: 372, height: 30))
            let img = NSImageView(frame: NSRect(x: 0, y: 6, width: 18, height: 18))
            img.image = NSImage(systemSymbolName: icon, accessibilityDescription: nil)
            img.contentTintColor = NSColor(srgbRed: 1.0, green: 0.45, blue: 0.08, alpha: 1.0)
            row.addSubview(img)

            let txt = NSTextField(labelWithString: "")
            txt.frame = NSRect(x: 26, y: 0, width: 346, height: 30)
            let attr = NSMutableAttributedString(string: "\(title) — ", attributes: [.font: NSFont.systemFont(ofSize: 11.5, weight: .bold), .foregroundColor: NSColor.labelColor])
            attr.append(NSAttributedString(string: desc, attributes: [.font: NSFont.systemFont(ofSize: 11.5, weight: .regular), .foregroundColor: NSColor.secondaryLabelColor]))
            txt.attributedStringValue = attr
            txt.maximumNumberOfLines = 2
            row.addSubview(txt)
            return row
        }

        cardContent.addArrangedSubview(makeRow(icon: "circle.circle", title: "3 Radial Dials", desc: "Hold ⇧ Shift (Convert), ⌘ Cmd (Tools), or ⌃ Ctrl (Actions)."))
        cardContent.addArrangedSubview(makeRow(icon: "hand.draw", title: "Drag & Drop", desc: "Drag any file anywhere to summon the dial directly at your cursor."))
        cardContent.addArrangedSubview(makeRow(icon: "lock.shield", title: "Accessibility", desc: "Required by macOS to detect modifier keys while dragging from Finder."))

        card.addSubview(cardContent)
        container.addSubview(card)

        // 5. Live Status Badge
        statusBadge.frame = NSRect(x: 28, y: 88, width: 404, height: 22)
        statusBadge.alignment = .center
        statusBadge.font = NSFont.systemFont(ofSize: 11.5, weight: .semibold)
        container.addSubview(statusBadge)

        // 6. Action Button (Primary)
        actionButton.frame = NSRect(x: 100, y: 44, width: 260, height: 34)
        actionButton.bezelStyle = .rounded
        actionButton.controlSize = .large
        actionButton.target = self
        actionButton.action = #selector(actionButtonTapped)
        container.addSubview(actionButton)

        // 7. Skip Button
        skipButton.frame = NSRect(x: 140, y: 14, width: 180, height: 24)
        skipButton.bezelStyle = .inline
        skipButton.isBordered = false
        skipButton.title = "Skip for Now (Use HotKeys & Menu Bar)"
        skipButton.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        skipButton.contentTintColor = .secondaryLabelColor
        skipButton.target = self
        skipButton.action = #selector(skipButtonTapped)
        container.addSubview(skipButton)

        updateStatus()
    }

    func show(isFirstLaunch: Bool = false) {
        updateStatus()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        startPolling()
    }

    private func updateStatus() {
        let trusted = AXIsProcessTrusted()
        self.isGranted = trusted

        if trusted {
            statusBadge.stringValue = "✓ Accessibility Granted — All features active!"
            statusBadge.textColor = NSColor(srgbRed: 0.18, green: 0.75, blue: 0.35, alpha: 1.0)
            actionButton.title = "✓ Ready to Go!"
            actionButton.keyEquivalent = "\r"
            skipButton.isHidden = true
        } else {
            statusBadge.stringValue = "⚠️ Accessibility Permission Needed for Drag Shortcuts"
            statusBadge.textColor = NSColor(srgbRed: 1.0, green: 0.50, blue: 0.10, alpha: 1.0)
            actionButton.title = "Open System Settings & Grant"
            actionButton.keyEquivalent = "\r"
            skipButton.isHidden = false
        }
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] timer in
            guard let self = self else { return }
            let trusted = AXIsProcessTrusted()
            if trusted != self.isGranted {
                self.updateStatus()
                if trusted {
                    NotificationCenter.default.post(name: NSNotification.Name("DropDialAccessibilityGranted"), object: nil)
                    // Auto close window after brief confirmation
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                        self?.close()
                    }
                }
            }
        }
    }

    @objc private func actionButtonTapped() {
        if AXIsProcessTrusted() {
            close()
            return
        }

        // 1. Prompt macOS system dialog
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)

        // 2. Open System Settings directly to Privacy & Security -> Accessibility
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func skipButtonTapped() {
        close()
    }

    override func close() {
        pollTimer?.invalidate()
        pollTimer = nil
        super.close()
    }
}
