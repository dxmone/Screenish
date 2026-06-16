//
//  CanvasNSView.swift
//  Screenish
//
//  The AppKit drawing surface. Flipped (top-left origin). Displays the base
//  image scaled to fit, draws annotations via the shared AnnotationDrawer,
//  handles selection/creation/move/resize, inline text editing, and crop.
//

import AppKit

final class CanvasNSView: NSView {
    let document: EditorDocument

    private var draft: Annotation?              // shape being created
    private var cropDraft: CGRect?              // crop rect being dragged (image space)

    private enum DragMode { case none, create, move, resize(Handle), crop }
    private var dragMode: DragMode = .none
    private var dragStartImage: CGPoint = .zero
    private var moveOriginal: Annotation?
    private var didBeginInteraction = false

    private var textView: NSTextView?
    private var editingAnnotationID: Annotation.ID?
    private var creatingText = false

    init(document: EditorDocument) {
        self.document = document
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: - Geometry (view ↔ inner-image-pixel space)
    //
    // The whole beautified composite (image + inset card + padding) is fit to the
    // canvas and centered, leaving a neutral margin around it (like Xnapper) so it
    // reads as a bounded image. Annotation geometry is in inner-image pixels and
    // maps through the layout's innerOrigin (image top-left within the composite).

    private var innerSize: CGSize { document.imageSize }
    private var bgLayout: BackgroundLayout {
        BackgroundRenderer.layout(innerSize: innerSize, style: document.background)
    }
    private var outerSize: CGSize { bgLayout.outerSize }
    private var innerOrigin: CGPoint { bgLayout.innerOrigin }

    private var scale: CGFloat {
        // Fill the canvas with the composite so the background fills the area and
        // the image stays as large as the padding allows (no extra neutral margin).
        let s = min(bounds.width / outerSize.width, bounds.height / outerSize.height)
        return s.isFinite && s > 0 ? s : 1
    }

    private var offset: CGPoint {
        CGPoint(x: (bounds.width - outerSize.width * scale) / 2,
                y: (bounds.height - outerSize.height * scale) / 2)
    }

    private func imagePoint(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: (p.x - offset.x) / scale - innerOrigin.x,
                       y: (p.y - offset.y) / scale - innerOrigin.y)
    }

    private func viewRect(_ imageRect: CGRect) -> CGRect {
        CGRect(x: offset.x + (innerOrigin.x + imageRect.minX) * scale,
               y: offset.y + (innerOrigin.y + imageRect.minY) * scale,
               width: imageRect.width * scale, height: imageRect.height * scale)
    }

