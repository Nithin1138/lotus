using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using System.Windows.Threading;
using Path = System.IO.Path;

namespace DropDial;

internal sealed class ToolWindow : Window
{
    private readonly string[] paths;
    private readonly Operation operation;
    private readonly Func<ConversionJob, CancellationToken, IProgress<JobProgress>?, Task<BatchResult>> submit;
    private readonly Dictionary<string, FrameworkElement> controls = [];
    private readonly Dictionary<string, TextBlock> fieldLabels = [];
    private readonly Dictionary<string, Slider> sliders = [];
    private readonly Dictionary<string, TextBlock> sliderValLabels = [];
    private readonly Dictionary<string, FrameworkElement> fieldContainers = [];
    private BitmapSource? originalBitmapSource;
    private BitmapSource? cachedPreviewBase;
    private bool syncingSlider;
    private readonly TextBlock status = new(), details = new();
    private readonly Image image = new() { Stretch = Stretch.Uniform };
    private readonly Canvas overlay = new() { Background = Brushes.Transparent };
    private readonly Grid previewHost = new();
    private readonly MediaElement player = new() { LoadedBehavior = MediaState.Manual, UnloadedBehavior = MediaState.Stop };
    private readonly ListBox order = new() { Height = 120 };
    private readonly Slider timeline = new() { Minimum = 0, Maximum = 1 };
    private readonly TextBlock positionLabel = new() { Foreground = UiTheme.Muted, Margin = new Thickness(0, 8, 0, 4) };
    private readonly Rectangle selection = new() { Stroke = Brushes.DarkOrange, StrokeThickness = 2, Fill = new SolidColorBrush(Color.FromArgb(35, 255, 120, 20)), Visibility = Visibility.Collapsed };
    private readonly List<Dictionary<string, object>> regions = [];
    private readonly List<Dictionary<string, double>> audioRanges = [];
    private readonly ListBox regionList = new() { Height = 82 };
    private readonly CancellationTokenSource closing = new();
    private readonly SemaphoreSlim previewGate = new(1, 1);
    private readonly DispatcherTimer previewDelay;
    private string folder = Path.Combine(Journal.DirectoryPath, "preview-" + Guid.NewGuid().ToString("N"));
    private string? originalPreview;
    private int originalWidth, originalHeight, pages;
    private double totalDuration, fps = 30;
    private Point? selectionStart;
    private bool loaded, showingOriginal = true;
    private bool rangeEdited;
    private int previewVersion;
    private string metadataText = "";
    private Button saveButton = null!, cancelButton = null!, revealButton = null!, copyButton = null!;
    private readonly BusyLine busyLine = new();
    private readonly CropFrame cropFrame = new();
    private string editedField = "";
    private FrameworkElement bodyPanel = null!;
    private CancellationTokenSource? saving, previewCancellation;
    private string? lastOutput;
    private readonly ComboBox framePicker = new() { Visibility = Visibility.Collapsed, Margin = new Thickness(0, 0, 0, 10) };
    private bool syncingRegion;
    private int imageFrame = -1;
    private bool Cropping => operation.Id is "cropImage" or "cropVideo";
    // Rotating is previewed by transforming the picture (or the playing video) itself, so every change shows at once.
    private bool Rotating => operation.Id is "rotateImage" or "rotateVideo";
    internal bool DebugReady => loaded;
    private readonly Grid rotateStage = new();
    private readonly Border rotatePlate = new() { HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center, Visibility = Visibility.Collapsed };
    // Cropping is previewed by the frame itself, so the preview is not regenerated while its settings change.
    private bool LivePreview => RefreshFrame && !HasMedia && operation.Id != "cropImage" && !IsRealtimePreviewTool;
    private bool VisualPreview => operation.Id == "watermark" && Catalog.Category(paths[0]) == "image" || operation.Id is "compress" or "editImage" or "frameImage" or "cropImage" or "cropVideo" or "redactImage" or "annotateImage" or "redactVideo" or "redactPDF" or "organizePDF" or "createCollage";
    private bool IsRealtimePreviewTool => !HasMedia && operation.Id is "editImage" or "frameImage" or "watermark" or "annotateImage" or "redactImage" or "createCollage";
    private bool ProcessedPlayback => operation.Id is "normalizeAudio" or "audioChannels" or "audioToVideo" or "redactAudio" or "trimAudio" or "trimVideo" or "cropVideo" or "changeVideoSpeed" or "redactVideo" or "muteVideo";
    private bool HasMedia => Catalog.Category(paths[0]) is "audio" or "video";
    private MediaTransport? transport;
    private bool syncingPlayback;
    private bool syncingTrim;
    private bool HasTimeline => operation.Id is "videoToGif" or "cropVideo" or "redactVideo" or "videoSnapshots" or "trimVideo" or "trimAudio" or "redactAudio";
    private bool RefreshFrame => VisualPreview || HasTimeline && Catalog.Category(paths[0]) == "video";
    private Button? compareButton;

    // Set when this tool is shown inside another window (a combined window); the tool then provides only its body.
    private readonly Window? host;
    public UIElement? Body { get; }
    public bool Busy => saving != null;
    // In a combined window, a successful save hands the result to the host instead of finishing here.
    public Action<BatchResult>? Saved { get; set; }
    public string SaveLabel { set => saveButton.Content = value; }
    public Task Start() => Initialize();
    private string ReadyText => Saved != null ? L.T("Adjust the settings, then click “Apply this step”.") : L.T("Adjust the settings, then save. The new file goes next to the original.");
    // Stops previews and playback and removes this tool's preview folder. Called when the window closes, or by the
    // host when it removes or closes an embedded tool.
    public async void Release()
    {
        closing.Cancel();
        previewCancellation?.Cancel();
        previewDelay.Stop();
        transport?.Dispose();
        player.Stop();
        player.Source = null;
        // The player and the engine let go of the files a moment after they stop.
        await Task.Delay(1000);
        try
        {
            string root = Path.GetFullPath(Journal.DirectoryPath) + Path.DirectorySeparatorChar;
            if (Path.GetFullPath(folder).StartsWith(root, StringComparison.OrdinalIgnoreCase) && Path.GetFileName(folder).StartsWith("preview-") && Directory.Exists(folder))
                Directory.Delete(folder, true);
        }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { }
    }

