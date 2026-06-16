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

        // Base of the head (where the shaft ends).
        let baseX = tip.x - ux * headLength
        let baseY = tip.y - uy * headLength

        ctx.saveGState()
        ctx.setStrokeColor(a.style.color.cgColor)
        ctx.setFillColor(a.style.color.cgColor)
        ctx.setLineWidth(w)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        // Shaft: tail → base of head.
        ctx.move(to: tail)
        ctx.addLine(to: CGPoint(x: baseX, y: baseY))
        ctx.strokePath()

        // Filled triangle head.
        let left = CGPoint(x: baseX + px * headHalfWidth, y: baseY + py * headHalfWidth)
        let right = CGPoint(x: baseX - px * headHalfWidth, y: baseY - py * headHalfWidth)
        ctx.move(to: tip)
        ctx.addLine(to: left)
        ctx.addLine(to: right)
        ctx.closePath()
        ctx.fillPath()
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
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: a.style.fontSize, weight: .semibold),
            .foregroundColor: a.style.color,
        ]
        let attr = NSAttributedString(string: a.text, attributes: attrs)
        let rect = a.rect

        ctx.saveGState()
        // Local flip so CoreText draws upright within this top-left context.
        ctx.translateBy(x: rect.minX, y: rect.minY + rect.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.textMatrix = .identity
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: rect.width, height: rect.height),
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
