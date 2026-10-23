using System;

namespace DropDial;

internal enum DragMenuRequest { None, Convert, Tools, Actions }

internal sealed class DragShortcutTracker(int horizontalThreshold, int verticalThreshold)
{
    private bool down, candidate, moved, triggered, suppressed;
    private int startX, startY, previousChord;
    public void Cancel() => suppressed = true;

    public DragMenuRequest Update(bool mouseDown, bool shift, bool control, bool alt, int x, int y, bool shellSource)
    {
        int chord = 0;
        if (alt && !shift && !control)
            chord = 3; // Actions (Alt)
        else if ((control && !alt) || (shift && control && !alt))
            chord = 2; // Tools (Ctrl or Shift + Ctrl)
        else if (shift && !control && !alt)
            chord = 1; // Convert (Shift)

        if (!mouseDown)
        {
            down = candidate = moved = triggered = suppressed = false;
            previousChord = chord;
            return DragMenuRequest.None;
        }

        if (!down)
        {
            down = true;
            candidate = shellSource;
            startX = x;
            startY = y;
            previousChord = chord;
        }

        moved |= Math.Abs((long)x - startX) >= Math.Max(2, horizontalThreshold) ||
                 Math.Abs((long)y - startY) >= Math.Max(2, verticalThreshold);

        DragMenuRequest request = DragMenuRequest.None;
        if (candidate && moved && !suppressed && chord != 0)
        {
            if (!triggered || chord != previousChord)
            {
                triggered = true;
                request = chord switch
                {
                    3 => DragMenuRequest.Actions,
                    2 => DragMenuRequest.Tools,
                    _ => DragMenuRequest.Convert
                };
            }
        }

        previousChord = chord;
        return request;
    }
}
