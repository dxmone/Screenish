//
//  EditorWindow.cs
//  Screenish
//
//  The editor window for one Shot: toolbar + canvas + Drag/Copy/Save/Done on
//  the left, the beautify inspector on the right. One window per open Shot.
//

using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace Screenish;

internal sealed class EditorWindow : Window
{
    private readonly EditorDocument _document;
    private readonly EditorCanvas _canvas;
    private readonly EditorToolbar _toolbar;

    /// Apply edits: annotations, crop and beautify of the finished document.
    public required Action<IReadOnlyList<Annotation>, Rect?, BackgroundStyle> OnDone { get; init; }
    public Action OnDragDelivered { get; init; } = () => { };
    public Action OnDiscard { get; init; } = () => { };
    /// Called after the image was written to the save folder (after edits are applied).
    public Action OnSaved { get; init; } = () => { };

    public EditorWindow(Shot shot)
    {
        _document = new EditorDocument(shot);
        Title = Loc.T("Edit Screenshot");
        Width = 1160;
        Height = 740;
        MinWidth = 900;
        MinHeight = 520;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        Theme.Prepare(this);

        _toolbar = new EditorToolbar(_document);
        _canvas = new EditorCanvas(_document) { MinWidth = 420, MinHeight = 340 };

        var left = new DockPanel();
        DockPanel.SetDock(_toolbar, Dock.Top);
        left.Children.Add(_toolbar);
        var topDivider = Theme.Divider();
        DockPanel.SetDock(topDivider, Dock.Top);
        left.Children.Add(topDivider);

        var bottom = BuildBottomBar();
        DockPanel.SetDock(bottom, Dock.Bottom);
        left.Children.Add(bottom);
        var bottomDivider = Theme.Divider();
        DockPanel.SetDock(bottomDivider, Dock.Bottom);
        left.Children.Add(bottomDivider);
        left.Children.Add(_canvas);

        var root = new DockPanel();
        var inspector = new InspectorPanel(_document);
        DockPanel.SetDock(inspector, Dock.Right);
        root.Children.Add(inspector);
        var sideDivider = Theme.Divider(vertical: true);
        DockPanel.SetDock(sideDivider, Dock.Right);
        root.Children.Add(sideDivider);
        root.Children.Add(left);
        Content = root;

        PreviewKeyDown += OnPreviewKeyDown;
        Loaded += (_, _) => _canvas.Focus();
    }

    private FrameworkElement BuildBottomBar()
    {
        var bar = new DockPanel { Margin = new Thickness(10), LastChildFill = false };

        var handle = new DragOutHandle(Render, _document.Shot.CreatedAt)
        {
            ToolTip = Loc.T("Drag the image into another app"),
        };
        handle.Delivered += () =>
        {
            OnDragDelivered();
            AnimateAwayThenClose();
        };
        DockPanel.SetDock(handle, Dock.Left);
        bar.Children.Add(handle);

        var done = MakeButton("Done", "Apply edits and update the shot in the stack", Done);
        done.IsDefault = true;
        done.Style = Theme.StyleOf("AccentButton");
        var save = MakeButton("Save", "Save the image to your folder", Save);
        var copy = MakeButton("Copy", "Copy the image to the clipboard", () => ClipboardHelper.Copy(Render()));
        foreach (var button in new[] { done, save, copy })   // docked right → listed in reverse
        {
            DockPanel.SetDock(button, Dock.Right);
            bar.Children.Add(button);
        }
        return bar;
    }

    private static Button MakeButton(string title, string help, Action action)
    {
        var button = new Button
        {
            Content = Loc.T(title), ToolTip = Loc.T(help), MinWidth = 72, Margin = new Thickness(8, 0, 0, 0),
        };
        button.Click += (_, _) => action();
        return button;
    }

    private void OnPreviewKeyDown(object sender, KeyEventArgs e)
    {
        bool typing = Keyboard.FocusedElement is TextBox;
        if (e.Key == Key.Escape && !typing)
        {
            e.Handled = true;
            if (_toolbar.ClosePopups()) return;
            OnDiscard();   // Esc discards the shot (removes it from the stack) + closes
            Close();
        }
        else if (!typing && Keyboard.Modifiers == ModifierKeys.Control && e.Key == Key.Z)
        {
            _document.Undo();
            e.Handled = true;
        }
        else if (!typing && (Keyboard.Modifiers == ModifierKeys.Control && e.Key == Key.Y
                 || Keyboard.Modifiers == (ModifierKeys.Control | ModifierKeys.Shift) && e.Key == Key.Z))
        {
            _document.Redo();
            e.Handled = true;
        }
    }

