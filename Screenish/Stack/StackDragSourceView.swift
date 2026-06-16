//
//  StackDragSourceView.swift
//  Screenish
//
//  AppKit drag source covering a Stack card. Mirrors the editor's DragOutHandle:
//  writes the file EAGERLY at drag start and drags a real file URL, so the drop
//  works in Terminal, Finder, and chat/Electron apps (Claude desktop, Slack) —
//  file promises only land in Finder. Also owns the card's click (open editor),
//  hover (dismiss button), and right-click menu, since the overlay would
//  otherwise swallow those events.
//

import AppKit
import SwiftUI
import OSLog
import UniformTypeIdentifiers

struct StackDragSourceView: NSViewRepresentable {
    var image: () -> CGImage
    var date: Date
    var onTap: () -> Void
    var onHoverChange: (Bool) -> Void
    var onSaveToFolder: () -> Void
    var onCopy: () -> Void
    var onRemove: () -> Void
    /// Fires on the main actor once the drop target accepted the file.
    var onDelivered: () -> Void

    func makeNSView(context: Context) -> StackDragNSView {
        let view = StackDragNSView()
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: StackDragNSView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to view: StackDragNSView) {
        view.image = image
        view.date = date
        view.onTap = onTap
        view.onHoverChange = onHoverChange
        view.onSaveToFolder = onSaveToFolder
        view.onCopy = onCopy
        view.onRemove = onRemove
        view.onDelivered = onDelivered
    }
}

final class StackDragNSView: NSView, NSDraggingSource {
    var image: (() -> CGImage)?
    var date: Date = Date()
    var onTap: (() -> Void)?
    var onHoverChange: ((Bool) -> Void)?
    var onSaveToFolder: (() -> Void)?
    var onCopy: (() -> Void)?
    var onRemove: (() -> Void)?
    var onDelivered: (() -> Void)?

    private var mouseDownPoint: NSPoint = .zero
    private var didDrag = false
    private var trackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: - Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow, .activeInActiveApp],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { onHoverChange?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChange?(false) }

    // MARK: - Click vs drag

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = convert(event.locationInWindow, from: nil)
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard !didDrag else { return }
        let p = convert(event.locationInWindow, from: nil)
        guard hypot(p.x - mouseDownPoint.x, p.y - mouseDownPoint.y) > 3 else { return }
        didDrag = true
        startDrag(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        if !didDrag { onTap?() }
    }

    private func startDrag(with event: NSEvent) {
        guard let cgImage = image?() else {
            Log.drag.error("stack drag aborted: no image")
            return
        }
        let format = Prefs.format

        guard let data = ImageExport.encode(cgImage, as: format) else {
            Log.drag.error("stack drag aborted: encode failed")
            return
        }
        let url = ShotDrag.dragDirectory
            .appendingPathComponent(ImageExport.fileName(for: date, format: format))
        do {
            try data.write(to: url)
        } catch {
            Log.drag.error("stack drag aborted: write failed \(error.localizedDescription, privacy: .public)")
            return
        }

        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let thumb = thumbnail(from: cgImage)
        let origin = NSPoint(x: bounds.midX - thumb.size.width / 2,
                             y: bounds.midY - thumb.size.height / 2)
        item.setDraggingFrame(NSRect(origin: origin, size: thumb.size), contents: thumb)

        Log.drag.log("stack begin drag session: \(url.lastPathComponent, privacy: .public)")
        beginDraggingSession(with: [item], event: event, source: self)
    }

    private func thumbnail(from cgImage: CGImage) -> NSImage {
        let maxW: CGFloat = 200
        let w = CGFloat(cgImage.width), h = CGFloat(cgImage.height)
        let scale = min(1, maxW / max(w, 1))
        let size = NSSize(width: (w * scale).rounded(), height: (h * scale).rounded())
        return NSImage(cgImage: cgImage, size: size)
    }

    // MARK: - Context menu

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: String(localized: "Save to Folder"),
                     action: #selector(saveToFolder), keyEquivalent: "").target = self
        menu.addItem(withTitle: String(localized: "Copy"),
                     action: #selector(copyImage), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: String(localized: "Remove"),
                     action: #selector(removeShot), keyEquivalent: "").target = self
        return menu
    }

    @objc private func saveToFolder() { onSaveToFolder?() }
    @objc private func copyImage() { onCopy?() }
    @objc private func removeShot() { onRemove?() }

    // MARK: - NSDraggingSource

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint,
                         operation: NSDragOperation) {
        if operation.isEmpty {
            Log.drag.log("stack drag cancelled")
        } else {
            Log.drag.log("stack drag delivered: \(operation.rawValue)")
            onDelivered?()
        }
    }
}
