//
//  InspectorPanel.cs
//  Screenish
//
//  Right-hand beautify panel: presets, padding, inset, corner radius, shadow,
//  background fill, and aspect ratio. Bound to document.Background.
//

using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;

namespace Screenish;

internal sealed class InspectorPanel : ScrollViewer
{
    private readonly EditorDocument _document;
    private readonly MenuButton _presetButton;
    private readonly List<Action> _refreshers = [];
    private readonly MenuButton _socialButton;
    private readonly Segmented<AspectRatioOption> _ratio;
    private readonly Dictionary<string, Border> _fillRings = new();
    private bool _refreshing;

    private List<BeautyPreset> _presets = Prefs.SavedPresets;
    private Guid? _selectedPresetId;
    private Guid? _defaultPresetId = Prefs.DefaultPresetId;

    public InspectorPanel(EditorDocument document)
    {
        _document = document;
        Width = 248;
        VerticalScrollBarVisibility = ScrollBarVisibility.Auto;
        Focusable = false;

        var stack = new StackPanel { Margin = new Thickness(20, 18, 20, 18) };
        Content = stack;

        stack.Children.Add(Theme.Text(Loc.T("Background"), "Fg", 14, FontWeights.SemiBold));

        // Presets
        _presetButton = new MenuButton(PopulatePresetMenu) { Width = 130 };
        var presetRow = new DockPanel { Margin = new Thickness(0, 16, 0, 0) };
        DockPanel.SetDock(_presetButton, Dock.Right);
        presetRow.Children.Add(_presetButton);
        presetRow.Children.Add(Theme.Text(Loc.T("Preset"), "FgSecondary", 12));
        stack.Children.Add(presetRow);

        // Unitless 0…100 padding amount mapped to a small fraction (100 ≈ 0.13 of longest side).
        stack.Children.Add(SliderRow(Loc.T("Padding"), 0, 100, percent: false,
            () => _document.Background.PaddingFraction * 750,
            v => _document.Background with { PaddingFraction = v / 750 }));
        stack.Children.Add(SliderRow(Loc.T("Inset"), 0, 0.06, percent: true,
            () => _document.Background.InsetFraction,
            v => _document.Background with { InsetFraction = v }));
        stack.Children.Add(SliderRow(Loc.T("Corner Radius"), 0, 0.2, percent: true,
            () => _document.Background.CornerRadiusFraction,
            v => _document.Background with { CornerRadiusFraction = v }));
        stack.Children.Add(SliderRow(Loc.T("Shadow"), 0, 0.8, percent: true,
            () => _document.Background.ShadowOpacity,
            v => _document.Background with { ShadowOpacity = v }));

        stack.Children.Add(BuildFillPicker());

        // Aspect ratio
        var ratioLabel = Theme.Text(Loc.T("Aspect Ratio"), "FgSecondary", 12);
        ratioLabel.Margin = new Thickness(0, 16, 0, 6);
        stack.Children.Add(ratioLabel);
        _ratio = new Segmented<AspectRatioOption>(
            AspectRatioOptions.Basic.Select(o => (o, (object)o.Label())), segmentWidth: 42.4);
        _ratio.SelectionChanged += SetRatio;
        stack.Children.Add(_ratio);

        _socialButton = new MenuButton(menu =>
        {
            foreach (var option in AspectRatioOptions.Social)
                menu.Items.Add(MenuButton.Item(option.Label(), () => SetRatio(option)));
        }, Icons.Make(Icons.Social, 14)) { Margin = new Thickness(0, 6, 0, 0) };
        stack.Children.Add(_socialButton);

        MatchSelectedPreset();
        document.Changed += Refresh;
        Refresh();
    }

    private void SetRatio(AspectRatioOption option)
    {
        _document.BeginInteraction();
        _document.Background = _document.Background with { Ratio = option };
    }

    /// Show the active preset's name when the shot opened with a style that matches
    /// a saved preset (e.g. a new capture using the pinned default preset).
    private void MatchSelectedPreset()
    {
        if (_defaultPresetId is Guid id && _presets.FirstOrDefault(p => p.Id == id)?.Style == _document.Background)
            _selectedPresetId = id;
        else
            _selectedPresetId = _presets.FirstOrDefault(p => p.Style == _document.Background)?.Id;
    }

