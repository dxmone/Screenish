//
//  EditorRenderer.cs
//  Screenish
//
//  Shared annotation drawing + flattening to a bitmap. `AnnotationDrawer` draws
//  annotations into a DrawingContext that is already in image-pixel space with a
//  top-left origin (the canvas applies a fit transform; the renderer uses 1:1).
//  Both the on-screen canvas and export go through the same drawer.
//

using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace Screenish;

internal static class AnnotationDrawer
{
    /// Cache of rendered redaction (blur/pixelate) bitmaps. Building one is
    /// expensive and it runs in the per-redraw annotation loop, so reuse the output
    /// while the inputs are unchanged. UI-thread only, so no locking is needed.
    private readonly record struct RedactionKey(AnnotationKind Kind, int X, int Y, int W, int H,
                                                int Amount, BitmapSource Base);
    private static readonly Dictionary<RedactionKey, (BitmapSource Image, Rect Target)> RedactionCache = new();
    private const int RedactionCacheLimit = 64;

    /// Drop cached redactions of a base image that is going away (the keys hold
    /// the bitmap alive otherwise).
    public static void Forget(BitmapSource baseImage)
    {
        foreach (var key in RedactionCache.Keys.Where(k => ReferenceEquals(k.Base, baseImage)).ToList())
            RedactionCache.Remove(key);
    }

    /// Draw the annotations in order, in image-pixel top-left space. `skip` hides
    /// one annotation (the text being edited inline).
    public static void DrawAll(DrawingContext dc, IReadOnlyList<Annotation> annotations,
                               BitmapSource baseImage, Guid? skip = null)
    {
        for (int i = 0; i < annotations.Count; i++)
        {
            if (annotations[i].Id == skip) continue;
            Draw(dc, annotations, i, baseImage, skip);
        }
    }

    private static void Draw(DrawingContext dc, IReadOnlyList<Annotation> list, int index,
                             BitmapSource baseImage, Guid? skip)
    {
        var a = list[index];
        switch (a.Kind)
        {
            case AnnotationKind.Arrow: DrawArrow(dc, a); break;
            case AnnotationKind.Line: DrawLine(dc, a); break;
            case AnnotationKind.Rectangle: DrawRectangle(dc, a, filled: false); break;
            case AnnotationKind.RectangleFilled: DrawRectangle(dc, a, filled: true); break;
            case AnnotationKind.Ellipse: DrawEllipse(dc, a); break;
            case AnnotationKind.Highlight: DrawHighlight(dc, list, index, baseImage, skip); break;
            case AnnotationKind.Text: DrawText(dc, a); break;
            case AnnotationKind.Blur or AnnotationKind.Pixelate: DrawRedaction(dc, a, baseImage); break;
            case AnnotationKind.Counter: DrawCounter(dc, a); break;
            case AnnotationKind.Spotlight: DrawSpotlight(dc, a, baseImage); break;
            case AnnotationKind.Pencil: DrawPencil(dc, a); break;
        }
    }

    private static SolidColorBrush Brush(Color color)
    {
        var brush = new SolidColorBrush(color);
        brush.Freeze();
        return brush;
    }

    private static Pen RoundPen(Color color, double width)
    {
        var pen = new Pen(Brush(color), width)
        {
            StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round, LineJoin = PenLineJoin.Round,
        };
        pen.Freeze();
        return pen;
    }

    // MARK: - Shapes

    private static void DrawLine(DrawingContext dc, Annotation a) =>
        dc.DrawLine(RoundPen(a.Style.Color, a.Style.LineWidth), a.Start, a.End);

