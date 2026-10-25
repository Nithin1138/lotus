using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Net.Http;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace DropDial;

internal sealed class ReleaseInfo
{
    public string TagName { get; init; } = "";
    public string Title { get; init; } = "";
    public string Body { get; init; } = "";
    public string HtmlUrl { get; init; } = "";
    public string? DownloadUrl { get; init; }
    public bool IsZip { get; init; }
}

internal static class UpdateManager
{
    public const string ReleasesApiUrl = "https://dropdial.app/api/releases";
    public const string FallbackReleasesApiUrl = "https://dropdial.app/api/releases/latest";
    public const string GitHubReleasesApiUrl = "https://api.github.com/repos/Nithin1138/lotus/releases/latest";

    public static Action? DismissWheelAction;
    private static bool _isShowingPrompt = false;
    private static string? _sessionDismissedVersion = null;
    private static bool _hasPromptedInCurrentRun = false;
    public static bool HasPendingPrompt { get; private set; }

    private const string LastAppliedTagKey = "LastAppliedUpdateTag";
    private const string SnoozedTagKey = "SnoozedUpdateTag";
    private const string SnoozedTimeKey = "SnoozedUpdateTime";

    public static void SetPendingPrompt(bool pending) => HasPendingPrompt = pending;

    public static bool IsSessionDismissed(string tagName) =>
        !string.IsNullOrEmpty(_sessionDismissedVersion) &&
        string.Equals(FormatVersion(_sessionDismissedVersion), FormatVersion(tagName), StringComparison.OrdinalIgnoreCase);

    public static bool IsAlreadyApplied(string tagName) =>
        string.Equals(Settings.GetString(LastAppliedTagKey), tagName, StringComparison.OrdinalIgnoreCase);

    public static bool IsSnoozed(string tagName)
    {
        string? snoozed = Settings.GetString(SnoozedTagKey);
        if (!string.Equals(snoozed, tagName, StringComparison.OrdinalIgnoreCase))
            return false;

        string? timeStr = Settings.GetString(SnoozedTimeKey);
        if (long.TryParse(timeStr, out long unixSecs))
        {
            long elapsed = DateTimeOffset.UtcNow.ToUnixTimeSeconds() - unixSecs;
            return elapsed < 86400; // 24 hours snooze
        }
        return false;
    }

    public static void PromptIfPending()
    {
        if (AvailableUpdate == null || _hasPromptedInCurrentRun)
            return;

        if (IsSessionDismissed(AvailableUpdate.TagName) || IsSnoozed(AvailableUpdate.TagName) || IsAlreadyApplied(AvailableUpdate.TagName))
        {
            HasPendingPrompt = false;
            return;
        }

        HasPendingPrompt = false;
        _hasPromptedInCurrentRun = true;
        ShowUpdatePrompt(AvailableUpdate);
    }

    public static string FormatVersion(string raw)
    {
        string clean = raw.Trim().TrimStart('v', 'V');
        var parts = clean.Split('.');
        if (parts.Length == 4 && parts[3] == "0")
        {
            clean = $"{parts[0]}.{parts[1]}.{parts[2]}";
        }
        return string.IsNullOrEmpty(clean) ? "v1.0.1" : "v" + clean;
    }

    public static string CurrentVersion =>
        FormatVersion(typeof(UpdateManager).Assembly.GetName().Version is { } v
            ? (v.Revision > 0 ? $"{v.Major}.{v.Minor}.{v.Build}.{v.Revision}" : $"{v.Major}.{v.Minor}.{v.Build}")
            : "1.0.2.2");

    public static ReleaseInfo? AvailableUpdate { get; private set; }
    public static event Action? UpdateStatusChanged;

    public static int[] ParseVersionComponents(string v)
    {
        string clean = v.Trim().TrimStart('v', 'V');
        var parts = clean.Split('.').Select(p => int.TryParse(p, out var n) ? n : 0).ToList();
        while (parts.Count > 1 && parts[^1] == 0)
        {
            parts.RemoveAt(parts.Count - 1);
        }
        return parts.ToArray();
    }

