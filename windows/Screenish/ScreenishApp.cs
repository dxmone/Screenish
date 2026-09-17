//
//  ScreenishApp.cs
//  Screenish
//
//  Tray agent: no taskbar button, a notification-area icon with capture
//  commands and Settings. Wires global hotkeys → capture → temp + clipboard + Stack.
//

using System.Windows;
using System.Windows.Threading;
using Forms = System.Windows.Forms;

namespace Screenish;

internal static class App
{
    public static TrayIcon? Tray { get; private set; }

    [STAThread]
    public static int Main(string[] args)
    {
        if (args.Length >= 2 && args[0] == "--render-test") return RenderTest.Run(args[1]);
        if (args.Length >= 1 && args[0] == "--smoke-test") return RenderTest.Smoke();

        // One instance per session. A relaunch (language change) waits for the old
        // instance to let go instead of bouncing off it.
        using var mutex = new Mutex(false, @"Local\Screenish.SingleInstance");
        bool owned;
        try { owned = mutex.WaitOne(args.Contains("--relaunch") ? TimeSpan.FromSeconds(8) : TimeSpan.Zero); }
        catch (AbandonedMutexException) { owned = true; }
        if (!owned) return 0;

        Log.InstallCrashHandlers();
        Prefs.Load();
        Loc.Init();

        Forms.Application.EnableVisualStyles();   // themed tray menu
        var app = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };   // tray only
        CrashReporter.Attach(app);
        Theme.Apply(app);

        // Sweep temp PNGs orphaned by a previous crash/force-quit before any capture
        // can write new files; also purge stale drag copies.
        ImageExport.SweepTempDirectory();
        ShotDrag.SweepDragDirectory();

        AppCoordinator.Shared.Start();
        Tray = new TrayIcon();

        if (CrashReporter.LastSessionCrashed) Tray.NotifyPreviousCrash();
        if (!Prefs.HideAtLaunch)
            app.Dispatcher.BeginInvoke(SettingsWindow.Open, DispatcherPriority.ApplicationIdle);

        app.Exit += (_, _) =>
        {
            Tray.Dispose();
            AppCoordinator.Shared.Hotkeys.Dispose();
            CrashReporter.MarkCleanShutdown();
            AppCoordinator.Shared.Store.CleanupTempDirectory();
        };
        app.Run();
        mutex.ReleaseMutex();
        return 0;
    }
}

// MARK: - Coordinator

/// Single owner of the capture pipeline shared by hotkeys and the tray menu.
internal sealed class AppCoordinator
{
    public static readonly AppCoordinator Shared = new();

    public ShotStore Store { get; } = new();
    public HotkeyManager Hotkeys { get; } = new();

    private readonly CaptureController _capture = new();
    private readonly Dictionary<Guid, EditorWindow> _editors = new();
    private StackController? _stack;
    private bool _isCapturing;

    private AppCoordinator() { }

    public void Start()
    {
        _stack = new StackController(Store);   // the floating panel controller
        Hotkeys.Pressed += Run;
        var failed = Hotkeys.RegisterAll();
        foreach (var mode in failed) Log.Breadcrumb($"hotkey for {mode} is taken by another app");
    }

    public async void Run(CaptureMode mode)
    {
        // Ignore overlapping captures — a second one would fight over the overlay.
        if (_isCapturing)
        {
            Log.Breadcrumb("capture ignored: already capturing");
            return;
        }
        _isCapturing = true;
        Log.Breadcrumb($"capture begin: {mode}");
        try
        {
            var image = await _capture.Capture(mode);
            if (image == null)
            {
                Log.Breadcrumb($"capture end: no image ({mode})");
                return;
            }
            Log.Breadcrumb($"capture end: got image ({mode})");
            var shot = Store.Add(image);
            ClipboardHelper.Copy(shot.Image);   // rendered (incl. remembered beautify)
            if (Prefs.OpenEditorAfterCapture) OpenEditor(shot);   // else it just sits in the stack
        }
        catch (Exception ex)
        {
            Log.Error($"capture pipeline failed: {ex}");
        }
        finally
        {
            _isCapturing = false;
        }
    }

    /// Discard a shot from the stack and close any editor open for it, so a removed
    /// shot never leaves an orphaned editor window behind. Used by the Stack's
    /// dismiss / remove / drag-out actions.
    public void DiscardShot(Shot shot)
    {
        if (_editors.TryGetValue(shot.Id, out var editor)) editor.Close();
        Store.Remove(shot);
    }

