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

    init(shot: Shot, onDone: @escaping ([Annotation], CGRect?, BackgroundStyle) -> Void,
         onDragDelivered: @escaping () -> Void = {},
         onDiscard: @escaping () -> Void = {}) {
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
            onClose: { [weak self] in self?.close() },
            // No animation at drag START — hiding the source window cancels the
            // in-flight drag. The thumbnail follows the cursor; the window flies
            // away only AFTER a successful drop.
            onDiscard: { [weak self] in
                onDiscard()
                self?.close()
            },
            onDragDelivered: { [weak self] in
                onDragDelivered()
                self?.animateAwayThenClose()
            })
        window.contentView = NSHostingView(rootView: root)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        window?.alphaValue = 1   // reset in case a prior drag animation left it faded
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    /// After a successful drop, shrink + fade the window away, then close.
    private func animateAwayThenClose() {
        guard let window else { close(); return }
        let f = window.frame
        let target = NSRect(x: f.midX - f.width * 0.3, y: f.midY - f.height * 0.3,
                            width: f.width * 0.6, height: f.height * 0.6)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().setFrame(target, display: true)
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.close()
        })
    }

    func windowWillClose(_ notification: Notification) {
        onClosed?()
    }
}
