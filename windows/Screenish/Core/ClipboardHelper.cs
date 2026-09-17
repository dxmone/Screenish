//
//  ClipboardHelper.cs
//  Screenish
//
//  Copies a captured image to the clipboard at full quality.
//

using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Media.Imaging;

namespace Screenish;

internal static class ClipboardHelper
{
    public static void Copy(BitmapSource image)
    {
        // A plain bitmap for every app, plus a "PNG" stream that keeps the alpha
        // channel (rounded corners without a fill) for apps that understand it.
        var data = new DataObject();
        data.SetImage(image);
        data.SetData("PNG", new MemoryStream(ImageExport.Encode(image, ImageFormat.Png)));

        // The clipboard is a shared resource; another process may hold it briefly.
        for (int attempt = 0; attempt < 5; attempt++)
        {
            try
            {
                Clipboard.SetDataObject(data, copy: true);
                return;
            }
            catch (COMException)
            {
                Thread.Sleep(40);
            }
        }
        Log.Error("clipboard busy: copy failed");
    }
}
