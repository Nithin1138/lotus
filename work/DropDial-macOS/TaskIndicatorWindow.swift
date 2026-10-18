import AppKit

enum JobCardState {
    case waiting
    case running
    case paused
    case completed
    case failed
}

// Custom progress bar with vibrant DropDial orange and smooth animation
final class JobProgressBar: NSView {
    var progress: Double = 0.0 {
        didSet {
            needsDisplay = true
        }
    }

    var fillColor: NSColor = NSColor(srgbRed: 1.0, green: 0.384, blue: 0.031, alpha: 1.0) {
        didSet {
            needsDisplay = true
        }
    }

    var isIndeterminate: Bool = false {
        didSet {
            if isIndeterminate { startAnimation() } else { stopAnimation() }
            needsDisplay = true
        }
    }

    private var animOffset: CGFloat = 0.0
    private var animTimer: Timer?

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let trackRect = bounds
        let corner = bounds.height / 2.0

        // 1. Subtle track background
        let trackPath = NSBezierPath(roundedRect: trackRect, xRadius: corner, yRadius: corner)
        NSColor(white: 0.5, alpha: 0.18).setFill()
        trackPath.fill()

        guard bounds.width > 0 else { return }

        // 2. Active fill
        if isIndeterminate {
            let fillW = max(35.0, bounds.width * 0.28)
            let x = -fillW + animOffset * (bounds.width + fillW)
            let fillRect = NSRect(x: x, y: 0, width: fillW, height: bounds.height)
            let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: corner, yRadius: corner)
            fillColor.setFill()
            fillPath.fill()
        } else {
            let p = max(0.0, min(1.0, progress))
            let fillW = max(bounds.height, bounds.width * CGFloat(p))
            let fillRect = NSRect(x: 0, y: 0, width: fillW, height: bounds.height)
            let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: corner, yRadius: corner)
            fillColor.setFill()
            fillPath.fill()
        }
    }

    private func startAnimation() {
        guard animTimer == nil else { return }
        animTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.animOffset += 0.025
            if self.animOffset > 1.0 { self.animOffset = 0.0 }
            self.needsDisplay = true
        }
    }

    private func stopAnimation() {
        animTimer?.invalidate()
        animTimer = nil
        animOffset = 0.0
    }

    deinit {
        stopAnimation()
    }
}

// MARK: - Styled Action Button
enum TaskActionButtonStyle {
    case primarySuccess
    case primaryAccent
    case secondary
    case destructive
    case ghost
}

