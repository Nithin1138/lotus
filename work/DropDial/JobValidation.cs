using System;
using System.Globalization;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;

namespace DropDial;

internal static class JobValidation
{
    public static void ResolveRatio(Dictionary<string, string> values)
    {
        if (values.GetValueOrDefault("ratio") != "custom")
            return;
        if (!double.TryParse(values.GetValueOrDefault("ratioWidth"), NumberStyles.Float, CultureInfo.InvariantCulture, out double width) || !double.TryParse(values.GetValueOrDefault("ratioHeight"), NumberStyles.Float, CultureInfo.InvariantCulture, out double height) || !double.IsFinite(width) || !double.IsFinite(height) || width <= 0 || height <= 0)
            throw new ArgumentException(L.T("Both sides of a custom ratio must be greater than 0, e.g. 3 : 2 or 2.35 : 1."));
        values["ratio"] = $"{width.ToString(CultureInfo.InvariantCulture)}:{height.ToString(CultureInfo.InvariantCulture)}";
    }
    public static double Time(string value)
    {
        string[] parts = value.Trim().Split(':');
        if (parts.Length > 3 || parts.Any(p => !double.TryParse(p, NumberStyles.Float, CultureInfo.InvariantCulture, out double v) || !double.IsFinite(v) || v < 0))
            throw new ArgumentException(L.T("Times must be seconds or h:m:s."));
        if (parts.Length > 1 && parts.Skip(1).Any(p => double.Parse(p, CultureInfo.InvariantCulture) >= 60))
            throw new ArgumentException(L.T("Minutes and seconds must be less than 60."));
        return parts.Reverse().Select((p, i) => double.Parse(p, CultureInfo.InvariantCulture) * Math.Pow(60, i)).Sum();
    }
    public static void Check(ConversionJob job, int width = 0, int height = 0, double duration = 0, int pages = 0)
    {
        var values = job.Parameters ?? new Dictionary<string, string>();
        double N(string key, double fallback = 0) => values.TryGetValue(key, out var v) && !string.IsNullOrWhiteSpace(v) ? Time(v) : fallback;
        double Signed(string key) => double.Parse(values[key], CultureInfo.InvariantCulture);
        void Range(string key, double min, double max, bool integer = false)
        {
            if (!values.TryGetValue(key, out string? raw) || string.IsNullOrWhiteSpace(raw))
                return;
            if (!double.TryParse(raw, NumberStyles.Float, CultureInfo.InvariantCulture, out double v) || !double.IsFinite(v) || v < min || v > max || integer && v != Math.Truncate(v))
                throw new ArgumentException(L.F("{0} must be between {1} and {2}", Catalog.Definition(job.Action, Catalog.Category(job.Paths[0])).Fields?.FirstOrDefault(f => f.Name == key)?.Label ?? key, min, max) + (integer ? L.T(", as a whole number.") : L.T(".")));
        }
        foreach (var field in Catalog.Definition(job.Action, Catalog.Category(job.Paths[0])).Fields ?? [])
        {
            if (field.Kind == "number")
            {
                if (field.Name is "start" or "end" or "time")
                    _ = N(field.Name);
                else if (!double.TryParse(values.GetValueOrDefault(field.Name, field.Default), NumberStyles.Float, CultureInfo.InvariantCulture, out double v) || !double.IsFinite(v))
                    throw new ArgumentException(field.Label + L.T(" needs a valid number."));
            }
            if (field.Kind == "json" && values.TryGetValue(field.Name, out string? raw) && !string.IsNullOrWhiteSpace(raw))
            {
                try
                { using var doc = JsonDocument.Parse(raw); if (doc.RootElement.ValueKind != (field.Name == "rotations" ? JsonValueKind.Object : JsonValueKind.Array)) throw new JsonException(); }
                catch (JsonException) { throw new ArgumentException(field.Label + L.T(" is not valid. Please check the advanced settings.")); }
            }
        }
        foreach (string k in new[] { "x", "y", "width", "height", "maxEdge", "targetKB", "padding", "radius", "shadow", "backgroundBlur", "gap", "columns" })
            Range(k, 0, 1000000, true);
        Range("frame", -1000000, 1000000, true);
        foreach (string k in new[] { "canvasWidth", "canvasHeight" })
            Range(k, 1, 20000, true);
        Range("parts", 2, 1000, true);
        Range("pagesPerFile", 1, 100000, true);
        Range("blockSize", 2, 100, true);
        Range("speed", .125, 8);
        Range("bitrate", 8, 512);
        Range("leftGain", 0, 10);
        Range("rightGain", 0, 10);
        Range("quality", 1, Catalog.Category(job.Paths[0]) == "video" ? 51 : 100, true);
        Range("angle", 0, 360);
        Range("exposure", -10, 10);
        Range("contrast", 0, 5);
        Range("saturation", 0, 5);
        foreach (string k in new[] { "temperature", "shadows", "highlights" })
            Range(k, -100, 100);
        foreach (string k in new[] { "clarity", "dehaze", "grain" })
            Range(k, 0, 100);
        Range("denoise", 0, 30);
        Range("loudness", -70, -5);
        Range("range", 1, 50);
        Range("peak", -9, 0);
        if (values.TryGetValue("ratio", out string? ratio) && ratio != "free")
        {
            string[] parts = ratio.Split(':');
            if (parts.Length != 2 || parts.Any(p => !double.TryParse(p, NumberStyles.Float, CultureInfo.InvariantCulture, out double v) || !double.IsFinite(v) || v <= 0))
                throw new ArgumentException(L.T("Both sides of the crop ratio must be greater than 0."));
        }
        if (values.ContainsKey("rotation") && !new[] { 0d, 90, 180, 270 }.Contains(Signed("rotation")))
            throw new ArgumentException(L.T("Rotation must be 0, 90, 180 or 270."));
        if (values.ContainsKey("canvasWidth") && N("canvasWidth") * N("canvasHeight") > 40000000)
            throw new ArgumentException(L.T("The canvas can be at most 40 megapixels."));
        if (job.Action == "frameImage" && N("padding") * 2 >= Math.Min(N("canvasWidth"), N("canvasHeight")))
            throw new ArgumentException(L.T("Padding must be less than half the canvas's shorter side."));
        if (job.Action is "cropImage" or "cropVideo" or "redactImage" or "redactVideo")
        {
            if (N("width") < 1 || N("height") < 1)
                throw new ArgumentException(L.T("Drag on the preview to select an area first."));
            if (width > 0 && N("x") + N("width") > width || height > 0 && N("y") + N("height") > height)
                throw new ArgumentException(L.T("The selection goes beyond the original image. Make it smaller or select again."));
        }
        if (values.ContainsKey("start") && values.ContainsKey("end"))
        {
            double start = N("start"), end = N("end");
            if (end == 0 && duration > 0)
                end = duration;
            if (end > 0 && end <= start || duration > 0 && (start >= duration || end > duration + .001))
                throw new ArgumentException(L.T("The end must be after the start and within the file's length."));
        }
        foreach (string key in new[] { "times", "splitPoints" })
            if (values.TryGetValue(key, out string? raw) && !string.IsNullOrWhiteSpace(raw))
                foreach (string item in raw.Split(','))
                { double t = Time(item); if (duration > 0 && t >= duration || key == "splitPoints" && t <= 0) throw new ArgumentException(L.T("Times must be within the file's length.")); }
        if (values.TryGetValue("pageOrder", out string? pageOrder) && !string.IsNullOrWhiteSpace(pageOrder))
            foreach (string item in pageOrder.Split(','))
                if (!int.TryParse(item.Trim(), out int page) || page < 1 || pages > 0 && page > pages)
                    throw new ArgumentException(L.F("Pages must be whole numbers from 1{0}, separated by commas.", pages > 0 ? $"–{pages}" : ""));
    }
}
