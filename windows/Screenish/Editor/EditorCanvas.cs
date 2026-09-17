//
//  EditorCanvas.cs
//  Screenish
//
//  The drawing surface. Displays the beautified composite scaled to fit, draws
//  annotations via the shared AnnotationDrawer, handles selection / creation /
//  move / resize, inline text editing, crop, and a view-only scroll zoom for
//  annotating small details.
//

using System.Collections.Immutable;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace Screenish;

internal sealed class EditorCanvas : Canvas
{
    private readonly EditorDocument _document;

    private Annotation? _draft;          // shape being created
    private Rect? _cropDraft;            // crop rect being dragged (image space)

    private enum DragMode { None, Create, Move, Resize, Crop }
    private DragMode _dragMode = DragMode.None;
    private Handle _resizeHandle;
    private Point _dragStartImage;
    private Annotation? _moveOriginal;
    private bool _didBeginInteraction;

    private TextBox? _textBox;
    private Guid? _editingId;

    public EditorCanvas(EditorDocument document)
    {
        _document = document;
        Focusable = true;
        FocusVisualStyle = null;
        ClipToBounds = true;   // keep the composite inside the canvas only
        Background = Brushes.Transparent;
        RenderOptions.SetBitmapScalingMode(this, BitmapScalingMode.HighQuality);
        document.Changed += OnDocumentChanged;
        SizeChanged += (_, _) => { CommitTextEditing(); InvalidateVisual(); };
    }

    private void OnDocumentChanged()
    {
        Cursor = _document.Tool == EditorTool.Select ? Cursors.Arrow : Cursors.Cross;
        SyncEditingTextStyle();
        InvalidateVisual();
    }

    // MARK: - Geometry (view ↔ inner-image-pixel space)
    //
    // The whole beautified composite (image + inset card + padding) is fit to the
    // canvas and centered. Annotation geometry is in inner-image pixels and maps
    // through the layout's InnerOrigin (image top-left within the composite).
    //
    // Crop is non-destructive: the canvas displays only the cropped region as the
    // focused image. Annotation geometry stays in original-image space; CropOrigin
    // shifts between original-image space and the visible inner (crop) space.

    private Point CropOrigin => _document.CropRect?.TopLeft ?? new Point(0, 0);
    private Size InnerSize => _document.CropRect?.Size ?? _document.ImageSize;
    private BackgroundLayout BgLayout => BackgroundRenderer.Layout(InnerSize, _document.Background);

    private double FitScale
    {
        get
        {
            var outer = BgLayout.OuterSize;
            double s = Math.Min(ActualWidth / outer.Width, ActualHeight / outer.Height);
            return double.IsFinite(s) && s > 0 ? s : 1;
        }
    }

    // View-only zoom: the wheel magnifies the canvas so small details can be
    // annotated precisely. Document geometry stays in image pixels and the export
    // is untouched — the full screenshot is always what leaves the editor.
    private double _viewZoom = 1;
    private Vector _viewPan;    // desired offset minus centered offset

    private double Scale => FitScale * _viewZoom;

    private Point Offset
    {
        get
        {
            // Clamp so the composite never detaches from the view: pan only within the
            // overflow when zoomed in; keep centered along any axis that still fits.
            var outer = BgLayout.OuterSize;
            double w = outer.Width * Scale, h = outer.Height * Scale;
            double x = (ActualWidth - w) / 2 + _viewPan.X;
            double y = (ActualHeight - h) / 2 + _viewPan.Y;
            x = w <= ActualWidth ? (ActualWidth - w) / 2 : Math.Min(0, Math.Max(ActualWidth - w, x));
            y = h <= ActualHeight ? (ActualHeight - h) / 2 : Math.Min(0, Math.Max(ActualHeight - h, y));
            return new Point(x, y);
        }
    }

    protected override void OnMouseWheel(MouseWheelEventArgs e)
    {
        SetZoom(_viewZoom * Math.Exp(e.Delta / 120.0 * 0.2), e.GetPosition(this));
        e.Handled = true;
    }

