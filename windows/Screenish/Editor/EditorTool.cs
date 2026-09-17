//
//  EditorTool.cs
//  Screenish
//
//  The tools available in the editor toolbar.
//

namespace Screenish;

internal enum EditorTool
{
    Select, Arrow, Line, Rectangle, RectangleFilled, Ellipse, Highlight,
    Text, Blur, Pixelate, Counter, Spotlight, Pencil, Crop,
}

internal static class EditorToolExtensions
{
    public static readonly EditorTool[] All = Enum.GetValues<EditorTool>();

    public static string Label(this EditorTool tool) => tool switch
    {
        EditorTool.Select => Loc.T("Select"),
        EditorTool.Arrow => Loc.T("Arrow"),
        EditorTool.Line => Loc.T("Line"),
        EditorTool.Rectangle => Loc.T("Rectangle"),
        EditorTool.RectangleFilled => Loc.T("Filled Rectangle"),
        EditorTool.Ellipse => Loc.T("Ellipse"),
        EditorTool.Highlight => Loc.T("Highlight"),
        EditorTool.Text => Loc.T("Text"),
        EditorTool.Blur => Loc.T("Blur"),
        EditorTool.Pixelate => Loc.T("Pixelate"),
        EditorTool.Counter => Loc.T("Counter"),
        EditorTool.Spotlight => Loc.T("Spotlight"),
        EditorTool.Pencil => Loc.T("Pencil"),
        _ => Loc.T("Crop"),
    };

    /// Longer tooltip describing what the tool does.
    public static string HelpText(this EditorTool tool) => tool switch
    {
        EditorTool.Select => Loc.T("Select and move objects"),
        EditorTool.Arrow => Loc.T("Draw an arrow"),
        EditorTool.Line => Loc.T("Draw a line"),
        EditorTool.Rectangle => Loc.T("Draw a rectangle outline"),
        EditorTool.RectangleFilled => Loc.T("Draw a filled rectangle"),
        EditorTool.Ellipse => Loc.T("Draw an ellipse or circle"),
        EditorTool.Highlight => Loc.T("Highlight an area (marker)"),
        EditorTool.Text => Loc.T("Add text"),
        EditorTool.Blur => Loc.T("Blur an area to hide sensitive info"),
        EditorTool.Pixelate => Loc.T("Pixelate an area to hide sensitive info"),
        EditorTool.Counter => Loc.T("Add a numbered step marker"),
        EditorTool.Spotlight => Loc.T("Spotlight an area (darken the rest)"),
        EditorTool.Pencil => Loc.T("Draw freehand"),
        _ => Loc.T("Crop the image"),
    };

    /// The annotation kind this tool creates, if any.
    public static AnnotationKind? AnnotationKind(this EditorTool tool) => tool switch
    {
        EditorTool.Select or EditorTool.Crop => null,
        EditorTool.Arrow => Screenish.AnnotationKind.Arrow,
        EditorTool.Line => Screenish.AnnotationKind.Line,
        EditorTool.Rectangle => Screenish.AnnotationKind.Rectangle,
        EditorTool.RectangleFilled => Screenish.AnnotationKind.RectangleFilled,
        EditorTool.Ellipse => Screenish.AnnotationKind.Ellipse,
        EditorTool.Highlight => Screenish.AnnotationKind.Highlight,
        EditorTool.Text => Screenish.AnnotationKind.Text,
        EditorTool.Blur => Screenish.AnnotationKind.Blur,
        EditorTool.Pixelate => Screenish.AnnotationKind.Pixelate,
        EditorTool.Counter => Screenish.AnnotationKind.Counter,
        EditorTool.Spotlight => Screenish.AnnotationKind.Spotlight,
        _ => Screenish.AnnotationKind.Pencil,
    };
}
