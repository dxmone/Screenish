//
//  Pixels.cs
//  Screenish
//
//  Raw-pixel helpers: BGRA access to a BitmapSource, a separable box blur (three
//  passes ≈ gaussian), and rendering a DrawingVisual to a frozen bitmap. WPF has
//  no blend modes or image filters that survive software rendering reliably, so
//  blur / pixelate / multiply / soft shadows are computed here.
//

using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace Screenish;

internal static class Pixels
{
    private static readonly ConditionalWeakTable<BitmapSource, byte[]> BgraCache = new();

    /// Straight-alpha BGRA bytes of a bitmap, cached per bitmap instance (the base
    /// image of a shot is immutable, so the copy never goes stale).
    public static byte[] Bgra(BitmapSource source) => BgraCache.GetValue(source, CopyBgra);

    public static byte[] CopyBgra(BitmapSource source)
    {
        BitmapSource converted = source.Format == PixelFormats.Bgra32
            ? source : new FormatConvertedBitmap(source, PixelFormats.Bgra32, null, 0);
        var bytes = new byte[source.PixelWidth * source.PixelHeight * 4];
        converted.CopyPixels(bytes, source.PixelWidth * 4, 0);
        return bytes;
    }

    public static BitmapSource FromBgra(byte[] bytes, int width, int height, bool premultiplied = false)
    {
        var bmp = BitmapSource.Create(width, height, 96, 96,
            premultiplied ? PixelFormats.Pbgra32 : PixelFormats.Bgra32, null, bytes, width * 4);
        bmp.Freeze();
        return bmp;
    }

    /// Render a visual into a frozen pixel-exact bitmap (1 unit = 1 pixel).
    public static BitmapSource Render(Visual visual, int width, int height)
    {
        var rtb = new RenderTargetBitmap(Math.Max(width, 1), Math.Max(height, 1), 96, 96, PixelFormats.Pbgra32);
        rtb.Render(visual);
        rtb.Freeze();
        return rtb;
    }

    public static BitmapSource Render(int width, int height, Action<DrawingContext> draw)
    {
        var visual = new DrawingVisual();
        RenderOptions.SetBitmapScalingMode(visual, BitmapScalingMode.HighQuality);
        using (var dc = visual.RenderOpen()) draw(dc);
        return Render(visual, width, height);
    }

    /// Normalize any bitmap to a frozen 96-DPI Pbgra32 copy with its own backing
    /// store, so it no longer references a parent (e.g. a CroppedBitmap's source).
    public static BitmapSource Detach(BitmapSource source)
    {
        var bytes = new byte[source.PixelWidth * source.PixelHeight * 4];
        BitmapSource converted = source.Format == PixelFormats.Pbgra32
            ? source : new FormatConvertedBitmap(source, PixelFormats.Pbgra32, null, 0);
        converted.CopyPixels(bytes, source.PixelWidth * 4, 0);
        return FromBgra(bytes, source.PixelWidth, source.PixelHeight, premultiplied: true);
    }

    public static BitmapSource Crop(BitmapSource source, Int32Rect rect) =>
        Detach(new CroppedBitmap(source, rect));

    /// Three box-blur passes over interleaved channels ≈ gaussian with `sigma`.
    public static void GaussianBlur(byte[] data, int width, int height, int channels, double sigma)
    {
        if (sigma <= 0 || width < 1 || height < 1) return;
        // Ideal box width for n = 3 passes: w = sqrt(12σ²/n + 1).
        int radius = Math.Max(1, (int)Math.Round((Math.Sqrt(4 * sigma * sigma + 1) - 1) / 2));
        var scratch = new byte[data.Length];
        for (int pass = 0; pass < 3; pass++)
        {
            BoxPass(data, scratch, width, height, channels, radius, horizontal: true);
            BoxPass(scratch, data, width, height, channels, radius, horizontal: false);
        }
    }

    /// One running-sum box pass with clamped edges (the edge pixel extends outward).
    private static void BoxPass(byte[] src, byte[] dst, int width, int height, int channels,
                                int radius, bool horizontal)
    {
        int length = horizontal ? width : height;
        int lines = horizontal ? height : width;
        int step = horizontal ? channels : width * channels;
        int window = radius * 2 + 1;

        for (int line = 0; line < lines; line++)
        {
            int origin = horizontal ? line * width * channels : line * channels;
            for (int c = 0; c < channels; c++)
            {
                int sum = 0;
                for (int i = -radius; i <= radius; i++)
                    sum += src[origin + Math.Clamp(i, 0, length - 1) * step + c];
                for (int i = 0; i < length; i++)
                {
                    dst[origin + i * step + c] = (byte)((sum + window / 2) / window);
                    int leaving = Math.Clamp(i - radius, 0, length - 1);
                    int entering = Math.Clamp(i + radius + 1, 0, length - 1);
                    sum += src[origin + entering * step + c] - src[origin + leaving * step + c];
                }
            }
        }
    }

    public static Rect Bounds(BitmapSource bitmap) => new(0, 0, bitmap.PixelWidth, bitmap.PixelHeight);
}
