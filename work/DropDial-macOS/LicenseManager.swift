import Cocoa
import CryptoKit

// MARK: - License Information Model
struct LicenseInfo: Equatable {
    let name: String
    let email: String
    let date: String
    let tier: String
}

enum LicenseStatus: Equatable {
    case pro(info: LicenseInfo)
    case trial(daysRemaining: Int)
    case trialExpired

    var isPro: Bool {
        if case .pro = self { return true }
        return false
    }

    var canUseApp: Bool {
        switch self {
        case .pro:
            return true
        case .trial(let days):
            return days >= 0
        case .trialExpired:
            return LicenseManager.shared.getDailyConversionsRemaining() > 0
        }
    }

    var displayText: String {
        switch self {
        case .pro(let info):
            return "DropDial Pro ✓ (\(info.name.isEmpty ? info.email : info.name))"
        case .trial(let days):
            if days <= 0 {
                return "Trial: Last day"
            } else if days == 1 {
                return "Trial: 1 day left"
            } else {
                return "Trial: \(days) days left"
            }
        case .trialExpired:
            let rem = LicenseManager.shared.getDailyConversionsRemaining()
            return "Free Tier: \(rem)/3 today — Activate Pro"
        }
    }
}

// MARK: - License Manager (Offline ECDSA P-256 Verification)
final class LicenseManager {
    static let shared = LicenseManager()

    // Embedded ECDSA P-256 public key (X9.62 uncompressed 65-byte point in Base64)
    static let publicKeyBase64 = "BGM3oGnG82GbsMcWAlnuMk2nF+c8lDJs37dTnffkzNFvjwVzgC0PwyyHUIe7LgZOPPOmWEyJeRTEGiCOCGcGdyQ="

    // Configurable purchase URL
    static let defaultBuyUrl = "https://dropdial.app/#pricing"

    // UserDefaults Keys
    private let licenseKeyStoreKey = "DROPDIAL_LICENSE_KEY"
    private let trialStartDateKey = "DROPDIAL_TRIAL_START_TIME"
    private let trialDurationDays = 7

    private(set) var status: LicenseStatus = .trial(daysRemaining: 7)
    var onStatusChanged: (() -> Void)?

    private init() {
        refreshStatus()
    }

    func initialize() {
        refreshStatus()
    }

    // MARK: - Status Checking
    func refreshStatus() {
        let defaults = UserDefaults.standard

        // 1. Check if a valid license key is stored
        if let storedKey = defaults.string(forKey: licenseKeyStoreKey), !storedKey.isEmpty {
            let result = verifyKey(storedKey)
            if result.isValid, let info = result.info {
                status = .pro(info: info)
                onStatusChanged?()
                return
            }
        }

        // 2. Check or initialize trial
        var trialStart = defaults.double(forKey: trialStartDateKey)
        let now = Date().timeIntervalSince1970

        if trialStart == 0 {
            // First run: begin trial today
            trialStart = now
            defaults.set(trialStart, forKey: trialStartDateKey)
        }

        // Anti-rollback check: if clock is earlier than recorded start, trigger expiration
        if now < trialStart - 86400 {
            status = .trialExpired
            onStatusChanged?()
            return
        }

        let secondsElapsed = now - trialStart
        let daysElapsed = Int(secondsElapsed / 86400.0)
        let daysRemaining = trialDurationDays - daysElapsed

        if daysRemaining >= 0 {
            status = .trial(daysRemaining: daysRemaining)
        } else {
            status = .trialExpired
        }

        onStatusChanged?()
    }

    func canUseApp() -> Bool {
        refreshStatus()
        return status.canUseApp
    }

    // MARK: - Daily Freemium Conversion Tracking
    private let dailyConversionsDateKey = "DROPDIAL_DAILY_CONV_DATE"
    private let dailyConversionsCountKey = "DROPDIAL_DAILY_CONV_COUNT"
    let maxFreeDailyConversions = 3

    func getDailyConversionsUsed() -> Int {
        let defaults = UserDefaults.standard
        let todayStr = getTodayDateString()
        let storedDate = defaults.string(forKey: dailyConversionsDateKey) ?? ""
        if storedDate != todayStr {
            return 0
        }
        return defaults.integer(forKey: dailyConversionsCountKey)
    }

