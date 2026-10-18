import Foundation

final class BackendBridge {
    static let shared = BackendBridge()

    private init() {}

    private var cachedPython: String?

    func getPythonPaths(backendDir: String) -> String {
        let bundleURL = Bundle.main.bundleURL
        let repoRoot = bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

        var paths: [String] = [backendDir]
        let candidateSitePackages = [
            bundleURL.appendingPathComponent("Contents/runtime/python/lib/python3.12/site-packages").path,
            bundleURL.appendingPathComponent("Contents/runtime/python/lib/python3.13/site-packages").path,
            bundleURL.appendingPathComponent("Contents/runtime/python/lib/python3.14/site-packages").path,
            repoRoot.appendingPathComponent(".venv/lib/python3.12/site-packages").path,
            repoRoot.appendingPathComponent(".venv/lib/python3.13/site-packages").path,
            repoRoot.appendingPathComponent(".venv/lib/python3.14/site-packages").path,
            FileManager.default.currentDirectoryPath + "/.venv/lib/python3.12/site-packages",
            NSHomeDirectory() + "/Library/Application Support/DropDial/venv/lib/python3.12/site-packages"
        ]

        for p in candidateSitePackages {
            if FileManager.default.fileExists(atPath: p) && !paths.contains(p) {
                paths.append(p)
            }
        }

        if let envPyPath = ProcessInfo.processInfo.environment["PYTHONPATH"], !envPyPath.isEmpty {
            paths.append(envPyPath)
        }

        return paths.joined(separator: ":")
    }