    private func viewPoint(_ imagePoint: CGPoint) -> CGPoint {
        CGPoint(x: offset.x + (innerOrigin.x + imagePoint.x) * scale,
                y: offset.y + (innerOrigin.y + imagePoint.y) * scale)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

        ctx.setFillColor(NSColor.underPageBackgroundColor.cgColor)
        ctx.fill(bounds)

        // Composite (outer) space, top-left origin.
        ctx.saveGState()
        ctx.translateBy(x: offset.x, y: offset.y)
        ctx.scaleBy(x: scale, y: scale)

        let bg = document.background
        let l = bgLayout
        let outerRect = CGRect(origin: .zero, size: l.outerSize)
        let cardRect = CGRect(origin: l.cardOrigin, size: l.cardSize)
        let innerRect = CGRect(origin: l.innerOrigin, size: innerSize)
        let radius = l.cornerRadius

        if !bg.isEmpty {
            BackgroundRenderer.applyFill(bg.fill, in: outerRect, ctx: ctx, space: space)
        }

        if bg.shadowOpacity > 0 {
            let blur = max(1, bg.shadowRadiusFraction * max(innerSize.width, innerSize.height))
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: blur * 0.35), blur: blur,
                          color: NSColor.black.withAlphaComponent(bg.shadowOpacity).cgColor)
            ctx.addPath(CGPath(roundedRect: cardRect, cornerWidth: radius,
                               cornerHeight: radius, transform: nil))
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillPath()
            ctx.restoreGState()
        }

        // Card (inset frame) + base image, clipped to the rounded card.
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: cardRect, cornerWidth: radius,
                           cornerHeight: radius, transform: nil))
        ctx.clip()
        if l.insetPx > 0 {
            ctx.setFillColor(bg.insetColor.cgColor)
            ctx.fill(cardRect)
        }
        ctx.saveGState()
        ctx.translateBy(x: innerRect.minX, y: innerRect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(document.baseImage, in: CGRect(origin: .zero, size: innerSize))
        ctx.restoreGState()
        ctx.restoreGState()

        // Annotations in inner-image space — NOT clipped, so they stay fully
        // visible and editable even with a background/rounded corners.
        ctx.saveGState()
        ctx.translateBy(x: l.innerOrigin.x, y: l.innerOrigin.y)
        for annotation in document.annotations where annotation.id != editingAnnotationID {
            AnnotationDrawer.draw(annotation, in: ctx, base: document.baseImage)
        }
        if let draft { AnnotationDrawer.draw(draft, in: ctx, base: document.baseImage) }
        ctx.restoreGState()

        ctx.restoreGState() // composite transform

        drawCropOverlay(ctx)
        drawSelectionHandles(ctx)
    }

    private func drawSelectionHandles(_ ctx: CGContext) {
        guard document.tool == .select, let sel = document.selected else { return }
        ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
        ctx.setLineWidth(1)
        for (_, point) in handlePoints(for: sel) {
            let v = viewPoint(point)
            let r = CGRect(x: v.x - 4, y: v.y - 4, width: 8, height: 8)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fill(r)
            ctx.stroke(r)
        }
    }

    private func drawCropOverlay(_ ctx: CGContext) {
        let rect = cropDraft ?? document.cropRect
        guard let rect else { return }
        let v = viewRect(rect)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)
        ctx.fill(bounds)
        ctx.setFillColor(NSColor.clear.cgColor)
        ctx.setBlendMode(.copy)
        ctx.fill(v)
        ctx.setBlendMode(.normal)
        ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(v)
    }

    // MARK: - Handles

    private enum Handle {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
        case startPoint, endPoint
    }

    private func handlePoints(for a: Annotation) -> [(Handle, CGPoint)] {
        if a.kind.isLinear {
            return [(.startPoint, a.start), (.endPoint, a.end)]
        }
        // Counter (point) and pencil (path) are move-only — no resize handles.
        if a.kind == .counter || a.kind.isPath { return [] }
        let r = a.rect
        return [
            (.topLeft, CGPoint(x: r.minX, y: r.minY)),
            (.top, CGPoint(x: r.midX, y: r.minY)),
            (.topRight, CGPoint(x: r.maxX, y: r.minY)),
            (.right, CGPoint(x: r.maxX, y: r.midY)),
            (.bottomRight, CGPoint(x: r.maxX, y: r.maxY)),
            (.bottom, CGPoint(x: r.midX, y: r.maxY)),
            (.bottomLeft, CGPoint(x: r.minX, y: r.maxY)),
            (.left, CGPoint(x: r.minX, y: r.midY)),
        ]
    }

    private func handle(at imgPoint: CGPoint, of a: Annotation) -> Handle? {
        let tolerance = 9 / scale
        for (handle, point) in handlePoints(for: a) {
            if abs(point.x - imgPoint.x) <= tolerance && abs(point.y - imgPoint.y) <= tolerance {
                return handle
            }
        }
        return nil
    }

    private func annotationHit(_ imgPoint: CGPoint) -> Annotation? {
        let tolerance = 6 / scale
        for annotation in document.annotations.reversed() {
            if annotation.kind.isLinear {
                if distanceToSegment(imgPoint, annotation.start, annotation.end)
                    <= max(tolerance, annotation.style.lineWidth) {
                    return annotation
                }
            } else if annotation.kind == .counter {
                let radius = max(annotation.style.lineWidth * 2.2, 14)
                if hypot(imgPoint.x - annotation.start.x, imgPoint.y - annotation.start.y)
                    <= radius + tolerance {
                    return annotation
                }
            } else if annotation.boundingRect.insetBy(dx: -tolerance, dy: -tolerance)
                .contains(imgPoint) {
                return annotation
            }
        }
        return nil
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        commitTextEditing()
        let p = imagePoint(event)
        dragStartImage = p
        didBeginInteraction = false

        // Double-click a text annotation to edit it.
        if event.clickCount == 2, let hit = annotationHit(p), hit.kind == .text {
            document.selectionID = hit.id
            creatingText = false
            startEditing(hit)
            dragMode = .none
            return
        }

        if document.tool == .crop {
            cropDraft = CGRect(origin: p, size: .zero)
            dragMode = .crop
            return
        }

        if document.tool == .select {
            if let sel = document.selected, let h = handle(at: p, of: sel) {
                dragMode = .resize(h)
                moveOriginal = sel
                return
            }
            if let hit = annotationHit(p) {
                document.selectionID = hit.id
                dragMode = .move
                moveOriginal = hit
            } else {
                document.selectionID = nil
                dragMode = .none
            }
            needsDisplay = true
            return
        }

        if document.tool == .text {
            beginTextCreation(at: p)
            dragMode = .none
            return
        }

        // Counter → single click places a numbered marker (no drag).
        if document.tool == .counter {
            let number = document.annotations.filter { $0.kind == .counter }.count + 1
            let counter = Annotation(kind: .counter, start: p, end: p,
                                     style: document.style, number: number)
            document.add(counter)
            dragMode = .none
            needsDisplay = true
            return
        }

        // Shape tools → start a draft.
        if let kind = document.tool.annotationKind {
            if kind == .pencil {
                draft = Annotation(kind: .pencil, start: p, end: p,
                                   style: document.style, points: [p])
            } else {
                draft = Annotation(kind: kind, start: p, end: p, style: document.style)
            }
            dragMode = .create
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let p = imagePoint(event)
        switch dragMode {
        case .none:
            break
        case .create:
            if draft?.kind.isPath == true {
                draft?.points.append(p)
                draft?.end = p
            } else {
                draft?.end = p
            }
            needsDisplay = true
        case .crop:
            cropDraft = CGRect(x: min(dragStartImage.x, p.x), y: min(dragStartImage.y, p.y),
                               width: abs(p.x - dragStartImage.x), height: abs(p.y - dragStartImage.y))
            needsDisplay = true
        case .move:
            guard let original = moveOriginal else { return }
            beginInteractionOnce()
            let moved = original.movedBy(dx: p.x - dragStartImage.x, dy: p.y - dragStartImage.y)
            document.replace(moved)
            needsDisplay = true
        case .resize(let handle):
            guard let original = moveOriginal else { return }
            beginInteractionOnce()
            document.replace(resized(original, handle: handle, to: p))
            needsDisplay = true
        }
    }

    override func mouseUp(with event: NSEvent) {
        switch dragMode {
        case .create:
            if var d = draft {
                let r = d.rect
                let bigEnough: Bool
                if d.kind.isPath {
                    bigEnough = d.points.count >= 2
                } else if d.kind.isLinear {
                    bigEnough = hypot(d.end.x - d.start.x, d.end.y - d.start.y) >= 5
                } else {
                    bigEnough = r.width >= 5 && r.height >= 5
                }
                if bigEnough {
                    d.style = document.style
                    document.add(d)
                }
            }
            draft = nil
        case .crop:
            if let c = cropDraft, c.width >= 5, c.height >= 5 {
                document.setCrop(c)
            }
            cropDraft = nil
        default:
            break
        }
        dragMode = .none
        moveOriginal = nil
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 { // delete / forward-delete
            document.deleteSelected()
            needsDisplay = true
        } else {
            super.keyDown(with: event)
        }
    }

    private func beginInteractionOnce() {
        if !didBeginInteraction {
            document.beginInteraction()
            didBeginInteraction = true
        }
    }

    private func resized(_ a: Annotation, handle: Handle, to p: CGPoint) -> Annotation {
        var result = a
        if a.kind.isLinear {
            switch handle {
            case .startPoint: result.start = p
            case .endPoint:   result.end = p
            default: break
            }
            return result
        }
        var minX = a.rect.minX, minY = a.rect.minY, maxX = a.rect.maxX, maxY = a.rect.maxY
        switch handle {
        case .topLeft:     minX = p.x; minY = p.y
        case .top:         minY = p.y
        case .topRight:    maxX = p.x; minY = p.y
        case .right:       maxX = p.x
        case .bottomRight: maxX = p.x; maxY = p.y
        case .bottom:      maxY = p.y
        case .bottomLeft:  minX = p.x; maxY = p.y
        case .left:        minX = p.x
        case .startPoint, .endPoint: break
        }
        result.start = CGPoint(x: minX, y: minY)
        result.end = CGPoint(x: maxX, y: maxY)
        return result
    }

    // MARK: - Text editing

    private func beginTextCreation(at p: CGPoint) {
        let defaultSize = CGSize(width: 240, height: document.style.fontSize * 1.6)
        let annotation = Annotation(kind: .text,
                                    start: p,
                                    end: CGPoint(x: p.x + defaultSize.width, y: p.y + defaultSize.height),
                                    style: document.style, text: "")
        document.add(annotation)
        creatingText = true
        startEditing(annotation)
    }

    func beginEditingSelectedTextIfNeeded() {
        if let sel = document.selected, sel.kind == .text {
            creatingText = false
            startEditing(sel)
        }
    }

    private func startEditing(_ annotation: Annotation) {
        let vRect = viewRect(annotation.rect)
        let tv = NSTextView(frame: vRect)
        tv.font = NSFont.systemFont(ofSize: annotation.style.fontSize * scale, weight: .semibold)
        tv.textColor = annotation.style.color
        tv.backgroundColor = NSColor.black.withAlphaComponent(0.15)
        tv.drawsBackground = true
        tv.isRichText = false
        tv.string = annotation.text
        tv.delegate = self
        tv.textContainerInset = .zero
        addSubview(tv)
        window?.makeFirstResponder(tv)
        textView = tv
        editingAnnotationID = annotation.id
        needsDisplay = true
    }

    func commitTextEditing() {
        guard let tv = textView, let id = editingAnnotationID else { return }
        let string = tv.string
        tv.removeFromSuperview()
        textView = nil
        editingAnnotationID = nil

        if let idx = document.annotations.firstIndex(where: { $0.id == id }) {
            if string.isEmpty {
                document.annotations.remove(at: idx)
                if document.selectionID == id { document.selectionID = nil }
            } else {
                document.annotations[idx].text = string
            }
        }
        creatingText = false
        needsDisplay = true
    }
}

extension CanvasNSView: NSTextViewDelegate {
    func textDidEndEditing(_ notification: Notification) {
        commitTextEditing()
    }
}

/// Shortest distance from a point to a line segment (image-pixel space).
private func distanceToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
    let dx = b.x - a.x, dy = b.y - a.y
    let lengthSquared = dx * dx + dy * dy
    if lengthSquared == 0 { return hypot(p.x - a.x, p.y - a.y) }
    var t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared
    t = max(0, min(1, t))
    let proj = CGPoint(x: a.x + t * dx, y: a.y + t * dy)
    return hypot(p.x - proj.x, p.y - proj.y)
}