    private static void DrawArrow(DrawingContext dc, Annotation a)
    {
        // Tail at Start (where the drag begins), head/tip at End (where it
        // points). Clean shaft + filled triangle head, sized to the line width.
        Point tip = a.End, tail = a.Start;
        double w = a.Style.LineWidth;
        double dx = tip.X - tail.X, dy = tip.Y - tail.Y;
        double length = Math.Max(Math.Sqrt(dx * dx + dy * dy), 1);
        double ux = dx / length, uy = dy / length;   // unit direction tail → tip
        double px = -uy, py = ux;                    // perpendicular

        double headLength = Math.Min(Math.Max(w * 3.5, 18), length);
        double headHalfWidth = w * 1.6;
        var pen = RoundPen(a.Style.Color, w);

        // Direction of the head: along the tangent at the tip (so the head aligns
        // with the curve for curved arrows).
        double headUx = ux, headUy = uy;
        var shaftEnd = new Point(tip.X - ux * headLength, tip.Y - uy * headLength);

        if (a.Style.ArrowStyle == ArrowStyle.Curved)
        {
            // Quadratic bezier bowed perpendicular from the midpoint.
            var mid = new Point((tail.X + tip.X) / 2, (tail.Y + tip.Y) / 2);
            double bow = length * 0.22;
            var control = new Point(mid.X + px * bow, mid.Y + py * bow);
            var curve = new StreamGeometry();
            using (var g = curve.Open())
            {
                g.BeginFigure(tail, false, false);
                g.QuadraticBezierTo(control, shaftEnd, true, true);
            }
            curve.Freeze();
            dc.DrawGeometry(null, pen, curve);
            // Tangent at the tip ≈ direction from control to tip.
            double tdx = tip.X - control.X, tdy = tip.Y - control.Y;
            double tlen = Math.Max(Math.Sqrt(tdx * tdx + tdy * tdy), 1);
            headUx = tdx / tlen; headUy = tdy / tlen;
        }
        else
        {
            dc.DrawLine(pen, tail, shaftEnd);
        }

        // Filled triangle head, oriented along headU.
        double hpx = -headUy, hpy = headUx;
        double baseX = tip.X - headUx * headLength, baseY = tip.Y - headUy * headLength;
        var head = new StreamGeometry();
        using (var g = head.Open())
        {
            g.BeginFigure(tip, true, true);
            g.LineTo(new Point(baseX + hpx * headHalfWidth, baseY + hpy * headHalfWidth), true, false);
            g.LineTo(new Point(baseX - hpx * headHalfWidth, baseY - hpy * headHalfWidth), true, false);
        }
        head.Freeze();
        dc.DrawGeometry(Brush(a.Style.Color), null, head);
    }

    private static void DrawPencil(DrawingContext dc, Annotation a)
    {
        if (a.Points.Count < 2) return;
        dc.DrawGeometry(null, RoundPen(a.Style.Color, a.Style.LineWidth), SmoothedPath(a.Points));
    }

    /// Catmull-Rom smoothing through the points → cubic bezier path.
    private static Geometry SmoothedPath(IReadOnlyList<Point> pts)
    {
        var path = new StreamGeometry();
        using (var g = path.Open())
        {
            g.BeginFigure(pts[0], false, false);
            if (pts.Count == 2)
            {
                g.LineTo(pts[1], true, true);
            }
            else
            {
                for (int i = 0; i < pts.Count - 1; i++)
                {
                    Point p0 = pts[Math.Max(i - 1, 0)], p1 = pts[i], p2 = pts[i + 1];
                    Point p3 = pts[Math.Min(i + 2, pts.Count - 1)];
                    var c1 = new Point(p1.X + (p2.X - p0.X) / 6, p1.Y + (p2.Y - p0.Y) / 6);
                    var c2 = new Point(p2.X - (p3.X - p1.X) / 6, p2.Y - (p3.Y - p1.Y) / 6);
                    g.BezierTo(c1, c2, p2, true, true);
                }
            }
        }
        path.Freeze();
        return path;
    }

    private static void DrawCounter(DrawingContext dc, Annotation a)
    {
        double radius = a.CounterRadius;
        dc.DrawEllipse(Brush(a.Style.Color), null, a.Start, radius, radius);

        var text = new FormattedText(a.Number.ToString(), System.Globalization.CultureInfo.InvariantCulture,
            FlowDirection.LeftToRight,
            new Typeface(new FontFamily("Segoe UI"), FontStyles.Normal, FontWeights.Bold, FontStretches.Normal),
            radius * 1.2, Brushes.White, 1.0);
        // Center on the glyph ink, not the line box, so digits sit dead center.
        var ink = text.BuildGeometry(new Point(0, 0)).Bounds;
        if (ink.IsEmpty) return;
        dc.DrawText(text, new Point(a.Start.X - ink.X - ink.Width / 2, a.Start.Y - ink.Y - ink.Height / 2));
    }

    private static void DrawSpotlight(DrawingContext dc, Annotation a, BitmapSource baseImage)
    {
        // Outer rect minus inner ellipse → darkens everything but the ellipse.
        var rect = a.Rect;
        var mask = new CombinedGeometry(GeometryCombineMode.Exclude,
            new RectangleGeometry(Pixels.Bounds(baseImage)),
            new EllipseGeometry(new Point(rect.X + rect.Width / 2, rect.Y + rect.Height / 2),
                                rect.Width / 2, rect.Height / 2));
        mask.Freeze();
        dc.DrawGeometry(Brush(Color.FromArgb(140, 0, 0, 0)), null, mask);   // black @ 0.55
    }

