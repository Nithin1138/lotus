using System;
using System.Diagnostics;
using System.IO;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace DropDial;

internal static class Backend
{
    private static bool _envChecked;
    private static readonly object _envLock = new();

    public static void EnsureEnvironment()
    {
        if (_envChecked) return;
        lock (_envLock)
        {
            if (_envChecked) return;
            _envChecked = true;
            try
            {
                string baseDir = AppContext.BaseDirectory;
                string bundledPython = Path.Combine(baseDir, "runtime", "python", "python.exe");
                if (File.Exists(bundledPython)) return;

                string pythonExe = FindPythonExecutable();
                var check = new ProcessStartInfo(pythonExe, "-c \"import pymupdf, pypdfium2\"")
                {
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardError = true,
                    RedirectStandardOutput = true
                };
                using var p = Process.Start(check);
                p?.WaitForExit(3500);
                if (p == null || p.ExitCode != 0)
                {
                    string reqFile = Path.Combine(baseDir, "requirements-runtime.txt");
                    string args = File.Exists(reqFile)
                        ? $"-m pip install --disable-pip-version-check -r \"{reqFile}\""
                        : "-m pip install --disable-pip-version-check pymupdf pillow pypdf pypdfium2 pdf2docx python-docx python-pptx openpyxl";

                    var install = new ProcessStartInfo(pythonExe, args)
                    {
                        UseShellExecute = false,
                        CreateNoWindow = true,
                        RedirectStandardError = true,
                        RedirectStandardOutput = true
                    };
                    using var ip = Process.Start(install);
                    ip?.WaitForExit(90000);
                }
            }
            catch { }
        }
    }

    private static string? _cachedPythonExe;

    public static string FindPythonExecutable()
    {
        if (_cachedPythonExe != null) return _cachedPythonExe;
        string baseDir = AppContext.BaseDirectory;
        string[] candidates = [
            Path.Combine(baseDir, "runtime", "python", "python.exe"),
            Path.Combine(baseDir, "runtime", "python.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "Python", "Python313", "python.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "Python", "Python312", "python.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "Python", "Python311", "python.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "Python", "Python310", "python.exe"),
            "python.exe"
        ];
        foreach (var c in candidates)
        {
            if (File.Exists(c))
            {
                _cachedPythonExe = c;
                return c;
            }
        }
        _cachedPythonExe = "python.exe";
        return _cachedPythonExe;
    }