final class TaskActionButton: NSButton {
    var buttonStyle: TaskActionButtonStyle = .secondary {
        didSet { applyStyle() }
    }

    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        bezelStyle = .inline
        isBordered = false
        alignment = .center
        wantsLayer = true
        layer?.cornerRadius = 13
        layer?.masksToBounds = true
        layer?.borderWidth = 1.0
        font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        applyStyle()
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height > 0 ? bounds.height / 2.0 : 13.0
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea {
            removeTrackingArea(ta)
        }
        let ta = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil)
        addTrackingArea(ta)
        self.trackingArea = ta
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        applyStyle()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        applyStyle()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    func applyStyle() {
        switch buttonStyle {
        case .primarySuccess:
            let bg = isHovered ? NSColor(srgbRed: 0.18, green: 0.78, blue: 0.42, alpha: 0.38) : NSColor(srgbRed: 0.16, green: 0.74, blue: 0.38, alpha: 0.22)
            let border = isHovered ? NSColor(srgbRed: 0.32, green: 0.92, blue: 0.55, alpha: 0.75) : NSColor(srgbRed: 0.24, green: 0.84, blue: 0.48, alpha: 0.45)
            layer?.backgroundColor = bg.cgColor
            layer?.borderColor = border.cgColor
            contentTintColor = isHovered ? .white : NSColor(srgbRed: 0.42, green: 0.98, blue: 0.65, alpha: 1.0)
            font = NSFont.systemFont(ofSize: 11.5, weight: .semibold)

        case .primaryAccent:
            let bg = isHovered ? NSColor(srgbRed: 1.0, green: 0.45, blue: 0.08, alpha: 0.40) : NSColor(srgbRed: 1.0, green: 0.42, blue: 0.08, alpha: 0.24)
            let border = isHovered ? NSColor(srgbRed: 1.0, green: 0.62, blue: 0.25, alpha: 0.75) : NSColor(srgbRed: 1.0, green: 0.52, blue: 0.18, alpha: 0.50)
            layer?.backgroundColor = bg.cgColor
            layer?.borderColor = border.cgColor
            contentTintColor = isHovered ? .white : NSColor(srgbRed: 1.0, green: 0.72, blue: 0.42, alpha: 1.0)
            font = NSFont.systemFont(ofSize: 11.5, weight: .semibold)

        case .secondary:
            let bg = isHovered ? NSColor(white: 1.0, alpha: 0.18) : NSColor(white: 1.0, alpha: 0.09)
            let border = isHovered ? NSColor(white: 1.0, alpha: 0.35) : NSColor(white: 1.0, alpha: 0.18)
            layer?.backgroundColor = bg.cgColor
            layer?.borderColor = border.cgColor
            contentTintColor = isHovered ? .white : NSColor(white: 0.94, alpha: 1.0)
            font = NSFont.systemFont(ofSize: 11.5, weight: .medium)

        case .destructive:
            let bg = isHovered ? NSColor(srgbRed: 1.0, green: 0.25, blue: 0.25, alpha: 0.30) : NSColor(srgbRed: 1.0, green: 0.25, blue: 0.25, alpha: 0.16)
            let border = isHovered ? NSColor(srgbRed: 1.0, green: 0.40, blue: 0.40, alpha: 0.65) : NSColor(srgbRed: 1.0, green: 0.32, blue: 0.32, alpha: 0.36)
            layer?.backgroundColor = bg.cgColor
            layer?.borderColor = border.cgColor
            contentTintColor = isHovered ? .white : NSColor(srgbRed: 1.0, green: 0.60, blue: 0.60, alpha: 1.0)
            font = NSFont.systemFont(ofSize: 11.5, weight: .medium)

        case .ghost:
            let bg = isHovered ? NSColor(white: 1.0, alpha: 0.12) : NSColor(white: 1.0, alpha: 0.05)
            let border = isHovered ? NSColor(white: 1.0, alpha: 0.25) : NSColor(white: 1.0, alpha: 0.12)
            layer?.backgroundColor = bg.cgColor
            layer?.borderColor = border.cgColor
            contentTintColor = isHovered ? NSColor(white: 0.95, alpha: 1.0) : NSColor(white: 0.72, alpha: 1.0)
            font = NSFont.systemFont(ofSize: 11.5, weight: .regular)
        }
    }
}

// MARK: - Individual Job Card View
final class JobCardView: NSView {
    let job: ConversionJob
    var process: Process?
    var runner: (() -> Void)?
    var state: JobCardState = .running {
        didSet {
            updateUIForState()
        }
    }

    private let effectView = NSVisualEffectView()
    private let statusDot = NSBox()
    private let statusHeadingLabel = NSTextField(labelWithString: "Processing")
    private let metaTimingLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let progressBar = JobProgressBar()
    private let metaLabel = NSTextField(labelWithString: "")

    // Button controls
    private let buttonContainer = NSView()
    private let pauseButton = TaskActionButton()
    private let cancelButton = TaskActionButton()
    private let hideButton = TaskActionButton()
    private let openButton = TaskActionButton()
    private let revealButton = TaskActionButton()

    // Timing & results
    private var elapsedSeconds: Int = 0
    private var elapsedTimer: Timer?
    var createdOutputPaths: [String] = []
    var onDismiss: (() -> Void)?

    override var intrinsicContentSize: NSSize {
        return NSSize(width: 344, height: 146)
    }

    init(job: ConversionJob) {
        self.job = job
        super.init(frame: NSRect(x: 0, y: 0, width: 344, height: 146))
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 344).isActive = true
        heightAnchor.constraint(equalToConstant: 146).isActive = true

        // 1. Frosted Glass Background
        effectView.frame = NSRect(x: 0, y: 0, width: 344, height: 146)
        effectView.autoresizingMask = [.width, .height]
        effectView.material = .hudWindow
        effectView.blendingMode = .withinWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 14
        effectView.layer?.masksToBounds = true
        effectView.layer?.borderColor = NSColor(white: 1.0, alpha: 0.16).cgColor
        effectView.layer?.borderWidth = 1.0
        addSubview(effectView)

        // Drop shadow for card separation
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.32
        layer?.shadowOffset = CGSize(width: 0, height: -4)
        layer?.shadowRadius = 10

