//
//  SettingsWindow.cs
//  Screenish
//
//  Tray-accessible settings: save location, launch behavior, JPG compression,
//  the global capture shortcuts, and an About tab.
//

using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Microsoft.Win32;

namespace Screenish;

internal sealed class SettingsWindow : Window
{
    private static SettingsWindow? _current;

    /// Open (or focus) the single settings window, in front of other apps.
    public static void Open()
    {
        _current ??= new SettingsWindow();
        if (_current.WindowState == WindowState.Minimized) _current.WindowState = WindowState.Normal;
        _current.Show();
        _current.Activate();
        Native.SetForegroundWindow(new WindowInteropHelper(_current).Handle);
    }

    private readonly ContentControl _page = new() { Focusable = false };

    private SettingsWindow()
    {
        Title = Loc.T("Screenish Settings");
        Width = 500;
        SizeToContent = SizeToContent.Height;
        ResizeMode = ResizeMode.CanMinimize;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Theme.Prepare(this);
        Closed += (_, _) => _current = null;

        var pages = new (string Title, Func<FrameworkElement> Build)[]
        {
            (Loc.T("General"), BuildGeneral), (Loc.T("Shortcuts"), BuildShortcuts), (Loc.T("About"), BuildAbout),
        };
        var tabs = new Segmented<int>(pages.Select((p, i) => (i, (object)p.Title)), segmentWidth: 110)
        {
            HorizontalAlignment = HorizontalAlignment.Center, Margin = new Thickness(0, 14, 0, 4),
        };
        tabs.SelectionChanged += i => _page.Content = pages[i].Build();
        tabs.Selected = 0;
        _page.Content = pages[0].Build();

        var root = new StackPanel();
        root.Children.Add(tabs);
        root.Children.Add(_page);
        Content = root;
    }

    // MARK: - General

    private FrameworkElement BuildGeneral()
    {
        var form = new StackPanel { Margin = new Thickness(24, 12, 24, 22) };

        // Language
        var language = new MenuButton(menu =>
        {
            foreach (var option in Enum.GetValues<AppLanguage>())
            {
                var item = MenuButton.Item(option.Label(), () => ChangeLanguage(option));
                item.IsChecked = option == Prefs.Language;
                menu.Items.Add(item);
            }
        }) { Width = 150, Title = Prefs.Language.Label() };
        form.Children.Add(Row(Loc.T("Language"), language));

        // Save location
        var path = Theme.Text(Prefs.SaveLocation, "FgSecondary", 12);
        path.TextTrimming = TextTrimming.CharacterEllipsis;
        path.ToolTip = Prefs.SaveLocation;
        path.MaxWidth = 220;
        path.Margin = new Thickness(0, 0, 10, 0);
        var choose = new Button { Content = Loc.T("Choose…") };
        choose.Click += (_, _) =>
        {
            var dialog = new OpenFolderDialog { InitialDirectory = Prefs.SaveLocation, Multiselect = false };
            if (dialog.ShowDialog(this) != true) return;
            Prefs.SaveLocationPath = dialog.FolderName;
            path.Text = dialog.FolderName;
            path.ToolTip = dialog.FolderName;
        };
        var location = new StackPanel { Orientation = Orientation.Horizontal };
        location.Children.Add(path);
        location.Children.Add(choose);
        form.Children.Add(Row(Loc.T("Save to"), location));

        form.Children.Add(Toggle("Open editor after capture", Prefs.OpenEditorAfterCapture, v => Prefs.OpenEditorAfterCapture = v));
        form.Children.Add(Toggle("Always hide window at launch", Prefs.HideAtLaunch, v => Prefs.HideAtLaunch = v));
        form.Children.Add(Toggle("Compress to JPG when saving", Prefs.CompressJpeg, v => Prefs.CompressJpeg = v));
        form.Children.Add(Toggle("Remove from stack after drag and drop", Prefs.RemoveAfterDrag, v => Prefs.RemoveAfterDrag = v));
        form.Children.Add(Toggle("Remove from stack after saving in editor", Prefs.RemoveAfterSave, v => Prefs.RemoveAfterSave = v));
        form.Children.Add(Toggle("Launch at login", LoginItem.IsEnabled, LoginItem.Set));
        return form;
    }

    private void ChangeLanguage(AppLanguage language)
    {
        if (language == Prefs.Language) return;
        Prefs.Language = language;
        _page.Content = BuildGeneral();
        var answer = MessageBox.Show(this,
            Loc.T("Restart Screenish to apply the new language.") + "\n\n" + Loc.T("Relaunch now") + "?",
            Loc.T("Restart required"), MessageBoxButton.YesNo, MessageBoxImage.Information);
        if (answer == MessageBoxResult.Yes) AppRelauncher.Relaunch();
    }

    private static FrameworkElement Row(string label, FrameworkElement control)
    {
        var row = new DockPanel { Margin = new Thickness(0, 7, 0, 7), LastChildFill = false };
        DockPanel.SetDock(control, Dock.Right);
        row.Children.Add(control);
        row.Children.Add(Theme.Text(label));
        return row;
    }