    private void SetZoom(double newZoom, Point anchor)
    {
        double clamped = Math.Max(1, Math.Min(8, newZoom));
        if (clamped == _viewZoom) return;
        CommitTextEditing();   // the overlay text box doesn't follow the zoom
        double oldScale = Scale;
        var oldOffset = Offset;
        _viewZoom = clamped;
        if (clamped == 1)
        {
            _viewPan = default;
        }
        else
        {
            // Keep the composite point under the cursor stationary:
            // offset' = anchor - (scale'/scale) * (anchor - offset)
            var outer = BgLayout.OuterSize;
            double ratio = Scale / oldScale;
            _viewPan = new Vector(
                anchor.X - ratio * (anchor.X - oldOffset.X) - (ActualWidth - outer.Width * Scale) / 2,
                anchor.Y - ratio * (anchor.Y - oldOffset.Y) - (ActualHeight - outer.Height * Scale) / 2);
        }
        InvalidateVisual();
    }

    private Point ImagePoint(MouseEventArgs e)
    {
        var p = e.GetPosition(this);
        var l = BgLayout;
        var offset = Offset;
        return new Point((p.X - offset.X) / Scale - l.InnerOrigin.X + CropOrigin.X,
                         (p.Y - offset.Y) / Scale - l.InnerOrigin.Y + CropOrigin.Y);
    }

    private Rect ViewRect(Rect imageRect)
    {
        var topLeft = ViewPoint(imageRect.TopLeft);
        return new Rect(topLeft.X, topLeft.Y, imageRect.Width * Scale, imageRect.Height * Scale);
    }

    private Point ViewPoint(Point imagePoint)
    {
        var l = BgLayout;
        var offset = Offset;
        return new Point(offset.X + (l.InnerOrigin.X + imagePoint.X - CropOrigin.X) * Scale,
                         offset.Y + (l.InnerOrigin.Y + imagePoint.Y - CropOrigin.Y) * Scale);
    }

    // MARK: - Drawing
    //
    // The static layers (margin + background fill + drop shadow + rounded card +
    // inset + base-image blit) are identical from frame to frame during an
    // annotation drag, yet they dominate the redraw cost. Cache them as a
    // device-resolution bitmap and blit it each frame; only annotations are redrawn
    // live on top. The cache is keyed on everything that affects those layers.

    private readonly record struct StaticLayerKey(int PixelWidth, int PixelHeight, BackgroundStyle Background,
                                                  Rect? CropRect, double Zoom, Vector Pan, bool Dark);
    private BitmapSource? _staticLayerCache;
    private StaticLayerKey? _staticLayerKey;

    protected override void OnRender(DrawingContext dc)
    {
        if (ActualWidth < 1 || ActualHeight < 1) return;
        var l = BgLayout;
        var bounds = new Rect(0, 0, ActualWidth, ActualHeight);

        var dpi = VisualTreeHelper.GetDpi(this);
        int pixelW = Math.Max(1, (int)Math.Round(ActualWidth * dpi.DpiScaleX));
        int pixelH = Math.Max(1, (int)Math.Round(ActualHeight * dpi.DpiScaleY));
        var key = new StaticLayerKey(pixelW, pixelH, _document.Background, _document.CropRect,
                                     _viewZoom, _viewPan, Theme.IsDark);
        if (_staticLayerKey != key || _staticLayerCache == null)
        {
            _staticLayerCache = RenderStaticLayers(pixelW, pixelH, dpi.DpiScaleX);
            _staticLayerKey = key;
        }
        dc.DrawImage(_staticLayerCache, bounds);

        // Annotations in original-image space, shifted by the crop origin and
        // clipped to the crop region (so annotations outside the crop are hidden,
        // matching the exported image). Drawn live every frame on top of the
        // cached static bitmap; the card's rounded corners clip them too.
        var offset = Offset;
        dc.PushTransform(new TranslateTransform(offset.X, offset.Y));
        dc.PushTransform(new ScaleTransform(Scale, Scale));
        dc.PushClip(BackgroundRenderer.CardGeometry(l));
        dc.PushTransform(new TranslateTransform(l.InnerOrigin.X - CropOrigin.X, l.InnerOrigin.Y - CropOrigin.Y));
        dc.PushClip(new RectangleGeometry(new Rect(CropOrigin, InnerSize)));
        IReadOnlyList<Annotation> visible = _document.Annotations;
        if (_draft != null) visible = [.. visible, _draft];
        AnnotationDrawer.DrawAll(dc, visible, _document.BaseImage, skip: _editingId);
        dc.Pop(); dc.Pop(); dc.Pop(); dc.Pop(); dc.Pop();

        DrawCropOverlay(dc, bounds);
        DrawSelectionHandles(dc);
    }