        // 2. Status Dot & Heading (y = 114 to 134)
        statusDot.frame = NSRect(x: 18, y: 121, width: 7, height: 7)
        statusDot.boxType = .custom
        statusDot.cornerRadius = 3.5
        statusDot.borderWidth = 0
        statusDot.fillColor = NSColor(srgbRed: 1.0, green: 0.42, blue: 0.08, alpha: 1.0)
        addSubview(statusDot)

        statusHeadingLabel.frame = NSRect(x: 31, y: 114, width: 175, height: 20)
        statusHeadingLabel.font = NSFont.systemFont(ofSize: 13.5, weight: .bold)
        statusHeadingLabel.textColor = .white
        addSubview(statusHeadingLabel)

        metaTimingLabel.frame = NSRect(x: 210, y: 116, width: 116, height: 16)
        metaTimingLabel.alignment = .right
        metaTimingLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        metaTimingLabel.textColor = NSColor(white: 0.65, alpha: 1.0)
        metaTimingLabel.stringValue = ""
        addSubview(metaTimingLabel)

        // 3. Subtitle / Filename (y = 92)
        let firstPath = job.Paths.first ?? ""
        let firstName = URL(fileURLWithPath: firstPath).lastPathComponent
        let countSuffix = job.Paths.count > 1 ? " and \(job.Paths.count - 1) more" : ""
        titleLabel.frame = NSRect(x: 18, y: 92, width: 308, height: 18)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = NSColor(white: 0.95, alpha: 1.0)
        titleLabel.stringValue = firstName + countSuffix
        titleLabel.lineBreakMode = .byTruncatingMiddle
        addSubview(titleLabel)

        // 4. Progress Bar (y = 78)
        progressBar.frame = NSRect(x: 18, y: 78, width: 308, height: 3.5)
        progressBar.progress = 0.0
        progressBar.isIndeterminate = true
        addSubview(progressBar)

