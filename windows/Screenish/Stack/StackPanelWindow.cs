//
//  StackPanelWindow.cs
//  Screenish
//
//  A non-activating floating window pinned to the bottom-left of the primary
//  screen, hosting the Stack of shots: a column of thumbnail cards, newest on
//  top. Shown while shots exist, hidden when empty. Each card is a drag source
//  and offers open / save / copy / dismiss.
//

using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Effects;
using System.Windows.Shapes;

namespace Screenish;

internal static class StackMetrics
{
    public const double CardWidth = 160;
    public const double MaxThumbHeight = 110;
    public const int CollapseThreshold = 5;
    public const double PilePeek = 28;
    public const double Margin = 20;
    public const double Padding = 10;
}

internal sealed class StackController
{
    private readonly ShotStore _store;
    private readonly StackPanelWindow _panel;

    public StackController(ShotStore store)
    {
        _store = store;
        _panel = new StackPanelWindow(store);
        store.Changed += Update;
    }

    private void Update()
    {
        if (_store.Shots.Count == 0)
        {
            _panel.Hide();
        }
        else
        {
            _panel.Rebuild();
            if (!_panel.IsVisible) _panel.Show();
            _panel.RefreshLayout();
        }
    }
}

internal sealed class StackPanelWindow : Window
{
    private readonly ShotStore _store;
    private readonly ScrollViewer _scroll;

    public StackPanelWindow(ShotStore store)
    {
        _store = store;
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        ShowActivated = false;
        Topmost = true;
        SizeToContent = SizeToContent.Manual;
        WindowStartupLocation = WindowStartupLocation.Manual;
        Width = StackMetrics.CardWidth + StackMetrics.Padding * 2;
        UseLayoutRounding = true;

        Content = _scroll = new ScrollViewer
        {
            VerticalScrollBarVisibility = ScrollBarVisibility.Hidden,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
            Focusable = false,
        };

        // Never take focus from the app the user is working in; stay out of Alt+Tab.
        SourceInitialized += (_, _) => Native.AddExStyle(new WindowInteropHelper(this).Handle,
            Native.WS_EX_NOACTIVATE | Native.WS_EX_TOOLWINDOW);
    }

    public void Rebuild()
    {
        var shots = _store.Shots;
        FrameworkElement content;
        if (shots.Count <= StackMetrics.CollapseThreshold)
        {
            var column = new StackPanel();
            for (int i = 0; i < shots.Count; i++)
            {
                var card = new StackCard(shots[i]);
                if (i > 0) card.Margin = new Thickness(0, 8, 0, 0);
                column.Children.Add(card);
            }
            content = column;
        }
        else
        {
            // More than the threshold → pile them with a small peek so the stack
            // stays compact. Newest is on top and fully visible.
            var pile = new Canvas
            {
                Width = StackMetrics.CardWidth,
                Height = (shots.Count - 1) * StackMetrics.PilePeek + StackMetrics.MaxThumbHeight,
            };
            for (int i = 0; i < shots.Count; i++)
            {
                var card = new StackCard(shots[i]);
                Canvas.SetTop(card, i * StackMetrics.PilePeek);
                Panel.SetZIndex(card, shots.Count - i);
                pile.Children.Add(card);
            }
            content = pile;
        }
        content.Margin = new Thickness(StackMetrics.Padding);
        _scroll.Content = content;
    }

    public void RefreshLayout()
    {
        // Always the primary screen: the stack must not follow whatever app has focus.
        var work = SystemParameters.WorkArea;
        double maxHeight = work.Height - StackMetrics.Margin * 2;

        var content = (FrameworkElement)_scroll.Content;
        content.Measure(new Size(Width, double.PositiveInfinity));
        Height = Math.Min(content.DesiredSize.Height, maxHeight);
        Left = work.Left + StackMetrics.Margin;
        Top = work.Bottom - StackMetrics.Margin - Height;
    }
}

/// One thumbnail card. Every card is the same fixed size — a small capture would
/// otherwise shrink to a sliver. The image aspect-fits inside (scaled up if
/// needed); any letterboxing shows the card background.
internal sealed class StackCard : Grid
{
    private readonly Shot _shot;
    private readonly Button _dismiss;
    private Point _mouseDown;
    private bool _pressed;

