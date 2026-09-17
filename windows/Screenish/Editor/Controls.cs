//
//  Controls.cs
//  Screenish
//
//  Small reusable controls for the editor: a stepper, a segmented picker, a
//  menu button, and the in-app swatch colour picker (preset swatches plus RGBA
//  sliders in a popover anchored to the toolbar — no system colour dialog).
//

using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using System.Windows.Shapes;

namespace Screenish;

/// Icon + value + −/+ buttons over a clamped numeric range.
internal sealed class Stepper : StackPanel
{
    private readonly double _min, _max, _step;
    private readonly TextBlock _readout;
    private double _value;

    public event Action<double>? ValueChanged;

    public Stepper(FrameworkElement label, double min, double max, double step)
    {
        (_min, _max, _step) = (min, max, step);
        Orientation = Orientation.Horizontal;
        VerticalAlignment = VerticalAlignment.Center;
        Background = Brushes.Transparent;   // hover target includes the gaps

        label.Margin = new Thickness(2, 0, 4, 0);
        Children.Add(label);
        _readout = Theme.Text("", "FgSecondary", 12);
        _readout.Width = 24;
        _readout.TextAlignment = TextAlignment.Right;
        _readout.Margin = new Thickness(0, 0, 5, 0);
        Children.Add(_readout);
        Children.Add(MakeButton("−", -1));
        Children.Add(MakeButton("+", +1));
    }

    public double Value
    {
        get => _value;
        set
        {
            _value = Math.Clamp(value, _min, _max);
            _readout.Text = _value.ToString("0");
        }
    }

    private RepeatButton MakeButton(string glyph, int direction)
    {
        var button = new RepeatButton
        {
            Content = glyph, Width = 22, Height = 24, Padding = new Thickness(0), MinHeight = 0,
            Style = Theme.StyleOf("BaseButton"), Focusable = false, Delay = 400, Interval = 70,
            Margin = new Thickness(direction > 0 ? -1 : 0, 0, 0, 0),
        };
        button.Click += (_, _) =>
        {
            double next = Math.Clamp(_value + direction * _step, _min, _max);
            if (next == _value) return;
            Value = next;
            ValueChanged?.Invoke(next);
        };
        return button;
    }
}

/// A row of mutually exclusive toggle buttons.
internal sealed class Segmented<T> : StackPanel where T : notnull
{
    private readonly Dictionary<T, ToggleButton> _buttons = new();

    public event Action<T>? SelectionChanged;

    public Segmented(IEnumerable<(T Value, object Content)> segments, double segmentWidth = double.NaN)
    {
        Orientation = Orientation.Horizontal;
        Background = Brushes.Transparent;
        foreach (var (value, content) in segments)
        {
            if (content is string s) Add(value, Theme.Text(s, "Fg", 12), segmentWidth);
            else Add(value, (FrameworkElement)content, segmentWidth);
        }
    }

    private void Add(T value, FrameworkElement content, double width)
    {
        var button = new ToggleButton
        {
            Content = content, Style = Theme.StyleOf("ToolToggle"), Focusable = false, MinHeight = 24,
            Width = width, Padding = new Thickness(double.IsNaN(width) ? 8 : 0, 0, double.IsNaN(width) ? 8 : 0, 0),
            Margin = new Thickness(_buttons.Count == 0 ? 0 : -1, 0, 0, 0),
        };
        button.Click += (_, _) =>
        {
            Selected = value;
            SelectionChanged?.Invoke(value);
        };
        _buttons[value] = button;
        Children.Add(button);
    }

    public T Selected
    {
        set
        {
            foreach (var (key, button) in _buttons) button.IsChecked = key.Equals(value);
        }
    }
}

/// A button that drops a context menu below itself, rebuilt on every open.
internal sealed class MenuButton : Button
{
    private readonly TextBlock _title;

    public MenuButton(Action<ContextMenu> populate, FrameworkElement? icon = null)
    {
        Focusable = false;
        Padding = new Thickness(8, 3, 6, 3);
        HorizontalContentAlignment = HorizontalAlignment.Stretch;

        var row = new DockPanel { LastChildFill = true };
        var chevron = Icons.Make(Icons.ChevronDown, 12, "FgSecondary");
        DockPanel.SetDock(chevron, Dock.Right);
        row.Children.Add(chevron);
        if (icon != null)
        {
            icon.Margin = new Thickness(0, 0, 6, 0);
            DockPanel.SetDock(icon, Dock.Left);
            row.Children.Add(icon);
        }
        _title = Theme.Text("", "Fg", 12);
        _title.TextTrimming = TextTrimming.CharacterEllipsis;
        _title.Margin = new Thickness(0, 0, 4, 0);
        row.Children.Add(_title);
        Content = row;

        Click += (_, _) =>
        {
            var menu = new ContextMenu { PlacementTarget = this, Placement = PlacementMode.Bottom };
            populate(menu);
            menu.IsOpen = true;
        };
    }

    public string Title
    {
        set => _title.Text = value;
    }

    public static MenuItem Item(string header, Action? action = null, bool enabled = true)
    {
        var item = new MenuItem { Header = header, IsEnabled = enabled };
        if (action != null) item.Click += (_, _) => action();
        return item;
    }
}

