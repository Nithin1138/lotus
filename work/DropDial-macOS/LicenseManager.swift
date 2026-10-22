import Cocoa
import CryptoKit

// MARK: - License Information Model
struct LicenseInfo: Equatable {
    let name: String
    let email: String
    let date: String
    let tier: String
    let expiresAt: Double? // Unix epoch seconds, nil if lifetime

    var planDisplayName: String {
        switch tier.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "single":
            return "Single"
        case "team":
            return "Team"
        case "universal":
            return "Universal"
        default:
            return "Pro"
        }
    }

    var isExpired: Bool {
        guard let exp = expiresAt else { return false }
        return Date().timeIntervalSince1970 >= exp
    }

    var secondsRemaining: Int {
        guard let exp = expiresAt else { return Int.max }
        return max(0, Int(exp - Date().timeIntervalSince1970))
    }
}

enum LicenseStatus: Equatable {
    case pro(info: LicenseInfo)
    case trial(daysRemaining: Int)
    case trialExpired

    var isPro: Bool {
        if case .pro(let info) = self {
            return !info.isExpired
        }
        return false
    }

    var canUseApp: Bool {
        switch self {
        case .pro(let info):
            return !info.isExpired
        case .trial(let days):
            return days > 0 && LicenseManager.shared.trialRemainingSeconds > 0
        case .trialExpired:
            return LicenseManager.shared.getDailyConversionsRemaining() > 0
        }
    }

