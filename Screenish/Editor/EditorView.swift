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
        .onExitCommand { onClose() }   // Esc hides the editor; shot stays in the stack
    }

    /// A grab handle that drags the current (rendered) image into other apps.
    private var dragHandle: some View {
        HStack(spacing: 6) {
            Image(systemName: "hand.draw")
            Text("Drag")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.15))
        .cornerRadius(8)
        .onDrag {
            // Snapshot first; defer the store mutation out of the gesture/update
            // cycle to avoid SwiftUI reentrancy. Close once the drop lands.
            let image = render() ?? document.baseImage
            let annotations = document.annotations
            let crop = document.cropRect
            let bg = document.background
            DispatchQueue.main.async { onDone(annotations, crop, bg) }
            return ShotDrag.itemProvider(image: image, date: document.shot.createdAt,
                                         onDelivered: { onClose() })
        }
        .help(String(localized: "Drag the image into another app"))
    }

    private func render() -> CGImage? { EditorRenderer.render(document) }

    private func copy() {
        if let image = render() { Pasteboard.copy(image) }
    }

    private func save() {
        guard let image = render(),
              let url = ImageExport.write(image, to: Prefs.saveLocation) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func done() {
        onDone(document.annotations, document.cropRect, document.background)
        onClose()
    }
}