internal sealed class SwatchColorPicker : Button
{
    /// 2 rows × 6 — annotation-friendly palette.
    private static readonly Color[] Presets =
    [
        Rgb(0xFF3B30), Rgb(0xFF9500), Rgb(0xFFCC00), Rgb(0x34C759), Rgb(0x00C7BE), Rgb(0x007AFF),
        Rgb(0xAF52DE), Rgb(0xFF2D55), Rgb(0x000000), Rgb(0xFFFFFF), Rgb(0x8E8E93), Rgb(0xA2845E),
    ];

    private readonly Border _swatch;
    private readonly Popup _popup;
    private Color _color;

    public event Action<Color>? ColorChanged;

    public SwatchColorPicker()
    {
        Style = Theme.StyleOf("PlainButton");
        Focusable = false;
        VerticalAlignment = VerticalAlignment.Center;
        _swatch = new Border { Width = 24, Height = 20, CornerRadius = new CornerRadius(4), BorderThickness = new Thickness(1) };
        _swatch.SetResourceReference(Border.BorderBrushProperty, "FgTertiary");
        Content = _swatch;

        _popup = new Popup
        {
            PlacementTarget = this, Placement = PlacementMode.Bottom, StaysOpen = false,
            AllowsTransparency = true, VerticalOffset = 6,
        };
        Click += (_, _) =>
        {
            _popup.Child = BuildPopover();
            _popup.IsOpen = true;
        };
    }

    public Color Color
    {
        get => _color;
        set
        {
            _color = value;
            _swatch.Background = Theme.Frozen(value);
        }
    }

    /// Close the popover if it is open (Esc). Returns whether it was.
    public bool ClosePopup()
    {
        if (!_popup.IsOpen) return false;
        _popup.IsOpen = false;
        return true;
    }

    private void Pick(Color color)
    {
        if (color == _color) return;
        Color = color;
        ColorChanged?.Invoke(color);
    }

    private FrameworkElement BuildPopover()
    {
        var stack = new StackPanel { Width = 196 };

        var grid = new WrapPanel();
        foreach (var preset in Presets)
        {
            var dot = new Grid { Width = 26, Height = 26, Margin = new Thickness(3) };
            var ring = new Ellipse { StrokeThickness = 2, Visibility = preset == _color ? Visibility.Visible : Visibility.Hidden };
            ring.SetResourceReference(Shape.StrokeProperty, "Fg");
            var fill = new Ellipse { Margin = new Thickness(3), Fill = Theme.Frozen(preset), StrokeThickness = 1 };
            fill.SetResourceReference(Shape.StrokeProperty, "FgTertiary");
            dot.Children.Add(ring);
            dot.Children.Add(fill);
            var button = new Button { Style = Theme.StyleOf("PlainButton"), Content = dot, Focusable = false };
            button.Click += (_, _) =>
            {
                Pick(preset);
                _popup.IsOpen = false;
            };
            grid.Children.Add(button);
        }
        stack.Children.Add(grid);

        var divider = Theme.Divider();
        divider.Margin = new Thickness(0, 8, 0, 8);
        stack.Children.Add(divider);

        stack.Children.Add(ChannelSlider("R", _color.R, v => Pick(Color.FromArgb(_color.A, v, _color.G, _color.B))));
        stack.Children.Add(ChannelSlider("G", _color.G, v => Pick(Color.FromArgb(_color.A, _color.R, v, _color.B))));
        stack.Children.Add(ChannelSlider("B", _color.B, v => Pick(Color.FromArgb(_color.A, _color.R, _color.G, v))));
        stack.Children.Add(ChannelSlider("A", _color.A, v => Pick(Color.FromArgb(v, _color.R, _color.G, _color.B))));

        var chrome = new Border
        {
            Child = stack, Padding = new Thickness(12), CornerRadius = new CornerRadius(8),
            BorderThickness = new Thickness(1), Margin = new Thickness(8),
            Effect = new System.Windows.Media.Effects.DropShadowEffect { BlurRadius = 12, ShadowDepth = 2, Opacity = 0.3, Direction = 270 },
        };
        chrome.SetResourceReference(Border.BackgroundProperty, "PanelBg");
        chrome.SetResourceReference(Border.BorderBrushProperty, "ControlBorder");
        return chrome;
    }

    private static FrameworkElement ChannelSlider(string label, byte value, Action<byte> changed)
    {
        var row = new DockPanel { Margin = new Thickness(0, 3, 0, 3) };
        var name = Theme.Text(label, "FgSecondary", 11);
        name.FontFamily = new FontFamily("Consolas");
        name.Width = 16;
        DockPanel.SetDock(name, Dock.Left);
        row.Children.Add(name);
        var slider = new Slider { Minimum = 0, Maximum = 255, Value = value, Focusable = false };
        slider.ValueChanged += (_, e) => changed((byte)Math.Round(e.NewValue));
        row.Children.Add(slider);
        return row;
    }

    private static Color Rgb(int hex) =>
        Color.FromRgb((byte)((hex >> 16) & 0xFF), (byte)((hex >> 8) & 0xFF), (byte)(hex & 0xFF));
}
