using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;

namespace DropDial;

internal sealed record Field(string Name, string Label, string Default = "", string Kind = "text", string[]? Choices = null);
// Parts: the tools a combined entry opens together. Chain: each part works on the previous parts' result.
// Recent: the option used last for this kind of file, shown first in the wheel with a ↻ mark.
internal sealed record Operation(string Id, string Label, bool Tool = false, Field[]? Fields = null, bool Ordered = false, string[]? Parts = null, bool Chain = false, bool Recent = false);

internal sealed record ToolGroup(string Label, List<Operation> Items);

internal static class Catalog
{
    // Files with ten or more tools show categories first; this is how each kind of file is divided.
    private static readonly Dictionary<string, (string Label, string[] Ids)[]> Categories = new()
    {
        ["image"] = [("Size & direction", ["cropImage", "rotateImage", "resizeImage"]), ("Look & marks", ["editImage", "frameImage", "watermark", "annotateImage", "redactImage"]),
            ("Output & extras", ["compress", "removeMetadata", "location", "ocrImage", "makeIcon", "createPDF", "createCollage", "createAnimation", "packArchive"])],
        ["video"] = [("Editing", ["editVideo", "trimVideo", "splitVideo", "joinVideos", "changeVideoSpeed", "videoSnapshots", "videoEffects"]), ("Picture", ["cropVideo", "rotateVideo", "videoSettings", "watermark", "redactVideo"]),
            ("Sound & subtitles", ["muteVideo", "subtitlesAudio"]), ("Output & extras", ["compress", "removeMetadata", "location", "videoToGif", "packArchive"])],
        ["audio"] = [("Editing", ["trimAudio", "redactAudio", "joinAudio"]), ("Sound", ["normalizeAudio", "audioChannels", "audioEffects"]),
            ("Output & extras", ["compress", "removeMetadata", "audioToVideo", "ringtone", "packArchive"])],
        ["document"] = [("Pages", ["splitPDF", "mergePDF", "organizePDF", "extractPdfImages", "pdfNumbers"]), ("Security & text", ["pdfPassword", "ocrPDF", "watermark", "redactPDF", "removeMetadata"]),
            ("Output & extras", ["compress", "packArchive"])],
    };

    // When a single file has ten or more tools, related tools share one window. The older two-wheel layout stays
    // available (tray menu) and is used instead when chosen.
    public const string LayoutKey = "wheelLayout";
    public static bool TwoWheels => false;
    private static readonly Dictionary<string, (string Id, string Label, string[] Parts, bool Chain)[]> Merged = new()
    {
        ["image"] = [("merge:cropRotate", "Crop & rotate", ["cropImage", "rotateImage"], true), ("merge:sizeCompress", "Size & compress", ["resizeImage", "compress"], true),
            ("merge:frameWatermark", "Background & watermark", ["frameImage", "watermark"], true)],
        ["video"] = [("merge:trimSplit", "Trim & split", ["trimVideo", "splitVideo"], false), ("merge:speedEffects", "Speed & effects", ["changeVideoSpeed", "videoEffects"], true),
            ("merge:cropRotateVideo", "Crop & rotate", ["cropVideo", "rotateVideo"], true), ("merge:resolutionCompress", "Resolution & compress", ["videoSettings", "compress"], true),
            ("merge:soundSubtitles", "Sound & subtitles", ["muteVideo", "subtitlesAudio"], true), ("merge:watermarkRedact", "Watermark & redact", ["watermark", "redactVideo"], true),
            ("merge:framesGif", "Frames & GIF", ["videoSnapshots", "videoToGif"], false)],
        ["document"] = [("merge:watermarkRedactPdf", "Watermark & redact", ["watermark", "redactPDF"], true)],
    };

    // Replaces each tool that belongs to a combined entry by that entry (in the place of its first tool).
    // Several files can share a combined window as well; each of its tools then saves on its own.
    private static List<string> Merge(string kind, List<string> ids)
    {
        if (TwoWheels || ids.Count < 10 || !Merged.TryGetValue(kind, out var plan))
            return ids;
        var result = new List<string>();
        foreach (string id in ids)
        {
            var entry = plan.FirstOrDefault(m => m.Parts.Contains(id) && m.Parts.All(ids.Contains));
            string chosen = entry.Id ?? id;
            if (!result.Contains(chosen))
                result.Add(chosen);
        }
        return result;
    }

