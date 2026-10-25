import Cocoa
import UserNotifications

// MARK: - Update Information Model
struct ReleaseInfo {
    let tagName: String
    let name: String
    let body: String
    let htmlUrl: String
    let downloadUrl: String?
    let isZip: Bool
}

// MARK: - Update Service
final class UpdateService: NSObject, URLSessionDownloadDelegate, UNUserNotificationCenterDelegate {
    static let shared = UpdateService()

    private let releasesApiUrl = "https://dropdial.app/api/releases"
    private let fallbackReleasesApiUrl = "https://dropdial.app/api/releases/latest"
    private let githubReleasesApiUrl = "https://api.github.com/repos/Nithin1138/lotus/releases/latest"

    static func formatVersion(_ raw: String) -> String {
        var clean = raw.trimmingCharacters(in: CharacterSet(charactersIn: "vV \t\r\n"))
        let parts = clean.split(separator: ".")
        if parts.count == 4 && parts[3] == "0" {
            clean = "\(parts[0]).\(parts[1]).\(parts[2])"
        }
        return clean.isEmpty ? "v1.0.1" : "v\(clean)"
    }

    var currentVersion: String {
        let raw = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.1"
        return UpdateService.formatVersion(raw)
    }

    private let kLastAppliedTag = "dropdial_last_applied_update_tag"
    private let kSnoozedTag = "dropdial_snoozed_update_tag"
    private let kSnoozedTimestamp = "dropdial_snoozed_update_time"

    private var hasPromptedInCurrentRun = false

    private(set) var latestRelease: ReleaseInfo?
    var onUpdateStatusChanged: (() -> Void)?

    private var downloadTask: URLSessionDownloadTask?
    private var progressWindow: NSWindow?
    private var progressBar: NSProgressIndicator?
    private var progressLabel: NSTextField?

    private var isShowingPrompt = false
    private var isUpdating = false
    private var sessionDismissedVersion: String?

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - Version Comparison
    static func parseVersionComponents(_ v: String) -> [Int] {
        let clean = v.trimmingCharacters(in: CharacterSet(charactersIn: "vV \t\r\n"))
        var parts = clean.split(separator: ".").compactMap { Int($0) }
        while parts.count > 1 && parts.last == 0 {
            parts.removeLast()
        }
        return parts
    }

    func isNewer(remote: String, local: String) -> Bool {
        let rParts = UpdateService.parseVersionComponents(remote)
        let lParts = UpdateService.parseVersionComponents(local)

        let count = max(rParts.count, lParts.count)
        for i in 0..<count {
            let r = i < rParts.count ? rParts[i] : 0
            let l = i < lParts.count ? lParts[i] : 0
            if r > l { return true }
            if r < l { return false }
        }
        return false
    }