        // 5. Meta / Detail Label (DEDICATED ROW y = 48, full 308pt width)
        metaLabel.frame = NSRect(x: 18, y: 48, width: 308, height: 20)
        metaLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .regular)
        metaLabel.textColor = NSColor(white: 0.72, alpha: 1.0)
        metaLabel.lineBreakMode = .byTruncatingTail
        metaLabel.stringValue = "Elapsed 0 s"
        addSubview(metaLabel)

        // 6. Action Buttons Bar (DEDICATED ROW y = 14, full 308pt width)
        buttonContainer.frame = NSRect(x: 18, y: 14, width: 308, height: 28)
        addSubview(buttonContainer)

        setupButton(pauseButton, title: "Pause", action: #selector(pauseTapped))
        setupButton(cancelButton, title: "Cancel", action: #selector(cancelTapped))
        setupButton(hideButton, title: "Hide", action: #selector(hideTapped))
        setupButton(openButton, title: "Open", action: #selector(openTapped))
        setupButton(revealButton, title: "Show in Finder", action: #selector(revealTapped))

        updateUIForState()
    }

    private func setupButton(_ btn: TaskActionButton, title: String, action: Selector) {
        btn.title = title
        btn.target = self
        btn.action = action
        buttonContainer.addSubview(btn)
    }

    func updateUIForState() {
        switch state {
        case .waiting:
            statusHeadingLabel.stringValue = "Waiting"
            statusHeadingLabel.textColor = NSColor(white: 0.85, alpha: 1.0)
            statusDot.fillColor = NSColor(white: 0.75, alpha: 1.0)
            metaTimingLabel.stringValue = "Queued"
            metaLabel.stringValue = "Starts when a running job finishes"
            progressBar.isIndeterminate = false
            progressBar.progress = 0.0

            cancelButton.buttonStyle = .destructive
            hideButton.buttonStyle = .ghost

            pauseButton.isHidden = true
            cancelButton.isHidden = false
            hideButton.isHidden = false
            openButton.isHidden = true
            revealButton.isHidden = true

            layoutButtons([cancelButton, hideButton])

        case .running:
            let actionName = job.Action.hasPrefix("convert:") ? "Converting" : "Processing"
            statusHeadingLabel.stringValue = actionName
            statusHeadingLabel.textColor = .white
            statusDot.fillColor = NSColor(srgbRed: 1.0, green: 0.42, blue: 0.08, alpha: 1.0)
            updateMetaText()

            pauseButton.buttonStyle = .secondary
            pauseButton.title = "Pause"
            cancelButton.buttonStyle = .destructive
            cancelButton.title = "Cancel"
            hideButton.buttonStyle = .ghost
            hideButton.title = "Hide"

            pauseButton.isHidden = false
            cancelButton.isHidden = false
            hideButton.isHidden = false
            openButton.isHidden = true
            revealButton.isHidden = true

            layoutButtons([pauseButton, cancelButton, hideButton])

        case .paused:
            statusHeadingLabel.stringValue = "Paused"
            statusHeadingLabel.textColor = NSColor(srgbRed: 1.0, green: 0.75, blue: 0.30, alpha: 1.0)
            statusDot.fillColor = NSColor(srgbRed: 1.0, green: 0.75, blue: 0.30, alpha: 1.0)
            metaTimingLabel.stringValue = "Paused"

            pauseButton.buttonStyle = .primaryAccent
            pauseButton.title = "Resume"
            cancelButton.buttonStyle = .destructive
            cancelButton.title = "Cancel"
            hideButton.buttonStyle = .ghost
            hideButton.title = "Hide"

            pauseButton.isHidden = false
            cancelButton.isHidden = false
            hideButton.isHidden = false
            openButton.isHidden = true
            revealButton.isHidden = true

            layoutButtons([pauseButton, cancelButton, hideButton])

        case .completed:
            statusHeadingLabel.stringValue = "Completed"
            statusHeadingLabel.textColor = NSColor(srgbRed: 0.32, green: 0.90, blue: 0.52, alpha: 1.0)
            statusDot.fillColor = NSColor(srgbRed: 0.32, green: 0.90, blue: 0.52, alpha: 1.0)
            metaTimingLabel.stringValue = "Done"

            progressBar.isIndeterminate = false
            progressBar.progress = 1.0
            progressBar.fillColor = NSColor(srgbRed: 0.32, green: 0.90, blue: 0.52, alpha: 1.0)

            openButton.buttonStyle = .primarySuccess
            openButton.title = "Open"
            revealButton.buttonStyle = .secondary
            revealButton.title = "Show in Finder"
            hideButton.buttonStyle = .ghost
            hideButton.title = "Hide"

            pauseButton.isHidden = true
            cancelButton.isHidden = true
            openButton.isHidden = false
            revealButton.isHidden = false
            hideButton.isHidden = false

            layoutButtons([openButton, revealButton, hideButton])

        case .failed:
            statusHeadingLabel.stringValue = "Failed"
            statusHeadingLabel.textColor = NSColor(srgbRed: 1.0, green: 0.35, blue: 0.35, alpha: 1.0)
            statusDot.fillColor = NSColor(srgbRed: 1.0, green: 0.35, blue: 0.35, alpha: 1.0)
            metaTimingLabel.stringValue = "Error"

            progressBar.isIndeterminate = false
            progressBar.progress = 1.0
            progressBar.fillColor = NSColor(srgbRed: 1.0, green: 0.35, blue: 0.35, alpha: 1.0)

            hideButton.buttonStyle = .ghost
            hideButton.title = "Dismiss"

            pauseButton.isHidden = true
            cancelButton.isHidden = true
            openButton.isHidden = true
            revealButton.isHidden = true
            hideButton.isHidden = false

            layoutButtons([hideButton])
        }
    }

    private func layoutButtons(_ buttons: [TaskActionButton]) {
        let spacing: CGFloat = 8
        var totalW: CGFloat = 0
        var widths: [CGFloat] = []

        for btn in buttons {
            let width: CGFloat
            if btn == revealButton {
                width = 114
            } else if btn == openButton {
                width = 58
            } else if btn == pauseButton && state == .paused {
                width = 72
            } else if btn == pauseButton {
                width = 62
            } else if btn == cancelButton {
                width = 66
            } else if btn == hideButton && state == .failed {
                width = 68
            } else {
                width = 50
            }
            widths.append(width)
            totalW += width
        }
        if !buttons.isEmpty {
            totalW += CGFloat(buttons.count - 1) * spacing
        }

        // Right-align inside buttonContainer (width 308)
        var x = max(0, buttonContainer.bounds.width - totalW)
        for (i, btn) in buttons.enumerated() {
            let w = widths[i]
            btn.frame = NSRect(x: x, y: 1, width: w, height: 26)
            x += w + spacing
        }
    }

    func startTimer() {
        stopTimer()
        elapsedSeconds = 0
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.elapsedSeconds += 1
            if self.state == .running {
                self.updateMetaText()
            }
        }
    }

    func stopTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }

    private func updateMetaText() {
        let timeStr: String
        if elapsedSeconds < 60 {
            timeStr = "Elapsed \(elapsedSeconds) s"
        } else {
            let mins = elapsedSeconds / 60
            let secs = elapsedSeconds % 60
            timeStr = "Elapsed \(mins)m \(secs)s"
        }
        metaTimingLabel.stringValue = timeStr
        if metaLabel.stringValue.hasPrefix("Elapsed ") || metaLabel.stringValue.isEmpty {
            metaLabel.stringValue = timeStr
        }
    }

    func updateProgress(_ progress: JobProgress) {
        if let total = progress.Total, total > 0, let processed = progress.Processed {
            progressBar.isIndeterminate = false
            progressBar.progress = Double(processed) / Double(total)
            if total > 1 {
                metaLabel.stringValue = "\(processed) of \(total) done · Elapsed \(elapsedSeconds) s"
            }
        }
        if let current = progress.Current, !current.isEmpty {
            titleLabel.stringValue = current
        }
    }

    func markCompleted(result: BatchResult) {
        stopTimer()

        var successful = result.Files.compactMap { $0.Output }.filter { !$0.isEmpty }
        let errors = result.Files.compactMap { $0.Error }.filter { !$0.isEmpty }

        // Fallback: check if the created file is present on disk
        if successful.isEmpty && errors.isEmpty {
            if let firstInput = job.Paths.first {
                let inputUrl = URL(fileURLWithPath: firstInput)
                let parentDir = inputUrl.deletingLastPathComponent()
                let stem = inputUrl.deletingPathExtension().lastPathComponent
                if let contents = try? FileManager.default.contentsOfDirectory(at: parentDir, includingPropertiesForKeys: [.contentModificationDateKey]) {
                    let recent = contents.filter { url in
                        url.lastPathComponent.hasPrefix(stem) && url.path != firstInput
                    }.sorted {
                        let d1 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                        let d2 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                        return d1 > d2
                    }
                    if let newest = recent.first {
                        successful.append(newest.path)
                    }
                }
            }
        }

        // Check if there are failures and zero outputs
        if successful.isEmpty && !errors.isEmpty {
            markFailed(error: NSError(domain: "DropDial", code: -1, userInfo: [NSLocalizedDescriptionKey: errors.joined(separator: ", ")]))
            return
        }

        self.createdOutputPaths = successful
        self.state = .completed

        if let firstOut = successful.first {
            let outUrl = URL(fileURLWithPath: firstOut)
            let outName = outUrl.lastPathComponent
            let folderName = outUrl.deletingLastPathComponent().lastPathComponent

            titleLabel.stringValue = successful.count > 1 ? "\(outName) (+\(successful.count - 1) more)" : outName

            var detail = "File created · Saved in \(folderName)"
            if let attrs = try? FileManager.default.attributesOfItem(atPath: firstOut), let sz = attrs[.size] as? Int64 {
                let szStr = ByteCountFormatter.string(fromByteCount: sz, countStyle: .file)
                detail = "File created (\(szStr)) · Saved in \(folderName)"
            }
            metaLabel.stringValue = detail

            // Automatically reveal and highlight the converted file in Finder!
            NSWorkspace.shared.activateFileViewerSelecting(successful.map { URL(fileURLWithPath: $0) })
        } else {
            metaLabel.stringValue = "File created"
        }

        TaskIndicatorManager.shared.onJobStateChanged(card: self)

        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
            self?.dismiss()
        }
    }

    func markFailed(error: Error) {
        stopTimer()
        self.state = .failed
        let msg = error.localizedDescription
        metaLabel.stringValue = msg.isEmpty ? "Failed" : msg

        TaskIndicatorManager.shared.onJobStateChanged(card: self)

        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
            self?.dismiss()
        }
    }

    @objc private func pauseTapped() {
        guard let pid = process?.processIdentifier else { return }
        if state == .running {
            kill(pid, SIGSTOP)
            state = .paused
            stopTimer()
            TaskIndicatorManager.shared.onJobStateChanged(card: self)
        } else if state == .paused {
            kill(pid, SIGCONT)
            state = .running
            startTimer()
            TaskIndicatorManager.shared.onJobStateChanged(card: self)
        }
    }

    @objc private func cancelTapped() {
        stopTimer()
        process?.terminate()
        dismiss()
    }

    @objc private func hideTapped() {
        dismiss()
    }

    @objc private func openTapped() {
        if let first = createdOutputPaths.first {
            NSWorkspace.shared.open(URL(fileURLWithPath: first))
        }
    }

    @objc private func revealTapped() {
        if !createdOutputPaths.isEmpty {
            let urls = createdOutputPaths.map { URL(fileURLWithPath: $0) }
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        }
    }

    func dismiss() {
        stopTimer()
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.onDismiss?()
            self?.removeFromSuperview()
        })
    }
}

