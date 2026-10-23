using System;
using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace DropDial;

internal sealed record LicenseInfo(string Name, string Email, string Date, string Tier, long? ExpiresAt = null)
{
    public bool IsExpired => ExpiresAt.HasValue && DateTimeOffset.UtcNow.ToUnixTimeSeconds() >= ExpiresAt.Value;
    public int SecondsRemaining => ExpiresAt.HasValue ? Math.Max(0, (int)(ExpiresAt.Value - DateTimeOffset.UtcNow.ToUnixTimeSeconds())) : int.MaxValue;
    public string PlanDisplayName
    {
        get
        {
            var t = (Tier ?? "").Trim().ToLowerInvariant();
            if (t.Contains("single") || t.Contains("solo") || t == "1")
                return "Single";
            if (t.Contains("team") || t.Contains("commercial") || t.Contains("studio") || t == "10")
                return "Team";
            if (t.Contains("universal"))
                return "Universal";
            if (t.Contains("pro"))
                return "Pro";
            return string.IsNullOrEmpty(t) ? "Pro" : char.ToUpper(t[0]) + t.Substring(1);
        }
    }
}

internal enum LicenseStatusKind
{
    Pro,
    Trial,
    TrialExpired
}

internal sealed class LicenseStatus
{
    public LicenseStatusKind Kind { get; }
    public LicenseInfo? Info { get; }
    public int DaysRemaining { get; }

    public bool IsPro => Kind == LicenseStatusKind.Pro && (Info == null || !Info.IsExpired);
    public bool CanUseApp => (Kind == LicenseStatusKind.Pro && (Info == null || !Info.IsExpired))
        || (Kind == LicenseStatusKind.Trial && DaysRemaining > 0 && LicenseManager.TrialRemainingSeconds > 0)
        || (Kind == LicenseStatusKind.TrialExpired && LicenseManager.GetDailyConversionsRemaining() > 0);

    private LicenseStatus(LicenseStatusKind kind, LicenseInfo? info, int days)
    {
        Kind = kind;
        Info = info;
        DaysRemaining = days;
    }

    public static LicenseStatus Pro(LicenseInfo info) => new(LicenseStatusKind.Pro, info, 0);
    public static LicenseStatus Trial(int days) => new(LicenseStatusKind.Trial, null, days);
    public static LicenseStatus Expired() => new(LicenseStatusKind.TrialExpired, null, 0);

    public string DisplayText => Kind switch
    {
        LicenseStatusKind.Pro => Info?.ExpiresAt.HasValue == true
            ? Info.SecondsRemaining switch
            {
                <= 0 => $"{Info.PlanDisplayName} Test License Expired",
                < 60 => $"DropDial {Info.PlanDisplayName} ({Info.SecondsRemaining}s left)",
                < 3600 => $"DropDial {Info.PlanDisplayName} ({Info.SecondsRemaining / 60}m {Info.SecondsRemaining % 60}s left)",
                _ => $"DropDial {Info.PlanDisplayName} ({Info.SecondsRemaining / 3600}h left)"
            }
            : $"DropDial {Info?.PlanDisplayName ?? "Pro"} Plan ✓ ({(string.IsNullOrEmpty(Info?.Name) ? Info?.Email : Info?.Name)})",
        LicenseStatusKind.Trial when LicenseManager.IsWithinFirst24Hours =>
            $"Trial: {DaysRemaining}d · 10% Off Early Bird ({LicenseManager.First24HoursRemainingSeconds / 3600}h {(LicenseManager.First24HoursRemainingSeconds % 3600) / 60}m left)...",
        LicenseStatusKind.Trial => DaysRemaining switch
        {
            <= 0 => $"Enter License Key (Trial: Last day • {LicenseManager.FormatTimeRemaining(LicenseManager.TrialRemainingSeconds)} left)...",
            1 => $"Enter License Key (Trial: 1 day left • {LicenseManager.FormatTimeRemaining(LicenseManager.TrialRemainingSeconds)})...",
            _ => $"Enter License Key (Trial: {DaysRemaining} days left)..."
        },
        _ => $"Enter License Key (Trial Expired — {LicenseManager.GetDailyConversionsRemaining()}/3 free today)..."
    };
}

