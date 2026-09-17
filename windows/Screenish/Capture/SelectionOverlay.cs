//
//  SelectionOverlay.cs
//  Screenish
//
//  One borderless overlay window PER display (a single window cannot span
//  monitors with different DPI cleanly). Each shows its slice of the frozen
//  desktop, dimmed. The controller holds the shared drag state in physical
//  screen pixels; every view draws its slice of the selection. In window mode
//  the hovered window is highlighted.
//

using System.Diagnostics;
using System.Globalization;
using System.Text;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Forms = System.Windows.Forms;

namespace Screenish;

internal enum OverlayMode { Region, Window }

internal readonly record struct PickedWindow(IntPtr Handle, Int32Rect Bounds);

/// Exactly one of Region / Window is set; neither = cancelled.
internal readonly record struct OverlayResult(Int32Rect? Region, PickedWindow? Window)
{
    public static readonly OverlayResult Cancelled = new(null, null);
}

internal sealed class SelectionOverlayController
{
    private readonly List<OverlayWindow> _windows = [];
    private OverlayMode _mode;
    private TaskCompletionSource<OverlayResult>? _completion;

    // Shared drag/hover state, all in physical screen pixels.
    private Point? _dragStart;
    private Point? _dragCurrent;
    private PickedWindow? _hover;

    // Window-mode snapshot. The window list is captured once on entry so hover
    // hit-tests are a cheap point-in-rect scan instead of a system query per move.
    private List<PickedWindow>? _windowSnapshot;

    public Task<OverlayResult> Present(OverlayMode mode, FrozenDesktop frozen)
    {
        // Defensive: never overwrite a live session (would leak its task).
        if (_completion != null) Finish(OverlayResult.Cancelled);

        _completion = new TaskCompletionSource<OverlayResult>();
        _mode = mode;
        _dragStart = _dragCurrent = null;
        _hover = null;
        _windowSnapshot = mode == OverlayMode.Window ? WindowPicker.Snapshot() : null;

        var cursor = Native.CursorPosition();
        OverlayWindow? underCursor = null;
        foreach (var screen in Forms.Screen.AllScreens)
        {
            var b = screen.Bounds;
            var bounds = new Int32Rect(b.X, b.Y, b.Width, b.Height);
            var slice = new CroppedBitmap(frozen.Image, new Int32Rect(
                b.X - frozen.Bounds.X, b.Y - frozen.Bounds.Y, b.Width, b.Height));
            slice.Freeze();
            var window = new OverlayWindow(this, bounds, slice, mode);
            _windows.Add(window);
            window.Show();
            if (b.Contains(cursor.X, cursor.Y)) underCursor = window;
        }
        // Key window = the one under the cursor, so Esc works immediately.
        (underCursor ?? _windows.FirstOrDefault())?.TakeFocus();
        if (mode == OverlayMode.Window) Moved(new Point(cursor.X, cursor.Y));

        return _completion.Task;
    }

    // MARK: - Event intake (physical screen coordinates)

    public void Began(Point p)
    {
        if (_mode != OverlayMode.Region) return;
        _dragStart = _dragCurrent = p;
        Redraw();
    }

    public void Dragged(Point p)
    {
        if (_mode != OverlayMode.Region || _dragStart == null) return;
        _dragCurrent = p;
        Redraw();
    }

    public void Ended()
    {
        if (_mode == OverlayMode.Region)
        {
            if (CurrentRect() is Int32Rect rect && rect.Width >= 3 && rect.Height >= 3)
                Finish(new OverlayResult(rect, null));
            else
                Finish(OverlayResult.Cancelled);
        }
        else
        {
            Finish(_hover is { } window ? new OverlayResult(null, window) : OverlayResult.Cancelled);
        }
    }

    public void Moved(Point p)
    {
        if (_mode != OverlayMode.Window) return;
        _hover = null;
        foreach (var window in _windowSnapshot ?? [])
        {
            var b = window.Bounds;
            if (p.X < b.X || p.X >= b.X + b.Width || p.Y < b.Y || p.Y >= b.Y + b.Height) continue;
            _hover = window;   // front-to-back order → first hit is the frontmost
            break;
        }
        Redraw();
    }

    public void Cancel() => Finish(OverlayResult.Cancelled);

    /// The current highlight rect in screen pixels (selection or hovered window).
    public Int32Rect? SelectionRect => _mode == OverlayMode.Region ? CurrentRect() : _hover?.Bounds;

    private Int32Rect? CurrentRect()
    {
        if (_dragStart is not Point s || _dragCurrent is not Point c) return null;
        int x0 = (int)Math.Min(s.X, c.X), y0 = (int)Math.Min(s.Y, c.Y);
        int x1 = (int)Math.Max(s.X, c.X), y1 = (int)Math.Max(s.Y, c.Y);
        return new Int32Rect(x0, y0, x1 - x0, y1 - y0);
    }

