//
//  CanvasView.swift
//  Screenish
//
//  SwiftUI bridge to the AppKit CanvasNSView drawing surface.
//

import SwiftUI

struct CanvasView: NSViewRepresentable {
    @ObservedObject var document: EditorDocument

    func makeNSView(context: Context) -> CanvasNSView {
        CanvasNSView(document: document)
    }

    func updateNSView(_ nsView: CanvasNSView, context: Context) {
        nsView.needsDisplay = true
    }
}
