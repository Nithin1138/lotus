using System;
using System.Collections.Generic;
using System.Collections.Specialized;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Brush = System.Windows.Media.Brush;
using Brushes = System.Windows.Media.Brushes;
using Color = System.Windows.Media.Color;
using Forms = System.Windows.Forms;
using Point = System.Windows.Point;

namespace DropDial;

// MARK: - Floating Shelf Item Card
internal sealed class FloatShelfItemCard : Border
{
    public string FilePath { get; }
    private readonly Action<string> onRemove;
    private readonly Action<string> onSelect;
    private readonly Action<string[]>? onConvert;
    private readonly Action<string[]>? onTools;
    private Point dragStartPoint;
    private bool isDragging;

    public FloatShelfItemCard(
        string filePath,
        Action<string> onRemove,
        Action<string> onSelect,
        Action<string[]>? onConvert = null,
        Action<string[]>? onTools = null)
    {
        FilePath = filePath;
        this.onRemove = onRemove;
        this.onSelect = onSelect;
        this.onConvert = onConvert;
        this.onTools = onTools;

        CornerRadius = new CornerRadius(10);
        Background = new SolidColorBrush(Color.FromArgb(220, 36, 40, 46));
        BorderBrush = new SolidColorBrush(Color.FromArgb(40, 255, 255, 255));
        BorderThickness = new Thickness(1);
        Margin = new Thickness(0, 0, 0, 8);
        Height = 56;
        Cursor = Cursors.Hand;

        var grid = new Grid { Margin = new Thickness(8, 6, 8, 6) };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(40) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        // 1. Icon / Thumbnail
        var iconImg = new System.Windows.Controls.Image
        {
            Width = 34,
            Height = 34,
            VerticalAlignment = VerticalAlignment.Center,
            HorizontalAlignment = HorizontalAlignment.Center
        };
        try
        {
            iconImg.Source = GetFileThumbnail(filePath);
        }
        catch
        {
            iconImg.Source = AppIcon.Window;
        }
        Grid.SetColumn(iconImg, 0);
        grid.Children.Add(iconImg);

        // 2. File Name & Details
        var textStack = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(8, 0, 4, 0) };
        string name = Path.GetFileName(filePath);
        if (string.IsNullOrEmpty(name)) name = filePath;

        var nameText = new TextBlock
        {
            Text = name,
            FontWeight = FontWeights.SemiBold,
            FontSize = 12,
            Foreground = Brushes.White,
            TextTrimming = TextTrimming.CharacterEllipsis
        };
        textStack.Children.Add(nameText);

        string detailStr = GetFileDetailString(filePath);
        var detailText = new TextBlock
        {
            Text = detailStr,
            FontSize = 10,
            Foreground = new SolidColorBrush(Color.FromRgb(160, 166, 176)),
            Margin = new Thickness(0, 2, 0, 0)
        };
        textStack.Children.Add(detailText);

        Grid.SetColumn(textStack, 1);
        grid.Children.Add(textStack);