    public ToolWindow(string[] paths, Operation operation, Func<ConversionJob, CancellationToken, IProgress<JobProgress>?, Task<BatchResult>> submit, Window? host = null)
    {
        this.paths = paths;
        this.operation = operation;
        this.submit = submit;
        this.host = host;
        if (host != null)
        {
            previewDelay = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(80) };
            previewDelay.Tick += async (_, _) => { previewDelay.Stop(); await UpdatePreview(); };
            Body = Build();
            return;
        }
        Title = operation.Label + " · " + Path.GetFileName(paths[0]);
        Width = 1040;
        Height = 800;
        MinWidth = 850;
        MinHeight = 640;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Background = UiTheme.WindowBack;
        FontFamily = UiTheme.Font;
        FontSize = 13;
        previewDelay = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(80) };
        previewDelay.Tick += async (_, _) => { previewDelay.Stop(); await UpdatePreview(); };
        UiTheme.Apply(this);
        Content = UiTheme.Frame(this, Build());
        Loaded += async (_, _) => await Initialize();
        Closing += (_, e) => { if (saving != null) { e.Cancel = true; status.Text = L.T("Still processing. Click Cancel and wait for the job to stop before closing the window."); } };
        PreviewKeyDown += async (_, e) => { if (e.Key == Key.Enter && Keyboard.Modifiers == ModifierKeys.Control) { e.Handled = true; await Save(); } };
        Closed += (_, _) => Release();
    }
    private UIElement Build()
    {
        var root = new Grid { Margin = new Thickness(24, 8, 24, 22) };
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        var header = new StackPanel();
        header.Children.Add(new TextBlock { Text = operation.Label, FontSize = 26, FontWeight = FontWeights.SemiBold });
        header.Children.Add(new TextBlock { Text = paths.Length == 1 ? Path.GetFileName(paths[0]) : L.F("{0} files selected", paths.Length), Foreground = UiTheme.Muted, Margin = new Thickness(0, 6, 0, 20) });
        if (host != null)
        { header.Visibility = Visibility.Collapsed; root.Margin = new Thickness(0); }
        root.Children.Add(header);
        var body = new Grid();
        body.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        body.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(340) });
        bodyPanel = body;
        Grid.SetRow(body, 1);
        root.Children.Add(body);
        var left = new StackPanel { Margin = new Thickness(0, 0, 0, 0) };
        left.Children.Add(new TextBlock { Text = VisualPreview || Rotating ? L.T("Preview") : L.T("Source preview"), FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 0, 0, 12) });
        left.Children.Add(framePicker);
        framePicker.SelectionChanged += async (_, _) => { if (loaded && framePicker.SelectedItem is ComboBoxItem item) { imageFrame = (int)item.Tag; regions.Clear(); regionList.Items.Clear(); await Initialize(); if (LivePreview) SchedulePreview(); } };
        // A whole PDF page needs more room to mark small text accurately.
        previewHost.Height = operation.Id == "redactPDF" ? 520 : 300;
        previewHost.Background = UiTheme.PreviewBack;
        if (Rotating)
        {
            rotateStage.Children.Add(rotatePlate);
            rotateStage.Children.Add(image);
            rotateStage.Children.Add(player);
            previewHost.Children.Add(rotateStage);
            previewHost.SizeChanged += (_, _) => UpdateRotationPreview();
        }
        else
        {
            previewHost.Children.Add(image);
            previewHost.Children.Add(player);
        }
        player.Visibility = Visibility.Collapsed;
        previewHost.Children.Add(overlay);
        overlay.Children.Add(selection);
        if (Cropping)
            AddCropFrame();
        // A thin line instead of a card: it never hides the picture and only appears if the work takes a moment.
        previewHost.Children.Add(busyLine);
        left.Children.Add(previewHost);
        overlay.MouseLeftButtonDown += BeginSelection;
        overlay.MouseMove += MoveSelection;
        overlay.MouseLeftButtonUp += EndSelection;
        var previewButtons = new WrapPanel { Margin = new Thickness(0, 8, 0, 8) };
        if (VisualPreview && !HasMedia)
        {
            compareButton = Button(L.T("Show result"), async () =>
            {
                if (showingOriginal)
                {
                    if (IsRealtimePreviewTool)
                    {
                        showingOriginal = false;
                        compareButton!.Content = L.T("Show original");
                        RenderRealtimePreview();
                        status.Text = L.T("Showing result preview.");
                    }
                    else
                    {
                        await UpdatePreview();
                    }
                }
                else if (originalBitmapSource != null || originalPreview != null)
                {
                    player.Stop();
                    player.Visibility = Visibility.Collapsed;
                    if (originalBitmapSource != null)
                        image.Source = originalBitmapSource;
                    else if (originalPreview != null)
                        SetImage(originalPreview);
                    showingOriginal = true;
                    compareButton!.Content = L.T("Show result");
                    status.Text = L.T("Showing the original.");
                    UpdateCropVisibility();
                }
            });
            previewButtons.Children.Add(compareButton);
        }
        left.Children.Add(previewButtons);
        if (HasMedia)
        {
            previewHost.Background = Brushes.Black;
            transport = new MediaTransport(player, timeline, paths, Catalog.Category(paths[0]) == "audio", ProcessedPlayback && paths.Length == 1, PreparePlayback, closing.Token, text => status.Text = text);
            transport.ViewChanged += () => { player.Visibility = transport.HasVideo ? Visibility.Visible : Visibility.Hidden; image.Visibility = transport.HasVideo ? Visibility.Collapsed : Visibility.Visible; };
            left.Children.Remove(previewHost);
            var surface = new StackPanel { Background = Brushes.Black };
            surface.Children.Add(previewHost);
            surface.Children.Add(transport.Controls);
            var mediaSurface = new Border { Child = surface, CornerRadius = new CornerRadius(10), Background = Brushes.Black, ClipToBounds = true };
            mediaSurface.SizeChanged += (_, _) => mediaSurface.Clip = new RectangleGeometry(new Rect(0, 0, mediaSurface.ActualWidth, mediaSurface.ActualHeight), 10, 10);
            left.Children.Add(mediaSurface);
            left.Children.Add(transport);
            if (operation.Id is "trimVideo" or "trimAudio")
                transport.RangeChanged += (first, last) => { syncingTrim = true; Set("start", first.ToString("0.000", CultureInfo.InvariantCulture)); Set("end", last.ToString("0.000", CultureInfo.InvariantCulture)); syncingTrim = false; transport.InvalidateEffect(); };
        }
        if (HasTimeline || HasMedia)
        {
            if (!HasMedia)
            { left.Children.Add(positionLabel); left.Children.Add(timeline); }
            System.Windows.Automation.AutomationProperties.SetName(timeline, L.T("Position (seconds)"));
            timeline.ValueChanged += (_, _) => { if (loaded) { syncingPlayback = transport?.IsSynchronizing == true; Set("time", timeline.Value.ToString("0.000", CultureInfo.InvariantCulture)); syncingPlayback = false; if (LivePreview) SchedulePreview(); } };
            var frameButtons = new WrapPanel();
            if (operation.Id == "videoSnapshots")
            { frameButtons.Children.Add(Button(L.T("Previous frame"), () => StepFrame(-1))); frameButtons.Children.Add(Button(L.T("Next frame"), () => StepFrame(1))); }
            if ((operation.Fields ?? []).Any(f => f.Name == "start"))
            { frameButtons.Children.Add(Button(L.T("Set start"), () => { Set("start", timeline.Value.ToString("0.000", CultureInfo.InvariantCulture)); return Task.CompletedTask; })); frameButtons.Children.Add(Button(L.T("Set end"), () => { Set("end", timeline.Value.ToString("0.000", CultureInfo.InvariantCulture)); return Task.CompletedTask; })); }
            left.Children.Add(frameButtons);
            if (transport != null)
                transport.ModeChanged += () => { frameButtons.IsEnabled = !transport.EffectSelected; UpdateCropVisibility(); };
        }
        StackPanel? rotationPanel = null;
        if (Rotating)
        {
            rotationPanel = new StackPanel { Margin = new Thickness(0, 8, 0, 4) };
            left.Children.Add(rotationPanel);
            if (operation.Id == "rotateVideo")
                left.Children.Add(new TextBlock { Text = L.T("The full length and audio are kept; the video is re-encoded."), Foreground = UiTheme.Muted, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 2, 0, 4) });
        }
        if (operation.Id == "cropVideo")
            left.Children.Add(new TextBlock { Text = L.T("Crops the picture only; the full length and audio are kept."), Foreground = UiTheme.Muted, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 6, 0, 4) });
        if (operation.Id == "redactPDF")
        {
            var pageButtons = new WrapPanel { Margin = new Thickness(0, 0, 0, 2) };
            pageButtons.Children.Add(Button(L.T("Previous page"), () => { TurnPage(-1); return Task.CompletedTask; }));
            pageButtons.Children.Add(Button(L.T("Next page"), () => { TurnPage(1); return Task.CompletedTask; }));
            left.Children.Add(pageButtons);
        }
        if (operation.Id is "cropImage" or "cropVideo" or "redactImage" or "redactVideo" or "redactPDF")
        {
            bool cropping = operation.Id is "cropImage" or "cropVideo";
            string help = cropping ? L.T("Drag the frame to move it; drag a corner or edge to resize it.") : operation.Id == "redactPDF" ? L.T("Drag on the page to mark what to black out; you can add several areas. The text and pictures inside are removed from the file, not just covered.") : L.T("Drag on the preview to add areas to redact. You can add several.");
            left.Children.Add(new TextBlock { Text = help, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 6, 0, 6) });
            left.Children.Add(Button(cropping ? L.T("Reset crop") : L.T("Clear areas"), () =>
            {
                if (cropping)
                { ResetCrop(); return Task.CompletedTask; }
                regions.Clear();
                regionList.Items.Clear();
                Set("regions", "");
                selection.Visibility = Visibility.Collapsed;
                Set("width", "0");
                Set("height", "0");
                rangeEdited = false;
                if (originalPreview != null)
                { SetImage(originalPreview); showingOriginal = true; }
                status.Text = L.T("Areas cleared. Drag on the preview to add new ones.");
                return Task.CompletedTask;
            }));
            if (operation.Id is "redactImage" or "redactVideo" or "redactPDF")
            {
                left.Children.Add(regionList);
                regionList.SelectionChanged += (_, _) =>
                {
                    if (regionList.SelectedItem is ListBoxItem item && item.Tag is Dictionary<string, object> r)
                    {
                        syncingRegion = true; foreach (string key in new[] { "x", "y", "width", "height", "start", "end", "style", "blockSize" }) if (r.TryGetValue(key, out var value)) Set(key, value.ToString()!); syncingRegion = false;
                        // A PDF area belongs to a page: selecting it shows that page.
                        if (r.TryGetValue("page", out var page) && Get("pageNumber") != page.ToString()) Set("pageNumber", page.ToString()!);
                    }
                };
                var regionButtons = new WrapPanel();
                regionButtons.Children.Add(Button(L.T("Remove selected area"), () => { if (regionList.SelectedItem is ListBoxItem item && item.Tag is Dictionary<string, object> r) { regions.Remove(r); regionList.Items.Remove(item); if (regions.Count == 0) { Set("width", "0"); Set("height", "0"); rangeEdited = false; if (originalPreview != null) { SetImage(originalPreview); showingOriginal = true; } } else SchedulePreview(); } return Task.CompletedTask; }));
                left.Children.Add(regionButtons);
            }
        }
        if (operation.Id == "redactAudio")
        {
            left.Children.Add(new TextBlock { Text = L.T("Drag on the waveform to choose a range. You can add several bleep ranges."), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 6, 0, 6) });
            left.Children.Add(Button(L.T("Clear ranges"), () => { audioRanges.Clear(); regionList.Items.Clear(); Set("ranges", ""); rangeEdited = false; selection.Visibility = Visibility.Collapsed; status.Text = L.T("Bleep ranges cleared."); return Task.CompletedTask; }));
            left.Children.Add(regionList);
            left.Children.Add(Button(L.T("Remove selected range"), () => { if (regionList.SelectedItem is ListBoxItem item && item.Tag is Dictionary<string, double> r) { audioRanges.Remove(r); regionList.Items.Remove(item); rangeEdited = audioRanges.Count > 0; } return Task.CompletedTask; }));
            regionList.SelectionChanged += (_, _) => { if (regionList.SelectedItem is ListBoxItem item && item.Tag is Dictionary<string, double> r) { syncingRegion = true; Set("start", r["start"].ToString(CultureInfo.InvariantCulture)); Set("end", r["end"].ToString(CultureInfo.InvariantCulture)); syncingRegion = false; } };
        }
        if (operation.Id == "normalizeAudio")
            left.Children.Add(Button(L.T("Measure loudness before and after"), async () =>
        {
            using var busy = busyLine.Begin();
            try
            { status.Text = L.T("Measuring loudness…"); var info = await Backend.Preview(Capture(), folder, closing.Token, "--analyze"); status.Text = L.F("Original {0} LUFS · result {1} LUFS", info.GetProperty("Input").GetString(), info.GetProperty("Output").GetString()); }
            catch (Exception ex) { status.Text = L.T("Analysis: ") + ex.Message; }
        }));
        left.Children.Add(new ScrollViewer { Content = details, MaxHeight = 130, VerticalScrollBarVisibility = ScrollBarVisibility.Auto });
        details.TextWrapping = TextWrapping.Wrap;
        details.Foreground = UiTheme.Muted;
        details.Margin = new Thickness(0, 8, 0, 8);
        if (operation.Ordered || operation.Id == "organizePDF")
        {
            left.Children.Add(order);
            var reorder = new WrapPanel();
            reorder.Children.Add(Button(L.T("Move up"), () => { MoveItem(-1); return Task.CompletedTask; }));
            reorder.Children.Add(Button(L.T("Move down"), () => { MoveItem(1); return Task.CompletedTask; }));
            reorder.Children.Add(Button(L.T("Remove"), () => { if (order.SelectedIndex >= 0) order.Items.RemoveAt(order.SelectedIndex); return Task.CompletedTask; }));
            if (operation.Id == "organizePDF")
                reorder.Children.Add(Button(L.T("Duplicate page"), () => { if (order.SelectedItem is ListBoxItem item) { int index = order.SelectedIndex; order.Items.Insert(index + 1, new ListBoxItem { Content = item.Content, Tag = item.Tag }); } return Task.CompletedTask; }));
            left.Children.Add(reorder);
            order.SelectionChanged += (_, _) => { if (loaded && VisualPreview) SchedulePreview(); };
        }
        var previewCard = UiTheme.Card(new ScrollViewer { Content = left, VerticalScrollBarVisibility = ScrollBarVisibility.Auto }, new Thickness(18));
        previewCard.Margin = new Thickness(0, 0, 16, 0);
        body.Children.Add(previewCard);
        var parameters = new StackPanel();
        parameters.Children.Add(new TextBlock { Text = L.T("Parameters"), FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 0, 0, 10) });
        if ((operation.Fields ?? []).Length == 0)
        {
            var infoBorder = new Border
            {
                Background = UiTheme.Tint,
                CornerRadius = new CornerRadius(8),
                Padding = new Thickness(12, 10, 12, 10),
                Margin = new Thickness(0, 0, 0, 14)
            };
            infoBorder.Child = new TextBlock
            {
                Text = L.F("Ready to run {0} on {1} selected file(s).", operation.Label, paths.Length),
                Foreground = UiTheme.Accent,
                FontWeight = FontWeights.Medium,
                TextWrapping = TextWrapping.Wrap
            };
            parameters.Children.Add(infoBorder);

            parameters.Children.Add(new TextBlock { Text = L.T("Quality Profile"), Margin = new Thickness(0, 6, 0, 4) });
            var qualityCombo = new ComboBox { Margin = new Thickness(0, 0, 0, 10) };
            qualityCombo.Items.Add(L.T("High Quality (Preserve Details)"));
            qualityCombo.Items.Add(L.T("Balanced (Recommended)"));
            qualityCombo.Items.Add(L.T("Maximum Compression (Small Size)"));
            qualityCombo.SelectedIndex = 1;
            parameters.Children.Add(qualityCombo);

            parameters.Children.Add(new TextBlock { Text = L.T("Output Destination"), Margin = new Thickness(0, 6, 0, 4) });
            var destCombo = new ComboBox { Margin = new Thickness(0, 0, 0, 10) };
            destCombo.Items.Add(L.T("Same folder as original"));
            destCombo.Items.Add(L.T("Desktop"));
            destCombo.Items.Add(L.T("Downloads"));
            destCombo.SelectedIndex = 0;
            parameters.Children.Add(destCombo);

            var metaCheck = new CheckBox
            {
                Content = L.T("Preserve original metadata and timestamps"),
                IsChecked = true,
                Margin = new Thickness(0, 8, 0, 8)
            };
            parameters.Children.Add(metaCheck);
        }
        var advanced = new StackPanel();
        foreach (var field in operation.Fields ?? [])
        {
            var fieldHost = field.Kind == "json" ? advanced : parameters;
            var fieldLabel = new TextBlock { Text = field.Label, Margin = new Thickness(0, 9, 0, 4), TextWrapping = TextWrapping.Wrap };
            if (Rotating && field.Name == "background" && Path.GetExtension(paths[0]).ToLowerInvariant() is ".jpg" or ".jpeg" or ".bmp")
                fieldLabel.Text = L.T("Empty corners (blank means white)");
            fieldLabels[field.Name] = fieldLabel;
            FrameworkElement control;
            var sliderBounds = GetSliderBounds(field.Name, operation.Id);
            if (sliderBounds != null)
            {
                var (min, max, def, step, unit) = sliderBounds.Value;
                double curVal = def;
                if (double.TryParse(field.Default, NumberStyles.Float, CultureInfo.InvariantCulture, out double parsedDef))
                    curVal = Math.Clamp(parsedDef, min, max);

                var box = new TextBox
                {
                    Text = curVal.ToString(CultureInfo.InvariantCulture),
                    Visibility = Visibility.Collapsed
                };
                box.TextChanged += (_, _) =>
                {
                    if (loaded && !syncingSlider)
                    {
                        if (double.TryParse(box.Text, NumberStyles.Float, CultureInfo.InvariantCulture, out double v))
                        {
                            syncingSlider = true;
                            if (sliders.TryGetValue(field.Name, out var s)) s.Value = Math.Clamp(v, min, max);
                            if (sliderValLabels.TryGetValue(field.Name, out var l)) l.Text = FormatSliderValue(v, unit, field.Name);
                            syncingSlider = false;
                        }
                        editedField = field.Name;
                        ParameterChanged();
                    }
                };
                control = box;
                controls[field.Name] = control;

                var slider = new Slider
                {
                    Minimum = min,
                    Maximum = max,
                    Value = curVal,
                    SmallChange = step,
                    LargeChange = step * 5,
                    IsMoveToPointEnabled = true,
                    Margin = new Thickness(0, 3, 0, 6),
                    HorizontalAlignment = HorizontalAlignment.Stretch
                };

                var valLabel = new TextBlock
                {
                    Text = FormatSliderValue(curVal, unit, field.Name),
                    Foreground = UiTheme.Accent,
                    FontWeight = FontWeights.Bold,
                    FontSize = 11,
                    VerticalAlignment = VerticalAlignment.Center,
                    HorizontalAlignment = HorizontalAlignment.Right
                };

                slider.ValueChanged += (_, e) =>
                {
                    if (syncingSlider) return;
                    syncingSlider = true;
                    double rounded = step < 1 ? Math.Round(e.NewValue / step) * step : Math.Round(e.NewValue);
                    string formattedText = step < 1 ? rounded.ToString("0.##", CultureInfo.InvariantCulture) : ((int)rounded).ToString(CultureInfo.InvariantCulture);
                    box.Text = formattedText;
                    valLabel.Text = FormatSliderValue(rounded, unit, field.Name);
                    syncingSlider = false;
                    if (loaded)
                    {
                        editedField = field.Name;
                        ParameterChanged();
                    }
                };

                sliders[field.Name] = slider;
                sliderValLabels[field.Name] = valLabel;

                var headerRow = new DockPanel { LastChildFill = true, Margin = new Thickness(0, 8, 0, 2) };
                DockPanel.SetDock(valLabel, Dock.Right);
                headerRow.Children.Add(valLabel);
                headerRow.Children.Add(fieldLabel);

                var sliderGroup = new StackPanel();
                sliderGroup.Children.Add(headerRow);
                sliderGroup.Children.Add(slider);
                sliderGroup.Children.Add(box);

                fieldContainers[field.Name] = sliderGroup;
                fieldHost.Children.Add(sliderGroup);
            }
            else
            {
                fieldHost.Children.Add(fieldLabel);
                if (field.Name == "metadata")
                    control = new MetadataEditor();
                else if (field.Kind == "bool")
                    control = new CheckBox { IsChecked = field.Default == "true", Content = L.T("On") };
                else if (field.Kind == "choice")
                {
                    var combo = new ComboBox();
                    foreach (string choice in field.Choices ?? [])
                        combo.Items.Add(new ComboBoxItem { Content = Choice(choice), Tag = choice });
                    combo.SelectedIndex = Array.IndexOf(field.Choices ?? [], field.Default);
                    control = combo;
                }
                else if (field.Kind == "password")
                    control = new PasswordBox();
                else
                {
                    var box = new TextBox { Text = field.Default, Padding = new Thickness(10, 8, 10, 8), AcceptsReturn = field.Kind == "json", TextWrapping = field.Kind == "json" ? TextWrapping.Wrap : TextWrapping.NoWrap, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
                    if (field.Kind == "json")
                    { box.Height = 105; box.FontFamily = new FontFamily("Consolas"); }
                    box.TextChanged += (_, _) => { if (loaded) { editedField = field.Name; if (new[] { "x", "y", "width", "height", "start", "end" }.Contains(field.Name)) rangeEdited = true; if (field.Name == "search") FilterMetadata(box.Text); else ParameterChanged(); } };
                    // While a number is being typed the frame follows it; once the box is left, the box shows what the frame really is.
                    if (Cropping && field.Name is "x" or "y" or "width" or "height")
                        box.LostKeyboardFocus += (_, _) => { if (loaded) WriteCropFields(); };
                    control = box;
                }
                controls[field.Name] = control;
                fieldContainers[field.Name] = control;
                fieldHost.Children.Add(control);
            }
            System.Windows.Automation.AutomationProperties.SetName(control, field.Label);
            if (control is ComboBox choiceControl)
                choiceControl.SelectionChanged += (_, _) => { if (loaded && (VisualPreview || Rotating)) { editedField = field.Name; ParameterChanged(); } };
            if (control is CheckBox toggle && field.Name == "remove")
            { toggle.Checked += (_, _) => SetMetadataState(); toggle.Unchecked += (_, _) => SetMetadataState(); }
            if (field.Kind.StartsWith("file"))
            {
                var (pickLabel, pickFilter) = field.Kind switch
                {
                    "file:audio" => (L.T("Choose audio…"), L.T("Audio|*.mp3;*.m4a;*.wav;*.flac;*.ogg;*.opus;*.aiff;*.wma|All files|*.*")),
                    "file:subtitle" => (L.T("Choose subtitles…"), L.T("Subtitles|*.srt;*.ass;*.ssa;*.vtt|All files|*.*")),
                    _ => (L.T("Choose image…"), L.T("Images|*.jpg;*.jpeg;*.png;*.webp;*.bmp;*.heic;*.avif|All files|*.*"))
                };
                parameters.Children.Add(Button(pickLabel, () => { var dialog = new Microsoft.Win32.OpenFileDialog { Filter = pickFilter }; if (dialog.ShowDialog(host ?? this) == true) Set(field.Name, dialog.FileName); return Task.CompletedTask; }));
            }
        }
        void ShowField(string name, bool visible)
        {
            if (fieldLabels.TryGetValue(name, out var lbl))
                lbl.Visibility = visible ? Visibility.Visible : Visibility.Collapsed;
            if (fieldContainers.TryGetValue(name, out var container))
                container.Visibility = visible ? Visibility.Visible : Visibility.Collapsed;
            else if (controls.TryGetValue(name, out var shown))
                shown.Visibility = visible ? Visibility.Visible : Visibility.Collapsed;
        }
        void WhenChanged(string name, Action update)
        {
            ((ComboBox)controls[name]).SelectionChanged += (_, _) => update();
            update();
        }
        if (operation.Id == "resizeImage")
            WhenChanged("mode", () => { string mode = Get("mode", "percent"); ShowField("percent", mode == "percent"); ShowField("edge", mode == "edge"); foreach (string name in new[] { "width", "height", "keepRatio" }) ShowField(name, mode == "size"); });
        if (operation.Id == "watermark")
            WhenChanged("layout", () => { bool tiled = Get("layout", "single") == "tiled"; ShowField("position", !tiled); ShowField("margin", !tiled); });
        if (operation.Id == "pdfPassword")
            WhenChanged("mode", () => ShowField("newPassword", Get("mode", "add") == "add"));
        if (operation.Id == "createAnimation")
            WhenChanged("format", () => ShowField("loop", Get("format", "gif") == "gif"));
        if (operation.Id == "location")
        {
            // DropDial never goes online, so there is no map here: coordinates are pasted from a map app, or taken from another photo.
            var note = new TextBlock { Text = L.T("Right-click a place in a map app to copy its coordinates, for example 31.2304, 121.4737. Or choose a photo taken there."), Foreground = UiTheme.Muted, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 10, 0, 0) };
            parameters.Children.Add(note);
            WhenChanged("mode", () =>
            {
                bool set = Get("mode", "strip") == "set";
                ShowField("coordinates", set); ShowField("locationSource", set);
                note.Visibility = set ? Visibility.Visible : Visibility.Collapsed;
                foreach (var pick in parameters.Children.OfType<Button>().Where(b => (string)b.Content == L.T("Choose image…")))
                    pick.Visibility = note.Visibility;
            });
        }
        if (operation.Id == "compress" && controls.ContainsKey("targetKB"))
        {
            // Common upload limits; a click fills the size target in.
            var limits = new WrapPanel { Margin = new Thickness(0, 6, 0, 0) };
            foreach (int megabytes in new[] { 8, 25, 50, 100 })
                limits.Children.Add(Button(megabytes + " MB", () => { Set("targetKB", (megabytes * 1024).ToString()); return Task.CompletedTask; }));
            limits.Children.Add(Button(L.T("No limit"), () => { Set("targetKB", "0"); return Task.CompletedTask; }));
            parameters.Children.Insert(parameters.Children.IndexOf(controls["targetKB"]) + 1, limits);
        }
        if (operation.Id == "editImage")
        {
            var resetBtn = Button(L.T("Reset adjustments"), () =>
            {
                foreach (var key in new[] { "exposure", "temperature", "shadows", "highlights", "clarity", "dehaze", "denoise", "grain" })
                    Set(key, "0");
                foreach (var key in new[] { "contrast", "saturation" })
                    Set(key, "1");
                ParameterChanged();
                return Task.CompletedTask;
            });
            resetBtn.Margin = new Thickness(0, 8, 0, 8);
            parameters.Children.Add(resetBtn);
        }
        if (operation.Id == "frameImage")
        {
            var colorRow = new WrapPanel { Margin = new Thickness(0, 4, 0, 8) };
            var colorPresets = new (string Hex, string Label)[]
            {
                ("#f0ebff", L.T("Lilac")),
                ("#ffffff", L.T("White")),
                ("#18181b", L.T("Graphite")),
                ("#ff6500", L.T("Orange")),
                ("#3b82f6", L.T("Blue")),
                ("#10b981", L.T("Green"))
            };
            foreach (var (hex, label) in colorPresets)
                colorRow.Children.Add(Button(label, () => { Set("background", hex); ParameterChanged(); return Task.CompletedTask; }));
            if (fieldContainers.TryGetValue("background", out var bgContainer))
                parameters.Children.Insert(parameters.Children.IndexOf(bgContainer) + 1, colorRow);
        }
        if (operation.Id == "annotateImage")
        {
            var stampRow = new WrapPanel { Margin = new Thickness(0, 4, 0, 8) };
            foreach (string word in new[] { "APPROVED", "CONFIDENTIAL", "DRAFT", "SAMPLE", "REJECTED" })
                stampRow.Children.Add(Button(word, () => { Set("text", word); ParameterChanged(); return Task.CompletedTask; }));
            if (fieldContainers.TryGetValue("text", out var textContainer))
                parameters.Children.Insert(parameters.Children.IndexOf(textContainer) + 1, stampRow);

            var colorRow = new WrapPanel { Margin = new Thickness(0, 4, 0, 8) };
            var badgeColors = new (string Hex, string Label)[]
            {
                ("#ff6500", L.T("Orange")),
                ("#ef4444", L.T("Red")),
                ("#3b82f6", L.T("Blue")),
                ("#10b981", L.T("Green")),
                ("#ffffff", L.T("White")),
                ("#000000", L.T("Black"))
            };
            foreach (var (hex, label) in badgeColors)
                colorRow.Children.Add(Button(label, () => { Set("color", hex); ParameterChanged(); return Task.CompletedTask; }));
            if (fieldContainers.TryGetValue("color", out var colContainer))
                parameters.Children.Insert(parameters.Children.IndexOf(colContainer) + 1, colorRow);
        }
        if (Presets.Supported(operation.Id))
            AddPresetBar(parameters);
        if (Rotating)
        {
            var angleBox = (TextBox)controls["angle"];
            parameters.Children.Remove(angleBox); parameters.Children.Remove(fieldLabels["angle"]);
            angleBox.Width = 76; angleBox.HorizontalContentAlignment = HorizontalAlignment.Center;
            System.Windows.Automation.AutomationProperties.SetName(angleBox, RotationDial.Caption);
            var heading = new DockPanel { LastChildFill = true, Margin = new Thickness(0, 0, 0, 8) };
            var value = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
            value.Children.Add(angleBox); value.Children.Add(new TextBlock { Text = "°", Margin = new Thickness(5, 0, 0, 0), VerticalAlignment = VerticalAlignment.Center, Foreground = UiTheme.Muted });
            DockPanel.SetDock(value, Dock.Right); heading.Children.Add(value);
            Task Turn(int quarters)
            {
                _ = double.TryParse(Get("angle", "0"), NumberStyles.Float, CultureInfo.InvariantCulture, out double angle);
                Set("angle", RotationDial.Signed(angle + 90 * quarters).ToString("0.#", CultureInfo.InvariantCulture)); return Task.CompletedTask;
            }
            var turnButtons = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(8, 0, 8, 0) };
            turnButtons.Children.Add(Button(L.T("↺ Turn left 90°"), () => Turn(-1)));
            turnButtons.Children.Add(Button(L.T("↻ Turn right 90°"), () => Turn(1)));
            DockPanel.SetDock(turnButtons, Dock.Right); heading.Children.Add(turnButtons);
            heading.Children.Add(new TextBlock { Text = RotationDial.Caption, VerticalAlignment = VerticalAlignment.Center, FontWeight = FontWeights.Medium });
            rotationPanel!.Children.Add(heading);
            var dial = new RotationDial(); rotationPanel.Children.Add(dial);
            rotationPanel.Children.Add(new TextBlock { Text = RotationDial.Help, Foreground = UiTheme.Muted, FontSize = 10, Margin = new Thickness(0, 6, 0, 0), TextAlignment = TextAlignment.Center });
            bool syncingAngle = false;
            void ShowCornerFields()
            {
                _ = double.TryParse(Get("angle", "0"), NumberStyles.Float, CultureInfo.InvariantCulture, out double angle);
                var visible = angle % 90 != 0 ? Visibility.Visible : Visibility.Collapsed;
                foreach (string name in new[] { "expand", "background" })
                    controls[name].Visibility = fieldLabels[name].Visibility = name == "background" && Get("expand") == "crop" ? Visibility.Collapsed : visible;
            }
            dial.ValueChanged += (_, _) => { if (!syncingAngle) { syncingAngle = true; angleBox.Text = dial.Value.ToString("0.#", CultureInfo.InvariantCulture); syncingAngle = false; } };
            angleBox.TextChanged += (_, _) =>
            {
                if (!syncingAngle && double.TryParse(angleBox.Text, NumberStyles.Float, CultureInfo.InvariantCulture, out double typed) && typed is >= -180 and <= 180)
                { syncingAngle = true; dial.Value = typed; syncingAngle = false; }
                ShowCornerFields();
            };
            angleBox.LostKeyboardFocus += (_, _) =>
            {
                if (!double.TryParse(angleBox.Text, NumberStyles.Float, CultureInfo.InvariantCulture, out double typed) || !double.IsFinite(typed)) typed = dial.Value;
                angleBox.Text = Math.Clamp(Math.Round(typed, 1), -180, 180).ToString("0.#", CultureInfo.InvariantCulture);
            };
            ShowCornerFields();
            ((ComboBox)controls["expand"]).SelectionChanged += (_, _) => ShowCornerFields();
        }
        if (operation.Id is "redactImage" or "redactVideo")
        {
            void UpdateRedactionFields()
            { bool mosaic = Get("style") == "pixelate"; controls["blockSize"].Visibility = fieldLabels["blockSize"].Visibility = mosaic ? Visibility.Visible : Visibility.Collapsed; if (controls.TryGetValue("color", out var color)) color.Visibility = fieldLabels["color"].Visibility = Get("style") == "solid" ? Visibility.Visible : Visibility.Collapsed; }
            ((ComboBox)controls["style"]).SelectionChanged += (_, _) => UpdateRedactionFields();
            UpdateRedactionFields();
        }
        if (controls.ContainsKey("ratio"))
        {
            var customRatio = new StackPanel { Margin = new Thickness(0, 10, 0, 0) };
            customRatio.Children.Add(new TextBlock { Text = L.T("Custom ratio (width : height)"), Margin = new Thickness(0, 0, 0, 6) });
            var inputs = new Grid();
            inputs.ColumnDefinitions.Add(new ColumnDefinition());
            inputs.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(26) });
            inputs.ColumnDefinitions.Add(new ColumnDefinition());
            foreach (string key in new[] { "ratioWidth", "ratioHeight" })
            { parameters.Children.Remove(controls[key]); parameters.Children.Remove(fieldLabels[key]); }
            inputs.Children.Add(controls["ratioWidth"]);
            Grid.SetColumn(controls["ratioHeight"], 2);
            inputs.Children.Add(controls["ratioHeight"]);
            var separator = new TextBlock { Text = ":", HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
            Grid.SetColumn(separator, 1);
            inputs.Children.Add(separator);
            customRatio.Children.Add(inputs);
            parameters.Children.Add(customRatio);
            void ShowCustomRatio() => customRatio.Visibility = Get("ratio") == "custom" ? Visibility.Visible : Visibility.Collapsed;
            ((ComboBox)controls["ratio"]).SelectionChanged += (_, _) => ShowCustomRatio();
            ShowCustomRatio();
        }
        if (advanced.Children.Count > 0)
            parameters.Children.Add(new Expander { Header = L.T("Advanced settings (optional)"), Content = advanced, Margin = new Thickness(0, 16, 0, 0) });
        if ((operation.Fields?.Length ?? 0) == 0)
        {
            var card = new Border
            {
                Background = UiTheme.Surface,
                BorderBrush = UiTheme.Line,
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(8),
                Padding = new Thickness(14, 12, 14, 12),
                Margin = new Thickness(0, 4, 0, 14)
            };
            var cardPanel = new StackPanel();
            cardPanel.Children.Add(new TextBlock
            {
                Text = L.T("Tool Settings & Options"),
                FontWeight = FontWeights.SemiBold,
                FontSize = 13,
                Foreground = UiTheme.Ink,
                Margin = new Thickness(0, 0, 0, 8)
            });
            cardPanel.Children.Add(new TextBlock
            {
                Text = operation.Ordered ? L.T("Arrange the files on the left, then save.") : L.T("Ready to run on selected files. Check the live preview, customize your output settings below, and click Save."),
                Foreground = UiTheme.Muted,
                TextWrapping = TextWrapping.Wrap,
                Margin = new Thickness(0, 0, 0, 12)
            });

            cardPanel.Children.Add(new TextBlock { Text = L.T("Quality Profile"), FontWeight = FontWeights.Medium, FontSize = 11, Foreground = UiTheme.Ink, Margin = new Thickness(0, 4, 0, 4) });
            var profileBox = new ComboBox { Margin = new Thickness(0, 0, 0, 10) };
            profileBox.Items.Add(new ComboBoxItem { Content = L.T("High Quality (Preserve Details)"), Tag = "high" });
            profileBox.Items.Add(new ComboBoxItem { Content = L.T("Balanced (Recommended)"), Tag = "balanced" });
            profileBox.Items.Add(new ComboBoxItem { Content = L.T("Maximum Compression (Small Size)"), Tag = "compact" });
            profileBox.SelectedIndex = 1;
            cardPanel.Children.Add(profileBox);

            cardPanel.Children.Add(new TextBlock { Text = L.T("Save Location"), FontWeight = FontWeights.Medium, FontSize = 11, Foreground = UiTheme.Ink, Margin = new Thickness(0, 4, 0, 4) });
            var destBox = new ComboBox { Margin = new Thickness(0, 0, 0, 10) };
            destBox.Items.Add(new ComboBoxItem { Content = L.T("Same Folder as Original"), Tag = "same" });
            destBox.Items.Add(new ComboBoxItem { Content = L.T("Desktop"), Tag = "desktop" });
            destBox.Items.Add(new ComboBoxItem { Content = L.T("Downloads"), Tag = "downloads" });
            destBox.SelectedIndex = 0;
            cardPanel.Children.Add(destBox);

            var metaCheck = new CheckBox { Content = L.T("Preserve original file metadata & creation date"), IsChecked = true, Margin = new Thickness(0, 4, 0, 4) };
            var openFolder = new CheckBox { Content = L.T("Open containing folder after saving"), IsChecked = false, Margin = new Thickness(0, 2, 0, 4) };
            cardPanel.Children.Add(metaCheck);
            cardPanel.Children.Add(openFolder);

            card.Child = cardPanel;
            parameters.Children.Add(card);
        }
        var scroll = UiTheme.Card(new ScrollViewer { Content = parameters, VerticalScrollBarVisibility = ScrollBarVisibility.Auto }, new Thickness(18));
        Grid.SetColumn(scroll, 1);
        body.Children.Add(scroll);
        var bottom = new Grid { Margin = new Thickness(0, 18, 0, 0) };
        bottom.ColumnDefinitions.Add(new ColumnDefinition());
        bottom.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        var feedback = new StackPanel { Margin = new Thickness(0, 0, 20, 0), VerticalAlignment = VerticalAlignment.Center };
        status.Text = L.T("Reading file information…");
        status.TextWrapping = TextWrapping.Wrap;
        status.Foreground = UiTheme.Muted;
        feedback.Children.Add(status);
        bottom.Children.Add(feedback);
        var actions = new StackPanel { Orientation = Orientation.Horizontal };
        Grid.SetColumn(actions, 1);
        bottom.Children.Add(actions);
        revealButton = Button(L.T("Show in folder"), () => { if (lastOutput != null) ExplorerIntegration.Reveal(lastOutput); return Task.CompletedTask; });
        revealButton.Visibility = Visibility.Collapsed;
        actions.Children.Add(revealButton);
        copyButton = Button(L.T("Copy result"), () => { CopyResult(); return Task.CompletedTask; });
        copyButton.Visibility = Visibility.Collapsed;
        actions.Children.Add(copyButton);
        cancelButton = Button(L.T("Cancel"), () => { saving?.Cancel(); cancelButton.IsEnabled = false; status.Text = L.T("Stopping…"); return Task.CompletedTask; });
        cancelButton.Visibility = Visibility.Collapsed;
        actions.Children.Add(cancelButton);
        saveButton = Button(L.T("Save new file"), Save);
        saveButton.IsEnabled = false;
        saveButton.Foreground = Brushes.White;
        saveButton.Background = UiTheme.Accent;
        saveButton.BorderThickness = new Thickness(0);
        saveButton.Padding = new Thickness(22, 10, 22, 10);
        saveButton.ToolTip = "Ctrl + Enter";
        actions.Children.Add(saveButton);
        Grid.SetRow(bottom, 2);
        root.Children.Add(bottom);
        return root;
    }
    private static string Choice(string value) => value switch { "crop" => L.T("Auto-crop empty corners"), "expand" => L.T("Expand canvas to keep entire image"), "keep" => L.T("Keep original size (allow empty corners)"), "none" => L.T("No flip"), "horizontal" => L.T("Flip left–right"), "vertical" => L.T("Flip top–bottom"), "percent" => L.T("By percentage"), "edge" => L.T("By longest side"), "size" => L.T("Exact size"), "single" => L.T("Single"), "tiled" => L.T("Tiled"), "original" => L.T("Keep as is"), "add" => L.T("Add a password"), "remove" => L.T("Remove the password"), "strip" => L.T("Remove location"), "set" => L.T("Set a new location"), "bottomRight" => L.T("Bottom right"), "bottomCenter" => L.T("Bottom centre"), "bottomLeft" => L.T("Bottom left"), "middleRight" => L.T("Middle right"), "center" => L.T("Centre"), "middleLeft" => L.T("Middle left"), "topRight" => L.T("Top right"), "topCenter" => L.T("Top centre"), "topLeft" => L.T("Top left"), "solid" => L.T("Solid fill"), "blur" => L.T("Blur"), "pixelate" => L.T("Pixelate"), "free" => L.T("Free"), "custom" => L.T("Custom"), "grid" => L.T("Grid"), "row" => L.T("Row"), "column" => L.T("Column"), "featured" => L.T("Featured"), "landscape" => L.T("Landscape"), "portrait" => L.T("Portrait"), "square" => L.T("Square"), "mono" => L.T("Mono"), "stereo" => L.T("Stereo"), _ => value };
    private static Button Button(string text, Func<Task> click)
    {
        var button = new Button { Content = text, HorizontalAlignment = HorizontalAlignment.Left, Padding = new Thickness(12, 8, 12, 8), Margin = new Thickness(0, 0, 6, 5) };
        button.Click += async (_, _) => await click();
        return button;
    }
    private async Task Initialize()
    {
        using var busy = busyLine.Begin();
        loaded = false;
        saveButton.IsEnabled = false;
        framePicker.IsEnabled = false;
        previewDelay.Stop();
        previewCancellation?.Cancel();
        previewVersion++;
        rangeEdited = false;
        if (operation.Ordered && order.Items.Count == 0)
            foreach (string path in paths)
                order.Items.Add(new ListBoxItem { Content = Path.GetFileName(path), Tag = path });
        try
        {
            var info = await Backend.Inspect(paths[0], folder, closing.Token, imageFrame);
            originalWidth = info.GetProperty("Width").GetInt32();
            originalHeight = info.GetProperty("Height").GetInt32();
            totalDuration = info.GetProperty("Duration").GetDouble();
            pages = info.GetProperty("Pages").GetInt32();
            double rate = info.GetProperty("FrameRate").GetDouble();
            if (rate > 0)
                fps = rate;
            originalPreview = info.GetProperty("Preview").GetString();
            if (originalPreview != null)
            { SetImage(originalPreview); showingOriginal = true; }
            if (paths.Length == 1 && info.TryGetProperty("Frames", out var frames) && frames.GetInt32() > 1)
            {
                if (framePicker.Items.Count == 0)
                { for (int i = 0; i < frames.GetInt32(); i++) framePicker.Items.Add(new ComboBoxItem { Content = L.F("Frame {0}", i + 1), Tag = i }); framePicker.SelectedIndex = info.GetProperty("Frame").GetInt32(); }
                framePicker.Visibility = Visibility.Visible;
                imageFrame = info.GetProperty("Frame").GetInt32();
            }
            if (originalWidth > 0 && operation.Id != "resizeImage")
            {
                Set("x", "0");
                Set("y", "0");
                Set("width", originalWidth.ToString());
                Set("height", originalHeight.ToString());
                details.Text = L.F("{0} × {1} px", originalWidth, originalHeight);
                if (Cropping)
                    cropFrame.SetSource(originalWidth, originalHeight);
            }
            if (totalDuration > 0)
            { timeline.Maximum = Math.Max(.001, totalDuration - .001); transport?.SetDuration(totalDuration); Set("end", totalDuration.ToString("0.000", CultureInfo.InvariantCulture)); details.Text += L.F("  · {0:0.00} s", totalDuration); if (Catalog.Category(paths[0]) == "video") details.Text += $" · {fps:0.##} fps"; positionLabel.Text = L.F("Preview position  {0:0.000} / {1:0.000} s", timeline.Value, totalDuration); }
            metadataText = JsonSerializer.Serialize(info.GetProperty("Metadata"), new JsonSerializerOptions { WriteIndented = true });
            Set("metadata", metadataText);
            if (controls.TryGetValue("metadata", out var editor) && editor is MetadataEditor table)
                table.Populate(info.GetProperty("Metadata"));
            if (operation.Id == "removeMetadata")
                details.Text = L.T("Fields are searchable. Turn off “Remove all” to edit metadata.");
            if (operation.Id == "location")
            {
                string? place = info.TryGetProperty("Location", out var where) && where.ValueKind == JsonValueKind.String ? where.GetString() : null;
                details.Text = (paths.Length > 1 ? L.T("First file: ") : "") + (place == null ? L.T("No location information.") : L.F("Current location: {0}", place));
            }
            if (operation.Id == "organizePDF")
            {
                for (int i = 1; i <= pages; i++)
                    order.Items.Add(new ListBoxItem { Content = L.F("Page {0}", i), Tag = i });
                Set("pageOrder", string.Join(",", Enumerable.Range(1, pages)));
                details.Text = L.F("{0} pages. Rearrange the list or type a page order.", pages);
            }
            status.Text = imageFrame >= 0 ? L.T("This image has several frames. Only the current frame is exported; the original is kept.") : ReadyText;
        }
        catch (OperationCanceledException) { }
        catch (Exception ex) { status.Text = L.T("Preview unavailable: ") + ex.Message + L.T(". You can still fill in the settings."); }
        if (Presets.Supported(operation.Id) && Presets.Last(operation.Id) is { } remembered)
            ApplyValues(remembered);
        loaded = true;
        UpdateRotationPreview();
        saveButton.IsEnabled = true;
        framePicker.IsEnabled = true;
        SetMetadataState();
        SyncTrimRange();
        UpdateCropVisibility();
        if (operation.Id == "redactPDF")
            SchedulePreview();
        if (IsRealtimePreviewTool)
        {
            showingOriginal = false;
            if (compareButton != null) compareButton.Content = L.T("Show original");
            RenderRealtimePreview();
        }
    }
    private int CurrentPage() => Math.Clamp(int.TryParse(Get("pageNumber", "1"), out int page) ? page : 1, 1, Math.Max(1, pages));
    private void TurnPage(int by) => Set("pageNumber", Math.Clamp(CurrentPage() + by, 1, Math.Max(1, pages)).ToString());
    private void Set(string name, string value)
    {
        if (sliders.TryGetValue(name, out var slider) && double.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out double sVal))
        {
            syncingSlider = true;
            slider.Value = Math.Clamp(sVal, slider.Minimum, slider.Maximum);
            if (sliderValLabels.TryGetValue(name, out var badge))
            {
                var bounds = GetSliderBounds(name, operation.Id);
                badge.Text = bounds != null ? FormatSliderValue(sVal, bounds.Value.Unit, name) : sVal.ToString(CultureInfo.InvariantCulture);
            }
            syncingSlider = false;
        }
        if (!controls.TryGetValue(name, out var control))
            return;
        if (control is TextBox text)
            text.Text = value;
        if (control is CheckBox check)
            check.IsChecked = value == "true";
        if (control is ComboBox combo)
            foreach (ComboBoxItem item in combo.Items)
                if (item.Tag?.ToString() == value)
                    combo.SelectedItem = item;
    }
    private string Get(string name, string fallback = "") => controls.TryGetValue(name, out var control) ? control switch { MetadataEditor table => table.ToJson(), TextBox text => text.Text, CheckBox check => check.IsChecked == true ? "true" : "false", ComboBox combo => ((ComboBoxItem?)combo.SelectedItem)?.Tag?.ToString() ?? fallback, PasswordBox pass => pass.Password, _ => fallback } : fallback;
    private ConversionJob Capture()
    {
        if (Cropping && cropFrame.HasSource)
        {
            // The frame is the truth: typed values that disagree with it (out of bounds, wrong ratio) are replaced by it.
            cropFrame.Ratio = CurrentRatio();
            WriteCropFields();
        }
        var values = new Dictionary<string, string>();
        foreach (var field in operation.Fields ?? [])
            values[field.Name] = Get(field.Name, field.Default);
        if (Rotating && double.TryParse(values["angle"], NumberStyles.Float, CultureInfo.InvariantCulture, out double rotation))
        {
            if (!double.IsFinite(rotation) || rotation is < -180 or > 180)
                throw new ArgumentException(L.T("Rotation must be between −180° and +180°."));
            values["angle"] = RotationDial.BackendAngle(rotation).ToString("0.#", CultureInfo.InvariantCulture);
        }
        if (values.TryGetValue("ratio", out var selectedRatio) && selectedRatio != "custom")
        { values["ratioWidth"] = "3"; values["ratioHeight"] = "2"; }
        if (values.TryGetValue("style", out var selectedStyle) && selectedStyle != "pixelate")
            values["blockSize"] = "12";
        JobValidation.ResolveRatio(values);
        foreach (var field in operation.Fields ?? [])
            if (field.Kind == "number" && !string.IsNullOrWhiteSpace(values[field.Name]) && !values[field.Name].Contains(':') && !double.TryParse(values[field.Name], NumberStyles.Float, CultureInfo.InvariantCulture, out _))
                throw new ArgumentException(field.Label + L.T(" needs a number"));
        values["fps"] = fps.ToString(CultureInfo.InvariantCulture);
        if (!values.ContainsKey("time"))
            values["time"] = timeline.Value.ToString(CultureInfo.InvariantCulture);
        if (regions.Count > 0)
            values["regions"] = JsonSerializer.Serialize(regions);
        if (audioRanges.Count > 0)
            values["ranges"] = JsonSerializer.Serialize(audioRanges);
        if (operation.Id is "redactImage" or "redactVideo" && regions.Count == 0 && string.IsNullOrWhiteSpace(Get("regions")) && !rangeEdited)
            throw new ArgumentException(L.T("Select an area on the preview first."));
        if (operation.Id == "redactAudio" && audioRanges.Count == 0 && string.IsNullOrWhiteSpace(Get("ranges")) && !rangeEdited)
            throw new ArgumentException(L.T("Select a range on the waveform first."));
        string[] ordered = operation.Ordered ? order.Items.Cast<ListBoxItem>().Select(x => (string)x.Tag).ToArray() : paths;
        if (ordered.Length == 0)
            throw new ArgumentException(L.T("Select at least one file"));
        if (operation.Id == "organizePDF")
        {
            string generated = string.Join(",", order.Items.Cast<ListBoxItem>().Select(x => x.Tag));
            string initial = string.Join(",", Enumerable.Range(1, pages));
            if (order.Items.Count == 0 && values["pageOrder"] == initial)
                throw new ArgumentException(L.T("Keep at least one page."));
            if (values["pageOrder"] == initial)
                values["pageOrder"] = generated;
            if (order.SelectedItem is ListBoxItem selected)
                values["pageNumber"] = selected.Tag.ToString()!;
        }
        if (imageFrame >= 0)
            values["imageFrame"] = imageFrame.ToString();
        var job = new ConversionJob(ordered, operation.Id, values);
        JobValidation.Check(job, originalWidth, originalHeight, totalDuration, pages);
        return job;
    }
    private void SchedulePreview() { previewDelay.Stop(); previewDelay.Start(); }
    private async Task UpdatePreview()
    {
        if (!loaded || closing.IsCancellationRequested || saving != null || selectionStart != null)
            return;
        int version = ++previewVersion;
        previewCancellation?.Cancel();
        var cancellation = CancellationTokenSource.CreateLinkedTokenSource(closing.Token);
        previewCancellation = cancellation;
        status.Text = L.T("Updating preview…");
        using var busy = busyLine.Begin();
        try
        {
            await previewGate.WaitAsync(cancellation.Token);
            try
            {
                var info = await Backend.Preview(Capture(), folder, cancellation.Token);
                if (version != previewVersion || cropFrame.IsDragging)
                    return;
                if (info.TryGetProperty("SourcePreview", out var source))
                    originalPreview = source.GetString();
                // A PDF page reports its size in points, which is the unit the drawn areas use.
                if (info.TryGetProperty("PageWidth", out var pageWidth))
                {
                    originalWidth = (int)Math.Round(pageWidth.GetDouble());
                    originalHeight = (int)Math.Round(info.GetProperty("PageHeight").GetDouble());
                    pages = info.GetProperty("Pages").GetInt32();
                    details.Text = L.F("Page {0} of {1}", info.GetProperty("Page").GetInt32(), pages);
                }
                var preview = info.GetProperty("Preview").GetString();
                if (preview != null)
                { player.Visibility = Visibility.Collapsed; player.Stop(); SetImage(preview); selection.Visibility = Visibility.Collapsed; showingOriginal = false; if (compareButton != null) compareButton.Content = L.T("Show original"); status.Text = L.T("Preview updated. Save to create the new file."); UpdateCropVisibility(); }
            }
            finally { previewGate.Release(); }
        }
        catch (OperationCanceledException) { }
        catch (Exception ex) { if (version == previewVersion) status.Text = L.T("Preview: ") + ex.Message; }
        finally { cancellation.Dispose(); if (ReferenceEquals(previewCancellation, cancellation)) previewCancellation = null; }
    }
    private void UpdateRotationPreview()
    {
        double width = previewHost.ActualWidth, height = previewHost.ActualHeight;
        if (!Rotating || originalWidth == 0 || width <= 0 || height <= 0)
            return;
        if (!double.TryParse(Get("angle", "0"), NumberStyles.Float, CultureInfo.InvariantCulture, out double angle) || !double.IsFinite(angle)) return;
        angle = Math.Clamp(angle, -180, 180);
        string flip = Get("flip", "none");
        string canvas = Get("expand", HasMedia ? "expand" : "crop");
        bool quarter = angle % 90 == 0, keep = !quarter && canvas == "keep", cropEmpty = !quarter && !HasMedia && canvas == "crop";
        // The picture is shown fitted to the preview; the rotated picture (or, when the size is kept, the original frame) is then fitted again.
        double fit = Math.Min(width / originalWidth, height / originalHeight), shownWidth = originalWidth * fit, shownHeight = originalHeight * fit;
        double radians = angle * Math.PI / 180, cos = Math.Abs(Math.Cos(radians)), sin = Math.Abs(Math.Sin(radians));
        var cropped = cropEmpty ? RotationGeometry.CropSize(originalWidth, originalHeight, angle) : (Width: originalWidth, Height: originalHeight);
        double boxWidth = cropEmpty ? cropped.Width * fit : keep ? shownWidth : shownWidth * cos + shownHeight * sin;
        double boxHeight = cropEmpty ? cropped.Height * fit : keep ? shownHeight : shownWidth * sin + shownHeight * cos;
        double zoom = keep ? 1 : Math.Min(width / boxWidth, height / boxHeight);
        var turn = new TransformGroup();
        turn.Children.Add(new RotateTransform(angle));
        turn.Children.Add(new ScaleTransform(flip == "horizontal" ? -1 : 1, flip == "vertical" ? -1 : 1));
        turn.Children.Add(new ScaleTransform(zoom, zoom));
        foreach (FrameworkElement element in new FrameworkElement[] { image, player })
        { element.RenderTransformOrigin = new Point(.5, .5); element.RenderTransform = turn; }
        Color fill = UiTheme.LineColor;   // empty corners of a picture without a fill colour: transparent in the file
        if (Path.GetExtension(paths[0]).ToLowerInvariant() is ".jpg" or ".jpeg" or ".bmp") fill = Colors.White;
        try { if (!string.IsNullOrWhiteSpace(Get("background")) && ColorConverter.ConvertFromString(Get("background").Trim()) is Color chosen) fill = chosen; }
        catch (FormatException) { }
        rotatePlate.Visibility = quarter || cropEmpty ? Visibility.Collapsed : Visibility.Visible;
        rotatePlate.Width = boxWidth * zoom;
        rotatePlate.Height = boxHeight * zoom;
        rotatePlate.Background = new SolidColorBrush(fill);
        // Keeping the original size cuts off whatever leaves the original frame.
        rotateStage.Clip = cropEmpty ? new RectangleGeometry(new Rect((width - boxWidth * zoom) / 2, (height - boxHeight * zoom) / 2, boxWidth * zoom, boxHeight * zoom))
            : keep ? new RectangleGeometry(new Rect((width - shownWidth) / 2, (height - shownHeight) / 2, shownWidth, shownHeight)) : null;
        if (!HasMedia)
        {
            int outWidth = cropEmpty ? cropped.Width : keep ? originalWidth : (int)Math.Round(originalWidth * cos + originalHeight * sin);
            int outHeight = cropEmpty ? cropped.Height : keep ? originalHeight : (int)Math.Round(originalWidth * sin + originalHeight * cos);
            details.Text = L.F("{0} × {1} px", originalWidth, originalHeight) + (outWidth == originalWidth && outHeight == originalHeight ? "" : L.F(" → {0} × {1} px", outWidth, outHeight));
        }
    }
    private static double ParseDouble(string? value, double fallback = 0.0)
    {
        if (string.IsNullOrWhiteSpace(value)) return fallback;
        return double.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out double result) ? result : fallback;
    }
    private (double Min, double Max, double Def, double Step, string Unit)? GetSliderBounds(string name, string toolId)
    {
        if (toolId == "editImage")
        {
            return name switch
            {
                "exposure" => (-2.0, 2.0, 0.0, 0.05, "EV"),
                "contrast" => (0.0, 2.0, 1.0, 0.05, "x"),
                "saturation" => (0.0, 2.0, 1.0, 0.05, "x"),
                "temperature" => (-100.0, 100.0, 0.0, 1.0, ""),
                "shadows" => (-100.0, 100.0, 0.0, 1.0, "%"),
                "highlights" => (-100.0, 100.0, 0.0, 1.0, "%"),
                "clarity" => (0.0, 100.0, 0.0, 1.0, "%"),
                "dehaze" => (0.0, 100.0, 0.0, 1.0, "%"),
                "denoise" => (0.0, 30.0, 0.0, 1.0, ""),
                "grain" => (0.0, 100.0, 0.0, 1.0, "%"),
                _ => null
            };
        }
        if (toolId == "frameImage")
        {
            return name switch
            {
                "padding" => (10.0, 300.0, 80.0, 1.0, "px"),
                "radius" => (0.0, 100.0, 24.0, 1.0, "px"),
                "shadow" => (0.0, 80.0, 20.0, 1.0, "px"),
                "backgroundBlur" => (0.0, 100.0, 0.0, 1.0, "%"),
                _ => null
            };
        }
        if (toolId == "watermark")
        {
            return name switch
            {
                "opacity" => (0.0, 100.0, 60.0, 1.0, "%"),
                "textSize" => (1.0, 25.0, 5.0, 0.5, "%"),
                "rotation" => (-180.0, 180.0, 0.0, 5.0, "°"),
                "margin" => (0.0, 20.0, 3.0, 0.5, "%"),
                "scale" => (5.0, 80.0, 20.0, 1.0, "%"),
                _ => null
            };
        }
        if (toolId == "redactImage")
        {
            return name switch
            {
                "blockSize" => (2.0, 64.0, 12.0, 1.0, "px"),
                _ => null
            };
        }
        if (toolId == "createCollage")
        {
            return name switch
            {
                "gap" => (0.0, 60.0, 16.0, 1.0, "px"),
                "radius" => (0.0, 50.0, 0.0, 1.0, "px"),
                _ => null
            };
        }
        if (toolId == "compress" && name == "quality")
        {
            return (1.0, 100.0, 75.0, 1.0, "%");
        }
        if (toolId == "resizeImage" && name == "percent")
        {
            return (1.0, 200.0, 50.0, 1.0, "%");
        }
        return null;
    }
    private static string FormatSliderValue(double val, string unit, string fieldName = "")
    {
        if (unit == "EV")
            return val.ToString("+0.00;-0.00;0.00", CultureInfo.InvariantCulture) + " EV";
        if (unit == "x")
            return val.ToString("0.00", CultureInfo.InvariantCulture) + "x";
        if (unit == "%")
        {
            int rounded = (int)Math.Round(val);
            if (fieldName is "shadows" or "highlights")
                return (rounded > 0 ? "+" : "") + rounded + "%";
            return rounded + "%";
        }
        if (unit == "°")
            return (int)Math.Round(val) + "°";
        if (unit == "px")
            return (int)Math.Round(val) + " px";
        if (string.IsNullOrEmpty(unit))
        {
            int rounded = (int)Math.Round(val);
            if (fieldName == "temperature")
                return (rounded > 0 ? "+" : "") + rounded;
            return rounded.ToString(CultureInfo.InvariantCulture);
        }
        return val.ToString("0.##", CultureInfo.InvariantCulture) + " " + unit;
    }
    private BitmapSource? GetCachedPreviewBase()
    {
        if (cachedPreviewBase != null)
            return cachedPreviewBase;
        if (originalBitmapSource == null)
            return null;

        int maxDim = 1000;
        int srcW = originalBitmapSource.PixelWidth;
        int srcH = originalBitmapSource.PixelHeight;
        if (srcW <= 0 || srcH <= 0)
            return null;

        BitmapSource baseSource = originalBitmapSource;
        if (srcW > maxDim || srcH > maxDim)
        {
            double scale = (double)maxDim / Math.Max(srcW, srcH);
            int targetW = Math.Max(1, (int)Math.Round(srcW * scale));
            int targetH = Math.Max(1, (int)Math.Round(srcH * scale));
            baseSource = new TransformedBitmap(originalBitmapSource, new ScaleTransform((double)targetW / srcW, (double)targetH / srcH));
        }

        if (baseSource.Format != PixelFormats.Bgra32)
        {
            var converted = new FormatConvertedBitmap(baseSource, PixelFormats.Bgra32, null, 0);
            converted.Freeze();
            cachedPreviewBase = converted;
        }
        else
        {
            if (baseSource.CanFreeze)
                baseSource.Freeze();
            cachedPreviewBase = baseSource;
        }
        return cachedPreviewBase;
    }
    private void RenderRealtimePreview()
    {
        if (!loaded || originalBitmapSource == null || showingOriginal)
            return;
        try
        {
            switch (operation.Id)
            {
                case "editImage":
                    UpdateEditImagePreview();
                    break;
                case "frameImage":
                    UpdateFramePreview();
                    break;
                case "watermark":
                    UpdateWatermarkPreview();
                    break;
                case "annotateImage":
                    UpdateAnnotatePreview();
                    break;
                case "redactImage":
                    UpdateRedactPreview();
                    break;
                case "createCollage":
                    UpdateCollagePreview();
                    break;
            }
        }
        catch (Exception ex)
        {
            status.Text = L.T("Preview: ") + ex.Message;
        }
    }
    private void UpdateEditImagePreview()
    {
        var baseSource = GetCachedPreviewBase();
        if (baseSource == null) return;

        double exp = ParseDouble(Get("exposure", "0"), 0.0);
        double contrast = ParseDouble(Get("contrast", "1"), 1.0);
        double saturation = ParseDouble(Get("saturation", "1"), 1.0);
        double temperature = ParseDouble(Get("temperature", "0"), 0.0);
        double shadows = ParseDouble(Get("shadows", "0"), 0.0);
        double highlights = ParseDouble(Get("highlights", "0"), 0.0);
        double clarity = ParseDouble(Get("clarity", "0"), 0.0);
        double dehaze = ParseDouble(Get("dehaze", "0"), 0.0);
        double grain = ParseDouble(Get("grain", "0"), 0.0);

        bool isDefault = Math.Abs(exp) < 0.001 &&
                         Math.Abs(contrast - 1.0) < 0.001 &&
                         Math.Abs(saturation - 1.0) < 0.001 &&
                         Math.Abs(temperature) < 0.1 &&
                         Math.Abs(shadows) < 0.1 &&
                         Math.Abs(highlights) < 0.1 &&
                         clarity < 0.1 &&
                         dehaze < 0.1 &&
                         grain < 0.1;

        if (isDefault)
        {
            image.Source = baseSource;
            return;
        }

        int w = baseSource.PixelWidth;
        int h = baseSource.PixelHeight;
        int stride = w * 4;
        int totalBytes = h * stride;

        byte[] srcPixels = new byte[totalBytes];
        baseSource.CopyPixels(srcPixels, stride, 0);

        byte[] destPixels = new byte[totalBytes];

        byte[] lutR = new byte[256];
        byte[] lutG = new byte[256];
        byte[] lutB = new byte[256];

        double expFactor = Math.Pow(2.0, exp);
        double sAmt = shadows / 100.0;
        double hAmt = highlights / 100.0;
        double effContrast = contrast * (1.0 + dehaze * 0.004);
        double effSat = saturation * (1.0 + dehaze * 0.003);
        double warmShift = temperature * 0.4;

        for (int i = 0; i < 256; i++)
        {
            double v = i * expFactor;
            double norm = Math.Clamp(v / 255.0, 0.0, 1.0);
            if (sAmt != 0 && norm < 0.5)
            {
                double shadowFactor = (0.5 - norm) * 2.0;
                v += sAmt * 55.0 * shadowFactor * shadowFactor;
            }
            if (hAmt != 0 && norm >= 0.5)
            {
                double highlightFactor = (norm - 0.5) * 2.0;
                v += hAmt * 55.0 * highlightFactor * highlightFactor;
            }
            v = 128.0 + (v - 128.0) * effContrast;
            if (clarity > 0)
            {
                double mid = 1.0 - Math.Abs(norm - 0.5) * 2.0;
                if (mid > 0)
                    v += (v - 128.0) * (clarity / 100.0) * 0.4 * mid;
            }

            lutR[i] = (byte)Math.Clamp((int)Math.Round(v + warmShift), 0, 255);
            lutG[i] = (byte)Math.Clamp((int)Math.Round(v), 0, 255);
            lutB[i] = (byte)Math.Clamp((int)Math.Round(v - warmShift), 0, 255);
        }

        bool hasSat = Math.Abs(effSat - 1.0) > 0.005;
        bool hasGrain = grain > 0.5;
        double grainScale = (grain / 100.0) * 0.25;

        for (int i = 0; i < totalBytes; i += 4)
        {
            byte b = lutB[srcPixels[i + 0]];
            byte g = lutG[srcPixels[i + 1]];
            byte r = lutR[srcPixels[i + 2]];
            byte a = srcPixels[i + 3];

            int outB = b;
            int outG = g;
            int outR = r;

            if (hasSat)
            {
                int y = (r * 77 + g * 150 + b * 29) >> 8;
                outB = Math.Clamp((int)(y + (b - y) * effSat), 0, 255);
                outG = Math.Clamp((int)(y + (g - y) * effSat), 0, 255);
                outR = Math.Clamp((int)(y + (r - y) * effSat), 0, 255);
            }

            if (hasGrain)
            {
                int noise = (int)((((i * 1103515245 + 12345) & 0x7FFFFFFF) % 100 - 50) * grainScale);
                outB = Math.Clamp(outB + noise, 0, 255);
                outG = Math.Clamp(outG + noise, 0, 255);
                outR = Math.Clamp(outR + noise, 0, 255);
            }

            destPixels[i + 0] = (byte)outB;
            destPixels[i + 1] = (byte)outG;
            destPixels[i + 2] = (byte)outR;
            destPixels[i + 3] = a;
        }

        var wb = new WriteableBitmap(w, h, 96, 96, PixelFormats.Bgra32, null);
        wb.WritePixels(new Int32Rect(0, 0, w, h), destPixels, stride, 0);
        wb.Freeze();
        image.Source = wb;
    }
    private void UpdateFramePreview()
    {
        var baseSource = GetCachedPreviewBase();
        if (baseSource == null) return;

        double pad = ParseDouble(Get("padding", "80"), 80.0);
        double radius = ParseDouble(Get("radius", "24"), 24.0);
        double shadow = ParseDouble(Get("shadow", "20"), 20.0);
        string bgStr = Get("background", "#f0ebff").Trim();
        string gradStr = Get("gradient", "").Trim();

        Color bgColor = Color.FromRgb(240, 235, 255);
        try { if (!string.IsNullOrEmpty(bgStr) && ColorConverter.ConvertFromString(bgStr) is Color c) bgColor = c; } catch { }

        Color? gradColor = null;
        try { if (!string.IsNullOrEmpty(gradStr) && ColorConverter.ConvertFromString(gradStr) is Color gc) gradColor = gc; } catch { }

        int srcW = baseSource.PixelWidth;
        int srcH = baseSource.PixelHeight;
        double scale = Math.Min(1.0, 800.0 / Math.Max(srcW, srcH));
        double imgW = srcW * scale;
        double imgH = srcH * scale;
        double scaledPad = pad * scale;
        double scaledRadius = radius * scale;
        double scaledShadow = shadow * scale;

        int canvasW = (int)Math.Max(10, Math.Round(imgW + scaledPad * 2));
        int canvasH = (int)Math.Max(10, Math.Round(imgH + scaledPad * 2));

        var rtb = new RenderTargetBitmap(canvasW, canvasH, 96, 96, PixelFormats.Pbgra32);
        var dv = new DrawingVisual();
        using (var dc = dv.RenderOpen())
        {
            Brush bgBrush = gradColor != null
                ? new LinearGradientBrush(bgColor, gradColor.Value, 45.0)
                : new SolidColorBrush(bgColor);
            dc.DrawRectangle(bgBrush, null, new Rect(0, 0, canvasW, canvasH));

            var imgRect = new Rect(scaledPad, scaledPad, imgW, imgH);

            if (scaledShadow > 0)
            {
                int steps = Math.Clamp((int)scaledShadow, 2, 20);
                for (int s = steps; s >= 1; s -= Math.Max(1, steps / 4))
                {
                    double op = 0.08 * (1.0 - (double)s / (steps + 1));
                    var sRect = new Rect(imgRect.X - s * 0.4, imgRect.Y + s * 0.3, imgRect.Width + s * 0.8, imgRect.Height + s * 0.8);
                    dc.DrawRoundedRectangle(new SolidColorBrush(Color.FromArgb((byte)(op * 255), 0, 0, 0)), null, sRect, scaledRadius + s * 0.4, scaledRadius + s * 0.4);
                }
            }

            dc.PushClip(new RectangleGeometry(imgRect, scaledRadius, scaledRadius));
            dc.DrawImage(baseSource, imgRect);
            dc.Pop();
        }
        rtb.Render(dv);
        rtb.Freeze();
        image.Source = rtb;
    }
    private void UpdateWatermarkPreview()
    {
        var baseSource = GetCachedPreviewBase();
        if (baseSource == null) return;

        string text = Get("text", "CONFIDENTIAL");
        if (string.IsNullOrWhiteSpace(text)) text = "CONFIDENTIAL";
        string colorHex = Get("color", "#ffffff").Trim();
        Color textColor = Colors.White;
        try { if (!string.IsNullOrEmpty(colorHex) && ColorConverter.ConvertFromString(colorHex) is Color tc) textColor = tc; } catch { }

        double opacity = Math.Clamp(ParseDouble(Get("opacity", "60"), 60.0) / 100.0, 0.0, 1.0);
        double textSizePercent = Math.Clamp(ParseDouble(Get("textSize", "5"), 5.0), 1.0, 30.0);
        double rotation = ParseDouble(Get("rotation", "0"), 0.0);
        double marginPercent = Math.Clamp(ParseDouble(Get("margin", "3"), 3.0), 0.0, 25.0);
        string layout = Get("layout", "single");
        string position = Get("position", "center");

        int w = baseSource.PixelWidth;
        int h = baseSource.PixelHeight;
        double shortSide = Math.Min(w, h);
        double fontSize = Math.Max(12.0, shortSide * (textSizePercent / 100.0));
        double margin = shortSide * (marginPercent / 100.0);

        var rtb = new RenderTargetBitmap(w, h, 96, 96, PixelFormats.Pbgra32);
        var dv = new DrawingVisual();
        using (var dc = dv.RenderOpen())
        {
            dc.DrawImage(baseSource, new Rect(0, 0, w, h));

            Color fontColorWithAlpha = Color.FromArgb((byte)(opacity * 255), textColor.R, textColor.G, textColor.B);
            var brush = new SolidColorBrush(fontColorWithAlpha);
            var typeface = new Typeface(new FontFamily("Segoe UI, Arial, sans-serif"), FontStyles.Normal, FontWeights.Bold, FontStretches.Normal);

            var ft = new FormattedText(
                text,
                CultureInfo.CurrentUICulture,
                FlowDirection.LeftToRight,
                typeface,
                fontSize,
                brush,
                1.0
            );

            void DrawWatermarkAt(Point center)
            {
                dc.PushTransform(new RotateTransform(rotation, center.X, center.Y));
                dc.DrawText(ft, new Point(center.X - ft.Width / 2.0, center.Y - ft.Height / 2.0));
                dc.Pop();
            }

            if (layout == "tiled")
            {
                int cols = 3, rows = 3;
                for (int r = 0; r < rows; r++)
                {
                    for (int c = 0; c < cols; c++)
                    {
                        double cx = w * (c + 0.5) / cols;
                        double cy = h * (r + 0.5) / rows;
                        DrawWatermarkAt(new Point(cx, cy));
                    }
                }
            }
            else
            {
                double cx = w / 2.0;
                double cy = h / 2.0;
                switch (position)
                {
                    case "topLeft":
                        cx = margin + ft.Width / 2.0;
                        cy = margin + ft.Height / 2.0;
                        break;
                    case "topCenter":
                        cx = w / 2.0;
                        cy = margin + ft.Height / 2.0;
                        break;
                    case "topRight":
                        cx = w - margin - ft.Width / 2.0;
                        cy = margin + ft.Height / 2.0;
                        break;
                    case "middleLeft":
                        cx = margin + ft.Width / 2.0;
                        cy = h / 2.0;
                        break;
                    case "center":
                        cx = w / 2.0;
                        cy = h / 2.0;
                        break;
                    case "middleRight":
                        cx = w - margin - ft.Width / 2.0;
                        cy = h / 2.0;
                        break;
                    case "bottomLeft":
                        cx = margin + ft.Width / 2.0;
                        cy = h - margin - ft.Height / 2.0;
                        break;
                    case "bottomCenter":
                        cx = w / 2.0;
                        cy = h - margin - ft.Height / 2.0;
                        break;
                    case "bottomRight":
                    default:
                        cx = w - margin - ft.Width / 2.0;
                        cy = h - margin - ft.Height / 2.0;
                        break;
                }
                DrawWatermarkAt(new Point(cx, cy));
            }
        }
        rtb.Render(dv);
        rtb.Freeze();
        image.Source = rtb;
    }
    private void UpdateAnnotatePreview()
    {
        var baseSource = GetCachedPreviewBase();
        if (baseSource == null) return;

        string text = Get("text", "APPROVED").Trim();
        if (string.IsNullOrEmpty(text)) text = "APPROVED";
        string colorHex = Get("color", "#ff6500").Trim();
        Color badgeColor = Color.FromRgb(255, 101, 0);
        try { if (!string.IsNullOrEmpty(colorHex) && ColorConverter.ConvertFromString(colorHex) is Color bc) badgeColor = bc; } catch { }

        string pos = Get("position", "bottom_right");

        int w = baseSource.PixelWidth;
        int h = baseSource.PixelHeight;

        double scale = Math.Max(1.0, Math.Min(w, h) / 700.0);
        double fontSize = 22.0 * scale;
        double padH = 20.0 * scale;
        double padV = 10.0 * scale;
        double margin = 35.0 * scale;

        var rtb = new RenderTargetBitmap(w, h, 96, 96, PixelFormats.Pbgra32);
        var dv = new DrawingVisual();
        using (var dc = dv.RenderOpen())
        {
            dc.DrawImage(baseSource, new Rect(0, 0, w, h));

            Color textCol = (badgeColor.R > 220 && badgeColor.G > 220 && badgeColor.B > 220) ? Colors.Black : Colors.White;
            var tf = new Typeface(new FontFamily("Segoe UI, Arial, sans-serif"), FontStyles.Normal, FontWeights.Bold, FontStretches.Normal);
            var ft = new FormattedText(
                text,
                CultureInfo.CurrentUICulture,
                FlowDirection.LeftToRight,
                tf,
                fontSize,
                new SolidColorBrush(textCol),
                1.0
            );

            double badgeW = ft.Width + padH * 2;
            double badgeH = ft.Height + padV * 2;
            double radius = badgeH / 2.0;

            double badgeX = w - badgeW - margin;
            double badgeY = h - badgeH - margin;
            if (pos is "bottom_left" or "bottomLeft")
            {
                badgeX = margin;
                badgeY = h - badgeH - margin;
            }
            else if (pos is "top_right" or "topRight")
            {
                badgeX = w - badgeW - margin;
                badgeY = margin;
            }
            else if (pos is "top_left" or "topLeft")
            {
                badgeX = margin;
                badgeY = margin;
            }
            else if (pos == "center")
            {
                badgeX = (w - badgeW) / 2.0;
                badgeY = (h - badgeH) / 2.0;
            }

            var badgeRect = new Rect(badgeX, badgeY, badgeW, badgeH);

            var shadowRect = new Rect(badgeX, badgeY + 3 * scale, badgeW, badgeH);
            dc.DrawRoundedRectangle(new SolidColorBrush(Color.FromArgb(90, 0, 0, 0)), null, shadowRect, radius, radius);

            dc.DrawRoundedRectangle(new SolidColorBrush(badgeColor), null, badgeRect, radius, radius);

            dc.DrawText(ft, new Point(badgeX + padH, badgeY + padV));
        }
        rtb.Render(dv);
        rtb.Freeze();
        image.Source = rtb;
    }
    private void UpdateRedactPreview()
    {
        var baseSource = GetCachedPreviewBase();
        if (baseSource == null) return;

        string style = Get("style", "pixelate");
        double blockSize = Math.Max(2.0, ParseDouble(Get("blockSize", "12"), 12.0));
        string colorHex = Get("color", "#000000").Trim();
        Color solidColor = Colors.Black;
        try { if (!string.IsNullOrEmpty(colorHex) && ColorConverter.ConvertFromString(colorHex) is Color sc) solidColor = sc; } catch { }

        int srcW = baseSource.PixelWidth;
        int srcH = baseSource.PixelHeight;

        var areaList = new List<Rect>();
        foreach (var r in regions)
        {
            if (r.TryGetValue("x", out var xo) && r.TryGetValue("y", out var yo) &&
                r.TryGetValue("width", out var wo) && r.TryGetValue("height", out var ho))
            {
                double rx = Convert.ToDouble(xo, CultureInfo.InvariantCulture);
                double ry = Convert.ToDouble(yo, CultureInfo.InvariantCulture);
                double rw = Convert.ToDouble(wo, CultureInfo.InvariantCulture);
                double rh = Convert.ToDouble(ho, CultureInfo.InvariantCulture);
                if (rw > 0 && rh > 0)
                    areaList.Add(new Rect(rx, ry, rw, rh));
            }
        }

        if (areaList.Count == 0)
        {
            double x = ParseDouble(Get("x", "0"), 0);
            double y = ParseDouble(Get("y", "0"), 0);
            double w = ParseDouble(Get("width", "0"), 0);
            double h = ParseDouble(Get("height", "0"), 0);
            if (w > 0 && h > 0)
                areaList.Add(new Rect(x, y, w, h));
        }

        if (areaList.Count == 0)
        {
            image.Source = baseSource;
            return;
        }

        double scaleX = (double)srcW / Math.Max(1, originalWidth);
        double scaleY = (double)srcH / Math.Max(1, originalHeight);

        int stride = srcW * 4;
        byte[]? pixelBuffer = null;
        if (style is "pixelate" or "blur")
        {
            pixelBuffer = new byte[srcH * stride];
            baseSource.CopyPixels(pixelBuffer, stride, 0);
        }

        var rtb = new RenderTargetBitmap(srcW, srcH, 96, 96, PixelFormats.Pbgra32);
        var dv = new DrawingVisual();
        using (var dc = dv.RenderOpen())
        {
            dc.DrawImage(baseSource, new Rect(0, 0, srcW, srcH));

            foreach (var originalRect in areaList)
            {
                var r = new Rect(
                    Math.Clamp(originalRect.X * scaleX, 0, srcW),
                    Math.Clamp(originalRect.Y * scaleY, 0, srcH),
                    Math.Clamp(originalRect.Width * scaleX, 1, srcW),
                    Math.Clamp(originalRect.Height * scaleY, 1, srcH)
                );

                if (style == "solid")
                {
                    dc.DrawRectangle(new SolidColorBrush(solidColor), null, r);
                }
                else if (style == "pixelate" && pixelBuffer != null)
                {
                    double bs = Math.Max(3.0, blockSize * scaleX);
                    for (double by = r.Y; by < r.Bottom; by += bs)
                    {
                        for (double bx = r.X; bx < r.Right; bx += bs)
                        {
                            double bw = Math.Min(bs, r.Right - bx);
                            double bh = Math.Min(bs, r.Bottom - by);
                            int sampleX = Math.Clamp((int)(bx + bw / 2.0), 0, srcW - 1);
                            int sampleY = Math.Clamp((int)(by + bh / 2.0), 0, srcH - 1);
                            int idx = sampleY * stride + sampleX * 4;
                            byte b = pixelBuffer[idx + 0];
                            byte g = pixelBuffer[idx + 1];
                            byte rCol = pixelBuffer[idx + 2];
                            byte a = pixelBuffer[idx + 3];
                            dc.DrawRectangle(new SolidColorBrush(Color.FromArgb(a, rCol, g, b)), null, new Rect(bx, by, bw, bh));
                        }
                    }
                }
                else if (style == "blur")
                {
                    dc.DrawRectangle(new SolidColorBrush(Color.FromArgb(190, 30, 30, 30)), null, r);
                    dc.DrawRectangle(null, new Pen(new SolidColorBrush(Color.FromArgb(120, 255, 255, 255)), 1), r);
                }
            }
        }
        rtb.Render(dv);
        rtb.Freeze();
        image.Source = rtb;
    }
    private void UpdateCollagePreview()
    {
        var baseSource = GetCachedPreviewBase();
        if (baseSource == null) return;

        string layout = Get("layout", "grid");
        double gap = Math.Max(0.0, ParseDouble(Get("gap", "16"), 16.0));
        double radius = Math.Max(0.0, ParseDouble(Get("radius", "0"), 0.0));
        string bgHex = Get("background", "#ffffff").Trim();
        Color bgColor = Colors.White;
        try { if (!string.IsNullOrEmpty(bgHex) && ColorConverter.ConvertFromString(bgHex) is Color bc) bgColor = bc; } catch { }

        int canvasW = 800;
        int canvasH = 600;

        var rtb = new RenderTargetBitmap(canvasW, canvasH, 96, 96, PixelFormats.Pbgra32);
        var dv = new DrawingVisual();
        using (var dc = dv.RenderOpen())
        {
            dc.DrawRectangle(new SolidColorBrush(bgColor), null, new Rect(0, 0, canvasW, canvasH));

            void DrawTile(Rect tileRect)
            {
                if (radius > 0)
                {
                    dc.PushClip(new RectangleGeometry(tileRect, radius, radius));
                    dc.DrawImage(baseSource, tileRect);
                    dc.Pop();
                }
                else
                {
                    dc.DrawImage(baseSource, tileRect);
                }
            }

            if (layout == "featured")
            {
                double innerW = canvasW - gap * 3;
                double innerH = canvasH - gap * 2;
                double heroW = innerW * 0.58;
                double rightW = innerW * 0.42;
                double tileH = (innerH - gap) / 2.0;

                DrawTile(new Rect(gap, gap, heroW, innerH));
                DrawTile(new Rect(gap * 2 + heroW, gap, rightW, tileH));
                DrawTile(new Rect(gap * 2 + heroW, gap * 2 + tileH, rightW, tileH));
            }
            else if (layout == "row")
            {
                double tileW = (canvasW - gap * 4) / 3.0;
                double tileH = canvasH - gap * 2;
                for (int i = 0; i < 3; i++)
                    DrawTile(new Rect(gap + i * (tileW + gap), gap, tileW, tileH));
            }
            else if (layout == "column")
            {
                double tileW = canvasW - gap * 2;
                double tileH = (canvasH - gap * 4) / 3.0;
                for (int i = 0; i < 3; i++)
                    DrawTile(new Rect(gap, gap + i * (tileH + gap), tileW, tileH));
            }
            else
            {
                double tileW = (canvasW - gap * 3) / 2.0;
                double tileH = (canvasH - gap * 3) / 2.0;
                for (int row = 0; row < 2; row++)
                    for (int col = 0; col < 2; col++)
                        DrawTile(new Rect(gap + col * (tileW + gap), gap + row * (tileH + gap), tileW, tileH));
            }
        }
        rtb.Render(dv);
        rtb.Freeze();
        image.Source = rtb;
    }
    private void ApplyValues(Dictionary<string, string> values)
    {
        foreach (var (name, value) in values)
            if (Presets.Keeps(name))
                Set(name, value);
    }
    private Dictionary<string, string> PresetValues() => (operation.Fields ?? []).Where(f => Presets.Keeps(f.Name) && f.Kind != "password").ToDictionary(f => f.Name, f => Get(f.Name, f.Default));
    private void AddPresetBar(Panel parameters)
    {
        var names = new ComboBox { MinWidth = 120, Margin = new Thickness(0, 0, 6, 0) };
        void Reload()
        {
            names.Items.Clear();
            names.Items.Add(new ComboBoxItem { Content = L.T("Presets…"), Tag = "" });
            foreach (string name in Presets.Names(operation.Id))
                names.Items.Add(new ComboBoxItem { Content = name, Tag = name });
            names.SelectedIndex = 0;
        }
        names.SelectionChanged += (_, _) =>
        {
            if (names.SelectedItem is ComboBoxItem { Tag: string name } && name.Length > 0 && Presets.Named(operation.Id, name) is { } values)
            { ApplyValues(values); ParameterChanged(); status.Text = L.F("Applied preset “{0}”.", name); }
        };
        var row = new WrapPanel { Margin = new Thickness(0, 0, 0, 4) };
        row.Children.Add(names);
        row.Children.Add(Button(L.T("Save as preset"), () =>
        {
            string? name = PromptName();
            if (!string.IsNullOrWhiteSpace(name))
            { Presets.SaveNamed(operation.Id, name.Trim(), PresetValues()); Reload(); status.Text = L.F("Saved preset “{0}”.", name.Trim()); }
            return Task.CompletedTask;
        }));
        row.Children.Add(Button(L.T("Delete preset"), () =>
        {
            if (names.SelectedItem is ComboBoxItem { Tag: string name } && name.Length > 0)
            { Presets.Delete(operation.Id, name); Reload(); }
            return Task.CompletedTask;
        }));
        Reload();
        parameters.Children.Insert(Math.Min(1, parameters.Children.Count), row);
    }
    private string? PromptName()
    {
        var box = new TextBox { Padding = new Thickness(8), Margin = new Thickness(0, 0, 0, 12) };
        var dialog = new Window { Title = L.T("Preset name"), Owner = host ?? this, Width = 340, SizeToContent = SizeToContent.Height, WindowStartupLocation = WindowStartupLocation.CenterOwner, ResizeMode = ResizeMode.NoResize, ShowInTaskbar = false, Background = Background, FontFamily = FontFamily };
        var ok = new Button { Content = L.T("Save"), IsDefault = true, Padding = new Thickness(18, 7, 18, 7), HorizontalAlignment = HorizontalAlignment.Right };
        ok.Click += (_, _) => dialog.DialogResult = true;
        var stack = new StackPanel { Margin = new Thickness(18) };
        stack.Children.Add(new TextBlock { Text = L.T("Give these settings a name:"), Margin = new Thickness(0, 0, 0, 8) });
        stack.Children.Add(box);
        stack.Children.Add(ok);
        dialog.Content = stack;
        dialog.Loaded += (_, _) => box.Focus();
        return dialog.ShowDialog() == true ? box.Text : null;
    }
    private void CopyResult()
    {
        if (lastOutput == null || !File.Exists(lastOutput))
            return;
        try
        {
            string extension = Path.GetExtension(lastOutput).ToLowerInvariant();
            if (extension is ".png" or ".jpg" or ".jpeg" or ".bmp" or ".webp" or ".tiff" or ".ico")
            {
                var bitmap = new BitmapImage();
                bitmap.BeginInit();
                bitmap.CacheOption = BitmapCacheOption.OnLoad;
                bitmap.UriSource = new Uri(lastOutput);
                bitmap.EndInit();
                Clipboard.SetImage(bitmap);
            }
            else if (extension == ".txt")
                Clipboard.SetText(File.ReadAllText(lastOutput));
            else
                Clipboard.SetFileDropList([lastOutput]);
            status.Text = L.T("Copied to the clipboard.");
        }
        catch (Exception ex) when (ex is System.Runtime.InteropServices.ExternalException or IOException or NotSupportedException) { status.Text = L.T("Copy failed: ") + ex.Message; }
    }
    private void SetImage(string path)
    {
        using var stream = File.OpenRead(path);
        var bitmap = new BitmapImage();
        bitmap.BeginInit();
        bitmap.CacheOption = BitmapCacheOption.OnLoad;
        bitmap.StreamSource = stream;
        bitmap.EndInit();
        bitmap.Freeze();
        if (showingOriginal || originalBitmapSource == null)
        {
            originalBitmapSource = bitmap;
            cachedPreviewBase = null;
        }
        image.Source = bitmap;
        image.Visibility = Visibility.Visible;
    }
    private void FilterMetadata(string search)
    {
        if (controls.TryGetValue("metadata", out var editor) && editor is MetadataEditor table)
            table.Filter(search);
        details.Text = L.T("Fields are searchable. Turn off “Remove all” to edit metadata.");
    }
    private void MoveItem(int direction)
    {
        int index = order.SelectedIndex, next = index + direction;
        if (index < 0 || next < 0 || next >= order.Items.Count)
            return;
        var item = order.Items[index];
        order.Items.RemoveAt(index);
        order.Items.Insert(next, item);
        order.SelectedIndex = next;
    }
    private void AddCropFrame()
    {
        if (operation.Id == "cropImage")
            previewHost.Height = 350;
        previewHost.Children.Add(cropFrame);
        cropFrame.Visibility = Visibility.Collapsed;
        System.Windows.Automation.AutomationProperties.SetName(cropFrame, L.T("Crop selection"));
        cropFrame.DragStarted += () =>
        {
            // Grabbing the frame means the result preview is out of date, and a request still in flight is of no use.
            cropFrame.Ratio = CurrentRatio();
            previewDelay.Stop();
            previewCancellation?.Cancel();
            previewVersion++;
            transport?.Pause();
            if (status.Text == L.T("Updating preview…"))
                status.Text = ReadyText;
        };
        cropFrame.Changed += () => WriteCropFields();
        cropFrame.DragEnded += () => { WriteCropFields(); transport?.InvalidateEffect(); };
    }
    // The frame is shown over the original picture; the cropped result and the video's "result" view replace it.
    private void UpdateCropVisibility() =>
        cropFrame.Visibility = Cropping && loaded && cropFrame.HasSource && showingOriginal && transport?.EffectSelected != true ? Visibility.Visible : Visibility.Collapsed;
    private CropRatio? CurrentRatio()
    {
        string ratio = Get("ratio", "free");
        return CropRatio.Parse(ratio == "custom" ? Get("ratioWidth") + ":" + Get("ratioHeight") : ratio);
    }
    private bool TryReadCropFields(out CropRect rect)
    {
        rect = default;
        var numbers = new double[4];
        string[] names = ["x", "y", "width", "height"];
        for (int i = 0; i < 4; i++)
            if (!double.TryParse(Get(names[i]), NumberStyles.Float, CultureInfo.InvariantCulture, out numbers[i]) || !double.IsFinite(numbers[i]) || Math.Abs(numbers[i]) > int.MaxValue)
                return false;
        rect = new CropRect((int)numbers[0], (int)numbers[1], (int)numbers[2], (int)numbers[3]);
        return true;
    }
    // Typed values move the frame. Numbers that are still being typed (too small, not a number yet) are left alone.
    private void FieldsToCropFrame()
    {
        if (!cropFrame.HasSource || !TryReadCropFields(out var typed))
            return;
        var ratio = CurrentRatio();
        cropFrame.Ratio = ratio;
        int min = cropFrame.MinSize;
        if (typed.Width < min || typed.Height < min)
            return;
        var keep = ratio == null ? CropKeep.Nothing : editedField == "width" ? CropKeep.Width : editedField == "height" ? CropKeep.Height : CropKeep.Nothing;
        var next = CropMath.Constrain(typed, originalWidth, originalHeight, ratio, min, keep);
        if (next != cropFrame.Crop)
            cropFrame.SetCrop(next);
        // The box being typed in is left alone so the cursor does not jump; the others follow the frame.
        WriteCropFields(editedField);
        if (!showingOriginal && originalPreview != null)
            ShowOriginalWithFrame();
    }
    private void WriteCropFields(string? except = null)
    {
        if (!cropFrame.HasSource)
            return;
        var crop = cropFrame.Crop;
        bool was = syncingRegion;
        syncingRegion = true;
        try
        {
            if (except != "x") Set("x", crop.X.ToString(CultureInfo.InvariantCulture));
            if (except != "y") Set("y", crop.Y.ToString(CultureInfo.InvariantCulture));
            if (except != "width") Set("width", crop.Width.ToString(CultureInfo.InvariantCulture));
            if (except != "height") Set("height", crop.Height.ToString(CultureInfo.InvariantCulture));
        }
        finally { syncingRegion = was; }
    }
    private void ShowOriginalWithFrame()
    {
        if (originalBitmapSource != null)
        { player.Stop(); player.Visibility = Visibility.Collapsed; image.Source = originalBitmapSource; }
        else if (originalPreview != null)
        { player.Stop(); player.Visibility = Visibility.Collapsed; SetImage(originalPreview); }
        showingOriginal = true;
        if (compareButton != null)
            compareButton.Content = L.T("Show result");
        UpdateCropVisibility();
    }
    private void ResetCrop()
    {
        if (!cropFrame.HasSource)
            return;
        bool was = syncingRegion;
        syncingRegion = true;
        try { Set("ratio", "free"); }
        finally { syncingRegion = was; }
        cropFrame.Ratio = null;
        cropFrame.SetCrop(new CropRect(0, 0, originalWidth, originalHeight));
        WriteCropFields();
        previewDelay.Stop();
        ShowOriginalWithFrame();
        transport?.InvalidateEffect();
    }
    // For screenshots and manual checks: puts the window into a known state (see the --debug-tool-render mode).
    internal void DebugScene(string scene)
    {
        foreach (string part in scene.Split(';', StringSplitOptions.RemoveEmptyEntries))
        {
            if (part == "busy")
            { busyLine.ShowDelay = TimeSpan.Zero; busyLine.Begin(); }
            else if (part.StartsWith("angle=") && Rotating)
                Set("angle", part[6..]);
            else if (part.StartsWith("ratio=") && controls.ContainsKey("ratio"))
            { Set("ratio", part[6..]); editedField = "ratio"; ParameterChanged(); }
            else if (part.StartsWith("crop=") && cropFrame.HasSource)
            {
                int[] v = part[5..].Split(',').Select(int.Parse).ToArray();
                cropFrame.SetCrop(CropMath.Constrain(new CropRect(v[0], v[1], v[2], v[3]), originalWidth, originalHeight, CurrentRatio(), cropFrame.MinSize));
                WriteCropFields();
            }
        }
    }
    private Point SourcePoint(Point point)
    {
        double scale = Math.Min(previewHost.ActualWidth / Math.Max(1, originalWidth), previewHost.ActualHeight / Math.Max(1, originalHeight));
        double offsetX = (previewHost.ActualWidth - originalWidth * scale) / 2, offsetY = (previewHost.ActualHeight - originalHeight * scale) / 2;
        return new Point(Math.Clamp((point.X - offsetX) / scale, 0, originalWidth), Math.Clamp((point.Y - offsetY) / scale, 0, originalHeight));
    }
    private void BeginSelection(object sender, MouseButtonEventArgs e)
    {
        bool audio = operation.Id is "redactAudio" or "trimAudio";
        if (!loaded || saving != null)
            return;
        if (!audio && (operation.Id is not ("redactImage" or "redactVideo" or "redactPDF") || originalWidth == 0))
            return;
        if (HasMedia)
        { if (transport?.EffectSelected == true) { status.Text = L.T("Switch to the original before selecting an area or audio range."); return; } transport?.Pause(); }
        if (!showingOriginal && !HasMedia && originalPreview != null)
        { SetImage(originalPreview); showingOriginal = true; }
        previewDelay.Stop();
        previewCancellation?.Cancel();
        selectionStart = e.GetPosition(previewHost);
        overlay.CaptureMouse();
        selection.Visibility = Visibility.Visible;
        Canvas.SetLeft(selection, selectionStart.Value.X);
        Canvas.SetTop(selection, selectionStart.Value.Y);
        selection.Width = selection.Height = 0;
    }
    private void MoveSelection(object sender, MouseEventArgs e)
    {
        if (selectionStart == null)
            return;
        var raw = e.GetPosition(previewHost);
        var point = new Point(Math.Clamp(raw.X, 0, previewHost.ActualWidth), Math.Clamp(raw.Y, 0, previewHost.ActualHeight));
        Canvas.SetLeft(selection, Math.Min(point.X, selectionStart.Value.X));
        Canvas.SetTop(selection, Math.Min(point.Y, selectionStart.Value.Y));
        selection.Width = Math.Abs(point.X - selectionStart.Value.X);
        selection.Height = Math.Abs(point.Y - selectionStart.Value.Y);
    }
    private void EndSelection(object sender, MouseButtonEventArgs e)
    {
        if (selectionStart == null)
            return;
        var first = SourcePoint(selectionStart.Value);
        var last = SourcePoint(e.GetPosition(previewHost));
        overlay.ReleaseMouseCapture();
        selectionStart = null;
        if (operation.Id is "redactAudio" or "trimAudio")
        {
            double start = Math.Clamp(Canvas.GetLeft(selection) / Math.Max(1, previewHost.ActualWidth) * totalDuration, 0, totalDuration), end = Math.Clamp((Canvas.GetLeft(selection) + selection.Width) / Math.Max(1, previewHost.ActualWidth) * totalDuration, 0, totalDuration);
            Set("start", start.ToString("0.000", CultureInfo.InvariantCulture));
            Set("end", end.ToString("0.000", CultureInfo.InvariantCulture));
            if (end - start < .001)
            { selection.Visibility = Visibility.Collapsed; return; }
            if (operation.Id == "redactAudio")
            { var r = new Dictionary<string, double> { ["start"] = start, ["end"] = end }; audioRanges.Add(r); var row = new ListBoxItem { Content = L.F("{0:0.000}–{1:0.000} s", start, end), Tag = r }; regionList.Items.Add(row); regionList.SelectedItem = row; status.Text = L.F("{0} bleep range(s) added.", audioRanges.Count); }
            return;
        }
        int x = (int)Math.Min(first.X, last.X), y = (int)Math.Min(first.Y, last.Y), w = (int)Math.Abs(last.X - first.X), h = (int)Math.Abs(last.Y - first.Y);
        if (w < 1 || h < 1)
            return;
        syncingRegion = true;
        Set("x", x.ToString());
        Set("y", y.ToString());
        Set("width", w.ToString());
        Set("height", h.ToString());
        syncingRegion = false;
        if (operation.Id == "redactPDF")
        {
            int page = CurrentPage();
            var mark = new Dictionary<string, object> { ["page"] = page, ["x"] = x, ["y"] = y, ["width"] = w, ["height"] = h };
            regions.Add(mark);
            var row = new ListBoxItem { Content = L.F("Page {0} · area {1}", page, regions.Count), Tag = mark };
            regionList.Items.Add(row);
            regionList.SelectedItem = row;
            status.Text = L.F("{0} area(s) added.", regions.Count);
        }
        if (operation.Id is "redactImage" or "redactVideo")
        {
            double start = TimeValue(Get("start", "0")), end = TimeValue(Get("end", "0"));
            var region = new Dictionary<string, object> { ["x"] = x, ["y"] = y, ["width"] = w, ["height"] = h, ["start"] = start, ["end"] = end, ["style"] = Get("style", "pixelate"), ["blockSize"] = Get("blockSize", "12") };
            regions.Add(region);
            var row = new ListBoxItem { Content = L.F("Area {0} · {1} × {2} · {3}", regions.Count, w, h, Choice(Get("style"))), Tag = region };
            regionList.Items.Add(row);
            regionList.SelectedItem = row;
            status.Text = L.F("{0} area(s) added.", regions.Count);
        }
        if (!HasMedia)
        {
            if (IsRealtimePreviewTool)
            {
                showingOriginal = false;
                if (compareButton != null) compareButton.Content = L.T("Show original");
                RenderRealtimePreview();
            }
            else
            {
                SchedulePreview();
            }
        }
    }
    private static double TimeValue(string value) => JobValidation.Time(value);
    private void SetMetadataState() { if (controls.TryGetValue("metadata", out var table) && table is MetadataEditor editor) editor.IsReadOnly = Get("remove") == "true"; }
    private void ParameterChanged()
    {
        if (syncingRegion || syncingPlayback || syncingTrim)
            return;
        SyncTrimRange();
        transport?.InvalidateEffect();
        if (Cropping)
            FieldsToCropFrame();
        if (Rotating)
            UpdateRotationPreview();
        if (operation.Id is "redactImage" or "redactVideo" && regionList.SelectedItem is ListBoxItem item && item.Tag is Dictionary<string, object> r)
        {
            try
            { foreach (string key in new[] { "x", "y", "width", "height", "start", "end", "blockSize" }) if (controls.ContainsKey(key)) r[key] = TimeValue(Get(key, "0")); r["style"] = Get("style", "pixelate"); item.Content = L.F("Area {0} · {1} × {2} · {3}", regionList.SelectedIndex + 1, r["width"], r["height"], Choice(Get("style"))); }
            catch (ArgumentException) { }
            catch (FormatException) { }
        }
        if (operation.Id == "redactAudio" && regionList.SelectedItem is ListBoxItem audioItem && audioItem.Tag is Dictionary<string, double> range)
        {
            try
            { range["start"] = TimeValue(Get("start", "0")); range["end"] = TimeValue(Get("end", "0")); audioItem.Content = L.F("{0:0.000}–{1:0.000} s", range["start"], range["end"]); }
            catch (ArgumentException) { }
        }
        if (IsRealtimePreviewTool)
        {
            showingOriginal = false;
            if (compareButton != null)
                compareButton.Content = L.T("Show original");
            RenderRealtimePreview();
            return;
        }
        if (LivePreview)
            SchedulePreview();
    }
    private void SyncTrimRange()
    {
        if (transport == null || operation.Id is not ("trimVideo" or "trimAudio") || totalDuration <= 0)
            return;
        try
        { double first = TimeValue(Get("start", "0")), last = TimeValue(Get("end", "0")); if (last == 0) last = totalDuration; if (first >= 0 && last > first && last <= totalDuration + .001) transport.SetTrimRange(first, last); }
        catch (ArgumentException) { }
        catch (FormatException) { }
    }
    private async Task Save()
    {
        if (!loaded || saving != null)
            return;
        ConversionJob job;
        try
        { job = Capture(); }
        catch (Exception ex) { status.Text = ex.Message; status.Foreground = UiTheme.Accent; return; }
        if (operation.Id == "location" && Get("mode") == "set" && string.IsNullOrWhiteSpace(Get("coordinates")) && string.IsNullOrWhiteSpace(Get("locationSource")))
        { status.Text = L.T("Type the coordinates of the new location, or choose a photo to copy its location from."); status.Foreground = UiTheme.Accent; return; }
        if (operation.Id == "redactPDF" && regions.Count == 0 && string.IsNullOrWhiteSpace(Get("findText")) && string.IsNullOrWhiteSpace(Get("regions")))
        { status.Text = L.T("Mark an area on the page, or type the text to black out."); status.Foreground = UiTheme.Accent; return; }
        if (operation.Id is "rotateImage" or "rotateVideo" && double.TryParse(Get("angle", "0"), NumberStyles.Float, CultureInfo.InvariantCulture, out double chosenAngle) && chosenAngle % 360 == 0 && Get("flip", "none") == "none")
        { status.Text = L.T("Choose a rotation or a flip first."); status.Foreground = UiTheme.Accent; return; }
        saving = CancellationTokenSource.CreateLinkedTokenSource(closing.Token);
        previewDelay.Stop();
        previewCancellation?.Cancel();
        transport?.Stop();
        player.Stop();
        player.Source = null;
        using var busy = busyLine.Begin();
        bodyPanel.IsEnabled = false;
        saveButton.IsEnabled = false;
        revealButton.Visibility = Visibility.Collapsed;
        copyButton.Visibility = Visibility.Collapsed;
        cancelButton.Visibility = Visibility.Visible;
        cancelButton.IsEnabled = true;
        status.Foreground = UiTheme.Muted;
        status.Text = L.T("You can cancel while it runs; the original is kept.");
        BatchResult? applied = null;
        try
        {
            var result = await submit(job, saving.Token, busy);
            var success = result.Files.Where(f => f.Output != null).ToArray();
            var failures = result.Files.Where(f => f.Error != null).ToArray();
            if (Saved != null && success.Length > 0 && failures.Length == 0)
            {
                if (Presets.Supported(operation.Id)) Presets.SaveLast(operation.Id, PresetValues());
                status.Text = L.T("Applied.");
                applied = result;
                return;
            }
            if (success.Length > 0)
            { lastOutput = success[^1].Output; revealButton.Visibility = Visibility.Visible; copyButton.Visibility = Visibility.Visible; if (Presets.Supported(operation.Id)) Presets.SaveLast(operation.Id, PresetValues()); }
            status.Text = failures.Length == 0 ? L.F("Saved {0}: {1}", success.Length, Path.GetFileName(lastOutput)) : L.F("{0} succeeded, {1} failed: {2}", success.Length, failures.Length, failures[0].Error);
            Journal.Write("ToolSaved", new { job.Action, success = success.Length, failures = failures.Length });
        }
        catch (OperationCanceledException) { status.Text = L.T("Cancelled. Adjust the settings and save again."); }
        catch (Exception ex) { status.Text = L.T("Save not completed: ") + ex.Message; status.Foreground = UiTheme.Accent; }
        finally
        {
            saving.Dispose(); saving = null; bodyPanel.IsEnabled = true; saveButton.IsEnabled = true; cancelButton.Visibility = Visibility.Collapsed;
            if (applied != null) Saved?.Invoke(applied);
        }
    }
    private async Task StepFrame(int direction)
    {
        if (Catalog.Category(paths[0]) != "video")
        { timeline.Value = Math.Clamp(timeline.Value + direction * .1, 0, totalDuration); return; }
        using var busy = busyLine.Begin();
        try
        { var job = Capture(); job.Parameters!["direction"] = direction.ToString(); job.Parameters["time"] = timeline.Value.ToString(CultureInfo.InvariantCulture); var info = await Backend.Preview(job, folder, closing.Token, "--frame-step"); timeline.Value = info.GetProperty("Time").GetDouble(); }
        catch (Exception ex) { status.Text = L.T("Frame step: ") + ex.Message; }
    }
    private async Task<JsonElement> PreparePlayback(bool effect, string source, double time, CancellationToken token)
    {
        using var busy = busyLine.Begin();
        var job = effect ? Capture() : new ConversionJob([source], "preview-original", new());
        job.Parameters!["time"] = time.ToString(CultureInfo.InvariantCulture);
        if (!effect)
            job.Parameters["fullPreview"] = "true";
        return await Backend.Preview(job, folder, token, "--playback");
    }
}