    public void ShowAndActivate()
    {
        if (WindowState == WindowState.Minimized) WindowState = WindowState.Normal;
        Show();
        Activate();
        Native.SetForegroundWindow(new WindowInteropHelper(this).Handle);
    }

    private BitmapSource Render()
    {
        _canvas.CommitTextEditing();
        return EditorRenderer.Render(_document);
    }

    private void Save()
    {
        try
        {
            var path = ImageExport.Write(Render(), Prefs.SaveLocation, Prefs.Format, DateTime.Now);
            AppInfo.RevealInExplorer(path);
            Done();      // persist edits + close the editor only on success
            OnSaved();
        }
        catch (Exception ex)
        {
            ShotDrag.PresentSaveError(ex, this);   // failed → leave the editor open
        }
    }

    private void Done()
    {
        _canvas.CommitTextEditing();
        OnDone(_document.Annotations, _document.CropRect, _document.Background);
        Close();
    }

    /// After a successful drop, shrink + fade the window away, then close.
    private void AnimateAwayThenClose()
    {
        var hwnd = new WindowInteropHelper(this).Handle;
        if (WindowState != WindowState.Normal || hwnd == IntPtr.Zero)
        {
            Close();
            return;
        }
        Native.AddExStyle(hwnd, Native.WS_EX_LAYERED);
        MinWidth = MinHeight = 0;
        double left = Left, top = Top, width = Width, height = Height;
        var started = DateTime.UtcNow;
        var timer = new DispatcherTimer(DispatcherPriority.Render) { Interval = TimeSpan.FromMilliseconds(15) };
        timer.Tick += (_, _) =>
        {
            double t = Math.Min(1, (DateTime.UtcNow - started).TotalSeconds / 0.22);
            double eased = t * t;                 // ease-in
            double shrink = 1 - 0.4 * eased;      // down to 60 %
            Width = width * shrink;
            Height = height * shrink;
            Left = left + (width - Width) / 2;
            Top = top + (height - Height) / 2;
            Native.SetLayeredWindowAttributes(hwnd, 0, (byte)(255 * (1 - eased)), Native.LWA_ALPHA);
            if (t < 1) return;
            timer.Stop();
            Close();
        };
        timer.Start();
    }
}

/// The editor's "Drag" grab handle: renders the current image once at drag start
/// and drags it out as a real file.
internal sealed class DragOutHandle : Border
{
    private readonly Func<BitmapSource> _render;
    private readonly DateTime _date;
    private Point _mouseDown;
    private bool _pressed;

    public event Action? Delivered;

    public DragOutHandle(Func<BitmapSource> render, DateTime date)
    {
        _render = render;
        _date = date;
        Width = 86;
        Height = 28;
        CornerRadius = new CornerRadius(8);
        Cursor = Cursors.SizeAll;
        SetResourceReference(BackgroundProperty, "ControlBgPressed");

        var row = new StackPanel
        {
            Orientation = Orientation.Horizontal, IsHitTestVisible = false,
            HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center,
        };
        row.Children.Add(Icons.Make(Icons.Hand, 14));
        var label = Theme.Text(Loc.T("Drag"), "Fg", 12);
        label.Margin = new Thickness(6, 0, 0, 0);
        row.Children.Add(label);
        Child = row;
    }

    protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e)
    {
        _mouseDown = e.GetPosition(this);
        _pressed = true;
    }

    protected override void OnMouseLeftButtonUp(MouseButtonEventArgs e) => _pressed = false;

    protected override void OnMouseMove(MouseEventArgs e)
    {
        if (!_pressed || e.LeftButton != MouseButtonState.Pressed) return;
        var p = e.GetPosition(this);
        if ((p - _mouseDown).Length <= 3) return;
        _pressed = false;

        BitmapSource image;
        try { image = _render(); }
        catch (Exception ex)
        {
            Log.Error("drag aborted: render failed: " + ex.Message);
            return;
        }
        if (ShotDrag.Run(this, image, _date)) Delivered?.Invoke();
    }
}
