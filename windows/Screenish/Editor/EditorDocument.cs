//
//  EditorDocument.cs
//  Screenish
//
//  Editable state for one Shot open in the editor: the base bitmap, the list of
//  annotations, the current tool/style, an optional crop, and undo/redo.
//

using System.Windows;
using System.Windows.Media.Imaging;

namespace Screenish;

internal sealed class EditorDocument
{
    public Shot Shot { get; }
    public BitmapSource BaseImage { get; }

    private List<Annotation> _annotations;
    private Guid? _selectionId;
    private EditorTool _tool = EditorTool.Arrow;
    private AnnotationStyle _style = AnnotationStyle.Default;
    private Rect? _cropRect;                       // image-pixel space; null = no crop
    private BackgroundStyle _background;

    /// Raised after any state change; the toolbar, inspector and canvas all refresh from it.
    public event Action? Changed;

    private readonly record struct Snapshot(List<Annotation> Annotations, Rect? CropRect, BackgroundStyle Background);
    private readonly List<Snapshot> _undoStack = [];
    private readonly List<Snapshot> _redoStack = [];

    public EditorDocument(Shot shot)
    {
        Shot = shot;
        BaseImage = shot.BaseImage;
        _annotations = shot.Annotations.ToList();
        _cropRect = shot.CropRect;
        _background = shot.Background;
    }

    public IReadOnlyList<Annotation> Annotations => _annotations;

    public Guid? SelectionId
    {
        get => _selectionId;
        set { if (_selectionId != value) { _selectionId = value; Changed?.Invoke(); } }
    }

    public EditorTool Tool
    {
        get => _tool;
        set { if (_tool != value) { _tool = value; Changed?.Invoke(); } }
    }

    public AnnotationStyle Style
    {
        get => _style;
        set { if (_style != value) { _style = value; Changed?.Invoke(); } }
    }

    public Rect? CropRect => _cropRect;

    public BackgroundStyle Background
    {
        get => _background;
        set { if (_background != value) { _background = value; Changed?.Invoke(); } }
    }

    private Snapshot CurrentSnapshot => new(_annotations.ToList(), _cropRect, _background);

    public Size ImageSize => new(BaseImage.PixelWidth, BaseImage.PixelHeight);

    public Annotation? Selected => _selectionId is Guid id ? _annotations.Find(a => a.Id == id) : null;

    // MARK: - Undo

    public bool CanUndo => _undoStack.Count > 0;
    public bool CanRedo => _redoStack.Count > 0;

    /// Snapshot current state before a mutation. Call once per user gesture.
    public void BeginInteraction()
    {
        _undoStack.Add(CurrentSnapshot);
        _redoStack.Clear();
    }

    public void Undo()
    {
        if (_undoStack.Count == 0) return;
        var snapshot = _undoStack[^1];
        _undoStack.RemoveAt(_undoStack.Count - 1);
        _redoStack.Add(CurrentSnapshot);
        Apply(snapshot);
    }

    public void Redo()
    {
        if (_redoStack.Count == 0) return;
        var snapshot = _redoStack[^1];
        _redoStack.RemoveAt(_redoStack.Count - 1);
        _undoStack.Add(CurrentSnapshot);
        Apply(snapshot);
    }

    private void Apply(Snapshot snapshot)
    {
        _annotations = snapshot.Annotations.ToList();
        _cropRect = snapshot.CropRect;
        _background = snapshot.Background;
        if (Selected == null) _selectionId = null;
        Changed?.Invoke();
    }

    // MARK: - Mutations

    /// Commit a freshly drawn annotation (one undo step).
    public void Add(Annotation annotation)
    {
        BeginInteraction();
        _annotations.Add(annotation);
        _selectionId = annotation.Id;
        Changed?.Invoke();
    }

    /// Replace an annotation in place (no undo push — used during a drag gesture
    /// whose start already called `BeginInteraction`, and by inline text editing).
    public void Replace(Annotation annotation)
    {
        int index = _annotations.FindIndex(a => a.Id == annotation.Id);
        if (index < 0) return;
        _annotations[index] = annotation;
        Changed?.Invoke();
    }

    /// Drop an annotation without an undo step (a text box committed empty).
    public void RemoveSilently(Guid id)
    {
        _annotations.RemoveAll(a => a.Id == id);
        if (_selectionId == id) _selectionId = null;
        Changed?.Invoke();
    }

    public void DeleteSelected()
    {
        if (_selectionId is not Guid id) return;
        BeginInteraction();
        _annotations.RemoveAll(a => a.Id == id);
        _selectionId = null;
        Changed?.Invoke();
    }

    /// Change the current style and apply it to the selected annotation (one undo step).
    public void SetStyle(AnnotationStyle style)
    {
        if (_style == style) return;
        _style = style;
        int index = _selectionId is Guid id ? _annotations.FindIndex(a => a.Id == id) : -1;
        if (index >= 0)
        {
            BeginInteraction();
            var updated = _annotations[index] with { Style = style };
            // Text boxes must grow/shrink with the font so glyphs aren't clipped.
            if (updated.Kind == AnnotationKind.Text) updated = updated.WithFittedTextHeight();
            _annotations[index] = updated;
        }
        Changed?.Invoke();
    }

    /// Remove all annotations (one undo step). Keeps crop and background.
    public void ClearAnnotations()
    {
        if (_annotations.Count == 0) return;
        BeginInteraction();
        _annotations.Clear();
        _selectionId = null;
        Changed?.Invoke();
    }

    public void SetCrop(Rect? rect)
    {
        BeginInteraction();
        _cropRect = rect;
        Changed?.Invoke();
    }
}