// MARK: - Top Summary Header Bar (shown when 2 or more jobs exist)
final class TaskIndicatorHeaderView: NSView {
    private let effectView = NSVisualEffectView()
    private let summaryLabel = NSTextField(labelWithString: "")
    private let collapseButton = TaskActionButton()
    private let hideAllButton = TaskActionButton()

    var isCollapsed = false {
        didSet {
            collapseButton.title = isCollapsed ? "Expand" : "Collapse"
        }
    }

    var onToggleCollapse: (() -> Void)?
    var onHideAll: (() -> Void)?

    override var intrinsicContentSize: NSSize {
        return NSSize(width: 344, height: 48)
    }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 344, height: 48))
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupUI() {
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 344).isActive = true
        heightAnchor.constraint(equalToConstant: 48).isActive = true

        effectView.frame = NSRect(x: 0, y: 0, width: 344, height: 48)
        effectView.autoresizingMask = [.width, .height]
        effectView.material = .hudWindow
        effectView.blendingMode = .withinWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 12
        effectView.layer?.masksToBounds = true
        effectView.layer?.borderColor = NSColor(white: 1.0, alpha: 0.18).cgColor
        effectView.layer?.borderWidth = 1.0
        addSubview(effectView)

        wantsLayer = true
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.22
        layer?.shadowOffset = CGSize(width: 0, height: -2)
        layer?.shadowRadius = 6

        summaryLabel.frame = NSRect(x: 14, y: 6, width: 185, height: 34)
        summaryLabel.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        summaryLabel.textColor = NSColor(white: 0.75, alpha: 1.0)
        summaryLabel.maximumNumberOfLines = 2
        summaryLabel.lineBreakMode = .byWordWrapping
        summaryLabel.stringValue = "2 jobs · running 1"
        addSubview(summaryLabel)

        collapseButton.buttonStyle = .secondary
        collapseButton.title = "Collapse"
        collapseButton.frame = NSRect(x: 202, y: 11, width: 68, height: 26)
        collapseButton.target = self
        collapseButton.action = #selector(collapseClicked)
        addSubview(collapseButton)

        hideAllButton.buttonStyle = .ghost
        hideAllButton.title = "Hide all"
        hideAllButton.frame = NSRect(x: 276, y: 11, width: 58, height: 26)
        hideAllButton.target = self
        hideAllButton.action = #selector(hideAllClicked)
        addSubview(hideAllButton)
    }

    func updateSummary(total: Int, running: Int, paused: Int, waiting: Int, completed: Int) {
        var line1 = "\(total) jobs"
        if running > 0 { line1 += " · running \(running)" }

        var line2Parts: [String] = []
        if paused > 0 { line2Parts.append("paused \(paused)") }
        if waiting > 0 { line2Parts.append("waiting \(waiting)") }
        if completed > 0 { line2Parts.append("done \(completed)") }

        if line2Parts.isEmpty {
            summaryLabel.stringValue = line1
        } else {
            summaryLabel.stringValue = line1 + "\n" + line2Parts.joined(separator: " · ")
        }
    }

    @objc private func collapseClicked() {
        onToggleCollapse?()
    }

    @objc private func hideAllClicked() {
        onHideAll?()
    }
}

