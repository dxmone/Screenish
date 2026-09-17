//
//  ImageExport.cs
//  Screenish
//
//  Encodes a bitmap to PNG/JPG, owns the temp directory, and builds
//  user-facing file names like "Screenish 2026-06-15 kl 14.32.05.png".
//

using System.Globalization;
using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace Screenish;

internal enum ImageFormat { Png, Jpeg }

internal static class ImageFormatExtensions
{
    public static string Ext(this ImageFormat format) => format == ImageFormat.Png ? "png" : "jpg";
}

/// A save failed in a way the user should hear about (encode or disk write).
internal sealed class ImageExportException(string message, Exception? inner = null) : Exception(message, inner);

internal static class ImageExport
{
    private const int JpegQuality = 80;

    /// Temp directory holding shots until saved, dragged out, or quit. Lives under
    /// the per-user %TEMP%, so it is already private to the account.
    public static string TempDirectory
    {
        get
        {
            var dir = Path.Combine(Path.GetTempPath(), "Screenish");
            Directory.CreateDirectory(dir);
            return dir;
        }
    }

    /// Downsample a composite into a small thumbnail for the Stack card. The long
    /// side is capped at `maxLongSide` (≈ card width × max screen scale) so the card
    /// holds a tiny texture instead of the full multi-MB composite.
    public static BitmapSource Thumbnail(BitmapSource image, double maxLongSide = 360)
    {
        double longSide = Math.Max(Math.Max(image.PixelWidth, image.PixelHeight), 1);
        if (longSide <= maxLongSide) return image;   // already small enough
        double scale = maxLongSide / longSide;
        int tw = Math.Max((int)Math.Round(image.PixelWidth * scale), 1);
        int th = Math.Max((int)Math.Round(image.PixelHeight * scale), 1);
        try
        {
            return Pixels.Render(tw, th, dc => dc.DrawImage(image, new Rect(0, 0, tw, th)));
        }
        catch
        {
            return image;
        }
    }

    /// Delete leftover temp PNGs from a previous session. Normally cleaned up on a
    /// clean quit, but a crash/force-quit leaves them behind, so sweep at launch
    /// before any capture can write new files.
    public static void SweepTempDirectory() => Sweep(TempDirectory);

    public static void Sweep(string directory)
    {
        try
        {
            foreach (var file in Directory.GetFiles(directory))
            {
                try { File.Delete(file); } catch { }
            }
        }
        catch { }
    }

    /// Encode a bitmap to PNG or JPEG bytes. Safe off the UI thread for frozen bitmaps.
    public static byte[] Encode(BitmapSource image, ImageFormat format)
    {
        BitmapEncoder encoder;
        if (format == ImageFormat.Jpeg)
        {
            encoder = new JpegBitmapEncoder { QualityLevel = JpegQuality };
            image = FlattenOnWhite(image);   // JPEG has no alpha; transparent corners would go black
        }
        else
        {
            encoder = new PngBitmapEncoder();
        }
        encoder.Frames.Add(BitmapFrame.Create(image));
        using var stream = new MemoryStream();
        encoder.Save(stream);
        return stream.ToArray();
    }

    private static BitmapSource FlattenOnWhite(BitmapSource image)
    {
        if (image.Format != PixelFormats.Pbgra32 && image.Format != PixelFormats.Bgra32) return image;
        var bytes = Pixels.CopyBgra(image);
        for (int i = 0; i < bytes.Length; i += 4)
        {
            int a = bytes[i + 3];
            if (a == 255) continue;
            bytes[i] = (byte)((bytes[i] * a + 255 * (255 - a)) / 255);
            bytes[i + 1] = (byte)((bytes[i + 1] * a + 255 * (255 - a)) / 255);
            bytes[i + 2] = (byte)((bytes[i + 2] * a + 255 * (255 - a)) / 255);
            bytes[i + 3] = 255;
        }
        return Pixels.FromBgra(bytes, image.PixelWidth, image.PixelHeight);
    }

    /// Deterministic temp path for a shot id — lets callers build the Shot with its
    /// final path up front and write the bytes later (possibly off-thread).
    public static string TempPath(Guid id) =>
        Path.Combine(TempDirectory, id.ToString().ToUpperInvariant() + ".png");

    /// Write a bitmap to a directory using the user-facing name + format. Creates
    /// the directory if needed and uniques the filename on collision so a same-second
    /// save never silently overwrites. Throws `ImageExportException` so callers can alert.
    public static string Write(BitmapSource image, string directory, ImageFormat format, DateTime date)
    {
        byte[] data;
        try { data = Encode(image, format); }
        catch (Exception ex) { throw new ImageExportException(Loc.T("The image couldn’t be encoded."), ex); }

        try
        {
            Directory.CreateDirectory(directory);
            var path = UniquePath(directory, BaseName(date), format.Ext());
            File.WriteAllBytes(path, data);
            return path;
        }
        catch (Exception ex)
        {
            Log.Error("write failed: " + ex.Message);
            throw new ImageExportException(ex.Message, ex);
        }
    }

    /// First non-colliding path: "<base>.ext", then "<base> 2.ext", "<base> 3.ext", …
    public static string UniquePath(string directory, string baseName, string ext)
    {
        var path = Path.Combine(directory, $"{baseName}.{ext}");
        for (int n = 2; File.Exists(path); n++)
            path = Path.Combine(directory, $"{baseName} {n}.{ext}");
        return path;
    }

    /// Base name without extension, e.g. "Screenish 2026-06-15 kl 14.32.05".
    /// Seconds included so distinct same-minute saves get distinct names.
    public static string BaseName(DateTime date) =>
        "Screenish " + date.ToString("yyyy-MM-dd 'kl' HH.mm.ss", CultureInfo.InvariantCulture);
}