internal static class LicenseManager
{
    // Embedded ECDSA P-256 public key (X9.62 uncompressed 65-byte point in Base64)
    public const string PublicKeyBase64 = "BGM3oGnG82GbsMcWAlnuMk2nF+c8lDJs37dTnffkzNFvjwVzgC0PwyyHUIe7LgZOPPOmWEyJeRTEGiCOCGcGdyQ=";

    public const string DefaultBuyUrl = "https://dropdial.app/#pricing";
    public const string EarlyBirdBuyUrl = "https://dropdial.app/#pricing?coupon=FIRST24&buy=1";
    public const int TrialDurationDays = 3;

    public static bool IsWithinFirst24Hours
    {
        get
        {
            if (CurrentStatus.IsPro) return false;
            var state = LoadState();
            if (state.TrialStartTime <= 0) return true;
            long now = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
            return (now - state.TrialStartTime) < 86400;
        }
    }

    public static int First24HoursRemainingSeconds
    {
        get
        {
            var state = LoadState();
            if (state.TrialStartTime <= 0) return 86400;
            long now = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
            long rem = 86400 - (now - state.TrialStartTime);
            return (int)Math.Max(0, rem);
        }
    }

    public static int TrialRemainingSeconds
    {
        get
        {
            var state = LoadState();
            if (state.TrialStartTime <= 0) return TrialDurationDays * 86400;
            long now = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
            long rem = ((long)TrialDurationDays * 86400) - (now - state.TrialStartTime);
            return (int)Math.Max(0, rem);
        }
    }

    public static string FormatTimeRemaining(int totalSeconds)
    {
        if (totalSeconds <= 0) return "0s";
        int h = totalSeconds / 3600;
        int m = (totalSeconds % 3600) / 60;
        int s = totalSeconds % 60;
        if (h > 0) return $"{h}h {m}m";
        if (m > 0) return $"{m}m {s}s";
        return $"{s}s";
    }

    public static LicenseStatus CurrentStatus { get; private set; } = LicenseStatus.Trial(TrialDurationDays);
    public static event Action? StatusChanged;

