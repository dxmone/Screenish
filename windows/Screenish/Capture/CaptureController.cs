//
//  CaptureController.cs
//  Screenish
//
//  Orchestrates a capture: freezes the desktop (our own windows excluded),
//  drives the selection overlay, and cuts the pixels out. Everything is in
//  physical pixels of the virtual desktop, so mixed-DPI setups just work.
//

using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Drawing = System.Drawing;
using Forms = System.Windows.Forms;

namespace Screenish;

internal enum CaptureMode { Region, Window, Screen }

internal sealed class CaptureController
{
    private readonly SelectionOverlayController _overlay = new();

    /// Run a capture for the given mode. Returns null on cancel/failure.
    public async Task<BitmapSource?> Capture(CaptureMode mode)
    {
        try
        {
            switch (mode)
            {
                case CaptureMode.Region:
                {
                    var frozen = ScreenGrabber.GrabVirtualScreen();
                    var result = await _overlay.Present(OverlayMode.Region, frozen);
                    return result.Region is Int32Rect rect ? frozen.Crop(rect) : null;
                }
                case CaptureMode.Window:
                {
                    var frozen = ScreenGrabber.GrabVirtualScreen();
                    var result = await _overlay.Present(OverlayMode.Window, frozen);
                    if (result.Window is not { } window) return null;
                    // Prefer the window's own rendering (complete even when other
                    // windows overlap it); fall back to the frozen desktop pixels.
                    return ScreenGrabber.GrabWindow(window.Handle, window.Bounds) ?? frozen.Crop(window.Bounds);
                }
                default:
                    return ScreenGrabber.GrabScreenUnderCursor();
            }
        }
        catch (Exception ex)
        {
            Log.Error($"capture failed ({mode}): {ex.Message}");
            return null;
        }
    }
}

/// A grab of the whole virtual desktop plus where it sits in screen coordinates.
internal sealed record FrozenDesktop(BitmapSource Image, Int32Rect Bounds)
{
    /// Cut a screen-space rect out into a standalone bitmap (detached from the
    /// full-desktop backing store, which can be 100+ MB on multi-monitor setups).
    public BitmapSource? Crop(Int32Rect screenRect)
    {
        int x0 = Math.Max(screenRect.X, Bounds.X), y0 = Math.Max(screenRect.Y, Bounds.Y);
        int x1 = Math.Min(screenRect.X + screenRect.Width, Bounds.X + Bounds.Width);
        int y1 = Math.Min(screenRect.Y + screenRect.Height, Bounds.Y + Bounds.Height);
        if (x1 - x0 < 1 || y1 - y0 < 1) return null;
        return Pixels.Crop(Image, new Int32Rect(x0 - Bounds.X, y0 - Bounds.Y, x1 - x0, y1 - y0));
    }
}

internal static class ScreenGrabber
{
    public static FrozenDesktop GrabVirtualScreen()
    {
        var v = Forms.SystemInformation.VirtualScreen;
        var bounds = new Int32Rect(v.X, v.Y, v.Width, v.Height);
        return new FrozenDesktop(GrabScreenRect(bounds), bounds);
    }

    public static BitmapSource GrabScreenUnderCursor()
    {
        var cursor = Native.CursorPosition();
        var b = Forms.Screen.FromPoint(new Drawing.Point(cursor.X, cursor.Y)).Bounds;
        return GrabScreenRect(new Int32Rect(b.X, b.Y, b.Width, b.Height));
    }

