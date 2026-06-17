//
//  Annotation.swift
//  Screenish
//
//  An editable annotation placed on a Shot's base bitmap. All geometry is in
//  image-pixel coordinates with a top-left origin (y grows downward), the same
//  space as the captured CGImage — so export needs no rescaling.
//

import AppKit
import CoreText

enum AnnotationKind: String {
    case arrow
    case line
    case rectangle        // stroked
    case rectangleFilled  // filled
    case ellipse
    case highlight        // translucent marker rectangle
    case text
    case blur
    case pixelate
    case counter          // numbered step marker
    case spotlight        // darkens everything outside an ellipse
    case pencil           // freehand path

    /// Point-based kinds use `start`/`end`; the rest use the derived `rect`.
    var isLinear: Bool { self == .arrow || self == .line }
    var isRedaction: Bool { self == .blur || self == .pixelate }
    /// Freehand path stored in `points`.
    var isPath: Bool { self == .pencil }
}

enum ArrowStyle: String {
    case straight
    case curved
}

enum TextStyle: String, CaseIterable, Identifiable {
    case standard
    case rounded
    case monospaced
    case outlined
    case boxed
    case roundedBoxed
    case monospacedBoxed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard:        return String(localized: "Standard")
        case .rounded:         return String(localized: "Rounded")
        case .monospaced:      return String(localized: "Monospaced")
        case .outlined:        return String(localized: "Outlined")
        case .boxed:           return String(localized: "Boxed")
        case .roundedBoxed:    return String(localized: "Rounded Boxed")
        case .monospacedBoxed: return String(localized: "Monospaced Boxed")
        }
    }

    var isBoxed: Bool { self == .boxed || self == .roundedBoxed || self == .monospacedBoxed }
    var isOutlined: Bool { self == .outlined }
    private var isMono: Bool { self == .monospaced || self == .monospacedBoxed }
    private var isRoundedFont: Bool { self == .rounded || self == .roundedBoxed }
    var hasRoundedBox: Bool { self == .roundedBoxed }

    func font(size: CGFloat) -> NSFont {
        let weight: NSFont.Weight = .semibold
        if isMono { return NSFont.monospacedSystemFont(ofSize: size, weight: weight) }
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        if isRoundedFont, let d = base.fontDescriptor.withDesign(.rounded) {
            return NSFont(descriptor: d, size: size) ?? base
        }
        return base
    }

    /// Inner padding for boxed styles (so glyphs aren't flush to the box edge).
    func boxPadding(for fontSize: CGFloat) -> CGFloat { isBoxed ? fontSize * 0.3 : 0 }

    /// CoreText/AppKit attributes for the glyphs (box fill is drawn separately).
    func textAttributes(size: CGFloat, color: NSColor) -> [NSAttributedString.Key: Any] {
        var attrs: [NSAttributedString.Key: Any] = [.font: font(size: size)]
        if isBoxed {
            attrs[.foregroundColor] = NSColor.white
        } else if isOutlined {
            attrs[.foregroundColor] = NSColor.white
            attrs[.strokeColor] = color
            attrs[.strokeWidth] = -max(3, size * 0.08)  // negative → fill + stroke
        } else {
            attrs[.foregroundColor] = color
        }
        return attrs
    }
}

struct AnnotationStyle {
    var color: NSColor
    var lineWidth: CGFloat
    var fontSize: CGFloat
    var arrowStyle: ArrowStyle = .straight
    var textStyle: TextStyle = .standard

    static let `default` = AnnotationStyle(color: .systemRed, lineWidth: 9, fontSize: 27)
}

struct Annotation: Identifiable {
    let id: UUID
    var kind: AnnotationKind
    var start: CGPoint   // image-pixel space
    var end: CGPoint
    var style: AnnotationStyle
    var text: String
    var points: [CGPoint] // freehand path (pencil); empty otherwise
    var number: Int       // step number (counter); 0 otherwise

    init(id: UUID = UUID(), kind: AnnotationKind, start: CGPoint, end: CGPoint,
         style: AnnotationStyle, text: String = "", points: [CGPoint] = [], number: Int = 0) {
        self.id = id
        self.kind = kind
        self.start = start
        self.end = end
        self.style = style
        self.text = text
        self.points = points
        self.number = number
    }

    /// Normalized bounding rect for rect-based kinds.
    var rect: CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    /// Bounding rect that also covers a freehand path.
    var boundingRect: CGRect {
        guard kind.isPath, !points.isEmpty else { return rect }
        let xs = points.map(\.x), ys = points.map(\.y)
        let minX = xs.min() ?? 0, maxX = xs.max() ?? 0
        let minY = ys.min() ?? 0, maxY = ys.max() ?? 0
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    func movedBy(dx: CGFloat, dy: CGFloat) -> Annotation {
        var copy = self
        copy.start = CGPoint(x: start.x + dx, y: start.y + dy)
        copy.end = CGPoint(x: end.x + dx, y: end.y + dy)
        copy.points = points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
        return copy
    }
}

/// Height (image-pixel space) text needs at a given box width and style.
/// Shared by inline editing (commit/refit) and toolbar size changes.
func fittedTextHeight(_ text: String, width: CGFloat, fontSize: CGFloat,
                      textStyle: TextStyle = .standard) -> CGFloat {
    let pad = textStyle.boxPadding(for: fontSize)
    let textWidth = max(width - pad * 2, 1)
    guard !text.isEmpty, textWidth > 1 else { return fontSize * 1.4 + pad * 2 }
    let attrs: [NSAttributedString.Key: Any] = [.font: textStyle.font(size: fontSize)]
    let attr = NSAttributedString(string: text, attributes: attrs)
    let fs = CTFramesetterCreateWithAttributedString(attr)
    let size = CTFramesetterSuggestFrameSizeWithConstraints(
        fs, CFRange(location: 0, length: attr.length), nil,
        CGSize(width: textWidth, height: .greatestFiniteMagnitude), nil)
    return max(ceil(size.height), fontSize * 1.4) + pad * 2
}