    public StackCard(Shot shot)
    {
        _shot = shot;
        Width = StackMetrics.CardWidth;
        Height = StackMetrics.MaxThumbHeight;
        Background = Brushes.Transparent;
        Cursor = Cursors.Hand;

        var clip = new RectangleGeometry(new Rect(0, 0, Width, Height), 8, 8);
        var face = new Border
        {
            CornerRadius = new CornerRadius(8),
            Effect = new DropShadowEffect { BlurRadius = 12, ShadowDepth = 3, Direction = 270, Opacity = 0.35 },
        };
        face.SetResourceReference(Border.BackgroundProperty, "WindowBg");
        Children.Add(face);

        // Draw the downsampled thumbnail — drag/copy/editor use the full image.
        var image = new Image { Source = shot.Thumbnail, Stretch = Stretch.Uniform };
        RenderOptions.SetBitmapScalingMode(image, BitmapScalingMode.HighQuality);
        var clipped = new Grid { Clip = clip };   // rounds the image without clipping the shadow
        clipped.Children.Add(image);
        Children.Add(clipped);
        Children.Add(new Border
        {
            CornerRadius = new CornerRadius(8), BorderThickness = new Thickness(1),
            BorderBrush = Theme.Frozen(Color.FromArgb(38, 255, 255, 255)), IsHitTestVisible = false,
        });

        _dismiss = MakeDismissButton();
        Children.Add(_dismiss);

        MouseEnter += (_, _) => _dismiss.Visibility = Visibility.Visible;
        MouseLeave += (_, _) => _dismiss.Visibility = Visibility.Collapsed;
        ContextMenu = MakeMenu();
    }

    private Button MakeDismissButton()
    {
        var glyph = new Grid { Width = 16, Height = 16 };
        glyph.Children.Add(new Ellipse { Fill = Theme.Frozen(Color.FromArgb(153, 0, 0, 0)) });
        glyph.Children.Add(new Path
        {
            Data = Geometry.Parse("M5,5 L11,11 M11,5 L5,11"), Stroke = Brushes.White, StrokeThickness = 1.6,
            StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round,
        });
        var button = new Button
        {
            Style = Theme.StyleOf("PlainButton"), Content = glyph, Margin = new Thickness(4),
            HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Top,
            Visibility = Visibility.Collapsed, Focusable = false,
        };
        button.Click += (_, _) => AppCoordinator.Shared.DiscardShot(_shot);
        return button;
    }

    private ContextMenu MakeMenu()
    {
        var menu = new ContextMenu();
        void Add(string title, Action action)
        {
            var item = new MenuItem { Header = Loc.T(title) };
            item.Click += (_, _) => action();
            menu.Items.Add(item);
        }
        Add("Save to Folder", SaveToFolder);
        Add("Copy", () => ClipboardHelper.Copy(_shot.Image));
        Add("Copy and Remove", () =>
        {
            ClipboardHelper.Copy(_shot.Image);
            AppCoordinator.Shared.DiscardShot(_shot);
        });
        menu.Items.Add(new Separator());
        Add("Remove", () => AppCoordinator.Shared.DiscardShot(_shot));
        return menu;
    }

    // MARK: - Click vs drag

    protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e)
    {
        _mouseDown = e.GetPosition(this);
        _pressed = true;
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        if (!_pressed || e.LeftButton != MouseButtonState.Pressed) return;
        var p = e.GetPosition(this);
        if (Math.Sqrt(Math.Pow(p.X - _mouseDown.X, 2) + Math.Pow(p.Y - _mouseDown.Y, 2)) <= 3) return;
        _pressed = false;
        if (ShotDrag.Run(this, _shot.Image, _shot.CreatedAt) && Prefs.RemoveAfterDrag)
            AppCoordinator.Shared.DiscardShot(_shot);
    }

    protected override void OnMouseLeftButtonUp(MouseButtonEventArgs e)
    {
        if (!_pressed) return;
        _pressed = false;
        AppCoordinator.Shared.OpenEditor(_shot);
    }

    private void SaveToFolder()
    {
        try
        {
            AppInfo.RevealInExplorer(ShotDrag.Save(_shot, Prefs.SaveLocation));
        }
        catch (Exception ex)
        {
            ShotDrag.PresentSaveError(ex);
        }
    }
}
