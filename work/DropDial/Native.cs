using System;
using System.Runtime.InteropServices;
using System.Text;

namespace DropDial;

internal static class Native
{
    [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT point);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);
    [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int key);
    [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern int GetSystemMetrics(int index);
    [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(POINT point);
    [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr hwnd, uint gaFlags);

    public static bool ShellFileWindow()
    {
        IntPtr fg = GetForegroundWindow();
        if (IsShellClass(fg)) return true;
        if (GetCursorPos(out var pt))
        {
            IntPtr atPt = WindowFromPoint(pt);
            if (IsShellClass(atPt)) return true;
            IntPtr root = GetAncestor(atPt, 2);
            if (root != IntPtr.Zero && IsShellClass(root)) return true;
        }
        return true;
    }

    private static bool IsShellClass(IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero) return false;
        var name = new StringBuilder(256);
        GetClassName(hwnd, name, name.Capacity);
        string cls = name.ToString();
        return cls is "CabinetWClass" or "ExploreWClass" or "Progman" or "WorkerW" or "ShellTabWindowClass" or "Shell_TrayWnd" or "DirectUIHWND" or "Windows.UI.Core.CoreWindow";
    }
    // Lets a window in another process come to the front; used when a second launch asks the running copy to show itself.
    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)] public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);
    [DllImport("user32.dll")] public static extern bool AllowSetForegroundWindow(int processId);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int width, int height, uint flags);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hwnd);
    [DllImport("user32.dll", SetLastError = true)] public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
    [DllImport("user32.dll", SetLastError = true)] public static extern bool UnregisterHotKey(IntPtr hWnd, int id);
    public delegate IntPtr HookProc(int nCode, IntPtr wParam, IntPtr lParam);
    [DllImport("user32.dll", SetLastError = true)] public static extern IntPtr SetWindowsHookEx(int idHook, HookProc lpfn, IntPtr hMod, uint dwThreadId);
    [DllImport("user32.dll", SetLastError = true)] public static extern bool UnhookWindowsHookEx(IntPtr hhk);
    [DllImport("user32.dll")] public static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);
    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)] public static extern IntPtr GetModuleHandle(string? lpModuleName);
    public const int WH_KEYBOARD_LL = 13;
    public const int WM_KEYDOWN = 0x0100;
    public const int WM_KEYUP = 0x0101;
    public const int WM_SYSKEYDOWN = 0x0104;
    public const int WM_SYSKEYUP = 0x0105;
    public const uint MOD_ALT = 0x0001;
    public const uint MOD_CONTROL = 0x0002;
    public const uint MOD_SHIFT = 0x0004;
    public const uint MOD_WIN = 0x0008;
    public const uint MOD_NOREPEAT = 0x4000;
    public const int WM_HOTKEY = 0x0312;
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
    [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);

    public static void ForceForeground(IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero) return;
        try
        {
            AllowSetForegroundWindow(-1);
            IntPtr fg = GetForegroundWindow();
            uint fgThread = fg != IntPtr.Zero ? GetWindowThreadProcessId(fg, out _) : 0;
            uint curThread = GetCurrentThreadId();
            if (fgThread != 0 && fgThread != curThread)
            {
                AttachThreadInput(curThread, fgThread, true);
                SetForegroundWindow(hwnd);
                BringWindowToTop(hwnd);
                SetWindowPos(hwnd, new IntPtr(-1), 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0040); // SWP_NOSIZE | SWP_NOMOVE | SWP_SHOWWINDOW
                AttachThreadInput(curThread, fgThread, false);
            }
            else
            {
                SetForegroundWindow(hwnd);
                BringWindowToTop(hwnd);
                SetWindowPos(hwnd, new IntPtr(-1), 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0040);
            }
        }
        catch { }
    }

    public static bool Down(int key) => (GetAsyncKeyState(key) & 0x8000) != 0;
    public static bool IsShiftDown() => Down(0x10) || Down(0xA0) || Down(0xA1);
    public static bool IsCtrlDown() => Down(0x11) || Down(0xA2) || Down(0xA3);
    public static bool IsAltDown() => Down(0x12) || Down(0xA4) || Down(0xA5);
}
