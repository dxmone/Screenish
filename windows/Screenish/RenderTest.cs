//
//  RenderTest.cs
//  Screenish
//
//  Developer checks, no user input needed:
//    Screenish.exe --render-test <dir>  renders every annotation kind + a beautified
//        composite and snapshots the editor / stack-card UI to PNG files, plus a raw
//        screen and window grab, so renderer and layout can be reviewed as images.
//    Screenish.exe --smoke-test         drives capture → stack → editor → discard and
//        the selection overlay end to end; the exit code is the number of failures.
//

using System.Collections.Immutable;
using System.Globalization;
using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace Screenish;

internal static class RenderTest
{
    public static int Run(string directory)
    {
        Directory.CreateDirectory(directory);
        Prefs.Load();
        Loc.Init();
        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        Theme.Apply(app);

        var baseImage = MakeBaseImage(1200, 760);
        var red = AnnotationStyle.Default;
        var blue = red with { Color = Color.FromRgb(0x00, 0x7A, 0xFF) };
        var yellow = red with { Color = Color.FromRgb(0xFF, 0xCC, 0x00) };
        Annotation Make(AnnotationKind kind, double x0, double y0, double x1, double y1, AnnotationStyle style,
                        string text = "", int number = 0) => new()
        {
            Kind = kind, Start = new Point(x0, y0), End = new Point(x1, y1), Style = style, Text = text, Number = number,
        };

        var annotations = new List<Annotation>
        {
            Make(AnnotationKind.Rectangle, 40, 40, 320, 180, red),
            Make(AnnotationKind.Highlight, 60, 215, 560, 255, yellow),
            Make(AnnotationKind.Arrow, 360, 60, 560, 170, red),
            Make(AnnotationKind.Arrow, 600, 60, 800, 170, blue with { ArrowStyle = ArrowStyle.Curved }),
            Make(AnnotationKind.Line, 840, 60, 1040, 170, blue),
            Make(AnnotationKind.Ellipse, 40, 300, 300, 440, blue),
            Make(AnnotationKind.RectangleFilled, 340, 300, 520, 380, red),
            Make(AnnotationKind.Blur, 560, 290, 860, 450, red),
            Make(AnnotationKind.Pixelate, 880, 290, 1180, 450, red),
            Make(AnnotationKind.Counter, 80, 520, 80, 520, red, number: 1),
            Make(AnnotationKind.Counter, 150, 520, 150, 520, blue, number: 12),
            new()
            {
                Kind = AnnotationKind.Pencil, Style = blue, Start = new Point(220, 520), End = new Point(520, 520),
                Points = Enumerable.Range(0, 60).Select(i => new Point(220 + i * 5, 520 + Math.Sin(i / 4.0) * 30))
                    .ToImmutableList(),
            },
        };
        double y = 480;
        foreach (var style in TextStyleExtensions.All)
        {
            var text = Make(AnnotationKind.Text, 600, y, 900, y + 40, red with { TextStyle = style, FontSize = 24 },
                            text: style.Label() + " åäö");
            text = text.WithFittedTextHeight();
            annotations.Add(text);
            y = text.Rect.Bottom + 4;
        }

        Save(EditorRenderer.RenderComposite(baseImage, annotations, null, BackgroundStyle.None),
             Path.Combine(directory, "annotations.png"));

        var spotlight = new List<Annotation> { Make(AnnotationKind.Spotlight, 300, 200, 800, 560, red) };
        var beautify = new BackgroundStyle
        {
            Fill = BackgroundFill.Of(GradientPresets.All[0]), PaddingFraction = 0.08, CornerRadiusFraction = 0.04,
            ShadowOpacity = 0.6, InsetFraction = 0.01, Ratio = AspectRatioOption.SixteenNine,
        };
        var composite = EditorRenderer.RenderComposite(baseImage, spotlight, new Rect(100, 100, 900, 560), beautify);
        Save(composite, Path.Combine(directory, "beautify.png"));
        File.WriteAllBytes(Path.Combine(directory, "beautify.jpg"), ImageExport.Encode(composite, ImageFormat.Jpeg));

        // UI snapshots (shown off-screen just long enough to lay out and render).
        var shot = new Shot
        {
            Id = Guid.NewGuid(), BaseImage = baseImage, Annotations = annotations, Background = beautify,
            Image = composite, Thumbnail = ImageExport.Thumbnail(composite), TempPath = "",
        };
        Snapshot(new EditorWindow(shot) { OnDone = (_, _, _) => { } }, Path.Combine(directory, "editor.png"));
        var card = new Window
        {
            Content = new StackCard(shot) { Margin = new Thickness(12) }, SizeToContent = SizeToContent.WidthAndHeight,
            WindowStyle = WindowStyle.None,
        };
        Snapshot(card, Path.Combine(directory, "stack-card.png"));

        // Capture interop: the screen under the cursor + the window list (no overlay, no UI).
        Save(ScreenGrabber.GrabScreenUnderCursor(), Path.Combine(directory, "screen.png"));
        var windows = WindowPicker.Snapshot();
        File.WriteAllLines(Path.Combine(directory, "windows.txt"),
            windows.Select(w => $"{w.Handle:X} {w.Bounds.X},{w.Bounds.Y} {w.Bounds.Width}x{w.Bounds.Height}"));
        if (windows.Count > 0 && ScreenGrabber.GrabWindow(windows[0].Handle, windows[0].Bounds) is { } grabbed)
            Save(grabbed, Path.Combine(directory, "window.png"));

        Console.WriteLine("render test written to " + directory);
        return 0;
    }

