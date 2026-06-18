//
//  EditorView.swift
//  Screenish
//
//  Editor window content: toolbar + canvas + Copy/Save/Done actions.
//

import SwiftUI

struct EditorView: View {
    @ObservedObject var document: EditorDocument
    var onDone: ([Annotation], CGRect?, BackgroundStyle) -> Void
    var onClose: () -> Void
    var onDiscard: () -> Void = {}
    var onDragWillBegin: () -> Void = {}
    var onDragRestore: () -> Void = {}
    var onDragDelivered: () -> Void = {}

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                EditorToolbar(document: document)
                    .background(Color(nsColor: .windowBackgroundColor))
                Divider()
                CanvasView(document: document)
                    .frame(minWidth: 420, minHeight: 340)
                    .clipped()   // keep the composite/checkerboard inside the canvas only
                Divider()
                HStack {
                    dragHandle
                    Spacer()
                    Button("Copy") { copy() }
                        .help(String(localized: "Copy the image to the clipboard"))
                    Button("Save") { save() }
                        .help(String(localized: "Save the image to your folder"))
                    Button("Done") { done() }
                        .keyboardShortcut(.defaultAction)
                        .help(String(localized: "Apply edits and update the shot in the stack"))
                }
                .padding(10)
                .background(Color(nsColor: .windowBackgroundColor))
            }
            Divider()
            InspectorPanel(document: document)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 900, minHeight: 520)
        .onExitCommand { onDiscard() }   // Esc discards the shot (removes from stack) + closes
    }

    /// A grab handle (self-contained AppKit drag source) that drags the current
    /// rendered image into other apps.
    private var dragHandle: some View {
        DragOutHandle(
            renderImage: { render() },
            date: document.shot.createdAt,
            onWillBegin: onDragWillBegin,
            onDelivered: onDragDelivered,
            onCancelled: onDragRestore)
        .frame(width: 86, height: 28)
        .help(String(localized: "Drag the image into another app"))
    }

    private func render() -> CGImage? { EditorRenderer.render(document) }

    private func copy() {
        if let image = render() { Pasteboard.copy(image) }
    }

    private func save() {
        guard let image = render() else {
            ShotDrag.presentSaveError(ImageExportError.encodeFailed)
            return   // keep the editor open so the user can retry
        }
        do {
            let url = try ImageExport.write(image, to: Prefs.saveLocation)
            NSWorkspace.shared.activateFileViewerSelecting([url])
            done()   // persist edits + close the editor only on success
        } catch {
            ShotDrag.presentSaveError(error)   // failed → leave the editor open
        }
    }

    private func done() {
        onDone(document.annotations, document.cropRect, document.background)
        onClose()
    }
}