    /// Render the static layers into a device-resolution bitmap. The composite
    /// transform (offset/scale) is baked in so the result blits 1:1 over the view.
    private BitmapSource RenderStaticLayers(int pixelWidth, int pixelHeight, double dpiScale) =>
        Pixels.Render(pixelWidth, pixelHeight, dc =>
        {
            dc.PushTransform(new ScaleTransform(dpiScale, dpiScale));
            dc.DrawRectangle((Brush)FindResource("CanvasBg"), null, new Rect(0, 0, ActualWidth, ActualHeight));

            // Composite (outer) space, top-left origin.
            var offset = Offset;
            var l = BgLayout;
            dc.PushTransform(new TranslateTransform(offset.X, offset.Y));
            dc.PushTransform(new ScaleTransform(Scale, Scale));
            if (!_document.Background.IsEmpty)
                BackgroundRenderer.DrawBackdrop(dc, l, InnerSize, _document.Background);

            // Base image, clipped to the rounded card and the visible (crop) region:
            // draw the full base shifted so the crop origin lands at the inner top-left.
            dc.PushClip(BackgroundRenderer.CardGeometry(l));
            dc.PushClip(new RectangleGeometry(new Rect(l.InnerOrigin, InnerSize)));
            dc.DrawImage(_document.BaseImage, new Rect(
                l.InnerOrigin.X - CropOrigin.X, l.InnerOrigin.Y - CropOrigin.Y,
                _document.ImageSize.Width, _document.ImageSize.Height));
            dc.Pop(); dc.Pop();
            dc.Pop(); dc.Pop(); dc.Pop();
        });

    private void DrawSelectionHandles(DrawingContext dc)
    {
        if (_document.Tool != EditorTool.Select || _document.Selected is not { } selected) return;
        var pen = new Pen(Theme.AccentBrush, 1);
        foreach (var (_, point) in HandlePoints(selected))
        {
            var v = ViewPoint(point);
            dc.DrawRectangle(Brushes.White, pen, new Rect(Math.Round(v.X) - 4.5, Math.Round(v.Y) - 4.5, 9, 9));
        }
    }

    private void DrawCropOverlay(DrawingContext dc, Rect bounds)
    {
        // Only preview the active drag; a committed crop is already shown cropped.
        if (_cropDraft is not Rect rect) return;
        var v = ViewRect(rect);
        // Darken everything outside the selection so the inside keeps showing the real image.
        var mask = new CombinedGeometry(GeometryCombineMode.Exclude,
                                        new RectangleGeometry(bounds), new RectangleGeometry(v));
        dc.DrawGeometry(Theme.Frozen(Color.FromArgb(115, 0, 0, 0)), null, mask);   // 0.45
        dc.DrawRectangle(null, new Pen(Theme.AccentBrush, 1), v);
    }

    // MARK: - Handles

    private enum Handle
    {
        TopLeft, Top, TopRight, Right, BottomRight, Bottom, BottomLeft, Left,
        StartPoint, EndPoint,
    }

