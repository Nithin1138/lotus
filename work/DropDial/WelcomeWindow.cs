using System;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace DropDial;

// DropDial has no main window, so this is the first thing a person sees after installing it: what it does and
// where it lives. It opens when DropDial starts, and again whenever DropDial is launched while already running.
internal sealed class WelcomeWindow : Window
{
    public const string HideAtStartKey = "hideWelcome";
    private CheckBox? startup;
    private TextBlock? startupMessage;
    private Button? startupSettings;

    public WelcomeWindow()
    {
        UiTheme.Apply(this);
        Width = 600;
        SizeToContent = SizeToContent.Height;
        ResizeMode = ResizeMode.CanMinimize;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Title = "DropDial";
        // Re-read every label if the language changes while the window is open (from the buttons below or the tray menu).
        L.Changed += Rebuild;
        StartupManager.Changed += RefreshStartup;
        LicenseManager.StatusChanged += Rebuild;
        Closed += (_, _) => L.Changed -= Rebuild;
        Closed += (_, _) => StartupManager.Changed -= RefreshStartup;
        Closed += (_, _) => LicenseManager.StatusChanged -= Rebuild;
        Rebuild();
    }

    private void Rebuild() => Content = UiTheme.Frame(this, Body(), "DropDial");

    private UIElement Body()
    {
        var panel = new StackPanel { Margin = new Thickness(32, 4, 32, 26) };

        var heading = new StackPanel { Orientation = Orientation.Horizontal };
        heading.Children.Add(new Image { Source = AppIcon.Window, Width = 52, Height = 52, Margin = new Thickness(0, 0, 16, 0) });
        var titles = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        titles.Children.Add(new TextBlock { Text = L.T("Welcome to DropDial"), FontSize = 24, FontWeight = FontWeights.Bold, Foreground = UiTheme.Ink });
        titles.Children.Add(new TextBlock { Text = L.T("Drag. Drop. Convert."), FontSize = 14, Foreground = UiTheme.Muted, Margin = new Thickness(0, 2, 0, 0) });
        heading.Children.Add(titles);
        panel.Children.Add(heading);

        var steps = new StackPanel { Margin = new Thickness(0, 24, 0, 0) };
        steps.Children.Add(Step(1, L.T("Drag files"), L.T("Select one or more files on the desktop or in File Explorer and start dragging them, as if you were moving them.")));
        steps.Children.Add(Step(2, L.T("Press Shift"), L.T("While dragging, press Shift for formats, Ctrl+Shift for tools, or Alt for actions (Floating Shelf, Copy, Move, Terminal). F8, F9, and F10 also work.")));
        steps.Children.Add(Step(3, L.T("Release on an option"), L.T("The new file is saved next to the original, which is never changed.")));
        panel.Children.Add(steps);

        var tray = new StackPanel();
        tray.Children.Add(new TextBlock { Text = L.T("DropDial runs in the notification area (next to the clock) and has no main window. Right-click its icon to pause or cancel jobs, change the language or quit. Can't see the icon? Click the ^ arrow on the taskbar."), TextWrapping = TextWrapping.Wrap, Foreground = UiTheme.Ink, LineHeight = 20 });
        tray.Children.Add(new TextBlock { Text = L.T("Everything is processed on this PC. Nothing is uploaded, and DropDial never connects to the internet."), TextWrapping = TextWrapping.Wrap, Foreground = UiTheme.Muted, FontSize = 12, Margin = new Thickness(0, 8, 0, 0) });
        var card = UiTheme.Card(tray, new Thickness(18, 14, 18, 14));
        card.Margin = new Thickness(0, 6, 0, 0);
        panel.Children.Add(card);

        var licStatus = LicenseManager.CurrentStatus;
        var licRow = new DockPanel();
        var licBtn = new Button
        {
            Content = licStatus.IsPro ? L.T("Manage License…") : (LicenseManager.IsWithinFirst24Hours ? "⚡ Claim 10% Off" : L.T("Enter License Key…")),
            Padding = new Thickness(14, 6, 14, 6),
            Margin = new Thickness(12, 0, 0, 0),
            FontWeight = FontWeights.SemiBold,
            Foreground = licStatus.IsPro ? UiTheme.Ink : Brushes.White,
            Background = licStatus.IsPro ? UiTheme.Shade : UiTheme.Accent,
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
                LicenseWindow.ShowDialogOrActivate();
            }
        };
        DockPanel.SetDock(licBtn, Dock.Right);
        licRow.Children.Add(licBtn);

        var licTextPanel = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        string licTitleText = licStatus.IsPro
            ? $"DropDial {licStatus.Info?.PlanDisplayName ?? "Pro"} Plan ✓"
            : (licStatus.Kind == LicenseStatusKind.Trial
                ? (LicenseManager.IsWithinFirst24Hours
                    ? $"Free Trial ({licStatus.DaysRemaining}d) · ⚡ 10% Off Early Bird"
                    : $"Free Trial ({licStatus.DaysRemaining} days left)")
                : "Free Tier (Trial Expired)");
        string licSubText = licStatus.IsPro
            ? $"Licensed to {(string.IsNullOrEmpty(licStatus.Info?.Name) ? licStatus.Info?.Email : licStatus.Info?.Name)}"
            : (LicenseManager.IsWithinFirst24Hours
                ? L.T("First 24 Hours Offer: Save 10% on Lifetime Pro with coupon FIRST24.")
                : L.T("Activate your license key to unlock unlimited conversions."));
        licTextPanel.Children.Add(new TextBlock { Text = licTitleText, FontWeight = FontWeights.SemiBold, FontSize = 14, Foreground = UiTheme.Ink });
        licTextPanel.Children.Add(new TextBlock { Text = licSubText, Foreground = UiTheme.Muted, FontSize = 12, Margin = new Thickness(0, 2, 0, 0) });
        licRow.Children.Add(licTextPanel);

