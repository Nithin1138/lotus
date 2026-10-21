using System.Collections.Generic;
using System.Diagnostics;
using System;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Text.Json;
using System.Threading.Channels;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Threading;
using Forms = System.Windows.Forms;

namespace DropDial;

internal static class Program
{
    internal static void SavePng(System.Windows.Media.Imaging.BitmapSource bitmap, string path)
    {
        var encoder = new System.Windows.Media.Imaging.PngBitmapEncoder();
        encoder.Frames.Add(System.Windows.Media.Imaging.BitmapFrame.Create(bitmap));
        using var stream = File.Create(path);
        encoder.Save(stream);
    }

    private static string WritableResultPath()
    {
        string preferred = Path.Combine(AppContext.BaseDirectory, "last-cli-result.json");
        try
        {
            using (File.Open(preferred, FileMode.OpenOrCreate, FileAccess.Write)) { }
            return preferred;
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
        {
            Directory.CreateDirectory(Journal.DirectoryPath);
            return Path.Combine(Journal.DirectoryPath, "last-cli-result.json");
        }
    }

    [STAThread]
    public static int Main(string[] args)
    {
        // Optional 5th argument: a scene such as "crop=250,200,800,600;ratio=4:3" or "busy" (see ToolWindow.DebugScene).
        if (args.Length is 4 or 5 && args[0] == "--debug-tool-render")
        {
            var testApp = new System.Windows.Application { ShutdownMode = ShutdownMode.OnMainWindowClose };
            var window = new ToolWindow([args[2]], Catalog.Definition(args[1], Catalog.Category(args[2])), Backend.Execute);
            window.Loaded += async (_, _) =>
            {
                for (int attempt = 0; attempt < 150 && !window.DebugReady; attempt++)
                    await Task.Delay(100);
                if (args.Length == 5)
                {
                    window.DebugScene(args[4]);
                    await Task.Delay(700);
                }
                window.UpdateLayout();
                var bitmap = new System.Windows.Media.Imaging.RenderTargetBitmap((int)window.ActualWidth, (int)window.ActualHeight, 96, 96, System.Windows.Media.PixelFormats.Pbgra32);
                var background = new System.Windows.Media.DrawingVisual();
                using (var dc = background.RenderOpen())
                    dc.DrawRoundedRectangle(window.Background, null, new Rect(0, 0, window.ActualWidth, window.ActualHeight),
                        window.WindowState == WindowState.Maximized ? 0 : UiTheme.WindowCornerRadius,
                        window.WindowState == WindowState.Maximized ? 0 : UiTheme.WindowCornerRadius);
                bitmap.Render(background);
                bitmap.Render((System.Windows.Media.Visual)window.Content);
                SavePng(bitmap, args[3]);
                window.Close();
            };
            testApp.Run(window);
            return 0;
        }
        if (args.Length == 3 && args[0] == "--debug-media-test")
        {
            var testApp = new System.Windows.Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
            var media = new System.Windows.Controls.MediaElement { LoadedBehavior = System.Windows.Controls.MediaState.Manual, UnloadedBehavior = System.Windows.Controls.MediaState.Stop, Height = 220 };
            var slider = new System.Windows.Controls.Slider();
            string? error = null;
            var transport = new MediaTransport(media, slider, [args[1]], Catalog.Category(args[1]) == "audio", false, (_, _, _, _) => throw new InvalidOperationException("Unexpected compatibility fallback"), CancellationToken.None, text => error = text);
            var panel = new System.Windows.Controls.StackPanel();
            panel.Children.Add(media);
            panel.Children.Add(transport);
            media.Volume = 0;
            var window = new Window { Width = 620, Height = 420, ShowActivated = false, ShowInTaskbar = false, Title = L.T("DropDial player check") };
            UiTheme.Apply(window);
            window.Content = UiTheme.Frame(window, panel);
            window.Loaded += async (_, _) =>
            {
                bool passed = false;
                bool videoFrameVisible = Catalog.Category(args[1]) == "audio";
                double advanced = 0, paused = 0, sought = 0;
                try
                {
                    transport.SetDuration(35);
                    await transport.Toggle();
                    for (int i = 0; i < 100 && !transport.IsPlaying; i++)
                        await Task.Delay(100);
                    await Task.Delay(1000);
                    advanced = media.Position.TotalSeconds;
                    if (!videoFrameVisible && media.ActualWidth > 0 && media.ActualHeight > 0)
                    {
                        var frame = new System.Windows.Media.Imaging.RenderTargetBitmap((int)media.ActualWidth, (int)media.ActualHeight, 96, 96, System.Windows.Media.PixelFormats.Pbgra32);
                        frame.Render(media);
                        var pixels = new byte[frame.PixelWidth * frame.PixelHeight * 4];
                        frame.CopyPixels(pixels, frame.PixelWidth * 4, 0);
                        int lit = 0;
                        for (int y = 0; y < frame.PixelHeight; y += 10)
                            for (int x = 0; x < frame.PixelWidth; x += 10)
                            { int p = (y * frame.PixelWidth + x) * 4; if (pixels[p] + pixels[p + 1] + pixels[p + 2] > 90) lit++; }
                        videoFrameVisible = lit > 10;
                        SavePng(frame, args[2] + ".frame.png");
                    }
                    transport.Pause();
                    paused = media.Position.TotalSeconds;
                    await Task.Delay(350);
                    bool holds = Math.Abs(media.Position.TotalSeconds - paused) < .15;
                    await transport.Seek(10);
                    await Task.Delay(400);
                    sought = media.Position.TotalSeconds;
                    passed = advanced > .1 && holds && Math.Abs(sought - 10) < .5 && error == null && videoFrameVisible;
                }
                catch (Exception ex) { error = ex.Message; }
                finally { transport.Dispose(); File.WriteAllText(args[2], JsonSerializer.Serialize(new { passed, advanced, paused, sought, videoFrameVisible, error })); window.Close(); testApp.Shutdown(); }
            };
            window.Show();
            testApp.Run();
            return 0;
        }
        if (args.Length == 3 && args[0] == "--capabilities")
        {
            string[] files = [args[1]];
            File.WriteAllText(args[2], JsonSerializer.Serialize(new { Category = Catalog.Category(args[1]), Conversions = Catalog.Options(files, false), Tools = Catalog.Options(files, true) }));
            return 0;
        }
        if (args.Length == 4 && args[0] == "--office-export")
        {
            try
            { OfficeBridge.Export(args[1], args[2], args[3]); return 0; }
            catch (Exception ex) { Console.Error.WriteLine(ex.Message); return 1; }
        }
        if (args.Length == 3 && args[0] == "--worker")
        {
            Backend.Run(["--job", args[1], args[2]]).GetAwaiter().GetResult();
            return 0;
        }
        if (args.Length >= 3 && args[0] == "--convert")
        {
            string folder = Path.Combine(Journal.DirectoryPath, "cli-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(folder);
            string request = Path.Combine(folder, "request.json"), response = WritableResultPath();
            File.WriteAllText(request, JsonSerializer.Serialize(new ConversionJob(args.Skip(2).ToArray(), "convert:" + args[1])));
            Backend.Run(["--job", request, response]).GetAwaiter().GetResult();
            var result = JsonSerializer.Deserialize<BatchResult>(File.ReadAllText(response))!;
            File.Delete(request);
            Directory.Delete(folder);
            return result.Files.All(f => f.Error == null) ? 0 : 1;
        }
        if (args.Length >= 3 && args[0] == "--debug-tool")
        {
            var testApp = new System.Windows.Application { ShutdownMode = ShutdownMode.OnMainWindowClose };
            var definition = Catalog.Definition(args[1], Catalog.Category(args[2]));
            testApp.Run(definition.Parts != null ? new ComboWindow(args.Skip(2).ToArray(), definition, Backend.Execute) : new ToolWindow(args.Skip(2).ToArray(), definition, Backend.Execute));
            return 0;
        }
        if (args.Length == 2 && args[0] == "--debug-window")
        {
            // Opens one of the small windows on its own, for checking its look (both languages and themes).
            var testApp = new System.Windows.Application { ShutdownMode = ShutdownMode.OnMainWindowClose };
            Window window = args[1] switch { "wheel-order" => new WheelOrderWindow(), "watch" => new WatchWindow(() => { }), "flows" => new FlowWindow(() => { }), _ => new WelcomeWindow() };
            testApp.Run(window);
            return 0;
        }
        if (args.Length == 5 && args[0] == "--debug-wheel-render")
        {
            // --debug-wheel-render <formats|tools> <file> <operation id to highlight> <out.png>
            var testApp = new System.Windows.Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
            testApp.Dispatcher.InvokeAsync(() =>
            {
                var wheel = new DropWheel((_, _) => { });
                wheel.Preview([args[2]], args[1] == "tools", args[3]);
                var root = (FrameworkElement)wheel.Content;
                double stage = wheel.StageSize;
                root.Measure(new Size(stage, stage));
                root.Arrange(new Rect(0, 0, stage, stage));
                root.UpdateLayout();
                var bitmap = new System.Windows.Media.Imaging.RenderTargetBitmap((int)(stage * 3), (int)(stage * 3), 288, 288, System.Windows.Media.PixelFormats.Pbgra32);
                bitmap.Render(root);
                SavePng(bitmap, args[4]);
                testApp.Shutdown();
            });
            testApp.Run();
            return 0;
        }
        if (args.Length == 2 && args[0] == "--debug-indicator")
        {
            // Renders the progress stack in several states to <prefix>-<state>.png for visual checks.
            var testApp = new System.Windows.Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
            var stack = new TaskIndicatorWindow(headless: true);
            void Render(string state)
            {
                var root = (FrameworkElement)stack.Content;
                root.Width = stack.Width;
                root.Measure(new Size(stack.Width, double.PositiveInfinity));
                root.Arrange(new Rect(root.DesiredSize));
                root.UpdateLayout();
                var bitmap = new System.Windows.Media.Imaging.RenderTargetBitmap((int)Math.Ceiling(root.ActualWidth * 2), (int)Math.Ceiling(root.ActualHeight * 2), 192, 192, System.Windows.Media.PixelFormats.Pbgra32);
                var backdrop = new System.Windows.Media.DrawingVisual();
                using (var dc = backdrop.RenderOpen())
                    dc.DrawRectangle(new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(214, 217, 221)), null, new Rect(0, 0, root.ActualWidth, root.ActualHeight));
                bitmap.Render(backdrop);
                bitmap.Render(root);
                SavePng(bitmap, $"{args[1]}-{state}.png");
            }
            testApp.Dispatcher.InvokeAsync(() =>
            {
                var first = stack.Add(new ConversionJob(["B&W"], "pack:zip"));
                first.Start().Report(new JobProgress("processing", 0, 1, "B&W"));
                Render("single");
                var second = stack.Add(new ConversionJob([L.T("holiday video.mp4")], "convert:webm"));
                second.Start().Report(new JobProgress("processing", 0, 1, L.T("holiday video.mp4")));
                second.SetPaused(true);
                var third = stack.Add(new ConversionJob([L.T("photo 1.heic"), L.T("photo 2.heic"), L.T("photo 3.heic")], "convert:jpg"));
                stack.Update();
                Render("expanded");
                stack.SetExpanded(false);
                Render("collapsed");
                stack.SetExpanded(true);
                stack.HideCard(first);
                Render("one-hidden");
                testApp.Shutdown();
            });
            testApp.Run();
            return 0;
        }
        bool startupLaunch = StartupManager.IsStartupLaunch(args);
        bool isLicenseCmd = args.Any(a => a is "--license" or "-license" or "--activate" or "-activate");
        using var mutex = new Mutex(true, @"Local\DropDial_20261003", out bool first);
        // Both copies create the same named event, so it works whichever starts first.
        using var showRequest = new EventWaitHandle(false, EventResetMode.AutoReset, @"Local\DropDial_20261003_Show");
        string[] opened = ExplorerIntegration.PathsIn(args);
        if (!first)
        {
            if (opened.Length > 0)
            { ExplorerIntegration.Send(opened); return 0; }
            if (isLicenseCmd)
            {
                Native.AllowSetForegroundWindow(-1);
                showRequest.Set();
                return 0;
            }
            if (startupLaunch) return 0;
            // Launching DropDial again (for example from the Start menu) wakes the running copy and shows its window.
            Native.AllowSetForegroundWindow(-1);
            showRequest.Set();
            return 0;
        }
        var app = new System.Windows.Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        using var resident = new Resident(app, showRequest, startupLaunch);
        if (isLicenseCmd)
            app.Dispatcher.InvokeAsync(LicenseWindow.ShowDialogOrActivate);
        if (opened.Length > 0)
            app.Dispatcher.InvokeAsync(() => resident.OpenFiles(opened));
        app.Run();
        return 0;
    }
}

internal static class Notices
{
    // Shipped beside the executable by build.ps1; lists every bundled component and its license.
    public static string Path => System.IO.Path.Combine(AppContext.BaseDirectory, "THIRD-PARTY-NOTICES.txt");
}

internal static class Journal
{
    // Keep logs and scratch folders in the user profile so a read-only install folder cannot break startup.
    public static readonly string DirectoryPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "DropDial", "logs");
    private const long MaxLogBytes = 4 * 1024 * 1024;
    private static readonly object Sync = new();
    public static void Write(string kind, object? data = null)
    {
        lock (Sync)
        {
            try
            {
                Directory.CreateDirectory(DirectoryPath);
                string log = Path.Combine(DirectoryPath, "events.jsonl");
                var info = new FileInfo(log);
                if (info.Exists && info.Length > MaxLogBytes)
                    File.Move(log, Path.Combine(DirectoryPath, "events.1.jsonl"), true);
                File.AppendAllText(log, JsonSerializer.Serialize(new { utc = DateTimeOffset.UtcNow, kind, data }) + Environment.NewLine);
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { }
        }
    }
    // Remove scratch folders left behind by crashes or forced exits.
    public static void Prune()
    {
        try
        {
            if (!Directory.Exists(DirectoryPath))
                return;
            var cutoff = DateTime.UtcNow.AddDays(-1);
            foreach (var folder in new DirectoryInfo(DirectoryPath).EnumerateDirectories())
            {
                if (folder.Name.Split('-')[0] is not ("job" or "preview" or "qa" or "cli" or "combo") || folder.LastWriteTimeUtc > cutoff)
                    continue;
                try
                { folder.Delete(true); }
                catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { }
            }
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { }
    }
}

internal sealed class Resident : IDisposable
{
    private readonly System.Windows.Application app;
    private readonly DropWheel wheel;
    private readonly TaskIndicatorWindow taskIndicator = new();
    private readonly DispatcherTimer timer;
    private readonly Forms.NotifyIcon tray;
    private readonly System.Drawing.Icon trayIcon;
    private readonly Channel<QueuedJob> queue = Channel.CreateBounded<QueuedJob>(new BoundedChannelOptions(16) { SingleReader = true, FullMode = BoundedChannelFullMode.Wait });
    private readonly CancellationTokenSource stopping = new();
    private readonly DragShortcutTracker dragShortcuts = new(Native.GetSystemMetrics(68), Native.GetSystemMetrics(69));
    private bool f8, f9, f10, escape, mouse, altSpacePressed, ctrlShiftLPressed, ctrlShiftSpacePressed, ctrlShiftPressed;
    private DateTime activated = DateTime.MinValue;
    private string? lastOutput;
    private bool disposed;
    // Up to this many jobs run at once; more wait their turn. A paused job gives its slot to the next one.
    private const int MaxParallelJobs = 2;
    private readonly SemaphoreSlim slots = new(MaxParallelJobs);
    private readonly List<RunningJob> jobs = [];
    private sealed class RunningJob(QueuedJob queued, CancellationTokenSource cancellation)
    {
        public readonly QueuedJob Queued = queued;
        public readonly CancellationTokenSource Cancellation = cancellation;
        public readonly string Token = Guid.NewGuid().ToString("N")[..12];
        public JobCard? Card;
        public Process? Worker;
        public TempSweep? Sweep;
        public ProcessTreePause? Pause;
        public bool HoldsSlot, Ended;
    }
    private sealed record QueuedJob(ConversionJob Job, TaskCompletionSource<BatchResult>? Completion = null, CancellationToken Cancellation = default, IProgress<JobProgress>? Progress = null) { public volatile bool Started; }

    private WelcomeWindow? welcome;
    private readonly List<string> recent = [];
    private WatchFolders? watch;
    private WatchWindow? watchWindow;
    private FlowWindow? flowWindow;
    private WheelOrderWindow? orderWindow;
    private readonly EventWaitHandle openRequest = new(false, EventResetMode.AutoReset, ExplorerIntegration.EventName);

    private Forms.ToolStripMenuItem? startupMenu;
    private HwndSource? hotkeySource;
    private const int HOTKEY_ID_F8 = 9001;
    private const int HOTKEY_ID_F9 = 9002;
    private const int HOTKEY_ID_F10 = 9003;
    private const int HOTKEY_ID_ALTSPACE = 9004;
    private const int HOTKEY_ID_WINSHIFTL = 9005;
    private const int HOTKEY_ID_CTRLSHIFTL = 9006;
    private const int HOTKEY_ID_CTRLSHIFTSPACE = 9007;

    internal static Resident? Instance { get; private set; }

    public Resident(System.Windows.Application app, EventWaitHandle showRequest, bool startupLaunch = false)
    {
        Instance = this;
        this.app = app;
        StartupManager.RefreshPortablePath();
        Journal.Prune();
        wheel = new DropWheel(BeginOperation);
        FloatShelfWindow.Instance.OnExecuteOperation = (files, op) => BeginOperation(files, op);
        SetupGlobalHotKeys();
        trayIcon = AppIcon.CreateTrayIcon();
        tray = new Forms.NotifyIcon { Icon = trayIcon, Visible = true };
        BuildTrayMenu();
        StartupManager.Changed += RefreshStartupMenu;
        // The tray menu, tooltip and progress stack switch language immediately; open tool windows keep theirs.
        L.Changed += () =>
        {
            BuildTrayMenu();
            taskIndicator.Relabel();
            Notify("DropDial", L.T("Switched to English"));
        };
        taskIndicator.PauseRequested += card => { if (jobs.FirstOrDefault(j => j.Card == card) is { } job) PauseJob(job); };
        taskIndicator.ResumeRequested += card => { if (jobs.FirstOrDefault(j => j.Card == card) is { } job) ResumeJob(job); };
        taskIndicator.CancelRequested += card => { if (jobs.FirstOrDefault(j => j.Card == card) is { } job) CancelJob(job); };
        tray.DoubleClick += (_, _) => ToggleWheel();
        tray.MouseClick += (_, e) =>
        {
            if (e.Button == Forms.MouseButtons.Left)
            {
                ToggleWheel();
            }
        };
        UpdateManager.UpdateStatusChanged += () => app.Dispatcher.InvokeAsync(BuildTrayMenu);
        _ = Task.Run(async () =>
        {
            await Task.Delay(3000);
            await UpdateManager.CheckForUpdatesAsync(isUserInitiated: false);
        });
        timer = new DispatcherTimer(DispatcherPriority.Input) { Interval = TimeSpan.FromMilliseconds(25) };
        timer.Tick += Poll;
        timer.Start();
        _ = WorkQueue();
        watch = new WatchFolders(Enqueue);
        watch.Reload();
        Journal.Write("Started", new { noMainWindow = true, modifierShortcuts = true, dragFunctionKeys = true });
        // DropDial only starts when someone launches it, so show how to use it. People who prefer the quiet start
        // can switch the window off; they still get the tray notification.
        if (startupLaunch) { /* Sign-in launches stay quiet. */ }
        else if (Settings.GetBool(WelcomeWindow.HideAtStartKey, false))
            Notify(L.T("DropDial is running"), L.T("Drag a file + Shift: convert. Ctrl+Shift: tools. F8/F9 also work while dragging."));
        else
            ShowWelcome();
        WatchForSecondLaunch(showRequest);
    }

    private void SetupGlobalHotKeys()
    {
        try
        {
            var parameters = new HwndSourceParameters("DropDialHotkeySink") { WindowStyle = 0 };
            hotkeySource = new HwndSource(parameters);
            hotkeySource.AddHook(HwndHook);
            IntPtr handle = hotkeySource.Handle;

            Native.RegisterHotKey(handle, HOTKEY_ID_F8, Native.MOD_NOREPEAT, 0x77);
            Native.RegisterHotKey(handle, HOTKEY_ID_F9, Native.MOD_NOREPEAT, 0x78);
            Native.RegisterHotKey(handle, HOTKEY_ID_F10, Native.MOD_NOREPEAT, 0x79);
            Native.RegisterHotKey(handle, HOTKEY_ID_ALTSPACE, Native.MOD_ALT | Native.MOD_NOREPEAT, 0x20);
            Native.RegisterHotKey(handle, HOTKEY_ID_WINSHIFTL, Native.MOD_WIN | Native.MOD_SHIFT | Native.MOD_NOREPEAT, 0x4C);
            Native.RegisterHotKey(handle, HOTKEY_ID_CTRLSHIFTL, Native.MOD_CONTROL | Native.MOD_SHIFT | Native.MOD_NOREPEAT, 0x4C);
            Native.RegisterHotKey(handle, HOTKEY_ID_CTRLSHIFTSPACE, Native.MOD_CONTROL | Native.MOD_SHIFT | Native.MOD_NOREPEAT, 0x20);
        }
        catch { }
    }

    private IntPtr HwndHook(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == Native.WM_HOTKEY)
        {
            int id = wParam.ToInt32();
            switch (id)
            {
                case HOTKEY_ID_F8:
                    app.Dispatcher.InvokeAsync(() => ToggleWheel(WheelMode.Convert));
                    handled = true;
                    break;
                case HOTKEY_ID_F9:
                    app.Dispatcher.InvokeAsync(() => ToggleWheel(WheelMode.Tools));
                    handled = true;
                    break;
                case HOTKEY_ID_F10:
                    app.Dispatcher.InvokeAsync(() => ToggleWheel(WheelMode.Actions));
                    handled = true;
                    break;
                case HOTKEY_ID_ALTSPACE:
                case HOTKEY_ID_WINSHIFTL:
                case HOTKEY_ID_CTRLSHIFTL:
                    app.Dispatcher.InvokeAsync(() => ToggleWheel());
                    handled = true;
                    break;
                case HOTKEY_ID_CTRLSHIFTSPACE:
                    app.Dispatcher.InvokeAsync(() => ToggleWheel(WheelMode.Tools));
                    handled = true;
                    break;
            }
        }
        return IntPtr.Zero;
    }

    internal void ToggleWheel(WheelMode? targetMode = null)
    {
        if ((DateTime.UtcNow - activated).TotalMilliseconds < 250)
            return;
        activated = DateTime.UtcNow;
        if (wheel.IsVisible)
        {
            if (targetMode.HasValue && wheel.CurrentMode != targetMode.Value)
            {
                wheel.ChangeMode(targetMode.Value);
            }
            else
            {
                wheel.Dismiss("HotkeyToggle");
            }
        }
        else
        {
            Activate(targetMode ?? WheelMode.Convert, "Hotkey");
        }
    }

    // Shows the welcome window, or brings it to the front if it is already open.
    private void ShowWelcome()
    {
        if (disposed)
            return;
        if (welcome == null)
        {
            welcome = new WelcomeWindow();
            welcome.Closed += (_, _) => welcome = null;
            welcome.Show();
        }
        if (welcome.WindowState == WindowState.Minimized)
            welcome.WindowState = WindowState.Normal;
        // Toggling Topmost reliably raises the window above whatever was in front, without keeping it there.
        welcome.Topmost = true;
        welcome.Activate();
        welcome.Topmost = false;
    }

    private void WatchForSecondLaunch(EventWaitHandle showRequest)
    {
        var watcher = new Thread(() =>
        {
            var handles = new WaitHandle[] { showRequest, stopping.Token.WaitHandle, openRequest };
            for (int signalled; (signalled = WaitHandle.WaitAny(handles)) != 1;)
                if (signalled == 0)
                    app.Dispatcher.InvokeAsync(ShowWelcome);
                else
                    app.Dispatcher.InvokeAsync(HandleOpenRequests);
        })
        { IsBackground = true, Name = "DropDial second-launch watcher" };
        watcher.Start();
    }

    // Several files chosen in Explorer can arrive as separate launches; wait a moment and treat them as one selection.
    private async void HandleOpenRequests()
    {
        await Task.Delay(500);
        if (disposed)
            return;
        var paths = ExplorerIntegration.Receive().SelectMany(batch => batch).Distinct(StringComparer.OrdinalIgnoreCase).Where(p => File.Exists(p) || Directory.Exists(p)).ToArray();
        if (paths.Length > 0)
            OpenFiles(paths);
    }

    public void OpenFiles(string[] paths)
    {
        if (!disposed)
            OpenMenu.Show(paths, BeginOperation);
    }

    private void OpenFromClipboard()
    {
        string[] paths = [];
        try
        {
            if (System.Windows.Clipboard.ContainsFileDropList())
                paths = System.Windows.Clipboard.GetFileDropList().Cast<string>().Where(p => File.Exists(p) || Directory.Exists(p)).ToArray();
            else if (System.Windows.Clipboard.ContainsImage() && System.Windows.Clipboard.GetImage() is { } image)
            {
                // Kept where the user can find the results: the chosen output folder, or a DropDial folder in Pictures.
                string folder = OutputFolder.Current ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyPictures), "DropDial");
                Directory.CreateDirectory(folder);
                string file = Path.Combine(folder, "clipboard-" + DateTime.Now.ToString("yyyyMMdd-HHmmss") + ".png");
                Program.SavePng(image, file);
                paths = [file];
            }
        }
        catch (Exception ex) when (ex is System.Runtime.InteropServices.ExternalException or IOException or UnauthorizedAccessException) { Notify(L.T("Cannot read the clipboard"), ex.Message); return; }
        if (paths.Length == 0)
        { Notify(L.T("No picture or files on the clipboard"), L.T("Copy a picture first, or copy files in Explorer.")); return; }
        OpenFiles(paths);
    }

    private void ChooseOutputFolder()
    {
        using var dialog = new Forms.FolderBrowserDialog { Description = L.T("Choose the folder for the results"), SelectedPath = OutputFolder.Current ?? "" };
        if (dialog.ShowDialog() == Forms.DialogResult.OK)
            OutputFolder.Choose(dialog.SelectedPath);
    }

    private void ShowWatchWindow()
    {
        if (watchWindow == null)
        {
            watchWindow = new WatchWindow(() => watch?.Reload());
            watchWindow.Closed += (_, _) => watchWindow = null;
            watchWindow.Show();
        }
        watchWindow.Activate();
    }

    private void OpenNotices()
    {
        if (File.Exists(Notices.Path))
            Process.Start(new ProcessStartInfo(Notices.Path) { UseShellExecute = true });
    }

    internal void PromptSelectFiles()
    {
        using var dialog = new Forms.OpenFileDialog
        {
            Multiselect = true,
            Title = L.T("Select files to process")
        };
        if (dialog.ShowDialog() == Forms.DialogResult.OK && dialog.FileNames.Length > 0)
        {
            Native.GetCursorPos(out var pt);
            wheel.OpenAt(pt, WheelMode.Convert);
            wheel.LoadFiles(dialog.FileNames, WheelMode.Convert);
        }
    }

    private void BuildTrayMenu()
    {
        tray.Text = L.T("DropDial · Drag + Shift to convert / Ctrl+Shift tools / Alt actions");
        var old = tray.ContextMenuStrip;
        var items = new Forms.ContextMenuStrip();
        items.Items.Add(L.T("Toggle Wheel") + "\tAlt+Space", null, (_, _) => ToggleWheel());
        items.Items.Add(L.T("Formats Wheel") + "\tF8", null, (_, _) => Activate(WheelMode.Convert, "TrayMenu"));
        items.Items.Add(L.T("Tools Wheel") + "\tF9", null, (_, _) => Activate(WheelMode.Tools, "TrayMenu"));
        items.Items.Add(L.T("Actions Wheel") + "\tF10", null, (_, _) => Activate(WheelMode.Actions, "TrayMenu"));
        items.Items.Add(L.T("Floating Shelf"), null, (_, _) => FloatShelfWindow.Instance.ShowWindow());
        items.Items.Add(new Forms.ToolStripSeparator());
        items.Items.Add(L.T("Choose Files…") + "\tCtrl+O", null, (_, _) => PromptSelectFiles());
        items.Items.Add(new Forms.ToolStripSeparator());
        items.Items.Add(L.T("How to Use DropDial"), null, (_, _) => ShowWelcome());
        items.Items.Add(new Forms.ToolStripSeparator());
        var showProgress = items.Items.Add(L.T("Show progress"), null, (_, _) => taskIndicator.ShowAll());
        var pauseAll = items.Items.Add(L.T("Pause all jobs"), null, (_, _) =>
        {
            bool resume = !jobs.Any(CanPause) && jobs.Any(j => j.Pause != null);
            foreach (var job in jobs.ToList())
                if (resume) ResumeJob(job); else PauseJob(job);
        });
        var cancelAll = items.Items.Add(L.T("Cancel all jobs"), null, (_, _) => { foreach (var job in jobs.ToList()) CancelJob(job); });
        items.Items.Add(L.T("Open latest output folder"), null, (_, _) => { if (lastOutput != null) ExplorerIntegration.Reveal(lastOutput); });
        items.Items.Add(new Forms.ToolStripSeparator());
        items.Items.Add(L.T("Process a picture or files from the clipboard…"), null, (_, _) => OpenFromClipboard());
        var recentMenu = new Forms.ToolStripMenuItem(L.T("Recent results"));
        items.Items.Add(recentMenu);
        var locationMenu = new Forms.ToolStripMenuItem(L.T("Save location"));
        var sameFolder = new Forms.ToolStripMenuItem(L.T("Same folder as the original"), null, (_, _) => OutputFolder.Choose(null));
        var otherFolder = new Forms.ToolStripMenuItem(L.T("Choose a folder…"), null, (_, _) => ChooseOutputFolder());
        locationMenu.DropDownItems.AddRange([sameFolder, otherFolder]);
        items.Items.Add(locationMenu);
        items.Items.Add(L.T("Watched folders…"), null, (_, _) => ShowWatchWindow());
        var layoutMenu = new Forms.ToolStripMenuItem(L.T("Wheel with many tools"));
        var mergedLayout = new Forms.ToolStripMenuItem(L.T("Combine related tools"), null, (_, _) => Settings.Set(Catalog.LayoutKey, "merged")) { Checked = !Catalog.TwoWheels };
        var twoWheelLayout = new Forms.ToolStripMenuItem(L.T("Two wheels (categories)"), null, (_, _) => Settings.Set(Catalog.LayoutKey, "twoWheels")) { Checked = Catalog.TwoWheels };
        layoutMenu.DropDownItems.AddRange([mergedLayout, twoWheelLayout]);
        layoutMenu.DropDownOpening += (_, _) => { mergedLayout.Checked = !Catalog.TwoWheels; twoWheelLayout.Checked = Catalog.TwoWheels; };
        items.Items.Add(layoutMenu);
        var themeMenu = new Forms.ToolStripMenuItem(L.T("Appearance"));
        foreach (var (choice, label) in new[] { ("system", L.T("Match Windows")), ("light", L.T("Light")), ("dark", L.T("Dark")) })
            themeMenu.DropDownItems.Add(new Forms.ToolStripMenuItem(label, null, (_, _) => { UiTheme.Choose(choice); taskIndicator.ApplyTheme(); }) { Tag = choice });
        themeMenu.DropDownOpening += (_, _) => { foreach (Forms.ToolStripMenuItem item in themeMenu.DropDownItems) item.Checked = (string)item.Tag! == UiTheme.Choice; };
        items.Items.Add(themeMenu);
        items.Items.Add(L.T("Customize wheel…"), null, (_, _) => { if (orderWindow == null) { orderWindow = new WheelOrderWindow(); orderWindow.Closed += (_, _) => orderWindow = null; orderWindow.Show(); } orderWindow.Activate(); });
        items.Items.Add(L.T("Flows…"), null, (_, _) => { if (flowWindow == null) { flowWindow = new FlowWindow(() => { }); flowWindow.Closed += (_, _) => flowWindow = null; flowWindow.Show(); } flowWindow.Activate(); });
        Forms.ToolStripMenuItem? explorerItem = null;
        if (ExplorerIntegration.Available)
        {
            explorerItem = new Forms.ToolStripMenuItem(L.T("Explorer right-click menu"));
            explorerItem.Click += (_, _) =>
            {
                try
                { ExplorerIntegration.Set(!ExplorerIntegration.Enabled); }
                catch (Exception ex) when (ex is UnauthorizedAccessException or System.Security.SecurityException or IOException) { Notify(L.T("Explorer right-click menu"), ex.Message); }
            };
            items.Items.Add(explorerItem);
        }
        items.Items.Add(new Forms.ToolStripSeparator());
        // Language names are shown in their own language so either can be found whatever is active.
        var language = new Forms.ToolStripMenuItem(L.T("Language") + " / Language");
        foreach (var (code, name) in new[] { ("zh", "English"), ("en", "English") })
            language.DropDownItems.Add(new Forms.ToolStripMenuItem(name, null, (_, _) => L.Language = code) { Checked = L.Language == code });
        items.Items.Add(language);
        startupMenu = new Forms.ToolStripMenuItem(L.T("Start with Windows"));
        var startupItem = startupMenu;
        startupItem.Click += async (_, _) =>
        {
            startupItem.Enabled = false;
            var result = await StartupManager.SetAsync(!startupItem.Checked);
            if (disposed) return;
            startupItem.Checked = result.Enabled; startupItem.Enabled = result.CanChange;
            if (result.Message != null) Notify(L.T("Start with Windows"), result.Message);
        };
        items.Items.Add(startupItem);
        if (UpdateManager.AvailableUpdate is { } update)
        {
            items.Items.Add($"✨ Update to {update.TagName} Available...", null, (_, _) => _ = UpdateManager.CheckForUpdatesAsync(isUserInitiated: true));
        }
        else
        {
            items.Items.Add(L.T("Check for Updates..."), null, (_, _) => _ = UpdateManager.CheckForUpdatesAsync(isUserInitiated: true));
        }
        var licenseMenuItem = items.Items.Add(LicenseManager.CurrentStatus.DisplayText, null, (_, _) => LicenseWindow.ShowDialogOrActivate());
        items.Items.Add(L.T("Quit DropDial"), null, (_, _) => app.Shutdown());
        items.Opening += (_, _) =>
        {
            licenseMenuItem.Text = LicenseManager.CurrentStatus.DisplayText;
            RefreshStartupMenu();
            recentMenu.DropDownItems.Clear();
            foreach (string output in recent.Take(10))
                recentMenu.DropDownItems.Add(Path.GetFileName(output) is { Length: > 0 } leaf ? leaf : output, null, (_, _) => { if (File.Exists(output) || Directory.Exists(output)) ExplorerIntegration.Reveal(output); });
            recentMenu.Enabled = recent.Count > 0;
            sameFolder.Checked = OutputFolder.Current == null;
            otherFolder.Text = OutputFolder.Current is { } chosen ? L.T("Choose a folder…") + "  (" + chosen + ")" : L.T("Choose a folder…");
            if (explorerItem != null)
                explorerItem.Checked = ExplorerIntegration.Enabled;
            bool canPause = jobs.Any(CanPause), canResume = jobs.Any(j => j.Pause != null);
            showProgress.Enabled = cancelAll.Enabled = jobs.Count > 0;
            pauseAll.Enabled = canPause || canResume;
            pauseAll.Text = !canPause && canResume ? L.T("Resume all jobs") : L.T("Pause all jobs");
        };
        tray.ContextMenuStrip = items;
        old?.Dispose();
        RefreshStartupMenu();
    }
    private async void RefreshStartupMenu()
    {
        var item = startupMenu;
        var status = await StartupManager.GetAsync();
        if (disposed || item == null || item.IsDisposed || item != startupMenu) return;
        item.Checked = status.Enabled; item.Enabled = status.CanChange;
        item.ToolTipText = status.Message ?? L.T("Run quietly in the background after signing in to Windows.");
    }

    private void Activate(WheelMode mode, string reason, bool modifier = false)
    {
        if (wheel.IsVisible)
        {
            if (wheel.CurrentMode == mode)
                return;
            activated = DateTime.UtcNow;
            wheel.ChangeMode(mode);
            Journal.Write("WheelModeChanged", new { reason, mode });
            return;
        }
        if (!modifier && (DateTime.UtcNow - activated).TotalMilliseconds < 200)
            return;
        activated = DateTime.UtcNow;
        Native.GetCursorPos(out var point);
        wheel.OpenAt(point, mode);
        Journal.Write("WheelOpened", new { reason, mode, mouseDown = Native.Down(1), point.X, point.Y });
    }

    private void Poll(object? sender, EventArgs e)
    {
        bool nextF8 = Native.Down(0x77), nextF9 = Native.Down(0x78), nextF10 = Native.Down(0x79), nextEscape = Native.Down(0x1B), nextMouse = Native.Down(1);
        bool nextAlt = Native.Down(0x12), nextSpace = Native.Down(0x20);
        bool nextCtrl = Native.Down(0x11), nextShift = Native.Down(0x10), nextL = Native.Down(0x4C);

        bool nextAltSpace = nextAlt && nextSpace;
        bool nextCtrlShift = nextCtrl && nextShift && !nextAlt;
        bool nextCtrlShiftSpace = nextCtrlShift && nextSpace;
        bool nextCtrlShiftL = nextCtrlShift && nextL;

        Native.GetCursorPos(out var cursor);
        var request = dragShortcuts.Update(nextMouse, nextShift, nextCtrl, nextAlt, cursor.X, cursor.Y, nextMouse && !mouse && Native.ShellFileWindow());
        if (nextEscape && !escape)
            dragShortcuts.Cancel();
        else if (request != DragMenuRequest.None)
        {
            WheelMode m = request switch
            {
                DragMenuRequest.Actions => WheelMode.Actions,
                DragMenuRequest.Tools => WheelMode.Tools,
                _ => WheelMode.Convert
            };
            Activate(m, "DragModifier", true);
        }

        // F8 / F9 / F10 shortcut triggers:
        // When mouse is held (dragging), they switch the drag wheel mode.
        // When mouse is NOT held, they toggle the corresponding wheel at the cursor position.
        if (nextF8 && !f8)
        {
            if (nextMouse)
                Activate(WheelMode.Convert, "DragFunctionKey", true);
            else
                ToggleWheel(WheelMode.Convert);
        }
        if (nextF9 && !f9)
        {
            if (nextMouse)
                Activate(WheelMode.Tools, "DragFunctionKey", true);
            else
                ToggleWheel(WheelMode.Tools);
        }
        if (nextF10 && !f10)
        {
            if (nextMouse)
                Activate(WheelMode.Actions, "DragFunctionKey", true);
            else
                ToggleWheel(WheelMode.Actions);
        }

        // Keyboard hotkeys when not mouse dragging:
        if (!nextMouse)
        {
            if (nextAltSpace && !altSpacePressed)
                ToggleWheel();
            if (nextCtrlShiftSpace && !ctrlShiftSpacePressed)
                ToggleWheel(WheelMode.Tools);
            if (nextCtrlShiftL && !ctrlShiftLPressed)
                ToggleWheel(WheelMode.Tools);
            if (ctrlShiftPressed && !nextCtrlShift && !nextAlt && !nextL && !nextSpace)
                ToggleWheel(WheelMode.Tools);
        }

        altSpacePressed = nextAltSpace;
        ctrlShiftSpacePressed = nextCtrlShiftSpace;
        ctrlShiftLPressed = nextCtrlShiftL;
        ctrlShiftPressed = nextCtrlShift && !nextMouse;

        if (nextEscape && !escape && wheel.IsVisible)
            wheel.Dismiss("Escape");

        // When mouse button is clicked, dismiss wheel if click happened outside the wheel window bounds
        if (wheel.IsVisible && nextMouse && !mouse)
        {
            var hwnd = new System.Windows.Interop.WindowInteropHelper(wheel).Handle;
            if (hwnd != IntPtr.Zero && Native.GetWindowRect(hwnd, out var rect))
            {
                if (cursor.X < rect.Left || cursor.X > rect.Right || cursor.Y < rect.Top || cursor.Y > rect.Bottom)
                {
                    if ((DateTime.UtcNow - activated).TotalMilliseconds > 400)
                    {
                        wheel.Dismiss("OutsideClick");
                    }
                }
            }
        }

        // If a file drag was underway and mouse was released outside the wheel:
        if (wheel.IsVisible && wheel.HasFileDrag && mouse && !nextMouse)
        {
            var hwnd = new System.Windows.Interop.WindowInteropHelper(wheel).Handle;
            if (hwnd != IntPtr.Zero && Native.GetWindowRect(hwnd, out var rect))
            {
                if (cursor.X < rect.Left || cursor.X > rect.Right || cursor.Y < rect.Top || cursor.Y > rect.Bottom)
                {
                    wheel.Dismiss("DragReleasedOutside");
                }
            }
        }
        f8 = nextF8;
        f9 = nextF9;
        f10 = nextF10;
        escape = nextEscape;
        mouse = nextMouse;
    }

    private void Enqueue(ConversionJob job)
    {
        if (!LicenseManager.CanUseApp())
        {
            LicenseWindow.ShowDialogOrActivate();
            return;
        }

        if (!queue.Writer.TryWrite(new QueuedJob(job)))
        { Notify(L.T("The job queue is full"), L.T("Please try again when the current files have finished.")); return; }
        Journal.Write("Queued", new { count = job.Paths.Length, job.Action });
    }

    private async Task<BatchResult> EnqueueTool(ConversionJob job, CancellationToken token, IProgress<JobProgress>? progress)
    {
        var completion = new TaskCompletionSource<BatchResult>(TaskCreationOptions.RunContinuationsAsynchronously);
        var queued = new QueuedJob(job, completion, token, progress);
        progress?.Report(new JobProgress("queued", 0, job.Paths.Length, Path.GetFileName(job.Paths[0])));
        using var registration = token.Register(() => { if (!queued.Started) completion.TrySetCanceled(token); });
        await queue.Writer.WriteAsync(queued, token);
        return await completion.Task;
    }

    private void BeginOperation(string[] paths, Operation operation)
    {
        if (!LicenseManager.CanUseApp())
        {
            LicenseWindow.ShowDialogOrActivate();
            return;
        }

        Catalog.RememberLast(paths, operation);
        if (operation.Id.StartsWith("action:"))
        {
            ExecuteFileAction(operation.Id, paths);
            return;
        }
        if (operation.Parts != null)
        {
            var combined = new ComboWindow(paths, operation, EnqueueTool);
            combined.Show();
            combined.Activate();
            return;
        }
        if (operation.Id == Flows.MenuId)
        {
            OpenMenu.ShowList(paths, Flows.For(paths), BeginOperation);
            return;
        }
        if (operation.Id.StartsWith(Flows.Prefix))
        {
            try
            { Enqueue(Flows.Job(paths, operation.Id)); }
            catch (ArgumentException ex) { Notify(L.T("Flows"), ex.Message); }
            return;
        }
        // Tools with settings, an order to choose, or a player open a window.
        if (operation.Tool)
        {
            try
            {
                var def = Catalog.Definition(operation.Id, Catalog.Category(paths[0]));
                if (operation.Fields == null || operation.Fields.Length == 0)
                    operation = def;
            }
            catch { }

            string[] zeroParamTools = ["removeMetadata", "muteVideo", "joinVideos", "joinAudio", "createPDF"];
            if (zeroParamTools.Contains(operation.Id) && (operation.Fields == null || operation.Fields.Length == 0 || operation.Id == "removeMetadata"))
            {
                Enqueue(new ConversionJob(paths, operation.Id));
            }
            else
            {
                var tool = new ToolWindow(paths, operation, EnqueueTool);
                tool.ReplaceInDropDial = newPaths =>
                {
                    wheel.LoadFiles(newPaths, WheelMode.Tools);
                    wheel.Show();
                    wheel.Activate();
                };
                tool.Show();
                tool.Activate();
            }
        }
        else
            Enqueue(new ConversionJob(paths, operation.Id));
    }

    private void ExecuteFileAction(string actionId, string[] paths)
    {
        if (paths.Length == 0) return;
        switch (actionId)
        {
            case "action:float":
                FloatShelfWindow.Instance.AddFiles(paths);
                FloatShelfWindow.Instance.ShowWindow();
                SoundManager.PlayPop();
                break;

            case "action:copy":
                try
                {
                    var list = new System.Collections.Specialized.StringCollection();
                    list.AddRange(paths);
                    System.Windows.Clipboard.SetFileDropList(list);
                    Notify("DropDial", paths.Length == 1 ? L.T("1 file copied to clipboard") : L.F("{0} files copied to clipboard", paths.Length));
                }
                catch (Exception ex) { Notify(L.T("Copy"), ex.Message); }
                break;

            case "action:move":
                try
                {
                    using var dialog = new Forms.FolderBrowserDialog { Description = L.T("Choose Destination Folder") };
                    if (dialog.ShowDialog() == Forms.DialogResult.OK && Directory.Exists(dialog.SelectedPath))
                    {
                        int moved = 0;
                        foreach (var p in paths)
                        {
                            if (File.Exists(p))
                            {
                                string dest = Path.Combine(dialog.SelectedPath, Path.GetFileName(p));
                                if (File.Exists(dest))
                                    dest = Path.Combine(dialog.SelectedPath, Path.GetFileNameWithoutExtension(p) + "_" + Guid.NewGuid().ToString("N")[..4] + Path.GetExtension(p));
                                File.Move(p, dest);
                                moved++;
                            }
                        }
                        Notify("DropDial", L.F("Moved {0} files to {1}", moved, Path.GetFileName(dialog.SelectedPath)));
                    }
                }
                catch (Exception ex) { Notify(L.T("Move"), ex.Message); }
                break;

            case "action:copyPath":
                try
                {
                    System.Windows.Clipboard.SetText(string.Join(Environment.NewLine, paths));
                    Notify("DropDial", L.T("File paths copied to clipboard"));
                }
                catch (Exception ex) { Notify(L.T("Copy Path"), ex.Message); }
                break;

            case "action:terminal":
            case "action:openTerminal":
                try
                {
                    string folder = Directory.Exists(paths[0]) ? paths[0] : (Path.GetDirectoryName(paths[0]) ?? Environment.GetFolderPath(Environment.SpecialFolder.UserProfile));
                    bool launched = false;
                    try
                    {
                        Process.Start(new ProcessStartInfo("wt.exe", $"-d \"{folder}\"") { UseShellExecute = true });
                        launched = true;
                    }
                    catch { }
                    if (!launched)
                    {
                        try
                        {
                            Process.Start(new ProcessStartInfo("powershell.exe") { WorkingDirectory = folder, UseShellExecute = true });
                            launched = true;
                        }
                        catch { }
                    }
                    if (!launched)
                    {
                        Process.Start(new ProcessStartInfo("cmd.exe") { WorkingDirectory = folder, UseShellExecute = true });
                    }
                }
                catch (Exception ex) { Notify(L.T("Terminal"), ex.Message); }
                break;

            case "action:share":
            case "action:airDrop":
                try
                {
                    var list = new System.Collections.Specialized.StringCollection();
                    list.AddRange(paths);
                    System.Windows.Clipboard.SetFileDropList(list);
                    ExplorerIntegration.Reveal(paths[0]);
                    Notify("DropDial", paths.Length == 1 ? L.T("Ready to share (copied to clipboard & revealed)") : L.F("{0} files ready to share", paths.Length));
                }
                catch
                {
                    try { ExplorerIntegration.Reveal(paths[0]); } catch { }
                }
                break;

            case "action:metadata":
                Enqueue(new ConversionJob(paths, "removeMetadata"));
                break;
        }
    }

    private async Task WorkQueue()
    {
        try
        {
            // Every job gets a card straight away (waiting, if all slots are busy) and then runs on its own.
            await foreach (var queued in queue.Reader.ReadAllAsync(stopping.Token))
            {
                var job = new RunningJob(queued, CancellationTokenSource.CreateLinkedTokenSource(stopping.Token, queued.Cancellation));
                if (queued.Progress == null)
                    job.Card = taskIndicator.Add(queued.Job);
                jobs.Add(job);
                _ = RunJob(job);
            }
        }
        catch (OperationCanceledException) { }
    }

    private async Task RunJob(RunningJob job)
    {
        var queued = job.Queued;
        string session = "", request = "", response = "";
        try
        {
            await slots.WaitAsync(job.Cancellation.Token);
            job.HoldsSlot = true;
            queued.Started = true;
            var progress = queued.Progress ?? job.Card!.Start();
            taskIndicator.Update();
            session = Path.Combine(Journal.DirectoryPath, "job-" + job.Token);
            Directory.CreateDirectory(session);
            request = Path.Combine(session, "request.json");
            response = Path.Combine(session, "result.json");
            File.WriteAllText(request, JsonSerializer.Serialize(queued.Job));
            job.Sweep = new TempSweep(queued.Job.Paths, job.Token, OutputFolder.For(queued.Job));
            // No fixed time limit: long video encodes are legitimate, and every job can be cancelled.
            await Backend.Run(["--job", request, response], job.Cancellation.Token, process => job.Worker = process, progress, job.Token);
            if (!File.Exists(response))
                throw new IOException(L.T("The processing engine did not finish normally"));
            var result = JsonSerializer.Deserialize<BatchResult>(File.ReadAllText(response))!;
            queued.Completion?.TrySetResult(result);
            var success = result.Files.Where(x => x.Output != null).ToArray();
            if (success.Length > 0)
            {
                lastOutput = success[^1].Output;
                foreach (var file in success.Reverse())
                { recent.Remove(file.Output!); recent.Insert(0, file.Output!); }
                if (recent.Count > 20)
                    recent.RemoveRange(20, recent.Count - 20);
            }
            int failures = result.Files.Length - success.Length;
            Journal.Write("Completed", new { queued.Job.Action, count = result.Files.Length, success = success.Length, failures, errors = result.Files.Where(x => x.Error != null).Select(x => x.Error) });
            string? folder = OutputFolder.For(queued.Job);
            string? lastSuccessOutput = success.Length > 0 ? success[^1].Output : null;
            string detail = failures > 0 && success.Length == 0
                ? CleanErrorMessage(result.Files.FirstOrDefault(x => x.Error != null)?.Error ?? L.T("The conversion failed."))
                : folder == null
                    ? L.T("New files were saved next to the originals.")
                    : L.F("New files were saved to {0}.", Path.GetFileName(folder.TrimEnd('\\')));
            string output = success.Length > 1
                ? L.F("{0} files created · {1}", success.Length, Path.GetFileName(lastSuccessOutput ?? ""))
                : (success.Length > 0 ? (Path.GetFileName(lastSuccessOutput) ?? L.T("New file saved")) : L.T("New file saved"));
            string title = failures == 0
                ? L.T("Done")
                : success.Length == 0
                    ? L.T("Failed")
                    : L.F("{0} succeeded · {1} failed", success.Length, failures);
            string cardDetail = failures == 0 ? output : (success.Length == 0 ? detail : output + " · " + detail);
            bool cardShown = job.Card == null || taskIndicator.Finish(job.Card, title, cardDetail, lastSuccessOutput);
            if (queued.Progress != null || failures > 0 || !cardShown)
                Notify(L.F("{0} done", success.Length) + (failures == 0 ? "" : L.F(" · {0} failed", failures)), failures == 0 && !cardShown ? output : detail);
        }
        catch (OperationCanceledException)
        {
            if (job.Sweep != null)
                await job.Sweep.Run();
            queued.Completion?.TrySetCanceled();
            bool cardShown = job.Card == null || taskIndicator.Finish(job.Card, L.T("Stopped"), L.T("This job was cancelled."));
            if (!stopping.IsCancellationRequested && (job.Worker != null || !cardShown))
                Notify(L.T("Stopped"), job.Worker != null ? L.T("This job was cancelled and its unfinished files were removed.") : L.T("This job was cancelled."));
        }
        catch (Exception ex)
        {
            if (job.Sweep != null)
                await job.Sweep.Run();
            queued.Completion?.TrySetException(ex);
            if (job.Card != null)
                taskIndicator.Finish(job.Card, L.T("Not completed"), ex.Message);
            Journal.Write("JobFailed", new { ex.Message });
            Notify(L.T("Conversion not completed"), ex.Message);
        }
        finally
        {
            job.Ended = true;
            job.Pause?.Dispose();
            job.Pause = null;
            if (job.HoldsSlot)
                slots.Release();
            job.HoldsSlot = false;
            jobs.Remove(job);
            job.Cancellation.Dispose();
            // Only remove files created for this specific worker request.
            foreach (var file in new[] { request, response, response + ".progress", response + ".progress.tmp" })
                if (Path.IsPathRooted(file) && File.Exists(file))
                    File.Delete(file);
            if (session.Length > 0 && Directory.Exists(session) && !Directory.EnumerateFileSystemEntries(session).Any())
                Directory.Delete(session);
        }
    }

    private static bool CanPause(RunningJob job) => !job.Ended && job.Card is { State: JobState.Running } && job.Worker is { HasExited: false } && job.Pause == null;

    private void PauseJob(RunningJob job)
    {
        if (!CanPause(job))
            return;
        try
        {
            job.Pause = ProcessTreePause.Suspend(job.Worker!);
            job.Card!.SetPaused(true);
            // A paused job frees its slot so a waiting job can start.
            if (job.HoldsSlot)
            { job.HoldsSlot = false; slots.Release(); }
            Journal.Write("JobPaused", new { job.Queued.Job.Action, processes = job.Pause.Count });
        }
        catch (Exception ex) when (ex is System.ComponentModel.Win32Exception or InvalidOperationException)
        { Notify(L.T("Could not pause"), ex.Message); }
        taskIndicator.Update();
    }

    private void ResumeJob(RunningJob job)
    {
        if (job.Pause == null || job.Ended)
            return;
        job.Pause.Dispose();
        job.Pause = null;
        job.Card?.SetPaused(false);
        // Take a slot back if one is free; otherwise run anyway, since the user asked for it.
        job.HoldsSlot = slots.Wait(0);
        Journal.Write("JobResumed", new { job.Queued.Job.Action });
        taskIndicator.Update();
    }

    private void CancelJob(RunningJob job)
    {
        if (job.Ended)
            return;
        job.Card?.SetStopping();
        taskIndicator.Update();
        // Killing works on a suspended tree too, so a paused job can be cancelled directly.
        try { job.Cancellation.Cancel(); } catch (ObjectDisposedException) { }
    }

    private void Notify(string title, string message)
    {
        if (disposed)
            return;
        app.Dispatcher.InvokeAsync(() =>
        {
            if (disposed)
                return;
            tray.BalloonTipTitle = title;
            tray.BalloonTipText = message.Length > 220 ? message[..220] : message;
            tray.ShowBalloonTip(3000);
        });
    }

    public void Dispose()
    {
        if (disposed)
            return;
        disposed = true;
        StartupManager.Changed -= RefreshStartupMenu;
        timer.Stop();
        stopping.Cancel();
        queue.Writer.TryComplete();
        foreach (var job in jobs.ToList())
        {
            try
            {
                if (job.Worker is { HasExited: false } worker)
                { worker.Kill(true); job.Sweep?.Run().Wait(TimeSpan.FromSeconds(3)); }
            }
            catch (InvalidOperationException) { }
            job.Pause?.Dispose();
        }
        watch?.Dispose();
        openRequest.Dispose();
        if (hotkeySource != null)
        {
            try
            {
                IntPtr handle = hotkeySource.Handle;
                Native.UnregisterHotKey(handle, HOTKEY_ID_F8);
                Native.UnregisterHotKey(handle, HOTKEY_ID_F9);
                Native.UnregisterHotKey(handle, HOTKEY_ID_F10);
                Native.UnregisterHotKey(handle, HOTKEY_ID_ALTSPACE);
                Native.UnregisterHotKey(handle, HOTKEY_ID_WINSHIFTL);
                Native.UnregisterHotKey(handle, HOTKEY_ID_CTRLSHIFTL);
                Native.UnregisterHotKey(handle, HOTKEY_ID_CTRLSHIFTSPACE);
            }
            catch { }
            hotkeySource.Dispose();
            hotkeySource = null;
        }
        tray.Dispose();
        trayIcon.Dispose();
        welcome?.Close();
        FloatShelfWindow.Instance.Close();
        wheel.Close();
        taskIndicator.Close();
        if (Instance == this) Instance = null;
        Journal.Write("Stopped");
    }

    private static string CleanErrorMessage(string raw)
    {
        if (string.IsNullOrWhiteSpace(raw)) return L.T("The conversion failed.");
        string trimmed = raw.Trim();
        if (trimmed.Contains("PermissionError", StringComparison.OrdinalIgnoreCase) ||
            trimmed.Contains("Permission denied", StringComparison.OrdinalIgnoreCase) ||
            trimmed.Contains("Operation not permitted", StringComparison.OrdinalIgnoreCase) ||
            trimmed.Contains("[Errno 1]", StringComparison.OrdinalIgnoreCase) ||
            trimmed.Contains("[Errno 13]", StringComparison.OrdinalIgnoreCase))
        {
            return L.T("Permission restricted by system. Output saved to Downloads.");
        }
        if (trimmed.Contains("FileNotFoundError", StringComparison.OrdinalIgnoreCase) ||
            trimmed.Contains("No such file or directory", StringComparison.OrdinalIgnoreCase))
        {
            return L.T("File could not be found or was moved.");
        }
        if (trimmed.Contains("MemoryError", StringComparison.OrdinalIgnoreCase))
        {
            return L.T("File is too large to process in memory.");
        }
        if (trimmed.StartsWith("[Errno") || trimmed.Contains("Traceback (most recent call last)"))
        {
            return L.T("Operation restricted by file permissions or read-only directory.");
        }
        return trimmed.Length > 90 ? trimmed[..87] + "..." : trimmed;
    }
}