    private static readonly string StorageDir = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
        "DropDial"
    );
    private static readonly string StorageFile = Path.Combine(StorageDir, "license.json");

    private sealed class StoredLicenseState
    {
        public string? LicenseKey { get; set; }
        public string? Tier { get; set; }
        public string? DeviceId { get; set; }
        public long TrialStartTime { get; set; }
        public string? DailyConversionDate { get; set; }
        public int DailyConversionCount { get; set; }
        public string? LastTrialExpiredPromptDate { get; set; }
    }

    static LicenseManager()
    {
        RefreshStatus();
    }

    public static void Initialize()
    {
        RefreshStatus();
    }

    public static void RefreshStatus()
    {
        try
        {
            var state = LoadState();

            // 1. Check if valid license key exists
            if (!string.IsNullOrWhiteSpace(state.LicenseKey))
            {
                var (isValid, info, _) = VerifyKey(state.LicenseKey);
                if (isValid && info != null && !info.IsExpired)
                {
                    if (!string.IsNullOrWhiteSpace(state.Tier))
                    {
                        info = info with { Tier = state.Tier };
                    }
                    CurrentStatus = LicenseStatus.Pro(info);
                    StatusChanged?.Invoke();
                    return;
                }
                else
                {
                    // Expired or invalid - clear stored key
                    state.LicenseKey = null;
                    state.Tier = null;
                    SaveState(state);
                }
            }

            // 2. Check or initialize trial
            long now = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
            if (state.TrialStartTime <= 0)
            {
                state.TrialStartTime = now;
                SaveState(state);
            }

            // Anti-rollback check: if clock is earlier than recorded start by > 1 day
            if (now < state.TrialStartTime - 86400)
            {
                CurrentStatus = LicenseStatus.Expired();
                StatusChanged?.Invoke();
                return;
            }

            long totalTrialSeconds = (long)TrialDurationDays * 86400;
            long elapsedSeconds = now - state.TrialStartTime;

            if (elapsedSeconds >= totalTrialSeconds)
            {
                CurrentStatus = LicenseStatus.Expired();
            }
            else
            {
                long remainingSeconds = totalTrialSeconds - elapsedSeconds;
                int daysRemaining = Math.Max(1, (int)Math.Ceiling(remainingSeconds / 86400.0));
                CurrentStatus = LicenseStatus.Trial(daysRemaining);
            }
        }
        catch
        {
            CurrentStatus = LicenseStatus.Trial(TrialDurationDays);
        }

        StatusChanged?.Invoke();
    }

    public static bool CanUseApp()
    {
        RefreshStatus();
        return CurrentStatus.CanUseApp;
    }

    public const int MaxFreeDailyConversions = 3;

    public static int GetDailyConversionsRemaining()
    {
        var state = LoadState();
        string today = DateTime.UtcNow.ToString("yyyy-MM-dd");
        if (state.DailyConversionDate != today) return MaxFreeDailyConversions;
        return Math.Max(0, MaxFreeDailyConversions - state.DailyConversionCount);
    }

    public static void RecordDailyConversion()
    {
        var state = LoadState();
        string today = DateTime.UtcNow.ToString("yyyy-MM-dd");
        if (state.DailyConversionDate != today)
        {
            state.DailyConversionDate = today;
            state.DailyConversionCount = 1;
        }
        else
        {
            state.DailyConversionCount++;
        }
        SaveState(state);
        StatusChanged?.Invoke();
    }

    public static bool ShouldShowTrialExpiredPromptOnLaunch()
    {
        RefreshStatus();
        if (CurrentStatus.IsPro || CurrentStatus.Kind != LicenseStatusKind.TrialExpired)
            return false;
        var state = LoadState();
        string today = DateTime.UtcNow.ToString("yyyy-MM-dd");
        return state.LastTrialExpiredPromptDate != today;
    }

    public static void MarkTrialExpiredPromptShown()
    {
        var state = LoadState();
        state.LastTrialExpiredPromptDate = DateTime.UtcNow.ToString("yyyy-MM-dd");
        SaveState(state);
    }

    public static (bool Allowed, string? Reason) CanPerformConversion(int fileCount = 1, bool isProTool = false, bool record = true)
    {
        RefreshStatus();
        if (CurrentStatus.IsPro) return (true, null);
        if (CurrentStatus.Kind == LicenseStatusKind.Trial && CurrentStatus.DaysRemaining > 0 && TrialRemainingSeconds > 0) return (true, null);

        if (isProTool) return (false, "Tools require DropDial Pro. Upgrade to unlock.");
        if (fileCount > 3) return (false, $"Batch conversion of {fileCount} files requires DropDial Pro.");

        if (GetDailyConversionsRemaining() > 0)
        {
            if (record) RecordDailyConversion();
            return (true, null);
        }

        return (false, "You have reached your 3 free conversions for today. Upgrade to DropDial Pro for unlimited conversions.");
    }

    public static (bool IsValid, LicenseInfo? Info, string? Error) VerifyKey(string licenseKey)
    {
        string trimmed = licenseKey?.Trim() ?? "";
        if (trimmed.StartsWith("\"") && trimmed.EndsWith("\"") && trimmed.Length >= 2)
            trimmed = trimmed[1..^1].Trim();
        if (trimmed.StartsWith("dd-", StringComparison.OrdinalIgnoreCase) && !trimmed.StartsWith("DD-"))
            trimmed = "DD-" + trimmed[3..];

        if (!trimmed.StartsWith("DD-", StringComparison.Ordinal))
        {
            return (false, null, "Invalid license key format (must start with DD-)");
        }

        string body = trimmed[3..];
        string[] parts = body.Split('.');
        if (parts.Length != 2)
        {
            return (false, null, "Invalid key structure");
        }

        byte[] payloadBytes;
        byte[] rawSig;
        try
        {
            payloadBytes = Base64UrlDecode(parts[0]);
            rawSig = Base64UrlDecode(parts[1]);
        }
        catch
        {
            return (false, null, "Malformed license key payload or signature");
        }

        if (rawSig.Length != 64)
        {
            return (false, null, "Invalid signature length");
        }

        try
        {
            byte[] pubBytes = Convert.FromBase64String(PublicKeyBase64);
            if (pubBytes.Length != 65 || pubBytes[0] != 0x04)
            {
                return (false, null, "Invalid verification public key");
            }

            byte[] x = new byte[32];
            byte[] y = new byte[32];
            Buffer.BlockCopy(pubBytes, 1, x, 0, 32);
            Buffer.BlockCopy(pubBytes, 33, y, 0, 32);

            var parameters = new ECParameters
            {
                Curve = ECCurve.NamedCurves.nistP256,
                Q = new ECPoint { X = x, Y = y }
            };

            using var ecdsa = ECDsa.Create(parameters);
            bool isValid = ecdsa.VerifyData(
                payloadBytes,
                rawSig,
                HashAlgorithmName.SHA256,
                DSASignatureFormat.IeeeP1363FixedFieldConcatenation
            );

            if (!isValid)
            {
                return (false, null, "Signature verification failed (tampered or counterfeit key)");
            }

            using var doc = JsonDocument.Parse(payloadBytes);
            var root = doc.RootElement;
            string email = root.TryGetProperty("e", out var pe) ? pe.GetString() ?? "" : "";
            string name = root.TryGetProperty("n", out var pn) ? pn.GetString() ?? "" : "";
            string date = root.TryGetProperty("d", out var pd) ? pd.GetString() ?? "" : "";
            string tier = root.TryGetProperty("t", out var pt) ? pt.GetString() ?? "pro" : "pro";

            long? expiresAt = null;
            if (root.TryGetProperty("exp", out var pexp))
            {
                if (pexp.ValueKind == JsonValueKind.Number && pexp.TryGetInt64(out long expVal))
                {
                    expiresAt = expVal;
                }
            }

            if (expiresAt.HasValue)
            {
                long nowSec = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
                if (nowSec >= expiresAt.Value)
                {
                    var expDate = DateTimeOffset.FromUnixTimeSeconds(expiresAt.Value).LocalDateTime;
                    return (false, null, $"This test license key expired on {expDate:g}");
                }
            }

            return (true, new LicenseInfo(name, email, date, tier, expiresAt), null);
        }
        catch (Exception ex)
        {
            return (false, null, $"Verification error: {ex.Message}");
        }
    }

    public static string GetDeviceId()
    {
        try
        {
            using var key = Microsoft.Win32.Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Microsoft\Cryptography");
            if (key?.GetValue("MachineGuid") is string guid && !string.IsNullOrWhiteSpace(guid))
                return guid.Trim();
        }
        catch { }

        var state = LoadState();
        if (string.IsNullOrWhiteSpace(state.DeviceId))
        {
            state.DeviceId = Guid.NewGuid().ToString("N");
            SaveState(state);
        }
        return state.DeviceId;
    }

    public static async Task<(bool Success, string Message)> ActivateAsync(string licenseKey)
    {
        var (isValid, info, error) = VerifyKey(licenseKey);
        if (!isValid || info == null)
        {
            return (false, error ?? "Invalid license key");
        }

        string deviceId = GetDeviceId();
        string deviceName = Environment.MachineName;

        string? serverSuccessMsg = null;
        // Verify device limit with activation server
        try
        {
            using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(10) };
            var payload = new
            {
                licenseKey = licenseKey.Trim(),
                deviceId,
                deviceName,
                platform = "windows"
            };
            var content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");
            var response = await client.PostAsync("https://www.dropdial.app/api/activate", content);
            if (!response.IsSuccessStatusCode)
            {
                string respJson = await response.Content.ReadAsStringAsync();
                try
                {
                    using var doc = JsonDocument.Parse(respJson);
                    if (doc.RootElement.TryGetProperty("message", out var msgElem))
                    {
                        return (false, msgElem.GetString() ?? "Device limit reached for this license.");
                    }
                }
                catch { }
                if (response.StatusCode == System.Net.HttpStatusCode.Forbidden)
                {
                    return (false, "This license has reached its device limit. Deactivate your other device to use it here.");
                }
            }
            else
            {
                try
                {
                    string respJson = await response.Content.ReadAsStringAsync();
                    using var doc = JsonDocument.Parse(respJson);
                    if (doc.RootElement.TryGetProperty("message", out var msgElem) && !string.IsNullOrWhiteSpace(msgElem.GetString()))
                    {
                        serverSuccessMsg = msgElem.GetString();
                    }
                    if (doc.RootElement.TryGetProperty("tier", out var tierElem) && !string.IsNullOrWhiteSpace(tierElem.GetString()))
                    {
                        info = info with { Tier = tierElem.GetString()! };
                    }
                    else if (doc.RootElement.TryGetProperty("planDisplayName", out var planElem) && !string.IsNullOrWhiteSpace(planElem.GetString()))
                    {
                        info = info with { Tier = planElem.GetString()! };
                    }
                }
                catch { }
            }
        }
        catch
        {
            // If offline, cryptographic verification succeeds locally
        }

        var state = LoadState();
        state.LicenseKey = licenseKey.Trim();
        state.Tier = info.Tier;
        SaveState(state);

        RefreshStatus();
        string displayMsg = !string.IsNullOrWhiteSpace(serverSuccessMsg)
            ? serverSuccessMsg!
            : $"DropDial {info.PlanDisplayName} successfully activated! Thank you, {(string.IsNullOrEmpty(info.Name) ? info.Email : info.Name)}.";
        return (true, displayMsg);
    }

    public static (bool Success, string Message) Activate(string licenseKey)
    {
        return Task.Run(() => ActivateAsync(licenseKey)).GetAwaiter().GetResult();
    }

    public static void Deactivate()
    {
        var state = LoadState();
        string? key = state.LicenseKey;
        string deviceId = GetDeviceId();
        if (!string.IsNullOrEmpty(key))
        {
            _ = Task.Run(async () =>
            {
                try
                {
                    using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(5) };
                    var payload = new { licenseKey = key, deviceId };
                    var content = new StringContent(JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");
                    await client.PostAsync("https://www.dropdial.app/api/deactivate", content);
                }
                catch { }
            });
        }
        state.LicenseKey = null;
        state.Tier = null;
        SaveState(state);
        RefreshStatus();
    }

    public static string? GetStoredKey()
    {
        return LoadState().LicenseKey;
    }

    private static StoredLicenseState LoadState()
    {
        try
        {
            if (File.Exists(StorageFile))
            {
                string json = File.ReadAllText(StorageFile);
                return JsonSerializer.Deserialize<StoredLicenseState>(json) ?? new StoredLicenseState();
            }
        }
        catch { }

        return new StoredLicenseState();
    }

    private static void SaveState(StoredLicenseState state)
    {
        try
        {
            Directory.CreateDirectory(StorageDir);
            string json = JsonSerializer.Serialize(state, new JsonSerializerOptions { WriteIndented = true });
            File.WriteAllText(StorageFile, json);
        }
        catch { }
    }

    private static byte[] Base64UrlDecode(string str)
    {
        string s = str.Replace('-', '+').Replace('_', '/');
        int pad = s.Length % 4;
        if (pad > 0)
        {
            s += new string('=', 4 - pad);
        }
        return Convert.FromBase64String(s);
    }
}
