//
//  ShotStore.cs
//  Screenish
//
//  Owns the live set of Shots shown in the floating Stack and the
//  lifecycle of their temp files. Shots persist until manually dismissed;
//  temp files are cleaned up on quit.
//

using System.IO;
using System.Windows;
using System.Windows.Media.Imaging;

namespace Screenish;

internal sealed class ShotStore
{
    private readonly List<Shot> _shots = [];

    /// Newest first.
    public IReadOnlyList<Shot> Shots => _shots;

    public event Action? Changed;

    /// Capture → Stack. The in-memory rendered composite is authoritative, so the
    /// shot is built and shown synchronously; the PNG is encoded + written to its
    /// deterministic temp path off the UI thread. Returns the created Shot.
    public Shot Add(BitmapSource capturedImage)
    {
        var id = Guid.NewGuid();
        var background = Prefs.DefaultBackground;   // remembered beautify
        var rendered = background.IsEmpty ? capturedImage
            : EditorRenderer.RenderComposite(capturedImage, [], null, background);
        var shot = new Shot
        {
            Id = id, BaseImage = capturedImage, Background = background, Image = rendered,
            Thumbnail = ImageExport.Thumbnail(rendered), TempPath = ImageExport.TempPath(id),
        };
        _shots.Insert(0, shot);
        WriteTempOffThread(rendered, shot.TempPath);
        Changed?.Invoke();
        return shot;
    }

    /// Apply edited annotations/crop to a Shot non-destructively: keep the original
    /// `BaseImage`, store the layers, and cache a freshly rendered composite. Keeps
    /// id/position/timestamp and bumps `Revision` so the Stack updates live.
    /// Returns the rendered composite.
    public BitmapSource? ApplyEdits(Shot shot, IReadOnlyList<Annotation> annotations, Rect? cropRect,
                                    BackgroundStyle background)
    {
        int index = _shots.FindIndex(s => s.Id == shot.Id);
        if (index < 0) return null;
        var current = _shots[index];
        var rendered = EditorRenderer.RenderComposite(current.BaseImage, annotations, cropRect, background);
        _shots[index] = current with
        {
            Annotations = annotations.ToList(), CropRect = cropRect, Background = background,
            Image = rendered, Thumbnail = ImageExport.Thumbnail(rendered), Revision = current.Revision + 1,
        };
        WriteTempOffThread(rendered, current.TempPath);
        Changed?.Invoke();
        return rendered;
    }

    /// The current state of a shot (callers may hold the revision they opened with).
    public Shot? Find(Guid id) => _shots.Find(s => s.Id == id);

    /// PNG-encode + write a composite to its temp path off the UI thread. The
    /// in-memory image is authoritative, so failures are logged, not surfaced.
    /// Frozen bitmaps are safe to read from any thread.
    private static void WriteTempOffThread(BitmapSource image, string path)
    {
        Task.Run(() =>
        {
            try { File.WriteAllBytes(path, ImageExport.Encode(image, ImageFormat.Png)); }
            catch (Exception ex) { Log.Error("failed to write temp shot: " + ex.Message); }
        });
    }

    public void Remove(Shot shot)
    {
        try { File.Delete(shot.TempPath); } catch { }
        if (_shots.RemoveAll(s => s.Id == shot.Id) == 0) return;
        AnnotationDrawer.Forget(shot.BaseImage);
        Changed?.Invoke();
    }

    /// Remove the entire temp directory; call on app termination.
    public void CleanupTempDirectory()
    {
        try { Directory.Delete(ImageExport.TempDirectory, recursive: true); } catch { }
    }
}