        var licCard = UiTheme.Card(licRow, new Thickness(18, 12, 18, 12));
        licCard.Margin = new Thickness(0, 10, 0, 0);
        panel.Children.Add(licCard);

        panel.Children.Add(LayoutChoice());

        var hide = new CheckBox { Content = L.T("Don't show this window when DropDial starts"), IsChecked = Settings.GetBool(HideAtStartKey, false), Margin = new Thickness(0, 18, 0, 0), Foreground = UiTheme.Muted };
        hide.Click += (_, _) => Settings.Set(HideAtStartKey, hide.IsChecked == true);
        panel.Children.Add(hide);
        startup = new CheckBox { Content = L.T("Start with Windows"), IsEnabled = false, Margin = new Thickness(0, 6, 0, 0), ToolTip = L.T("Run quietly in the background after signing in to Windows.") };
        startupMessage = new TextBlock { Foreground = UiTheme.Muted, FontSize = 11, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(6, 3, 0, 0) };
        startupSettings = new Button { Content = L.T("Windows startup app settings"), Visibility = Visibility.Collapsed, HorizontalAlignment = HorizontalAlignment.Left, Margin = new Thickness(6, 5, 0, 0) };
        startupSettings.Click += (_, _) => StartupManager.OpenWindowsSettings();
        startup.Click += async (_, _) =>
        {
            startup.IsEnabled = false;
            var status = await StartupManager.SetAsync(startup.IsChecked == true);
            UpdateStartup(status);
        };
        panel.Children.Add(startup); panel.Children.Add(startupMessage); panel.Children.Add(startupSettings);
        RefreshStartup();

        var footer = new DockPanel { Margin = new Thickness(0, 14, 0, 0) };
        var close = new Button { Content = L.T("Got it"), Background = UiTheme.Accent, Foreground = Brushes.White, BorderBrush = UiTheme.Accent, Padding = new Thickness(26, 9, 26, 9), IsDefault = true, IsCancel = true };
        close.Click += (_, _) => Close();
        DockPanel.SetDock(close, Dock.Right);
        footer.Children.Add(close);
        var languages = new StackPanel { Orientation = Orientation.Horizontal };
        // Language names are always shown in their own language so either one can be found.
        foreach (var (code, name) in new[] { ("en", "English"), ("zh", "English") })
        {
            bool current = L.Language == code;
            var button = new Button { Content = name, Margin = new Thickness(0, 0, 8, 0), FontWeight = current ? FontWeights.SemiBold : FontWeights.Normal, BorderBrush = current ? UiTheme.Accent : UiTheme.Line };
            button.Click += (_, _) => L.Language = code;
            languages.Children.Add(button);
        }
        footer.Children.Add(languages);
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
        var section = new StackPanel { Margin = new Thickness(0, 18, 0, 0) };
        section.Children.Add(new TextBlock { Text = L.T("Wheel with many tools"), FontWeight = FontWeights.SemiBold, FontSize = 15, Foreground = UiTheme.Ink });
        section.Children.Add(new TextBlock { Text = L.T("Used when a single picture or video has many tools. You can change it anytime from the tray menu."), TextWrapping = TextWrapping.Wrap, Foreground = UiTheme.Muted, Margin = new Thickness(0, 2, 0, 8) });
        var choices = new Grid();
        choices.ColumnDefinitions.Add(new ColumnDefinition());
        choices.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(12) });
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
        var words = new StackPanel { Margin = new Thickness(12, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center };
        words.Children.Add(new TextBlock { Text = (chosen ? "✓ " : "") + title, FontWeight = FontWeights.SemiBold, Foreground = chosen ? UiTheme.Accent : UiTheme.Ink });
        words.Children.Add(new TextBlock { Text = text, TextWrapping = TextWrapping.Wrap, Foreground = UiTheme.Muted, FontSize = 12, Margin = new Thickness(0, 2, 0, 0) });
        row.Children.Add(words);
        var button = new Button { Content = row, HorizontalContentAlignment = HorizontalAlignment.Stretch, Padding = new Thickness(12, 10, 12, 10) };
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
        var canvas = new System.Windows.Controls.Canvas { Width = twoWheels ? 84 : 52, Height = 52 };
        AddWheel(canvas, 26, 26, 25, twoWheels ? 5 : 8, twoWheels ? 1 : -1);
        if (twoWheels)
        {
            canvas.Children.Add(new TextBlock { Text = "›", FontSize = 16, Foreground = UiTheme.Muted, Margin = new Thickness(53, 13, 0, 0) });
            AddWheel(canvas, 72, 26, 12, 4, -1);
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
        var row = new Grid { Margin = new Thickness(0, 0, 0, 14) };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(44) });
        row.ColumnDefinitions.Add(new ColumnDefinition());
        var badge = new Border { Width = 30, Height = 30, CornerRadius = new CornerRadius(15), Background = UiTheme.Tint, VerticalAlignment = VerticalAlignment.Top, HorizontalAlignment = HorizontalAlignment.Left };
        badge.Child = new TextBlock { Text = number.ToString(), FontWeight = FontWeights.Bold, Foreground = UiTheme.Accent, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        row.Children.Add(badge);
        var words = new StackPanel();
        words.Children.Add(new TextBlock { Text = title, FontWeight = FontWeights.SemiBold, FontSize = 15, Foreground = UiTheme.Ink });
        words.Children.Add(new TextBlock { Text = text, TextWrapping = TextWrapping.Wrap, Foreground = UiTheme.Muted, Margin = new Thickness(0, 2, 0, 0), LineHeight = 20 });
        Grid.SetColumn(words, 1);
        row.Children.Add(words);
        return row;
    }
}