    public static bool IsNewer(string remote, string local)
    {
        var rParts = ParseVersionComponents(remote);
        var lParts = ParseVersionComponents(local);

        int count = Math.Max(rParts.Length, lParts.Length);
        for (int i = 0; i < count; i++)
        {
            int r = i < rParts.Length ? rParts[i] : 0;
            int l = i < lParts.Length ? lParts[i] : 0;
            if (r > l) return true;
            if (r < l) return false;
        }
        return false;
    }

    private static HttpClient CreateClient()
    {
        var handler = new HttpClientHandler
        {
            AllowAutoRedirect = true,
            MaxAutomaticRedirections = 5
        };
        var client = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(15) };
        client.DefaultRequestHeaders.UserAgent.ParseAdd($"DropDial-Windows/{CurrentVersion}");
        client.DefaultRequestHeaders.Accept.ParseAdd("application/json");
        return client;
    }

    public static async Task CheckForUpdatesAsync(bool isUserInitiated, bool autoPromptOnWheelOpen = false)
    {
        try
        {
            using var client = CreateClient();

            HttpResponseMessage? response = null;
            try
            {
                response = await client.GetAsync(ReleasesApiUrl);
            }
            catch { }

            if (response == null || (!response.IsSuccessStatusCode && (int)response.StatusCode != 404))
            {
                try
                {
                    response?.Dispose();
                    response = await client.GetAsync(FallbackReleasesApiUrl);
                }
                catch { }
            }

            if (response == null || (!response.IsSuccessStatusCode && (int)response.StatusCode != 404))
            {
                try
                {
                    response?.Dispose();
                    response = await client.GetAsync(GitHubReleasesApiUrl);
                }
                catch { }
            }

            if (response == null || !response.IsSuccessStatusCode)
            {
                if (response != null && (int)response.StatusCode == 404)
                {
                    bool changed = AvailableUpdate != null;
                    AvailableUpdate = null;
                    if (changed)
                        UpdateStatusChanged?.Invoke();
                    if (isUserInitiated)
                        ShowUpToDateDialog();
                    return;
                }
                if (isUserInitiated)
                    ShowErrorDialog("Unable to check for updates. Please check your internet connection.");
                return;
            }

            var jsonStream = await response.Content.ReadAsStreamAsync();
            using var doc = await JsonDocument.ParseAsync(jsonStream);
            var root = doc.RootElement;

            if (!root.TryGetProperty("tag_name", out var tagElem))
            {
                bool changed = AvailableUpdate != null;
                AvailableUpdate = null;
                if (changed)
                    UpdateStatusChanged?.Invoke();
                if (isUserInitiated)
                    ShowUpToDateDialog();
                return;
            }

            string tagName = tagElem.GetString() ?? "";
            string title = root.TryGetProperty("name", out var nameElem) ? (nameElem.GetString() ?? tagName) : tagName;
            string body = root.TryGetProperty("body", out var bodyElem) ? (bodyElem.GetString() ?? "") : "";
            string htmlUrl = root.TryGetProperty("html_url", out var urlElem) ? (urlElem.GetString() ?? "https://dropdial.app") : "https://dropdial.app";

            string? downloadUrl = null;
            bool isZip = false;

            if (root.TryGetProperty("assets", out var assetsElem) && assetsElem.ValueKind == JsonValueKind.Array)
            {
                // Check if this machine already has local runtime (i.e. existing installation updating in-place)
                string baseDir = AppDomain.CurrentDomain.BaseDirectory;
                bool hasLocalRuntime = Directory.Exists(Path.Combine(baseDir, "runtime"));

                string? updateZipUrl = null;
                string? fullZipUrl = null;
                string? exeUrl = null;

                foreach (var asset in assetsElem.EnumerateArray())
                {
                    string assetName = asset.TryGetProperty("name", out var aName) ? (aName.GetString() ?? "") : "";
                    string assetUrl = asset.TryGetProperty("browser_download_url", out var aUrl) ? (aUrl.GetString() ?? "") : "";

                    if (assetName.EndsWith(".zip", StringComparison.OrdinalIgnoreCase))
                    {
                        if (assetName.Contains("update", StringComparison.OrdinalIgnoreCase))
                        {
                            updateZipUrl = assetUrl;
                        }
                        else if (assetName.Contains("win", StringComparison.OrdinalIgnoreCase) || assetName.Contains("windows", StringComparison.OrdinalIgnoreCase))
                        {
                            fullZipUrl = assetUrl;
                        }
                        else if (fullZipUrl == null)
                        {
                            fullZipUrl = assetUrl;
                        }
                    }
                    else if (exeUrl == null && (assetName.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) || assetName.EndsWith(".msi", StringComparison.OrdinalIgnoreCase)))
                    {
                        exeUrl = assetUrl;
                    }
                }

                // If existing runtime is present and a lightweight update zip is available, download that (~15 MB)
                // Otherwise fall back to the full standalone zip (~250 MB) or executable installer.
                if (hasLocalRuntime && !string.IsNullOrEmpty(updateZipUrl))
                {
                    downloadUrl = updateZipUrl;
                    isZip = true;
                }
                else if (!string.IsNullOrEmpty(fullZipUrl))
                {
                    downloadUrl = fullZipUrl;
                    isZip = true;
                }
                else if (!string.IsNullOrEmpty(updateZipUrl))
                {
                    downloadUrl = updateZipUrl;
                    isZip = true;
                }
                else if (!string.IsNullOrEmpty(exeUrl))
                {
                    downloadUrl = exeUrl;
                    isZip = false;
                }
            }

            if (!string.IsNullOrEmpty(downloadUrl) && downloadUrl.Contains("github.com", StringComparison.OrdinalIgnoreCase))
            {
                try
                {
                    var fileName = Path.GetFileName(new Uri(downloadUrl).AbsolutePath);
                    if (!string.IsNullOrEmpty(fileName))
                        downloadUrl = $"https://dropdial.app/downloads/{fileName}";
                }
                catch { }
            }

            var release = new ReleaseInfo
            {
                TagName = tagName,
                Title = title,
                Body = body,
                HtmlUrl = htmlUrl,
                DownloadUrl = downloadUrl,
                IsZip = isZip
            };

            bool newer = IsNewer(tagName, CurrentVersion);
            bool alreadyApplied = IsAlreadyApplied(tagName);
            bool snoozed = IsSnoozed(tagName);

            if (newer && !alreadyApplied)
            {
                bool changed = AvailableUpdate?.TagName != release.TagName;
                AvailableUpdate = release;
                if (changed)
                    UpdateStatusChanged?.Invoke();

                if (isUserInitiated)
                {
                    HasPendingPrompt = false;
                    _hasPromptedInCurrentRun = true;
                    ShowUpdatePrompt(release);
                }
                else if (autoPromptOnWheelOpen)
                {
                    if (!IsSessionDismissed(release.TagName) && !snoozed && !_hasPromptedInCurrentRun)
                    {
                        HasPendingPrompt = false;
                        _hasPromptedInCurrentRun = true;
                        ShowUpdatePrompt(release);
                    }
                }
                else
                {
                    // Do not interrupt user while working in other apps.
                    // Mark pending so the update prompt appears only when the user opens the wheel / interacts with DropDial.
                    if (!IsSessionDismissed(release.TagName) && !snoozed && !_hasPromptedInCurrentRun)
                    {
                        HasPendingPrompt = true;
                    }
                    else
                    {
                        HasPendingPrompt = false;
                    }
                }
            }
            else
            {
                HasPendingPrompt = false;
                bool changed = AvailableUpdate != null;
                AvailableUpdate = null;
                if (changed)
                    UpdateStatusChanged?.Invoke();

                if (isUserInitiated)
                {
                    ShowUpToDateDialog();
                }
            }
        }
        catch (Exception ex)
        {
            if (isUserInitiated)
            {
                ShowErrorDialog(ex.Message);
            }
        }
    }

    public static void ShowUpdatePrompt(ReleaseInfo release)
    {
        if (System.Windows.Application.Current?.Dispatcher is { } disp && !disp.CheckAccess())
        {
            disp.Invoke(() => ShowUpdatePrompt(release));
            return;
        }

        if (_isShowingPrompt) return;
        _isShowingPrompt = true;

        try
        {
            DismissWheelAction?.Invoke();
            string current = FormatVersion(CurrentVersion);
            string available = FormatVersion(release.TagName);

            using var form = new Form
            {
                Text = "DropDial Update Available",
                FormBorderStyle = FormBorderStyle.FixedDialog,
                MaximizeBox = false,
                MinimizeBox = false,
                StartPosition = FormStartPosition.CenterScreen,
                ClientSize = new System.Drawing.Size(420, 185),
                TopMost = true,
                ShowInTaskbar = true
            };

            try
            {
                using var stream = typeof(UpdateManager).Assembly.GetManifestResourceStream("DropDial.AppIcon");
                if (stream != null) form.Icon = new System.Drawing.Icon(stream);
            }
            catch { }

            var titleLabel = new System.Windows.Forms.Label
            {
                Text = "A new version of DropDial is available!",
                Location = new System.Drawing.Point(20, 18),
                Size = new System.Drawing.Size(380, 24),
                Font = new System.Drawing.Font(System.Drawing.FontFamily.GenericSansSerif, 10.5f, System.Drawing.FontStyle.Bold)
            };

            var infoLabel = new System.Windows.Forms.Label
            {
                Text = $"Current version: {current}\nAvailable version: {available}\n\nWould you like to download and install this update now?",
                Location = new System.Drawing.Point(20, 48),
                Size = new System.Drawing.Size(380, 65),
                Font = new System.Drawing.Font(System.Drawing.FontFamily.GenericSansSerif, 9.25f, System.Drawing.FontStyle.Regular)
            };

            var updateBtn = new System.Windows.Forms.Button
            {
                Text = "Update Now",
                Location = new System.Drawing.Point(205, 130),
                Size = new System.Drawing.Size(105, 34),
                DialogResult = DialogResult.Yes,
                Font = new System.Drawing.Font(System.Drawing.FontFamily.GenericSansSerif, 9.0f, System.Drawing.FontStyle.Bold)
            };

            var laterBtn = new System.Windows.Forms.Button
            {
                Text = "Later",
                Location = new System.Drawing.Point(320, 130),
                Size = new System.Drawing.Size(80, 34),
                DialogResult = DialogResult.No
            };

            form.AcceptButton = updateBtn;
            form.CancelButton = laterBtn;

            form.Controls.Add(titleLabel);
            form.Controls.Add(infoLabel);
            form.Controls.Add(updateBtn);
            form.Controls.Add(laterBtn);

            Native.AllowSetForegroundWindow(-1);
            form.Shown += (_, _) =>
            {
                form.Activate();
                form.BringToFront();
                updateBtn.Focus();
            };

            var choice = form.ShowDialog();

            if (choice == DialogResult.Yes)
            {
                HasPendingPrompt = false;
                _sessionDismissedVersion = null;
                Settings.Set(LastAppliedTagKey, release.TagName);
                if (release.IsZip && !string.IsNullOrEmpty(release.DownloadUrl))
                {
                    _ = DownloadAndApplyUpdateAsync(release);
                }
                else if (!string.IsNullOrEmpty(release.DownloadUrl))
                {
                    OpenBrowser(release.DownloadUrl);
                }
                else
                {
                    OpenBrowser(release.HtmlUrl);
                }
            }
            else
            {
                HasPendingPrompt = false;
                _sessionDismissedVersion = release.TagName;
                Settings.Set(SnoozedTagKey, release.TagName);
                Settings.Set(SnoozedTimeKey, DateTimeOffset.UtcNow.ToUnixTimeSeconds().ToString());
            }
        }
        finally
        {
            _isShowingPrompt = false;
        }
    }

    private static void ShowUpToDateDialog()
    {
        if (System.Windows.Application.Current?.Dispatcher is { } disp && !disp.CheckAccess())
        {
            disp.Invoke(ShowUpToDateDialog);
            return;
        }

        Native.AllowSetForegroundWindow(-1);
        MessageBox.Show(
            $"You are running DropDial {FormatVersion(CurrentVersion)}, which is currently the newest version available.",
            "DropDial is Up to Date",
            MessageBoxButtons.OK,
            MessageBoxIcon.Information
        );
    }

    private static void ShowErrorDialog(string error)
    {
        if (System.Windows.Application.Current?.Dispatcher is { } disp && !disp.CheckAccess())
        {
            disp.Invoke(() => ShowErrorDialog(error));
            return;
        }

        Native.AllowSetForegroundWindow(-1);
        MessageBox.Show(
            error,
            "Check for Updates",
            MessageBoxButtons.OK,
            MessageBoxIcon.Information
        );
    }

    public static void OpenBrowser(string url)
    {
        try
        {
            Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
        }
        catch { }
    }

    private static async Task DownloadAndApplyUpdateAsync(ReleaseInfo release)
    {
        using var cts = new CancellationTokenSource();
        var progressForm = CreateProgressDialog(release.TagName, cts, () => OpenBrowser(release.HtmlUrl));
        progressForm.Show();

        string tempZip = Path.Combine(Path.GetTempPath(), $"DropDial_Update_{Guid.NewGuid():N}.zip");
        string stagingDir = Path.Combine(Path.GetTempPath(), $"DropDial_Staging_{Guid.NewGuid():N}");

        try
        {
            var downloadUrls = new System.Collections.Generic.List<string>();
            string primaryUrl = release.DownloadUrl ?? "";
            string fileName = "";
            try { fileName = Path.GetFileName(new Uri(primaryUrl).AbsolutePath); } catch { }
            if (string.IsNullOrEmpty(fileName)) fileName = "DropDial-Windows-Update.zip";

            if (!string.IsNullOrEmpty(primaryUrl))
            {
                string normalized = primaryUrl.Replace("www.dropdial.app", "dropdial.app");
                downloadUrls.Add(normalized);
                if (normalized != primaryUrl)
                    downloadUrls.Add(primaryUrl);
            }
            downloadUrls.Add($"https://dropdial.app/downloads/{fileName}");
            downloadUrls.Add($"https://dropdial.app/api/releases?download={fileName}");
            downloadUrls.Add("https://dropdial.app/downloads/DropDial-Windows-x64.zip");
            downloadUrls.Add($"https://github.com/Nithin1138/lotus/releases/download/{release.TagName}/{fileName}");
            downloadUrls.Add($"https://github.com/Nithin1138/lotus/releases/latest/download/{fileName}");

            HttpResponseMessage? response = null;
            HttpClient? activeClient = null;
            Exception? lastEx = null;

            foreach (var url in downloadUrls.Distinct(StringComparer.OrdinalIgnoreCase))
            {
                try
                {
                    activeClient?.Dispose();
                    var handler = new HttpClientHandler
                    {
                        AllowAutoRedirect = true,
                        MaxAutomaticRedirections = 10
                    };
                    activeClient = new HttpClient(handler) { Timeout = TimeSpan.FromMinutes(5) };
                    activeClient.DefaultRequestHeaders.UserAgent.ParseAdd($"DropDial-Windows/{CurrentVersion}");

                    var req = new HttpRequestMessage(HttpMethod.Get, url);
                    var resp = await activeClient.SendAsync(req, HttpCompletionOption.ResponseHeadersRead, cts.Token);
                    if (resp.IsSuccessStatusCode)
                    {
                        response = resp;
                        break;
                    }
                    resp.Dispose();
                }
                catch (Exception ex)
                {
                    lastEx = ex;
                }
            }

            if (response == null || activeClient == null)
            {
                throw lastEx ?? new HttpRequestException("Could not connect to update servers. Please download manually.");
            }

            using (activeClient)
            using (response)
            {
                long? totalBytes = response.Content.Headers.ContentLength;
                using var contentStream = await response.Content.ReadAsStreamAsync(cts.Token);
                using var fileStream = new FileStream(tempZip, FileMode.Create, FileAccess.Write, FileShare.None, 65536, true);

                var buffer = new byte[65536];
                long totalRead = 0;
                int read;

                while ((read = await contentStream.ReadAsync(buffer, 0, buffer.Length, cts.Token)) > 0)
                {
                    await fileStream.WriteAsync(buffer, 0, read, cts.Token);
                    totalRead += read;

                    if (totalBytes.HasValue && totalBytes.Value > 0)
                    {
                        int percent = (int)((totalRead * 100) / totalBytes.Value);
                        progressForm.UpdateProgress(percent, totalRead, totalBytes.Value);
                    }
                }
            }

            progressForm.SetStatus("Extracting update files...");
            Directory.CreateDirectory(stagingDir);
            ZipFile.ExtractToDirectory(tempZip, stagingDir, true);

            // Locate files inside staging directory (handle single root folder if packed that way)
            string sourceDir = stagingDir;
            if (!File.Exists(Path.Combine(sourceDir, "DropDial.exe")))
            {
                var subDirs = Directory.GetDirectories(stagingDir);
                foreach (var sub in subDirs)
                {
                    if (File.Exists(Path.Combine(sub, "DropDial.exe")))
                    {
                        sourceDir = sub;
                        break;
                    }
                }
            }

            string targetDir = AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\', '/');
            string targetExe = Path.Combine(targetDir, "DropDial.exe");
            int currentPid = Environment.ProcessId;

            string batPath = Path.Combine(Path.GetTempPath(), $"apply_update_{Guid.NewGuid():N}.bat");
            string batContent = $@"@echo off
set ""CURRENT_PID={currentPid}""
set ""SOURCE_DIR={sourceDir}""
set ""TARGET_DIR={targetDir}""
set ""EXE_PATH={targetExe}""

:: 1. Wait up to 5 seconds for PID to exit, then force kill to release all file locks
for /L %%i in (1,1,10) do (
    tasklist /fi ""PID eq %CURRENT_PID%"" 2>NUL | find /I ""%CURRENT_PID%"" >NUL
    if errorlevel 1 (
        goto ready
    )
    if %%i GEQ 3 (
        taskkill /F /PID %CURRENT_PID% >NUL 2>&1
        taskkill /F /IM DropDial.exe >NUL 2>&1
    )
    ping 127.0.0.1 -n 2 >NUL
)

:ready
:: Ensure all DropDial instances and file locks are completely released
taskkill /F /IM DropDial.exe >NUL 2>&1
ping 127.0.0.1 -n 3 >NUL

:: 2. Robust copy using robocopy with retries, fallback to xcopy
robocopy ""%SOURCE_DIR%"" ""%TARGET_DIR%"" /E /IS /IT /NP /R:10 /W:1 >NUL 2>&1
if errorlevel 8 (
    xcopy ""%SOURCE_DIR%\*"" ""%TARGET_DIR%\"" /E /Y /I /Q /K /R /H >NUL 2>&1
)

:: 3. Launch updated DropDial with proper working directory
start """" /D ""%TARGET_DIR%"" ""%EXE_PATH%""

:: 4. Clean up temporary staging files and self-delete batch script
rmdir /s /q ""%SOURCE_DIR%"" >NUL 2>&1
del /f /q ""%~f0"" >NUL 2>&1
";
            File.WriteAllText(batPath, batContent);

            var psi = new ProcessStartInfo("cmd.exe", $"/s /c \"\"{batPath}\"\"")
            {
                CreateNoWindow = true,
                UseShellExecute = false
            };
            Process.Start(psi);

            progressForm.Close();

            // Ensure WPF application dispatcher shuts down and process terminates immediately
            try
            {
                System.Windows.Application.Current?.Dispatcher.Invoke(() =>
                {
                    System.Windows.Application.Current.Shutdown();
                });
            }
            catch { }
            Environment.Exit(0);
        }
        catch (OperationCanceledException)
        {
            CleanUpTempFiles(tempZip, stagingDir);
            progressForm.Close();
        }
        catch (Exception ex)
        {
            CleanUpTempFiles(tempZip, stagingDir);
            progressForm.Close();

            var result = MessageBox.Show(
                $"Automatic update could not be completed ({ex.Message}).\n\nWould you like to download the update manually in your browser?",
                "Update Error",
                MessageBoxButtons.YesNo,
                MessageBoxIcon.Warning
            );

            if (result == DialogResult.Yes)
            {
                OpenBrowser(release.HtmlUrl);
            }
        }
    }

    private static void CleanUpTempFiles(string zipPath, string stagingDir)
    {
        try { if (File.Exists(zipPath)) File.Delete(zipPath); } catch { }
        try { if (Directory.Exists(stagingDir)) Directory.Delete(stagingDir, true); } catch { }
    }

    private static UpdateProgressForm CreateProgressDialog(string version, CancellationTokenSource cts, Action onManual)
    {
        return new UpdateProgressForm(version, cts, onManual);
    }

    private sealed class UpdateProgressForm : Form
    {
        private readonly System.Windows.Forms.Label statusLabel;
        private readonly System.Windows.Forms.ProgressBar progressBar;
        private readonly System.Windows.Forms.Button cancelButton;
        private readonly System.Windows.Forms.Button manualButton;
        private readonly CancellationTokenSource cts;

        public UpdateProgressForm(string version, CancellationTokenSource cts, Action onManual)
        {
            this.cts = cts;
            Text = "DropDial Update";
            FormBorderStyle = FormBorderStyle.FixedDialog;
            MaximizeBox = false;
            MinimizeBox = false;
            StartPosition = FormStartPosition.CenterScreen;
            ClientSize = new System.Drawing.Size(380, 140);
            TopMost = true;

            statusLabel = new System.Windows.Forms.Label
            {
                Text = $"Downloading DropDial {version}...",
                Location = new System.Drawing.Point(20, 20),
                Size = new System.Drawing.Size(340, 22),
                Font = new System.Drawing.Font(System.Drawing.FontFamily.GenericSansSerif, 9.5f, System.Drawing.FontStyle.Regular)
            };

            progressBar = new System.Windows.Forms.ProgressBar
            {
                Location = new System.Drawing.Point(20, 50),
                Size = new System.Drawing.Size(340, 22),
                Minimum = 0,
                Maximum = 100,
                Value = 0
            };

            manualButton = new System.Windows.Forms.Button
            {
                Text = "Manual Download",
                Location = new System.Drawing.Point(20, 90),
                Size = new System.Drawing.Size(140, 30)
            };
            manualButton.Click += (_, _) =>
            {
                cts.Cancel();
                onManual();
                Close();
            };

            cancelButton = new System.Windows.Forms.Button
            {
                Text = "Cancel",
                Location = new System.Drawing.Point(270, 90),
                Size = new System.Drawing.Size(90, 30)
            };
            cancelButton.Click += (_, _) =>
            {
                cts.Cancel();
                Close();
            };

            Controls.Add(statusLabel);
            Controls.Add(progressBar);
            Controls.Add(manualButton);
            Controls.Add(cancelButton);
        }

        public void UpdateProgress(int percent, long currentBytes, long totalBytes)
        {
            if (InvokeRequired)
            {
                BeginInvoke(new Action(() => UpdateProgress(percent, currentBytes, totalBytes)));
                return;
            }
            progressBar.Value = Math.Clamp(percent, 0, 100);
            double mbCurrent = currentBytes / (1024.0 * 1024.0);
            double mbTotal = totalBytes / (1024.0 * 1024.0);
            statusLabel.Text = $"Downloading: {mbCurrent:F1} MB / {mbTotal:F1} MB ({percent}%)";
        }

        public void SetStatus(string text)
        {
            if (InvokeRequired)
            {
                BeginInvoke(new Action(() => SetStatus(text)));
                return;
            }
            statusLabel.Text = text;
            progressBar.Style = ProgressBarStyle.Marquee;
        }
    }
}
