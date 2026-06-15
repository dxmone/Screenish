//
//  EditorWindowController.swift
//  Screenish
//
//  Hosts the SwiftUI editor in a standard window. One controller per open Shot.
//

import AppKit
import SwiftUI

@MainActor
final class EditorWindowController: NSWindowController, NSWindowDelegate {
    var onClosed: (() -> Void)?

    init(shot: Shot, onDone: @escaping ([Annotation], CGRect?, BackgroundStyle) -> Void) {
        let document = EditorDocument(shot: shot)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 740),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false)
        window.title = String(localized: "Edit Screenshot")
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self

        let root = EditorView(
            document: document,
            onDone: onDone,
            onClose: { [weak self] in self?.close() })
        window.contentView = NSHostingView(rootView: root)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onClosed?()
    }
}
