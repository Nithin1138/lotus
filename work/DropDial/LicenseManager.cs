using System;
using System.Diagnostics;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Windows.Forms;

namespace DropDial;

internal sealed record LicenseInfo(string Name, string Email, string Date, string Tier, long? ExpiresAt = null)
{
    public bool IsExpired => ExpiresAt.HasValue && DateTimeOffset.UtcNow.ToUnixTimeSeconds() >= ExpiresAt.Value;
    public int SecondsRemaining => ExpiresAt.HasValue ? Math.Max(0, (int)(ExpiresAt.Value - DateTimeOffset.UtcNow.ToUnixTimeSeconds())) : int.MaxValue;
    public string PlanDisplayName => (Tier?.Trim().ToLowerInvariant()) switch
    {
        "single" => "Single",
        "team" => "Team",
        "universal" => "Universal",
        _ => "Pro"
    };
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
        || (Kind == LicenseStatusKind.Trial && DaysRemaining >= 0)
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
        LicenseStatusKind.Trial => DaysRemaining switch
        {
            <= 0 => "🔑 Enter License Key (Trial: Last day)...",
            1 => "🔑 Enter License Key (Trial: 1 day left)...",
            _ => $"🔑 Enter License Key (Trial: {DaysRemaining} days left)..."
        },
        _ => $"🔑 Enter License Key (Trial Expired — {LicenseManager.GetDailyConversionsRemaining()}/3 free today)..."
    };
}

internal static class LicenseManager
{
    // Embedded ECDSA P-256 public key (X9.62 uncompressed 65-byte point in Base64)
    public const string PublicKeyBase64 = "BGM3oGnG82GbsMcWAlnuMk2nF+c8lDJs37dTnffkzNFvjwVzgC0PwyyHUIe7LgZOPPOmWEyJeRTEGiCOCGcGdyQ=";

    public const string DefaultBuyUrl = "https://dropdial.app/#pricing";
    public const int TrialDurationDays = 7;

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
        public long TrialStartTime { get; set; }
        public string? DailyConversionDate { get; set; }
        public int DailyConversionCount { get; set; }
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
                    CurrentStatus = LicenseStatus.Pro(info);
                    StatusChanged?.Invoke();
                    return;
                }
                else
                {
                    // Expired or invalid - clear stored key
                    state.LicenseKey = null;
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

            long elapsedSeconds = now - state.TrialStartTime;
            int elapsedDays = (int)(elapsedSeconds / 86400);
            int daysRemaining = TrialDurationDays - elapsedDays;

            if (daysRemaining >= 0)
            {
                CurrentStatus = LicenseStatus.Trial(daysRemaining);
            }
            else
            {
                CurrentStatus = LicenseStatus.Expired();
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

    public static (bool Allowed, string? Reason) CanPerformConversion(int fileCount = 1, bool isProTool = false)
    {
        RefreshStatus();
        if (CurrentStatus.IsPro) return (true, null);
        if (CurrentStatus.Kind == LicenseStatusKind.Trial && CurrentStatus.DaysRemaining >= 0) return (true, null);

        if (isProTool) return (false, "Advanced Pro Tools require DropDial Pro.");
        if (fileCount > 3) return (false, $"Bulk batch conversion ({fileCount} files) requires DropDial Pro.");

        if (GetDailyConversionsRemaining() > 0)
        {
            RecordDailyConversion();
            return (true, null);
        }

        return (false, "You have reached your 3 free conversions for today. Unlock unlimited lifetime conversions with DropDial Pro.");
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

    public static (bool Success, string Message) Activate(string licenseKey)
    {
        var (isValid, info, error) = VerifyKey(licenseKey);
        if (!isValid || info == null)
        {
            return (false, error ?? "Invalid license key");
        }

        var state = LoadState();
        state.LicenseKey = licenseKey.Trim();
        SaveState(state);

        RefreshStatus();
        return (true, $"DropDial Pro successfully activated! Thank you, {(string.IsNullOrEmpty(info.Name) ? info.Email : info.Name)}.");
    }

    public static void Deactivate()
    {
        var state = LoadState();
        state.LicenseKey = null;
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
