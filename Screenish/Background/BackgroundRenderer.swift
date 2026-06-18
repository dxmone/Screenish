//
//  BackgroundRenderer.swift
//  Screenish
//
//  Wraps the annotated (and cropped) image in padding + background + rounded
//  corners + shadow, sized to an optional aspect ratio. Resolution-independent:
//  all sizes derive from fractions of the inner image.
//

import AppKit
import CoreImage

/// Geometry of the beautified canvas. The "card" is the image plus its inset
/// frame (this is what gets rounded corners + shadow); padding surrounds the
/// card; the whole thing is the outer canvas (optionally aspect-ratio padded).
/// Centered, so the same origins work in top-left (canvas) and bottom-left
/// (export) spaces.
struct BackgroundLayout {
    let outerSize: CGSize
    let cardOrigin: CGPoint   // card top-left within outer
    let cardSize: CGSize
    let innerOrigin: CGPoint  // image top-left within outer (= cardOrigin + inset)
    let cornerRadius: CGFloat // applied to the card
    let insetPx: CGFloat
}

enum BackgroundRenderer {
    /// Built `CGGradient`s keyed by `GradientPreset.id`. Presets are immutable
    /// (stable id, fixed colors/angle) so a built gradient never goes stale.
    /// Main-thread only (all rendering is), so no locking is needed.
    private static var gradientCache: [String: CGGradient] = [:]

    static func layout(innerSize: CGSize, style: BackgroundStyle) -> BackgroundLayout {
        let innerW = innerSize.width, innerH = innerSize.height
        let longest = max(innerW, innerH)

        let inset = (style.insetFraction * longest).rounded()
        let cardW = innerW + inset * 2
        let cardH = innerH + inset * 2

        let padding = (style.paddingFraction * longest).rounded()
        var contentW = cardW + padding * 2
        var contentH = cardH + padding * 2
        if let ratio = style.ratio.value {
            if contentW / contentH < ratio {
                contentW = (contentH * ratio).rounded()
            } else {
                contentH = (contentW / ratio).rounded()
            }
        }
        let outerW = max(contentW, cardW), outerH = max(contentH, cardH)
        let cardOrigin = CGPoint(x: ((outerW - cardW) / 2).rounded(),
                                 y: ((outerH - cardH) / 2).rounded())
        let innerOrigin = CGPoint(x: cardOrigin.x + inset, y: cardOrigin.y + inset)
        let radius = min(style.cornerRadiusFraction * min(cardW, cardH), min(cardW, cardH) / 2)
        return BackgroundLayout(outerSize: CGSize(width: outerW, height: outerH),
                                cardOrigin: cardOrigin, cardSize: CGSize(width: cardW, height: cardH),
                                innerOrigin: innerOrigin, cornerRadius: radius, insetPx: inset)
    }

    static func wrap(inner: CGImage, style: BackgroundStyle) -> CGImage {
        guard !style.isEmpty else { return inner }

        let innerSize = CGSize(width: inner.width, height: inner.height)
        let l = layout(innerSize: innerSize, style: style)
        let outerW = Int(l.outerSize.width), outerH = Int(l.outerSize.height)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: outerW, height: outerH, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return inner }

        let outerRect = CGRect(x: 0, y: 0, width: outerW, height: outerH)
        applyFill(style.fill, in: outerRect, ctx: ctx, space: space)

        let cardRect = CGRect(origin: l.cardOrigin, size: l.cardSize)
        let innerRect = CGRect(origin: l.innerOrigin, size: innerSize)
        let radius = l.cornerRadius

        if style.shadowOpacity > 0 {
            let blur = max(1, style.shadowRadiusFraction * max(innerSize.width, innerSize.height))
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -blur * 0.35), blur: blur,
                          color: NSColor.black.withAlphaComponent(style.shadowOpacity).cgColor)
            ctx.addPath(CGPath(roundedRect: cardRect, cornerWidth: radius,
                               cornerHeight: radius, transform: nil))
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillPath()
            ctx.restoreGState()
        }

        // Card (inset frame), rounded; the image sits inside it.
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: cardRect, cornerWidth: radius,
                           cornerHeight: radius, transform: nil))
        ctx.clip()
        if l.insetPx > 0 {
            ctx.setFillColor(style.insetColor.cgColor)
            ctx.fill(cardRect)
        }
        ctx.draw(inner, in: innerRect)
        ctx.restoreGState()

        return ctx.makeImage() ?? inner
    }

    /// Draw the background fill into `rect` of `ctx` (shared by export + canvas).
    static func applyFill(_ fill: BackgroundFill, in rect: CGRect,
                          ctx: CGContext, space: CGColorSpace) {
        switch fill {
        case .none:
            break
        case .solid(let color):
            ctx.setFillColor(color.cgColor)
            ctx.fill(rect)
        case .gradient(let preset):
            guard let gradient = gradient(for: preset, space: space) else { return }
            let a = preset.angle * .pi / 180
            let dx = cos(a), dy = sin(a)
            let cx = rect.midX, cy = rect.midY
            let half = (abs(dx) * rect.width + abs(dy) * rect.height) / 2
            let start = CGPoint(x: cx - dx * half, y: cy - dy * half)
            let end = CGPoint(x: cx + dx * half, y: cy + dy * half)
            // Clip to the rect — drawsBefore/After otherwise floods the whole context.
            ctx.saveGState()
            ctx.clip(to: rect)
            ctx.drawLinearGradient(gradient, start: start, end: end,
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            ctx.restoreGState()
        }
    }

    /// Cached `CGGradient` for a preset, built once and reused across redraws
    /// (applyFill runs on every canvas redraw). Re-converts colors to sRGB only
    /// on the first miss.
    private static func gradient(for preset: GradientPreset, space: CGColorSpace) -> CGGradient? {
        if let cached = gradientCache[preset.id] { return cached }
        let cgColors = preset.colors.map { $0.usingColorSpace(.sRGB)?.cgColor ?? $0.cgColor }
        guard let gradient = CGGradient(colorsSpace: space,
                                        colors: cgColors as CFArray, locations: nil) else {
            return nil
        }
        gradientCache[preset.id] = gradient
        return gradient
    }
}