        // 3. Hover Actions (Convert, Tools, Reveal, Remove)
        var actionsPanel = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            VerticalAlignment = VerticalAlignment.Center,
            Visibility = Visibility.Collapsed
        };

        if (onConvert != null)
        {
            var convertBtn = CreateHoverButton("🔄", "Convert with DropDial", () => onConvert([filePath]));
            actionsPanel.Children.Add(convertBtn);
        }
        if (onTools != null)
        {
            var toolsBtn = CreateHoverButton("🛠", "Tools in DropDial", () => onTools([filePath]));
            actionsPanel.Children.Add(toolsBtn);
        }

        var revealBtn = CreateHoverButton("📁", "Reveal in File Explorer", () => ExplorerIntegration.Reveal(filePath));
        var removeBtn = CreateHoverButton("×", "Remove from Shelf", () => onRemove(filePath));

        actionsPanel.Children.Add(revealBtn);
        actionsPanel.Children.Add(removeBtn);

        Grid.SetColumn(actionsPanel, 2);
        grid.Children.Add(actionsPanel);

        Child = grid;

        // Hover effect: show action buttons & highlight border
        MouseEnter += (_, _) =>
        {
            actionsPanel.Visibility = Visibility.Visible;
            BorderBrush = UiTheme.Accent;
            Background = new SolidColorBrush(Color.FromArgb(240, 48, 54, 62));
        };
        MouseLeave += (_, _) =>
        {
            actionsPanel.Visibility = Visibility.Collapsed;
            BorderBrush = new SolidColorBrush(Color.FromArgb(40, 255, 255, 255));
            Background = new SolidColorBrush(Color.FromArgb(220, 36, 40, 46));
        };

        // Drag Out & Click events
        PreviewMouseLeftButtonDown += (_, e) =>
        {
            dragStartPoint = e.GetPosition(this);
            isDragging = false;
        };

        PreviewMouseMove += (_, e) =>
        {
            if (e.LeftButton == MouseButtonState.Pressed && !isDragging)
            {
                Point current = e.GetPosition(this);
                if (Math.Abs(current.X - dragStartPoint.X) > 4 || Math.Abs(current.Y - dragStartPoint.Y) > 4)
                {
                    isDragging = true;
                    var data = new DataObject(DataFormats.FileDrop, new string[] { FilePath });
                    DragDrop.DoDragDrop(this, data, DragDropEffects.Copy);
                    isDragging = false;
                }
            }
        };

        MouseLeftButtonUp += (_, e) =>
        {
            if (!isDragging)
            {
                if (e.ClickCount == 2)
                {
                    try { Process.Start(new ProcessStartInfo(FilePath) { UseShellExecute = true }); } catch { }
                }
                else
                {
                    onSelect(FilePath);
                }
            }
        };

        // Context Menu
        ContextMenu = BuildContextMenu();
    }

    private ContextMenu BuildContextMenu()
    {
        var menu = new ContextMenu();

        var convertItem = new MenuItem { Header = "Convert with DropDial..." };
        convertItem.Click += (_, _) => onConvert?.Invoke([FilePath]);
        menu.Items.Add(convertItem);

        var toolsItem = new MenuItem { Header = "Tools in DropDial..." };
        toolsItem.Click += (_, _) => onTools?.Invoke([FilePath]);
        menu.Items.Add(toolsItem);

        menu.Items.Add(new Separator());

        var revealItem = new MenuItem { Header = "Reveal in File Explorer" };
        revealItem.Click += (_, _) => ExplorerIntegration.Reveal(FilePath);
        menu.Items.Add(revealItem);

        var copyItem = new MenuItem { Header = "Copy File" };
        copyItem.Click += (_, _) =>
        {
            try
            {
                var col = new StringCollection { FilePath };
                Clipboard.SetFileDropList(col);
            }
            catch { }
        };
        menu.Items.Add(copyItem);

        var copyPathItem = new MenuItem { Header = "Copy Path" };
        copyPathItem.Click += (_, _) =>
        {
            try { Clipboard.SetText(FilePath); } catch { }
        };
        menu.Items.Add(copyPathItem);

        menu.Items.Add(new Separator());

        var removeItem = new MenuItem { Header = "Remove from Shelf" };
        removeItem.Click += (_, _) => onRemove(FilePath);
        menu.Items.Add(removeItem);

        return menu;
    }

    private Button CreateHoverButton(string text, string tooltip, Action onClick)
    {
        var btn = new Button
        {
            Content = text,
            Width = 24,
            Height = 24,
            Margin = new Thickness(2, 0, 0, 0),
            Background = Brushes.Transparent,
            Foreground = new SolidColorBrush(Color.FromRgb(200, 206, 216)),
            BorderThickness = new Thickness(0),
            FontSize = 13,
            FontWeight = FontWeights.Bold,
            ToolTip = tooltip,
            Cursor = Cursors.Hand
        };
        btn.Click += (_, e) =>
        {
            e.Handled = true;
            onClick();
        };
        return btn;
    }

    private static string GetFileDetailString(string path)
    {
        try
        {
            if (Directory.Exists(path))
            {
                int count = Directory.GetFileSystemEntries(path).Length;
                return $"Folder • {count} {(count == 1 ? "item" : "items")}";
            }
            if (File.Exists(path))
            {
                long bytes = new FileInfo(path).Length;
                string sizeStr = FormatBytes(bytes);
                string ext = Path.GetExtension(path).TrimStart('.').ToUpperInvariant();
                if (string.IsNullOrEmpty(ext)) ext = "FILE";
                return $"{sizeStr} • {ext}";
            }
        }
        catch { }
        return "FILE";
    }

    private static string FormatBytes(long bytes)
    {
        if (bytes < 1024) return $"{bytes} B";
        if (bytes < 1024 * 1024) return $"{(bytes / 1024.0):F1} KB";
        if (bytes < 1024 * 1024 * 1024) return $"{(bytes / (1024.0 * 1024)):F1} MB";
        return $"{(bytes / (1024.0 * 1024 * 1024)):F2} GB";
    }

    private static ImageSource GetFileThumbnail(string path)
    {
        try
        {
            if (File.Exists(path))
            {
                string ext = Path.GetExtension(path).ToLowerInvariant();
                if (ext is ".jpg" or ".jpeg" or ".png" or ".webp" or ".bmp" or ".gif")
                {
                    var bmp = new BitmapImage();
                    bmp.BeginInit();
                    bmp.UriSource = new Uri(path);
                    bmp.DecodePixelWidth = 72;
                    bmp.CacheOption = BitmapCacheOption.OnLoad;
                    bmp.EndInit();
                    bmp.Freeze();
                    return bmp;
                }
            }

            using var icon = System.Drawing.Icon.ExtractAssociatedIcon(path);
            if (icon != null)
            {
                var bs = Imaging.CreateBitmapSourceFromHIcon(
                    icon.Handle,
                    Int32Rect.Empty,
                    BitmapSizeOptions.FromEmptyOptions());
                bs.Freeze();
                return bs;
            }
        }
        catch { }

        return AppIcon.Window;
    }
}