    /// `--smoke-test`: drives the live pipeline end to end without user input —
    /// full-screen capture → stack panel → editor → discard, then the selection
    /// overlay in both modes (cancelled after a moment). The clipboard is left alone.
    public static int Smoke()
    {
        Prefs.Load();
        Loc.Init();
        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        Theme.Apply(app);
        int failures = 0;
        void Check(string name, bool ok)
        {
            Console.WriteLine((ok ? "ok    " : "FAIL  ") + name);
            if (!ok) failures++;
        }

        app.Dispatcher.BeginInvoke(async () =>
        {
            try
            {
                var coordinator = AppCoordinator.Shared;
                coordinator.Start();
                var image = ScreenGrabber.GrabScreenUnderCursor();
                var shot = coordinator.Store.Add(image);
                Check("shot added to the stack", coordinator.Store.Shots.Count == 1);
                Check("stack panel visible", app.Windows.OfType<StackPanelWindow>().Any(w => w.IsVisible));

                coordinator.OpenEditor(shot);
                await Task.Delay(1200);
                Check("editor open", app.Windows.OfType<EditorWindow>().Any(w => w.IsVisible));
                coordinator.DiscardShot(shot);
                await Task.Delay(300);
                Check("editor closed with its shot", !app.Windows.OfType<EditorWindow>().Any());
                Check("stack hidden when empty", !app.Windows.OfType<StackPanelWindow>().Any(w => w.IsVisible));

                foreach (var mode in new[] { OverlayMode.Region, OverlayMode.Window })
                {
                    var overlay = new SelectionOverlayController();
                    var pending = overlay.Present(mode, ScreenGrabber.GrabVirtualScreen());
                    await Task.Delay(700);
                    int shown = app.Windows.OfType<OverlayWindow>().Count();
                    // Every overlay must sit pixel-exact on its monitor, whatever that monitor's DPI.
                    var screens = System.Windows.Forms.Screen.AllScreens.Select(s => s.Bounds).ToList();
                    bool exact = app.Windows.OfType<OverlayWindow>().All(w =>
                    {
                        Native.GetWindowRect(new System.Windows.Interop.WindowInteropHelper(w).Handle, out var r);
                        return screens.Contains(new System.Drawing.Rectangle(r.Left, r.Top, r.Width, r.Height));
                    });
                    Check($"overlay {mode}: windows match monitor bounds", exact);
                    overlay.Cancel();
                    var result = await pending;
                    Check($"overlay {mode}: one window per monitor ({shown})",
                          shown == System.Windows.Forms.Screen.AllScreens.Length);
                    Check($"overlay {mode}: cancel → no result", result.Region == null && result.Window == null);
                }
                coordinator.Hotkeys.Dispose();
            }
            catch (Exception ex)
            {
                Check("no exception: " + ex, false);
            }
            app.Shutdown();
        });
        app.Run();
        return failures;
    }

    private static void Snapshot(Window window, string path)
    {
        window.WindowStartupLocation = WindowStartupLocation.Manual;
        window.Left = -20000;
        window.Top = -20000;
        window.ShowInTaskbar = false;
        window.ShowActivated = false;
        window.Show();
        // Drain layout + render before grabbing the visual tree.
        window.Dispatcher.Invoke(() => { }, DispatcherPriority.ApplicationIdle);

        var root = (FrameworkElement)window.Content;
        var dpi = VisualTreeHelper.GetDpi(root);
        var rtb = new RenderTargetBitmap(
            (int)Math.Ceiling(root.ActualWidth * dpi.DpiScaleX), (int)Math.Ceiling(root.ActualHeight * dpi.DpiScaleY),
            dpi.PixelsPerInchX, dpi.PixelsPerInchY, PixelFormats.Pbgra32);
        var backdrop = new DrawingVisual();
        using (var dc = backdrop.RenderOpen())
            dc.DrawRectangle((Brush)window.FindResource("WindowBg"), null,
                             new Rect(0, 0, root.ActualWidth, root.ActualHeight));
        rtb.Render(backdrop);
        rtb.Render(root);
        Save(rtb, path);
        window.Close();
    }

    private static void Save(BitmapSource image, string path) =>
        File.WriteAllBytes(path, ImageExport.Encode(image, ImageFormat.Png));

    /// A fake "screenshot": light page, header bar, and lines of text to redact/highlight.
    private static BitmapSource MakeBaseImage(int width, int height) =>
        Pixels.Render(width, height, dc =>
        {
            dc.DrawRectangle(Brushes.White, null, new Rect(0, 0, width, height));
            dc.DrawRectangle(new SolidColorBrush(Color.FromRgb(0x24, 0x29, 0x2F)), null, new Rect(0, 0, width, 28));
            var face = new Typeface("Segoe UI");
            for (int row = 0; row < 17; row++)
            {
                var line = new FormattedText(
                    $"Row {row + 1}: The quick brown fox jumps over the lazy dog — secret-token-{row * 7919 % 10000:0000}",
                    CultureInfo.InvariantCulture, FlowDirection.LeftToRight, face, 22,
                    row % 2 == 0 ? Brushes.Black : Brushes.DimGray, 1.0);
                dc.DrawText(line, new Point(60, 50 + row * 41));
            }
        });
}
