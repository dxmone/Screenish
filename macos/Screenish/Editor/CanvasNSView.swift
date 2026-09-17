//
//  CanvasNSView.swift
//  Screenish
//
//  The AppKit drawing surface. Flipped (top-left origin). Displays the base
//  image scaled to fit, draws annotations via the shared AnnotationDrawer,
//  handles selection/creation/move/resize, inline text editing, crop, and a
//  view-only scroll/pinch zoom for annotating small details.
//

import AppKit
import CoreText

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

    // Crop is non-destructive: the canvas displays only the cropped region as the
    // focused image. Annotation geometry stays in original-image space; cropOrigin
    // shifts between original-image space and the visible inner (crop) space.
    private var cropOrigin: CGPoint { document.cropRect?.origin ?? .zero }
    private var innerSize: CGSize { document.cropRect?.size ?? document.imageSize }
    private var bgLayout: BackgroundLayout {
        BackgroundRenderer.layout(innerSize: innerSize, style: document.background)
    }
    private var outerSize: CGSize { bgLayout.outerSize }
    private var innerOrigin: CGPoint { bgLayout.innerOrigin }

    private var fitScale: CGFloat {
        // Fill the canvas with the composite so the background fills the area and
        // the image stays as large as the padding allows (no extra neutral margin).
        let s = min(bounds.width / outerSize.width, bounds.height / outerSize.height)
        return s.isFinite && s > 0 ? s : 1
    }

    // View-only zoom: scroll/pinch magnifies the canvas so small details can be
    // annotated precisely. Document geometry stays in image pixels and the export
    // is untouched — the full screenshot is always what leaves the editor.
    private var viewZoom: CGFloat = 1
    private var viewPan: CGPoint = .zero    // desired offset minus centered offset

    private var scale: CGFloat { fitScale * viewZoom }

    private var offset: CGPoint {
        // Clamp so the composite never detaches from the view: pan only within the
        // overflow when zoomed in; keep centered along any axis that still fits.
        let w = outerSize.width * scale, h = outerSize.height * scale
        var x = (bounds.width - w) / 2 + viewPan.x
        var y = (bounds.height - h) / 2 + viewPan.y
        if w <= bounds.width { x = (bounds.width - w) / 2 }
        else { x = min(0, max(bounds.width - w, x)) }
        if h <= bounds.height { y = (bounds.height - h) / 2 }
        else { y = min(0, max(bounds.height - h, y)) }
        return CGPoint(x: x, y: y)
    }

    // MARK: - Zoom gestures

    override func scrollWheel(with event: NSEvent) {
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 100
                                                    : event.scrollingDeltaY / 10
        guard delta != 0 else { return }
        setZoom(viewZoom * exp(delta), anchor: convert(event.locationInWindow, from: nil))
    }

    override func magnify(with event: NSEvent) {
        setZoom(viewZoom * (1 + event.magnification),
                anchor: convert(event.locationInWindow, from: nil))
    }

    private func setZoom(_ newZoom: CGFloat, anchor: CGPoint) {
        let clamped = max(1, min(8, newZoom))
        guard clamped != viewZoom else { return }
        commitTextEditing()   // the overlay text view doesn't follow the zoom
        let oldScale = scale
        let oldOffset = offset
        viewZoom = clamped
        if clamped == 1 {
            viewPan = .zero
        } else {
            // Keep the composite point under the cursor stationary:
            // offset' = anchor - (scale'/scale) * (anchor - offset)
            let ratio = scale / oldScale
            viewPan = CGPoint(
                x: anchor.x - ratio * (anchor.x - oldOffset.x)
                    - (bounds.width - outerSize.width * scale) / 2,
                y: anchor.y - ratio * (anchor.y - oldOffset.y)
                    - (bounds.height - outerSize.height * scale) / 2)
        }
        needsDisplay = true
    }

    private func imagePoint(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: (p.x - offset.x) / scale - innerOrigin.x + cropOrigin.x,
                       y: (p.y - offset.y) / scale - innerOrigin.y + cropOrigin.y)
    }

    private func viewRect(_ imageRect: CGRect) -> CGRect {
        CGRect(x: offset.x + (innerOrigin.x + imageRect.minX - cropOrigin.x) * scale,
               y: offset.y + (innerOrigin.y + imageRect.minY - cropOrigin.y) * scale,
               width: imageRect.width * scale, height: imageRect.height * scale)
    }

    private func viewPoint(_ imagePoint: CGPoint) -> CGPoint {
        CGPoint(x: offset.x + (innerOrigin.x + imagePoint.x - cropOrigin.x) * scale,
                y: offset.y + (innerOrigin.y + imagePoint.y - cropOrigin.y) * scale)
    }

    // MARK: - Drawing
    //
    // The static layers (neutral margin + background fill + drop shadow + rounded
    // card + inset + base-image blit) are identical from frame to frame during an
    // annotation drag, yet they dominate the redraw cost (multi-megapixel base
    // blit + gradient + shadow). Cache them as a backing-resolution CGImage and
    // blit it each frame; only annotations are redrawn live on top. The cache is
    // keyed on everything that affects those layers (view pixel size, background,
    // crop, base-image identity) and rebuilt when any of those change.

    private var staticLayerCache: CGImage?
    private struct StaticLayerKey: Equatable {
        var pixelWidth: Int
        var pixelHeight: Int
        var background: Screenish.BackgroundStyle
        var cropRect: CGRect?
        var baseImage: ObjectIdentifier
        // View zoom/pan are baked into the cached bitmap's transform.
        var zoom: CGFloat
        var pan: CGPoint
    }
    private var staticLayerKey: StaticLayerKey?

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let l = bgLayout

        // Static layers (margin + background + shadow + card + inset + base blit),
        // cached at backing resolution and reused until the key changes.
        let backing = convertToBacking(bounds)
        let pixelW = max(1, Int(backing.width.rounded()))
        let pixelH = max(1, Int(backing.height.rounded()))
        let key = StaticLayerKey(pixelWidth: pixelW, pixelHeight: pixelH,
                                 background: document.background, cropRect: document.cropRect,
                                 baseImage: ObjectIdentifier(document.baseImage),
                                 zoom: viewZoom, pan: viewPan)
        if staticLayerKey != key || staticLayerCache == nil {
            staticLayerCache = renderStaticLayers(pixelWidth: pixelW, pixelHeight: pixelH)
            staticLayerKey = key
        }
        if let cached = staticLayerCache {
            // The bitmap is rendered top-left origin (row 0 = top). This view is
            // flipped, so blit with a local flip to keep it upright on screen.
            ctx.saveGState()
            ctx.translateBy(x: 0, y: bounds.height)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(cached, in: bounds)
            ctx.restoreGState()
        }

        // Annotations in original-image space, shifted by the crop origin and
        // clipped to the crop region (so annotations outside the crop are hidden,
        // matching the exported image). Drawn live every frame on top of the
        // cached static bitmap.
        ctx.saveGState()
        ctx.translateBy(x: offset.x, y: offset.y)
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: l.innerOrigin.x - cropOrigin.x, y: l.innerOrigin.y - cropOrigin.y)
        ctx.clip(to: CGRect(origin: cropOrigin, size: innerSize))
        for annotation in document.annotations where annotation.id != editingAnnotationID {
            AnnotationDrawer.draw(annotation, in: ctx, base: document.baseImage)
        }
        if let draft { AnnotationDrawer.draw(draft, in: ctx, base: document.baseImage) }
        ctx.restoreGState()

        drawCropOverlay(ctx)
        drawSelectionHandles(ctx)
    }

    /// Render the static layers into a backing-resolution bitmap. The composite
    /// transform (offset/scale) is baked in at backing scale so the result blits
    /// 1:1 over `bounds` and is pixel-identical to drawing them directly.
    private func renderStaticLayers(pixelWidth: Int, pixelHeight: Int) -> CGImage? {
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8,
            bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

        // The bitmap is bottom-left origin; flip to match the view's top-left
        // (flipped) coordinate space, then scale points → backing pixels.
        let backingScale = bounds.height > 0 ? CGFloat(pixelHeight) / bounds.height : 1
        ctx.translateBy(x: 0, y: CGFloat(pixelHeight))
        ctx.scaleBy(x: backingScale, y: -backingScale)

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
        // Clip to the visible (crop) region, then draw the full base shifted so the
        // crop origin lands at the inner top-left — only the cropped part shows.
        ctx.clip(to: CGRect(origin: .zero, size: innerSize))
        ctx.draw(document.baseImage,
                 in: CGRect(x: -cropOrigin.x, y: -cropOrigin.y,
                            width: document.imageSize.width, height: document.imageSize.height))
        ctx.restoreGState()
        ctx.restoreGState()

        ctx.restoreGState() // composite transform
        return ctx.makeImage()
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
        // Only preview the active drag; a committed crop is already shown cropped.
        guard let rect = cropDraft else { return }
        let v = viewRect(rect)
        // Darken everything outside the selection with an even-odd mask so the
        // inside keeps showing the real image (no transparent punch-through).
        let path = CGMutablePath()
        path.addRect(bounds)
        path.addRect(v)
        ctx.addPath(path)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.45).cgColor)
        ctx.fillPath(using: .evenOdd)
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

        // Text tool: click an existing text annotation → edit it, not a new box.
        if document.tool == .text, let hit = annotationHit(p), hit.kind == .text {
            document.selectionID = hit.id
            creatingText = false
            startEditing(hit)
            dragMode = .none
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
                if d.kind == .text {
                    // Drag → sized box; click (tiny) → default box at the click point.
                    let r = d.rect
                    if r.width < 12 || r.height < 12 {
                        let w: CGFloat = 240
                        let h = d.style.fontSize * 1.6
                        d.start = CGPoint(x: r.minX, y: r.minY)
                        d.end = CGPoint(x: r.minX + w, y: r.minY + h)
                    }
                    d.style = document.style
                    document.add(d)
                    draft = nil
                    creatingText = true
                    startEditing(d)
                    dragMode = .none
                    moveOriginal = nil
                    needsDisplay = true
                    return
                }
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

    /// Mirror the annotation's text style onto the live NSTextView (font design,
    /// boxed background/white text, inner padding) for WYSIWYG editing.
    private func applyTextStyle(to tv: NSTextView, style: AnnotationStyle) {
        let ts = style.textStyle
        tv.font = ts.font(size: style.fontSize * scale)
        if ts.isBoxed {
            tv.textColor = .white
            tv.backgroundColor = style.color
        } else {
            tv.textColor = style.color
            tv.backgroundColor = NSColor.black.withAlphaComponent(0.15)
        }
        let pad = ts.boxPadding(for: style.fontSize) * scale
        tv.textContainerInset = CGSize(width: pad, height: pad)
    }

    private func startEditing(_ annotation: Annotation) {
        let vRect = viewRect(annotation.rect)
        let tv = NSTextView(frame: vRect)
        tv.drawsBackground = true
        tv.isRichText = false
        tv.string = annotation.text
        tv.delegate = self
        applyTextStyle(to: tv, style: annotation.style)

        // Multi-line: wrap to the box width, allow newlines, grow vertically.
        tv.isHorizontallyResizable = false
        tv.isVerticallyResizable = true
        tv.textContainer?.widthTracksTextView = true
        tv.textContainer?.containerSize = CGSize(width: vRect.width,
                                                 height: .greatestFiniteMagnitude)
        tv.minSize = CGSize(width: vRect.width, height: vRect.height)
        tv.maxSize = CGSize(width: vRect.width, height: .greatestFiniteMagnitude)

        addSubview(tv)
        window?.makeFirstResponder(tv)
        textView = tv
        editingAnnotationID = annotation.id
        needsDisplay = true
    }

    /// Push the editing annotation's current style into the live text view so
    /// font-size / colour changes from the toolbar show up while still editing.
    func syncEditingTextStyle() {
        guard let tv = textView, let id = editingAnnotationID,
              let a = document.annotations.first(where: { $0.id == id }) else { return }
        applyTextStyle(to: tv, style: a.style)
        // Re-fit the box height for the new font (same as textDidChange auto-grow).
        if let lm = tv.layoutManager, let container = tv.textContainer {
            lm.ensureLayout(for: container)
            var frame = tv.frame
            frame.size.height = max(lm.usedRect(for: container).height, frame.height)
            tv.frame = frame
        }
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
                // Fit the box height to the (possibly multi-line) text.
                let a = document.annotations[idx]
                let r = a.rect
                let h = fittedTextHeight(string, width: r.width, fontSize: a.style.fontSize,
                                         textStyle: a.style.textStyle)
                document.annotations[idx].start = CGPoint(x: r.minX, y: r.minY)
                document.annotations[idx].end = CGPoint(x: r.maxX, y: r.minY + h)
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

    func textDidChange(_ notification: Notification) {
        // Auto-grow the editing box vertically as lines are added.
        guard let tv = textView, let lm = tv.layoutManager,
              let container = tv.textContainer else { return }
        lm.ensureLayout(for: container)
        let used = lm.usedRect(for: container).height
        var frame = tv.frame
        frame.size.height = max(used, frame.height)
        tv.frame = frame
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
