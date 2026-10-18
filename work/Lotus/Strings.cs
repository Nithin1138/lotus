using System;
using System.Collections.Generic;
using System.Globalization;

namespace Lotus;

// Application string helpers. All strings are natively in English.
internal static class L
{
    public static event Action? Changed;

    public static string Language
    {
        get => "en";
        set { }
    }

    public static bool English => true;

    public static string T(string text) => text;

    public static string F(string text, params object?[] values) => string.Format(CultureInfo.InvariantCulture, text, values);

    public static void UseForSession(string value) { }
}
