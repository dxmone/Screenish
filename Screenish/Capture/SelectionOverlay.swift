//
//  SelectionOverlay.swift
//  Screenish
//
//  One borderless overlay window PER display (a single window cannot span
//  displays when "Displays have separate Spaces" is on). The controller holds
//  the shared drag state in AppKit global coordinates; every view draws its
//  slice of the selection. In window mode the hovered window is highlighted.
//

import AppKit

enum OverlayMode { case region, window }

enum OverlayResult {
    case region(CGRect)       // AppKit global rect
    case window(CGWindowID)
    case cancelled
}

@MainActor
final class SelectionOverlayController {
    private var windows: [OverlayWindow] = []
    private var views: [SelectionView] = []
    private var mode: OverlayMode = .region
    private var continuation: CheckedContinuation<OverlayResult, Never>?

    // Shared drag/hover state, all in AppKit global (bottom-left) coordinates.
    private var dragStartGlobal: CGPoint?
    private var dragCurrentGlobal: CGPoint?
    private var hoverWindowID: CGWindowID?
    private var hoverRectGlobal: CGRect?

    func present(mode: OverlayMode) async -> OverlayResult {
        // Defensive: never overwrite a live continuation (would leak it). Resume
        // and tear down any previous session first.
        if let leftover = continuation {
            continuation = nil
            NSCursor.pop() // balance the crosshair push() of the leaked session
            windows.forEach { $0.orderOut(nil) }
            windows.removeAll()
            views.removeAll()
            leftover.resume(returning: .cancelled)
        }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.mode = mode
            self.dragStartGlobal = nil
            self.dragCurrentGlobal = nil
            self.hoverWindowID = nil
            self.hoverRectGlobal = nil

            for screen in NSScreen.screens {
                let win = OverlayWindow(contentRect: screen.frame,
                                        styleMask: .borderless,
                                        backing: .buffered,
                                        defer: false)
                win.level = .screenSaver
                win.backgroundColor = .clear
                win.isOpaque = false
                win.hasShadow = false
                win.ignoresMouseEvents = false
                win.acceptsMouseMovedEvents = true
                win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

                let view = SelectionView(screenFrame: screen.frame, mode: mode)
                view.controller = self
                win.contentView = view
                win.setFrame(screen.frame, display: true)
                win.orderFrontRegardless()
                windows.append(win)
                views.append(view)
            }
            NSApp.activate(ignoringOtherApps: true)
            windows.first?.makeKey()
            // Hold the crosshair on the cursor stack for the overlay's lifetime.
            // A one-shot set() races the async activation and is overwritten when
            // the window isn't yet key; push() survives that gap. Balanced by
            // NSCursor.pop() in finish().
            NSCursor.crosshair.push()
        }
    }

    // MARK: - Event intake (global coordinates)

    func began(at global: CGPoint) {
        guard mode == .region else { return }
        dragStartGlobal = global
        dragCurrentGlobal = global
        redraw()
    }

    func dragged(to global: CGPoint) {
        guard mode == .region else { return }
        dragCurrentGlobal = global
        redraw()
    }

    func ended(at global: CGPoint) {
        switch mode {
        case .region:
            guard let rect = currentGlobalRect(), rect.width >= 3, rect.height >= 3 else {
                finish(.cancelled); return
            }
            finish(.region(rect))
        case .window:
            if let id = hoverWindowID { finish(.window(id)) } else { finish(.cancelled) }
        }
    }

    func moved(to global: CGPoint) {
        guard mode == .window else { return }
        if let (id, rect) = WindowPicker.window(atGlobalPoint: global) {
            hoverWindowID = id
            hoverRectGlobal = rect
        } else {
            hoverWindowID = nil
            hoverRectGlobal = nil
        }
        redraw()
    }

    func cancel() { finish(.cancelled) }

    /// The current highlight rect in global coordinates (selection or hovered window).
    var selectionGlobalRect: CGRect? {
        mode == .region ? currentGlobalRect() : hoverRectGlobal
    }

    private func currentGlobalRect() -> CGRect? {
        guard let s = dragStartGlobal, let c = dragCurrentGlobal else { return nil }
        return CGRect(x: min(s.x, c.x), y: min(s.y, c.y),
                      width: abs(s.x - c.x), height: abs(s.y - c.y))
    }

    private func redraw() { views.forEach { $0.needsDisplay = true } }

    private func finish(_ result: OverlayResult) {
        NSCursor.pop() // balance the crosshair push() in present()
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        views.removeAll()
        continuation?.resume(returning: result)
        continuation = nil
    }
}

