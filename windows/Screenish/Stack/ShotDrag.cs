//
//  ShotDrag.cs
//  Screenish
//
//  Shared drag-out: writes the image EAGERLY to a scratch file at drag start and
//  drags a real file path (CF_HDROP), so the drop works in Explorer, terminals,
//  mail and chat/Electron apps alike. Also the folder-save helper + save alert.
//

using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace Screenish;

internal static class ShotDrag
{
    /// Drag scratch lives in LocalAppData, not %TEMP% (which cleanup tools reap), so
    /// a dragged file's path keeps resolving for the whole session — path-referencing
    /// targets like a terminal read the file after the drag ends. Swept at next launch.
    public static string DragDirectory
    {
        get
        {
            var dir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Screenish", "drag");
            Directory.CreateDirectory(dir);
            return dir;
        }
    }

    /// Purge drag copies left by previous sessions. Drag copies outlive their drag,
    /// so they accumulate until swept here at launch.
    public static void SweepDragDirectory() => ImageExport.Sweep(DragDirectory);

    /// Run a file drag for `image`, blocking until the drop completes. Returns true
    /// when a target accepted the file, false when cancelled or on failure.
    public static bool Run(DependencyObject source, BitmapSource image, DateTime date)
    {
        var format = Prefs.Format;
        string path;
        try
        {
            // Unique name, bumping on collision: the files outlive their drag, so a
            // same-second write must never clobber a path an earlier drag handed out.
            path = ImageExport.UniquePath(DragDirectory, ImageExport.BaseName(date), format.Ext());
            File.WriteAllBytes(path, ImageExport.Encode(image, format));
        }
        catch (Exception ex)
        {
            Log.Error("drag aborted: " + ex.Message);
            return false;
        }

        var data = new DataObject(DataFormats.FileDrop, new[] { path });
        using var ghost = new DragGhost(image);
        GiveFeedbackEventHandler follow = (_, _) => ghost.FollowCursor();
        if (source is UIElement element) element.GiveFeedback += follow;

        Log.Breadcrumb("drag begin: " + Path.GetFileName(path));
        DragDropEffects effect;
        try
        {
            ghost.FollowCursor();
            effect = DragDrop.DoDragDrop(source, data, DragDropEffects.Copy);
        }
        finally
        {
            if (source is UIElement e) e.GiveFeedback -= follow;
        }

        // Don't delete the dragged file here: path-referencing targets only capture
        // the path during the drag and read it later. It's swept at next launch.
        Log.Breadcrumb(effect == DragDropEffects.None ? "drag cancelled" : "drag delivered: " + effect);
        return effect != DragDropEffects.None;
    }

    /// Save a shot to a folder with its user-facing name + format. Throws so the
    /// caller can alert the user instead of silently reporting success.
    public static string Save(Shot shot, string directory) =>
        ImageExport.Write(shot.Image, directory, Prefs.Format, shot.CreatedAt);

    /// Modal alert telling the user a save failed — used by every save call site so a
    /// failed write is never reported as success.
    public static void PresentSaveError(Exception error, Window? owner = null)
    {
        var text = Loc.T("Couldn’t save the screenshot") + "\n\n" + error.Message;
        if (owner != null) MessageBox.Show(owner, text, "Screenish", MessageBoxButton.OK, MessageBoxImage.Warning);
        else MessageBox.Show(text, "Screenish", MessageBoxButton.OK, MessageBoxImage.Warning);
    }
}

/// A small click-through thumbnail window that follows the cursor during a drag
/// (OLE drag-and-drop shows no image of its own for a plain file drop).
internal sealed class DragGhost : IDisposable
{
    private readonly Window _window;
    private readonly int _width, _height;

    public DragGhost(BitmapSource image)
    {
        const double maxW = 200;
        double scale = Math.Min(1, maxW / Math.Max(image.PixelWidth, 1));
        _width = Math.Max(1, (int)Math.Round(image.PixelWidth * scale));
        _height = Math.Max(1, (int)Math.Round(image.PixelHeight * scale));

        _window = new Window
        {
            WindowStyle = WindowStyle.None, AllowsTransparency = true, Background = Brushes.Transparent,
            ShowInTaskbar = false, Topmost = true, ShowActivated = false, IsHitTestVisible = false,
            ResizeMode = ResizeMode.NoResize, Opacity = 0.85,
            Left = -10000, Top = -10000, Width = 10, Height = 10,
            Content = new Image { Source = ImageExport.Thumbnail(image, 400), Stretch = Stretch.Fill },
        };
        _window.SourceInitialized += (_, _) => Native.AddExStyle(new WindowInteropHelper(_window).Handle,
            Native.WS_EX_TRANSPARENT | Native.WS_EX_NOACTIVATE | Native.WS_EX_TOOLWINDOW);
        _window.Show();
    }

    /// Center the thumbnail on the cursor (physical pixels, any monitor).
    public void FollowCursor()
    {
        var p = Native.CursorPosition();
        var hwnd = new WindowInteropHelper(_window).Handle;
        Native.SetWindowPos(hwnd, Native.HWND_TOPMOST, p.X - _width / 2, p.Y - _height / 2, _width, _height,
                            Native.SWP_NOACTIVATE);
    }

    public void Dispose() => _window.Close();
}
