using System;
using System.Media;

namespace DropDial;

internal static class SoundManager
{
    public const string SoundKey = "soundEffects";

    public static bool Enabled
    {
        get => false;
        set { }
    }

    public static void PlayTick() { }
    public static void PlayPop() { }
}
