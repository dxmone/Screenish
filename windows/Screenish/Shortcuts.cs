//
//  Shortcuts.cs
//  Screenish
//
//  Global hotkeys (RegisterHotKey on a message-only window). Defaults use
//  Ctrl+Shift+number — the same chords as the macOS client, and clear of the
//  Windows system screenshot shortcuts (Win+Shift+S, PrtSc).
//

using System.Text.Json.Nodes;
using System.Windows.Input;
using System.Windows.Interop;

namespace Screenish;

/// A key chord: RegisterHotKey modifier flags + a virtual-key code.
internal sealed record Hotkey(uint Modifiers, int VirtualKey)
{
    public static Hotkey Default(CaptureMode mode) => new(Native.MOD_CONTROL | Native.MOD_SHIFT, mode switch
    {
        CaptureMode.Region => 0x31,   // 1
        CaptureMode.Window => 0x32,   // 2
        _ => 0x33,                    // 3
    });

    /// "Ctrl+Shift+1"
    public string DisplayString
    {
        get
        {
            var parts = new List<string>();
            if ((Modifiers & Native.MOD_CONTROL) != 0) parts.Add("Ctrl");
            if ((Modifiers & Native.MOD_ALT) != 0) parts.Add("Alt");
            if ((Modifiers & Native.MOD_SHIFT) != 0) parts.Add("Shift");
            if ((Modifiers & Native.MOD_WIN) != 0) parts.Add("Win");
            parts.Add(KeyName(KeyInterop.KeyFromVirtualKey(VirtualKey)));
            return string.Join("+", parts);
        }
    }

    private static string KeyName(Key key) => key switch
    {
        >= Key.D0 and <= Key.D9 => ((int)key - (int)Key.D0).ToString(),
        >= Key.NumPad0 and <= Key.NumPad9 => "Num " + ((int)key - (int)Key.NumPad0),
        Key.OemComma => ",", Key.OemPeriod => ".", Key.OemMinus => "-", Key.OemPlus => "+",
        Key.Snapshot => "PrtSc", Key.Return => "Enter", Key.Next => "PgDn", Key.Prior => "PgUp",
        _ => key.ToString(),
    };

    public JsonObject ToJson() => new() { ["modifiers"] = Modifiers, ["key"] = VirtualKey };

    public static Hotkey? FromJson(JsonNode node)
    {
        try
        {
            if (node["key"] is null) return null;
            return new Hotkey((uint)node["modifiers"]!, (int)node["key"]!);
        }
        catch { return null; }
    }
}

internal sealed class HotkeyManager : IDisposable
{
    private readonly HwndSource _source;
    private readonly Dictionary<int, CaptureMode> _registered = new();

    public event Action<CaptureMode>? Pressed;

    public HotkeyManager()
    {
        _source = new HwndSource(new HwndSourceParameters("ScreenishHotkeys")
        {
            ParentWindow = Native.HWND_MESSAGE, Width = 0, Height = 0, WindowStyle = 0,
        });
        _source.AddHook(WndProc);
    }

    /// (Re)register every configured hotkey. Returns the modes whose chord could
    /// not be registered (already taken by another app).
    public List<CaptureMode> RegisterAll()
    {
        UnregisterAll();
        var failed = new List<CaptureMode>();
        foreach (var mode in Enum.GetValues<CaptureMode>())
        {
            if (Prefs.GetHotkey(mode) is not { } hotkey) continue;
            int id = (int)mode + 1;
            if (Native.RegisterHotKey(_source.Handle, id, hotkey.Modifiers | Native.MOD_NOREPEAT,
                                      (uint)hotkey.VirtualKey))
                _registered[id] = mode;
            else
                failed.Add(mode);
        }
        return failed;
    }

    /// Release the chords, e.g. while the settings recorder listens for a new one.
    public void UnregisterAll()
    {
        foreach (var id in _registered.Keys) Native.UnregisterHotKey(_source.Handle, id);
        _registered.Clear();
    }

    private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == Native.WM_HOTKEY && _registered.TryGetValue(wParam.ToInt32(), out var mode))
        {
            handled = true;
            Pressed?.Invoke(mode);
        }
        return IntPtr.Zero;
    }

    public void Dispose()
    {
        UnregisterAll();
        _source.Dispose();
    }
}