    private void Refresh()
    {
        _refreshing = true;
        foreach (var refresh in _refreshers) refresh();
        _refreshing = false;

        var bg = _document.Background;
        foreach (var (id, ring) in _fillRings)
        {
            bool active = id.Length == 0 ? bg.Fill.Kind == FillKind.None
                : bg.Fill.Kind == FillKind.Gradient && bg.Fill.Gradient!.Id == id;
            ring.BorderThickness = new Thickness(active ? 2 : id.Length == 0 ? 1 : 0);
            ring.SetResourceReference(Border.BorderBrushProperty, active ? "Accent" : "ControlBorder");
        }

        _ratio.Selected = bg.Ratio;
        _socialButton.Title = AspectRatioOptions.Social.Contains(bg.Ratio) ? bg.Ratio.Label() : Loc.T("Social size");
        // Name shown on the preset button — the active preset, or a placeholder.
        _presetButton.Title = _presets.FirstOrDefault(p => p.Id == _selectedPresetId)?.Name ?? Loc.T("Preset");
    }

    // MARK: - Presets

    private void PopulatePresetMenu(ContextMenu menu)
    {
        if (_presets.Count == 0)
        {
            menu.Items.Add(MenuButton.Item(Loc.T("No saved presets"), enabled: false));
        }
        else
        {
            foreach (var preset in _presets)
            {
                // Active preset gets a check; the pinned default a star.
                var item = MenuButton.Item(preset.Name, () => ApplyPreset(preset));
                if (preset.Id == _defaultPresetId) item.Icon = new TextBlock { Text = "★" };
                else item.IsChecked = preset.Id == _selectedPresetId;
                menu.Items.Add(item);
            }

            var setDefault = MenuButton.Item(Loc.T("Set as default"));
            foreach (var preset in _presets)
                setDefault.Items.Add(MenuButton.Item(preset.Name, () => SetDefaultPreset(preset.Id)));
            if (_defaultPresetId != null)
            {
                setDefault.Items.Add(new Separator());
                setDefault.Items.Add(MenuButton.Item(Loc.T("None"), () => SetDefaultPreset(null)));
            }
            menu.Items.Add(setDefault);

            var delete = MenuButton.Item(Loc.T("Delete"));
            foreach (var preset in _presets)
                delete.Items.Add(MenuButton.Item(preset.Name, () => DeletePreset(preset)));
            menu.Items.Add(delete);
        }
        menu.Items.Add(new Separator());
        menu.Items.Add(MenuButton.Item(Loc.T("Save current…"), SavePreset));
    }

    private void ApplyPreset(BeautyPreset preset)
    {
        _document.BeginInteraction();
        _selectedPresetId = preset.Id;
        _document.Background = preset.Style;
        Refresh();
    }

    private void SavePreset()
    {
        var name = PromptDialog.Ask(Window.GetWindow(this), Loc.T("Save preset"), Loc.T("Preset name"))?.Trim();
        if (string.IsNullOrEmpty(name)) return;
        var preset = new BeautyPreset(Guid.NewGuid(), name, _document.Background);
        var list = Prefs.SavedPresets;
        list.Add(preset);
        Prefs.SavedPresets = _presets = list;
        _selectedPresetId = preset.Id;   // a just-saved preset is the active one
        Refresh();
    }

    private void DeletePreset(BeautyPreset preset)
    {
        var list = Prefs.SavedPresets;
        list.RemoveAll(p => p.Id == preset.Id);
        Prefs.SavedPresets = _presets = list;
        if (_selectedPresetId == preset.Id) _selectedPresetId = null;
        if (_defaultPresetId == preset.Id) SetDefaultPreset(null);
        Refresh();
    }

    private void SetDefaultPreset(Guid? id)
    {
        Prefs.DefaultPresetId = _defaultPresetId = id;
    }

    // MARK: - Background fill

