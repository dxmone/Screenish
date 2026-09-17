//
//  BackgroundRenderer.cs
//  Screenish
//
//  Wraps the annotated (and cropped) image in padding + background + rounded
//  corners + shadow, sized to an optional aspect ratio. Resolution-independent:
//  all sizes derive from fractions of the inner image.
//

using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace Screenish;

/// Geometry of the beautified canvas. The "card" is the image plus its inset
/// frame (this is what gets rounded corners + shadow); padding surrounds the
/// card; the whole thing is the outer canvas (optionally aspect-ratio padded).
internal readonly record struct BackgroundLayout(
    Size OuterSize,
    Point CardOrigin,     // card top-left within outer
    Size CardSize,
    Point InnerOrigin,    // image top-left within outer (= CardOrigin + inset)
    double CornerRadius,  // applied to the card
    double InsetPx);

internal static class BackgroundRenderer
{
    private static double Round(double v) => Math.Round(v, MidpointRounding.AwayFromZero);

    public static BackgroundLayout Layout(Size innerSize, BackgroundStyle style)
    {
        double innerW = innerSize.Width, innerH = innerSize.Height;
        double longest = Math.Max(innerW, innerH);

        double inset = Round(style.InsetFraction * longest);
        double cardW = innerW + inset * 2;
        double cardH = innerH + inset * 2;

        double padding = Round(style.PaddingFraction * longest);
        double contentW = cardW + padding * 2;
        double contentH = cardH + padding * 2;
        if (style.Ratio.Value() is double ratio)
        {
            if (contentW / contentH < ratio) contentW = Round(contentH * ratio);
            else contentH = Round(contentW / ratio);
        }
        double outerW = Math.Max(contentW, cardW), outerH = Math.Max(contentH, cardH);
        var cardOrigin = new Point(Round((outerW - cardW) / 2), Round((outerH - cardH) / 2));
        var innerOrigin = new Point(cardOrigin.X + inset, cardOrigin.Y + inset);
        double shortest = Math.Min(cardW, cardH);
        double radius = Math.Min(style.CornerRadiusFraction * shortest, shortest / 2);
        return new BackgroundLayout(new Size(outerW, outerH), cardOrigin, new Size(cardW, cardH),
                                    innerOrigin, radius, inset);
    }

    public static BitmapSource Wrap(BitmapSource inner, BackgroundStyle style)
    {
        if (style.IsEmpty) return inner;

        var innerSize = new Size(inner.PixelWidth, inner.PixelHeight);
        var l = Layout(innerSize, style);
        // Defense-in-depth: a non-finite or absurd outer size would request an
        // enormous bitmap. Bail to the unwrapped image rather than crash.
        const double maxDim = 32_768;
        if (!double.IsFinite(l.OuterSize.Width) || !double.IsFinite(l.OuterSize.Height)
            || l.OuterSize.Width < 1 || l.OuterSize.Height < 1
            || l.OuterSize.Width > maxDim || l.OuterSize.Height > maxDim)
            return inner;

        try
        {
            return Pixels.Render((int)l.OuterSize.Width, (int)l.OuterSize.Height, dc =>
            {
                DrawBackdrop(dc, l, innerSize, style);
                dc.PushClip(CardGeometry(l));
                dc.DrawImage(inner, new Rect(l.InnerOrigin, innerSize));
                dc.Pop();
            });
        }
        catch (Exception ex)
        {
            Log.Error("background wrap failed: " + ex.Message);
            return inner;
        }
    }

    public static Geometry CardGeometry(BackgroundLayout l)
    {
        var geometry = new RectangleGeometry(new Rect(l.CardOrigin, l.CardSize), l.CornerRadius, l.CornerRadius);
        geometry.Freeze();
        return geometry;
    }

    /// Everything beneath the image: fill, drop shadow and the inset frame. Shared
    /// by export and the editor canvas so they can never disagree.
    public static void DrawBackdrop(DrawingContext dc, BackgroundLayout l, Size innerSize, BackgroundStyle style)
    {
        var outerRect = new Rect(new Point(0, 0), l.OuterSize);
        var cardRect = new Rect(l.CardOrigin, l.CardSize);

        if (FillBrush(style.Fill, outerRect) is Brush fill)
            dc.DrawRectangle(fill, null, outerRect);

        if (style.ShadowOpacity > 0)
        {
            double blur = Math.Max(1, style.ShadowRadiusFraction * Math.Max(innerSize.Width, innerSize.Height));
            dc.PushClip(new RectangleGeometry(outerRect));
            DrawShadow(dc, cardRect, l.CornerRadius, blur, style.ShadowOpacity);
            dc.Pop();
        }

        if (l.InsetPx > 0)
        {
            var brush = new SolidColorBrush(style.InsetColor);
            brush.Freeze();
            dc.DrawRoundedRectangle(brush, null, cardRect, l.CornerRadius, l.CornerRadius);
        }
    }

