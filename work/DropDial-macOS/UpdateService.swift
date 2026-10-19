import Cocoa

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
final class UpdateService: NSObject, URLSessionDownloadDelegate {
    static let shared = UpdateService()

    private let repoOwner = "Nithin1138"
    private let repoName = "lotus"
    private let releasesApiUrl = "https://api.github.com/repos/Nithin1138/lotus/releases/latest"

    var currentVersion: String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private(set) var latestRelease: ReleaseInfo?
    var onUpdateStatusChanged: (() -> Void)?

    private var downloadTask: URLSessionDownloadTask?
    private var progressWindow: NSWindow?
    private var progressBar: NSProgressIndicator?
    private var progressLabel: NSTextField?

    // MARK: - Version Comparison
    func isNewer(remote: String, local: String) -> Bool {
        let cleanRemote = remote.trimmingCharacters(in: CharacterSet(charactersIn: "vV \t\r\n"))
        let cleanLocal = local.trimmingCharacters(in: CharacterSet(charactersIn: "vV \t\r\n"))

        let rParts = cleanRemote.split(separator: ".").compactMap { Int($0) }
        let lParts = cleanLocal.split(separator: ".").compactMap { Int($0) }

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
        guard let url = URL(string: releasesApiUrl) else { return }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("DropDial-macOS/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15.0

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                if isUserInitiated {
                    DispatchQueue.main.async {
                        self.showFailureAlert(error: error.localizedDescription)
                    }
                }
                return
            }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String else {
                if isUserInitiated {
                    DispatchQueue.main.async {
                        self.showFailureAlert(error: "Invalid response from update server.")
                    }
                }
                return
            }

            let releaseTitle = json["name"] as? String ?? tagName
            let releaseBody = json["body"] as? String ?? ""
            let htmlUrl = json["html_url"] as? String ?? "https://github.com/\(self.repoOwner)/\(self.repoName)/releases/latest"

            // Look for matching macOS asset: prefer .zip for direct in-place update, fallback to .dmg
            var downloadUrl: String?
            var isZip = false
            if let assets = json["assets"] as? [[String: Any]] {
                // First pass: look for macOS .zip
                for a in assets {
                    if let name = a["name"] as? String,
                       let urlStr = a["browser_download_url"] as? String {
                        if name.lowercased().hasSuffix(".zip") && (name.lowercased().contains("mac") || name.lowercased().contains("dropdial")) {
                            downloadUrl = urlStr
                            isZip = true
                            break
                        }
                    }
                }
                // Second pass: if no zip found, look for dmg
                if downloadUrl == nil {
                    for a in assets {
                        if let name = a["name"] as? String,
                           let urlStr = a["browser_download_url"] as? String {
                            if name.lowercased().hasSuffix(".dmg") {
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

            let hasUpdate = self.isNewer(remote: tagName, local: self.currentVersion)

            DispatchQueue.main.async {
                if hasUpdate {
                    self.latestRelease = release
                    self.onUpdateStatusChanged?()

                    // Check if ignored for automatic prompts
                    let ignoredVersion = UserDefaults.standard.string(forKey: "dropdial_ignored_update_version")
                    if !isUserInitiated && ignoredVersion == tagName {
                        // Keep menu bar item updated, but do not nag with a popup
                        return
                    }

                    self.showUpdateAvailableDialog(release: release)
                } else {
                    self.latestRelease = nil
                    self.onUpdateStatusChanged?()
                    if isUserInitiated {
                        self.showUpToDateAlert()
                    }
                }
            }
        }
        task.resume()
    }

    // MARK: - Alerts
    private func showUpdateAvailableDialog(release: ReleaseInfo) {
        let alert = NSAlert()
        alert.messageText = "A New Version of DropDial is Available!"
        
        var notes = release.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if notes.isEmpty {
            notes = "Includes performance improvements and bug fixes."
        }
        if notes.count > 350 {
            notes = String(notes.prefix(350)) + "..."
        }

        alert.informativeText = "Version \(release.tagName) is now available (Current: v\(currentVersion)).\n\nRelease Summary:\n\(notes)"
        alert.alertStyle = .informational

        alert.addButton(withTitle: release.isZip ? "Update Now" : "Download Update")
        alert.addButton(withTitle: "Manual Download (Browser)")
        alert.addButton(withTitle: "Later")

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            if release.isZip && release.downloadUrl != nil {
                startDownloadAndApply(release: release)
            } else {
                openManualDownload(url: release.downloadUrl ?? release.htmlUrl)
            }
        case .alertSecondButtonReturn:
            openManualDownload(url: release.htmlUrl)
        case .alertThirdButtonReturn:
            UserDefaults.standard.set(release.tagName, forKey: "dropdial_ignored_update_version")
        default:
            break
        }
    }

    private func showUpToDateAlert() {
        let alert = NSAlert()
        alert.messageText = "DropDial is Up to Date"
        alert.informativeText = "You are running DropDial v\(currentVersion), which is the latest version available."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showFailureAlert(error: String) {
        let alert = NSAlert()
        alert.messageText = "Check for Updates"
        alert.informativeText = "Could not check for updates:\n\(error)\n\nYou can visit GitHub to check and download updates manually."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Releases Page")
        alert.addButton(withTitle: "Close")

        if alert.runModal() == .alertFirstButtonReturn {
            openManualDownload(url: "https://github.com/\(repoOwner)/\(repoName)/releases")
        }
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
        cancelBtn.frame = NSRect(x: winW - 100, y: 14, width: 80, height: 28)
        cancelBtn.bezelStyle = .rounded
        content.addSubview(cancelBtn)

        let manualBtn = NSButton(title: "Manual Download", target: self, action: #selector(fallbackManualDownload))
        manualBtn.frame = NSRect(x: 18, y: 14, width: 140, height: 28)
        manualBtn.bezelStyle = .rounded
        content.addSubview(manualBtn)

        win.contentView = content
        win.makeKeyAndOrderFront(nil)
        self.progressWindow = win
    }

    @objc private func cancelUpdateDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        progressWindow?.close()
        progressWindow = nil
    }

    @objc private func fallbackManualDownload() {
        cancelUpdateDownload()
        if let rel = latestRelease {
            openManualDownload(url: rel.htmlUrl)
        } else {
            openManualDownload(url: "https://github.com/\(repoOwner)/\(repoName)/releases/latest")
        }
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
            let enumerator = fileManager.enumerator(atPath: extractDir.path)
            while let element = enumerator?.nextObject() as? String {
                if element.hasSuffix("DropDial.app") {
                    newAppPath = extractDir.appendingPathComponent(element).path
                    break
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
            CURRENT_PID="\(currentPid)"
            NEW_APP="\(foundNewApp)"
            TARGET_APP="\(currentAppPath)"

            # Wait for current app to exit
            while kill -0 "$CURRENT_PID" 2>/dev/null; do
                sleep 0.2
            done
            sleep 0.3

            # Replace application bundle
            rm -rf "$TARGET_APP"
            cp -R "$NEW_APP" "$TARGET_APP"
            xattr -dr com.apple.quarantine "$TARGET_APP" 2>/dev/null || true

            # Relaunch the updated app
            open "$TARGET_APP"
            """

            try scriptContent.write(toFile: scriptPath, atomically: true, encoding: .utf8)

            let chmod = Process()
            chmod.executableURL = URL(fileURLWithPath: "/bin/chmod")
            chmod.arguments = ["+x", scriptPath]
            try chmod.run()
            chmod.waitUntilExit()

            // Execute update script detached
            let updater = Process()
            updater.executableURL = URL(fileURLWithPath: "/bin/bash")
            updater.arguments = [scriptPath]
            try updater.run()

            DispatchQueue.main.async {
                self.progressWindow?.close()
                self.progressWindow = nil
                NSApp.terminate(nil)
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.progressWindow?.close()
                self.progressWindow = nil

                let alert = NSAlert()
                alert.messageText = "Auto-Update Could Not Complete"
                alert.informativeText = "An error occurred while installing the update (\(error.localizedDescription)).\n\nWould you like to download the update manually?"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Download in Browser")
                alert.addButton(withTitle: "Cancel")
                if alert.runModal() == .alertFirstButtonReturn {
                    self.fallbackManualDownload()
                }
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error, (error as NSError).code != NSURLErrorCancelled {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.progressWindow?.close()
                self.progressWindow = nil

                let alert = NSAlert()
                alert.messageText = "Download Failed"
                alert.informativeText = "The update download was interrupted: \(error.localizedDescription).\n\nWould you like to download it manually?"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Manual Download")
                alert.addButton(withTitle: "Cancel")
                if alert.runModal() == .alertFirstButtonReturn {
                    self.fallbackManualDownload()
                }
            }
        }
    }
}
