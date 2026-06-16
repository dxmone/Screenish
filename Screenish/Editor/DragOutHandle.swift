//
//  DragOutHandle.swift
//  Screenish
//
//  AppKit drag source for the editor's "Drag" handle. Renders the current image
//  once at drag start, drags it out as a file promise with a small thumbnail
//  that follows the cursor, and reports begin/deliver/cancel so the editor can
//  animate away and close (or restore). All callbacks fire on the main thread.
//

import AppKit
import SwiftUI
import OSLog
import UniformTypeIdentifiers

struct DragOutHandle: NSViewRepresentable {
    var renderImage: () -> CGImage?
    var date: Date
    var onWillBegin: () -> Void
    var onDelivered: () -> Void
    var onCancelled: () -> Void

    func makeNSView(context: Context) -> DragSourceNSView {
        let view = DragSourceNSView()
        view.renderImage = renderImage
        view.date = { date }
        view.onWillBegin = onWillBegin
        view.onDelivered = onDelivered
        view.onCancelled = onCancelled
        return view
    }

    func updateNSView(_ nsView: DragSourceNSView, context: Context) {
        nsView.renderImage = renderImage
        nsView.date = { date }
        nsView.onWillBegin = onWillBegin
        nsView.onDelivered = onDelivered
        nsView.onCancelled = onCancelled
    }
}

final class DragSourceNSView: NSView, NSDraggingSource {
    var renderImage: (() -> CGImage?)?
    var date: (() -> Date)?
    var onWillBegin: (() -> Void)?
    var onDelivered: (() -> Void)?
    var onCancelled: (() -> Void)?

    private var mouseDownPoint: NSPoint = .zero

    private let label = NSTextField(labelWithString: "")
    private let icon = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.secondaryLabelColor.withAlphaComponent(0.15).cgColor

        icon.image = NSImage(systemSymbolName: "hand.draw", accessibilityDescription: nil)
        icon.translatesAutoresizingMaskIntoConstraints = false
        label.stringValue = String(localized: "Drag")
        label.font = .systemFont(ofSize: 12)
        label.translatesAutoresizingMaskIntoConstraints = false
        let stack = NSStackView(views: [icon, label])
        stack.orientation = .horizontal
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: 86, height: 28) }

    // Subviews must not swallow the drag — route all hits to self.
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = convert(event.locationInWindow, from: nil)
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard hypot(p.x - mouseDownPoint.x, p.y - mouseDownPoint.y) > 3 else { return }
        startDrag(with: event)
    }

    private func startDrag(with event: NSEvent) {
        guard let image = renderImage?() else {
            Log.drag.error("drag aborted: render produced no image")
            return
        }
        let format = Prefs.format

        // Write the file eagerly and drag a real file URL. File promises only work
        // in Finder; a concrete file URL drops into Terminal, Mail, chat apps, etc.
        guard let data = ImageExport.encode(image, as: format) else {
            Log.drag.error("drag aborted: encode failed")
            return
        }
        let url = ShotDrag.dragDirectory
            .appendingPathComponent(ImageExport.fileName(for: date?() ?? Date(), format: format))
        do {
            try data.write(to: url)
        } catch {
            Log.drag.error("drag aborted: write failed \(error.localizedDescription, privacy: .public)")
            return
        }

        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let thumb = thumbnail(from: image)
        let origin = NSPoint(x: bounds.midX - thumb.size.width / 2,
                             y: bounds.midY - thumb.size.height / 2)
        item.setDraggingFrame(NSRect(origin: origin, size: thumb.size), contents: thumb)

        Log.breadcrumb("drag begin: \(url.lastPathComponent)")
        beginDraggingSession(with: [item], event: event, source: self)
    }

    private func thumbnail(from cgImage: CGImage) -> NSImage {
        let maxW: CGFloat = 200
        let w = CGFloat(cgImage.width), h = CGFloat(cgImage.height)
        let scale = min(1, maxW / max(w, 1))
        let size = NSSize(width: (w * scale).rounded(), height: (h * scale).rounded())
        return NSImage(cgImage: cgImage, size: size)
    }

    // MARK: - NSDraggingSource

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        onWillBegin?()
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint,
                         operation: NSDragOperation) {
        if operation.isEmpty {
            Log.breadcrumb("drag cancelled")
            onCancelled?()
        } else {
            Log.breadcrumb("drag delivered: \(operation.rawValue)")
            onDelivered?()
        }
    }
}
