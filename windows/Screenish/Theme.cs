//
//  Theme.cs
//  Screenish
//
//  Light/dark palette following the Windows app-mode setting, the vector icon
//  set (the macOS client uses SF Symbols; these are drawn to match), and small
//  UI factory helpers shared by the windows.
//

using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Shapes;
using Microsoft.Win32;

namespace Screenish;

internal static class Theme
{
    public static bool IsDark { get; private set; }

    public static readonly Color Accent = Color.FromRgb(0x0A, 0x84, 0xFF);
    public static readonly SolidColorBrush AccentBrush = Frozen(Accent);

    public static void Apply(Application app)
    {
        app.Resources.MergedDictionaries.Add((ResourceDictionary)Application.LoadComponent(
            new Uri("/Screenish;component/Theme.xaml", UriKind.Relative)));
        Refresh(app);
        SystemEvents.UserPreferenceChanged += (_, e) =>
        {
            if (e.Category == UserPreferenceCategory.General)
                app.Dispatcher.BeginInvoke(() => Refresh(app));
        };
    }

    private static void Refresh(Application app)
    {
        IsDark = ReadIsDark();
        var r = app.Resources;
        r["WindowBg"] = Frozen(IsDark ? Rgb(0x2B2B2B) : Rgb(0xF3F3F3));
        r["PanelBg"] = Frozen(IsDark ? Rgb(0x323232) : Rgb(0xFFFFFF));
        r["CanvasBg"] = Frozen(IsDark ? Rgb(0x1C1C1C) : Rgb(0xDCDCDC));
        r["Fg"] = Frozen(IsDark ? Rgb(0xF2F2F2) : Rgb(0x1B1B1B));
        r["FgSecondary"] = Frozen(IsDark ? Rgb(0xA8A8A8) : Rgb(0x5F5F5F));
        r["FgTertiary"] = Frozen(IsDark ? Rgb(0x7C7C7C) : Rgb(0x8E8E8E));
        r["Divider"] = Frozen(IsDark ? Rgb(0x454545) : Rgb(0xD6D6D6));
        r["ControlBg"] = Frozen(IsDark ? Rgb(0x3C3C3C) : Rgb(0xFFFFFF));
        r["ControlBgHover"] = Frozen(IsDark ? Rgb(0x484848) : Rgb(0xF0F0F0));
        r["ControlBgPressed"] = Frozen(IsDark ? Rgb(0x545454) : Rgb(0xE2E2E2));
        r["ControlBorder"] = Frozen(IsDark ? Rgb(0x565656) : Rgb(0xC8C8C8));
        r["Accent"] = AccentBrush;
        r["AccentSoft"] = Frozen(Color.FromArgb(0x4D, Accent.R, Accent.G, Accent.B));   // 30 %
    }

