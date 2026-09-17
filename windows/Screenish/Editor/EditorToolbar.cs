//
//  EditorToolbar.cs
//  Screenish
//
//  Top toolbar: tool selection + inline color/thickness + undo/redo/delete.
//

using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;

namespace Screenish;

internal sealed class EditorToolbar : StackPanel
{
    private readonly EditorDocument _document;
    private readonly Dictionary<EditorTool, ToggleButton> _toolButtons = new();
    private readonly SwatchColorPicker _color = new();
    private readonly Stepper _lineWidth;
    private readonly Stepper _fontSize;
    private readonly Segmented<ArrowStyle> _arrowStyle;
    private readonly MenuButton _textStyle;
    private readonly Button _undo, _redo, _delete, _clear;
    private readonly TextBlock _caption;

    /// Help text for whatever the pointer is currently over. Shown instantly in
    /// the caption row below — no tooltip delay, no need to select first.
    private string? _hoverHelp;

    public EditorToolbar(EditorDocument document)
    {
        _document = document;
        Margin = new Thickness(10, 6, 10, 6);

        var flow = new WrapPanel();
        Children.Add(flow);

        foreach (var tool in EditorToolExtensions.All)
        {
            var button = new ToggleButton
            {
                Content = Icons.ForTool(tool), Width = 30, Height = 28, Focusable = false,
                Style = Theme.StyleOf("ToolToggle"),
            };
            button.Click += (_, _) =>
            {
                _document.Tool = tool;
                Refresh();   // re-assert the checked state when the active tool is clicked again
            };
            _toolButtons[tool] = button;
            Add(flow, button, tool.HelpText());
        }

        flow.Children.Add(Separator());

        _color.ColorChanged += c => _document.SetStyle(_document.Style with { Color = c });
        Add(flow, _color, Loc.T("Color"));

        _lineWidth = new Stepper(Icons.Make(Icons.LineWeight), 1, 40, 1);
        _lineWidth.ValueChanged += v => _document.SetStyle(_document.Style with { LineWidth = v });
        Add(flow, _lineWidth, Loc.T("Thickness"));

        _arrowStyle = new Segmented<ArrowStyle>(
        [
            (ArrowStyle.Straight, Icons.Make(Icons.Arrow)),
            (ArrowStyle.Curved, Icons.Make(Icons.ArrowCurved)),
        ], segmentWidth: 38);
        _arrowStyle.SelectionChanged += s => _document.SetStyle(_document.Style with { ArrowStyle = s });
        Add(flow, _arrowStyle, Loc.T("Arrow style"));

        var sizeLabel = Theme.Text("aA", "Fg", 13, FontWeights.SemiBold);
        _fontSize = new Stepper(sizeLabel, 8, 200, 2);
        _fontSize.ValueChanged += v => _document.SetStyle(_document.Style with { FontSize = v });
        Add(flow, _fontSize, Loc.T("Text size"));

        _textStyle = new MenuButton(menu =>
        {
            foreach (var style in TextStyleExtensions.All)
            {
                var item = MenuButton.Item(style.Label(),
                    () => _document.SetStyle(_document.Style with { TextStyle = style }));
                item.IsChecked = style == CurrentTextStyle;
                menu.Items.Add(item);
            }
        }) { Width = 140 };
        Add(flow, _textStyle, Loc.T("Text style"));

        flow.Children.Add(Separator());

        _undo = ActionButton(flow, Icons.Undo, Loc.T("Undo"), _document.Undo);
        _redo = ActionButton(flow, Icons.Redo, Loc.T("Redo"), _document.Redo);
        _delete = ActionButton(flow, Icons.Trash, Loc.T("Delete selected"), _document.DeleteSelected);
        _clear = ActionButton(flow, Icons.TrashSlash, Loc.T("Clear all edits"), _document.ClearAnnotations);

        _caption = Theme.Text("", "FgSecondary", 11);
        _caption.Margin = new Thickness(2, 2, 0, 0);
        Children.Add(_caption);

        document.Changed += Refresh;
        Refresh();
    }

    /// Esc closes an open colour popover before it means anything else.
    public bool ClosePopups() => _color.ClosePopup();

    private TextStyle CurrentTextStyle => _document.Selected?.Style.TextStyle ?? _document.Style.TextStyle;

    private void Add(Panel flow, FrameworkElement element, string help)
    {
        element.Margin = new Thickness(0, 3, 3, 3);
        element.MouseEnter += (_, _) => SetHelp(help, true);
        element.MouseLeave += (_, _) => SetHelp(help, false);
        flow.Children.Add(element);
    }

    private Button ActionButton(Panel flow, string icon, string help, Action action)
    {
        var button = new Button
        {
            Content = Icons.Make(icon), Width = 30, Height = 28, Padding = new Thickness(0), Focusable = false,
        };
        button.Click += (_, _) => action();
        Add(flow, button, help);
        return button;
    }

    private static FrameworkElement Separator()
    {
        var line = Theme.Divider(vertical: true);
        line.Height = 20;
        line.Margin = new Thickness(4, 0, 8, 0);
        return line;
    }

    private void SetHelp(string text, bool hovering)
    {
        if (hovering) _hoverHelp = text;
        else if (_hoverHelp == text) _hoverHelp = null;
        _caption.Text = _hoverHelp ?? _document.Tool.HelpText();
    }

    private void Refresh()
    {
        foreach (var (tool, button) in _toolButtons) button.IsChecked = tool == _document.Tool;

        var selected = _document.Selected;
        _color.Color = _document.Style.Color;
        _lineWidth.Value = _document.Style.LineWidth;

        // Arrow-style picker: for the arrow tool or a selected arrow.
        bool showArrow = _document.Tool == EditorTool.Arrow || selected?.Kind == AnnotationKind.Arrow;
        _arrowStyle.Visibility = showArrow ? Visibility.Visible : Visibility.Collapsed;
        _arrowStyle.Selected = selected?.Style.ArrowStyle ?? _document.Style.ArrowStyle;

        // Text size + style: for the text tool or a selected text annotation.
        bool showText = _document.Tool == EditorTool.Text || selected?.Kind == AnnotationKind.Text;
        _fontSize.Visibility = _textStyle.Visibility = showText ? Visibility.Visible : Visibility.Collapsed;
        _fontSize.Value = selected?.Style.FontSize ?? _document.Style.FontSize;
        _textStyle.Title = CurrentTextStyle.Label();

        _undo.IsEnabled = _document.CanUndo;
        _redo.IsEnabled = _document.CanRedo;
        _delete.IsEnabled = _document.SelectionId != null;
        _clear.IsEnabled = _document.Annotations.Count > 0;

        _caption.Text = _hoverHelp ?? _document.Tool.HelpText();
    }
}
