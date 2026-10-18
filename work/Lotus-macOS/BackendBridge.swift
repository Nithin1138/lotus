import Foundation

final class BackendBridge {
    static let shared = BackendBridge()

    private init() {}

    private var cachedPython: String?

    func findPython() -> String {
        if let cached = cachedPython { return cached }

        let bundleURL = Bundle.main.bundleURL
        let repoRoot = bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        
        let candidates = [
            bundleURL.appendingPathComponent("Contents/runtime/python/bin/python3").path,
            repoRoot.appendingPathComponent(".venv/bin/python").path,
            FileManager.default.currentDirectoryPath + "/.venv/bin/python",
            "/Library/Frameworks/Python.framework/Versions/Current/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.14/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.13/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.12/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
            "/opt/homebrew/bin/python3",
            "/opt/homebrew/bin/python3.12"
        ]

        // First pass: test each candidate to ensure it can import PIL
        for path in candidates {
            guard FileManager.default.isExecutableFile(atPath: path) else { continue }
            if verifyPython(path) {
                cachedPython = path
                return path
            }
        }

        // Fallback: return first existing executable
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
        proc.arguments = ["-c", "import PIL"]
        do {
            try proc.run()
            proc.waitUntilExit()
            return proc.terminationStatus == 0
        } catch {
            return false
        }
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
        let localPath = repoRoot.appendingPathComponent("work/Lotus/backend/worker.py").path
        if FileManager.default.fileExists(atPath: localPath) {
            return localPath
        }

        let currentDirScript = FileManager.default.currentDirectoryPath + "/work/Lotus/backend/worker.py"
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
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("lotus-job-" + UUID().uuidString)
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
        env["LOTUS_LANG"] = "en"
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
        let existingPath = env["PATH"] ?? ""
        env["PATH"] = (extraPaths + [existingPath]).joined(separator: ":")
        let backendDir = (worker as NSString).deletingLastPathComponent
        env["PYTHONPATH"] = backendDir

        if let customOutput = UserDefaults.standard.string(forKey: "LOTUS_OUTPUT_DIR"), !customOutput.isEmpty {
            env["LOTUS_OUTPUT_DIR"] = customOutput
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
                    let message = errText.isEmpty ? "Processing failed" : errText
                    completion(.failure(NSError(domain: "Lotus", code: Int(proc.terminationStatus), userInfo: [NSLocalizedDescriptionKey: message])))
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
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("lotus-inspect-" + UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let resultFile = tempDir.appendingPathComponent("inspect.json")

        let python = findPython()
        let worker = findWorkerScript()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = [worker, "--inspect", path, resultFile.path, tempDir.path, "-1"]

        var env = ProcessInfo.processInfo.environment
        env["LOTUS_LANG"] = "en"
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
                    let errText = String(data: errData, encoding: .utf8) ?? "Failed to inspect file"
                    completion(.failure(NSError(domain: "Lotus", code: Int(proc.terminationStatus), userInfo: [NSLocalizedDescriptionKey: errText])))
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