    func getDailyConversionsRemaining() -> Int {
        return max(0, maxFreeDailyConversions - getDailyConversionsUsed())
    }

    func recordDailyConversion() {
        let defaults = UserDefaults.standard
        let todayStr = getTodayDateString()
        let storedDate = defaults.string(forKey: dailyConversionsDateKey) ?? ""
        var count = 0
        if storedDate == todayStr {
            count = defaults.integer(forKey: dailyConversionsCountKey)
        }
        defaults.set(todayStr, forKey: dailyConversionsDateKey)
        defaults.set(count + 1, forKey: dailyConversionsCountKey)
        onStatusChanged?()
    }

    private func getTodayDateString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    func canPerformConversion(fileCount: Int = 1, isProTool: Bool = false) -> (allowed: Bool, reason: String?) {
        refreshStatus()
        if status.isPro {
            return (true, nil)
        }
        if case .trial(let days) = status, days >= 0 {
            return (true, nil)
        }

        // Trial has expired — Freemium daily hook
        if isProTool {
            return (false, "Advanced Pro Tools (Trimming, OCR, Redact, Audio Bleep) require DropDial Pro.")
        }
        if fileCount > 3 {
            return (false, "Bulk batch conversion (\(fileCount) files) requires DropDial Pro.")
        }

        let remaining = getDailyConversionsRemaining()
        if remaining > 0 {
            recordDailyConversion()
            return (true, nil)
        }

        return (false, "You've reached your 3 free conversions for today. Unlock unlimited lifetime conversions with DropDial Pro.")
    }

    // MARK: - Offline ECDSA P-256 Key Verification
    func verifyKey(_ licenseKey: String) -> (isValid: Bool, info: LicenseInfo?, error: String?) {
        let trimmed = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.hasPrefix("DD-") else {
            return (false, nil, "Invalid license key format (must start with DD-)")
        }

        let body = String(trimmed.dropFirst(3))
        let parts = body.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            return (false, nil, "Invalid key structure")
        }

        guard let payloadData = base64UrlDecode(String(parts[0])),
              let sigData = base64UrlDecode(String(parts[1])) else {
            return (false, nil, "Malformed license key payload or signature")
        }

        guard sigData.count == 64 else {
            return (false, nil, "Invalid signature length")
        }

        // Decode Public Key
        guard let pubKeyData = Data(base64Encoded: LicenseManager.publicKeyBase64) else {
            return (false, nil, "Failed to load verification public key")
        }

        guard let pubKey = try? P256.Signing.PublicKey(x963Representation: pubKeyData) else {
            return (false, nil, "Failed to parse public key")
        }

        // Parse ECDSA P-256 IEEE P1363 (raw r||s 64-byte) signature
        guard let ecdsaSig = try? P256.Signing.ECDSASignature(rawRepresentation: sigData) else {
            return (false, nil, "Failed to parse signature")
        }

        // Verify cryptographic signature
        guard pubKey.isValidSignature(ecdsaSig, for: payloadData) else {
            return (false, nil, "Signature verification failed (tampered or counterfeit key)")
        }

        // Parse JSON payload
        guard let json = try? JSONSerialization.jsonObject(with: payloadData, options: []) as? [String: Any] else {
            return (false, nil, "Corrupted license key data")
        }

        let email = json["e"] as? String ?? ""
        let name = json["n"] as? String ?? ""
        let date = json["d"] as? String ?? ""
        let tier = json["t"] as? String ?? "pro"

        let info = LicenseInfo(name: name, email: email, date: date, tier: tier)
        return (true, info, nil)
    }

    // MARK: - Activation & Deactivation
    func activate(key: String) -> (success: Bool, message: String) {
        let result = verifyKey(key)
        guard result.isValid, let info = result.info else {
            return (false, result.error ?? "Invalid license key")
        }

        UserDefaults.standard.set(key.trimmingCharacters(in: .whitespacesAndNewlines), forKey: licenseKeyStoreKey)
        status = .pro(info: info)
        onStatusChanged?()
        return (true, "DropDial Pro successfully activated! Thank you, \(info.name.isEmpty ? info.email : info.name).")
    }

    func deactivate() {
        UserDefaults.standard.removeObject(forKey: licenseKeyStoreKey)
        refreshStatus()
    }

    func getStoredKey() -> String? {
        return UserDefaults.standard.string(forKey: licenseKeyStoreKey)
    }

    // MARK: - Base64URL Helper
    private func base64UrlDecode(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }
}

