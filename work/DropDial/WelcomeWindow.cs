using System;
using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;

namespace DropDial;

// DropDial has no main window, so this is the first thing a person sees after installing it: what it does and
// where it lives. It opens when DropDial starts, and again whenever DropDial is launched while already running.
internal sealed class WelcomeWindow : Window
{
    public const string HideAtStartKey = "hideWelcome";
    public static Action? ToggleWheelAction;
    public static Action<WheelMode?>? ToggleModeAction;
    public static Action? PromptSelectFilesAction;
    public static Action? ShowShelfAction;
    public static Action? ShowLicenseAction;
    private CheckBox? startup;
    private TextBlock? startupMessage;
    private Button? startupSettings;

    public WelcomeWindow()
    {
        UiTheme.Apply(this);
        Width = 530;
        MaxHeight = Math.Max(500, SystemParameters.WorkArea.Height - 50);
        SizeToContent = SizeToContent.Height;
        ResizeMode = ResizeMode.CanMinimize;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Title = "DropDial";
        PreviewKeyDown += (_, e) =>
        {
            if ((e.Key == Key.Space || e.SystemKey == Key.Space) && (Keyboard.Modifiers & ModifierKeys.Alt) != 0)
            {
                e.Handled = true;
                WindowState = WindowState.Minimized;
                ToggleWheelAction?.Invoke();
            }
            else if (e.Key == Key.F8)
            {
                e.Handled = true;
                WindowState = WindowState.Minimized;
                ToggleModeAction?.Invoke(WheelMode.Convert);
            }
            else if (e.Key == Key.F9)
            {
                e.Handled = true;
                WindowState = WindowState.Minimized;
                ToggleModeAction?.Invoke(WheelMode.Tools);
            }
            else if (e.Key == Key.F10)
            {
                e.Handled = true;
                WindowState = WindowState.Minimized;
                ToggleModeAction?.Invoke(WheelMode.Actions);
            }
        };
        // Re-read every label if the language changes while the window is open (from the tray menu).
        L.Changed += Rebuild;
        StartupManager.Changed += RefreshStartup;
        LicenseManager.StatusChanged += Rebuild;
        UpdateManager.UpdateStatusChanged += OnUpdateStatusChanged;
        Closed += (_, _) => L.Changed -= Rebuild;
        Closed += (_, _) => StartupManager.Changed -= RefreshStartup;
        Closed += (_, _) => LicenseManager.StatusChanged -= Rebuild;
        Closed += (_, _) => UpdateManager.UpdateStatusChanged -= OnUpdateStatusChanged;
        Rebuild();
    }

    private void OnUpdateStatusChanged()
    {
        Dispatcher.InvokeAsync(Rebuild);
    }

    private void Rebuild()
    {
        var scroll = new ScrollViewer
        {
            Content = Body(),
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
            Focusable = false
        };
        Content = UiTheme.Frame(this, scroll, "DropDial");
    }