    private static FrameworkElement Toggle(string key, bool value, Action<bool> changed)
    {
        var box = new CheckBox { Content = Loc.T(key), IsChecked = value, Margin = new Thickness(0, 7, 0, 7) };
        box.Click += (_, _) => changed(box.IsChecked == true);
        return box;
    }

    // MARK: - Shortcuts

    private static FrameworkElement BuildShortcuts()
    {
        var form = new StackPanel { Margin = new Thickness(24, 12, 24, 22) };
        form.Children.Add(Row(Loc.T("Capture Area"), new ShortcutRecorder(CaptureMode.Region)));
        form.Children.Add(Row(Loc.T("Capture Window"), new ShortcutRecorder(CaptureMode.Window)));
        form.Children.Add(Row(Loc.T("Capture Full Screen"), new ShortcutRecorder(CaptureMode.Screen)));
        return form;
    }

    // MARK: - About

    private static FrameworkElement BuildAbout()
    {
        var stack = new StackPanel { Margin = new Thickness(24, 22, 24, 30) };
        void Add(FrameworkElement element, double top = 0)
        {
            element.HorizontalAlignment = HorizontalAlignment.Center;
            element.Margin = new Thickness(0, top, 0, 0);
            stack.Children.Add(element);
        }

        Add(new Image
        {
            Source = new BitmapImage(new Uri("pack://application:,,,/Assets/AppIcon256.png")),
            Width = 96, Height = 96,
        });
        Add(Theme.Text("Screenish", "Fg", 20, FontWeights.Bold), 8);
        Add(Theme.Text(string.Format(Loc.T("Version {0}"), AppInfo.DisplayVersion), "FgSecondary", 12), 6);
        Add(Theme.Text(Loc.T("Created by Thomas Strömberg with AI coding."), "Fg", 12), 16);

        var link = new Hyperlink(new Run("github.com/dxmone/Screenish")) { Foreground = Theme.AccentBrush };
        link.Click += (_, _) => AppInfo.OpenUrl(AppInfo.RepoUrl);
        Add(new TextBlock(link) { FontSize = 12 }, 8);
        return stack;
    }
}

/// Click, then press a chord to record it. Esc cancels; Backspace/Delete clears.
internal sealed class ShortcutRecorder : Button
{
    private readonly CaptureMode _mode;
    private bool _recording;

    public ShortcutRecorder(CaptureMode mode)
    {
        _mode = mode;
        Width = 170;
        ToolTip = Loc.T("Record shortcut");
        ShowCurrent();
        Click += (_, _) => { if (_recording) Stop(); else Start(); };
        LostKeyboardFocus += (_, _) => { if (_recording) Stop(); };
    }

    private void ShowCurrent() => Content = Prefs.GetHotkey(_mode)?.DisplayString ?? "—";

    private void Start()
    {
        _recording = true;
        Content = Loc.T("Press shortcut…");
        // Free the chords while listening, or pressing the current one would capture.
        AppCoordinator.Shared.Hotkeys.UnregisterAll();
        Focus();
    }

    private void Stop()
    {
        _recording = false;
        ShowCurrent();
        var failed = AppCoordinator.Shared.Hotkeys.RegisterAll();
        if (failed.Contains(_mode) && Prefs.GetHotkey(_mode) is { } hotkey)
        {
            MessageBox.Show(Window.GetWindow(this)!,
                string.Format(Loc.T("The shortcut {0} is already in use by another app."), hotkey.DisplayString),
                "Screenish", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
        App.Tray?.RefreshShortcuts();
    }

    protected override void OnPreviewKeyDown(KeyEventArgs e)
    {
        if (!_recording)
        {
            base.OnPreviewKeyDown(e);
            return;
        }
        e.Handled = true;
        var key = e.Key == Key.System ? e.SystemKey : e.Key;
        if (key is Key.LeftCtrl or Key.RightCtrl or Key.LeftAlt or Key.RightAlt or Key.LeftShift
            or Key.RightShift or Key.LWin or Key.RWin) return;   // wait for the non-modifier key

        var modifiers = Keyboard.Modifiers;
        if (modifiers == ModifierKeys.None && key == Key.Escape)
        {
            Stop();
            return;
        }
        if (modifiers == ModifierKeys.None && key is Key.Back or Key.Delete)
        {
            Prefs.SetHotkey(_mode, null);
            Stop();
            return;
        }
        // A global hotkey needs a modifier, or it would swallow plain typing
        // (function keys and PrtSc are fine on their own).
        bool standalone = key is >= Key.F1 and <= Key.F24 or Key.Snapshot;
        if ((modifiers & ~ModifierKeys.Shift) == ModifierKeys.None && !standalone) return;

        uint flags = 0;
        if (modifiers.HasFlag(ModifierKeys.Control)) flags |= Native.MOD_CONTROL;
        if (modifiers.HasFlag(ModifierKeys.Alt)) flags |= Native.MOD_ALT;
        if (modifiers.HasFlag(ModifierKeys.Shift)) flags |= Native.MOD_SHIFT;
        if (modifiers.HasFlag(ModifierKeys.Windows)) flags |= Native.MOD_WIN;
        Prefs.SetHotkey(_mode, new Hotkey(flags, KeyInterop.VirtualKeyFromKey(key)));
        Stop();
    }
}