// MARK: - License Window Controller (Clean & Native macOS Activation UI)
private final class LicenseFlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class LicenseWindowController: NSWindowController {
    static let shared = LicenseWindowController()

    private var iconImageView: NSImageView!
    private var titleLabel: NSTextField!
    private var statusLabel: NSTextField!
    private var keyTextField: NSTextField!
    private var pasteButton: NSButton!
    private var messageLabel: NSTextField!
    private var primaryButton: NSButton!
    private var secondaryButton: NSButton!

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 260),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "DropDial Pro"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)

        setupUI()
    }

    private func setupUI() {
        guard let window = window else { return }

        let visualEffect = NSVisualEffectView(frame: window.contentView!.bounds)
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.material = .sheet
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow
        window.contentView = visualEffect

        let container = LicenseFlippedView(frame: NSRect(x: 0, y: 0, width: 420, height: 260))
        container.autoresizingMask = [.width, .height]
        visualEffect.addSubview(container)

        // 1. App Icon (50x50, centered)
        iconImageView = NSImageView(frame: NSRect(x: (420 - 50) / 2, y: 24, width: 50, height: 50))
        if let iconImage = NSApplication.shared.applicationIconImage ?? NSImage(named: "AppIcon") ?? NSImage(named: "dropdial") {
            iconImageView.image = iconImage
        } else {
            iconImageView.image = NSImage(systemSymbolName: "wand.and.stars", accessibilityDescription: nil)
            iconImageView.contentTintColor = .labelColor
        }
        container.addSubview(iconImageView)

        // 2. Title
        titleLabel = NSTextField(labelWithString: "DropDial Pro")
        titleLabel.frame = NSRect(x: 20, y: 82, width: 380, height: 22)
        titleLabel.alignment = .center
        titleLabel.font = NSFont.systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .labelColor
        container.addSubview(titleLabel)

        // 3. Status / Subtitle (Clean & subtle, no tacky banners or emojis)
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.frame = NSRect(x: 20, y: 106, width: 380, height: 18)
        statusLabel.alignment = .center
        statusLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        statusLabel.textColor = .secondaryLabelColor
        container.addSubview(statusLabel)

        // 4. License Key Input Box (Rounded, monospaced) & Dedicated Paste Button
        keyTextField = NSTextField(frame: NSRect(x: 45, y: 134, width: 254, height: 28))
        keyTextField.bezelStyle = .roundedBezel
        keyTextField.placeholderString = "Enter license key (DD-…)"
        keyTextField.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        keyTextField.alignment = .left
        keyTextField.isEditable = true
        keyTextField.isSelectable = true
        keyTextField.target = self
        keyTextField.action = #selector(keyFieldSubmitted)
        container.addSubview(keyTextField)

        pasteButton = NSButton(frame: NSRect(x: 307, y: 134, width: 68, height: 28))
        pasteButton.bezelStyle = .rounded
        pasteButton.title = "Paste"
        pasteButton.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Paste")
        pasteButton.imagePosition = .imageLeading
        pasteButton.font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        pasteButton.target = self
        pasteButton.action = #selector(pasteKeyTapped)
        pasteButton.toolTip = "Paste license key from clipboard"
        container.addSubview(pasteButton)

        // 5. Message / Feedback Label
        messageLabel = NSTextField(labelWithString: "")
        messageLabel.frame = NSRect(x: 30, y: 166, width: 360, height: 16)
        messageLabel.alignment = .center
        messageLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        messageLabel.lineBreakMode = .byTruncatingTail
        container.addSubview(messageLabel)

        // 6. Action Buttons (Balanced native macOS button row)
        secondaryButton = NSButton(frame: NSRect(x: 45, y: 196, width: 160, height: 32))
        secondaryButton.bezelStyle = .rounded
        secondaryButton.target = self
        container.addSubview(secondaryButton)

        primaryButton = NSButton(frame: NSRect(x: 420 - 45 - 160, y: 196, width: 160, height: 32))
        primaryButton.bezelStyle = .rounded
        primaryButton.keyEquivalent = "\r"
        primaryButton.target = self
        container.addSubview(primaryButton)

        updateDisplay()
    }

    func show() {
        messageLabel.stringValue = ""
        updateDisplay()

        // If not already Pro and clipboard contains a DD- key, autofill it seamlessly
        if case .pro = LicenseManager.shared.status { } else {
            if let clip = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
               clip.hasPrefix("DD-") {
                keyTextField.stringValue = clip
            }
        }

        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func updateDisplay() {
        LicenseManager.shared.refreshStatus()
        let status = LicenseManager.shared.status

        switch status {
        case .pro(let info):
            let nameStr = info.name.isEmpty ? info.email : info.name
            statusLabel.stringValue = "Licensed to \(nameStr)"
            statusLabel.textColor = .secondaryLabelColor

            keyTextField.stringValue = LicenseManager.shared.getStoredKey() ?? ""
            keyTextField.isEnabled = false
            pasteButton.isEnabled = false

            secondaryButton.title = "Deactivate…"
            secondaryButton.action = #selector(deactivateTapped)
            secondaryButton.isHidden = false

            primaryButton.title = "Done"
            primaryButton.action = #selector(closeTapped)
            primaryButton.isEnabled = true

            messageLabel.stringValue = ""

        case .trial(let days):
            if days <= 1 {
                statusLabel.stringValue = "1 day remaining in free trial"
            } else {
                statusLabel.stringValue = "\(days) days remaining in free trial"
            }
            statusLabel.textColor = .secondaryLabelColor

            keyTextField.stringValue = ""
            keyTextField.isEnabled = true
            pasteButton.isEnabled = true

            secondaryButton.title = "Buy License…"
            secondaryButton.action = #selector(buyTapped)
            secondaryButton.isHidden = false

            primaryButton.title = "Activate"
            primaryButton.action = #selector(activateTapped)
            primaryButton.isEnabled = true

        case .trialExpired:
            let rem = LicenseManager.shared.getDailyConversionsRemaining()
            statusLabel.stringValue = "Trial expired • Free tier: \(rem)/\(LicenseManager.shared.maxFreeDailyConversions) conversions left today"
            statusLabel.textColor = .systemOrange

            keyTextField.stringValue = ""
            keyTextField.isEnabled = true
            pasteButton.isEnabled = true

            secondaryButton.title = "Buy License…"
            secondaryButton.action = #selector(buyTapped)
            secondaryButton.isHidden = false

            primaryButton.title = "Activate"
            primaryButton.action = #selector(activateTapped)
            primaryButton.isEnabled = true
        }
    }

    @objc private func pasteKeyTapped() {
        guard let clip = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !clip.isEmpty else {
            messageLabel.stringValue = "Clipboard is empty"
            messageLabel.textColor = .systemOrange
            return
        }
        keyTextField.stringValue = clip
        messageLabel.stringValue = ""
        keyTextField.selectText(nil)
        if clip.hasPrefix("DD-") {
            messageLabel.stringValue = "Key pasted • Click Activate to confirm"
            messageLabel.textColor = .secondaryLabelColor
        }
    }

    @objc private func keyFieldSubmitted() {
        activateTapped()
    }

    @objc private func closeTapped() {
        window?.close()
    }

    @objc private func activateTapped() {
        let key = keyTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            messageLabel.stringValue = "Please enter your license key."
            messageLabel.textColor = .systemRed
            return
        }

        let result = LicenseManager.shared.activate(key: key)
        if result.success {
            messageLabel.stringValue = ""
            updateDisplay()
        } else {
            messageLabel.stringValue = result.message
            messageLabel.textColor = .systemRed
        }
    }

    @objc private func deactivateTapped() {
        let alert = NSAlert()
        alert.messageText = "Deactivate DropDial Pro?"
        alert.informativeText = "Are you sure you want to remove the license from this Mac? You can re-activate it anytime using your key."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Deactivate")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            LicenseManager.shared.deactivate()
            messageLabel.stringValue = "License deactivated."
            messageLabel.textColor = .secondaryLabelColor
            updateDisplay()
        }
    }

    @objc private func buyTapped() {
        if let url = URL(string: LicenseManager.defaultBuyUrl) {
            NSWorkspace.shared.open(url)
        }
    }
}