    public static ProcessStartInfo StartInfo(params string[] arguments)
    {
        string baseDir = AppContext.BaseDirectory;
        string pythonExe = FindPythonExecutable();
        var info = new ProcessStartInfo(pythonExe) { UseShellExecute = false, CreateNoWindow = true, RedirectStandardError = true, RedirectStandardOutput = true, WorkingDirectory = baseDir };
        info.ArgumentList.Add(Path.Combine(baseDir, "backend", "worker.py"));

        string sitePackages = Path.Combine(baseDir, "runtime", "python", "Lib", "site-packages");
        if (Directory.Exists(sitePackages))
        {
            string existingPpath = Environment.GetEnvironmentVariable("PYTHONPATH") ?? "";
            info.Environment["PYTHONPATH"] = string.IsNullOrEmpty(existingPpath) ? sitePackages : sitePackages + Path.PathSeparator + existingPpath;
        }

        string ffmpegDir = Path.Combine(baseDir, "runtime", "ffmpeg");
        string sevenZipDir = Path.Combine(baseDir, "runtime", "7zip");
        string existingPath = Environment.GetEnvironmentVariable("PATH") ?? "";
        string newPath = existingPath;
        if (Directory.Exists(ffmpegDir)) newPath = ffmpegDir + Path.PathSeparator + newPath;
        if (Directory.Exists(sevenZipDir)) newPath = sevenZipDir + Path.PathSeparator + newPath;
        info.Environment["PATH"] = newPath;

        // Messages from the engine (errors, page headings in text exports) follow the app's language.
        info.Environment["DROPDIAL_LANG"] = L.Language;
        // Optimized pycache directory to allow fast module import
        string pyCache = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DropDial", "pycache");
        try { Directory.CreateDirectory(pyCache); } catch { }
        info.Environment["PYTHONPYCACHEPREFIX"] = pyCache;
        info.Environment["PYTHONOPTIMIZE"] = "1";
        info.Environment["PYTHONDONTWRITEBYTECODE"] = "0";
        // Results go where the user chose (tray menu); an empty value means next to the source file.
        info.Environment["DROPDIAL_OUTPUT_DIR"] = OutputFolder.Current ?? "";
        foreach (string arg in arguments)
            info.ArgumentList.Add(arg);
        return info;
    }
    // jobToken tags the worker's staging files, so cleaning up after a cancel touches only this job's files.
    public static async Task Run(string[] arguments, CancellationToken cancellation = default, Action<Process>? onStart = null, IProgress<JobProgress>? progress = null, string? jobToken = null)
    {
        using var watch = arguments.Length >= 3 && arguments[0] == "--job" ? WatchProgress(arguments[2], progress) : null;
        var start = StartInfo(arguments);
        if (jobToken != null)
            start.Environment["DROPDIAL_JOB"] = jobToken;
        using var process = Process.Start(start) ?? throw new IOException(L.T("Could not start the local processing engine"));
        onStart?.Invoke(process);
        var error = process.StandardError.ReadToEndAsync();
        var output = process.StandardOutput.ReadToEndAsync();
        try
        { await process.WaitForExitAsync(cancellation).ConfigureAwait(false); }
        catch (OperationCanceledException) { if (!process.HasExited) process.Kill(true); throw; }
        await output.ConfigureAwait(false);
        if (process.ExitCode != 0)
        {
            string detail = await error.ConfigureAwait(false);
            // The engine writes its own message into the result file when it stops on an error.
            try
            {
                if (arguments.Length > 2 && File.Exists(arguments[2]))
                {
                    using var json = JsonDocument.Parse(File.ReadAllText(arguments[2]));
                    if (json.RootElement.TryGetProperty("Error", out var message))
                        detail = message.GetString() ?? detail;
                }
            }
            catch (Exception ex) when (ex is IOException or JsonException) { }
            throw new IOException(string.IsNullOrWhiteSpace(detail) ? L.T("The local engine did not finish") : detail);
        }
    }
    public static async Task<JsonElement> Inspect(string path, string folder, CancellationToken token, int frame = -1)
    {
        folder = Path.Combine(folder, "inspect-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(folder);
        string response = Path.Combine(folder, "inspect.json");
        await Run(["--inspect", path, response, folder, frame.ToString()], token);
        return JsonSerializer.Deserialize<JsonElement>(File.ReadAllText(response));
    }
    public static async Task<JsonElement> Preview(ConversionJob job, string folder, CancellationToken token, string mode = "--preview")
    {
        folder = Path.Combine(folder, "request-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(folder);
        string request = Path.Combine(folder, "preview-request.json"), response = Path.Combine(folder, "preview-result.json");
        File.WriteAllText(request, JsonSerializer.Serialize(job));
        await Run([mode, request, response, folder], token);
        return JsonSerializer.Deserialize<JsonElement>(File.ReadAllText(response));
    }
    public static IDisposable? WatchProgress(string response, IProgress<JobProgress>? progress)
    {
        if (progress == null)
            return null;
        return new Timer(_ => { var value = ProgressReader.Read(response + ".progress"); if (value != null) progress.Report(value); }, null, 0, 200);
    }
    public static async Task<BatchResult> Execute(ConversionJob job, CancellationToken token, IProgress<JobProgress>? progress = null)
    {
        string folder = Path.Combine(Journal.DirectoryPath, "qa-ui-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(folder);
        string request = Path.Combine(folder, "request.json"), response = Path.Combine(folder, "result.json");
        File.WriteAllText(request, JsonSerializer.Serialize(job));
        await Run(["--job", request, response], token, progress: progress);
        return JsonSerializer.Deserialize<BatchResult>(File.ReadAllText(response))!;
    }
}