    private static Rect InsetForStroke(Rect rect, double lineWidth)
    {
        double half = lineWidth / 2;
        return new Rect(rect.X + half, rect.Y + half,
                        Math.Max(rect.Width - lineWidth, 0), Math.Max(rect.Height - lineWidth, 0));
    }

    private static Pen MiterPen(Color color, double width)
    {
        var pen = new Pen(Brush(color), width);
        pen.Freeze();
        return pen;
    }

    private static void DrawRectangle(DrawingContext dc, Annotation a, bool filled)
    {
        if (filled) dc.DrawRectangle(Brush(a.Style.Color), null, a.Rect);
        else dc.DrawRectangle(null, MiterPen(a.Style.Color, a.Style.LineWidth),
                              InsetForStroke(a.Rect, a.Style.LineWidth));
    }

    private static void DrawEllipse(DrawingContext dc, Annotation a)
    {
        var r = InsetForStroke(a.Rect, a.Style.LineWidth);
        dc.DrawEllipse(null, MiterPen(a.Style.Color, a.Style.LineWidth),
                       new Point(r.X + r.Width / 2, r.Y + r.Height / 2), r.Width / 2, r.Height / 2);
    }

    /// Marker highlight = multiply blend at 40 %, so dark text stays crisp under the
    /// colour. WPF has no blend modes: render what lies beneath the rect (base image
    /// + earlier annotations), multiply the pixels, and draw the result back.
    private static void DrawHighlight(DrawingContext dc, IReadOnlyList<Annotation> list, int index,
                                      BitmapSource baseImage, Guid? skip)
    {
        var a = list[index];
        var region = Rect.Intersect(a.Rect, Pixels.Bounds(baseImage));
        if (region.IsEmpty) return;
        int x = (int)Math.Floor(region.X), y = (int)Math.Floor(region.Y);
        int w = (int)Math.Ceiling(region.Right) - x, h = (int)Math.Ceiling(region.Bottom) - y;
        if (w < 1 || h < 1) return;

        var beneath = Pixels.Render(w, h, under =>
        {
            under.PushTransform(new TranslateTransform(-x, -y));
            under.DrawImage(baseImage, Pixels.Bounds(baseImage));
            for (int i = 0; i < index; i++)
            {
                if (list[i].Id == skip) continue;
                if (!Reach(list[i], baseImage).IntersectsWith(region)) continue;
                Draw(under, list, i, baseImage, skip);
            }
            under.Pop();
        });

        var bytes = Pixels.CopyBgra(beneath);
        var c = a.Style.Color;
        double alpha = 0.4 * c.A / 255.0;
        int fb = (int)Math.Round((1 - alpha + alpha * c.B / 255.0) * 256);
        int fg = (int)Math.Round((1 - alpha + alpha * c.G / 255.0) * 256);
        int fr = (int)Math.Round((1 - alpha + alpha * c.R / 255.0) * 256);
        for (int i = 0; i < bytes.Length; i += 4)
        {
            bytes[i] = (byte)(bytes[i] * fb >> 8);
            bytes[i + 1] = (byte)(bytes[i + 1] * fg >> 8);
            bytes[i + 2] = (byte)(bytes[i + 2] * fr >> 8);
        }
        dc.PushClip(new RectangleGeometry(region));
        dc.DrawImage(Pixels.FromBgra(bytes, w, h), new Rect(x, y, w, h));
        dc.Pop();
    }

    /// The area an annotation can paint into (strokes overhang their geometry).
    private static Rect Reach(Annotation a, BitmapSource baseImage)
    {
        if (a.Kind == AnnotationKind.Spotlight) return Pixels.Bounds(baseImage);
        Rect r = a.Kind.IsLinear() ? new Rect(a.Start, a.End) : a.BoundingRect;
        double grow = a.Kind == AnnotationKind.Counter ? a.CounterRadius : a.Style.LineWidth * 4 + 18;
        r.Inflate(grow, grow);
        return r;
    }