    var displayText: String {
        switch self {
        case .pro(let info):
            let displayName = info.name.isEmpty ? info.email : info.name
            let plan = info.planDisplayName
            if let _ = info.expiresAt {
                let sec = info.secondsRemaining
                if sec <= 0 {
                    return "\(plan) Test License Expired"
                } else if sec < 60 {
                    return "DropDial \(plan) (\(sec)s left)"
                } else if sec < 3600 {
                    let m = sec / 60
                    let s = sec % 60
                    return "DropDial \(plan) (\(m)m \(s)s left)"
                } else {
                    let h = sec / 3600
                    return "DropDial \(plan) (\(h)h left)"
                }
            }
            return "DropDial \(plan) Plan ✓ (\(displayName))"
        case .trial(let days):
            if LicenseManager.shared.isWithinFirst24Hours {
                let sec = LicenseManager.shared.first24HoursRemainingSeconds
                let h = sec / 3600
                let m = (sec % 3600) / 60
                return "Trial: \(days)d · 10% Off (\(h)h \(m)m left)"
            }
            if days <= 0 {
                let timeStr = LicenseManager.formatTimeRemaining(LicenseManager.shared.trialRemainingSeconds)
                return "Trial: Last day (\(timeStr) left) — Activate Pro"
            } else if days == 1 {
                let timeStr = LicenseManager.formatTimeRemaining(LicenseManager.shared.trialRemainingSeconds)
                return "Trial: 1 day left (\(timeStr)) — Activate Pro"
            } else {
                return "Trial: \(days) days left — Activate Pro"
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

    // Configurable purchase URLs
    static let defaultBuyUrl = "https://dropdial.app/#pricing"
    static let earlyBirdBuyUrl = "https://dropdial.app/#pricing?coupon=FIRST24&buy=1"

    // UserDefaults Keys
    private let licenseKeyStoreKey = "DROPDIAL_LICENSE_KEY"
    private let trialStartDateKey = "DROPDIAL_TRIAL_START_TIME"
    private let trialDurationDays = 3

    var isWithinFirst24Hours: Bool {
        if status.isPro { return false }
        let defaults = UserDefaults.standard
        let trialStart = defaults.double(forKey: trialStartDateKey)
        guard trialStart > 0 else { return true }
        let now = Date().timeIntervalSince1970
        return (now - trialStart) < 86400
    }

    var first24HoursRemainingSeconds: Int {
        let defaults = UserDefaults.standard
        let trialStart = defaults.double(forKey: trialStartDateKey)
        guard trialStart > 0 else { return 86400 }
        let now = Date().timeIntervalSince1970
        let remaining = Int(86400 - (now - trialStart))
        return max(0, remaining)
    }

    var trialRemainingSeconds: Int {
        let defaults = UserDefaults.standard
        let trialStart = defaults.double(forKey: trialStartDateKey)
        guard trialStart > 0 else { return trialDurationDays * 86400 }
        let now = Date().timeIntervalSince1970
        let remaining = Int(Double(trialDurationDays * 86400) - (now - trialStart))
        return max(0, remaining)
    }

    static func formatTimeRemaining(_ totalSeconds: Int) -> String {
        guard totalSeconds > 0 else { return "0s" }
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        let s = totalSeconds % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }

    private(set) var status: LicenseStatus = .trial(daysRemaining: 3)
    var onStatusChanged: (() -> Void)?

    private init() {
        refreshStatus()
    }

    private var periodicCheckTimer: Timer?

    func initialize() {
        refreshStatus()
        periodicCheckTimer?.invalidate()
        periodicCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if case .pro(let info) = self.status, info.expiresAt != nil {
                self.refreshStatus()
            } else if case .trial = self.status, self.isWithinFirst24Hours {
                self.onStatusChanged?()
            }
        }
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
            } else {
                // Key has expired or is invalid! Clear stored key so status reverts
                defaults.removeObject(forKey: licenseKeyStoreKey)
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

        let totalTrialSeconds = Double(trialDurationDays * 86400)
        let secondsElapsed = now - trialStart

        if secondsElapsed >= totalTrialSeconds {
            status = .trialExpired
        } else {
            let secondsRemaining = Int(totalTrialSeconds - secondsElapsed)
            let daysRemaining = max(1, Int(ceil(Double(secondsRemaining) / 86400.0)))
            status = .trial(daysRemaining: daysRemaining)
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

    private let lastTrialExpiredPromptKey = "DROPDIAL_LAST_TRIAL_EXPIRED_PROMPT_DATE"

    func shouldShowTrialExpiredPromptOnLaunch() -> Bool {
        refreshStatus()
        guard case .trialExpired = status else { return false }
        let defaults = UserDefaults.standard
        let todayStr = getTodayDateString()
        let lastPrompt = defaults.string(forKey: lastTrialExpiredPromptKey) ?? ""
        return lastPrompt != todayStr
    }

    func markTrialExpiredPromptShown() {
        let defaults = UserDefaults.standard
        defaults.set(getTodayDateString(), forKey: lastTrialExpiredPromptKey)
    }

    func canPerformConversion(fileCount: Int = 1, isProTool: Bool = false, record: Bool = true) -> (allowed: Bool, reason: String?) {
        refreshStatus()
        if status.isPro {
            return (true, nil)
        }
        if case .trial(let days) = status, days > 0, trialRemainingSeconds > 0 {
            return (true, nil)
        }

        // Trial has expired — Freemium daily hook
        if isProTool {
            return (false, "Tools require DropDial Pro. Upgrade to unlock.")
        }
        if fileCount > 3 {
            return (false, "Batch conversion of \(fileCount) files requires DropDial Pro.")
        }

        let remaining = getDailyConversionsRemaining()
        if remaining > 0 {
            if record {
                recordDailyConversion()
            }
            return (true, nil)
        }

        return (false, "You have reached your 3 free conversions for today. Upgrade to DropDial Pro for unlimited conversions.")
    }

    // MARK: - Offline ECDSA P-256 Key Verification
    func verifyKey(_ licenseKey: String) -> (isValid: Bool, info: LicenseInfo?, error: String?) {
        var trimmed = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"") && trimmed.count >= 2 {
            trimmed = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if trimmed.lowercased().hasPrefix("dd-") && !trimmed.hasPrefix("DD-") {
            trimmed = "DD-" + trimmed.dropFirst(3)
        }

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

        let exp: Double?
        if let expNum = json["exp"] as? Double {
            exp = expNum
        } else if let expInt = json["exp"] as? Int {
            exp = Double(expInt)
        } else if let expNum = json["exp"] as? NSNumber {
            exp = expNum.doubleValue
        } else {
            exp = nil
        }

        if let exp = exp {
            let now = Date().timeIntervalSince1970
            if now >= exp {
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                formatter.timeStyle = .medium
                let dateStr = formatter.string(from: Date(timeIntervalSince1970: exp))
                return (false, nil, "This test license key expired on \(dateStr)")
            }
        }

        let info = LicenseInfo(name: name, email: email, date: date, tier: tier, expiresAt: exp)
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
    private var dismissButton: NSButton!
    private var activeReason: String? = nil

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 280),
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

        let container = LicenseFlippedView(frame: NSRect(x: 0, y: 0, width: 420, height: 280))
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

        dismissButton = NSButton(frame: NSRect(x: (420 - 220) / 2, y: 236, width: 220, height: 22))
        dismissButton.isBordered = false
        dismissButton.title = "Continue with Free (3/day)"
        dismissButton.font = NSFont.systemFont(ofSize: 11.5, weight: .regular)
        dismissButton.contentTintColor = .secondaryLabelColor
        dismissButton.target = self
        dismissButton.action = #selector(dismissTapped)
        dismissButton.isHidden = true
        container.addSubview(dismissButton)

        updateDisplay()
    }

    private var windowUpdateTimer: Timer?

    func show(reason: String? = nil) {
        activeReason = reason
        messageLabel.stringValue = ""
        updateDisplay()

        windowUpdateTimer?.invalidate()
        windowUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, self.window?.isVisible == true else { return }
            self.updateDisplay()
        }

        // If not already Pro and field is empty, autofill if clipboard contains a DD- key
        if case .pro = LicenseManager.shared.status { } else {
            if keyTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if var clip = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !clip.isEmpty {
                    if clip.hasPrefix("\"") && clip.hasSuffix("\"") && clip.count >= 2 {
                        clip = String(clip.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    if clip.lowercased().hasPrefix("dd-") && !clip.hasPrefix("DD-") {
                        clip = "DD-" + clip.dropFirst(3)
                    }
                    if clip.hasPrefix("DD-") {
                        keyTextField.stringValue = clip
                        messageLabel.stringValue = "Key pasted • Click Activate to confirm"
                        messageLabel.textColor = .secondaryLabelColor
                    }
                }
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
            titleLabel.stringValue = "DropDial Pro"
            dismissButton.isHidden = true
            let plan = info.planDisplayName
            let nameStr = info.name.isEmpty ? info.email : info.name
            if let _ = info.expiresAt {
                let sec = info.secondsRemaining
                if sec <= 0 {
                    statusLabel.stringValue = "\(plan) Test License Expired"
                    statusLabel.textColor = .systemRed
                } else if sec < 60 {
                    statusLabel.stringValue = "\(plan) Plan • Licensed to \(nameStr) (\(sec)s left)"
                    statusLabel.textColor = .systemOrange
                } else if sec < 3600 {
                    let m = sec / 60
                    let s = sec % 60
                    statusLabel.stringValue = "\(plan) Plan • Licensed to \(nameStr) (\(m)m \(s)s left)"
                    statusLabel.textColor = .systemOrange
                } else {
                    let h = sec / 3600
                    statusLabel.stringValue = "\(plan) Plan • Licensed to \(nameStr) (\(h)h left)"
                    statusLabel.textColor = .systemOrange
                }
            } else {
                statusLabel.stringValue = "\(plan) Plan • Licensed to \(nameStr)"
                statusLabel.textColor = .secondaryLabelColor
            }

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

        case .trial(let days) where LicenseManager.shared.trialRemainingSeconds > 0:
            titleLabel.stringValue = "DropDial Pro"
            dismissButton.isHidden = true
            if days <= 1 {
                let timeStr = LicenseManager.formatTimeRemaining(LicenseManager.shared.trialRemainingSeconds)
                statusLabel.stringValue = "Last day of free trial • \(timeStr) remaining"
            } else {
                statusLabel.stringValue = "\(days) days remaining in free trial"
            }
            statusLabel.textColor = .secondaryLabelColor

            if LicenseManager.shared.isWithinFirst24Hours {
                let sec = LicenseManager.shared.first24HoursRemainingSeconds
                let h = sec / 3600
                let m = (sec % 3600) / 60
                secondaryButton.title = "Buy (10% Off • \(h)h \(m)m left)"
            } else {
                secondaryButton.title = "Buy License…"
            }
            secondaryButton.action = #selector(buyTapped)
            secondaryButton.isHidden = false

            primaryButton.title = "Activate"
            primaryButton.action = #selector(activateTapped)
            primaryButton.isEnabled = true

        case .trialExpired, .trial:
            titleLabel.stringValue = "Your Free Trial Has Ended"
            let rem = LicenseManager.shared.getDailyConversionsRemaining()
            if let reason = activeReason, !reason.isEmpty {
                statusLabel.stringValue = "\(reason) • Free tier: \(rem)/\(LicenseManager.shared.maxFreeDailyConversions) left today"
            } else {
                statusLabel.stringValue = "Free tier: \(rem)/\(LicenseManager.shared.maxFreeDailyConversions) conversions left today • Upgrade for unlimited"
            }
            statusLabel.textColor = .systemOrange

            keyTextField.isEnabled = true
            pasteButton.isEnabled = true

            secondaryButton.title = "Upgrade to Pro…"
            secondaryButton.action = #selector(buyTapped)
            secondaryButton.isHidden = false

            primaryButton.title = "Activate"
            primaryButton.action = #selector(activateTapped)
            primaryButton.isEnabled = true

            dismissButton.isHidden = false
        }
    }

    @objc private func dismissTapped() {
        window?.close()
    }

    @objc private func pasteKeyTapped() {
        guard var clip = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !clip.isEmpty else {
            messageLabel.stringValue = "Clipboard is empty"
            messageLabel.textColor = .systemOrange
            return
        }
        if clip.hasPrefix("\"") && clip.hasSuffix("\"") && clip.count >= 2 {
            clip = String(clip.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if clip.lowercased().hasPrefix("dd-") && !clip.hasPrefix("DD-") {
            clip = "DD-" + clip.dropFirst(3)
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
        windowUpdateTimer?.invalidate()
        windowUpdateTimer = nil
        window?.close()
    }

    @objc private func activateTapped() {
        var key = keyTextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.hasPrefix("\"") && key.hasSuffix("\"") && key.count >= 2 {
            key = String(key.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if key.lowercased().hasPrefix("dd-") && !key.hasPrefix("DD-") {
            key = "DD-" + key.dropFirst(3)
        }
        keyTextField.stringValue = key

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
            keyTextField.stringValue = ""
            messageLabel.stringValue = "License deactivated."
            messageLabel.textColor = .secondaryLabelColor
            updateDisplay()
        }
    }

    @objc private func buyTapped() {
        let urlStr = LicenseManager.shared.isWithinFirst24Hours ? LicenseManager.earlyBirdBuyUrl : LicenseManager.defaultBuyUrl
        if let url = URL(string: urlStr) {
            NSWorkspace.shared.open(url)
        }
    }
}
