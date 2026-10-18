import AppKit

final class JobCardView: NSView {
    let job: ConversionJob
    var process: Process?
    var isPaused = false

    private let effectView = NSVisualEffectView()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let progressIndicator = NSProgressIndicator()
    private let pauseButton = NSButton()
    private let cancelButton = NSButton()
    private let revealButton = NSButton()
    private var lastResult: BatchResult?

    var onDismiss: (() -> Void)?

    override var intrinsicContentSize: NSSize {
        return NSSize(width: 336, height: 86)
    }

    init(job: ConversionJob) {
        self.job = job
        super.init(frame: NSRect(x: 0, y: 0, width: 336, height: 86))
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 336).isActive = true
        heightAnchor.constraint(equalToConstant: 86).isActive = true

        // 1. Frosted Glass Background
        effectView.frame = NSRect(x: 0, y: 0, width: 336, height: 86)
        effectView.autoresizingMask = [.width, .height]
        effectView.material = .hudWindow
        effectView.blendingMode = .withinWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 14
        effectView.layer?.masksToBounds = true
        effectView.layer?.borderColor = NSColor(white: 1.0, alpha: 0.2).cgColor
        effectView.layer?.borderWidth = 1.0
        addSubview(effectView)

        // Subtle Card Shadow
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.35
        layer?.shadowOffset = CGSize(width: 0, height: -3)
        layer?.shadowRadius = 8

        // 2. Icon
        iconView.frame = NSRect(x: 14, y: 40, width: 32, height: 32)
        if let firstPath = job.Paths.first {
            iconView.image = NSWorkspace.shared.icon(forFile: firstPath)
        } else {
            iconView.image = NSImage(systemSymbolName: "doc", accessibilityDescription: nil)
        }
        addSubview(iconView)

        // 3. Title Label (High-contrast white)
        let fileName = URL(fileURLWithPath: job.Paths.first ?? "").lastPathComponent
        let countSuffix = job.Paths.count > 1 ? " (+\(job.Paths.count - 1))" : ""
        titleLabel.frame = NSRect(x: 54, y: 52, width: 218, height: 18)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.stringValue = fileName + countSuffix
        titleLabel.lineBreakMode = .byTruncatingMiddle
        addSubview(titleLabel)

        // 4. Status Label
        statusLabel.frame = NSRect(x: 54, y: 34, width: 218, height: 16)
        statusLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        statusLabel.textColor = NSColor(white: 0.85, alpha: 1.0)
        let actionName = job.Action.hasPrefix("convert:") ? "Converting to \(job.Action.dropFirst(8).uppercased())..." : "Processing..."
        statusLabel.stringValue = actionName
        addSubview(statusLabel)

        // 5. Progress Indicator
        progressIndicator.frame = NSRect(x: 14, y: 16, width: 308, height: 6)
        progressIndicator.isIndeterminate = false
        progressIndicator.minValue = 0
        progressIndicator.maxValue = Double(job.Paths.count)
        progressIndicator.doubleValue = 0
        progressIndicator.style = .bar
        addSubview(progressIndicator)

        // 6. Action Buttons
        // Cancel Button
        cancelButton.frame = NSRect(x: 300, y: 48, width: 26, height: 26)
        cancelButton.bezelStyle = .regularSquare
        cancelButton.isBordered = false
        cancelButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Cancel")
        cancelButton.imageScaling = .scaleProportionallyUpOrDown
        cancelButton.contentTintColor = NSColor(white: 0.85, alpha: 1.0)
        cancelButton.target = self
        cancelButton.action = #selector(cancelTapped)
        addSubview(cancelButton)

        // Pause Button
        pauseButton.frame = NSRect(x: 270, y: 48, width: 26, height: 26)
        pauseButton.bezelStyle = .regularSquare
        pauseButton.isBordered = false
        pauseButton.image = NSImage(systemSymbolName: "pause.circle.fill", accessibilityDescription: "Pause")
        pauseButton.imageScaling = .scaleProportionallyUpOrDown
        pauseButton.contentTintColor = NSColor(white: 0.85, alpha: 1.0)
        pauseButton.target = self
        pauseButton.action = #selector(pauseTapped)
        addSubview(pauseButton)