    /// The background fill as a brush mapped onto `rect`, or null for no fill.
    public static Brush? FillBrush(BackgroundFill fill, Rect rect)
    {
        switch (fill.Kind)
        {
            case FillKind.Solid:
                var solid = new SolidColorBrush(fill.Color);
                solid.Freeze();
                return solid;
            case FillKind.Gradient:
                var preset = fill.Gradient!;
                double a = preset.Angle * Math.PI / 180;
                double dx = Math.Cos(a), dy = Math.Sin(a);
                double cx = rect.X + rect.Width / 2, cy = rect.Y + rect.Height / 2;
                double half = (Math.Abs(dx) * rect.Width + Math.Abs(dy) * rect.Height) / 2;
                // Angle is measured counter-clockwise with y up (as the macOS export
                // draws it), so 45° runs bottom-left → top-right in our y-down space.
                var brush = new LinearGradientBrush
                {
                    MappingMode = BrushMappingMode.Absolute,
                    StartPoint = new Point(cx - dx * half, cy + dy * half),
                    EndPoint = new Point(cx + dx * half, cy - dy * half),
                };
                for (int i = 0; i < preset.Colors.Length; i++)
                    brush.GradientStops.Add(new GradientStop(preset.Colors[i],
                        preset.Colors.Length == 1 ? 0 : (double)i / (preset.Colors.Length - 1)));
                brush.Freeze();
                return brush;
            default:
                return null;
        }
    }

    // MARK: - Shadow

    private readonly record struct ShadowKey(int W, int H, int Radius, int Blur);
    private static readonly Dictionary<ShadowKey, (BitmapSource Image, double Scale, double Margin)> ShadowCache = new();

    /// Soft drop shadow of a rounded card: an alpha mask rendered small (shadows
    /// carry no detail), blurred on the CPU and stretched back up. Deterministic in
    /// both the editor canvas and export, unlike WPF's GPU-dependent effects.
    private static void DrawShadow(DrawingContext dc, Rect card, double radius, double blur, double opacity)
    {
        var key = new ShadowKey((int)card.Width, (int)card.Height, (int)radius, (int)blur);
        if (!ShadowCache.TryGetValue(key, out var shadow))
        {
            double sigma = blur / 2;                     // CoreGraphics blur ≈ 2σ
            double scale = Math.Min(1, 6 / sigma);       // keep the working σ around 6 px
            double margin = Math.Ceiling(sigma * 3);
            int w = Math.Max(1, (int)Math.Ceiling((card.Width + margin * 2) * scale));
            int h = Math.Max(1, (int)Math.Ceiling((card.Height + margin * 2) * scale));

            var mask = Pixels.Render(w, h, m =>
            {
                m.PushTransform(new ScaleTransform(scale, scale));
                m.DrawRoundedRectangle(Brushes.Black, null,
                    new Rect(margin, margin, card.Width, card.Height), radius, radius);
                m.Pop();
            });
            var bgra = Pixels.CopyBgra(mask);
            var alpha = new byte[w * h];
            for (int i = 0; i < alpha.Length; i++) alpha[i] = bgra[i * 4 + 3];
            Pixels.GaussianBlur(alpha, w, h, 1, sigma * scale);
            for (int i = 0; i < alpha.Length; i++)
            {
                bgra[i * 4] = bgra[i * 4 + 1] = bgra[i * 4 + 2] = 0;   // premultiplied black
                bgra[i * 4 + 3] = alpha[i];
            }
            shadow = (Pixels.FromBgra(bgra, w, h, premultiplied: true), scale, margin);
            if (ShadowCache.Count >= 16) ShadowCache.Clear();
            ShadowCache[key] = shadow;
        }

        var target = new Rect(card.X - shadow.Margin, card.Y - shadow.Margin + blur * 0.35,
                              shadow.Image.PixelWidth / shadow.Scale, shadow.Image.PixelHeight / shadow.Scale);
        dc.PushOpacity(opacity);
        dc.DrawImage(shadow.Image, target);
        dc.Pop();
    }
}