    private static Operation? MergedDefinition(string id) =>
        Merged.Values.SelectMany(x => x).Where(m => m.Id == id).Select(m => new Operation(m.Id, L.T(m.Label), true, null, false, m.Parts, m.Chain)).FirstOrDefault();

    public static List<ToolGroup>? Grouped(List<Operation> operations, string kind)
    {
        if (operations.Count < 10 || !Categories.TryGetValue(kind, out var plan))
            return null;
        var groups = new List<ToolGroup>();
        var placed = new HashSet<string>();
        void Add(string label, IEnumerable<Operation> items)
        {
            var list = items.ToList();
            if (list.Count == 0)
                return;
            groups.Add(new ToolGroup(L.T(label), list));
            foreach (var item in list)
                placed.Add(item.Id);
        }
        foreach (var (label, ids) in plan)
            Add(label, ids.Select(id => operations.FirstOrDefault(o => o.Id == id)).Where(o => o != null).Select(o => o!));
        Add("Flows", operations.Where(o => o.Id.StartsWith(Flows.Prefix)));
        Add("Other", operations.Where(o => !placed.Contains(o.Id)));
        return groups.Count >= 2 ? groups : null;
    }

    public static string Extension(string path)
    {
        string ext = Path.GetExtension(path).TrimStart('.').ToLowerInvariant();
        return ext switch { "jpeg" => "jpg", "tif" => "tiff", "heif" => "heic", "aif" => "aiff", "tgz" => "gz", _ => ext };
    }
    public static readonly string[] Images = ["jpg", "png", "webp", "heic", "tiff", "svg", "avif", "bmp", "ico"];
    public static readonly string[] Audio = ["mp3", "m4a", "wav", "flac", "ogg", "opus", "aiff", "wma", "aac"];
    public static readonly string[] Video = ["mp4", "mov", "mkv", "webm", "avi", "wmv"];
    public static readonly string[] Archives = ["zip", "tar", "gz", "rar", "7z"];
    public static readonly string[] OfficeSlides = ["ppt", "pptx", "pptm", "pps", "ppsx", "odp"];
    public static readonly string[] OfficeWords = ["doc", "docx", "docm", "rtf", "odt"];
    public static readonly string[] OfficeSheets = ["xls", "xlsx", "xlsm", "xlsb", "ods", "csv", "tsv"];
    private static readonly string[] ImageTargets = ["jpg", "png", "webp", "heic", "tiff", "avif", "bmp", "pdf", "ico"];
    public static string Category(string path)
    {
        string ext = Extension(path);
        return Images.Contains(ext) ? "image" : Audio.Contains(ext) ? "audio" : Video.Contains(ext) || ext == "gif" ? "video" : OfficeSlides.Contains(ext) || OfficeWords.Contains(ext) || OfficeSheets.Contains(ext) ? "office" : new[] { "pdf", "txt", "srt", "vtt", "epub", "md", "markdown" }.Contains(ext) ? "document" : Archives.Contains(ext) ? "archive" : "file";
    }
    public static bool PackingOnly(string[] paths) => paths.Length > 0 && paths.All(path => Directory.Exists(path) || Category(path) == "file");
    private static string[] Targets(string ext)
    {
        if (OfficeSlides.Contains(ext))
            return OfficeBridge.Available("PowerPoint") ? ["pdf", "jpg", "png", "pptx", "txt", "ppt", "odp"] : ["pdf", "jpg", "png", "txt"];
        if (OfficeWords.Contains(ext))
            return OfficeBridge.Available("Word") ? ["pages", "pdf", "txt", "md", "html", "epub", "png", "jpg", "docx", "doc", "rtf", "odt"] : ext is "rtf" or "rtfd" ? ["pages", "pdf", "docx", "txt", "html", "epub", "md"] : ["pages", "pdf", "txt", "md", "html", "epub", "png", "jpg"];
        if (OfficeSheets.Contains(ext))
            return OfficeBridge.Available("Excel") ? ["ods", "csv", "tsv", "pdf", "xlsx", "xls", "json", "txt"] : ext is "xlsx" or "xlsm" ? ["ods", "csv", "tsv", "pdf", "json", "txt"] : ext is "csv" or "tsv" ? ["xlsx", "ods", "csv", "tsv", "json", "txt"] : ["ods", "csv", "tsv", "pdf", "txt"];
        if (ext == "epub")
            return ["pdf", "docx", "pages", "txt", "md", "html"];
        if (ext is "md" or "markdown")
            return ["pdf", "docx", "pages", "epub", "html", "txt"];
        return ext is "jpg" or "png" ? [.. ImageTargets, "docx"] : Images.Contains(ext) ? ImageTargets : Audio.Contains(ext) ? Audio : Video.Contains(ext) ? [.. Video, "gif", "mp3", "m4a", "wav"] : ext == "gif" ? [.. Video, "mp4", "webm"] : ext == "pdf" ? ["docx", "pptx", "xlsx", "epub", "md", "jpg", "png", "txt"] : ext == "txt" ? ["pdf", "docx", "md", "jpg", "png", "srt", "vtt"] : ext is "srt" or "vtt" ? ["srt", "vtt", "txt"] : Archives;
    }
    public static readonly Operation[] FileActions = [
        new("action:float", "Float", true),
        new("action:copy", "Copy", true),
        new("action:move", "Move", true),
        new("action:copyPath", "Copy Path", true),
        new("action:terminal", "Terminal", true),
        new("action:share", "Share", true),
        new("action:metadata", "Strip EXIF", true)
    ];

