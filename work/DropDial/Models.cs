using System.Collections.Generic;

namespace DropDial;

internal enum WheelMode
{
    Convert,
    Tools,
    Actions
}

internal sealed record ConversionJob(string[] Paths, string Action, Dictionary<string, string>? Parameters = null);
internal sealed record FileResult(string Input, string? Output, string? Error);
internal sealed record BatchResult(FileResult[] Files);
internal sealed record JobProgress(string Phase, int Processed, int Total, string? Current = null);
