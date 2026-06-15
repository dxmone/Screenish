//
//  EditorDocument.swift
//  Screenish
//
//  Editable state for one Shot open in the editor: the base bitmap, the list of
//  annotations, the current tool/style, an optional crop, and undo/redo.
//

import AppKit
import Combine

@MainActor
final class EditorDocument: ObservableObject {
    let shot: Shot
    let baseImage: CGImage

    @Published var annotations: [Annotation] = []
    @Published var selectionID: Annotation.ID?
    @Published var tool: EditorTool = .arrow
    @Published var style: AnnotationStyle = .default
    @Published var cropRect: CGRect?          // image-pixel space; nil = no crop
    @Published var background: BackgroundStyle = .none

    private struct Snapshot {
        var annotations: [Annotation]
        var cropRect: CGRect?
        var background: BackgroundStyle
    }
    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []

    init(shot: Shot) {
        self.shot = shot
        self.baseImage = shot.baseImage
        self.annotations = shot.annotations
        self.cropRect = shot.cropRect
        self.background = shot.background
    }

    private var currentSnapshot: Snapshot {
        Snapshot(annotations: annotations, cropRect: cropRect, background: background)
    }

    var imageSize: CGSize {
        CGSize(width: baseImage.width, height: baseImage.height)
    }

    var selected: Annotation? {
        guard let id = selectionID else { return nil }
        return annotations.first { $0.id == id }
    }

    // MARK: - Undo

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Snapshot current state before a mutation. Call once per user gesture.
    func beginInteraction() {
        undoStack.append(currentSnapshot)
        redoStack.removeAll()
    }

    func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        redoStack.append(currentSnapshot)
        apply(snapshot)
        if selectionID == nil || !annotations.contains(where: { $0.id == selectionID }) {
            selectionID = nil
        }
    }

    func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        undoStack.append(currentSnapshot)
        apply(snapshot)
    }

    private func apply(_ snapshot: Snapshot) {
        annotations = snapshot.annotations
        cropRect = snapshot.cropRect
        background = snapshot.background
    }

    // MARK: - Mutations

    /// Commit a freshly drawn annotation (one undo step).
    func add(_ annotation: Annotation) {
        beginInteraction()
        annotations.append(annotation)
        selectionID = annotation.id
    }

    /// Replace an annotation in place (no undo push — used during a drag gesture
    /// whose start already called `beginInteraction`).
    func replace(_ annotation: Annotation) {
        guard let idx = annotations.firstIndex(where: { $0.id == annotation.id }) else { return }
        annotations[idx] = annotation
    }

    func deleteSelected() {
        guard let id = selectionID else { return }
        beginInteraction()
        annotations.removeAll { $0.id == id }
        selectionID = nil
    }

    /// Apply the current `style` to the selected annotation (one undo step).
    func applyStyleToSelection() {
        guard let id = selectionID,
              let idx = annotations.firstIndex(where: { $0.id == id }) else { return }
        beginInteraction()
        annotations[idx].style = style
    }

    func setCrop(_ rect: CGRect?) {
        beginInteraction()
        cropRect = rect
    }
}
