//
//  Shot.cs
//  Screenish
//
//  A Shot is a captured image — the artifact produced by a Capture.
//  Editing is non-destructive: `BaseImage` is the original capture, `Annotations`
//  + `CropRect` are the editable layers, and `Image` is the rendered composite
//  used for display, clipboard, drag-out, and save. `Revision` bumps on every
//  edit so the Stack re-renders the thumbnail. All bitmaps are frozen.
//

using System.Windows;
using System.Windows.Media.Imaging;

namespace Screenish;

internal sealed record Shot
{
    public required Guid Id { get; init; }
    public required BitmapSource BaseImage { get; init; }       // original capture, never mutated
    public IReadOnlyList<Annotation> Annotations { get; init; } = [];   // editable layers
    public Rect? CropRect { get; init; }                        // editable crop (image-pixel space)
    public BackgroundStyle Background { get; init; } = BackgroundStyle.None;   // editable beautify
    public required BitmapSource Image { get; init; }           // rendered composite
    public required BitmapSource Thumbnail { get; init; }       // small downsampled composite for the Stack card
    public required string TempPath { get; init; }
    public DateTime CreatedAt { get; init; } = DateTime.Now;
    public int Revision { get; init; }
}
