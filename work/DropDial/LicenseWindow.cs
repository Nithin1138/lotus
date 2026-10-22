using System;
using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace DropDial;

internal sealed class LicenseWindow : Window
{
    private static LicenseWindow? openInstance;

    private readonly TextBlock titleText;
    private readonly TextBlock statusSubtitle;
    private readonly TextBox keyInput;
    private readonly Button pasteBtn;
    private readonly Button primaryBtn;
    private readonly Button secondaryBtn;
    private readonly Button dismissBtn;
    private readonly TextBlock messageText = new();
    private string? activeReason;

    public static void ShowDialogOrActivate(string? reason = null)
    {
        if (openInstance != null)
        {
            if (!string.IsNullOrEmpty(reason))
            {
                openInstance.activeReason = reason;
                openInstance.UpdateUI();
            }
            openInstance.Activate();
            return;
        }

        var win = new LicenseWindow(reason);
        openInstance = win;
        win.Closed += (_, _) => openInstance = null;
        win.Show();
        win.Activate();
    }

    public LicenseWindow(string? reason = null)
    {
        activeReason = reason;
        UiTheme.Apply(this);
        Width = 440;
        SizeToContent = SizeToContent.Height;
        ResizeMode = ResizeMode.NoResize;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Title = "DropDial Pro";

        var panel = new StackPanel { Margin = new Thickness(36, 24, 36, 24) };

        // 1. App Icon (Centered)
        var iconImg = new Image
        {
            Source = AppIcon.Window,
            Width = 48,
            Height = 48,
            HorizontalAlignment = HorizontalAlignment.Center,
            Margin = new Thickness(0, 0, 0, 10)
        };
        panel.Children.Add(iconImg);

        // 2. Title
        titleText = new TextBlock
        {
            Text = "DropDial Pro",
            FontSize = 18,
            FontWeight = FontWeights.SemiBold,
            Foreground = UiTheme.Ink,
            HorizontalAlignment = HorizontalAlignment.Center
        };
        panel.Children.Add(titleText);

        // 3. Status Subtitle (Clean & subtle, no tacky banners or emojis)
        statusSubtitle = new TextBlock
        {
            FontSize = 12,
            Foreground = UiTheme.Muted,
            HorizontalAlignment = HorizontalAlignment.Center,
            Margin = new Thickness(0, 4, 0, 18),
            TextAlignment = TextAlignment.Center
        };
        panel.Children.Add(statusSubtitle);

        // 4. License Key Input Box (Monospaced) & Paste Button
        var keyRow = new Grid { Margin = new Thickness(0, 0, 0, 6) };
        keyRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        keyRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(8) });
        keyRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(72) });

        keyInput = new TextBox
        {
            Height = 32,
            FontSize = 12,
            FontFamily = new FontFamily("Consolas, Courier New, monospace"),
            VerticalContentAlignment = VerticalAlignment.Center,
            HorizontalContentAlignment = HorizontalAlignment.Left,
            Padding = new Thickness(8, 0, 8, 0),
            Background = UiTheme.Surface,
            Foreground = UiTheme.Ink,
            BorderBrush = UiTheme.Line
        };
        keyInput.KeyDown += (_, e) =>
        {
            if (e.Key == System.Windows.Input.Key.Enter)
            {
                e.Handled = true;
                OnPrimaryClick();
            }
        };
        Grid.SetColumn(keyInput, 0);
        keyRow.Children.Add(keyInput);

        pasteBtn = new Button
        {
            Content = "Paste",
            Height = 32,
            Background = UiTheme.Surface,
            Foreground = UiTheme.Ink,
            BorderBrush = UiTheme.Line,
            ToolTip = "Paste license key from clipboard"
        };
        pasteBtn.Click += (_, _) =>
        {
            try
            {
                var clip = Clipboard.GetText()?.Trim();
                if (!string.IsNullOrEmpty(clip))
                {
                    if (clip.StartsWith("\"") && clip.EndsWith("\"") && clip.Length >= 2)
                        clip = clip[1..^1].Trim();
                    if (clip.StartsWith("dd-", StringComparison.OrdinalIgnoreCase) && !clip.StartsWith("DD-"))
                        clip = "DD-" + clip[3..];

                    keyInput.Text = clip;
                    keyInput.SelectAll();
                    if (clip.StartsWith("DD-", StringComparison.OrdinalIgnoreCase) && messageText != null)
                    {
                        messageText.Text = "Key pasted • Click Activate to confirm";
                        messageText.Foreground = UiTheme.Muted;
                    }
                }
                else if (messageText != null)
                {
                    messageText.Text = "Clipboard is empty";
                    messageText.Foreground = UiTheme.Accent;
                }
            }
            catch { }
        };
        Grid.SetColumn(pasteBtn, 2);
        keyRow.Children.Add(pasteBtn);

        panel.Children.Add(keyRow);

        // 5. Message / Feedback Text
        messageText.FontSize = 11;
        messageText.HorizontalAlignment = HorizontalAlignment.Center;
        messageText.Margin = new Thickness(0, 0, 0, 14);
        messageText.MinHeight = 16;
        panel.Children.Add(messageText);

        // 6. Action Buttons Row (Balanced, clean)
        var btnRow = new Grid();
        btnRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        btnRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(12) });
        btnRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

        secondaryBtn = new Button
        {
            Height = 32,
            Background = UiTheme.Surface,
            Foreground = UiTheme.Ink,
            BorderBrush = UiTheme.Line
        };
        Grid.SetColumn(secondaryBtn, 0);
        btnRow.Children.Add(secondaryBtn);

        primaryBtn = new Button
        {
            Height = 32,
            IsDefault = true,
            Background = UiTheme.Surface,
            Foreground = UiTheme.Ink,
            BorderBrush = UiTheme.Line
        };
        primaryBtn.Click += (_, _) => OnPrimaryClick();
        Grid.SetColumn(primaryBtn, 2);
        btnRow.Children.Add(primaryBtn);

        panel.Children.Add(btnRow);

        dismissBtn = new Button
        {
            Content = "Continue with Free (3/day)",
            Height = 28,
            Margin = new Thickness(0, 10, 0, 0),
            Background = Brushes.Transparent,
            Foreground = UiTheme.Muted,
            BorderThickness = new Thickness(0),
            Cursor = System.Windows.Input.Cursors.Hand,
            HorizontalAlignment = HorizontalAlignment.Center,
            Visibility = Visibility.Collapsed
        };
        dismissBtn.Click += (_, _) => Close();
        panel.Children.Add(dismissBtn);

        Content = UiTheme.Frame(this, panel, "DropDial Pro");

        // Pre-fill from clipboard if it holds a DD- key and input is empty
        try
        {
            if (Clipboard.ContainsText() && string.IsNullOrEmpty(keyInput.Text))
            {
                string clip = Clipboard.GetText().Trim();
                if (clip.StartsWith("\"") && clip.EndsWith("\"") && clip.Length >= 2)
                    clip = clip[1..^1].Trim();
                if (clip.StartsWith("dd-", StringComparison.OrdinalIgnoreCase) && !clip.StartsWith("DD-"))
                    clip = "DD-" + clip[3..];

                if (clip.StartsWith("DD-", StringComparison.OrdinalIgnoreCase))
                {
                    keyInput.Text = clip;
                    if (messageText != null)
                    {
                        messageText.Text = "Key pasted • Click Activate to confirm";
                        messageText.Foreground = UiTheme.Muted;
                    }
                }
            }
        }
        catch { }

        UpdateUI();
        var timer = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromSeconds(1) };
        timer.Tick += (_, _) => UpdateUI();
        timer.Start();

        LicenseManager.StatusChanged += UpdateUI;
        Closed += (_, _) =>
        {
            timer.Stop();
            LicenseManager.StatusChanged -= UpdateUI;
        };
    }

    private void UpdateUI()
    {
        var status = LicenseManager.CurrentStatus;

        if (status.IsPro && status.Info != null)
        {
            string plan = status.Info.PlanDisplayName;
            string name = string.IsNullOrEmpty(status.Info.Name) ? status.Info.Email : status.Info.Name;
            if (status.Info.ExpiresAt.HasValue)
            {
                int sec = status.Info.SecondsRemaining;
                statusSubtitle.Foreground = new SolidColorBrush(Color.FromRgb(220, 100, 30));
                if (sec <= 0)
                {
                    statusSubtitle.Text = $"{plan} Test License Expired";
                }
                else if (sec < 60)
                {
                    statusSubtitle.Text = $"{plan} Plan • Licensed to {name} ({sec}s left)";
                }
                else if (sec < 3600)
                {
                    statusSubtitle.Text = $"{plan} Plan • Licensed to {name} ({sec / 60}m {sec % 60}s left)";
                }
                else
                {
                    statusSubtitle.Text = $"{plan} Plan • Licensed to {name} ({sec / 3600}h left)";
                }
            }
            else
            {
                statusSubtitle.Foreground = UiTheme.Muted;
                statusSubtitle.Text = $"{plan} Plan • Licensed to {name}";
            }

            keyInput.Text = LicenseManager.GetStoredKey() ?? "";
            keyInput.IsEnabled = false;
            pasteBtn.IsEnabled = false;

            secondaryBtn.Content = "Deactivate…";
            secondaryBtn.Click -= OnBuyClick;
            secondaryBtn.Click -= OnDeactivateClick;
            secondaryBtn.Click += OnDeactivateClick;

            primaryBtn.Content = "Done";
            messageText.Text = "";
            titleText.Text = "DropDial Pro";
            dismissBtn.Visibility = Visibility.Collapsed;
        }
        else if (status.Kind == LicenseStatusKind.Trial && LicenseManager.TrialRemainingSeconds > 0)
        {
            titleText.Text = "DropDial Pro";
            dismissBtn.Visibility = Visibility.Collapsed;
            statusSubtitle.Foreground = UiTheme.Muted;
            statusSubtitle.Text = status.DaysRemaining <= 1
                ? $"Last day of free trial • {LicenseManager.FormatTimeRemaining(LicenseManager.TrialRemainingSeconds)} remaining"
                : $"{status.DaysRemaining} days remaining in free trial";

            keyInput.IsEnabled = true;
            pasteBtn.IsEnabled = true;

            if (LicenseManager.IsWithinFirst24Hours)
            {
                int sec = LicenseManager.First24HoursRemainingSeconds;
                secondaryBtn.Content = $"Buy (10% Off • {sec / 3600}h {(sec % 3600) / 60}m left)";
            }
            else
            {
                secondaryBtn.Content = "Buy License…";
            }
            secondaryBtn.Click -= OnBuyClick;
            secondaryBtn.Click -= OnDeactivateClick;
            secondaryBtn.Click += OnBuyClick;

            primaryBtn.Content = "Activate";
        }
        else
        {
            titleText.Text = "Your Free Trial Has Ended";
            statusSubtitle.Foreground = new SolidColorBrush(Color.FromRgb(220, 100, 30));
            int rem = LicenseManager.GetDailyConversionsRemaining();
            if (!string.IsNullOrEmpty(activeReason))
            {
                statusSubtitle.Text = $"{activeReason}\nFree tier: {rem}/3 conversions left today";
            }
            else
            {
                statusSubtitle.Text = $"You are on the Free Tier • {rem}/3 conversions left today\nUpgrade to DropDial Pro for unlimited conversions.";
            }

            keyInput.IsEnabled = true;
            pasteBtn.IsEnabled = true;

            secondaryBtn.Content = "Upgrade to Pro…";
            secondaryBtn.Click -= OnBuyClick;
            secondaryBtn.Click -= OnDeactivateClick;
            secondaryBtn.Click += OnBuyClick;

            primaryBtn.Content = "Activate";
            dismissBtn.Visibility = Visibility.Visible;
        }
    }

    private void OnBuyClick(object? sender, RoutedEventArgs e)
    {
        string url = LicenseManager.IsWithinFirst24Hours ? LicenseManager.EarlyBirdBuyUrl : LicenseManager.DefaultBuyUrl;
        try { Process.Start(new ProcessStartInfo(url) { UseShellExecute = true }); } catch { }
    }

    private void OnPrimaryClick()
    {
        if (LicenseManager.CurrentStatus.IsPro)
        {
            Close();
            return;
        }

        string key = keyInput.Text.Trim();
        if (key.StartsWith("\"") && key.EndsWith("\"") && key.Length >= 2)
            key = key[1..^1].Trim();
        if (key.StartsWith("dd-", StringComparison.OrdinalIgnoreCase) && !key.StartsWith("DD-"))
            key = "DD-" + key[3..];
        keyInput.Text = key;

        if (string.IsNullOrEmpty(key))
        {
            messageText.Text = "Please enter your license key.";
            messageText.Foreground = new SolidColorBrush(Color.FromRgb(220, 53, 69));
            return;
        }

        var (success, msg) = LicenseManager.Activate(key);
        if (success)
        {
            messageText.Text = "";
            UpdateUI();
        }
        else
        {
            messageText.Text = msg;
            messageText.Foreground = new SolidColorBrush(Color.FromRgb(220, 53, 69));
        }
    }

    private void OnActivateClick()
    {
        string key = keyInput.Text.Trim();
        if (key.StartsWith("\"") && key.EndsWith("\"") && key.Length >= 2)
            key = key[1..^1].Trim();
        if (key.StartsWith("dd-", StringComparison.OrdinalIgnoreCase) && !key.StartsWith("DD-"))
            key = "DD-" + key[3..];
        keyInput.Text = key;

        if (string.IsNullOrEmpty(key))
        {
            messageText.Text = "Please paste or enter your license key.";
            messageText.Foreground = new SolidColorBrush(Color.FromRgb(220, 53, 69));
            return;
        }

        var (success, msg) = LicenseManager.Activate(key);
        if (success)
        {
            messageText.Text = msg;
            messageText.Foreground = new SolidColorBrush(Color.FromRgb(40, 167, 69));
            UpdateUI();
        }
        else
        {
            messageText.Text = msg;
            messageText.Foreground = new SolidColorBrush(Color.FromRgb(220, 53, 69));
        }
    }

    private void OnDeactivateClick(object? sender, RoutedEventArgs e)
    {
        var result = MessageBox.Show(
            "Are you sure you want to deactivate DropDial Pro on this PC? You can re-activate anytime using your license key.",
            "Deactivate License",
            MessageBoxButton.YesNo,
            MessageBoxImage.Question
        );

        if (result == MessageBoxResult.Yes)
        {
            LicenseManager.Deactivate();
            keyInput.Text = "";
            messageText.Text = "License deactivated.";
            messageText.Foreground = UiTheme.Muted;
            UpdateUI();
        }
    }
}