    public static List<Operation> Options(string[] paths, WheelMode mode)
    {
        if (paths.Length == 0 || paths.Any(p => !File.Exists(p) && !Directory.Exists(p)))
            return [];
        if (mode == WheelMode.Actions)
            return FileActions.ToList();
        return Arrange(Build(paths, mode == WheelMode.Tools), Category(paths[0]), mode == WheelMode.Tools, true);
    }

    public static List<Operation> Options(string[] paths, bool tools) =>
        Options(paths, tools ? WheelMode.Tools : WheelMode.Convert);

    // --- the order of the wheel: the user's own order, and the option used last at the top --------------------
    public const string LastFirstKey = "wheelLastFirst";
    public static bool LastFirst => Settings.GetBool(LastFirstKey, true);
    private static string Mode(bool tools) => tools ? "tools" : "formats";
    public static bool IsToolId(string id) => !id.StartsWith("convert:") && !id.StartsWith("pack:");

    public static List<string> SavedOrder(string kind, bool tools)
    {
        try
        { return System.Text.Json.JsonSerializer.Deserialize<List<string>>(Settings.GetString($"wheelOrder:{kind}:{Mode(tools)}") ?? "[]") ?? []; }
        catch (System.Text.Json.JsonException) { return []; }
    }

    public static void SaveOrder(string kind, bool tools, List<string>? ids) =>
        Settings.Set($"wheelOrder:{kind}:{Mode(tools)}", ids == null ? "" : System.Text.Json.JsonSerializer.Serialize(ids));

    public static void RememberLast(string[] paths, Operation operation)
    {
        if (paths.Length > 0 && operation.Id != Flows.MenuId)
            Settings.Set($"wheelLast:{Category(paths[0])}:{Mode(IsToolId(operation.Id))}", operation.Id);
    }

    private static List<Operation> Arrange(List<Operation> list, string kind, bool tools, bool markRecent)
    {
        var order = SavedOrder(kind, tools);
        var result = list.Select((operation, index) => (operation, index))
            .OrderBy(x => order.IndexOf(x.operation.Id) is int at and >= 0 ? at : int.MaxValue).ThenBy(x => x.index)
            .Select(x => x.operation).ToList();
        if (markRecent && LastFirst && Settings.GetString($"wheelLast:{kind}:{Mode(tools)}") is { Length: > 0 } last)
        {
            // A tool used on its own may now be part of a combined entry; that entry moves up instead.
            int at = result.FindIndex(o => o.Id == last);
            if (at < 0)
                at = result.FindIndex(o => o.Parts?.Contains(last) == true);
            if (at >= 0)
            {
                var recent = result[at] with { Recent = true };
                result.RemoveAt(at);
                result.Insert(0, recent);
            }
        }
        return result;
    }

    // What the wheel offers for a kind of file, in its current order, for arranging it (one file and several files together).
    public static List<Operation> Sample(string kind, bool tools)
    {
        string[] extensions = kind switch { "image" => Images, "video" => Video, "audio" => Audio, "document" => ["pdf", "txt", "srt", "vtt"], _ => Archives };
        var all = new List<Operation>();
        foreach (string extension in tools ? extensions.Take(1) : extensions)
            foreach (var paths in new[] { new[] { "x." + extension }, new[] { "x." + extension, "y." + extension } })
                foreach (var operation in Build(paths, tools))
                    if (!all.Any(o => o.Id == operation.Id))
                        all.Add(operation);
        return Arrange(all, kind, tools, false);
    }