    private static void DrawText(DrawingContext dc, Annotation a)
    {
        if (a.Text.Length == 0) return;
        var ts = a.Style.TextStyle;
        var rect = a.Rect;

        // Boxed styles: fill the box first (rounded variant gets a corner radius).
        if (ts.IsBoxed())
        {
            double r = ts.HasRoundedBox() ? Math.Min(a.Style.FontSize * 0.5, rect.Height / 2) : 0;
            dc.DrawRoundedRectangle(Brush(a.Style.Color), null, rect, r, r);
        }

        double pad = ts.BoxPadding(a.Style.FontSize);
        var textRect = new Rect(rect.X + pad, rect.Y + pad,
                                Math.Max(rect.Width - pad * 2, 1), Math.Max(rect.Height - pad * 2, 1));
        var glyphBrush = ts.IsBoxed() || ts.IsOutlined() ? Brushes.White : (Brush)Brush(a.Style.Color);
        var text = TextLayout.Format(a.Text, a.Style.FontSize, ts, glyphBrush, textRect.Width);

        dc.PushClip(new RectangleGeometry(new Rect(textRect.X - pad, textRect.Y, textRect.Width + pad * 2,
                                                   Math.Max(textRect.Height, a.Style.FontSize * 1.4) + 2)));
        if (ts.IsOutlined())
        {
            // Stroke in the annotation colour behind white glyphs (fill + stroke).
            var outline = text.BuildGeometry(textRect.TopLeft);
            var pen = new Pen(Brush(a.Style.Color), TextStyleExtensions.OutlineWidth(a.Style.FontSize))
            {
                LineJoin = PenLineJoin.Round,
            };
            pen.Freeze();
            dc.DrawGeometry(Brushes.White, pen, outline);
        }
        else
        {
            dc.DrawText(text, textRect.TopLeft);
        }
        dc.Pop();
    }

    // MARK: - Redaction

    private static void DrawRedaction(DrawingContext dc, Annotation a, BitmapSource baseImage)
    {
        var rect = Rect.Intersect(a.Rect, Pixels.Bounds(baseImage));
        if (rect.IsEmpty || rect.Width < 1 || rect.Height < 1) return;
        if (RedactedImage(a.Kind, rect, baseImage) is not { } redacted) return;

        // Pixelate blocks must stay hard-edged when the small block bitmap is
        // stretched; blur is upsampled smoothly.
        var group = new DrawingGroup { ClipGeometry = new RectangleGeometry(rect) };
        RenderOptions.SetBitmapScalingMode(group, a.Kind == AnnotationKind.Pixelate
            ? BitmapScalingMode.NearestNeighbor : BitmapScalingMode.HighQuality);
        group.Children.Add(new ImageDrawing(redacted.Image, redacted.Target));
        group.Freeze();
        dc.DrawDrawing(group);
    }

    /// Produce a blurred/pixelated stand-in for the base image region under `rect`,
    /// plus the image-space rect it should be stretched over.
    private static (BitmapSource Image, Rect Target)? RedactedImage(AnnotationKind kind, Rect rect,
                                                                   BitmapSource baseImage)
    {
        // Derived strength is a function of the rect size.
        double amount = kind == AnnotationKind.Blur
            ? Math.Max(8, Math.Min(rect.Width, rect.Height) / 8)
            : Math.Max(8, Math.Min(rect.Width, rect.Height) / 12);
        var key = new RedactionKey(kind, (int)Math.Round(rect.X), (int)Math.Round(rect.Y),
                                   (int)Math.Round(rect.Width), (int)Math.Round(rect.Height),
                                   (int)Math.Round(amount), baseImage);
        if (RedactionCache.TryGetValue(key, out var cached)) return cached;

        var result = kind == AnnotationKind.Blur
            ? Blurred(baseImage, key, amount)
            : Pixelated(baseImage, rect, Math.Max(2, (int)Math.Round(amount)));

        // Bound growth: clear when the working set outgrows the cap (a drag only
        // touches one key at a time, so this rarely triggers).
        if (RedactionCache.Count >= RedactionCacheLimit) RedactionCache.Clear();
        RedactionCache[key] = result;
        return result;
    }

    /// Gaussian blur (σ = amount) with clamped edges. The region is box-averaged
    /// down by `k` first — a blurred image has no detail to lose — which cuts the
    /// work by k² and keeps dragging a blur box responsive.
    private static (BitmapSource, Rect) Blurred(BitmapSource baseImage, RedactionKey key, double sigma)
    {
        var src = Pixels.Bgra(baseImage);
        int bw = baseImage.PixelWidth, bh = baseImage.PixelHeight;
        int k = Math.Max(1, (int)(sigma / 4));
        int margin = (int)Math.Ceiling(sigma * 3 / k);          // in downsampled cells
        int cellsW = (key.W + k - 1) / k + margin * 2, cellsH = (key.H + k - 1) / k + margin * 2;
        int originX = key.X - margin * k, originY = key.Y - margin * k;

        var cells = new byte[cellsW * cellsH * 4];
        for (int cy = 0; cy < cellsH; cy++)
        for (int cx = 0; cx < cellsW; cx++)
        {
            int b = 0, g = 0, r = 0;
            for (int sy = 0; sy < k; sy++)
            {
                int py = Math.Clamp(originY + cy * k + sy, 0, bh - 1);
                for (int sx = 0; sx < k; sx++)
                {
                    int px = Math.Clamp(originX + cx * k + sx, 0, bw - 1);
                    int o = (py * bw + px) * 4;
                    b += src[o]; g += src[o + 1]; r += src[o + 2];
                }
            }
            int n = k * k, d = (cy * cellsW + cx) * 4;
            cells[d] = (byte)(b / n); cells[d + 1] = (byte)(g / n); cells[d + 2] = (byte)(r / n);
            cells[d + 3] = 255;
        }
        Pixels.GaussianBlur(cells, cellsW, cellsH, 4, sigma / k);
        return (Pixels.FromBgra(cells, cellsW, cellsH), new Rect(originX, originY, cellsW * k, cellsH * k));
    }

