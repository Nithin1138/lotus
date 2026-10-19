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
    public const string RepoOwner = "Nithin1138";
    public const string RepoName = "lotus";
    public const string ReleasesApiUrl = "https://api.github.com/repos/Nithin1138/lotus/releases/latest";

    public static string CurrentVersion =>
        typeof(UpdateManager).Assembly.GetName().Version is { } v
            ? $"{v.Major}.{v.Minor}.{v.Build}"
            : "1.0.0";

    public static ReleaseInfo? AvailableUpdate { get; private set; }
    public static event Action? UpdateStatusChanged;

    public static bool IsNewer(string remote, string local)
    {
        string cleanRemote = remote.Trim().TrimStart('v', 'V');
        string cleanLocal = local.Trim().TrimStart('v', 'V');

        var rParts = cleanRemote.Split('.').Select(p => int.TryParse(p, out var n) ? n : 0).ToArray();
        var lParts = cleanLocal.Split('.').Select(p => int.TryParse(p, out var n) ? n : 0).ToArray();

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

    public static async Task CheckForUpdatesAsync(bool isUserInitiated)
    {
        try
        {
            using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(15) };
            client.DefaultRequestHeaders.UserAgent.ParseAdd($"DropDial-Windows/{CurrentVersion}");
            client.DefaultRequestHeaders.Accept.ParseAdd("application/vnd.github+json");

            var response = await client.GetAsync(ReleasesApiUrl);
            if (!response.IsSuccessStatusCode)
            {
                if (isUserInitiated)
                    ShowErrorDialog($"Could not check for updates (server returned {(int)response.StatusCode}).");
                return;
            }

            var jsonStream = await response.Content.ReadAsStreamAsync();
            using var doc = await JsonDocument.ParseAsync(jsonStream);
            var root = doc.RootElement;

            if (!root.TryGetProperty("tag_name", out var tagElem))
            {
                if (isUserInitiated)
                    ShowErrorDialog("Invalid release information received from server.");
                return;
            }

            string tagName = tagElem.GetString() ?? "";
            string title = root.TryGetProperty("name", out var nameElem) ? (nameElem.GetString() ?? tagName) : tagName;
            string body = root.TryGetProperty("body", out var bodyElem) ? (bodyElem.GetString() ?? "") : "";
            string htmlUrl = root.TryGetProperty("html_url", out var urlElem) ? (urlElem.GetString() ?? $"https://github.com/{RepoOwner}/{RepoName}/releases/latest") : $"https://github.com/{RepoOwner}/{RepoName}/releases/latest";

            string? downloadUrl = null;
            bool isZip = false;

            if (root.TryGetProperty("assets", out var assetsElem) && assetsElem.ValueKind == JsonValueKind.Array)
            {
                foreach (var asset in assetsElem.EnumerateArray())
                {
                    string assetName = asset.TryGetProperty("name", out var aName) ? (aName.GetString() ?? "") : "";
                    string assetUrl = asset.TryGetProperty("browser_download_url", out var aUrl) ? (aUrl.GetString() ?? "") : "";

                    if (assetName.EndsWith(".zip", StringComparison.OrdinalIgnoreCase))
                    {
                        if (assetName.Contains("win", StringComparison.OrdinalIgnoreCase) || assetName.Contains("windows", StringComparison.OrdinalIgnoreCase))
                        {
                            downloadUrl = assetUrl;
                            isZip = true;
                            break;
                        }
                        if (downloadUrl == null)
                        {
                            downloadUrl = assetUrl;
                            isZip = true;
                        }
                    }
                }
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

            if (newer)
            {
                AvailableUpdate = release;
                UpdateStatusChanged?.Invoke();

                string? ignored = Settings.GetString("IgnoredUpdateVersion");
                if (!isUserInitiated && string.Equals(ignored, tagName, StringComparison.OrdinalIgnoreCase))
                {
                    return;
                }

                ShowUpdatePrompt(release);
            }
            else
            {
                AvailableUpdate = null;
                UpdateStatusChanged?.Invoke();

                if (isUserInitiated)
                {
                    MessageBox.Show(
                        $"You are running DropDial v{CurrentVersion}, which is currently the newest version available.",
                        "DropDial is Up to Date",
                        MessageBoxButtons.OK,
                        MessageBoxIcon.Information
                    );
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

    private static void ShowUpdatePrompt(ReleaseInfo release)
    {
        string summary = string.IsNullOrWhiteSpace(release.Body) ? "Includes performance improvements and bug fixes." : release.Body.Trim();
        if (summary.Length > 300) summary = summary.Substring(0, 300) + "...";

        string message = $"A new version of DropDial is available!\n\n" +
                         $"Latest Version: {release.TagName}\n" +
                         $"Current Version: v{CurrentVersion}\n\n" +
                         $"Release Notes:\n{summary}\n\n" +
                         $"Click 'Yes' to update automatically now,\n" +
                         $"'No' to download manually in your browser,\n" +
                         $"or 'Cancel' to remind me later.";

        var choice = MessageBox.Show(message, "DropDial Update Available", MessageBoxButtons.YesNoCancel, MessageBoxIcon.Information);

        if (choice == DialogResult.Yes)
        {
            if (release.IsZip && !string.IsNullOrEmpty(release.DownloadUrl))
            {
                _ = DownloadAndApplyUpdateAsync(release);
            }
            else
            {
                OpenBrowser(release.HtmlUrl);
            }
        }
        else if (choice == DialogResult.No)
        {
            OpenBrowser(release.HtmlUrl);
        }
        else
        {
            Settings.Set("IgnoredUpdateVersion", release.TagName);
        }
    }

    private static void ShowErrorDialog(string error)
    {
        var result = MessageBox.Show(
            $"Could not check for updates:\n{error}\n\nWould you like to open the releases page on GitHub directly?",
            "Check for Updates",
            MessageBoxButtons.YesNo,
            MessageBoxIcon.Warning
        );

        if (result == DialogResult.Yes)
        {
            OpenBrowser($"https://github.com/{RepoOwner}/{RepoName}/releases");
        }
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
            using (var client = new HttpClient { Timeout = TimeSpan.FromMinutes(5) })
            {
                client.DefaultRequestHeaders.UserAgent.ParseAdd($"DropDial-Windows/{CurrentVersion}");
                using var response = await client.GetAsync(release.DownloadUrl!, HttpCompletionOption.ResponseHeadersRead, cts.Token);
                response.EnsureSuccessStatusCode();

                long? totalBytes = response.Content.Headers.ContentLength;
                using var contentStream = await response.Content.ReadAsStreamAsync(cts.Token);
                using var fileStream = new FileStream(tempZip, FileMode.Create, FileAccess.Write, FileShare.None, 8192, true);

                var buffer = new byte[8192];
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
set CURRENT_PID={currentPid}
set SOURCE_DIR=""{sourceDir}""
set TARGET_DIR=""{targetDir}""
set EXE_PATH=""{targetExe}""

:waitloop
tasklist /fi ""PID eq %CURRENT_PID%"" 2>NUL | find /I ""%CURRENT_PID%"" >NUL
if not errorlevel 1 (
    timeout /t 1 /nobreak >NUL
    goto waitloop
)

timeout /t 1 /nobreak >NUL
xcopy %SOURCE_DIR%\* %TARGET_DIR%\ /E /Y /I >NUL
start """" %EXE_PATH%
del /f /q ""%~f0""
";
            File.WriteAllText(batPath, batContent);

            var psi = new ProcessStartInfo("cmd.exe", $"/c \"{batPath}\"")
            {
                CreateNoWindow = true,
                UseShellExecute = false
            };
            Process.Start(psi);

            progressForm.Close();
            Application.Exit();
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
