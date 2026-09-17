//
//  Annotation.cs
//  Screenish
//
//  An editable annotation placed on a Shot's base bitmap. All geometry is in
//  image-pixel coordinates with a top-left origin (y grows downward), the same
//  space as the captured bitmap — so export needs no rescaling. Annotations are
//  immutable records: edits produce copies, which makes undo snapshots free.
//

using System.Collections.Immutable;
using System.Globalization;
using System.Windows;
using System.Windows.Media;

namespace Screenish;

internal enum AnnotationKind
{
    Arrow,
    Line,
    Rectangle,        // stroked
    RectangleFilled,  // filled
    Ellipse,
    Highlight,        // translucent marker rectangle
    Text,
    Blur,
    Pixelate,
    Counter,          // numbered step marker
    Spotlight,        // darkens everything outside an ellipse
    Pencil,           // freehand path
}

internal static class AnnotationKindExtensions
{
    /// Point-based kinds use Start/End; the rest use the derived Rect.
    public static bool IsLinear(this AnnotationKind k) => k is AnnotationKind.Arrow or AnnotationKind.Line;
    public static bool IsRedaction(this AnnotationKind k) => k is AnnotationKind.Blur or AnnotationKind.Pixelate;
    /// Freehand path stored in Points.
    public static bool IsPath(this AnnotationKind k) => k == AnnotationKind.Pencil;
}

internal enum ArrowStyle { Straight, Curved }

internal enum TextStyle { Standard, Rounded, Monospaced, Outlined, Boxed, RoundedBoxed, MonospacedBoxed }

internal static class TextStyleExtensions
{
    public static readonly TextStyle[] All = Enum.GetValues<TextStyle>();

    public static string Label(this TextStyle s) => s switch
    {
        TextStyle.Standard => Loc.T("Standard"),
        TextStyle.Rounded => Loc.T("Rounded"),
        TextStyle.Monospaced => Loc.T("Monospaced"),
        TextStyle.Outlined => Loc.T("Outlined"),
        TextStyle.Boxed => Loc.T("Boxed"),
        TextStyle.RoundedBoxed => Loc.T("Rounded Boxed"),
        _ => Loc.T("Monospaced Boxed"),
    };

    public static bool IsBoxed(this TextStyle s) =>
        s is TextStyle.Boxed or TextStyle.RoundedBoxed or TextStyle.MonospacedBoxed;
    public static bool IsOutlined(this TextStyle s) => s == TextStyle.Outlined;
    public static bool HasRoundedBox(this TextStyle s) => s == TextStyle.RoundedBoxed;
    private static bool IsMono(this TextStyle s) => s is TextStyle.Monospaced or TextStyle.MonospacedBoxed;
    private static bool IsRoundedFont(this TextStyle s) => s is TextStyle.Rounded or TextStyle.RoundedBoxed;

    // Windows has no rounded system font; fall through to the closest installed one.
    private static readonly FontFamily StandardFamily = new("Segoe UI");
    private static readonly FontFamily RoundedFamily = new("Arial Rounded MT Bold, Nunito, Varela Round, Segoe UI");
    private static readonly FontFamily MonoFamily = new("Cascadia Mono, Consolas, Courier New");

    public static FontFamily Family(this TextStyle s) =>
        s.IsMono() ? MonoFamily : s.IsRoundedFont() ? RoundedFamily : StandardFamily;

    public static Typeface Typeface(this TextStyle s) =>
        new(s.Family(), FontStyles.Normal, FontWeights.SemiBold, FontStretches.Normal);

    /// Inner padding for boxed styles (so glyphs aren't flush to the box edge).
    public static double BoxPadding(this TextStyle s, double fontSize) => s.IsBoxed() ? fontSize * 0.3 : 0;

    /// Outline width in pixels: the macOS stroke is max(3, size·0.08) percent of the font size.
    public static double OutlineWidth(double fontSize) => fontSize * Math.Max(3, fontSize * 0.08) / 100;
}

internal readonly record struct AnnotationStyle(
    Color Color,
    double LineWidth,
    double FontSize,
    ArrowStyle ArrowStyle = ArrowStyle.Straight,
    TextStyle TextStyle = TextStyle.Standard)
{
    public static readonly AnnotationStyle Default = new(Color.FromRgb(0xFF, 0x3B, 0x30), 9, 27);
}

internal sealed record Annotation
{
    public Guid Id { get; init; } = Guid.NewGuid();
    public required AnnotationKind Kind { get; init; }
    public Point Start { get; init; }   // image-pixel space
    public Point End { get; init; }
    public AnnotationStyle Style { get; init; }
    public string Text { get; init; } = "";
    public ImmutableList<Point> Points { get; init; } = ImmutableList<Point>.Empty;  // freehand path (pencil)
    public int Number { get; init; }    // step number (counter); 0 otherwise

    /// Normalized bounding rect for rect-based kinds.
    public Rect Rect => new(Math.Min(Start.X, End.X), Math.Min(Start.Y, End.Y),
                            Math.Abs(End.X - Start.X), Math.Abs(End.Y - Start.Y));

    /// Bounding rect that also covers a freehand path.
    public Rect BoundingRect
    {
        get
        {
            if (!Kind.IsPath() || Points.IsEmpty) return Rect;
            double minX = Points.Min(p => p.X), maxX = Points.Max(p => p.X);
            double minY = Points.Min(p => p.Y), maxY = Points.Max(p => p.Y);
            return new Rect(minX, minY, maxX - minX, maxY - minY);
        }
    }

    /// Radius of a counter marker.
    public double CounterRadius => Math.Max(Style.LineWidth * 2.2, 14);

    public Annotation MovedBy(double dx, double dy) => this with
    {
        Start = new Point(Start.X + dx, Start.Y + dy),
        End = new Point(End.X + dx, End.Y + dy),
        Points = Points.Select(p => new Point(p.X + dx, p.Y + dy)).ToImmutableList(),
    };

    /// Same annotation with its box height refitted to the (possibly multi-line) text.
    public Annotation WithFittedTextHeight()
    {
        var r = Rect;
        double h = TextLayout.FittedHeight(Text, r.Width, Style.FontSize, Style.TextStyle);
        return this with { Start = new Point(r.Left, r.Top), End = new Point(r.Right, r.Top + h) };
    }
}

internal static class TextLayout
{
    public static FormattedText Format(string text, double fontSize, TextStyle style, Brush brush, double maxWidth)
    {
        var formatted = new FormattedText(text, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight,
                                          style.Typeface(), Math.Max(fontSize, 1), brush, 1.0)
        {
            MaxTextWidth = Math.Max(maxWidth, 1),
        };
        return formatted;
    }

    /// Height (image-pixel space) text needs at a given box width and style.
    /// Shared by inline editing (commit/refit) and toolbar size changes.
    public static double FittedHeight(string text, double width, double fontSize, TextStyle style)
    {
        double pad = style.BoxPadding(fontSize);
        double textWidth = Math.Max(width - pad * 2, 1);
        if (text.Length == 0 || textWidth <= 1) return fontSize * 1.4 + pad * 2;
        var formatted = Format(text, fontSize, style, Brushes.Black, textWidth);
        return Math.Max(Math.Ceiling(formatted.Height), fontSize * 1.4) + pad * 2;
    }
}