    private static List<(Handle, Point)> HandlePoints(Annotation a)
    {
        if (a.Kind.IsLinear()) return [(Handle.StartPoint, a.Start), (Handle.EndPoint, a.End)];
        // Counter (point) and pencil (path) are move-only — no resize handles.
        if (a.Kind == AnnotationKind.Counter || a.Kind.IsPath()) return [];
        var r = a.Rect;
        double midX = r.X + r.Width / 2, midY = r.Y + r.Height / 2;
        return
        [
            (Handle.TopLeft, r.TopLeft), (Handle.Top, new Point(midX, r.Top)), (Handle.TopRight, r.TopRight),
            (Handle.Right, new Point(r.Right, midY)), (Handle.BottomRight, r.BottomRight),
            (Handle.Bottom, new Point(midX, r.Bottom)), (Handle.BottomLeft, r.BottomLeft),
            (Handle.Left, new Point(r.Left, midY)),
        ];
    }

    private Handle? HandleAt(Point imagePoint, Annotation a)
    {
        double tolerance = 9 / Scale;
        foreach (var (handle, point) in HandlePoints(a))
            if (Math.Abs(point.X - imagePoint.X) <= tolerance && Math.Abs(point.Y - imagePoint.Y) <= tolerance)
                return handle;
        return null;
    }

    private Annotation? AnnotationHit(Point p)
    {
        double tolerance = 6 / Scale;
        for (int i = _document.Annotations.Count - 1; i >= 0; i--)
        {
            var a = _document.Annotations[i];
            if (a.Kind.IsLinear())
            {
                if (DistanceToSegment(p, a.Start, a.End) <= Math.Max(tolerance, a.Style.LineWidth)) return a;
            }
            else if (a.Kind == AnnotationKind.Counter)
            {
                if ((p - a.Start).Length <= a.CounterRadius + tolerance) return a;
            }
            else
            {
                var r = a.BoundingRect;
                r.Inflate(tolerance, tolerance);
                if (r.Contains(p)) return a;
            }
        }
        return null;
    }

    // MARK: - Mouse

    protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e)
    {
        CommitTextEditing();
        Focus();
        var p = ImagePoint(e);
        _dragStartImage = p;
        _didBeginInteraction = false;
        _dragMode = DragMode.None;
        e.Handled = true;

        // Double-click a text annotation to edit it. With the text tool a single
        // click on an existing text annotation edits it too, instead of a new box.
        if ((e.ClickCount == 2 || _document.Tool == EditorTool.Text)
            && AnnotationHit(p) is { Kind: AnnotationKind.Text } text)
        {
            _document.SelectionId = text.Id;
            StartEditing(text);
            return;
        }

        if (_document.Tool == EditorTool.Crop)
        {
            _cropDraft = new Rect(p, new Size(0, 0));
            _dragMode = DragMode.Crop;
        }
        else if (_document.Tool == EditorTool.Select)
        {
            if (_document.Selected is { } selected && HandleAt(p, selected) is Handle handle)
            {
                _dragMode = DragMode.Resize;
                _resizeHandle = handle;
                _moveOriginal = selected;
            }
            else if (AnnotationHit(p) is { } hit)
            {
                _document.SelectionId = hit.Id;
                _dragMode = DragMode.Move;
                _moveOriginal = hit;
            }
            else
            {
                _document.SelectionId = null;
            }
        }
        else if (_document.Tool == EditorTool.Counter)
        {
            // Single click places a numbered marker (no drag).
            int number = _document.Annotations.Count(a => a.Kind == AnnotationKind.Counter) + 1;
            _document.Add(new Annotation
            {
                Kind = AnnotationKind.Counter, Start = p, End = p, Style = _document.Style, Number = number,
            });
        }
        else if (_document.Tool.AnnotationKind() is AnnotationKind kind)
        {
            // Shape tools → start a draft.
            _draft = new Annotation
            {
                Kind = kind, Start = p, End = p, Style = _document.Style,
                Points = kind == AnnotationKind.Pencil ? [p] : ImmutableList<Point>.Empty,
            };
            _dragMode = DragMode.Create;
        }

        if (_dragMode != DragMode.None) CaptureMouse();
        InvalidateVisual();
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        if (_dragMode == DragMode.None || e.LeftButton != MouseButtonState.Pressed) return;
        var p = ImagePoint(e);
        switch (_dragMode)
        {
            case DragMode.Create when _draft != null:
                _draft = _draft.Kind.IsPath()
                    ? _draft with { Points = _draft.Points.Add(p), End = p }
                    : _draft with { End = p };
                break;
            case DragMode.Crop:
                _cropDraft = new Rect(_dragStartImage, p);
                break;
            case DragMode.Move when _moveOriginal != null:
                BeginInteractionOnce();
                _document.Replace(_moveOriginal.MovedBy(p.X - _dragStartImage.X, p.Y - _dragStartImage.Y));
                break;
            case DragMode.Resize when _moveOriginal != null:
                BeginInteractionOnce();
                _document.Replace(Resized(_moveOriginal, _resizeHandle, p));
                break;
        }
        InvalidateVisual();
    }

    protected override void OnMouseLeftButtonUp(MouseButtonEventArgs e)
    {
        var mode = _dragMode;
        _dragMode = DragMode.None;
        _moveOriginal = null;
        ReleaseMouseCapture();

        if (mode == DragMode.Create && _draft is { } d)
        {
            _draft = null;
            d = d with { Style = _document.Style };
            var r = d.Rect;
            if (d.Kind == AnnotationKind.Text)
            {
                // Drag → sized box; click (tiny) → default box at the click point.
                if (r.Width < 12 || r.Height < 12)
                    d = d with { Start = r.TopLeft, End = new Point(r.Left + 240, r.Top + d.Style.FontSize * 1.6) };
                _document.Add(d);
                StartEditing(d);
            }
            else
            {
                bool bigEnough = d.Kind.IsPath() ? d.Points.Count >= 2
                    : d.Kind.IsLinear() ? (d.End - d.Start).Length >= 5
                    : r.Width >= 5 && r.Height >= 5;
                if (bigEnough) _document.Add(d);
            }
        }
        else if (mode == DragMode.Crop)
        {
            if (_cropDraft is Rect c && c.Width >= 5 && c.Height >= 5)
            {
                // Whole pixels inside the image, so the preview equals the export.
                var bounded = Rect.Intersect(c, new Rect(_document.ImageSize));
                if (!bounded.IsEmpty && bounded.Width >= 1 && bounded.Height >= 1)
                    _document.SetCrop(new Rect(Math.Round(bounded.X), Math.Round(bounded.Y),
                                               Math.Max(1, Math.Round(bounded.Width)),
                                               Math.Max(1, Math.Round(bounded.Height))));
            }
            _cropDraft = null;
        }
        InvalidateVisual();
    }

    protected override void OnKeyDown(KeyEventArgs e)
    {
        if (e.Key is Key.Delete or Key.Back)
        {
            _document.DeleteSelected();
            e.Handled = true;
        }
    }

    private void BeginInteractionOnce()
    {
        if (_didBeginInteraction) return;
        _document.BeginInteraction();
        _didBeginInteraction = true;
    }

    private static Annotation Resized(Annotation a, Handle handle, Point p)
    {
        if (a.Kind.IsLinear())
        {
            return handle switch
            {
                Handle.StartPoint => a with { Start = p },
                Handle.EndPoint => a with { End = p },
                _ => a,
            };
        }
        double minX = a.Rect.Left, minY = a.Rect.Top, maxX = a.Rect.Right, maxY = a.Rect.Bottom;
        switch (handle)
        {
            case Handle.TopLeft: minX = p.X; minY = p.Y; break;
            case Handle.Top: minY = p.Y; break;
            case Handle.TopRight: maxX = p.X; minY = p.Y; break;
            case Handle.Right: maxX = p.X; break;
            case Handle.BottomRight: maxX = p.X; maxY = p.Y; break;
            case Handle.Bottom: maxY = p.Y; break;
            case Handle.BottomLeft: minX = p.X; maxY = p.Y; break;
            case Handle.Left: minX = p.X; break;
        }
        return a with { Start = new Point(minX, minY), End = new Point(maxX, maxY) };
    }

    // MARK: - Text editing

    /// Mirror the annotation's text style onto the live TextBox (font, boxed
    /// background/white text, inner padding) for WYSIWYG editing.
    private void ApplyTextStyle(TextBox box, AnnotationStyle style)
    {
        var ts = style.TextStyle;
        box.FontFamily = ts.Family();
        box.FontWeight = FontWeights.SemiBold;
        box.FontSize = Math.Max(style.FontSize * Scale, 1);
        var color = new SolidColorBrush(style.Color);
        if (ts.IsBoxed())
        {
            box.Foreground = box.CaretBrush = Brushes.White;
            box.Background = color;
        }
        else
        {
            box.Foreground = box.CaretBrush = color;
            box.Background = Theme.Frozen(Color.FromArgb(38, 0, 0, 0));
        }
        double pad = ts.BoxPadding(style.FontSize) * Scale;
        box.Padding = new Thickness(pad);
    }

    private void StartEditing(Annotation annotation)
    {
        var v = ViewRect(annotation.Rect);
        // Multi-line: wrap to the box width, allow newlines, grow vertically.
        var box = new TextBox
        {
            Text = annotation.Text, AcceptsReturn = true, TextWrapping = TextWrapping.Wrap,
            BorderThickness = new Thickness(0), Width = Math.Max(v.Width, 8), MinHeight = v.Height,
            Style = null,   // opt out of the themed TextBox look: this is part of the picture
        };
        TextOptions.SetTextFormattingMode(box, TextFormattingMode.Ideal);
        ApplyTextStyle(box, annotation.Style);
        SetLeft(box, v.X);
        SetTop(box, v.Y);

        box.LostKeyboardFocus += (_, _) => CommitTextEditing();
        box.PreviewKeyDown += (_, e) =>
        {
            if (e.Key != Key.Escape) return;
            CommitTextEditing();   // Esc ends text editing; it does not discard the shot
            e.Handled = true;
        };

        Children.Add(box);
        _textBox = box;
        _editingId = annotation.Id;
        InvalidateVisual();
        Dispatcher.BeginInvoke(() => { box.Focus(); box.CaretIndex = box.Text.Length; });
    }

    /// Push the editing annotation's current style into the live text box so
    /// font-size / colour changes from the toolbar show up while still editing.
    private void SyncEditingTextStyle()
    {
        if (_textBox == null || _editingId is not Guid id) return;
        if (_document.Annotations.FirstOrDefault(a => a.Id == id) is { } a) ApplyTextStyle(_textBox, a.Style);
    }

    public void CommitTextEditing()
    {
        if (_textBox is not { } box || _editingId is not Guid id) return;
        _textBox = null;
        _editingId = null;
        string text = box.Text;
        Children.Remove(box);

        if (_document.Annotations.FirstOrDefault(a => a.Id == id) is { } annotation)
        {
            if (text.Length == 0) _document.RemoveSilently(id);
            // Fit the box height to the (possibly multi-line) text.
            else _document.Replace((annotation with { Text = text }).WithFittedTextHeight());
        }
        InvalidateVisual();
    }

    /// Shortest distance from a point to a line segment (image-pixel space).
    private static double DistanceToSegment(Point p, Point a, Point b)
    {
        var d = b - a;
        if (d.LengthSquared == 0) return (p - a).Length;
        double t = Math.Clamp(((p.X - a.X) * d.X + (p.Y - a.Y) * d.Y) / d.LengthSquared, 0, 1);
        return (p - new Point(a.X + t * d.X, a.Y + t * d.Y)).Length;
    }
}