    private FrameworkElement BuildFillPicker()
    {
        var section = new StackPanel { Margin = new Thickness(0, 16, 0, 0) };
        var label = Theme.Text(Loc.T("Fill"), "FgSecondary", 12);
        label.Margin = new Thickness(0, 0, 0, 8);
        section.Children.Add(label);

        var grid = new UniformGrid { Columns = 4, Margin = new Thickness(-4, -4, -4, -4) };
        section.Children.Add(grid);

        var none = Swatch("", null, Icons.Make(Icons.NoSign, 16, "FgSecondary"), Loc.T("No background"));
        none.Click += (_, _) =>
        {
            _document.BeginInteraction();
            _document.Background = _document.Background with { Fill = BackgroundFill.None };
        };
        grid.Children.Add(none);

        foreach (var preset in GradientPresets.All)
        {
            var brush = BackgroundRenderer.FillBrush(BackgroundFill.Of(preset), new Rect(0, 0, 46, 28));
            var swatch = Swatch(preset.Id, brush, null, preset.Id);
            swatch.Click += (_, _) =>
            {
                _document.BeginInteraction();
                var bg = _document.Background with { Fill = BackgroundFill.Of(preset) };
                // A thin, adjustable border so a newly chosen background is visible
                // without forcing a big default — drag Padding to 0 to remove it.
                if (bg.PaddingFraction == 0) bg = bg with { PaddingFraction = 0.04 };
                _document.Background = bg;
            };
            grid.Children.Add(swatch);
        }
        return section;
    }

    private Button Swatch(string id, Brush? fill, FrameworkElement? glyph, string tooltip)
    {
        var ring = new Border { CornerRadius = new CornerRadius(6), Height = 28, Background = fill, Child = glyph };
        _fillRings[id] = ring;
        return new Button
        {
            Style = Theme.StyleOf("PlainButton"), Content = ring, Margin = new Thickness(4),
            ToolTip = tooltip, Focusable = false, HorizontalContentAlignment = HorizontalAlignment.Stretch,
        };
    }

    // MARK: - Slider helper

    private FrameworkElement SliderRow(string title, double min, double max, bool percent,
                                       Func<double> read, Func<double, BackgroundStyle> write)
    {
        var section = new StackPanel { Margin = new Thickness(0, 16, 0, 0) };
        var header = new DockPanel();
        var readout = Theme.Text("", "FgTertiary", 11);
        DockPanel.SetDock(readout, Dock.Right);
        header.Children.Add(readout);
        header.Children.Add(Theme.Text(title, "FgSecondary", 12));
        section.Children.Add(header);

        var slider = new Slider { Minimum = min, Maximum = max, Margin = new Thickness(0, 4, 0, 0), Focusable = false };
        // One undo step per slider gesture (drag or track click).
        slider.PreviewMouseLeftButtonDown += (_, _) => _document.BeginInteraction();
        slider.ValueChanged += (_, e) =>
        {
            if (!_refreshing) _document.Background = write(e.NewValue);
        };
        section.Children.Add(slider);

        _refreshers.Add(() =>
        {
            double value = Math.Clamp(read(), min, max);
            slider.Value = value;
            readout.Text = percent ? $"{Math.Round(value / max * 100)}%" : $"{Math.Round(value)}";
        });
        return section;
    }
}

/// Minimal modal text prompt ("Save preset").
internal static class PromptDialog
{
    public static string? Ask(Window? owner, string title, string placeholder)
    {
        var input = new TextBox { MinWidth = 260, Margin = new Thickness(0, 10, 0, 14) };
        var save = new Button { Content = Loc.T("Save"), IsDefault = true, Style = Theme.StyleOf("AccentButton"), MinWidth = 76 };
        var cancel = new Button { Content = Loc.T("Cancel"), IsCancel = true, MinWidth = 76, Margin = new Thickness(0, 0, 8, 0) };
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right };
        buttons.Children.Add(cancel);
        buttons.Children.Add(save);

        var stack = new StackPanel { Margin = new Thickness(20) };
        stack.Children.Add(Theme.Text(placeholder, "FgSecondary", 12));
        stack.Children.Add(input);
        stack.Children.Add(buttons);

        var dialog = new Window
        {
            Title = title, Content = stack, SizeToContent = SizeToContent.WidthAndHeight,
            ResizeMode = ResizeMode.NoResize, ShowInTaskbar = false, Owner = owner,
            WindowStartupLocation = owner != null ? WindowStartupLocation.CenterOwner : WindowStartupLocation.CenterScreen,
        };
        Theme.Prepare(dialog);
        save.Click += (_, _) => dialog.DialogResult = true;
        dialog.Loaded += (_, _) => Keyboard.Focus(input);
        return dialog.ShowDialog() == true ? input.Text : null;
    }
}