    func findPython() -> String {
        if let cached = cachedPython { return cached }

        let bundleURL = Bundle.main.bundleURL
        let repoRoot = bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        
        let candidates = [
            bundleURL.appendingPathComponent("Contents/runtime/python/bin/python3").path,
            bundleURL.appendingPathComponent("Contents/runtime/python/bin/python").path,
            repoRoot.appendingPathComponent(".venv/bin/python").path,
            FileManager.default.currentDirectoryPath + "/.venv/bin/python",
            NSHomeDirectory() + "/Library/Application Support/DropDial/venv/bin/python3",
            "/opt/homebrew/bin/python3.12",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3.12",
            "/usr/local/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.12/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.13/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.14/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/Current/bin/python3",
            "/usr/bin/python3"
        ]

        // First pass: test each candidate to ensure it can import essential packages (PIL, pypdfium2)
        for path in candidates {
            guard FileManager.default.isExecutableFile(atPath: path) else { continue }
            if verifyPython(path) {
                cachedPython = path
                return path
            }
        }

        // Second pass: fallback to any working python executable
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                cachedPython = path
                return path
            }
        }
        return "python3"
    }

    private func verifyPython(_ path: String) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = ["-c", "import PIL, pypdfium2"]
        let worker = findWorkerScript()
        let backendDir = (worker as NSString).deletingLastPathComponent
        var env = ProcessInfo.processInfo.environment
        env["PYTHONPATH"] = getPythonPaths(backendDir: backendDir)
        proc.environment = env
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        } catch {
            return false
        }
    }

    static func cleanErrorMessage(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Processing failed" }

        // Break into lines and remove empty/whitespace lines
        let lines = trimmed.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return "Processing failed" }

        // Find the last line that isn't internal traceback mechanics
        var candidateLine = lines.last ?? trimmed
        for line in lines.reversed() {
            if line.hasPrefix("Traceback") || line.hasPrefix("File \"") || line.hasPrefix("During handling of") {
                continue
            }
            candidateLine = line
            break
        }

        // Clean up common exception prefixes
        var message = candidateLine
        let prefixes = [
            "ValueError: ", "TypeError: ", "RuntimeError: ", "IOError: ",
            "OSError: ", "Exception: ", "KeyError: ", "IndexError: "
        ]
        for prefix in prefixes {
            if message.hasPrefix(prefix) {
                message = String(message.dropFirst(prefix.count))
                break
            }
        }

        // Pattern matching for user-friendly error translations
        if message.contains("No module named") || candidateLine.contains("ModuleNotFoundError") {
            if let range = message.range(of: "'[a-zA-Z0-9_]+'", options: .regularExpression) {
                let mod = String(message[range]).trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
                return "Missing required component (\(mod)). Please restart the app."
            }
            return "Missing internal component. Please restart the app."
        }

        if message.contains("FileNotFoundError") || message.contains("No such file or directory") {
            return "File could not be found or was moved."
        }

        if message.contains("PermissionError") || message.contains("Permission denied") {
            return "Permission denied when accessing or saving file."
        }

        if message.contains("MemoryError") {
            return "File is too large to process in memory."
        }

        if message.contains("This document conversion is not supported") {
            return "This document conversion is not supported."
        }

        if message.contains("This PDF has no selectable text") {
            return "This PDF has no selectable text; scanned documents need OCR."
        }

        if message.contains("Cannot reach the target size") {
            return "Cannot reach target size; try adjusting compression settings."
        }

        // Filter out any raw path tracebacks starting with /Library or /usr or /opt
        if message.hasPrefix("/") || message.contains("/Library/Frameworks") || message.contains(".framework/") {
            return "Conversion failed for this file format."
        }

        if message.count > 100 {
            message = String(message.prefix(97)) + "..."
        }

        return message
    }

    func findWorkerScript() -> String {
        let bundleURL = Bundle.main.bundleURL
        let bundleBackend = bundleURL.appendingPathComponent("Contents/backend/worker.py").path
        if FileManager.default.fileExists(atPath: bundleBackend) {
            return bundleBackend
        }

        let insideResources = Bundle.main.resourceURL?.appendingPathComponent("backend/worker.py").path
        if let path = insideResources, FileManager.default.fileExists(atPath: path) {
            return path
        }
        
        let repoRoot = bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let localPath = repoRoot.appendingPathComponent("work/DropDial/backend/worker.py").path
        if FileManager.default.fileExists(atPath: localPath) {
            return localPath
        }

        let currentDirScript = FileManager.default.currentDirectoryPath + "/work/DropDial/backend/worker.py"
        if FileManager.default.fileExists(atPath: currentDirScript) {
            return currentDirScript
        }

        return "worker.py"
    }

    @discardableResult
    func execute(
        job: ConversionJob,
        onStart: ((Process) -> Void)? = nil,
        progressHandler: ((JobProgress) -> Void)? = nil,
        completion: @escaping (Result<BatchResult, Error>) -> Void
    ) -> Process? {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("dropdial-job-" + UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let requestFile = tempDir.appendingPathComponent("request.json")
        let resultFile = tempDir.appendingPathComponent("result.json")
        let progressFile = resultFile.appendingPathExtension("progress")

        do {
            let encoder = JSONEncoder()
            let jobData = try encoder.encode(job)
            try jobData.write(to: requestFile)
        } catch {
            completion(.failure(error))
            return nil
        }

        let python = findPython()
        let worker = findWorkerScript()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = [worker, "--job", requestFile.path, resultFile.path]

        var env = ProcessInfo.processInfo.environment
        env["DROPDIAL_LANG"] = "en"
        let extraPaths = [
            "/Library/Frameworks/Python.framework/Versions/Current/bin",
            "/Library/Frameworks/Python.framework/Versions/3.14/bin",
            "/Library/Frameworks/Python.framework/Versions/3.13/bin",
            "/Library/Frameworks/Python.framework/Versions/3.12/bin",
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        let backendDir = (worker as NSString).deletingLastPathComponent
        let existingPath = env["PATH"] ?? ""
        env["PATH"] = ([backendDir] + extraPaths + [existingPath]).joined(separator: ":")
        env["PYTHONPATH"] = getPythonPaths(backendDir: backendDir)

        if let customOutput = UserDefaults.standard.string(forKey: "DROPDIAL_OUTPUT_DIR"), !customOutput.isEmpty {
            env["DROPDIAL_OUTPUT_DIR"] = customOutput
        }
        process.environment = env

        let errorPipe = Pipe()
        process.standardError = errorPipe

        var progressTimer: DispatchSourceTimer?
        if let progressHandler = progressHandler {
            let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
            timer.schedule(deadline: .now(), repeating: .milliseconds(200))
            timer.setEventHandler {
                guard FileManager.default.fileExists(atPath: progressFile.path),
                      let data = try? Data(contentsOf: progressFile),
                      let prog = try? JSONDecoder().decode(JobProgress.self, from: data) else {
                    return
                }
                DispatchQueue.main.async {
                    progressHandler(prog)
                }
            }
            timer.resume()
            progressTimer = timer
        }

        process.terminationHandler = { proc in
            progressTimer?.cancel()
            progressTimer = nil

            DispatchQueue.main.async {
                if proc.terminationStatus == 0 && FileManager.default.fileExists(atPath: resultFile.path) {
                    do {
                        let data = try Data(contentsOf: resultFile)
                        let batch = try JSONDecoder().decode(BatchResult.self, from: data)
                        completion(.success(batch))
                    } catch {
                        completion(.failure(error))
                    }
                } else {
                    let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let errText = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let clean = BackendBridge.cleanErrorMessage(errText)
                    completion(.failure(NSError(domain: "DropDial", code: Int(proc.terminationStatus), userInfo: [NSLocalizedDescriptionKey: clean])))
                }

                try? FileManager.default.removeItem(at: tempDir)
            }
        }

        do {
            try process.run()
            onStart?(process)
            return process
        } catch {
            progressTimer?.cancel()
            completion(.failure(error))
            return nil
        }
    }

    func inspect(path: String, completion: @escaping (Result<InspectResult, Error>) -> Void) {
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("dropdial-inspect-" + UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let resultFile = tempDir.appendingPathComponent("inspect.json")

        let python = findPython()
        let worker = findWorkerScript()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = [worker, "--inspect", path, resultFile.path, tempDir.path, "-1"]

        var env = ProcessInfo.processInfo.environment
        env["DROPDIAL_LANG"] = "en"
        let backendDir = (worker as NSString).deletingLastPathComponent
        let extraPaths = [
            "/Library/Frameworks/Python.framework/Versions/Current/bin",
            "/Library/Frameworks/Python.framework/Versions/3.14/bin",
            "/Library/Frameworks/Python.framework/Versions/3.13/bin",
            "/Library/Frameworks/Python.framework/Versions/3.12/bin",
            "/usr/local/bin",
            "/opt/homebrew/bin",
            "/usr/bin",
            "/bin"
        ]
        let existingPath = env["PATH"] ?? ""
        env["PATH"] = ([backendDir] + extraPaths + [existingPath]).joined(separator: ":")
        env["PYTHONPATH"] = getPythonPaths(backendDir: backendDir)
        process.environment = env

        let errorPipe = Pipe()
        process.standardError = errorPipe

        process.terminationHandler = { proc in
            DispatchQueue.main.async {
                if proc.terminationStatus == 0 && FileManager.default.fileExists(atPath: resultFile.path) {
                    do {
                        let data = try Data(contentsOf: resultFile)
                        let result = try JSONDecoder().decode(InspectResult.self, from: data)
                        completion(.success(result))
                    } catch {
                        completion(.failure(error))
                    }
                } else {
                    let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let errText = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let clean = BackendBridge.cleanErrorMessage(errText.isEmpty ? "Failed to inspect file" : errText)
                    completion(.failure(NSError(domain: "DropDial", code: Int(proc.terminationStatus), userInfo: [NSLocalizedDescriptionKey: clean])))
                }
            }
        }

        do {
            try process.run()
        } catch {
            completion(.failure(error))
        }
    }
}