    /// Copy a screen rect. Our own windows (stack panel, editor, settings) are
    /// excluded from the capture for its duration so they never end up in a shot;
    /// the mouse cursor is never part of a GDI screen copy.
    private static BitmapSource GrabScreenRect(Int32Rect rect)
    {
        var own = OwnWindowHandles();
        foreach (var hwnd in own) Native.SetWindowDisplayAffinity(hwnd, Native.WDA_EXCLUDEFROMCAPTURE);
        try
        {
            if (own.Count > 0)
            {
                // Let the compositor present a frame without our windows.
                Native.DwmFlush();
                Native.DwmFlush();
            }
            using var bitmap = new Drawing.Bitmap(rect.Width, rect.Height, Drawing.Imaging.PixelFormat.Format32bppRgb);
            using (var g = Drawing.Graphics.FromImage(bitmap))
                g.CopyFromScreen(rect.X, rect.Y, 0, 0, new Drawing.Size(rect.Width, rect.Height));
            return ToBitmapSource(bitmap);
        }
        finally
        {
            foreach (var hwnd in own) Native.SetWindowDisplayAffinity(hwnd, Native.WDA_NONE);
        }
    }

    private static List<IntPtr> OwnWindowHandles()
    {
        var handles = new List<IntPtr>();
        foreach (Window window in Application.Current.Windows)
        {
            if (!window.IsVisible) continue;
            var hwnd = new WindowInteropHelper(window).Handle;
            if (hwnd != IntPtr.Zero) handles.Add(hwnd);
        }
        return handles;
    }

    /// Ask the window to render itself (PrintWindow), so it comes out complete even
    /// if partly covered or off-screen. Returns null when the window won't cooperate
    /// (some GPU surfaces render black) — the caller then crops the frozen desktop.
    public static BitmapSource? GrabWindow(IntPtr hwnd, Int32Rect visibleBounds)
    {
        if (!Native.GetWindowRect(hwnd, out var full) || full.Width < 1 || full.Height < 1) return null;
        using var bitmap = new Drawing.Bitmap(full.Width, full.Height, Drawing.Imaging.PixelFormat.Format32bppRgb);
        using (var g = Drawing.Graphics.FromImage(bitmap))
        {
            var hdc = g.GetHdc();
            bool ok;
            try { ok = Native.PrintWindow(hwnd, hdc, Native.PW_RENDERFULLCONTENT); }
            finally { g.ReleaseHdc(hdc); }
            if (!ok) return null;
        }

        // GetWindowRect includes the invisible resize border; keep only the visible frame.
        var crop = new Drawing.Rectangle(visibleBounds.X - full.Left, visibleBounds.Y - full.Top,
                                         visibleBounds.Width, visibleBounds.Height);
        crop.Intersect(new Drawing.Rectangle(0, 0, full.Width, full.Height));
        if (crop.Width < 1 || crop.Height < 1) return null;

        var image = ToBitmapSource(bitmap);
        var cropped = Pixels.Crop(image, new Int32Rect(crop.X, crop.Y, crop.Width, crop.Height));
        return IsBlank(cropped) ? null : cropped;
    }

    /// True when every sampled pixel is black — PrintWindow's failure mode.
    private static bool IsBlank(BitmapSource image)
    {
        var bytes = Pixels.CopyBgra(image);
        int step = Math.Max(4, bytes.Length / 4 / 4096 * 4);
        for (int i = 0; i < bytes.Length - 3; i += step)
            if (bytes[i] != 0 || bytes[i + 1] != 0 || bytes[i + 2] != 0) return false;
        return true;
    }

    private static BitmapSource ToBitmapSource(Drawing.Bitmap bitmap)
    {
        var data = bitmap.LockBits(new Drawing.Rectangle(0, 0, bitmap.Width, bitmap.Height),
                                   Drawing.Imaging.ImageLockMode.ReadOnly,
                                   Drawing.Imaging.PixelFormat.Format32bppRgb);
        try
        {
            // Bgr32 ignores the (undefined) alpha byte of a screen copy → fully opaque.
            var source = BitmapSource.Create(bitmap.Width, bitmap.Height, 96, 96, PixelFormats.Bgr32, null,
                                             data.Scan0, data.Stride * bitmap.Height, data.Stride);
            source.Freeze();
            return source;
        }
        finally
        {
            bitmap.UnlockBits(data);
        }
    }
}
