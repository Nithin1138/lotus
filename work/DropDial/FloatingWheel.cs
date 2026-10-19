using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Effects;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using Forms = System.Windows.Forms;
using ShapePath = System.Windows.Shapes.Path;

namespace DropDial;

// The wheel shown while dragging files or triggered via shortcuts/tray. With fewer than ten choices it is one wheel. With more, the first wheel lists
// categories (each shows a preview of the tools inside); hovering one opens a second wheel around the first with that
// category's tools, and the drop happens on one of those.
internal sealed class DropWheel : Window
{
    private sealed class Ring
    {
        public readonly List<ShapePath> Petals = [], Sidewalls = [];
        public readonly List<FrameworkElement> Labels = [];
        public int Highlighted = -1;
    }
    private readonly Action<string[], Operation> submit;
    private readonly Grid stage = new();
    private readonly Canvas canvas = new() { Width = 380, Height = 390 };
    private readonly Ring first = new(), second = new();
    private readonly Border center;

    // Top Floating Pill Bar & Close Button
    private const double TopBarHeight = 44;
    private readonly StackPanel topBarContainer = new() { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 6, 0, 6) };
    private readonly Border floatBar = new() { Height = 32, CornerRadius = new CornerRadius(16), Padding = new Thickness(3, 2, 3, 2) };
    private readonly Border closeButton = new() { Width = 32, Height = 32, CornerRadius = new CornerRadius(16), Margin = new Thickness(8, 0, 0, 0), Cursor = Cursors.Hand };
    private readonly TextBlock closeIcon = new() { Text = "✕", FontSize = 12, FontWeight = FontWeights.Bold, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };

    // Tabs inside floatBar
    private readonly Border convertTab = new() { Height = 26, CornerRadius = new CornerRadius(13), Margin = new Thickness(1, 0, 1, 0), Cursor = Cursors.Hand };
    private readonly Border convertKeycap = new() { Width = 18, Height = 18, CornerRadius = new CornerRadius(4), BorderThickness = new Thickness(0.5), Margin = new Thickness(0, 0, 5, 0) };
    private readonly TextBlock convertKeyText = new() { Text = "⇧", FontSize = 9, FontWeight = FontWeights.Bold, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
    private readonly TextBlock convertLabel = new() { Text = L.T("Convert"), FontSize = 11, VerticalAlignment = VerticalAlignment.Center };

    private readonly Border toolsTab = new() { Height = 26, CornerRadius = new CornerRadius(13), Margin = new Thickness(1, 0, 1, 0), Cursor = Cursors.Hand };
    private readonly Border toolsKeycap = new() { Width = 26, Height = 18, CornerRadius = new CornerRadius(4), BorderThickness = new Thickness(0.5), Margin = new Thickness(0, 0, 5, 0) };
    private readonly TextBlock toolsKeyText = new() { Text = "Ctrl", FontSize = 9, FontWeight = FontWeights.Bold, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
    private readonly TextBlock toolsLabel = new() { Text = L.T("Tools"), FontSize = 11, VerticalAlignment = VerticalAlignment.Center };

    private readonly Border actionsTab = new() { Height = 26, CornerRadius = new CornerRadius(13), Margin = new Thickness(1, 0, 1, 0), Cursor = Cursors.Hand };
    private readonly Border actionsKeycap = new() { Width = 22, Height = 18, CornerRadius = new CornerRadius(4), BorderThickness = new Thickness(0.5), Margin = new Thickness(0, 0, 5, 0) };
    private readonly TextBlock actionsKeyText = new() { Text = "Alt", FontSize = 9, FontWeight = FontWeights.Bold, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
    private readonly TextBlock actionsLabel = new() { Text = L.T("Actions"), FontSize = 11, VerticalAlignment = VerticalAlignment.Center };

    // Center Hub elements
    private readonly StackPanel hubSlicePanel = new() { VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Center, Visibility = Visibility.Collapsed };
    private readonly TextBlock hubModeBadge = new() { FontSize = 8.5, FontWeight = FontWeights.Bold, Foreground = Solid("#FF6208"), TextAlignment = TextAlignment.Center };
    private readonly TextBlock hubSliceTitle = new() { FontSize = 12.5, FontWeight = FontWeights.Bold, TextAlignment = TextAlignment.Center, TextTrimming = TextTrimming.CharacterEllipsis, MaxWidth = 96, Margin = new Thickness(0, 1, 0, 1) };
    private readonly TextBlock hubSliceSub = new() { Text = L.T("Click or drop"), FontSize = 8, FontWeight = FontWeights.Medium, Foreground = UiTheme.Muted, TextAlignment = TextAlignment.Center };

    private readonly StackPanel hubFilePanel = new() { VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Center, Visibility = Visibility.Collapsed };
    private readonly Image hubThumbnail = new() { Width = 26, Height = 26, Stretch = Stretch.Uniform, HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 0, 0, 2) };
    private readonly TextBlock hubFileName = new() { FontSize = 8.5, FontWeight = FontWeights.SemiBold, TextAlignment = TextAlignment.Center, MaxWidth = 92, TextTrimming = TextTrimming.CharacterEllipsis };
    private readonly TextBlock hubFileMode = new() { FontSize = 8, FontWeight = FontWeights.Medium, Foreground = Solid("#FF6208"), TextAlignment = TextAlignment.Center, Margin = new Thickness(0, 1, 0, 0) };

    private readonly StackPanel hubIdlePanel = new() { VerticalAlignment = VerticalAlignment.Center, HorizontalAlignment = HorizontalAlignment.Center };
    private readonly TextBlock hubBrand = new() { Text = "Lotus", FontSize = 14, FontWeight = FontWeights.Bold, Foreground = Solid("#FF6208"), TextAlignment = TextAlignment.Center };
    private readonly TextBlock hubIdleSub = new() { Text = L.T("Drop files\nor click"), FontSize = 8.5, FontWeight = FontWeights.Medium, Foreground = UiTheme.Muted, TextAlignment = TextAlignment.Center, Margin = new Thickness(0, 2, 0, 0) };

    // Bottom pagination dots and hint label
    private readonly StackPanel paginationDots = new() { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Center };
    private readonly TextBlock hint = new() { TextAlignment = TextAlignment.Center, FontSize = 9, Foreground = UiTheme.Muted, Width = 380 };

    // The wheel's colours in the light and the dark theme; it takes the current theme each time it opens.
    private sealed record Look(Brush RestingFace, Brush SelectedFace, Brush OpenFace, Brush RestingSide, Brush SelectedSide, Brush OpenSide, Brush RestingOutline, Brush OpenOutline, Brush OuterFace, Brush Disk, Brush Hub, Brush HubEdge);
    private static readonly Look LightLook = new(Solid("#F1F3F2"), Solid("#FF6208"), Solid("#FFE2CF"), Solid("#DDE2DE"), Solid("#D94D04"), Solid("#F0C3A5"), Solid("#CFD5D1"), Solid("#F2B791"), Solid("#F7F8F7"), Solid("#EAEEEB"), Solid("#FFFFFF"), Solid("#F8FAF8"));
    private static readonly Look DarkLook = new(Solid("#30353A"), Solid("#FF6208"), Solid("#5C3723"), Solid("#1C2023"), Solid("#D94D04"), Solid("#3D2416"), Solid("#42484E"), Solid("#8C512E"), Solid("#373C41"), Solid("#24282B"), Solid("#2B2F34"), Solid("#3C4147"));
    private static Look Shade => UiTheme.Dark ? DarkLook : LightLook;
    private static Brush RestingFace => Shade.RestingFace;
    private static Brush SelectedFace => Shade.SelectedFace;
    private static Brush OpenFace => Shade.OpenFace;
    private static Brush RestingSide => Shade.RestingSide;
    private static Brush SelectedSide => Shade.SelectedSide;
    private static Brush OpenSide => Shade.OpenSide;
    private static Brush RestingOutline => Shade.RestingOutline;
    private static Brush OpenOutline => Shade.OpenOutline;
    private static Brush OuterFace => Shade.OuterFace;
    private readonly Ellipse disk, hubSide;
    private List<Operation> operations = [];
    private List<ToolGroup>? groups;
    private int openGroup = -1;
    private string[] paths = [];
    private bool entered, eligible, allowedCopy;
    private WheelMode mode = WheelMode.Convert;

    // -- Smooth rotation state --
    /// Full list of operations for the current mode/file (may exceed 8).
    private List<Operation> allOperations = [];
    /// Current side/page index (0-based: 0 is Side 1, 1 is Side 2, etc.)
    private int currentSideIndex = 0;
    private int TotalSides => Math.Max(1, (allOperations.Count + 7) / 8);
    /// The current visual rotation angle applied to petal geometry (degrees), smoothly animated.
    private double wheelAngle = 0;
    /// Target angle the spring animation follows.
    private double targetAngle = 0;
    /// Accumulated mouse-wheel delta for sub-step smoothness.
    private double scrollAccum = 0;
    /// 60 fps animation timer.
    private readonly System.Windows.Threading.DispatcherTimer rotationTimer;
    public long Instance { get; private set; }
    public WheelMode CurrentMode => mode;
    public bool ToolsMode => mode == WheelMode.Tools;
    public bool HasFileDrag => entered && paths.Length > 0;
    // The size of the window's picture: 380 for one wheel, larger when a second wheel can open around it.
    public double StageSize { get; private set; } = SingleSize;
    private const double SingleSize = 380, DoubleSize = 640;
    private const double Center = 190, Outer = 172, Inner = 65, OuterRingInner = 184, OuterRingOuter = 300;

    public DropWheel(Action<string[], Operation> submit)
    {
        this.submit = submit;
        Title = L.T("Lotus DropDial");
        Icon = AppIcon.Window;
        Width = SingleSize;
        Height = SingleSize + TopBarHeight;
        WindowStyle = WindowStyle.None;
        ResizeMode = ResizeMode.NoResize;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        ShowInTaskbar = false;
        ShowActivated = false;
        Topmost = true;
        AllowDrop = true;
        Focusable = true;
        FontFamily = UiTheme.Font;

        // --- 1. Assemble Top Floating Pill Toolbar ---
        var floatStack = new StackPanel { Orientation = Orientation.Horizontal };

        var cStack = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(5, 0, 8, 0) };
        convertKeycap.Child = convertKeyText;
        cStack.Children.Add(convertKeycap);
        cStack.Children.Add(convertLabel);
        convertTab.Child = cStack;
        floatStack.Children.Add(convertTab);

        var tStack = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(5, 0, 8, 0) };
        toolsKeycap.Child = toolsKeyText;
        tStack.Children.Add(toolsKeycap);
        tStack.Children.Add(toolsLabel);
        toolsTab.Child = tStack;
        floatStack.Children.Add(toolsTab);

        var aStack = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(5, 0, 8, 0) };
        actionsKeycap.Child = actionsKeyText;
        aStack.Children.Add(actionsKeycap);
        aStack.Children.Add(actionsLabel);
        actionsTab.Child = aStack;
        floatStack.Children.Add(actionsTab);

        floatBar.Child = floatStack;
        topBarContainer.Children.Add(floatBar);

        closeButton.Child = closeIcon;
        topBarContainer.Children.Add(closeButton);

        WireTabHover(convertTab, WheelMode.Convert);
        WireTabHover(toolsTab, WheelMode.Tools);
        WireTabHover(actionsTab, WheelMode.Actions);

        closeButton.MouseEnter += (_, _) =>
        {
            closeButton.Background = Solid("#E84135");
            closeIcon.Foreground = Brushes.White;
        };
        closeButton.MouseLeave += (_, _) =>
        {
            closeButton.Background = Shade.Disk;
            closeIcon.Foreground = UiTheme.Muted;
        };
        closeButton.MouseLeftButtonUp += (_, e) =>
        {
            e.Handled = true;
            SoundManager.PlayPop();
            Dismiss("CloseButton");
        };

        // --- 2. Assemble Canvas & Wheel ---
        disk = new Ellipse { Width = 360, Height = 360, Fill = Shade.Disk, IsHitTestVisible = false,
            Effect = new DropShadowEffect { BlurRadius = 14, ShadowDepth = 5, Opacity = .13, Color = Color.FromRgb(42, 50, 45) } };
        Canvas.SetLeft(disk, 10);
        Canvas.SetTop(disk, 10);
        canvas.Children.Add(disk);

        hubSide = new Ellipse { Width = 112, Height = 112, Fill = RestingSide, IsHitTestVisible = false,
            Effect = new DropShadowEffect { BlurRadius = 8, ShadowDepth = 2, Opacity = .08, Color = Color.FromRgb(42, 50, 45) } };
        Canvas.SetLeft(hubSide, Center - 56); Canvas.SetTop(hubSide, Center - 56 + 4);
        Canvas.SetZIndex(hubSide, 9); canvas.Children.Add(hubSide);

        center = new Border
        {
            Width = 112,
            Height = 112,
            CornerRadius = new CornerRadius(56),
            Background = Shade.Hub,
            BorderBrush = Solid("#FF6208"),
            BorderThickness = new Thickness(1.5),
            Cursor = Cursors.Hand
        };
        center.MouseEnter += (_, _) => center.BorderThickness = new Thickness(2.0);
        center.MouseLeave += (_, _) => center.BorderThickness = new Thickness(1.5);
        center.MouseLeftButtonUp += (_, e) => { e.Handled = true; OnHubClicked(); };

        hubSlicePanel.Children.Add(hubModeBadge);
        hubSlicePanel.Children.Add(hubSliceTitle);
        hubSlicePanel.Children.Add(hubSliceSub);

        hubFilePanel.Children.Add(hubThumbnail);
        hubFilePanel.Children.Add(hubFileName);
        hubFilePanel.Children.Add(hubFileMode);

        hubIdlePanel.Children.Add(hubBrand);
        hubIdlePanel.Children.Add(hubIdleSub);

        var hubGrid = new Grid();
        hubGrid.Children.Add(hubSlicePanel);
        hubGrid.Children.Add(hubFilePanel);
        hubGrid.Children.Add(hubIdlePanel);
        center.Child = hubGrid;

        Canvas.SetLeft(center, Center - 56);
        Canvas.SetTop(center, Center - 56);
        Canvas.SetZIndex(center, 10);
        canvas.Children.Add(center);

        Canvas.SetZIndex(paginationDots, 15);
        canvas.Children.Add(paginationDots);

        Canvas.SetLeft(hint, 0);
        Canvas.SetTop(hint, Center + Outer + 10);
        Canvas.SetZIndex(hint, 15);
        canvas.Children.Add(hint);

        // --- 3. Assemble Stage Grid ---
        stage.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        stage.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });

        Grid.SetRow(topBarContainer, 0);
        stage.Children.Add(topBarContainer);

        Grid.SetRow(canvas, 1);
        canvas.HorizontalAlignment = HorizontalAlignment.Center;
        canvas.VerticalAlignment = VerticalAlignment.Center;
        stage.Children.Add(canvas);

        Content = stage;

        PreviewDragEnter += Enter;
        PreviewDragOver += Over;
        PreviewDragLeave += (_, e) => { var p = e.GetPosition(this); if (p.X < 0 || p.Y < 0 || p.X > ActualWidth || p.Y > ActualHeight) { Highlight(first, -1); Highlight(second, -1); } e.Handled = true; };
        PreviewDrop += OnDrop;
        PreviewMouseLeftButtonUp += OnPreviewMouseLeftButtonUp;
        PreviewMouseMove += OnMouseMove;
        MouseLeave += (_, _) => { Highlight(first, -1); Highlight(second, -1); };
        PreviewMouseRightButtonUp += (_, e) => { e.Handled = true; Dismiss("RightClick"); };
        PreviewKeyDown += OnPreviewKeyDown;
        // Mouse-wheel rotates the tool ring smoothly.
        PreviewMouseWheel += OnMouseWheel;
        // 60-fps spring animation timer.
        rotationTimer = new System.Windows.Threading.DispatcherTimer(System.Windows.Threading.DispatcherPriority.Render)
        { Interval = TimeSpan.FromSeconds(1.0 / 60.0) };
        rotationTimer.Tick += TickRotation;

        Recolor();
    }

    private void WireTabHover(Border tab, WheelMode tabMode)
    {
        tab.MouseEnter += (_, _) =>
        {
            if (mode != tabMode)
                tab.Background = UiTheme.Dark ? Solid("#18FFFFFF") : Solid("#0C000000");
        };
        tab.MouseLeave += (_, _) =>
        {
            if (mode != tabMode)
                tab.Background = Brushes.Transparent;
        };
        tab.MouseLeftButtonUp += (_, e) =>
        {
            e.Handled = true;
            SoundManager.PlayPop();
            ChangeMode(tabMode);
        };
    }

    // Follows a theme change made since the wheel was last shown.
    private void Recolor()
    {
        UiTheme.Refresh();
        disk.Fill = Shade.Disk;
        hubSide.Fill = Shade.RestingSide;
        center.Background = Shade.Hub;
        center.BorderBrush = Solid("#FF6208");
        floatBar.Background = Shade.Disk;
        floatBar.BorderBrush = Shade.RestingOutline;
        closeButton.Background = Shade.Disk;
        closeButton.BorderBrush = Shade.RestingOutline;
        closeIcon.Foreground = UiTheme.Muted;
        UpdateTopBar();
        UpdateHub();
        UpdatePaginationDots();
    }

    private void UpdateTopBar()
    {
        UpdateTab(convertTab, convertKeycap, convertKeyText, convertLabel, mode == WheelMode.Convert);
        UpdateTab(toolsTab, toolsKeycap, toolsKeyText, toolsLabel, mode == WheelMode.Tools);
        UpdateTab(actionsTab, actionsKeycap, actionsKeyText, actionsLabel, mode == WheelMode.Actions);
    }

    private static void UpdateTab(Border tab, Border keycap, TextBlock keyText, TextBlock label, bool active)
    {
        bool dark = UiTheme.Dark;
        if (active)
        {
            tab.Background = dark ? Solid("#42484E") : Solid("#FFFFFF");
            tab.Effect = new DropShadowEffect { BlurRadius = 4, ShadowDepth = 1, Opacity = dark ? 0.25 : 0.08, Color = Color.FromRgb(42, 50, 45) };
            keycap.Background = dark ? Solid("#2D3237") : Solid("#F0F2F1");
            keycap.BorderBrush = dark ? Solid("#555D65") : Solid("#D0D5D2");
            keyText.Foreground = Solid("#FF6208");
            label.Foreground = dark ? Brushes.White : UiTheme.Ink;
            label.FontWeight = FontWeights.Bold;
        }
        else
        {
            tab.Background = Brushes.Transparent;
            tab.Effect = null;
            keycap.Background = dark ? Solid("#25292D") : Solid("#E2E6E3");
            keycap.BorderBrush = dark ? Solid("#383E44") : Solid("#CCD1CD");
            keyText.Foreground = UiTheme.Muted;
            label.Foreground = UiTheme.Muted;
            label.FontWeight = FontWeights.Medium;
        }
    }

    private void UpdateHub()
    {
        // 1. Hovered slice preview
        if (first.Highlighted >= 0 && first.Highlighted < operations.Count)
        {
            hubSlicePanel.Visibility = Visibility.Visible;
            hubFilePanel.Visibility = Visibility.Collapsed;
            hubIdlePanel.Visibility = Visibility.Collapsed;
            hubModeBadge.Text = mode switch
            {
                WheelMode.Convert => "CONVERT",
                WheelMode.Tools => "TOOL",
                _ => "ACTION"
            };
            hubSliceTitle.Text = operations[first.Highlighted].Label;
            hubSliceTitle.Foreground = UiTheme.Ink;
            return;
        }
        if (second.Highlighted >= 0 && openGroup >= 0 && groups != null && second.Highlighted < groups[openGroup].Items.Count)
        {
            hubSlicePanel.Visibility = Visibility.Visible;
            hubFilePanel.Visibility = Visibility.Collapsed;
            hubIdlePanel.Visibility = Visibility.Collapsed;
            hubModeBadge.Text = "TOOL";
            hubSliceTitle.Text = groups[openGroup].Items[second.Highlighted].Label;
            hubSliceTitle.Foreground = UiTheme.Ink;
            return;
        }

        // 2. File loaded state
        if (paths.Length > 0)
        {
            hubSlicePanel.Visibility = Visibility.Collapsed;
            hubFilePanel.Visibility = Visibility.Visible;
            hubIdlePanel.Visibility = Visibility.Collapsed;

            if (paths.Length == 1)
            {
                hubThumbnail.Source = GetThumbnail(paths[0]);
                hubThumbnail.Visibility = hubThumbnail.Source != null ? Visibility.Visible : Visibility.Collapsed;
                hubFileName.Text = TruncateMiddle(System.IO.Path.GetFileName(paths[0]), 14);
                hubFileName.Foreground = UiTheme.Ink;
                hubFileMode.Text = mode switch
                {
                    WheelMode.Convert => "CONVERT",
                    WheelMode.Tools => "TOOLS",
                    _ => "ACTIONS"
                };
                hubFileMode.Foreground = Solid("#FF6208");
            }
            else
            {
                hubThumbnail.Source = null;
                hubThumbnail.Visibility = Visibility.Collapsed;
                hubFileName.Text = L.F("{0} files", paths.Length);
                hubFileName.Foreground = Solid("#FF6208");
                hubFileMode.Text = L.T("click to switch");
                hubFileMode.Foreground = UiTheme.Muted;
            }
            return;
        }

        // 3. Idle state
        hubSlicePanel.Visibility = Visibility.Collapsed;
        hubFilePanel.Visibility = Visibility.Collapsed;
        hubIdlePanel.Visibility = Visibility.Visible;
        hubBrand.Foreground = Solid("#FF6208");
        hubIdleSub.Foreground = UiTheme.Muted;
    }

    private void UpdatePaginationDots()
    {
        paginationDots.Children.Clear();
        if (allOperations.Count <= 8 || groups != null)
        {
            paginationDots.Visibility = Visibility.Collapsed;
            return;
        }
        paginationDots.Visibility = Visibility.Visible;
        int total = TotalSides;
        for (int i = 0; i < total; i++)
        {
            bool isCurrent = i == currentSideIndex;
            var dot = new Ellipse
            {
                Width = isCurrent ? 6 : 4,
                Height = isCurrent ? 6 : 4,
                Fill = isCurrent ? Solid("#FF6208") : (UiTheme.Dark ? Solid("#66FFFFFF") : Solid("#44000000")),
                Margin = new Thickness(2.5, 0, 2.5, 0),
                VerticalAlignment = VerticalAlignment.Center
            };
            paginationDots.Children.Add(dot);
        }
        paginationDots.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
        Canvas.SetLeft(paginationDots, Center - paginationDots.DesiredSize.Width / 2);
        Canvas.SetTop(paginationDots, Center + Outer + 2);
    }

    public void OpenAt(Native.POINT point, WheelMode mode)
    {
        Recolor();
        Instance++;
        entered = false;
        eligible = allowedCopy = false;
        paths = [];
        groups = null;
        this.mode = mode;
        ResetRotation();
        LoadDefaultItems();
        UpdateTopBar();
        UpdateHub();
        Resize(SingleSize);
        if (!IsVisible)
            Show();
        var hwnd = new WindowInteropHelper(this).Handle;
        var area = Forms.Screen.FromPoint(new System.Drawing.Point(point.X, point.Y)).WorkingArea;
        Native.SetWindowPos(hwnd, new IntPtr(-1), point.X, point.Y, 0, 0, 0x0001 | 0x0010);
        double scale = Native.GetDpiForWindow(hwnd) / 96.0;
        int sizeW = (int)Math.Round(SingleSize * scale);
        int sizeH = (int)Math.Round((SingleSize + TopBarHeight) * scale);
        int radius = (int)Math.Round(180.0 * scale);
        int targetX = (point.X + radius + sizeW / 2 <= area.Right) ? (point.X + radius - sizeW / 2) : (point.X - radius - sizeW / 2);
        int x = Math.Clamp(targetX, area.Left, Math.Max(area.Left, area.Right - sizeW));
        int targetY = point.Y - sizeH / 2;
        int y = Math.Clamp(targetY, area.Top, Math.Max(area.Top, area.Bottom - sizeH));
        Native.SetWindowPos(hwnd, new IntPtr(-1), x, y, sizeW, sizeH, 0x0010 | 0x0040);
        UpdateLayout();
        Focus();
    }

    public void OpenAt(Native.POINT point, bool tools) =>
        OpenAt(point, tools ? WheelMode.Tools : WheelMode.Convert);

    // Grows or shrinks the window around the wheel's centre so a second wheel has room.
    private void Resize(double size)
    {
        if (Math.Abs(size - StageSize) < .5)
            return;
        var hwnd = new WindowInteropHelper(this).Handle;
        if (hwnd == IntPtr.Zero || !IsVisible)
        {
            StageSize = size;
            Width = size;
            Height = size + TopBarHeight;
            canvas.Width = size;
            canvas.Height = size > SingleSize ? size : 390;
            return;
        }
        Native.GetWindowRect(hwnd, out var current);
        double scale = Native.GetDpiForWindow(hwnd) / 96.0;
        int pixelsW = (int)Math.Round(size * scale);
        int pixelsH = (int)Math.Round((size + TopBarHeight) * scale);
        int midX = (current.Left + current.Right) / 2;
        int midY = (current.Top + current.Bottom) / 2;
        var area = Forms.Screen.FromPoint(new System.Drawing.Point(midX, midY)).WorkingArea;
        int x = Math.Clamp(midX - pixelsW / 2, area.Left, Math.Max(area.Left, area.Right - pixelsW));
        int y = Math.Clamp(midY - pixelsH / 2, area.Top, Math.Max(area.Top, area.Bottom - pixelsH));
        StageSize = size;
        Width = size;
        Height = size + TopBarHeight;
        canvas.Width = size;
        canvas.Height = size > SingleSize ? size : 390;
        Native.SetWindowPos(hwnd, new IntPtr(-1), x, y, pixelsW, pixelsH, 0x0010 | 0x0040);
        UpdateLayout();
    }

    public void Dismiss(string reason)
    {
        if (!IsVisible)
            return;
        Hide();
        paths = [];
        eligible = false;
        entered = false;
        Journal.Write("WheelDismissed", new { reason });
    }

    // For screenshots: show the wheel as if these files were being dragged over it, with one option lit.
    public void Preview(string[] files, WheelMode targetMode, string highlightId)
    {
        Recolor();
        mode = targetMode;
        paths = files;
        entered = allowedCopy = true;
        Populate();
        if (groups != null)
        {
            int group = groups.FindIndex(g => g.Items.Any(o => o.Id == highlightId));
            if (group >= 0)
            {
                OpenGroup(group);
                Highlight(second, groups[group].Items.FindIndex(o => o.Id == highlightId));
            }
        }
        else
            Highlight(first, operations.FindIndex(o => o.Id == highlightId));
    }

    public void Preview(string[] files, bool toolsMode, string highlightId) =>
        Preview(files, toolsMode ? WheelMode.Tools : WheelMode.Convert, highlightId);

    public void ChangeMode(WheelMode nextMode)
    {
        mode = nextMode;
        UpdateTopBar();
        if (!entered && paths.Length == 0)
        {
            LoadDefaultItems();
            return;
        }
        Populate();
    }

    public void ChangeMode(bool nextTools) => ChangeMode(nextTools ? WheelMode.Tools : WheelMode.Convert);

    public void LoadFiles(string[] filePaths, WheelMode? targetMode = null)
    {
        if (targetMode.HasValue)
            mode = targetMode.Value;
        paths = filePaths;
        entered = allowedCopy = true;
        Populate();
        if (!IsVisible)
        {
            Native.GetCursorPos(out var pt);
            OpenAt(pt, mode);
        }
    }

    public void LoadDefaultItems()
    {
        ResetRotation();
        openGroup = -1;
        groups = null;
        RenderSecond(null);
        allOperations = GetDefaultOperations(mode);
        operations = allOperations;
        SyncWindow();
        eligible = true;
        hint.Text = Prompt();
        UpdateTopBar();
        UpdateHub();
        UpdatePaginationDots();
        Render(operations);
        Resize(SingleSize);
    }

    private static List<Operation> GetDefaultOperations(WheelMode m) => m switch
    {
        WheelMode.Actions => Catalog.FileActions.ToList(),
        WheelMode.Tools => [
            Catalog.Definition("compress", "image"),
            Catalog.Definition("resizeImage", "image"),
            Catalog.Definition("cropImage", "image"),
            Catalog.Definition("editImage", "image"),
            Catalog.Definition("frameImage", "image"),
            Catalog.Definition("watermark", "image"),
            Catalog.Definition("redactImage", "image"),
            Catalog.Definition("ocrImage", "image"),
            Catalog.Definition("annotateImage", "image"),
            Catalog.Definition("makeIcon", "image")
        ],
        _ => [
            new("convert:png", "PNG"),
            new("convert:webp", "WEBP"),
            new("convert:jpg", "JPG"),
            new("convert:pdf", "PDF"),
            new("convert:docx", "DOCX"),
            new("convert:txt", "TXT"),
            new("convert:mp4", "MP4"),
            new("convert:zip", "ZIP")
        ]
    };

    private void Populate()
    {
        if (paths.Length == 0)
        {
            LoadDefaultItems();
            return;
        }
        var all = paths.Length <= 200 ? Catalog.Options(paths, mode) : [];
        groups = mode == WheelMode.Tools && paths.Length > 0 && Catalog.TwoWheels ? Catalog.Grouped(all, Catalog.Category(paths[0])) : null;
        openGroup = -1;
        RenderSecond(null);
        allOperations = groups == null ? all : groups.Select((g, i) => new Operation("__group:" + i, g.Label)).ToList();
        ResetRotation();
        operations = allOperations;
        SyncWindow();
        eligible = allowedCopy && all.Count > 0;
        bool packing = Catalog.PackingOnly(paths);
        hint.Text = packing && mode != WheelMode.Tools ? L.T("No conversions for this type") : eligible ? Prompt() : L.T("Esc to cancel");
        UpdateTopBar();
        UpdateHub();
        UpdatePaginationDots();
        Render(operations);
        Resize(groups != null ? DoubleSize : SingleSize);
    }

    // Keeps `operations` as a page of up to 8 items from `allOperations`.
    private void SyncWindow()
    {
        if (allOperations.Count <= 8) { currentSideIndex = 0; operations = allOperations; return; }
        int total = TotalSides;
        currentSideIndex = ((currentSideIndex % total) + total) % total;
        int start = currentSideIndex * 8;
        int count = Math.Min(8, allOperations.Count - start);
        operations = allOperations.GetRange(start, count);
    }

    // Resets rotation state to zero.
    private void ResetRotation()
    {
        rotationTimer.Stop();
        currentSideIndex = 0;
        wheelAngle = 0;
        targetAngle = 0;
        scrollAccum = 0;
    }

    // Mouse-wheel handler: rotate to another side only if more than 8 items.
    private void OnMouseWheel(object sender, MouseWheelEventArgs e)
    {
        if (allOperations.Count <= 8 || groups != null) return;
        e.Handled = true;

        scrollAccum += e.Delta;
        const double step = 120.0;
        if (Math.Abs(scrollAccum) >= step)
        {
            bool forward = scrollAccum < 0;
            scrollAccum = 0;
            int oldSide = currentSideIndex;
            int total = TotalSides;
            currentSideIndex = forward ? (currentSideIndex + 1) % total : (currentSideIndex - 1 + total) % total;
            if (currentSideIndex != oldSide)
            {
                SoundManager.PlayTick();
                SyncWindow();
                hint.Text = Prompt();
                UpdatePaginationDots();
                wheelAngle = forward ? 120.0 : -120.0;
                targetAngle = 0;
                Render(operations, wheelAngle);
                if (!rotationTimer.IsEnabled)
                    rotationTimer.Start();
            }
        }
    }

    // Spring-follow animation tick.
    private void TickRotation(object? sender, EventArgs e)
    {
        double diff = targetAngle - wheelAngle;
        if (Math.Abs(diff) < 0.05)
        {
            wheelAngle = targetAngle;
            rotationTimer.Stop();
        }
        else
        {
            wheelAngle += diff * 0.18;
        }
        Render(operations, wheelAngle);
    }

    private string Prompt()
    {
        if (groups != null) return L.T("Move onto a category, pick a tool, then release");
        if (allOperations.Count > 8)
            return L.F("Side {0} of {1} · scroll to rotate", currentSideIndex + 1, TotalSides);
        return mode switch
        {
            WheelMode.Actions => L.T("Pick an action or release to run"),
            WheelMode.Tools => L.T("Pick a tool or release to run"),
            _ => L.T("Release on an option")
        };
    }

    private void Enter(object sender, DragEventArgs e)
    {
        if (!entered)
        {
            entered = true;
            try
            { paths = e.Data.GetDataPresent(DataFormats.FileDrop) ? e.Data.GetData(DataFormats.FileDrop) as string[] ?? [] : []; }
            catch { paths = []; }
            allowedCopy = (e.AllowedEffects & DragDropEffects.Copy) != 0;
            Populate();
            Journal.Write("DragEntered", new { count = paths.Length, eligible, category = paths.Length > 0 ? Catalog.Category(paths[0]) : "none", allowed = e.AllowedEffects.ToString(), operations = (groups?.SelectMany(g => g.Items) ?? operations).Select(x => x.Id) });
        }
        e.Effects = eligible ? DragDropEffects.Copy : DragDropEffects.None;
        e.Handled = true;
    }

    private void Over(object sender, DragEventArgs e)
    {
        if (!entered)
            Enter(sender, e);

        // Check drag over top bar tabs for instant mode switching during drag!
        var ptTopBar = e.GetPosition(topBarContainer);
        if (ptTopBar.Y >= 0 && ptTopBar.Y <= topBarContainer.ActualHeight)
        {
            var pC = e.GetPosition(convertTab);
            var pT = e.GetPosition(toolsTab);
            var pA = e.GetPosition(actionsTab);
            if (pC.X >= 0 && pC.X <= convertTab.ActualWidth && pC.Y >= 0 && pC.Y <= convertTab.ActualHeight && mode != WheelMode.Convert)
            {
                SoundManager.PlayTick();
                ChangeMode(WheelMode.Convert);
            }
            else if (pT.X >= 0 && pT.X <= toolsTab.ActualWidth && pT.Y >= 0 && pT.Y <= toolsTab.ActualHeight && mode != WheelMode.Tools)
            {
                SoundManager.PlayTick();
                ChangeMode(WheelMode.Tools);
            }
            else if (pA.X >= 0 && pA.X <= actionsTab.ActualWidth && pA.Y >= 0 && pA.Y <= actionsTab.ActualHeight && mode != WheelMode.Actions)
            {
                SoundManager.PlayTick();
                ChangeMode(WheelMode.Actions);
            }
        }

        bool actionable = false;
        if (eligible)
        {
            var point = e.GetPosition(canvas);
            int tool = openGroup >= 0 ? Hit(second, point, OuterRingInner, OuterRingOuter + 10) : -1;
            int category = tool >= 0 ? -1 : Hit(first, point, Inner, Outer);
            if (tool >= 0)
            { Highlight(second, tool); actionable = true; }
            else if (groups != null && category >= 0)
            { OpenGroup(category); Highlight(second, -1); actionable = true; }
            else if (groups == null)
            { Highlight(first, category); actionable = category >= 0; }
            else
                Highlight(second, -1);
        }
        e.Effects = actionable ? DragDropEffects.Copy : DragDropEffects.None;
        e.Handled = true;
    }

    private void OnDrop(object sender, DragEventArgs e)
    {
        if (!entered)
            Enter(sender, e);

        // Check if dropped on top bar tabs
        var ptTopBar = e.GetPosition(topBarContainer);
        if (ptTopBar.Y >= 0 && ptTopBar.Y <= topBarContainer.ActualHeight)
        {
            var pC = e.GetPosition(convertTab);
            var pT = e.GetPosition(toolsTab);
            var pA = e.GetPosition(actionsTab);
            if (pC.X >= 0 && pC.X <= convertTab.ActualWidth && pC.Y >= 0 && pC.Y <= convertTab.ActualHeight)
            {
                ChangeMode(WheelMode.Convert);
                e.Effects = DragDropEffects.Copy;
                e.Handled = true;
                return;
            }
            if (pT.X >= 0 && pT.X <= toolsTab.ActualWidth && pT.Y >= 0 && pT.Y <= toolsTab.ActualHeight)
            {
                ChangeMode(WheelMode.Tools);
                e.Effects = DragDropEffects.Copy;
                e.Handled = true;
                return;
            }
            if (pA.X >= 0 && pA.X <= actionsTab.ActualWidth && pA.Y >= 0 && pA.Y <= actionsTab.ActualHeight)
            {
                ChangeMode(WheelMode.Actions);
                e.Effects = DragDropEffects.Copy;
                e.Handled = true;
                return;
            }
        }

        Operation? selected = null;
        if (eligible)
        {
            var point = e.GetPosition(canvas);
            if (openGroup >= 0 && Hit(second, point, OuterRingInner, OuterRingOuter + 10) is var tool and >= 0)
                selected = groups![openGroup].Items[tool];
            else if (groups == null && Hit(first, point, Inner, Outer) is var index and >= 0 && index < operations.Count)
                selected = operations[index];
        }
        if (selected == null)
        { e.Effects = DragDropEffects.None; e.Handled = true; Dismiss("InvalidDrop"); return; }
        var files = paths.ToArray();
        e.Effects = DragDropEffects.Copy;
        e.Handled = true;
        Hide();
        paths = [];
        entered = false;
        eligible = false;
        Journal.Write("DropAccepted", new { Action = selected.Id, count = files.Length, effect = "Copy" });
        SoundManager.PlayPop();
        Dispatcher.InvokeAsync(() => submit(files, selected));
    }

    private void OnHubClicked()
    {
        if (paths.Length == 0)
        {
            using var dialog = new Forms.OpenFileDialog
            {
                Multiselect = true,
                Title = L.T("Select files to process")
            };
            if (dialog.ShowDialog() == Forms.DialogResult.OK && dialog.FileNames.Length > 0)
            {
                LoadFiles(dialog.FileNames, mode);
            }
        }
        else
        {
            var next = mode switch
            {
                WheelMode.Convert => WheelMode.Tools,
                WheelMode.Tools => WheelMode.Actions,
                _ => WheelMode.Convert
            };
            SoundManager.PlayPop();
            ChangeMode(next);
        }
    }

    private void TriggerOperation(Operation selected)
    {
        if (paths.Length == 0)
        {
            using var dialog = new Forms.OpenFileDialog
            {
                Multiselect = true,
                Title = L.F("Choose files for {0}", selected.Label)
            };
            if (dialog.ShowDialog() == Forms.DialogResult.OK && dialog.FileNames.Length > 0)
            {
                var files = dialog.FileNames;
                Hide();
                paths = [];
                entered = false;
                eligible = false;
                SoundManager.PlayPop();
                Dispatcher.InvokeAsync(() => submit(files, selected));
            }
            return;
        }

        var filesToRun = paths.ToArray();
        Hide();
        paths = [];
        entered = false;
        eligible = false;
        SoundManager.PlayPop();
        Dispatcher.InvokeAsync(() => submit(filesToRun, selected));
    }

    protected override void OnPreviewMouseLeftButtonDown(MouseButtonEventArgs e)
    {
        base.OnPreviewMouseLeftButtonDown(e);
        // Allow dragging the window when clicking on empty top bar or disk background
        var ptInCanvas = e.GetPosition(canvas);
        double distFromCenter = (ptInCanvas - new Point(Center, Center)).Length;
        var ptInTopBar = e.GetPosition(topBarContainer);
        bool overTopBarBackground = ptInTopBar.Y >= 0 && ptInTopBar.Y <= topBarContainer.ActualHeight &&
            !closeButton.IsMouseOver && !convertTab.IsMouseOver && !toolsTab.IsMouseOver && !actionsTab.IsMouseOver;
        bool overCanvasBackground = (distFromCenter > Outer && distFromCenter <= 180) || (distFromCenter < Inner && distFromCenter > 56);

        if (overTopBarBackground || overCanvasBackground)
        {
            DragMove();
        }
    }

    private void OnPreviewMouseLeftButtonUp(object sender, MouseButtonEventArgs e)
    {
        var point = e.GetPosition(canvas);
        double dist = (point - new Point(Center, Center)).Length;
        if (dist <= 56)
        {
            e.Handled = true;
            OnHubClicked();
            return;
        }
        int tool = openGroup >= 0 ? Hit(second, point, OuterRingInner, OuterRingOuter + 10) : -1;
        int category = tool >= 0 ? -1 : Hit(first, point, Inner, Outer);
        Operation? selected = null;
        if (tool >= 0 && openGroup >= 0 && groups != null)
            selected = groups[openGroup].Items[tool];
        else if (category >= 0 && groups != null)
        {
            OpenGroup(category);
            e.Handled = true;
            return;
        }
        else if (category >= 0 && category < operations.Count)
            selected = operations[category];

        if (selected != null)
        {
            e.Handled = true;
            TriggerOperation(selected);
        }
    }

    private void OnMouseMove(object sender, MouseEventArgs e)
    {
        if (HasFileDrag) return;
        var point = e.GetPosition(canvas);
        int tool = openGroup >= 0 ? Hit(second, point, OuterRingInner, OuterRingOuter + 10) : -1;
        int category = tool >= 0 ? -1 : Hit(first, point, Inner, Outer);
        if (tool >= 0)
            Highlight(second, tool);
        else if (groups != null && category >= 0)
        {
            OpenGroup(category);
            Highlight(second, -1);
        }
        else if (groups == null)
            Highlight(first, category);
        else
            Highlight(second, -1);
    }

    private void OnPreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Escape)
        {
            e.Handled = true;
            Dismiss("Escape");
            return;
        }
        if (e.Key == Key.Tab)
        {
            e.Handled = true;
            var next = mode switch
            {
                WheelMode.Convert => WheelMode.Tools,
                WheelMode.Tools => WheelMode.Actions,
                _ => WheelMode.Convert
            };
            SoundManager.PlayPop();
            ChangeMode(next);
            return;
        }
        if (e.Key is Key.LeftShift or Key.RightShift or Key.F8)
        {
            e.Handled = true;
            SoundManager.PlayPop();
            ChangeMode(WheelMode.Convert);
            return;
        }
        if (e.Key is Key.LeftCtrl or Key.RightCtrl or Key.F9)
        {
            e.Handled = true;
            SoundManager.PlayPop();
            ChangeMode(WheelMode.Tools);
            return;
        }
        if (e.Key is Key.LeftAlt or Key.RightAlt or Key.System or Key.F10)
        {
            e.Handled = true;
            SoundManager.PlayPop();
            ChangeMode(WheelMode.Actions);
            return;
        }
        if (e.Key is Key.Left or Key.Up)
        {
            if (operations.Count > 0)
            {
                e.Handled = true;
                int next = (first.Highlighted - 1 + operations.Count) % operations.Count;
                Highlight(first, next);
            }
            return;
        }
        if (e.Key is Key.Right or Key.Down)
        {
            if (operations.Count > 0)
            {
                e.Handled = true;
                int next = (first.Highlighted + 1) % operations.Count;
                Highlight(first, next);
            }
            return;
        }
        if (e.Key is Key.Enter or Key.Space)
        {
            e.Handled = true;
            if (first.Highlighted >= 0 && first.Highlighted < operations.Count)
                TriggerOperation(operations[first.Highlighted]);
            else
                OnHubClicked();
            return;
        }
        int num = e.Key switch
        {
            Key.D1 or Key.NumPad1 => 0,
            Key.D2 or Key.NumPad2 => 1,
            Key.D3 or Key.NumPad3 => 2,
            Key.D4 or Key.NumPad4 => 3,
            Key.D5 or Key.NumPad5 => 4,
            Key.D6 or Key.NumPad6 => 5,
            Key.D7 or Key.NumPad7 => 6,
            Key.D8 or Key.NumPad8 => 7,
            Key.D9 or Key.NumPad9 => 8,
            _ => -1
        };
        if (num >= 0 && num < operations.Count)
        {
            e.Handled = true;
            TriggerOperation(operations[num]);
            return;
        }
    }

    private static Point Polar(double radius, double angle) => new(Center + radius * Math.Cos(angle), Center + radius * Math.Sin(angle));

    private static Brush Solid(string color)
    {
        var brush = new SolidColorBrush((Color)ColorConverter.ConvertFromString(color));
        brush.Freeze();
        return brush;
    }

    private static Geometry Keycap(double start, double end, double inner = Inner, double outer = Outer)
    {
        // Flat circular faces with softly rounded junctions between the arcs and radial edges.
        const double outerCorner = 16, innerCorner = 10;
        double outerInset = outerCorner / outer, innerInset = innerCorner / inner;
        var geometry = new StreamGeometry();
        using (var context = geometry.Open())
        {
            context.BeginFigure(Polar(inner + innerCorner, start), true, true);
            context.LineTo(Polar(outer - outerCorner, start), true, false);
            context.QuadraticBezierTo(Polar(outer, start), Polar(outer, start + outerInset), true, false);
            context.ArcTo(Polar(outer, end - outerInset), new Size(outer, outer), 0,
                end - start - 2 * outerInset > Math.PI, SweepDirection.Clockwise, true, false);
            context.QuadraticBezierTo(Polar(outer, end), Polar(outer - outerCorner, end), true, false);
            context.LineTo(Polar(inner + innerCorner, end), true, false);
            context.QuadraticBezierTo(Polar(inner, end), Polar(inner, end - innerInset), true, false);
            context.ArcTo(Polar(inner, start + innerInset), new Size(inner, inner), 0,
                end - start - 2 * innerInset > Math.PI, SweepDirection.Counterclockwise, true, false);
            context.QuadraticBezierTo(Polar(inner, start), Polar(inner + innerCorner, start), true, false);
        }
        geometry.Freeze();
        return geometry;
    }

    private void Clear(Ring ring)
    {
        foreach (var shape in ring.Petals)
            canvas.Children.Remove(shape);
        foreach (var label in ring.Labels)
            canvas.Children.Remove(label);
        foreach (var sidewall in ring.Sidewalls)
            canvas.Children.Remove(sidewall);
        ring.Petals.Clear();
        ring.Labels.Clear();
        ring.Sidewalls.Clear();
        ring.Highlighted = -1;
    }

    private static string? GetOperationIcon(string id)
    {
        string key = id.StartsWith("action:") ? id["action:".Length..] : id;
        return key switch
        {
            // Actions
            "float" => "📌",
            "copy" => "📋",
            "move" => "📁",
            "copyPath" => "📋",
            "terminal" or "openTerminal" => "💻",
            "share" => "🔗",
            "metadata" or "stripExif" => "🛡",
            "airDrop" => "📤",
            "reveal" => "📁",
            "copyImage" => "🖼",
            "vscode" => "📝",
            "properties" => "ℹ",
            "trash" => "🗑",
            "openWith" => "↗",
            "uploadDrop" => "☁",
            "hash" => "#",
            "archive" => "📦",
            "unarchive" => "📤",
            "email" => "✉",

            // Image Tools
            "compress" => "🗜️",
            "resizeImage" => "⤢",
            "cropImage" => "✂",
            "editImage" => "🎛",
            "frameImage" => "🔲",
            "watermark" => "💬",
            "redactImage" => "👁‍🗨",
            "ocrImage" => "📄",
            "annotateImage" => "✏",
            "makeIcon" => "🖼",
            "removeMetadata" => "🛡",
            "rotateImage" => "↻",
            "location" => "📍",
            "createCollage" => "▦",
            "createAnimation" => "🎞",

            // Audio Tools
            "trimAudio" => "✂",
            "compressAudio" => "🗜️",
            "normalizeAudio" => "🔊",
            "splitAudio" => "⫽",
            "audioChannels" => "🎚",
            "changeAudioSpeed" => "⏩",
            "reverseAudio" => "⏪",
            "audioEffects" => "🎛",
            "joinAudio" => "🔗",
            "ringtone" => "🔔",
            "subtitlesAudio" => "💬",

            // Video Tools
            "trimVideo" => "✂",
            "compressVideo" => "🗜️",
            "cropVideo" => "✂",
            "muteVideo" => "🔇",
            "videoToGif" => "🎞",
            "extractFrames" => "📷",
            "extractAudio" => "🎵",
            "changeVideoSpeed" => "⏩",
            "splitVideo" => "⫽",
            "videoSettings" => "⚙",
            "videoEffects" => "✨",
            "joinVideos" => "🔗",
            "rotateVideo" => "↻",
            "redactVideo" => "👁‍🗨",
            "editVideo" => "🎬",

            // PDF Tools
            "createPDF" => "📄",
            "mergePdf" or "officeMergePDF" or "mergePDF" => "📑",
            "splitPdf" or "splitPDF" => "⫽",
            "compressPdf" => "🗜️",
            "protectPdf" or "pdfPassword" => "🔒",
            "unlockPdf" => "🔓",
            "pdfToImages" or "extractPdfImages" => "🖼",
            "imagesToPdf" => "📄",
            "watermarkPdf" => "💬",
            "pageNumbersPdf" or "pdfNumbers" => "🔢",
            "rotatePdf" => "↻",
            "ocrPdf" or "ocrPDF" => "📄",
            "redactPDF" => "👁‍🗨",
            "organizePDF" => "📑",
            "officePdf" => "📤",

            // Archives
            "packArchive" => "📦",
            "extractArchive" => "📤",

            _ => null
        };
    }

    // One petal with its label. labelCounterRotDeg counter-rotates the label so text stays upright during wheel rotation.
    private void AddPetal(Ring ring, double start, double end, double inner, double outer, double labelRadius, double labelWidth, string title, string? preview, double titleSize, Brush face, int layer, double labelCounterRotDeg = 0, string? id = null)
    {
        var geometry = Keycap(start, end, inner, outer);
        var sidewall = new ShapePath { Data = geometry, Fill = RestingSide, IsHitTestVisible = false,
            RenderTransform = new TranslateTransform(0, 4),
            Effect = new DropShadowEffect { BlurRadius = 6, ShadowDepth = 2, Opacity = .09, Color = Color.FromRgb(42, 50, 45) } };
        Canvas.SetZIndex(sidewall, layer); ring.Sidewalls.Add(sidewall); canvas.Children.Add(sidewall);
        var shape = new ShapePath { Data = geometry, Fill = face, Stroke = RestingOutline, StrokeThickness = .7 };
        Canvas.SetZIndex(shape, layer + 1);
        ring.Petals.Add(shape);
        canvas.Children.Add(shape);

        var label = new StackPanel { Width = labelWidth, IsHitTestVisible = false };
        string? icon = id != null ? GetOperationIcon(id) : null;
        if (!string.IsNullOrEmpty(icon))
        {
            label.Children.Add(new TextBlock
            {
                Text = icon,
                FontFamily = UiTheme.Font,
                Foreground = UiTheme.Ink,
                FontSize = groups != null ? 12 : 14,
                HorizontalAlignment = HorizontalAlignment.Center,
                Margin = new Thickness(0, 0, 0, 1)
            });
        }
        label.Children.Add(new TextBlock
        {
            Text = title,
            FontFamily = UiTheme.Font,
            Foreground = UiTheme.Ink,
            FontSize = titleSize,
            FontWeight = FontWeights.Medium,
            TextAlignment = TextAlignment.Center,
            TextWrapping = TextWrapping.Wrap
        });
        if (preview != null)
            label.Children.Add(new TextBlock { Text = preview, FontFamily = UiTheme.Font, Foreground = UiTheme.Muted, FontSize = 9, TextAlignment = TextAlignment.Center, TextWrapping = TextWrapping.Wrap, TextTrimming = TextTrimming.CharacterEllipsis, MaxHeight = 26, Margin = new Thickness(0, 2, 0, 0) });
        label.Measure(new Size(labelWidth, double.PositiveInfinity));
        Point p = Polar(labelRadius, (start + end) / 2);
        // Apply counter-rotation so the label text stays upright when the ring rotates.
        if (labelCounterRotDeg != 0)
        {
            label.RenderTransformOrigin = new System.Windows.Point(0.5, 0.5);
            label.RenderTransform = new RotateTransform(labelCounterRotDeg);
        }
        Canvas.SetLeft(label, p.X - labelWidth / 2);
        Canvas.SetTop(label, p.Y - label.DesiredSize.Height / 2);
        Canvas.SetZIndex(label, layer + 2);
        ring.Labels.Add(label);
        canvas.Children.Add(label);
    }

    private void Render(List<Operation> actions, double rotationDeg = 0)
    {
        Clear(first);
        double rotRad = rotationDeg * Math.PI / 180.0;
        for (int i = 0; i < actions.Count; i++)
        {
            double angle = rotRad + (-Math.PI / 2 + i * 2 * Math.PI / actions.Count), half = Math.PI / actions.Count;
            double labelWidth = Math.Clamp(2 * 119 * Math.Sin(half) - 16, 72, groups != null ? 92 : 112);
            string? preview = groups != null ? Preview(groups[i]) : null;
            AddPetal(first, angle - half + .016, angle + half - .016, Inner, Outer, 119, labelWidth, (actions[i].Recent ? "↻ " : "") + actions[i].Label, preview, groups != null ? 13 : actions.Count > 7 ? 11.5 : 13.5, RestingFace, 1, -rotationDeg, actions[i].Id);
        }
        UpdateLayout();
    }

    private static string Preview(ToolGroup group) => string.Join(" · ", group.Items.Take(2).Select(o => o.Label)) + (group.Items.Count > 2 ? " …" : "");

    // The second wheel: the tools of one category, fanned out around the first wheel on the side of that category.
    private void OpenGroup(int index)
    {
        if (groups == null || index == openGroup)
            return;
        openGroup = index;
        RenderSecond(groups[index]);
        for (int i = 0; i < first.Petals.Count; i++)
            Paint(first, i, i == index ? OpenFace : RestingFace, i == index ? OpenSide : RestingSide, i == index ? OpenOutline : RestingOutline, UiTheme.Ink);
        hint.Text = L.T("Pick a tool, then release");
    }

    private void RenderSecond(ToolGroup? group)
    {
        Clear(second);
        if (group == null || groups == null)
            return;
        int groupIndex = groups.IndexOf(group), n = group.Items.Count;
        double direction = -Math.PI / 2 + groupIndex * 2 * Math.PI / groups.Count;
        double width = Math.Min(Math.PI * 2 * .92 / n, 32 * Math.PI / 180), total = width * n;
        for (int i = 0; i < n; i++)
        {
            double middle = direction - total / 2 + width * (i + .5), half = width / 2;
            double labelWidth = Math.Clamp(2 * 242 * Math.Sin(half) - 16, 70, 104);
            AddPetal(second, middle - half + .018, middle + half - .018, OuterRingInner, OuterRingOuter, 242, labelWidth, group.Items[i].Label, null, 12, OuterFace, 20, 0, group.Items[i].Id);
        }
        UpdateLayout();
    }

    private static int Hit(Ring ring, Point point, double inner, double outer)
    {
        double distance = (point - new Point(Center, Center)).Length;
        if (distance <= inner || distance > outer)
            return -1;
        for (int i = 0; i < ring.Petals.Count; i++)
            if (ring.Petals[i].Data.FillContains(point))
                return i;
        return -1;
    }

    private static void Paint(Ring ring, int index, Brush face, Brush side, Brush outline, Brush text)
    {
        ring.Petals[index].Fill = face;
        ring.Petals[index].Stroke = outline;
        ring.Sidewalls[index].Fill = side;
        var blocks = ((StackPanel)ring.Labels[index]).Children.OfType<TextBlock>().ToList();
        bool white = text == Brushes.White;
        for (int i = 0; i < blocks.Count; i++)
        {
            if (white)
                blocks[i].Foreground = Brushes.White;
            else
                blocks[i].Foreground = i == blocks.Count - 1 && blocks.Count > 2 ? UiTheme.Muted : text;
        }
    }

    private void Highlight(Ring ring, int index)
    {
        if (index == ring.Highlighted)
            return;
        if (index >= 0)
            SoundManager.PlayTick();
        ring.Highlighted = index;
        for (int i = 0; i < ring.Petals.Count; i++)
        {
            bool selected = i == index;
            bool openCategory = ring == first && groups != null && i == openGroup;
            Brush face = selected ? SelectedFace : openCategory ? OpenFace : ring == second ? OuterFace : RestingFace;
            Paint(ring, i, face, selected ? SelectedSide : openCategory ? OpenSide : RestingSide, selected ? SelectedFace : openCategory ? OpenOutline : RestingOutline, selected ? Brushes.White : UiTheme.Ink);
        }
        UpdateHub();
        if (ring == second && index >= 0 && openGroup >= 0)
            hint.Text = groups![openGroup].Items[index].Label;
        else if (ring == first)
            hint.Text = index >= 0 ? operations[index].Label : Catalog.PackingOnly(paths) ? L.T("No conversions for this type") : Prompt();
        else if (openGroup >= 0)
            hint.Text = groups![openGroup].Label;
    }

    private static string TruncateMiddle(string text, int maxLen = 14)
    {
        if (string.IsNullOrEmpty(text) || text.Length <= maxLen) return text;
        int keep = Math.Max(2, (maxLen - 3) / 2);
        return text[..keep] + "…" + text[^keep..];
    }

    private static ImageSource? GetThumbnail(string path)
    {
        try
        {
            if (!System.IO.File.Exists(path)) return null;
            string ext = System.IO.Path.GetExtension(path).TrimStart('.').ToLowerInvariant();
            if (Catalog.Images.Contains(ext))
            {
                var bmp = new BitmapImage();
                bmp.BeginInit();
                bmp.UriSource = new Uri(path);
                bmp.DecodePixelWidth = 56;
                bmp.CacheOption = BitmapCacheOption.OnLoad;
                bmp.EndInit();
                bmp.Freeze();
                return bmp;
            }
            using var sysIcon = System.Drawing.Icon.ExtractAssociatedIcon(path);
            if (sysIcon != null)
            {
                var bs = Imaging.CreateBitmapSourceFromHIcon(
                    sysIcon.Handle,
                    Int32Rect.Empty,
                    BitmapSizeOptions.FromEmptyOptions());
                bs.Freeze();
                return bs;
            }
        }
        catch
        {
            // Ignore fallback
        }
        return null;
    }
}