// MARK: - Floating Shelf Window
internal sealed class FloatShelfWindow : Window
{
    private static FloatShelfWindow? instance;
    public static FloatShelfWindow Instance => instance ??= new FloatShelfWindow();

    public void ShowWindow()
    {
        if (WindowState == WindowState.Minimized) WindowState = WindowState.Normal;
        Show();
        Activate();
    }

    private readonly List<string> floatedPaths = [];
    private string? selectedPath;
    private readonly StackPanel itemsStack;
    private readonly ScrollViewer scroller;
    private readonly Border emptyState;
    private readonly TextBlock countBadge;
    private readonly Button dragAllBtn;
    private readonly Border dropOverlay;

    public Action<string[], Operation>? OnExecuteOperation { get; set; }

    public FloatShelfWindow()
    {
        Title = "DropDial Floating Shelf";
        Width = 270;
        Height = 440;
        WindowStyle = WindowStyle.None;
        ResizeMode = ResizeMode.NoResize;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        Topmost = true;
        ShowInTaskbar = false;
        FontFamily = UiTheme.Font;

        // Position on right edge of primary screen
        var workingArea = Forms.Screen.PrimaryScreen?.WorkingArea ?? new System.Drawing.Rectangle(0, 0, 1920, 1080);
        Left = workingArea.Right - Width - 24;
        Top = (workingArea.Height - Height) / 2;

        var rootGrid = new Grid();

        // Background Outer Card with Glassmorphic styling
        var outerBorder = new Border
        {
            CornerRadius = new CornerRadius(16),
            Background = new SolidColorBrush(Color.FromArgb(235, 20, 22, 26)),
            BorderBrush = new SolidColorBrush(Color.FromArgb(60, 255, 255, 255)),
            BorderThickness = new Thickness(1),
            Margin = new Thickness(8)
        };
        outerBorder.Effect = new System.Windows.Media.Effects.DropShadowEffect
        {
            BlurRadius = 24,
            ShadowDepth = 6,
            Opacity = 0.45,
            Color = Colors.Black
        };

        var contentGrid = new Grid { Margin = new Thickness(12, 12, 12, 12) };
        contentGrid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto }); // Header
        contentGrid.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) }); // Items
        contentGrid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto }); // Bottom Bar

        // 1. Header (Title, Badge, Add, Close)
        var headerGrid = new Grid { Margin = new Thickness(2, 0, 2, 12) };
        headerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        headerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        headerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        headerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        headerGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var titleText = new TextBlock
        {
            Text = "Floating Shelf",
            FontSize = 13,
            FontWeight = FontWeights.Bold,
            Foreground = Brushes.White,
            VerticalAlignment = VerticalAlignment.Center
        };
        Grid.SetColumn(titleText, 0);
        headerGrid.Children.Add(titleText);

        countBadge = new TextBlock
        {
            Text = "0",
            FontSize = 10,
            FontWeight = FontWeights.Bold,
            Foreground = Brushes.White,
            Background = UiTheme.Accent,
            Padding = new Thickness(6, 1, 6, 1),
            Margin = new Thickness(8, 0, 0, 0),
            VerticalAlignment = VerticalAlignment.Center
        };
        var badgeBorder = new Border
        {
            CornerRadius = new CornerRadius(8),
            Background = UiTheme.Accent,
            Margin = new Thickness(6, 0, 0, 0),
            Child = countBadge
        };
        Grid.SetColumn(badgeBorder, 1);
        headerGrid.Children.Add(badgeBorder);

        var addBtn = new Button
        {
            Content = "+ Add",
            FontSize = 11,
            FontWeight = FontWeights.SemiBold,
            Background = Brushes.Transparent,
            Foreground = UiTheme.Accent,
            BorderThickness = new Thickness(0),
            Margin = new Thickness(0, 0, 6, 0),
            Cursor = Cursors.Hand
        };
        addBtn.Click += (_, _) => BrowseFiles();
        Grid.SetColumn(addBtn, 3);
        headerGrid.Children.Add(addBtn);

        var closeBtn = new Button
        {
            Content = "×",
            FontSize = 16,
            FontWeight = FontWeights.Bold,
            Background = Brushes.Transparent,
            Foreground = new SolidColorBrush(Color.FromRgb(160, 166, 176)),
            BorderThickness = new Thickness(0),
            Width = 20,
            Height = 20,
            Cursor = Cursors.Hand
        };
        closeBtn.Click += (_, _) => HideShelf();
        Grid.SetColumn(closeBtn, 4);
        headerGrid.Children.Add(closeBtn);

        Grid.SetRow(headerGrid, 0);
        contentGrid.Children.Add(headerGrid);

        // 2. Middle Body: ScrollViewer / StackPanel
        itemsStack = new StackPanel();
        scroller = new ScrollViewer
        {
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
            Content = itemsStack
        };
        Grid.SetRow(scroller, 1);
        contentGrid.Children.Add(scroller);

        // Empty state placeholder
        emptyState = CreateEmptyState();
        Grid.SetRow(emptyState, 1);
        contentGrid.Children.Add(emptyState);

        // 3. Bottom Action Bar: Clear, Share, Drag All
        var bottomGrid = new Grid { Margin = new Thickness(0, 10, 0, 0) };
        bottomGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        bottomGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        bottomGrid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

        var clearBtn = new Button
        {
            Content = "Clear",
            Height = 28,
            Padding = new Thickness(10, 0, 10, 0),
            Background = new SolidColorBrush(Color.FromArgb(40, 255, 255, 255)),
            Foreground = new SolidColorBrush(Color.FromRgb(200, 206, 216)),
            BorderThickness = new Thickness(0),
            FontSize = 11,
            Cursor = Cursors.Hand
        };
        clearBtn.Click += (_, _) => ClearAll();
        Grid.SetColumn(clearBtn, 0);
        bottomGrid.Children.Add(clearBtn);

        var shareBtn = new Button
        {
            Content = "Share",
            Height = 28,
            Margin = new Thickness(6, 0, 0, 0),
            Padding = new Thickness(10, 0, 10, 0),
            Background = new SolidColorBrush(Color.FromArgb(40, 255, 255, 255)),
            Foreground = new SolidColorBrush(Color.FromRgb(200, 206, 216)),
            BorderThickness = new Thickness(0),
            FontSize = 11,
            Cursor = Cursors.Hand,
            ToolTip = "Copy files to clipboard & reveal in Explorer"
        };
        shareBtn.Click += (_, _) => ShareAll();
        Grid.SetColumn(shareBtn, 1);
        bottomGrid.Children.Add(shareBtn);

        dragAllBtn = new Button
        {
            Content = "Drag All",
            Height = 28,
            Margin = new Thickness(6, 0, 0, 0),
            Background = UiTheme.Accent,
            Foreground = Brushes.White,
            BorderThickness = new Thickness(0),
            FontWeight = FontWeights.Bold,
            FontSize = 11,
            Cursor = Cursors.Hand,
            ToolTip = "Drag this button to drop all files, or click to copy them"
        };
        SetupDragAllButton(dragAllBtn);
        Grid.SetColumn(dragAllBtn, 2);
        bottomGrid.Children.Add(dragAllBtn);

        Grid.SetRow(bottomGrid, 2);
        contentGrid.Children.Add(bottomGrid);

        outerBorder.Child = contentGrid;
        rootGrid.Children.Add(outerBorder);

        // Drop Highlight Overlay (When dragging files over the shelf)
        dropOverlay = new Border
        {
            CornerRadius = new CornerRadius(16),
            Background = new SolidColorBrush(Color.FromArgb(200, 213, 84, 24)),
            BorderBrush = UiTheme.Accent,
            BorderThickness = new Thickness(2),
            Margin = new Thickness(8),
            Visibility = Visibility.Collapsed,
            IsHitTestVisible = false
        };
        var dropOverlayText = new TextBlock
        {
            Text = "Drop files here to add to shelf",
            FontSize = 13,
            FontWeight = FontWeights.Bold,
            Foreground = Brushes.White,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center
        };
        dropOverlay.Child = dropOverlayText;
        rootGrid.Children.Add(dropOverlay);

        Content = rootGrid;

        // Allow window dragging from background
        MouseDown += (_, e) =>
        {
            if (e.ChangedButton == MouseButton.Left)
                DragMove();
        };

        // Drag & Drop acceptance
        AllowDrop = true;
        DragEnter += (_, e) =>
        {
            if (e.Data.GetDataPresent(DataFormats.FileDrop))
            {
                dropOverlay.Visibility = Visibility.Visible;
                e.Effects = DragDropEffects.Copy;
            }
        };
        DragLeave += (_, _) => dropOverlay.Visibility = Visibility.Collapsed;
        Drop += (_, e) =>
        {
            dropOverlay.Visibility = Visibility.Collapsed;
            if (e.Data.GetData(DataFormats.FileDrop) is string[] files)
            {
                AddFiles(files);
            }
        };

        // ESC key hides shelf, Space key triggers quick preview
        KeyDown += (_, e) =>
        {
            if (e.Key == Key.Escape)
                HideShelf();
            else if (e.Key == Key.Space)
            {
                string? target = selectedPath ?? floatedPaths.FirstOrDefault();
                if (!string.IsNullOrEmpty(target))
                {
                    e.Handled = true;
                    try { Process.Start(new ProcessStartInfo(target) { UseShellExecute = true }); } catch { }
                }
            }
        };

        RefreshUI();
    }

    private Border CreateEmptyState()
    {
        var panel = new StackPanel
        {
            VerticalAlignment = VerticalAlignment.Center,
            HorizontalAlignment = HorizontalAlignment.Center,
            Margin = new Thickness(16)
        };

        var iconText = new TextBlock
        {
            Text = "📥",
            FontSize = 28,
            HorizontalAlignment = HorizontalAlignment.Center,
            Margin = new Thickness(0, 0, 0, 8)
        };
        panel.Children.Add(iconText);

        var title = new TextBlock
        {
            Text = "Drop Files Here",
            FontSize = 12,
            FontWeight = FontWeights.Bold,
            Foreground = Brushes.White,
            HorizontalAlignment = HorizontalAlignment.Center,
            Margin = new Thickness(0, 0, 0, 4)
        };
        panel.Children.Add(title);

        var subtitle = new TextBlock
        {
            Text = "Keep files handy while switching apps and folders.",
            FontSize = 10,
            Foreground = new SolidColorBrush(Color.FromRgb(150, 156, 166)),
            TextWrapping = TextWrapping.Wrap,
            TextAlignment = TextAlignment.Center,
            Margin = new Thickness(0, 0, 0, 14)
        };
        panel.Children.Add(subtitle);

        var browseBtn = new Button
        {
            Content = "+ Add Files...",
            Height = 26,
            Padding = new Thickness(14, 0, 14, 0),
            Background = new SolidColorBrush(Color.FromArgb(40, 255, 255, 255)),
            Foreground = Brushes.White,
            BorderThickness = new Thickness(0),
            FontSize = 11,
            Cursor = Cursors.Hand
        };
        browseBtn.Click += (_, _) => BrowseFiles();
        panel.Children.Add(browseBtn);

        return new Border
        {
            CornerRadius = new CornerRadius(10),
            Background = new SolidColorBrush(Color.FromArgb(40, 255, 255, 255)),
            BorderBrush = new SolidColorBrush(Color.FromArgb(30, 255, 255, 255)),
            BorderThickness = new Thickness(1),
            Child = panel
        };
    }

    private void SetupDragAllButton(Button btn)
    {
        Point startPoint = default;
        bool dragging = false;

        btn.PreviewMouseLeftButtonDown += (_, e) =>
        {
            startPoint = e.GetPosition(btn);
            dragging = false;
        };

        btn.PreviewMouseMove += (_, e) =>
        {
            if (e.LeftButton == MouseButtonState.Pressed && !dragging && floatedPaths.Count > 0)
            {
                Point current = e.GetPosition(btn);
                if (Math.Abs(current.X - startPoint.X) > 4 || Math.Abs(current.Y - startPoint.Y) > 4)
                {
                    dragging = true;
                    var data = new DataObject(DataFormats.FileDrop, floatedPaths.ToArray());
                    DragDrop.DoDragDrop(btn, data, DragDropEffects.Copy);
                    dragging = false;
                }
            }
        };

        btn.Click += (_, _) =>
        {
            if (!dragging && floatedPaths.Count > 0)
            {
                try
                {
                    var col = new StringCollection();
                    col.AddRange(floatedPaths.ToArray());
                    Clipboard.SetFileDropList(col);

                    string oldText = (string)btn.Content;
                    btn.Content = "Copied ✓";
                    var timer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(1.2) };
                    timer.Tick += (_, _) =>
                    {
                        timer.Stop();
                        btn.Content = oldText;
                    };
                    timer.Start();
                }
                catch { }
            }
        };
    }

    public void AddFiles(IEnumerable<string> paths)
    {
        foreach (var p in paths)
        {
            string clean = p?.Trim() ?? "";
            if (!string.IsNullOrEmpty(clean) && (File.Exists(clean) || Directory.Exists(clean)))
            {
                if (!floatedPaths.Contains(clean))
                {
                    floatedPaths.Insert(0, clean); // Newest on top
                }
            }
        }
        RefreshUI();
        ShowShelf();
    }

    public void RemoveFile(string path)
    {
        floatedPaths.Remove(path);
        RefreshUI();
    }

    public void ClearAll()
    {
        floatedPaths.Clear();
        RefreshUI();
    }

    private void RefreshUI()
    {
        countBadge.Text = floatedPaths.Count.ToString();
        itemsStack.Children.Clear();

        if (floatedPaths.Count == 0)
        {
            selectedPath = null;
            emptyState.Visibility = Visibility.Visible;
            scroller.Visibility = Visibility.Collapsed;
            dragAllBtn.IsEnabled = false;
        }
        else
        {
            if (selectedPath == null || !floatedPaths.Contains(selectedPath))
                selectedPath = floatedPaths[0];

            emptyState.Visibility = Visibility.Collapsed;
            scroller.Visibility = Visibility.Visible;
            dragAllBtn.IsEnabled = true;

            foreach (var p in floatedPaths)
            {
                var card = new FloatShelfItemCard(
                    p,
                    onRemove: RemoveFile,
                    onSelect: selected => { selectedPath = selected; },
                    onConvert: files => TriggerWheelForFiles(files, tools: false),
                    onTools: files => TriggerWheelForFiles(files, tools: true)
                );
                itemsStack.Children.Add(card);
            }
        }
    }

    public void ShareAll()
    {
        if (floatedPaths.Count == 0) return;
        try
        {
            var col = new StringCollection();
            col.AddRange(floatedPaths.ToArray());
            Clipboard.SetFileDropList(col);
            ExplorerIntegration.Reveal(floatedPaths[0]);
        }
        catch { }
    }

    private void TriggerWheelForFiles(string[] files, bool tools)
    {
        if (files.Length == 0) return;
        Native.GetCursorPos(out var pt);
        // Find main window or trigger wheel
        Dispatcher.Invoke(() =>
        {
            if (OnExecuteOperation != null && files.Length > 0)
            {
                var options = Catalog.Options(files, tools);
                if (options.Count > 0)
                {
                    OnExecuteOperation(files, options[0]);
                }
            }
        });
    }

    private void BrowseFiles()
    {
        var dlg = new Forms.OpenFileDialog
        {
            Multiselect = true,
            Title = "Add Files to Floating Shelf"
        };
        if (dlg.ShowDialog() == Forms.DialogResult.OK)
        {
            AddFiles(dlg.FileNames);
        }
    }

    public void ShowShelf()
    {
        if (!IsVisible) Show();
        Activate();
    }

    public void HideShelf()
    {
        Hide();
    }

    public void ToggleShelf()
    {
        if (IsVisible) HideShelf(); else ShowShelf();
    }
}