    // MARK: - Check For Updates
    func checkForUpdates(isUserInitiated: Bool) {
        fetchReleaseData(urlString: releasesApiUrl) { [weak self] release, error, is404 in
            guard let self = self else { return }
            if let release = release {
                self.handleReleaseResult(release: release, isUserInitiated: isUserInitiated)
            } else if is404 {
                DispatchQueue.main.async {
                    self.latestRelease = nil
                    self.onUpdateStatusChanged?()
                    if isUserInitiated {
                        self.showUpToDateAlert()
                    }
                }
            } else {
                // Try fallback to secondary dropdial.app release endpoint
                self.fetchReleaseData(urlString: self.fallbackReleasesApiUrl) { [weak self] fbRelease, fbError, fbIs404 in
                    guard let self = self else { return }
                    if let fbRelease = fbRelease {
                        self.handleReleaseResult(release: fbRelease, isUserInitiated: isUserInitiated)
                    } else {
                        // Optional fallback to GitHub if available
                        self.fetchReleaseData(urlString: self.githubReleasesApiUrl) { [weak self] ghRelease, _, ghIs404 in
                            guard let self = self else { return }
                            if let ghRelease = ghRelease {
                                self.handleReleaseResult(release: ghRelease, isUserInitiated: isUserInitiated)
                            } else {
                                DispatchQueue.main.async {
                                    if fbIs404 || ghIs404 {
                                        self.latestRelease = nil
                                        self.onUpdateStatusChanged?()
                                        if isUserInitiated {
                                            self.showUpToDateAlert()
                                        }
                                    } else if isUserInitiated {
                                        self.showConnectionAlert()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func fetchReleaseData(urlString: String, completion: @escaping (ReleaseInfo?, Error?, Bool) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(nil, nil, false)
            return
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("DropDial-macOS/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 12.0

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(nil, error, false)
                return
            }

            let http = response as? HTTPURLResponse
            if let status = http?.statusCode, status == 404 {
                completion(nil, nil, true)
                return
            }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else {
                completion(nil, nil, false)
                return
            }

            let releaseTitle = json["name"] as? String ?? tagName
            let releaseBody = json["body"] as? String ?? ""
            let htmlUrl = json["html_url"] as? String ?? "https://dropdial.app"

            var downloadUrl: String?
            var isZip = false
            if let assets = json["assets"] as? [[String: Any]] {
                // Priority 1: Specifically find macOS zip archive (e.g. DropDial-macOS.zip)
                for a in assets {
                    if let name = a["name"] as? String,
                       let urlStr = a["browser_download_url"] as? String {
                        let lower = name.lowercased()
                        let isMac = lower.contains("mac") || lower.contains("darwin") || lower.contains("apple") || lower == "dropdial.zip"
                        let isWindows = lower.contains("win") || lower.contains("setup") || lower.hasSuffix(".exe")
                        if lower.hasSuffix(".zip") && isMac && !isWindows {
                            downloadUrl = urlStr
                            isZip = true
                            break
                        }
                    }
                }
                // Priority 2: Fallback to macOS DMG (e.g. DropDial.dmg)
                if downloadUrl == nil {
                    for a in assets {
                        if let name = a["name"] as? String,
                           let urlStr = a["browser_download_url"] as? String {
                            let lower = name.lowercased()
                            let isWindows = lower.contains("win") || lower.contains("setup") || lower.hasSuffix(".exe")
                            if lower.hasSuffix(".dmg") && !isWindows {
                                downloadUrl = urlStr
                                isZip = false
                                break
                            }
                        }
                    }
                }
            }

            let release = ReleaseInfo(
                tagName: tagName,
                name: releaseTitle,
                body: releaseBody,
                htmlUrl: htmlUrl,
                downloadUrl: downloadUrl,
                isZip: isZip
            )
            completion(release, nil, false)
        }
        task.resume()
    }

    private(set) var hasPendingPrompt = false

    private func handleReleaseResult(release: ReleaseInfo, isUserInitiated: Bool) {
        let hasUpdate = isNewer(remote: release.tagName, local: currentVersion)

        // 1. Anti-loop check: Check if this release tag was already applied / installed
        let lastAppliedTag = UserDefaults.standard.string(forKey: kLastAppliedTag)
        let isAlreadyApplied = (lastAppliedTag != nil && lastAppliedTag == release.tagName)

        // 2. Snooze check: Check if snoozed by user in the last 24 hours
        let snoozedTag = UserDefaults.standard.string(forKey: kSnoozedTag)
        let snoozedTime = UserDefaults.standard.double(forKey: kSnoozedTimestamp)
        let isSnoozed = (snoozedTag == release.tagName && (Date().timeIntervalSince1970 - snoozedTime) < 86400)

        DispatchQueue.main.async {
            if hasUpdate && !isAlreadyApplied {
                self.latestRelease = release
                self.onUpdateStatusChanged?()

                if isUserInitiated {
                    // User explicitly tapped "Check for Updates" -> show prompt immediately
                    self.hasPendingPrompt = false
                    self.showUpdateAvailableDialog(release: release)
                } else {
                    // Background check: DO NOT interrupt the user while working in other apps!
                    // And do not re-prompt if already applied, snoozed, or already prompted in this active run
                    if !isSnoozed && self.sessionDismissedVersion != release.tagName && !self.hasPromptedInCurrentRun {
                        self.hasPendingPrompt = true
                    } else {
                        self.hasPendingPrompt = false
                    }
                }
            } else {
                self.latestRelease = nil
                self.hasPendingPrompt = false
                self.onUpdateStatusChanged?()
                if isUserInitiated {
                    self.showUpToDateAlert()
                }
            }
        }
    }

    func promptIfPending() {
        guard hasPendingPrompt, let release = latestRelease else { return }
        guard !isShowingPrompt && !isUpdating else { return }
        if sessionDismissedVersion == release.tagName || hasPromptedInCurrentRun {
            hasPendingPrompt = false
            return
        }
        hasPendingPrompt = false
        hasPromptedInCurrentRun = true
        showUpdateAvailableDialog(release: release)
    }

    func dismissForSession(tagName: String) {
        sessionDismissedVersion = tagName
        hasPendingPrompt = false
    }

    private func postUpdateNotification(release: ReleaseInfo) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "DropDial Update Available"
            content.body = "Version \(UpdateService.formatVersion(release.tagName)) is ready to install. Click to update now."
            content.sound = .default
            let request = UNNotificationRequest(identifier: "dropdial_update_available", content: content, trigger: nil)
            center.add(request, withCompletionHandler: nil)
        }
    }

    // MARK: - UNUserNotificationCenterDelegate
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if let release = self.latestRelease {
                self.showUpdateAvailableDialog(release: release)
            } else {
                self.checkForUpdates(isUserInitiated: true)
            }
        }
        completionHandler()
    }

    // MARK: - Alerts
    func showUpdateAvailableDialog(release: ReleaseInfo) {
        guard !isShowingPrompt && !isUpdating else { return }
        isShowingPrompt = true
        hasPendingPrompt = false
        hasPromptedInCurrentRun = true
        defer { isShowingPrompt = false }

        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "A New Version of DropDial is Available!"
        
        let current = UpdateService.formatVersion(currentVersion)
        let available = UpdateService.formatVersion(release.tagName)

        alert.informativeText = "Current version: \(current)\nAvailable version: \(available)\n\nWould you like to download and install this update now?"
        alert.alertStyle = .informational

        alert.addButton(withTitle: "Update Now")
        alert.addButton(withTitle: "Later")

        alert.window.level = .floating
        alert.window.center()
        alert.window.orderFrontRegardless()
        alert.window.makeKeyAndOrderFront(nil)

        let response = alert.runModal()
        NSApp.setActivationPolicy(.accessory)

        switch response {
        case .alertFirstButtonReturn:
            sessionDismissedVersion = nil
            hasPendingPrompt = false
            UserDefaults.standard.set(release.tagName, forKey: kLastAppliedTag)
            UserDefaults.standard.synchronize()
            if release.isZip && release.downloadUrl != nil {
                startDownloadAndApply(release: release)
            } else if let dl = release.downloadUrl ?? URL(string: release.htmlUrl)?.absoluteString {
                openManualDownload(url: dl)
            }
        case .alertSecondButtonReturn:
            // Snooze for 24h and for this active running session
            UserDefaults.standard.set(release.tagName, forKey: kSnoozedTag)
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: kSnoozedTimestamp)
            UserDefaults.standard.synchronize()
            sessionDismissedVersion = release.tagName
            hasPendingPrompt = false
        default:
            hasPendingPrompt = false
            break
        }
    }

    private func showUpToDateAlert() {
        let alert = NSAlert()
        alert.messageText = "DropDial is Up to Date"
        alert.informativeText = "You are running DropDial \(UpdateService.formatVersion(currentVersion)), which is the latest version available."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showConnectionAlert() {
        let alert = NSAlert()
        alert.messageText = "Check for Updates"
        alert.informativeText = "Unable to check for updates. Please check your internet connection."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func openManualDownload(url: String) {
        if let targetUrl = URL(string: url) {
            NSWorkspace.shared.open(targetUrl)
        }
    }

    // MARK: - Auto Update Download & Apply
    private func startDownloadAndApply(release: ReleaseInfo) {
        guard let downloadUrlStr = release.downloadUrl,
              let downloadUrl = URL(string: downloadUrlStr) else {
            openManualDownload(url: release.htmlUrl)
            return
        }

        isUpdating = true
        showProgressUI(version: release.tagName)

        let sessionConfig = URLSessionConfiguration.default
        let session = URLSession(configuration: sessionConfig, delegate: self, delegateQueue: nil)
        downloadTask = session.downloadTask(with: downloadUrl)
        downloadTask?.resume()
    }

    private func showProgressUI(version: String) {
        let winW: CGFloat = 360
        let winH: CGFloat = 140

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: winW, height: winH),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        win.title = "DropDial Update"
        win.center()
        win.isReleasedWhenClosed = false
        win.level = .floating

        let content = NSView(frame: NSRect(x: 0, y: 0, width: winW, height: winH))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor(white: 0.12, alpha: 0.98).cgColor

        let label = NSTextField(labelWithString: "Downloading DropDial \(version)...")
        label.frame = NSRect(x: 24, y: winH - 42, width: winW - 48, height: 20)
        label.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .white
        content.addSubview(label)
        self.progressLabel = label

        let bar = NSProgressIndicator(frame: NSRect(x: 24, y: winH - 74, width: winW - 48, height: 16))
        bar.isIndeterminate = false
        bar.minValue = 0.0
        bar.maxValue = 1.0
        bar.doubleValue = 0.0
        content.addSubview(bar)
        self.progressBar = bar

        let cancelBtn = NSButton(title: "Cancel", target: self, action: #selector(cancelUpdateDownload))
        cancelBtn.frame = NSRect(x: (winW - 100) / 2, y: 14, width: 100, height: 28)
        cancelBtn.bezelStyle = .rounded
        content.addSubview(cancelBtn)

        win.contentView = content
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.progressWindow = win
    }

    @objc private func cancelUpdateDownload() {
        isUpdating = false
        downloadTask?.cancel()
        downloadTask = nil
        progressWindow?.close()
        progressWindow = nil
    }

    // MARK: - URLSessionDownloadDelegate
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        DispatchQueue.main.async { [weak self] in
            self?.progressBar?.doubleValue = progress
            let mbWritten = Double(totalBytesWritten) / (1024 * 1024)
            let mbTotal = Double(totalBytesExpectedToWrite) / (1024 * 1024)
            self?.progressLabel?.stringValue = String(format: "Downloading: %.1f MB / %.1f MB (%.0f%%)", mbWritten, mbTotal, progress * 100)
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        DispatchQueue.main.async { [weak self] in
            self?.progressLabel?.stringValue = "Extracting & preparing update..."
            self?.progressBar?.isIndeterminate = true
            self?.progressBar?.startAnimation(nil)
        }

        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent("DropDial_Update_\(UUID().uuidString)")

        do {
            try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let localZip = tempDir.appendingPathComponent("update.zip")
            try fileManager.copyItem(at: location, to: localZip)

            // Extract with native macOS ditto
            let extractDir = tempDir.appendingPathComponent("extracted")
            try fileManager.createDirectory(at: extractDir, withIntermediateDirectories: true)

            let ditto = Process()
            ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            ditto.arguments = ["-xk", localZip.path, extractDir.path]
            try ditto.run()
            ditto.waitUntilExit()

            // Find DropDial.app in extracted folder
            var newAppPath: String?
            let directApp = extractDir.appendingPathComponent("DropDial.app")
            if fileManager.fileExists(atPath: directApp.path) {
                newAppPath = directApp.path
            } else {
                let enumerator = fileManager.enumerator(atPath: extractDir.path)
                while let element = enumerator?.nextObject() as? String {
                    if element.hasSuffix("DropDial.app") {
                        newAppPath = extractDir.appendingPathComponent(element).path
                        break
                    }
                }
            }

            guard let foundNewApp = newAppPath, fileManager.fileExists(atPath: foundNewApp) else {
                throw NSError(domain: "DropDialUpdater", code: -1, userInfo: [NSLocalizedDescriptionKey: "DropDial.app not found in update archive."])
            }

            let currentAppPath = Bundle.main.bundleURL.path
            let currentPid = ProcessInfo.processInfo.processIdentifier

            // Write helper shell script to swap bundles and relaunch
            let scriptPath = tempDir.appendingPathComponent("apply_update.sh").path
            let scriptContent = """
            #!/bin/bash
            exec > /tmp/dropdial_update.log 2>&1
            CURRENT_PID="$1"
            NEW_APP="$2"
            TARGET_APP="$3"

            echo "[DropDial Updater] Starting update at $(date)"
            echo "[DropDial Updater] Current PID: $CURRENT_PID"
            echo "[DropDial Updater] New App: $NEW_APP"
            echo "[DropDial Updater] Target App: $TARGET_APP"

            # Wait for current app to exit
            for i in {1..50}; do
                if ! kill -0 "$CURRENT_PID" 2>/dev/null; then
                    break
                fi
                sleep 0.2
            done
            sleep 0.5

            # Replace application bundle
            echo "[DropDial Updater] Removing existing bundle..."
            rm -rf "$TARGET_APP"
            echo "[DropDial Updater] Copying new bundle..."
            cp -R "$NEW_APP" "$TARGET_APP"
            xattr -dr com.apple.quarantine "$TARGET_APP" 2>/dev/null || true
            chmod -R +x "$TARGET_APP/Contents/MacOS" "$TARGET_APP/Contents/backend" 2>/dev/null || true

            # Relaunch the updated app
            echo "[DropDial Updater] Relaunching..."
            open "$TARGET_APP"
            echo "[DropDial Updater] Complete."
            """

            try scriptContent.write(toFile: scriptPath, atomically: true, encoding: .utf8)

            let chmod = Process()
            chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
            chmod.arguments = ["+x", scriptPath]
            try chmod.run()
            chmod.waitUntilExit()

            // Execute update script detached with explicit arguments
            let updater = Process()
            updater.executableURL = URL(fileURLWithPath: "/bin/bash")
            updater.arguments = [scriptPath, "\(currentPid)", foundNewApp, currentAppPath]
            try updater.run()

            DispatchQueue.main.async {
                self.progressWindow?.close()
                self.progressWindow = nil
                NSApp.terminate(nil)
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.isUpdating = false
                self.progressWindow?.close()
                self.progressWindow = nil

                let alert = NSAlert()
                alert.messageText = "Update Failed"
                alert.informativeText = "An error occurred while installing the update (\(error.localizedDescription))."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isUpdating = false
            if let error = error, (error as NSError).code != NSURLErrorCancelled {
                self.progressWindow?.close()
                self.progressWindow = nil

                let alert = NSAlert()
                alert.messageText = "Download Failed"
                alert.informativeText = "The update download was interrupted: \(error.localizedDescription)."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }
}