    private UIElement Body()
    {
        var panel = new StackPanel { Margin = new Thickness(20, 2, 20, 12) };

        if (UpdateManager.AvailableUpdate is { } upd)
        {
            var updateCard = new Border
            {
                Background = UiTheme.Tint,
                BorderBrush = UiTheme.Accent,
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(6),
                Padding = new Thickness(10, 5, 10, 5),
                Margin = new Thickness(0, 0, 0, 9)
            };
            var updateRow = new DockPanel();
            var updateBtn = new Button
            {
                Content = L.T("Update Now"),
                Padding = new Thickness(10, 3, 10, 3),
                FontSize = 11,
                FontWeight = FontWeights.SemiBold,
                Foreground = Brushes.White,
                Background = UiTheme.Accent,
                BorderBrush = UiTheme.Accent,
                Cursor = Cursors.Hand,
                VerticalAlignment = VerticalAlignment.Center
            };
            DockPanel.SetDock(updateBtn, Dock.Right);
            updateBtn.Click += (_, _) => UpdateManager.ShowUpdatePrompt(upd);
            updateRow.Children.Add(updateBtn);
            var updateText = new TextBlock
            {
                Text = $"✨ {L.T("New version available:")} {upd.TagName}",
                FontWeight = FontWeights.SemiBold,
                FontSize = 11.5,
                Foreground = UiTheme.Ink,
                VerticalAlignment = VerticalAlignment.Center
            };
            updateRow.Children.Add(updateText);
            updateCard.Child = updateRow;
            panel.Children.Add(updateCard);
        }

        var heading = new StackPanel { Orientation = Orientation.Horizontal };
        heading.Children.Add(new Image { Source = AppIcon.Window, Width = 32, Height = 32, Margin = new Thickness(0, 0, 10, 0) });
        var titles = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        titles.Children.Add(new TextBlock { Text = L.T("Welcome to DropDial"), FontSize = 17, FontWeight = FontWeights.Bold, Foreground = UiTheme.Ink });
        titles.Children.Add(new TextBlock { Text = L.T("Drag. Drop. Convert."), FontSize = 11.5, Foreground = UiTheme.Muted, Margin = new Thickness(0, 1, 0, 0) });
        heading.Children.Add(titles);
        panel.Children.Add(heading);

        var steps = new StackPanel { Margin = new Thickness(0, 9, 0, 0) };
        steps.Children.Add(Step(1, L.T("Drag files"), L.T("Select one or more files on the desktop or in File Explorer and start dragging them, as if you were moving them.")));
        steps.Children.Add(Step(2, L.T("Press Shift"), L.T("While dragging, press Shift for formats, Ctrl+Shift for tools, or Alt for actions (Floating Shelf, Copy, Move, Terminal). F8, F9, and F10 also work.")));
        steps.Children.Add(Step(3, L.T("Release on an option"), L.T("The new file is saved next to the original, which is never changed.")));
        panel.Children.Add(steps);

        var launchRow = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 8, 0, 6) };

        var openWheelBtn = new Button
        {
            Content = L.T("Open Floating Wheel"),
            Padding = new Thickness(12, 5, 12, 5),
            Margin = new Thickness(0, 0, 6, 0),
            FontSize = 12,
            FontWeight = FontWeights.SemiBold,
            Foreground = Brushes.White,
            Background = UiTheme.Accent,
            BorderBrush = UiTheme.Accent,
            Cursor = Cursors.Hand
        };
        openWheelBtn.Click += (_, _) =>
        {
            WindowState = WindowState.Minimized;
            ToggleWheelAction?.Invoke();
        };
        launchRow.Children.Add(openWheelBtn);

        var openShelfBtn = new Button
        {
            Content = L.T("Open Floating Shelf"),
            Padding = new Thickness(10, 5, 10, 5),
            Margin = new Thickness(0, 0, 6, 0),
            FontSize = 12,
            FontWeight = FontWeights.Normal,
            Foreground = UiTheme.Ink,
            Background = UiTheme.Surface,
            BorderBrush = UiTheme.Line,
            Cursor = Cursors.Hand
        };
        openShelfBtn.Click += (_, _) =>
        {
            ShowShelfAction?.Invoke();
        };
        launchRow.Children.Add(openShelfBtn);

        var selectFilesBtn = new Button
        {
            Content = L.T("Choose Files…"),
            Padding = new Thickness(10, 5, 10, 5),
            FontSize = 12,
            FontWeight = FontWeights.Normal,
            Foreground = UiTheme.Ink,
            Background = UiTheme.Surface,
            BorderBrush = UiTheme.Line,
            Cursor = Cursors.Hand
        };
        selectFilesBtn.Click += (_, _) =>
        {
            PromptSelectFilesAction?.Invoke();
        };
        launchRow.Children.Add(selectFilesBtn);

        panel.Children.Add(launchRow);

        var tray = new StackPanel();
        tray.Children.Add(new TextBlock { Text = L.T("DropDial runs in the notification area (next to the clock) and has no main window. Click or right-click its tray icon to toggle the wheel, pause jobs, or change settings."), TextWrapping = TextWrapping.Wrap, Foreground = UiTheme.Ink, FontSize = 11, LineHeight = 15 });
        tray.Children.Add(new TextBlock { Text = L.T("Everything is processed on this PC. Nothing is uploaded, and DropDial never connects to the internet."), TextWrapping = TextWrapping.Wrap, Foreground = UiTheme.Muted, FontSize = 10.5, Margin = new Thickness(0, 3, 0, 0) });
        var card = UiTheme.Card(tray, new Thickness(12, 6, 12, 6));
        card.Margin = new Thickness(0, 4, 0, 0);
        panel.Children.Add(card);

        var licStatus = LicenseManager.CurrentStatus;
        var licRow = new DockPanel();
        var licBtn = new Button
        {
            Content = licStatus.IsPro ? L.T("Manage License…") : (LicenseManager.IsWithinFirst24Hours ? L.T("Claim 10% Off") : L.T("Enter License Key…")),
            Padding = new Thickness(10, 4, 10, 4),
            Margin = new Thickness(8, 0, 0, 0),
            FontSize = 11,
            FontWeight = FontWeights.SemiBold,
            Foreground = licStatus.IsPro ? UiTheme.Ink : Brushes.White,
            Background = licStatus.IsPro ? UiTheme.Surface : UiTheme.Accent,
            BorderBrush = licStatus.IsPro ? UiTheme.Line : UiTheme.Accent,
            VerticalAlignment = VerticalAlignment.Center
        };
        licBtn.Click += (_, _) =>
        {
            if (!licStatus.IsPro && LicenseManager.IsWithinFirst24Hours)
            {
                try { Process.Start(new ProcessStartInfo(LicenseManager.EarlyBirdBuyUrl) { UseShellExecute = true }); } catch { }
            }
            else
            {
                ShowLicenseAction?.Invoke();
            }
        };
        DockPanel.SetDock(licBtn, Dock.Right);
        licRow.Children.Add(licBtn);

        var licTextPanel = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        string licTitleText = licStatus.IsPro
            ? $"DropDial {licStatus.Info?.PlanDisplayName ?? "Pro"} Plan ✓"
            : (licStatus.Kind == LicenseStatusKind.Trial
                ? (LicenseManager.IsWithinFirst24Hours
                    ? $"Free Trial ({licStatus.DaysRemaining}d) · 10% Off Early Bird"
                    : $"Free Trial ({licStatus.DaysRemaining} days left)")
                : "Free Tier (Trial Expired)");
        string licSubText = licStatus.IsPro
            ? $"Licensed to {(string.IsNullOrEmpty(licStatus.Info?.Name) ? licStatus.Info?.Email : licStatus.Info?.Name)}"
            : (LicenseManager.IsWithinFirst24Hours
                ? L.T("First 24 Hours Offer: Save 10% on Lifetime Pro with coupon FIRST24.")
                : L.T("Activate your license key to unlock unlimited conversions."));
        licTextPanel.Children.Add(new TextBlock { Text = licTitleText, FontWeight = FontWeights.SemiBold, FontSize = 12, Foreground = UiTheme.Ink });
        licTextPanel.Children.Add(new TextBlock { Text = licSubText, Foreground = UiTheme.Muted, FontSize = 10.5, Margin = new Thickness(0, 1, 0, 0) });
        licRow.Children.Add(licTextPanel);

        var licCard = UiTheme.Card(licRow, new Thickness(12, 6, 12, 6));
        licCard.Margin = new Thickness(0, 5, 0, 0);
        panel.Children.Add(licCard);

        panel.Children.Add(LayoutChoice());

        var hide = new CheckBox { Content = L.T("Don't show this window when DropDial starts"), IsChecked = Settings.GetBool(HideAtStartKey, false), Margin = new Thickness(0, 6, 0, 0), FontSize = 11, Foreground = UiTheme.Muted };
        hide.Click += (_, _) => Settings.Set(HideAtStartKey, hide.IsChecked == true);
        panel.Children.Add(hide);
        startup = new CheckBox { Content = L.T("Start with Windows"), IsEnabled = false, Margin = new Thickness(0, 2, 0, 0), FontSize = 11, ToolTip = L.T("Run quietly in the background after signing in to Windows.") };
        startupMessage = new TextBlock { Foreground = UiTheme.Muted, FontSize = 10, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(6, 1, 0, 0) };
        startupSettings = new Button { Content = L.T("Windows startup app settings"), Visibility = Visibility.Collapsed, HorizontalAlignment = HorizontalAlignment.Left, FontSize = 10, Margin = new Thickness(6, 2, 0, 0) };
        startupSettings.Click += (_, _) => StartupManager.OpenWindowsSettings();
        startup.Click += async (_, _) =>
        {
            startup.IsEnabled = false;
            var status = await StartupManager.SetAsync(startup.IsChecked == true);
            UpdateStartup(status);
        };
        panel.Children.Add(startup); panel.Children.Add(startupMessage); panel.Children.Add(startupSettings);
        RefreshStartup();

        var footer = new DockPanel { Margin = new Thickness(0, 8, 0, 0) };
        var close = new Button { Content = L.T("Got it"), Background = UiTheme.Accent, Foreground = Brushes.White, BorderBrush = UiTheme.Accent, Padding = new Thickness(20, 5, 20, 5), FontSize = 12, FontWeight = FontWeights.SemiBold, IsDefault = true, IsCancel = true };
        close.Click += (_, _) => Close();
        DockPanel.SetDock(close, Dock.Right);
        footer.Children.Add(close);
        panel.Children.Add(footer);
        return panel;
    }
    private async void RefreshStartup() => UpdateStartup(await StartupManager.GetAsync());
    private void UpdateStartup(StartupStatus status)
    {
        if (startup == null || startupMessage == null || startupSettings == null) return;
        startup.IsChecked = status.Enabled; startup.IsEnabled = status.CanChange;
        startupMessage.Text = status.Message ?? L.T("Run quietly in the background after signing in to Windows.");
        startupSettings.Visibility = status.Message == null ? Visibility.Collapsed : Visibility.Visible;
    }

    // The two ways a wheel with many tools can look; the same setting as the tray menu's layout item.
    private UIElement LayoutChoice()
    {
        var section = new StackPanel { Margin = new Thickness(0, 6, 0, 0) };
        section.Children.Add(new TextBlock { Text = L.T("Wheel with many tools"), FontWeight = FontWeights.SemiBold, FontSize = 12, Foreground = UiTheme.Ink });
        section.Children.Add(new TextBlock { Text = L.T("Used when a single picture or video has many tools. You can change it anytime from the tray menu."), TextWrapping = TextWrapping.Wrap, Foreground = UiTheme.Muted, FontSize = 10.5, Margin = new Thickness(0, 1, 0, 4) });
        var choices = new Grid();
        choices.ColumnDefinitions.Add(new ColumnDefinition());
        choices.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(8) });
        choices.ColumnDefinitions.Add(new ColumnDefinition());
        var merged = LayoutCard(L.T("Combine related tools"), L.T("Related tools share one window, so one wheel shows everything."), Picture(false), !Catalog.TwoWheels, "merged");
        var twoWheels = LayoutCard(L.T("Two wheels (categories)"), L.T("Pick a category first, then the tool on a second wheel."), Picture(true), Catalog.TwoWheels, "twoWheels");
        Grid.SetColumn(twoWheels, 2);
        choices.Children.Add(merged);
        choices.Children.Add(twoWheels);
        section.Children.Add(choices);
        return section;
    }

    private Button LayoutCard(string title, string text, UIElement picture, bool chosen, string value)
    {
        var row = new DockPanel();
        DockPanel.SetDock(picture, Dock.Left);
        row.Children.Add(picture);
        var words = new StackPanel { Margin = new Thickness(8, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center };
        words.Children.Add(new TextBlock { Text = (chosen ? "✓ " : "") + title, FontWeight = FontWeights.SemiBold, FontSize = 11.5, Foreground = chosen ? UiTheme.Accent : UiTheme.Ink });
        words.Children.Add(new TextBlock { Text = text, TextWrapping = TextWrapping.Wrap, Foreground = UiTheme.Muted, FontSize = 10, Margin = new Thickness(0, 1, 0, 0) });
        row.Children.Add(words);
        var button = new Button { Content = row, HorizontalContentAlignment = HorizontalAlignment.Stretch, Padding = new Thickness(8, 5, 8, 5) };
        if (chosen)
        {
            button.Background = UiTheme.Tint;
            button.BorderBrush = UiTheme.Accent;
        }
        button.Click += (_, _) => { Settings.Set(Catalog.LayoutKey, value); Rebuild(); };
        return button;
    }

    // A small drawing of the layout: one wheel, or a category wheel leading to a second wheel.
    private static UIElement Picture(bool twoWheels)
    {
        var canvas = new System.Windows.Controls.Canvas { Width = twoWheels ? 68 : 42, Height = 42 };
        AddWheel(canvas, 21, 21, 19, twoWheels ? 5 : 8, twoWheels ? 1 : -1);
        if (twoWheels)
        {
            canvas.Children.Add(new TextBlock { Text = "›", FontSize = 13, Foreground = UiTheme.Muted, Margin = new Thickness(43, 11, 0, 0) });
            AddWheel(canvas, 57, 21, 10, 4, -1);
        }
        return canvas;
    }

    private static void AddWheel(System.Windows.Controls.Canvas canvas, double cx, double cy, double radius, int slices, int highlighted)
    {
        double inner = radius * 0.42, gap = 0.09;
        for (int i = 0; i < slices; i++)
        {
            double a0 = 2 * Math.PI * i / slices - Math.PI / 2 + gap, a1 = 2 * Math.PI * (i + 1) / slices - Math.PI / 2 - gap;
            Point P(double r, double a) => new(cx + r * Math.Cos(a), cy + r * Math.Sin(a));
            var figure = new PathFigure { StartPoint = P(inner, a0), IsClosed = true };
            figure.Segments.Add(new LineSegment(P(radius, a0), true));
            figure.Segments.Add(new ArcSegment(P(radius, a1), new Size(radius, radius), 0, false, SweepDirection.Clockwise, true));
            figure.Segments.Add(new LineSegment(P(inner, a1), true));
            figure.Segments.Add(new ArcSegment(P(inner, a0), new Size(inner, inner), 0, false, SweepDirection.Counterclockwise, true));
            canvas.Children.Add(new System.Windows.Shapes.Path
            {
                Data = new PathGeometry([figure]),
                Fill = i == highlighted ? UiTheme.Accent : UiTheme.Line,
            });
        }
    }

    private static UIElement Step(int number, string title, string text)
    {
        var row = new Grid { Margin = new Thickness(0, 0, 0, 5) };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(28) });
        row.ColumnDefinitions.Add(new ColumnDefinition());
        var badge = new Border { Width = 20, Height = 20, CornerRadius = new CornerRadius(10), Background = UiTheme.Tint, VerticalAlignment = VerticalAlignment.Top, HorizontalAlignment = HorizontalAlignment.Left };
        badge.Child = new TextBlock { Text = number.ToString(), FontWeight = FontWeights.Bold, FontSize = 10.5, Foreground = UiTheme.Accent, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        row.Children.Add(badge);
        var words = new StackPanel();
        words.Children.Add(new TextBlock { Text = title, FontWeight = FontWeights.SemiBold, FontSize = 12.5, Foreground = UiTheme.Ink });
        words.Children.Add(new TextBlock { Text = text, TextWrapping = TextWrapping.Wrap, Foreground = UiTheme.Muted, FontSize = 11, Margin = new Thickness(0, 1, 0, 0), LineHeight = 15 });
        Grid.SetColumn(words, 1);
        row.Children.Add(words);
        return row;
    }
}
