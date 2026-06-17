//
//  EditorRenderer.swift
//  Screenish
//
//  Shared annotation drawing + flattening to a CGImage. `AnnotationDrawer` draws
//  one annotation into a CGContext whose CTM is already in image-pixel space with
//  a top-left origin (the canvas applies a fit transform; the renderer uses 1:1).
//  Both the on-screen canvas and export go through the same drawer.
//

import AppKit
import CoreText
import CoreImage
import CoreImage.CIFilterBuiltins

enum AnnotationDrawer {
    static let ciContext = CIContext()

    /// Draw a single annotation in image-pixel top-left space.
    static func draw(_ a: Annotation, in ctx: CGContext, base: CGImage) {
        switch a.kind {
        case .arrow:           drawArrow(a, in: ctx)
        case .line:            drawLine(a, in: ctx)
        case .rectangle:       drawRectangle(a, in: ctx, filled: false)
        case .rectangleFilled: drawRectangle(a, in: ctx, filled: true)
        case .ellipse:         drawEllipse(a, in: ctx)
        case .highlight:       drawHighlight(a, in: ctx)
        case .text:            drawText(a, in: ctx)
        case .blur, .pixelate: drawRedaction(a, in: ctx, base: base)
        case .counter:         drawCounter(a, in: ctx)
        case .spotlight:       drawSpotlight(a, in: ctx, base: base)
        case .pencil:          drawPencil(a, in: ctx)
        }
    }

    // MARK: - Shapes

    private static func drawLine(_ a: Annotation, in ctx: CGContext) {
        ctx.saveGState()
        ctx.setStrokeColor(a.style.color.cgColor)
        ctx.setLineWidth(a.style.lineWidth)
        ctx.setLineCap(.round)
        ctx.move(to: a.start)
        ctx.addLine(to: a.end)
        ctx.strokePath()
        ctx.restoreGState()
    }

    private static func drawArrow(_ a: Annotation, in ctx: CGContext) {
        // Tail at `start` (where the drag begins), head/tip at `end` (where it
        // points). Clean shaft + filled triangle head, sized to the line width.
        let tip = a.end          // arrow points here
        let tail = a.start
        let w = a.style.lineWidth
        let dx = tip.x - tail.x
        let dy = tip.y - tail.y
        let length = max(hypot(dx, dy), 1)
        let ux = dx / length      // unit direction tail → tip
        let uy = dy / length
        let px = -uy              // perpendicular
        let py = ux

        let headLength = min(max(w * 3.5, 18), length)
        let headHalfWidth = w * 1.6

        ctx.saveGState()
        ctx.setStrokeColor(a.style.color.cgColor)
        ctx.setFillColor(a.style.color.cgColor)
        ctx.setLineWidth(w)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        // Direction of the head: along the tangent at the tip (perpendicular
        // offset for curved arrows so the head aligns with the curve).
        var headUx = ux, headUy = uy

        if a.style.arrowStyle == .curved {
            // Quadratic bezier bowed perpendicular from the midpoint.
            let mid = CGPoint(x: (tail.x + tip.x) / 2, y: (tail.y + tip.y) / 2)
            let bow = length * 0.22
            let control = CGPoint(x: mid.x + px * bow, y: mid.y + py * bow)
            let base = CGPoint(x: tip.x - ux * headLength, y: tip.y - uy * headLength)
            ctx.move(to: tail)
            ctx.addQuadCurve(to: base, control: control)
            ctx.strokePath()
            // Tangent at the tip ≈ direction from control to tip.
            let tdx = tip.x - control.x, tdy = tip.y - control.y
            let tlen = max(hypot(tdx, tdy), 1)
            headUx = tdx / tlen; headUy = tdy / tlen
        } else {
            let base = CGPoint(x: tip.x - ux * headLength, y: tip.y - uy * headLength)
            ctx.move(to: tail)
            ctx.addLine(to: base)
            ctx.strokePath()
        }

        // Filled triangle head, oriented along headU.
        let hpx = -headUy, hpy = headUx
        let baseX = tip.x - headUx * headLength
        let baseY = tip.y - headUy * headLength
        let left = CGPoint(x: baseX + hpx * headHalfWidth, y: baseY + hpy * headHalfWidth)
        let right = CGPoint(x: baseX - hpx * headHalfWidth, y: baseY - hpy * headHalfWidth)
        ctx.move(to: tip)
        ctx.addLine(to: left)
        ctx.addLine(to: right)
        ctx.closePath()
        ctx.fillPath()
        ctx.restoreGState()
    }