    /// Mosaic of block averages; the block grid is centered on the rect.
    private static (BitmapSource, Rect) Pixelated(BitmapSource baseImage, Rect rect, int block)
    {
        var src = Pixels.Bgra(baseImage);
        int bw = baseImage.PixelWidth, bh = baseImage.PixelHeight;
        double centerX = rect.X + rect.Width / 2, centerY = rect.Y + rect.Height / 2;
        int originX = (int)Math.Round(centerX - Math.Ceiling((centerX - rect.X) / block) * block);
        int originY = (int)Math.Round(centerY - Math.Ceiling((centerY - rect.Y) / block) * block);
        int cols = Math.Max(1, (int)Math.Ceiling((rect.Right - originX) / block));
        int rows = Math.Max(1, (int)Math.Ceiling((rect.Bottom - originY) / block));

        var cells = new byte[cols * rows * 4];
        for (int cy = 0; cy < rows; cy++)
        for (int cx = 0; cx < cols; cx++)
        {
            int b = 0, g = 0, r = 0, n = 0;
            int y0 = Math.Max(originY + cy * block, 0), y1 = Math.Min(originY + (cy + 1) * block, bh);
            int x0 = Math.Max(originX + cx * block, 0), x1 = Math.Min(originX + (cx + 1) * block, bw);
            for (int py = y0; py < y1; py++)
            for (int px = x0; px < x1; px++)
            {
                int o = (py * bw + px) * 4;
                b += src[o]; g += src[o + 1]; r += src[o + 2]; n++;
            }
            int d = (cy * cols + cx) * 4;
            if (n > 0) { cells[d] = (byte)(b / n); cells[d + 1] = (byte)(g / n); cells[d + 2] = (byte)(r / n); }
            cells[d + 3] = 255;
        }
        return (Pixels.FromBgra(cells, cols, rows), new Rect(originX, originY, cols * block, rows * block));
    }
}

internal static class EditorRenderer
{
    /// Flatten the document (base + annotations, crop, then beautify) to a bitmap.
    public static BitmapSource Render(EditorDocument document) =>
        RenderComposite(document.BaseImage, document.Annotations, document.CropRect, document.Background);

    /// Render base + annotations + optional crop, then wrap in the background style.
    public static BitmapSource RenderComposite(BitmapSource baseImage, IReadOnlyList<Annotation> annotations,
                                               Rect? cropRect, BackgroundStyle background)
    {
        var full = annotations.Count == 0 ? baseImage : RenderFull(baseImage, annotations);
        var inner = full;
        if (cropRect is Rect crop)
        {
            var bounded = Rect.Intersect(crop, Pixels.Bounds(full));
            var pixels = new Int32Rect((int)Math.Round(bounded.X), (int)Math.Round(bounded.Y),
                                       (int)Math.Round(bounded.Width), (int)Math.Round(bounded.Height));
            pixels.Width = Math.Min(pixels.Width, full.PixelWidth - pixels.X);
            pixels.Height = Math.Min(pixels.Height, full.PixelHeight - pixels.Y);
            if (!bounded.IsEmpty && pixels.Width >= 1 && pixels.Height >= 1)
                inner = Pixels.Crop(full, pixels);
        }
        return BackgroundRenderer.Wrap(inner, background);
    }

    private static BitmapSource RenderFull(BitmapSource baseImage, IReadOnlyList<Annotation> annotations) =>
        Pixels.Render(baseImage.PixelWidth, baseImage.PixelHeight, dc =>
        {
            dc.DrawImage(baseImage, Pixels.Bounds(baseImage));
            dc.PushClip(new RectangleGeometry(Pixels.Bounds(baseImage)));
            AnnotationDrawer.DrawAll(dc, annotations, baseImage);
            dc.Pop();
        });
}