    private void Redraw()
    {
        foreach (var window in _windows) window.Redraw();
    }

    private void Finish(OverlayResult result)
    {
        var completion = _completion;
        _completion = null;
        foreach (var window in _windows.ToList()) window.CloseQuietly();
        _windows.Clear();
        _windowSnapshot = null;
        completion?.TrySetResult(result);
    }
}

/// Borderless, topmost window covering exactly one monitor.
internal sealed class OverlayWindow : Window
{
    private readonly SelectionOverlayController _controller;
    private readonly Int32Rect _screenBounds;   // physical pixels
    private readonly SelectionView _view;
    private bool _closing;

    public OverlayWindow(SelectionOverlayController controller, Int32Rect screenBounds,
                         BitmapSource slice, OverlayMode mode)
    {
        _controller = controller;
        _screenBounds = screenBounds;

        WindowStyle = WindowStyle.None;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        Topmost = true;
        ShowActivated = false;   // only the window under the cursor takes focus (TakeFocus)
        WindowStartupLocation = WindowStartupLocation.Manual;
        Background = Brushes.Black;
        Cursor = Cursors.Cross;
        Left = Top = 0; Width = Height = 100;   // real bounds are applied in pixels below

        Content = _view = new SelectionView(controller, screenBounds, slice, mode);

        SourceInitialized += (_, _) =>
        {
            Native.AddExStyle(new WindowInteropHelper(this).Handle, Native.WS_EX_TOOLWINDOW);
            ApplyBounds();
        };
        // Moving onto a monitor with another DPI makes WPF resize the window; re-pin it.
        Loaded += (_, _) => ApplyBounds();
        DpiChanged += (_, _) => Dispatcher.BeginInvoke(ApplyBounds);

        KeyDown += (_, e) => { if (e.Key == Key.Escape) _controller.Cancel(); };
        MouseRightButtonDown += (_, _) => _controller.Cancel();
        // Alt+Tab away (or anything else stealing focus) abandons the capture.
        Deactivated += (_, _) =>
        {
            if (_closing) return;
            Dispatcher.BeginInvoke(() =>
            {
                if (!_closing && !Application.Current.Windows.OfType<OverlayWindow>().Any(w => w.IsActive))
                    _controller.Cancel();
            });
        };
    }

    private void ApplyBounds()
    {
        var hwnd = new WindowInteropHelper(this).Handle;
        if (hwnd == IntPtr.Zero || _closing) return;
        Native.SetWindowPos(hwnd, Native.HWND_TOPMOST, _screenBounds.X, _screenBounds.Y,
                            _screenBounds.Width, _screenBounds.Height, Native.SWP_NOACTIVATE);
    }

    public void TakeFocus()
    {
        Activate();
        Native.SetForegroundWindow(new WindowInteropHelper(this).Handle);
        Focus();
    }

    public void Redraw() => _view.InvalidateVisual();

    public void CloseQuietly()
    {
        _closing = true;
        Close();
    }
}

internal sealed class SelectionView : FrameworkElement
{
    private static readonly Brush Dim = Frozen(new SolidColorBrush(Color.FromArgb(89, 0, 0, 0)));        // 0.35
    private static readonly Brush LabelBg = Frozen(new SolidColorBrush(Color.FromArgb(191, 0, 0, 0)));   // 0.75

    private readonly SelectionOverlayController _controller;
    private readonly Int32Rect _screenBounds;
    private readonly BitmapSource _slice;
    private readonly OverlayMode _mode;

    public SelectionView(SelectionOverlayController controller, Int32Rect screenBounds,
                         BitmapSource slice, OverlayMode mode)
    {
        _controller = controller;
        _screenBounds = screenBounds;
        _slice = slice;
        _mode = mode;
        Focusable = true;
        RenderOptions.SetBitmapScalingMode(this, BitmapScalingMode.NearestNeighbor);
    }

    private static Brush Frozen(Brush brush) { brush.Freeze(); return brush; }

    /// Mouse position in physical screen pixels — straight from the system, so it
    /// is right on every monitor regardless of per-monitor DPI.
    private static Point ScreenPoint()
    {
        var p = Native.CursorPosition();
        return new Point(p.X, p.Y);
    }

    // MARK: - Mouse

    protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e)
    {
        CaptureMouse();   // keep receiving the drag when it crosses onto another monitor
        _controller.Began(ScreenPoint());
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        if (e.LeftButton == MouseButtonState.Pressed) _controller.Dragged(ScreenPoint());
        else _controller.Moved(ScreenPoint());
    }

    protected override void OnMouseLeftButtonUp(MouseButtonEventArgs e)
    {
        ReleaseMouseCapture();
        _controller.Ended();
    }

    // MARK: - Drawing

    protected override void OnRender(DrawingContext dc)
    {
        var bounds = new Rect(0, 0, ActualWidth, ActualHeight);
        if (bounds.Width <= 0 || bounds.Height <= 0) return;
        dc.DrawImage(_slice, bounds);

        // Screen pixels → this view's DIPs.
        double sx = ActualWidth / _screenBounds.Width, sy = ActualHeight / _screenBounds.Height;
        Rect? local = null;
        if (_controller.SelectionRect is Int32Rect global)
        {
            var screen = new Rect(_screenBounds.X, _screenBounds.Y, _screenBounds.Width, _screenBounds.Height);
            var inter = Rect.Intersect(new Rect(global.X, global.Y, global.Width, global.Height), screen);
            if (!inter.IsEmpty && inter.Width > 0 && inter.Height > 0)
                local = new Rect((inter.X - screen.X) * sx, (inter.Y - screen.Y) * sy, inter.Width * sx, inter.Height * sy);
        }

        if (local is not Rect hole)
        {
            dc.DrawRectangle(Dim, null, bounds);
            return;
        }

        // Dim everything except the selection, which keeps showing the real pixels.
        var mask = new CombinedGeometry(GeometryCombineMode.Exclude,
                                        new RectangleGeometry(bounds), new RectangleGeometry(hole));
        dc.DrawGeometry(Dim, null, mask);
        dc.DrawRectangle(null, new Pen(Theme.AccentBrush, 2), hole);

        if (_mode == OverlayMode.Region && _controller.SelectionRect is Int32Rect full)
            DrawDimensionLabel(dc, full, hole, bounds);
    }

    private void DrawDimensionLabel(DrawingContext dc, Int32Rect selection, Rect anchor, Rect bounds)
    {
        var text = new FormattedText($"{selection.Width} × {selection.Height}", CultureInfo.InvariantCulture,
            FlowDirection.LeftToRight,
            new Typeface(new FontFamily("Segoe UI"), FontStyles.Normal, FontWeights.SemiBold, FontStretches.Normal),
            12, Brushes.White, VisualTreeHelper.GetDpi(this).PixelsPerDip);
        const double pad = 6;
        double w = text.Width + pad * 2, h = text.Height + pad * 2;
        double y = anchor.Top - 6 - h;
        if (y < bounds.Top) y = anchor.Bottom + 6;                      // no room above → below
        if (y + h > bounds.Bottom) y = anchor.Top + 6;                  // nor below → inside
        double x = Math.Min(anchor.Left, bounds.Right - w);
        var bg = new Rect(Math.Max(x, bounds.Left), y, w, h);
        dc.DrawRoundedRectangle(LabelBg, null, bg, 5, 5);
        dc.DrawText(text, new Point(bg.X + pad, bg.Y + pad));
    }
}

/// Finds the frontmost on-screen window under a screen point.
///
/// The expensive part — enumerating top-level windows and querying DWM — is
/// done once via `Snapshot()`. The result answers per-point hover queries with a
/// cheap point-in-rect scan.
internal static class WindowPicker
{
    // Desktop + taskbar shells: never a capture target (the macOS client likewise
    // only offers normal-layer windows).
    private static readonly HashSet<string> IgnoredClasses =
        ["Progman", "WorkerW", "Shell_TrayWnd", "Shell_SecondaryTrayWnd", "Windows.UI.Core.CoreWindow"];

    /// Eligible on-screen windows (own process excluded) in front-to-back order,
    /// with their visible bounds in physical screen pixels.
    public static List<PickedWindow> Snapshot()
    {
        var windows = new List<PickedWindow>();
        uint ownPid = (uint)Environment.ProcessId;
        var className = new StringBuilder(256);

        Native.EnumWindows((hwnd, _) =>
        {
            if (!Native.IsWindowVisible(hwnd) || Native.IsIconic(hwnd)) return true;
            Native.GetWindowThreadProcessId(hwnd, out var pid);
            if (pid == ownPid) return true;
            // Cloaked = exists but not shown (other virtual desktop, suspended UWP).
            if (Native.DwmGetWindowAttribute(hwnd, Native.DWMWA_CLOAKED, out int cloaked, sizeof(int)) == 0
                && cloaked != 0) return true;
            className.Clear();
            Native.GetClassName(hwnd, className, className.Capacity);
            if (IgnoredClasses.Contains(className.ToString())) return true;

            // The extended frame excludes the invisible resize border GetWindowRect includes.
            if (Native.DwmGetWindowAttribute(hwnd, Native.DWMWA_EXTENDED_FRAME_BOUNDS, out Native.RECT rect,
                    System.Runtime.InteropServices.Marshal.SizeOf<Native.RECT>()) != 0
                && !Native.GetWindowRect(hwnd, out rect)) return true;
            if (rect.Width < 8 || rect.Height < 8) return true;

            windows.Add(new PickedWindow(hwnd, new Int32Rect(rect.Left, rect.Top, rect.Width, rect.Height)));
            return true;
        }, IntPtr.Zero);

        Debug.WriteLine($"window snapshot: {windows.Count}");
        return windows;
    }
}