    private static func drawPencil(_ a: Annotation, in ctx: CGContext) {
        guard a.points.count >= 2 else { return }
        ctx.saveGState()
        ctx.setStrokeColor(a.style.color.cgColor)
        ctx.setLineWidth(a.style.lineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        let path = smoothedPath(a.points)
        ctx.addPath(path)
        ctx.strokePath()
        ctx.restoreGState()
    }

    /// Catmull-Rom smoothing through the points → cubic bezier path.
    private static func smoothedPath(_ pts: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = pts.first else { return path }
        path.move(to: first)
        if pts.count == 2 { path.addLine(to: pts[1]); return path }
        for i in 0..<(pts.count - 1) {
            let p0 = pts[max(i - 1, 0)]
            let p1 = pts[i]
            let p2 = pts[i + 1]
            let p3 = pts[min(i + 2, pts.count - 1)]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        return path
    }

    private static func drawCounter(_ a: Annotation, in ctx: CGContext) {
        let radius = max(a.style.lineWidth * 2.2, 14)
        let center = a.start
        let circle = CGRect(x: center.x - radius, y: center.y - radius,
                            width: radius * 2, height: radius * 2)
        ctx.saveGState()
        ctx.setFillColor(a.style.color.cgColor)
        ctx.fillEllipse(in: circle)

        // CoreText (not NSString.draw) so orientation is deterministic — it draws
        // on the CGContext directly, independent of NSGraphicsContext.current.
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: radius * 1.2, weight: .bold),
            .foregroundColor: NSColor.white,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: "\(a.number)",
                                                                       attributes: attrs))
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))

        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.scaleBy(x: 1, y: -1)            // local flip → upright in top-left space
        ctx.textMatrix = .identity
        ctx.textPosition = CGPoint(x: -width / 2, y: -(ascent - descent) / 2)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
        ctx.restoreGState()
    }

    private static func drawSpotlight(_ a: Annotation, in ctx: CGContext, base: CGImage) {
        let full = CGRect(x: 0, y: 0, width: base.width, height: base.height)
        let rect = a.rect
        ctx.saveGState()
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.55).cgColor)
        // Even-odd fill: outer rect + inner ellipse → darkens everything but the ellipse.
        let path = CGMutablePath()
        path.addRect(full)
        path.addEllipse(in: rect)
        ctx.addPath(path)
        ctx.fillPath(using: .evenOdd)
        ctx.restoreGState()
    }

    private static func drawRectangle(_ a: Annotation, in ctx: CGContext, filled: Bool) {
        ctx.saveGState()
        if filled {
            ctx.setFillColor(a.style.color.cgColor)
            ctx.fill(a.rect)
        } else {
            ctx.setStrokeColor(a.style.color.cgColor)
            ctx.setLineWidth(a.style.lineWidth)
            ctx.stroke(a.rect.insetBy(dx: a.style.lineWidth / 2, dy: a.style.lineWidth / 2))
        }
        ctx.restoreGState()
    }

    private static func drawEllipse(_ a: Annotation, in ctx: CGContext) {
        ctx.saveGState()
        ctx.setStrokeColor(a.style.color.cgColor)
        ctx.setLineWidth(a.style.lineWidth)
        ctx.strokeEllipse(in: a.rect.insetBy(dx: a.style.lineWidth / 2, dy: a.style.lineWidth / 2))
        ctx.restoreGState()
    }

    private static func drawHighlight(_ a: Annotation, in ctx: CGContext) {
        ctx.saveGState()
        ctx.setBlendMode(.multiply)
        ctx.setFillColor(a.style.color.withAlphaComponent(0.4).cgColor)
        ctx.fill(a.rect)
        ctx.restoreGState()
    }

    private static func drawText(_ a: Annotation, in ctx: CGContext) {
        guard !a.text.isEmpty else { return }
        let ts = a.style.textStyle
        let rect = a.rect

        // Boxed styles: fill the box first (rounded variant gets a corner radius).
        if ts.isBoxed {
            ctx.saveGState()
            ctx.setFillColor(a.style.color.cgColor)
            if ts.hasRoundedBox {
                let r = min(a.style.fontSize * 0.5, rect.height / 2)
                ctx.addPath(CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r,
                                   transform: nil))
                ctx.fillPath()
            } else {
                ctx.fill(rect)
            }
            ctx.restoreGState()
        }

        let pad = ts.boxPadding(for: a.style.fontSize)
        let textRect = rect.insetBy(dx: pad, dy: pad)
        let attrs = ts.textAttributes(size: a.style.fontSize, color: a.style.color)
        let attr = NSAttributedString(string: a.text, attributes: attrs)

        ctx.saveGState()
        // Local flip so CoreText draws upright within this top-left context.
        ctx.translateBy(x: textRect.minX, y: textRect.minY + textRect.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.textMatrix = .identity
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: textRect.width, height: textRect.height),
                          transform: nil)
        let framesetter = CTFramesetterCreateWithAttributedString(attr)
        let frame = CTFramesetterCreateFrame(framesetter,
                                             CFRange(location: 0, length: attr.length), path, nil)
        CTFrameDraw(frame, ctx)
        ctx.restoreGState()
    }

    private static func drawRedaction(_ a: Annotation, in ctx: CGContext, base: CGImage) {
        let rect = a.rect
        guard rect.width >= 1, rect.height >= 1,
              let img = redactedImage(kind: a.kind, rect: rect, base: base) else { return }
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.minY + rect.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
        ctx.restoreGState()
    }

    /// Produce a blurred/pixelated copy of the base image region under `rect`
    /// (rect is top-left image-pixel space).
    private static func redactedImage(kind: AnnotationKind, rect: CGRect, base: CGImage) -> CGImage? {
        let ciBase = CIImage(cgImage: base)
        let h = CGFloat(base.height)
        // top-left rect → CoreImage bottom-left rect
        let ciRect = CGRect(x: rect.minX, y: h - rect.maxY, width: rect.width, height: rect.height)

        let output: CIImage
        switch kind {
        case .blur:
            let f = CIFilter.gaussianBlur()
            f.inputImage = ciBase.clampedToExtent()
            f.radius = Float(max(8, min(rect.width, rect.height) / 8))
            guard let out = f.outputImage else { return nil }
            output = out.cropped(to: ciRect)
        case .pixelate:
            let f = CIFilter.pixellate()
            f.inputImage = ciBase.clampedToExtent()
            f.scale = Float(max(8, min(rect.width, rect.height) / 12))
            f.center = CGPoint(x: ciRect.midX, y: ciRect.midY)
            guard let out = f.outputImage else { return nil }
            output = out.cropped(to: ciRect)
        default:
            return nil
        }
        return ciContext.createCGImage(output, from: ciRect)
    }
}