        // Reveal Button (Shown on completion)
        revealButton.frame = NSRect(x: 198, y: 10, width: 124, height: 22)
        revealButton.bezelStyle = .rounded
        revealButton.title = "Show in Finder"
        revealButton.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        revealButton.target = self
        revealButton.action = #selector(revealTapped)
        revealButton.isHidden = true
        addSubview(revealButton)
    }

    func updateProgress(_ progress: JobProgress) {
        if let processed = progress.Processed {
            progressIndicator.doubleValue = Double(processed)
        }
        if let current = progress.Current {
            statusLabel.stringValue = "Processing: \(current)"
        }
    }

    func markCompleted(result: BatchResult) {
        lastResult = result
        pauseButton.isHidden = true
        progressIndicator.doubleValue = progressIndicator.maxValue
        progressIndicator.isHidden = true

        if let firstOut = result.Files.first?.Output, !firstOut.isEmpty {
            let outUrl = URL(fileURLWithPath: firstOut)
            let outName = outUrl.lastPathComponent
            let folderName = outUrl.deletingLastPathComponent().lastPathComponent
            titleLabel.stringValue = outName
            statusLabel.stringValue = "Saved in \(folderName)"
            statusLabel.textColor = NSColor(srgbRed: 0.25, green: 0.85, blue: 0.45, alpha: 1.0)
            revealButton.isHidden = false

            // Automatically reveal and highlight the converted file in Finder!
            NSWorkspace.shared.activateFileViewerSelecting([outUrl])
        } else {
            statusLabel.stringValue = "Completed"
            statusLabel.textColor = NSColor(srgbRed: 0.25, green: 0.85, blue: 0.45, alpha: 1.0)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) { [weak self] in
            self?.dismiss()
        }
    }

    func markFailed(error: Error) {
        pauseButton.isHidden = true
        progressIndicator.isHidden = true
        statusLabel.stringValue = error.localizedDescription
        statusLabel.textColor = NSColor(srgbRed: 1.0, green: 0.35, blue: 0.35, alpha: 1.0)

        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) { [weak self] in
            self?.dismiss()
        }
    }

    @objc private func cancelTapped() {
        process?.terminate()
        dismiss()
    }

    @objc private func pauseTapped() {
        guard let pid = process?.processIdentifier else { return }
        if isPaused {
            kill(pid, SIGCONT)
            isPaused = false
            pauseButton.image = NSImage(systemSymbolName: "pause.circle.fill", accessibilityDescription: "Pause")
            statusLabel.stringValue = "Processing..."
        } else {
            kill(pid, SIGSTOP)
            isPaused = true
            pauseButton.image = NSImage(systemSymbolName: "play.circle.fill", accessibilityDescription: "Resume")
            statusLabel.stringValue = "Paused"
        }
    }

    @objc private func revealTapped() {
        if let firstOut = lastResult?.Files.first?.Output, !firstOut.isEmpty {
            let url = URL(fileURLWithPath: firstOut)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        dismiss()
    }

    private func dismiss() {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.onDismiss?()
            self?.removeFromSuperview()
        })
    }
}

final class TaskIndicatorManager {
    static let shared = TaskIndicatorManager()

    private var panel: NSPanel?
    private let stackView = NSStackView()
    private var cards: [JobCardView] = []

    private init() {
        setupPanel()
    }

    private func setupPanel() {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 350, height: 100),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.hasShadow = false

        guard let contentView = p.contentView else { return }

        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.spacing = 8
        stackView.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        self.panel = p
    }

    func addJob(_ job: ConversionJob) -> JobCardView {
        let card = JobCardView(job: job)
        cards.append(card)
        stackView.addArrangedSubview(card)

        card.onDismiss = { [weak self, weak card] in
            guard let self = self, let card = card else { return }
            self.cards.removeAll(where: { $0 === card })
            self.stackView.removeArrangedSubview(card)
            card.removeFromSuperview()
            if self.cards.isEmpty {
                self.panel?.orderOut(nil)
            } else {
                self.updatePosition()
            }
        }

        updatePosition()
        panel?.orderFront(nil)
        return card
    }

    private func updatePosition() {
        guard let screen = NSScreen.main else { return }
        guard !cards.isEmpty else {
            panel?.orderOut(nil)
            return
        }

        let totalHeight = CGFloat(cards.count) * 94.0 + 16.0
        let x = screen.visibleFrame.maxX - 360.0
        let y = screen.visibleFrame.minY + 24.0
        panel?.setFrame(NSRect(x: x, y: y, width: 350.0, height: totalHeight), display: true)
    }
}