    private static List<Operation> Build(string[] paths, bool tools)
    {
        if (tools)
        {
            var ids = Tools(paths[0], paths.Length).ToList();
            foreach (string path in paths.Skip(1))
                ids = ids.Intersect(Tools(path, paths.Length)).ToList();
            ids = Merge(Category(paths[0]), ids);
            var chosen = ids.Select(id => Definition(id, Category(paths[0]))).Select(o => paths.Length > 1 && o.Chain ? o with { Chain = false } : o).ToList();
            var flows = Flows.For(paths);
            // Flows follow the tools; if they would make the wheel too crowded they share one entry.
            if (!TwoWheels && chosen.Count + flows.Count >= 10 && flows.Count > 1)
                chosen.Add(new Operation(Flows.MenuId, L.T("Flows…"), true));
            else
                chosen.AddRange(flows);
            return chosen;
        }
        if (PackingOnly(paths))
            return Archives.Select(target => new Operation("pack:" + target, L.T("Pack ") + (target == "gz" ? "GZIP" : target.ToUpperInvariant()))).ToList();
        string ext = Extension(paths[0]);
        var targets = Targets(ext).ToList();
        foreach (string path in paths.Skip(1))
            targets = targets.Intersect(Targets(Extension(path))).ToList();
        return targets.Where(target => !paths.All(p => Extension(p) == target)).Select(target => new Operation("convert:" + target, target == "gz" ? "GZIP" : target.ToUpperInvariant())).ToList();
    }
    public static string[] ToolIds(string kind) => Tools(kind switch { "image" => "x.jpg", "video" => "x.mp4", "audio" => "x.mp3", _ => "x.pdf" }, 1);
    private static string[] Tools(string path, int count)
    {
        string kind = Category(path), ext = Extension(path);
        if (kind == "image")
        {
            if (ext == "svg")
                return count > 1 ? ["createPDF", "createCollage", "createAnimation", "packArchive"] : ["resizeImage", "makeIcon"];
            if (ext == "bmp")
                return count > 1 ? ["compress", "rotateImage", "resizeImage", "watermark", "createPDF", "createCollage", "createAnimation", "packArchive"] : ["compress", "editImage", "frameImage", "cropImage", "rotateImage", "resizeImage", "watermark", "annotateImage", "makeIcon", "ocrImage", "redactImage"];
            return count > 1 ? ["compress", "removeMetadata", "location", "rotateImage", "resizeImage", "watermark", "createPDF", "createCollage", "createAnimation", "packArchive"] : ["compress", "removeMetadata", "location", "editImage", "frameImage", "cropImage", "rotateImage", "resizeImage", "watermark", "annotateImage", "makeIcon", "ocrImage", "redactImage"];
        }
        if (kind == "audio")
            return count > 1 ? ["compress", "normalizeAudio", "audioEffects", "joinAudio", "packArchive"] : ["compress", "removeMetadata", "normalizeAudio", "audioToVideo", "trimAudio", "audioChannels", "audioEffects", "ringtone", "redactAudio"];
        if (kind == "video")
            return ext == "gif" ? ["removeMetadata"] : count > 1 ? ["compress", "location", "muteVideo", "rotateVideo", "videoSettings", "watermark", "joinVideos", "packArchive"] : ["compress", "editVideo", "removeMetadata", "location", "muteVideo", "trimVideo", "cropVideo", "rotateVideo", "changeVideoSpeed", "videoSnapshots", "splitVideo", "videoSettings", "videoEffects", "videoToGif", "watermark", "subtitlesAudio", "redactVideo"];
        if (kind == "office")
        {
            string family = OfficeSlides.Contains(ext) ? "PowerPoint" : OfficeWords.Contains(ext) ? "Word" : "Excel";
            bool render = OfficeBridge.Available(family), modern = new[] { "pptx", "pptm", "ppsx", "docx", "docm", "xlsx", "xlsm", "xlsb" }.Contains(ext);
            if (count > 1)
                return render ? ["officeMergePDF"] : [];
            return render ? modern ? ["officePdf", "removeMetadata"] : ["officePdf"] : modern ? ["removeMetadata"] : [];
        }
        if (ext == "pdf")
            return count > 1 ? ["compress", "splitPDF", "mergePDF", "watermark", "packArchive"] : ["compress", "removeMetadata", "splitPDF", "organizePDF", "pdfPassword", "pdfNumbers", "extractPdfImages", "watermark", "redactPDF", "ocrPDF"];
        if (kind == "file")
            return ["packArchive"];
        return Archives.Contains(ext) ? ["extractArchive"] : [];
    }
    private static Field N(string name, string label, string value) => new(name, label, value, "number");
    private static Field T(string name, string label, string value = "", string kind = "text") => new(name, label, value, kind);
    private static Field C(string name, string label, string value, params string[] choices) => new(name, label, value, "choice", choices);
    private static Field[] Crop => [N("x", L.T("Left x (px)"), "0"), N("y", L.T("Top y (px)"), "0"), N("width", L.T("Width (px)"), "0"), N("height", L.T("Height (px)"), "0")];
    private static Field[] Rotation(bool video) => [N("angle", L.T("Rotation angle (0–360°, clockwise)"), "0"), C("flip", L.T("Flip"), "none", "none", "horizontal", "vertical"), C("expand", L.T("Canvas on free rotation"), video ? "expand" : "crop", video ? ["expand", "keep"] : ["crop", "expand", "keep"]), T("background", video ? L.T("Fill colour for the empty corners") : L.T("Padding colour (blank for transparent)"), video ? "#000000" : "")];
    private static Field[] Positions => [C("position", L.T("Position"), "bottomRight", "bottomRight", "bottomCenter", "bottomLeft", "middleRight", "center", "middleLeft", "topRight", "topCenter", "topLeft")];
    private static Field[] Times => [N("start", L.T("Start (seconds or h:m:s)"), "0"), N("end", L.T("End (0 = end of file)"), "0")];
    private static Field[] Ratio => [C("ratio", L.T("Aspect ratio"), "Free Style", "Free Style", "1:1 (Square)", "16:9 (Widescreen)", "4:3 (Standard)", "9:16 (Story / Reel)", "3:2 (Classic Photo)", "Original Ratio", "custom"), N("ratioWidth", L.T("Ratio width"), "3"), N("ratioHeight", L.T("Ratio height"), "2")];
    public static Operation Definition(string id, string kind) => MergedDefinition(id) ?? id switch
    {
        "officePdf" => new(id, L.T("Export pages"), true, [T("pageOrder", L.T("Pages to export (comma-separated, blank for all)"))]),
        "officeMergePDF" => new(id, L.T("Merge into PDF"), true, [], true),
        "editVideo" => new(id, L.T("Video Studio"), true, [C("mode", L.T("Tool"), "trim", "trim", "crop", "split"), C("ratio", L.T("Aspect Ratio"), "Free Style (Custom Drag)", "Free Style (Custom Drag)", "1:1 (Square)", "16:9 (Widescreen)", "4:3 (Standard)", "9:16 (Story / Reel)", "3:2 (Classic Photo)"), C("parts", L.T("Equal Parts"), "2", "2", "3", "4", "5", "6"), .. Times, .. Crop]),
        "compress" => new(id, L.T("Compress"), true, kind == "audio" ? [C("targetSize", L.T("Max target size"), "Auto", "Auto", "1 MB", "2 MB", "5 MB", "10 MB", "25 MB"), N("bitrate", L.T("Bitrate (kbps)"), "96"), N("targetKB", L.T("Target size (KB, 0 = no limit)"), "0")] : [N("quality", kind == "video" ? L.T("CRF (higher = smaller file)") : L.T("Quality (1–100)"), kind == "video" ? "28" : "75"), C("maxEdge", L.T("Longest side"), "Original", kind == "video" ? ["Original", "1920 (1080p)", "1280 (720p)", "854 (480p)"] : ["Original", "2560 (2K)", "1920 (Full HD)", "1280 (Web)", "800 (Compact)"]), C("targetSize", L.T("Max target size"), "Auto", "Auto", "200 KB", "500 KB", "1 MB", "2 MB", "5 MB", "10 MB", "25 MB", "50 MB", "100 MB"), N("targetKB", L.T("Target size (KB, 0 = no limit)"), "0")]),
        "removeMetadata" => new(id, L.T("Metadata"), true, [T("remove", L.T("Remove all metadata"), "true", "bool"), T("search", L.T("Search metadata fields")), T("metadata", L.T("Metadata fields (editable when “Remove all” is off)"), "{}", "metadata")]),
        "editImage" => new(id, L.T("Edit image"), true, [N("exposure", L.T("Exposure (EV)"), "0"), N("contrast", L.T("Contrast (1 = original)"), "1"), N("saturation", L.T("Saturation (1 = original)"), "1"), N("temperature", L.T("Temperature (-100 to 100)"), "0"), N("shadows", L.T("Shadows (-100 to 100)"), "0"), N("highlights", L.T("Highlights (-100 to 100)"), "0"), N("clarity", L.T("Clarity (0–100)"), "0"), N("dehaze", L.T("Dehaze (0–100)"), "0"), N("denoise", L.T("Noise reduction (0–30)"), "0"), N("grain", L.T("Grain (0–100)"), "0"), T("annotations", L.T("Annotations (JSON, optional)"), "", "json")]),
        "frameImage" => new(id, L.T("Add background"), true, [N("canvasWidth", L.T("Canvas width"), "1400"), N("canvasHeight", L.T("Canvas height"), "1000"), N("padding", L.T("Padding"), "80"), N("radius", L.T("Corner radius"), "24"), N("shadow", L.T("Shadow"), "20"), T("background", L.T("Background colour"), "#f0ebff"), T("gradient", L.T("Gradient end colour")), T("backgroundImage", L.T("Background image"), "", "file"), N("backgroundBlur", L.T("Background blur"), "0")]),
        "annotateImage" => new(id, L.T("Annotate image"), true, [T("text", L.T("Annotation text"), "APPROVED"), T("color", L.T("Text colour"), "#ff6500"), C("position", L.T("Position"), "bottom_right", "bottom_right", "bottom_left", "top_right", "top_left", "center")]),
        "cropImage" => new(id, L.T("Crop"), true, [.. Crop, .. Ratio]),
        "resizeImage" => new(id, L.T("Resize"), true, [C("mode", L.T("Mode"), "percent", "percent", "edge", "size"), N("percent", L.T("Scale (%)"), "50"), N("edge", L.T("Longest side (px)"), "1920"), N("width", L.T("Width (pixels, 0 = any)"), "0"), N("height", L.T("Height (pixels, 0 = any)"), "0"), T("keepRatio", L.T("Keep the ratio when both width and height are given"), "true", "bool")]),
        "watermark" => new(id, L.T("Watermark"), true, [T("text", L.T("Watermark text"), "CONFIDENTIAL"), T("logo", L.T("Watermark picture (optional)"), "", "file:image"), C("repeats", L.T("Repeats / Pattern"), "Single (Center)", "Single (Center)", "Single (Bottom Right)", "4 (2×2 Grid)", "9 (3×3 Grid)", "16 (4×4 Dense Grid)", "Tiled Pattern (Full Page)"), C("angle", L.T("Angle / Rotation"), "45° (Diagonal)", "45° (Diagonal)", "0° (Horizontal)", "30° (Subtle Angle)", "-45° (Inverse Diagonal)", "90° (Vertical)"), C("size", L.T("Text Size"), "48 pt (Large)", "18 pt (Small)", "32 pt (Medium)", "48 pt (Large)", "72 pt (Extra Large)", "96 pt (Huge)"), C("opacity", L.T("Opacity"), "35%", "20%", "35%", "50%", "70%", "90%"), C("color", L.T("Text colour"), "#ffffff", "#ffffff", "#000000", "#ff6500", "#ef4444", "#3b82f6", "#10b981", "#f59e0b"), .. Positions, C("layout", L.T("Layout"), "single", "single", "tiled"), N("textSize", L.T("Text size (% of the short side)"), "5"), N("scale", L.T("Logo width (% of the picture)"), "20"), N("rotation", L.T("Angle"), "0"), N("margin", L.T("Margin (% of the short side)"), "3")]),
        "makeIcon" => new(id, L.T("Make icons"), true, [C("iconKind", L.T("Output"), "ico", "ico", "favicon")]),
        "ocrImage" => new(id, L.T("Text recognition (OCR)"), true, [T("language", L.T("Language (auto = system languages, e.g. zh-Hans-CN, en-US)"), "auto"), C("output", L.T("Output"), "txt", "txt", "pdf")]),
        "ocrPDF" => new(id, L.T("Text recognition (OCR)"), true, [T("language", L.T("Language (auto = system languages, e.g. zh-Hans-CN, en-US)"), "auto"), C("output", L.T("Output"), "txt", "txt", "pdf"), T("password", L.T("PDF password (if needed)"), "", "password")]),
        "createAnimation" => new(id, L.T("Animation / slideshow"), true, [C("format", L.T("Output"), "gif", "gif", "mp4"), N("seconds", L.T("Seconds per picture"), "1"), N("maxEdge", L.T("Longest side (px)"), "720"), T("loop", L.T("Loop the GIF"), "true", "bool")], true),
        "videoToGif" => new(id, L.T("Make a GIF"), true, [.. Times, N("fps", L.T("Frame rate"), "12"), N("width", L.T("Width (px)"), "480"), T("loop", L.T("Loop"), "true", "bool")]),
        "videoSettings" => new(id, L.T("Resolution / frame rate"), true, [C("height", L.T("Resolution (height)"), "original", "original", "2160", "1440", "1080", "720", "480", "360"), N("fps", L.T("Frame rate (0 = unchanged)"), "0")]),
        "videoEffects" => new(id, L.T("Fade / reverse / loop"), true, [N("fadeIn", L.T("Fade in (seconds)"), "0"), N("fadeOut", L.T("Fade out (seconds)"), "0"), T("reverse", L.T("Play backwards (up to 2 minutes)"), "false", "bool"), N("loops", L.T("Repeat count (1 = no repeat)"), "1")]),
        "subtitlesAudio" => new(id, L.T("Subtitles / soundtrack"), true, [T("subtitleFile", L.T("Subtitle file (.srt / .ass / .vtt)"), "", "file:subtitle"), N("subtitleSize", L.T("Subtitle size"), "22"), T("audioFile", L.T("Audio file (replaces or is mixed in)"), "", "file:audio"), T("mix", L.T("Mix with the original sound (off replaces it)"), "false", "bool"), N("volume", L.T("Volume of the new audio (1 = original)"), "1")]),
        "audioEffects" => new(id, L.T("Volume / fades"), true, [N("gainDb", L.T("Volume change (dB)"), "0"), N("fadeIn", L.T("Fade in (seconds)"), "0"), N("fadeOut", L.T("Fade out (seconds)"), "0"), T("denoise", L.T("Reduce background noise"), "false", "bool")]),
        "joinAudio" => new(id, L.T("Join audio"), true, [], true),
        "ringtone" => new(id, L.T("Phone ringtone"), true, [N("start", L.T("Start (seconds)"), "0"), N("length", L.T("Length (seconds, up to 40)"), "30")]),
        "pdfPassword" => new(id, L.T("PDF password"), true, [C("mode", L.T("Action"), "add", "add", "remove"), T("password", L.T("Current password (if encrypted)"), "", "password"), T("newPassword", L.T("New password (when adding protection)"), "", "password")]),
        "pdfNumbers" => new(id, L.T("Page numbers / header & footer"), true, [T("numberFormat", L.T("Page number format ({n} = this page, {total} = page count)"), "{n} / {total}"), C("position", L.T("Page number position"), "bottomRight", "bottomRight", "bottomCenter", "bottomLeft", "topRight", "topCenter", "topLeft"), N("startAt", L.T("First page number"), "1"), T("header", L.T("Header text")), T("footer", L.T("Footer text")), N("fontSize", L.T("Font size"), "10"), T("password", L.T("PDF password (if needed)"), "", "password")]),
        "extractPdfImages" => new(id, L.T("Extract images"), true, [N("minSize", L.T("Skip pictures whose short side is smaller than (pixels)"), "64"), T("password", L.T("PDF password (if needed)"), "", "password")]),
        "packArchive" => new(id, L.T("Encrypted / split archive"), true, [C("format", L.T("Format"), "zip", "zip", "7z"), T("password", L.T("Password (optional)"), "", "password"), N("level", L.T("Compression level (1–9)"), "5"), N("splitMB", L.T("Volume size (MB, 0 = one file)"), "0")], false),
        "rotateImage" or "rotateVideo" => new(id, L.T("Rotate / flip"), true, Rotation(id == "rotateVideo")),
        "redactImage" => new(id, L.T("Redact"), true, [.. Crop, C("style", L.T("Redaction style"), "pixelate", "pixelate", "blur", "solid"), N("blockSize", L.T("Pixel block size (px)"), "12"), T("color", L.T("Fill colour"), "#000000"), T("regions", L.T("Multiple regions"), "", "json")]),
        "createPDF" => new(id, L.T("Make PDF"), true, [], true),
        "createCollage" => new(id, L.T("Collage"), true, [C("layout", L.T("Layout"), "grid", "grid", "row", "column", "featured"), N("canvasWidth", L.T("Canvas width"), "1600"), N("canvasHeight", L.T("Canvas height"), "1200"), N("columns", L.T("Grid columns (0 = auto)"), "0"), N("gap", L.T("Gap"), "16"), N("radius", L.T("Corner radius"), "0"), T("background", L.T("Background colour"), "#ffffff")], true),
        "muteVideo" => new(id, L.T("Remove audio"), true),
        "location" => new(id, L.T("Location"), true, [C("mode", L.T("Action"), "strip", "strip", "set"), T("coordinates", L.T("New location (latitude, longitude)")), T("locationSource", L.T("Or use the location of another photo"), "", "file:image")]),
        "redactPDF" => new(id, L.T("Redact PDF"), true, [N("pageNumber", L.T("Page"), "1"), T("findText", L.T("Also black out this text wherever it appears (optional)")), T("password", L.T("PDF password (if needed)"), "", "password"), T("regions", L.T("Multiple regions"), "", "json")]),
        "trimVideo" => new(id, L.T("Trim"), true, Times),
        "cropVideo" => new(id, L.T("Crop frame"), true, [.. Crop, .. Ratio]),
        "changeVideoSpeed" => new(id, L.T("Speed"), true, [C("speed", L.T("Speed multiplier"), "1.5", "0.5", "0.75", "1.25", "1.5", "2.0")]),
        "joinVideos" => new(id, L.T("Join videos"), true, [], true),
        "videoSnapshots" => new(id, L.T("Save frames"), true, [N("time", L.T("Time (seconds)"), "0"), N("frame", L.T("Frame offset"), "0"), T("times", L.T("Several times (seconds, comma-separated)")), T("sheet", L.T("Combine into one contact sheet"), "false", "bool"), N("sheetCount", L.T("Thumbnails in the sheet"), "12"), N("sheetColumns", L.T("Columns in the sheet"), "4")]),
        "splitVideo" => new(id, L.T("Split"), true, [C("parts", L.T("Number of equal parts"), "2", "2", "3", "4", "5", "6"), T("splitPoints", L.T("Custom split points (seconds, comma-separated)"))]),
        "redactVideo" => new(id, L.T("Redact"), true, [.. Crop, .. Times, C("style", L.T("Redaction style"), "pixelate", "pixelate", "blur", "solid"), N("blockSize", L.T("Pixel block size (px)"), "12"), T("regions", L.T("Regions and their time ranges"), "", "json")]),
        "normalizeAudio" => new(id, L.T("Normalize loudness"), true, [C("loudness", L.T("Target LUFS"), "-16 (Podcast/Web)", "-16 (Podcast/Web)", "-14 (Streaming/Music)", "-23 (Broadcast/EBU)"), N("range", L.T("Loudness range (LRA)"), "11"), N("peak", L.T("True peak (dBTP)"), "-1.5")]),
        "audioToVideo" => new(id, L.T("Waveform video"), true, [C("aspect", L.T("Aspect ratio"), "landscape", "landscape", "portrait", "square"), T("backgroundImage", L.T("Still background image (blank = waveform)"), "", "file")]),
        "trimAudio" => new(id, L.T("Trim audio"), true, [.. Times, T("removeSilence", L.T("Remove silence at the start and end"), "false", "bool")]),
        "audioChannels" => new(id, L.T("Channels"), true, [C("channels", L.T("Output channels"), "mono", "mono", "stereo"), N("leftGain", L.T("Left volume (1 = original)"), "1"), N("rightGain", L.T("Right volume (1 = original)"), "1")]),
        "redactAudio" => new(id, L.T("Bleep"), true, [.. Times, T("ranges", L.T("Multiple ranges"), "", "json")]),
        "splitPDF" => new(id, L.T("Split PDF"), true, [N("pagesPerFile", L.T("Pages per file"), "1"), T("password", L.T("PDF password (if needed)"), "", "password")]),
        "mergePDF" => new(id, L.T("Merge PDFs"), true, [T("password", L.T("PDF password (if needed)"), "", "password")], true),
        "organizePDF" => new(id, L.T("Pages"), true, [C("action", L.T("Quick action"), "none", "none", "Reverse All Pages", "Rotate All 90°", "Rotate All 180°", "Rotate All 270°", "Extract Even Pages", "Extract Odd Pages", "Delete First Page", "Delete Last Page"), T("pageOrder", L.T("Page order (pages may repeat or be left out)")), N("rotation", L.T("Rotate all pages (0/90/180/270)"), "0"), T("rotations", L.T("Per-page rotation, e.g. {\"1\": 90}"), "{}", "json"), T("password", L.T("PDF password (if needed)"), "", "password")]),
        "extractArchive" => new(id, L.T("Extract"), true, [T("password", L.T("Archive password (if needed)"), "", "password")]),
        _ => throw new ArgumentException(L.T("Unknown tool ") + id)
    };
}
