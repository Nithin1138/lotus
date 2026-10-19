using System;
using System.Media;

namespace DropDial;

internal static class SoundManager
{
    public const string SoundKey = "soundEffects";

    public static bool Enabled
    {
        get => Settings.GetBool(SoundKey, true);
        set => Settings.Set(SoundKey, value);
    }

    private static long lastTickMs;

    public static void PlayTick()
    {
        if (!Enabled) return;
        long now = Environment.TickCount64;
        if (now - lastTickMs < 35) return;
        lastTickMs = now;
        try
        {
            SystemSounds.Asterisk.Play();
        }
        catch { }
    }

    public static void PlayPop()
    {
        if (!Enabled) return;
        try
        {
            SystemSounds.Beep.Play();
        }
        catch { }
    }
}
