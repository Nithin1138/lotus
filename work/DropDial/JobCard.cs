using System;
using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Effects;

namespace DropDial;

// One background job on the desktop progress stack: waiting → running (pausable) → result.
internal sealed class JobCard : Border
{
    private readonly ActivityIndicator indicator = new();
    private readonly StackPanel controls = new() { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(0, 12, 0, 0) };
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

    public JobCard(ConversionJob job)
    {
        converting = job.Action.StartsWith("convert:");
        firstName = Path.GetFileName(job.Paths[0]);
        count = job.Paths.Length;
        (stage, file) = Labels();
        Background = UiTheme.Surface;
        BorderBrush = UiTheme.Line;
        BorderThickness = new Thickness(1);
        CornerRadius = new CornerRadius(12);
        Padding = new Thickness(20, 16, 20, 14);
        Margin = new Thickness(10, 5, 10, 5);
        Effect = new DropShadowEffect { BlurRadius = 14, ShadowDepth = 2, Opacity = .12 };
        pauseButton = Action(L.T("Pause"), L.T("Pause this job; resume it any time"), () => (Paused ? ResumeRequested : PauseRequested)?.Invoke(this));
        cancelButton = Action(L.T("Cancel"), L.T("Stop this job and remove its unfinished files"), () => CancelRequested?.Invoke(this));
        openButton = Action(L.T("Open"), L.T("Open the created file"), () =>
        {
            try
            {
                if (!string.IsNullOrEmpty(outputPath) && File.Exists(outputPath))
                    Process.Start(new ProcessStartInfo(outputPath) { UseShellExecute = true });
            }
            catch { }
        });
        openButton.Visibility = Visibility.Collapsed;
        revealButton = Action(L.T("Show in Explorer"), L.T("Open folder and highlight file"), () =>
        {
            try
            {
                if (!string.IsNullOrEmpty(outputPath))
                    ExplorerIntegration.Reveal(outputPath);
            }
            catch { }
        });
        revealButton.Visibility = Visibility.Collapsed;
        hideButton = Action(L.T("Hide"), L.T("Hide this card. The job keeps running; show it again from the tray menu"), () => HideRequested?.Invoke(this));
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

    private Button Action(string text, string tip, System.Action click)
    {
        var button = new Button { Content = text, ToolTip = tip, Margin = new Thickness(0, 0, 8, 0) };
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
        return session;
    }

    public void SetPaused(bool value)
    {
        Paused = value;
        pauseButton.Content = value ? L.T("Resume") : L.T("Pause");
        pauseButton.ToolTip = value ? L.T("Continue from where it paused") : L.T("Pause this job; resume it any time");
        session?.SetPaused(value);
    }

    public void SetStopping()
    {
        State = JobState.Stopping;
        pauseButton.IsEnabled = cancelButton.IsEnabled = false;
        Paused = false;
        session?.SetPaused(false);
    }

    public void Complete(string title, string detail, string? output = null)
    {
        outputPath = output;
        session?.Dispose();
        session = null;
        State = JobState.Done;
        Paused = false;
        indicator.Complete(title, detail);
        pauseButton.Visibility = Visibility.Collapsed;
        cancelButton.Visibility = Visibility.Collapsed;
        if (!string.IsNullOrEmpty(outputPath))
        {
            openButton.Visibility = Visibility.Visible;
            revealButton.Visibility = Visibility.Visible;
            hideButton.Visibility = Visibility.Visible;
            controls.Visibility = Visibility.Visible;
        }
        else
        {
            openButton.Visibility = Visibility.Collapsed;
            revealButton.Visibility = Visibility.Collapsed;
            controls.Visibility = Visibility.Collapsed;
        }
    }
}

internal enum JobState { Waiting, Running, Stopping, Done }