    private static bool ReadIsDark()
    {
        try
        {
            using var key = Registry.CurrentUser.OpenSubKey(
                @"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
            return key?.GetValue("AppsUseLightTheme") is int value && value == 0;
        }
        catch { return false; }
    }

    private static Color Rgb(int hex) =>
        Color.FromRgb((byte)((hex >> 16) & 0xFF), (byte)((hex >> 8) & 0xFF), (byte)(hex & 0xFF));

    public static SolidColorBrush Frozen(Color color)
    {
        var brush = new SolidColorBrush(color);
        brush.Freeze();
        return brush;
    }

    // MARK: - UI helpers

    public static System.Windows.Style StyleOf(string key) => (System.Windows.Style)Application.Current.FindResource(key);

    /// Common window chrome: theme background/foreground, crisp text + layout.
    public static void Prepare(Window window)
    {
        window.SetResourceReference(Control.BackgroundProperty, "WindowBg");
        window.SetResourceReference(Control.ForegroundProperty, "Fg");
        window.FontFamily = new FontFamily("Segoe UI Variable Text, Segoe UI");
        window.FontSize = 13;
        window.UseLayoutRounding = true;
        TextOptions.SetTextFormattingMode(window, TextFormattingMode.Display);
        window.Icon = System.Windows.Media.Imaging.BitmapFrame.Create(
            new Uri("pack://application:,,,/Assets/Screenish.ico"));
    }

    public static TextBlock Text(string text, string brushKey = "Fg", double size = 13, FontWeight? weight = null)
    {
        var block = new TextBlock { Text = text, FontSize = size, VerticalAlignment = VerticalAlignment.Center };
        if (weight is FontWeight w) block.FontWeight = w;
        block.SetResourceReference(TextBlock.ForegroundProperty, brushKey);
        return block;
    }

    public static Border Divider(bool vertical = false)
    {
        var line = new Border();
        if (vertical) line.Width = 1; else line.Height = 1;
        line.SetResourceReference(Border.BackgroundProperty, "Divider");
        return line;
    }
}

/// Vector icons on a 20×20 grid, tinted with the current foreground.
internal static class Icons
{
    public const string Select = "F M5,2.5 L5,16 L8.4,12.8 L10.8,18 L13,17 L10.6,11.9 L15.2,11.6 Z";
    public const string Arrow = "M4.5,15.5 L15,5 M8,4.8 L15.2,4.8 L15.2,12";
    public const string ArrowCurved = "M4,16 Q4.5,6.5 14,6 M10.2,2.6 L14.4,6 L10.6,9.8";
    public const string Line = "M4.5,15.5 L15.5,4.5";
    public const string Rectangle = "M3.5,5 H16.5 V15 H3.5 Z";
    public const string RectangleFilled = "F M3,4.5 H17 V15.5 H3 Z";
    public const string Ellipse = "M10,3.5 A6.5,6.5 0 1 1 9.99,3.5 Z";
    public const string Highlight = "M8,15.5 L4.5,12 L12.5,4 L16,7.5 Z M4.5,12 L3.5,16.5 L8,15.5 M3,18 H9";
    public const string Text = "M4.5,6.5 V4.5 H15.5 V6.5 M10,4.5 V15.5 M7.5,15.5 H12.5";
    public const string Blur = "F M10,2.5 C10,2.5 4.5,9 4.5,12.5 A5.5,5.5 0 0 0 15.5,12.5 C15.5,9 10,2.5 10,2.5 Z";
    public const string Pixelate = "F M3,3 h4.4 v4.4 h-4.4 Z M12.6,3 h4.4 v4.4 h-4.4 Z M7.8,7.8 h4.4 v4.4 h-4.4 Z " +
                                   "M3,12.6 h4.4 v4.4 h-4.4 Z M12.6,12.6 h4.4 v4.4 h-4.4 Z";
    public const string Counter = "F M10,2.5 A7.5,7.5 0 1 1 9.99,2.5 Z M8.3,7.6 L10.4,6 H11.3 V14.2 H9.9 V7.9 L8.3,9 Z";
    public const string Spotlight = "F M10,6 A4,4 0 1 1 9.99,6 Z";
    public const string SpotlightRing = "M10,2.5 A7.5,7.5 0 1 1 9.99,2.5 Z";
    public const string Pencil = "M4,16 L5,12.2 L13.2,4 L16,6.8 L7.8,15 Z M11.4,5.8 L14.2,8.6";
    public const string Crop = "M6,2.5 V14 H17.5 M2.5,6 H14 V17.5";
    public const string Undo = "M7.5,4.5 L3.8,8.2 L7.5,11.9 M4,8.2 H12 A4,4 0 0 1 12,16.2 H8.5";
    public const string Redo = "M12.5,4.5 L16.2,8.2 L12.5,11.9 M16,8.2 H8 A4,4 0 0 0 8,16.2 H11.5";
    public const string Trash = "M4,6 H16 M8,6 V4 H12 V6 M5.5,6 L6.4,17 H13.6 L14.5,6 M8.6,9 V14 M11.4,9 V14";
    public const string TrashSlash = Trash + " M3,3 L17,17";
    public const string LineWeight = "F M3,4 h14 v1.2 h-14 Z M3,8 h14 v2.6 h-14 Z M3,13.2 h14 v4 h-14 Z";
    public const string NoSign = "M10,3 A7,7 0 1 1 9.99,3 Z M5.2,5.2 L14.8,14.8";
    public const string Hand = "M10,2.5 V17.5 M2.5,10 H17.5 M7.6,4.9 L10,2.5 L12.4,4.9 M7.6,15.1 L10,17.5 L12.4,15.1 " +
                               "M4.9,7.6 L2.5,10 L4.9,12.4 M15.1,7.6 L17.5,10 L15.1,12.4";
    public const string Social = "M3.5,5.5 H11 V17 H3.5 Z M7,5.5 V3 H16.5 V14.5 H11";
    public const string ChevronDown = "M5.5,8 L10,12.5 L14.5,8";
    public const string Close = "M6,6 L14,14 M14,6 L6,14";

    /// An icon element. Data starting with "F " is filled; everything else is stroked.
    public static FrameworkElement Make(string data, double size = 16, string brushKey = "Fg")
    {
        bool filled = data.StartsWith("F ");
        var path = new Path
        {
            Data = Geometry.Parse(filled ? "F0 " + data[2..] : data),
            Width = 20, Height = 20, Stretch = Stretch.None,
            StrokeThickness = 1.5, StrokeLineJoin = PenLineJoin.Round,
            StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round,
        };
        path.SetResourceReference(filled ? Shape.FillProperty : Shape.StrokeProperty, brushKey);
        return new Viewbox { Width = size, Height = size, Child = path };
    }

    public static FrameworkElement ForTool(EditorTool tool)
    {
        if (tool == EditorTool.Spotlight)
        {
            // Dashed ring + solid core.
            var grid = new Grid { Width = 20, Height = 20 };
            var ring = new Path
            {
                Data = Geometry.Parse(SpotlightRing), StrokeThickness = 1.5,
                StrokeDashArray = [2, 1.6],
            };
            ring.SetResourceReference(Shape.StrokeProperty, "Fg");
            var core = new Path { Data = Geometry.Parse("F0 " + Spotlight[2..]) };
            core.SetResourceReference(Shape.FillProperty, "Fg");
            grid.Children.Add(ring);
            grid.Children.Add(core);
            return new Viewbox { Width = 16, Height = 16, Child = grid };
        }
        return Make(tool switch
        {
            EditorTool.Select => Select,
            EditorTool.Arrow => Arrow,
            EditorTool.Line => Line,
            EditorTool.Rectangle => Rectangle,
            EditorTool.RectangleFilled => RectangleFilled,
            EditorTool.Ellipse => Ellipse,
            EditorTool.Highlight => Highlight,
            EditorTool.Text => Text,
            EditorTool.Blur => Blur,
            EditorTool.Pixelate => Pixelate,
            EditorTool.Counter => Counter,
            EditorTool.Pencil => Pencil,
            _ => Crop,
        });
    }
}