enum EditorRenderer {
    /// Flatten the document (base + annotations, crop, then beautify) to a CGImage.
    static func render(_ document: EditorDocument) -> CGImage? {
        renderComposite(base: document.baseImage,
                        annotations: document.annotations,
                        cropRect: document.cropRect,
                        background: document.background)
    }

    /// Render base + annotations + optional crop, then wrap in the background style.
    static func renderComposite(base: CGImage, annotations: [Annotation],
                                cropRect: CGRect?, background: BackgroundStyle) -> CGImage? {
        guard let full = renderFull(base: base, annotations: annotations) else { return nil }
        var inner = full
        if let crop = cropRect {
            let bounded = crop.intersection(CGRect(x: 0, y: 0,
                                                   width: full.width, height: full.height))
            if !bounded.isNull, bounded.width >= 1, bounded.height >= 1 {
                inner = full.cropping(to: bounded) ?? full
            }
        }
        return BackgroundRenderer.wrap(inner: inner, style: background)
    }

    private static func renderFull(base: CGImage, annotations: [Annotation]) -> CGImage? {
        let w = base.width, h = base.height
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }

        // Move into top-left origin space.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)

        // Draw base upright (undo the flip locally).
        ctx.saveGState()
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(base, in: CGRect(x: 0, y: 0, width: w, height: h))
        ctx.restoreGState()

        for annotation in annotations {
            AnnotationDrawer.draw(annotation, in: ctx, base: base)
        }
        return ctx.makeImage()
    }
}
