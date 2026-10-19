using System;
using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Markup;
using System.Windows.Media;
using System.Windows.Media.Effects;

namespace DropDial;

public enum TaskButtonStyle
{
    PrimarySuccess,
    PrimaryAccent,
    Secondary,
    Destructive,
    Ghost
}

// One background job on the desktop progress stack: waiting → running (pausable) → result.
internal sealed class JobCard : Border
{
    private readonly ActivityIndicator indicator = new();
    private readonly StackPanel controls = new() { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 14, 0, 0) };
    private readonly Button pauseButton, cancelButton, openButton, revealButton, hideButton;
    private readonly bool converting;
    private readonly string firstName;
    private readonly int count;
    private string stage, file;
    private ActivityIndicator.Session? session;
    private string? outputPath;

    public event Action<JobCard>? PauseRequested, ResumeRequested, CancelRequested, HideRequested;
    public JobState State { get; private set; } = JobState.Waiting;
    public bool Paused { get; private set; }
    public bool UserHidden { get; set; }
    public string FileName => file;

    public static Style CreateButtonStyle(TaskButtonStyle style, bool isDark)
    {
        string bg, fg, border, hoverBg, hoverBorder, hoverFg;
        string weight = "Medium";

        switch (style)
        {
            case TaskButtonStyle.PrimarySuccess:
                weight = "SemiBold";
                if (isDark)
                {
                    bg = "#382EC76B"; fg = "#45FFAA"; border = "#732EC76B";
                    hoverBg = "#552EC76B"; hoverBorder = "#B32EC76B"; hoverFg = "#FFFFFF";
                }
                else
                {
                    bg = "#2222A055"; fg = "#0E7A3B"; border = "#5522A055";
                    hoverBg = "#3522A055"; hoverBorder = "#8822A055"; hoverFg = "#0A5A2B";
                }
                break;

            case TaskButtonStyle.PrimaryAccent:
                weight = "SemiBold";
                if (isDark)
                {
                    bg = "#38FF6B14"; fg = "#FF8E4D"; border = "#73FF6B14";
                    hoverBg = "#55FF6B14"; hoverBorder = "#B3FF6B14"; hoverFg = "#FFFFFF";
                }
                else
                {
                    bg = "#22D55418"; fg = "#D55418"; border = "#55D55418";
                    hoverBg = "#38D55418"; hoverBorder = "#88D55418"; hoverFg = "#B5400E";
                }
                break;

            case TaskButtonStyle.Secondary:
                if (isDark)
                {
                    bg = "#1AFFFFFF"; fg = "#F0F2F5"; border = "#2EFFFFFF";
                    hoverBg = "#33FFFFFF"; hoverBorder = "#55FFFFFF"; hoverFg = "#FFFFFF";
                }
                else
                {
                    bg = "#0D000000"; fg = "#24272B"; border = "#26000000";
                    hoverBg = "#1A000000"; hoverBorder = "#40000000"; hoverFg = "#000000";
                }
                break;

            case TaskButtonStyle.Destructive:
                if (isDark)
                {
                    bg = "#28FF4D4D"; fg = "#FF7373"; border = "#55FF4D4D";
                    hoverBg = "#45FF4D4D"; hoverBorder = "#88FF4D4D"; hoverFg = "#FFFFFF";
                }
                else
                {
                    bg = "#1CE03636"; fg = "#D02525"; border = "#45E03636";
                    hoverBg = "#30E03636"; hoverBorder = "#70E03636"; hoverFg = "#B01818";
                }
                break;

            case TaskButtonStyle.Ghost:
            default:
                weight = "Normal";
                if (isDark)
                {
                    bg = "#0DFFFFFF"; fg = "#B0B5BD"; border = "#1CFFFFFF";
                    hoverBg = "#24FFFFFF"; hoverBorder = "#3DFFFFFF"; hoverFg = "#F0F2F5";
                }
                else
                {
                    bg = "#06000000"; fg = "#6E737B"; border = "#16000000";
                    hoverBg = "#12000000"; hoverBorder = "#2B000000"; hoverFg = "#24272B";
                }
                break;
        }

        string xaml = $$"""
            <Style xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" TargetType="Button">
              <Setter Property="Background" Value="{{bg}}"/>
              <Setter Property="Foreground" Value="{{fg}}"/>
              <Setter Property="BorderBrush" Value="{{border}}"/>
              <Setter Property="BorderThickness" Value="1"/>
              <Setter Property="Padding" Value="13,2"/>
              <Setter Property="MinHeight" Value="26"/>
              <Setter Property="Height" Value="26"/>
              <Setter Property="FontSize" Value="11.5"/>
              <Setter Property="FontWeight" Value="{{weight}}"/>
              <Setter Property="Cursor" Value="Hand"/>
              <Setter Property="Template">
                <Setter.Value>
                  <ControlTemplate TargetType="Button">
                    <Border x:Name="surface" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="13" Padding="{TemplateBinding Padding}">
                      <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </Border>
                    <ControlTemplate.Triggers>
                      <Trigger Property="IsMouseOver" Value="True">
                        <Setter TargetName="surface" Property="Background" Value="{{hoverBg}}"/>
                        <Setter TargetName="surface" Property="BorderBrush" Value="{{hoverBorder}}"/>
                        <Setter Property="Foreground" Value="{{hoverFg}}"/>
                      </Trigger>
                      <Trigger Property="IsEnabled" Value="False">
                        <Setter TargetName="surface" Property="Opacity" Value="0.4"/>
                      </Trigger>
                    </ControlTemplate.Triggers>
                  </ControlTemplate>
                </Setter.Value>
              </Setter>
            </Style>
            """;

        return (Style)XamlReader.Parse(xaml);
    }

    public JobCard(ConversionJob job)
    {
        converting = job.Action.StartsWith("convert:");
        firstName = Path.GetFileName(job.Paths[0]);
        count = job.Paths.Length;
        (stage, file) = Labels();
        Background = UiTheme.Surface;
        BorderBrush = UiTheme.Line;
        BorderThickness = new Thickness(1);
        CornerRadius = new CornerRadius(14);
        Padding = new Thickness(18, 16, 18, 14);
        Margin = new Thickness(10, 5, 10, 5);
        Effect = new DropShadowEffect { BlurRadius = 14, ShadowDepth = 2, Opacity = .14 };

        pauseButton = Action(L.T("Pause"), L.T("Pause this job; resume it any time"), () => (Paused ? ResumeRequested : PauseRequested)?.Invoke(this), TaskButtonStyle.Secondary);
        cancelButton = Action(L.T("Cancel"), L.T("Stop this job and remove its unfinished files"), () => CancelRequested?.Invoke(this), TaskButtonStyle.Destructive);
        openButton = Action(L.T("Open"), L.T("Open the created file"), () =>
        {
            try
            {
                if (!string.IsNullOrEmpty(outputPath) && File.Exists(outputPath))
                    Process.Start(new ProcessStartInfo(outputPath) { UseShellExecute = true });
            }
            catch { }
        }, TaskButtonStyle.PrimarySuccess);
        openButton.Visibility = Visibility.Collapsed;

        revealButton = Action(L.T("Show in Explorer"), L.T("Open folder and highlight file"), () =>
        {
            try
            {
                if (!string.IsNullOrEmpty(outputPath))
                    ExplorerIntegration.Reveal(outputPath);
            }
            catch { }
        }, TaskButtonStyle.Secondary);
        revealButton.Visibility = Visibility.Collapsed;

        hideButton = Action(L.T("Hide"), L.T("Hide this card. The job keeps running; show it again from the tray menu"), () => HideRequested?.Invoke(this), TaskButtonStyle.Ghost);
        hideButton.Margin = new Thickness(0);

        var content = new StackPanel();
        content.Children.Add(indicator);
        content.Children.Add(controls);
        Child = content;

        session = indicator.Begin(stage, file);
        session.Report(new JobProgress("queued", 0, 1, file));
        pauseButton.IsEnabled = false; // nothing to pause until it runs
    }

    private (string Stage, string File) Labels() =>
        (converting ? L.T("Converting") : L.T("Processing"), firstName + (count > 1 ? L.F(" and {1} more", count, count - 1) : ""));

    public void ApplyTheme()
    {
        Background = UiTheme.Surface;
        BorderBrush = UiTheme.Line;
        openButton.Style = CreateButtonStyle(TaskButtonStyle.PrimarySuccess, UiTheme.Dark);
        revealButton.Style = CreateButtonStyle(TaskButtonStyle.Secondary, UiTheme.Dark);
        hideButton.Style = CreateButtonStyle(TaskButtonStyle.Ghost, UiTheme.Dark);
        cancelButton.Style = CreateButtonStyle(TaskButtonStyle.Destructive, UiTheme.Dark);
        pauseButton.Style = CreateButtonStyle(Paused ? TaskButtonStyle.PrimaryAccent : TaskButtonStyle.Secondary, UiTheme.Dark);
        indicator.ApplyTheme();
    }

    // Re-reads every label in the current interface language.
    public void Relabel()
    {
        (stage, file) = Labels();
        session?.Rename(stage, file);
        SetPaused(Paused);
        cancelButton.Content = L.T("Cancel");
        cancelButton.ToolTip = L.T("Stop this job and remove its unfinished files");
        openButton.Content = L.T("Open");
        openButton.ToolTip = L.T("Open the created file");
        revealButton.Content = L.T("Show in Explorer");
        revealButton.ToolTip = L.T("Open folder and highlight file");
        hideButton.Content = L.T("Hide");
        hideButton.ToolTip = L.T("Hide this card. The job keeps running; show it again from the tray menu");
    }

    private Button Action(string text, string tip, System.Action click, TaskButtonStyle style)
    {
        var button = new Button
        {
            Content = text,
            ToolTip = tip,
            Margin = new Thickness(0, 0, 8, 0),
            Style = CreateButtonStyle(style, UiTheme.Dark)
        };
        button.Click += (_, _) => click();
        controls.Children.Add(button);
        return button;
    }

    // Waiting → running: the elapsed clock starts now, not when the job was queued.
    public IProgress<JobProgress> Start()
    {
        session?.Dispose();
        session = indicator.Begin(stage, file);
        State = JobState.Running;
        pauseButton.IsEnabled = true;
        pauseButton.Style = CreateButtonStyle(TaskButtonStyle.Secondary, UiTheme.Dark);
        return session;
    }

    public void SetPaused(bool value)
    {
        Paused = value;
        pauseButton.Content = value ? L.T("Resume") : L.T("Pause");
        pauseButton.ToolTip = value ? L.T("Continue from where it paused") : L.T("Pause this job; resume it any time");
        pauseButton.Style = CreateButtonStyle(value ? TaskButtonStyle.PrimaryAccent : TaskButtonStyle.Secondary, UiTheme.Dark);
        session?.SetPaused(value);
    }

    public void SetStopping()
    {
        State = JobState.Stopping;
        pauseButton.IsEnabled = cancelButton.IsEnabled = false;
        Paused = false;
        session?.SetPaused(false);
    }

    private static string FormatSize(long bytes)
    {
        string[] units = ["B", "KB", "MB", "GB"];
        double len = bytes;
        int order = 0;
        while (len >= 1024 && order < units.Length - 1)
        {
            order++;
            len /= 1024;
        }
        return $"{len:0.#} {units[order]}";
    }

    public void Complete(string title, string detail, string? output = null)
    {
        outputPath = output;
        session?.Dispose();
        session = null;
        State = JobState.Done;
        Paused = false;

        string? subDetail = null;
        if (!string.IsNullOrEmpty(output) && File.Exists(output))
        {
            try
            {
                var fi = new FileInfo(output);
                string folder = fi.Directory?.Name ?? "";
                string sz = FormatSize(fi.Length);
                subDetail = string.IsNullOrEmpty(folder)
                    ? L.F("File created ({0})", sz)
                    : L.F("File created ({0}) · Saved in {1}", sz, folder);
            }
            catch { }
        }

        indicator.Complete(title, detail, subDetail);
        pauseButton.Visibility = Visibility.Collapsed;
        cancelButton.Visibility = Visibility.Collapsed;

        if (!string.IsNullOrEmpty(outputPath))
        {
            openButton.Style = CreateButtonStyle(TaskButtonStyle.PrimarySuccess, UiTheme.Dark);
            revealButton.Style = CreateButtonStyle(TaskButtonStyle.Secondary, UiTheme.Dark);
            hideButton.Style = CreateButtonStyle(TaskButtonStyle.Ghost, UiTheme.Dark);
            openButton.Visibility = Visibility.Visible;
            revealButton.Visibility = Visibility.Visible;
            hideButton.Visibility = Visibility.Visible;
            controls.Visibility = Visibility.Visible;
            Cursor = System.Windows.Input.Cursors.Hand;
        }
        else
        {
            openButton.Visibility = Visibility.Collapsed;
            revealButton.Visibility = Visibility.Collapsed;
            controls.Visibility = Visibility.Collapsed;
            Cursor = System.Windows.Input.Cursors.Arrow;
        }
    }

    private Point dragStartPoint;
    private bool isDragging;

    protected override void OnPreviewMouseLeftButtonDown(System.Windows.Input.MouseButtonEventArgs e)
    {
        base.OnPreviewMouseLeftButtonDown(e);
        if (!string.IsNullOrEmpty(outputPath) && File.Exists(outputPath))
        {
            dragStartPoint = e.GetPosition(this);
            isDragging = false;
        }
    }

    protected override void OnPreviewMouseMove(System.Windows.Input.MouseEventArgs e)
    {
        base.OnPreviewMouseMove(e);
        if (e.LeftButton == System.Windows.Input.MouseButtonState.Pressed && !string.IsNullOrEmpty(outputPath) && File.Exists(outputPath))
        {
            var cur = e.GetPosition(this);
            if (!isDragging && (Math.Abs(cur.X - dragStartPoint.X) > 6 || Math.Abs(cur.Y - dragStartPoint.Y) > 6))
            {
                isDragging = true;
                try
                {
                    var data = new DataObject(DataFormats.FileDrop, new string[] { outputPath });
                    DragDrop.DoDragDrop(this, data, DragDropEffects.Copy);
                }
                catch { }
                isDragging = false;
            }
        }
    }
}

internal enum JobState { Waiting, Running, Stopping, Done }
