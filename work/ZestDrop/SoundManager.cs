using System;
using System.Media;

namespace ZestDrop;

internal static class SoundManager
{
    public const string SoundKey = "soundEffects";

    public static bool Enabled
    {
        get => Settings.GetBool(SoundKey, true);
        set => Settings.Set(SoundKey, value);
    }

    public static void PlayTick()
    {
        if (!Enabled) return;
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
            SystemSounds.MenuPopup.Play();
        }
        catch { }
    }
}