// MARK: - Manager & Floating Panel
final class TaskIndicatorManager {
    static let shared = TaskIndicatorManager()

    private var panel: NSPanel?
    private let stackView = NSStackView()
    private let headerView = TaskIndicatorHeaderView()
    private var cards: [JobCardView] = []
    private var isCollapsed: Bool = false

    private init() {
        setupPanel()
    }

    private func setupPanel() {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 100),
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
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        headerView.onToggleCollapse = { [weak self] in
            guard let self = self else { return }
            self.isCollapsed.toggle()
            self.headerView.isCollapsed = self.isCollapsed
            self.applyCollapseState()
            self.updatePosition()
        }

        headerView.onHideAll = { [weak self] in
            self?.hideAll()
        }

        self.panel = p
    }

    /// Enqueue a job. If a job is already running, this card is queued as `.waiting`.
    /// When active jobs finish, waiting jobs start automatically.
    @discardableResult
    func enqueue(job: ConversionJob, runner: @escaping (JobCardView) -> Void) -> JobCardView {
        let card = JobCardView(job: job)
        card.runner = { [weak card] in
            guard let card = card else { return }
            runner(card)
        }

        cards.append(card)

        let isAnyRunning = cards.contains { $0 !== card && ($0.state == .running || $0.state == .paused) }
        if isAnyRunning {
            card.state = .waiting
        } else {
            card.state = .running
            card.startTimer()
            card.runner?()
        }

        wireCard(card)
        refreshStack()
        updatePosition()
        panel?.orderFront(nil)
        return card
    }

    /// Backwards compatibility helper
    @discardableResult
    func addJob(_ job: ConversionJob) -> JobCardView {
        let card = JobCardView(job: job)
        cards.append(card)

        let isAnyRunning = cards.contains { $0 !== card && ($0.state == .running || $0.state == .paused) }
        if isAnyRunning {
            card.state = .waiting
        } else {
            card.state = .running
            card.startTimer()
        }

        wireCard(card)
        refreshStack()
        updatePosition()
        panel?.orderFront(nil)
        return card
    }

    private func wireCard(_ card: JobCardView) {
        card.onDismiss = { [weak self, weak card] in
            guard let self = self, let card = card else { return }
            self.cards.removeAll(where: { $0 === card })
            self.stackView.removeArrangedSubview(card)
            card.removeFromSuperview()

            self.checkNextWaitingJob()
            self.refreshStack()

            if self.cards.isEmpty {
                self.panel?.orderOut(nil)
            } else {
                self.updatePosition()
            }
        }
    }

    func onJobStateChanged(card: JobCardView) {
        checkNextWaitingJob()
        refreshStack()
        updatePosition()
    }

    private func checkNextWaitingJob() {
        let hasActive = cards.contains { $0.state == .running || $0.state == .paused }
        if !hasActive {
            if let next = cards.first(where: { $0.state == .waiting }) {
                next.state = .running
                next.startTimer()
                next.runner?()
            }
        }
    }

    func hideAll() {
        for card in cards {
            card.dismiss()
        }
        panel?.orderOut(nil)
    }

    private func refreshStack() {
        // Clear all subviews
        for sub in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(sub)
            sub.removeFromSuperview()
        }

        // Header view is shown when there are 2 or more jobs
        if cards.count >= 2 {
            let total = cards.count
            let running = cards.filter { $0.state == .running }.count
            let paused = cards.filter { $0.state == .paused }.count
            let waiting = cards.filter { $0.state == .waiting }.count
            let completed = cards.filter { $0.state == .completed }.count
            headerView.updateSummary(total: total, running: running, paused: paused, waiting: waiting, completed: completed)
            stackView.addArrangedSubview(headerView)
        }

        applyCollapseState()
    }

    private func applyCollapseState() {
        if isCollapsed && cards.count > 1 {
            // Only show the top active running card or newest card
            let topCard = cards.last(where: { $0.state == .running }) ?? cards.last
            for card in cards {
                if card === topCard {
                    if !stackView.arrangedSubviews.contains(card) {
                        stackView.addArrangedSubview(card)
                    }
                    card.isHidden = false
                } else {
                    card.isHidden = true
                }
            }
        } else {
            for card in cards {
                if !stackView.arrangedSubviews.contains(card) {
                    stackView.addArrangedSubview(card)
                }
                card.isHidden = false
            }
        }
    }

    private func updatePosition() {
        guard let screen = NSScreen.main else { return }
        guard !cards.isEmpty else {
            panel?.orderOut(nil)
            return
        }

        var totalHeight: CGFloat = 16.0
        if cards.count >= 2 {
            totalHeight += 56.0
        }

        if isCollapsed && cards.count > 1 {
            totalHeight += 154.0
        } else {
            totalHeight += CGFloat(cards.count) * 154.0
        }

        let x = screen.visibleFrame.maxX - 376.0
        let y = screen.visibleFrame.minY + 24.0
        panel?.setFrame(NSRect(x: x, y: y, width: 360.0, height: totalHeight), display: true)
    }
}