    /// Open (or focus) the annotation editor for a Shot.
    public void OpenEditor(Shot shot)
    {
        Log.Breadcrumb($"openEditor {shot.Id} existing={_editors.ContainsKey(shot.Id)}");
        if (_editors.TryGetValue(shot.Id, out var existing))
        {
            existing.ShowAndActivate();
            return;
        }
        var current = Store.Find(shot.Id) ?? shot;
        var editor = new EditorWindow(current)
        {
            OnDone = (annotations, cropRect, background) =>
            {
                Prefs.LastUsedBackground = background;   // remember beautify for next captures
                if (Store.ApplyEdits(current, annotations, cropRect, background) is { } rendered)
                    ClipboardHelper.Copy(rendered);
            },
            OnDragDelivered = () => Store.Remove(current),   // dropped into another app → leave the stack
            OnDiscard = () => Store.Remove(current),         // Esc → throw the shot away
            // Saved to the folder → optionally leave the stack (setting).
            OnSaved = () => { if (Prefs.RemoveAfterSave) Store.Remove(current); },
        };
        editor.Closed += (_, _) => _editors.Remove(shot.Id);
        _editors[shot.Id] = editor;
        editor.ShowAndActivate();
    }
}

// MARK: - Tray

/// The notification-area icon and its menu.
internal sealed class TrayIcon : IDisposable
{
    private readonly Forms.NotifyIcon _icon;
    private readonly Dictionary<CaptureMode, Forms.ToolStripMenuItem> _captureItems = new();

    public TrayIcon()
    {
        var menu = new Forms.ContextMenuStrip();
        AddCapture(menu, CaptureMode.Region, "Capture Area");
        AddCapture(menu, CaptureMode.Window, "Capture Window");
        AddCapture(menu, CaptureMode.Screen, "Capture Full Screen");
        menu.Items.Add(new Forms.ToolStripSeparator());
        menu.Items.Add(Loc.T("Settings…"), null, (_, _) => SettingsWindow.Open());
        menu.Items.Add(Loc.T("Reveal Crash Logs"), null, (_, _) => CrashReporter.RevealInExplorer());
        menu.Items.Add(Loc.T("Quit Screenish"), null, (_, _) => Application.Current.Shutdown());
        RefreshShortcuts();

        using var stream = Application.GetResourceStream(new Uri("pack://application:,,,/Assets/Screenish.ico")).Stream;
        _icon = new Forms.NotifyIcon
        {
            Icon = new System.Drawing.Icon(stream, Forms.SystemInformation.SmallIconSize),
            Text = "Screenish",
            ContextMenuStrip = menu,
            Visible = true,
        };
        // Left click opens the menu too, like the macOS menu-bar item.
        _icon.MouseUp += (_, e) =>
        {
            if (e.Button != Forms.MouseButtons.Left) return;
            typeof(Forms.NotifyIcon).GetMethod("ShowContextMenu",
                System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)?.Invoke(_icon, null);
        };
        _icon.BalloonTipClicked += (_, _) => CrashReporter.RevealInExplorer();
    }

    private void AddCapture(Forms.ContextMenuStrip menu, CaptureMode mode, string title)
    {
        var item = new Forms.ToolStripMenuItem(Loc.T(title), null, (_, _) =>
            // Let the menu finish closing first so it is not part of the capture.
            Application.Current.Dispatcher.BeginInvoke(() => AppCoordinator.Shared.Run(mode),
                                                       DispatcherPriority.ApplicationIdle));
        _captureItems[mode] = item;
        menu.Items.Add(item);
    }

    /// Show the current global chords next to the capture commands.
    public void RefreshShortcuts()
    {
        foreach (var (mode, item) in _captureItems)
            item.ShortcutKeyDisplayString = Prefs.GetHotkey(mode)?.DisplayString ?? "";
    }

    /// The previous session died with a crash banner. Tell the user so they can grab
    /// the report; clicking the notification reveals the crash-log folder. The tray
    /// menu's "Reveal Crash Logs" is the guaranteed path either way.
    public void NotifyPreviousCrash() =>
        _icon.ShowBalloonTip(10_000, Loc.T("Screenish crashed last session"),
                             Loc.T("Click to reveal the crash log so you can share it."), Forms.ToolTipIcon.Warning);

    public void Dispose()
    {
        _icon.Visible = false;
        _icon.Dispose();
    }
}