/// Borderless window that can still become key (for ESC and mouse events).
final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class SelectionView: NSView {
    private let screenFrame: CGRect   // this display's frame in AppKit global coords
    private let mode: OverlayMode
    weak var controller: SelectionOverlayController?

    init(screenFrame: CGRect, mode: OverlayMode) {
        self.screenFrame = screenFrame
        self.mode = mode
        super.init(frame: NSRect(origin: .zero, size: screenFrame.size))
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited,
                      .cursorUpdate, .inVisibleRect],
            owner: self, userInfo: nil))
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    // Crosshair is set from every AppKit cursor path so that whichever fires first
    // wins, independent of when the overlay becomes key (see push() in present()).
    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }
    override func mouseEntered(with event: NSEvent) { NSCursor.crosshair.set() }

    // MARK: - Coordinates

    /// View-local point → AppKit global point.
    private func toGlobal(_ local: CGPoint) -> CGPoint {
        CGPoint(x: screenFrame.minX + local.x, y: screenFrame.minY + local.y)
    }

    private func localPoint(_ event: NSEvent) -> CGPoint {
        toGlobal(convert(event.locationInWindow, from: nil))
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        controller?.began(at: localPoint(event))
    }

    override func mouseDragged(with event: NSEvent) {
        NSCursor.crosshair.set()
        controller?.dragged(to: localPoint(event))
    }

    override func mouseUp(with event: NSEvent) {
        controller?.ended(at: localPoint(event))
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.crosshair.set()
        controller?.moved(to: localPoint(event))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { controller?.cancel() } // ESC
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.35).setFill()
        bounds.fill()

        guard let global = controller?.selectionGlobalRect else { return }
        // Intersect the global selection with this display, then localize.
        let inter = global.intersection(screenFrame)
        guard !inter.isNull, inter.width > 0, inter.height > 0 else { return }
        let local = CGRect(x: inter.minX - screenFrame.minX,
                           y: inter.minY - screenFrame.minY,
                           width: inter.width, height: inter.height)

        NSColor.clear.setFill()
        local.fill(using: .copy)

        NSColor.controlAccentColor.setStroke()
        let border = NSBezierPath(rect: local)
        border.lineWidth = 2
        border.stroke()

        if mode == .region {
            drawDimensionLabel(globalRect: global, anchorLocal: local)
        }
    }

    private func drawDimensionLabel(globalRect: CGRect, anchorLocal: CGRect) {
        let scale = window?.backingScaleFactor ?? 2
        let px = Int((globalRect.width * scale).rounded())
        let py = Int((globalRect.height * scale).rounded())
        let text = "\(px) × \(py)" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attrs)
        let pad: CGFloat = 6
        var origin = CGPoint(x: anchorLocal.minX, y: anchorLocal.maxY + 6)
        if origin.y + size.height + pad * 2 > bounds.maxY {
            origin.y = anchorLocal.minY - size.height - pad * 2 - 6
        }
        let bg = CGRect(x: origin.x, y: origin.y,
                        width: size.width + pad * 2, height: size.height + pad * 2)
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: bg, xRadius: 5, yRadius: 5).fill()
        text.draw(at: CGPoint(x: bg.minX + pad, y: bg.minY + pad), withAttributes: attrs)
    }
}

/// Finds the frontmost on-screen window under a global (AppKit) point.
enum WindowPicker {
    static func window(atGlobalPoint global: CGPoint) -> (CGWindowID, CGRect)? {
        guard let primary = NSScreen.screens.first else { return nil }
        let primaryHeight = primary.frame.height
        // AppKit global (bottom-left) → CoreGraphics global (top-left).
        let cgPoint = CGPoint(x: global.x, y: primaryHeight - global.y)

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infos = CGWindowListCopyWindowInfo(options, kCGNullWindowID)
            as? [[String: Any]] else { return nil }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        for info in infos {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let pid = info[kCGWindowOwnerPID as String] as? Int32, pid != ownPID,
                  let idNum = info[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat],
                  let cgRect = cgRect(from: boundsDict) else { continue }
            if cgRect.contains(cgPoint) {
                // CoreGraphics rect → AppKit global rect.
                let appKitRect = CGRect(x: cgRect.minX,
                                        y: primaryHeight - cgRect.maxY,
                                        width: cgRect.width, height: cgRect.height)
                return (idNum, appKitRect)
            }
        }
        return nil
    }

    private static func cgRect(from dict: [String: CGFloat]) -> CGRect? {
        guard let x = dict["X"], let y = dict["Y"],
              let w = dict["Width"], let h = dict["Height"] else { return nil }
        return CGRect(x: x, y: y, width: w, height: h)
    }
}
