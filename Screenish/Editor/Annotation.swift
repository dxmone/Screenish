//
//  Annotation.swift
//  Screenish
//
//  An editable annotation placed on a Shot's base bitmap. All geometry is in
//  image-pixel coordinates with a top-left origin (y grows downward), the same
//  space as the captured CGImage — so export needs no rescaling.
//

import AppKit

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

    /// Point-based kinds use `start`/`end`; the rest use the derived `rect`.
    var isLinear: Bool { self == .arrow || self == .line }
    var isRedaction: Bool { self == .blur || self == .pixelate }
}

struct AnnotationStyle {
    var color: NSColor
    var lineWidth: CGFloat
    var fontSize: CGFloat

    static let `default` = AnnotationStyle(color: .systemRed, lineWidth: 4, fontSize: 36)
}

struct Annotation: Identifiable {
    let id: UUID
    var kind: AnnotationKind
    var start: CGPoint   // image-pixel space
    var end: CGPoint
    var style: AnnotationStyle
    var text: String

    init(id: UUID = UUID(), kind: AnnotationKind, start: CGPoint, end: CGPoint,
         style: AnnotationStyle, text: String = "") {
        self.id = id
        self.kind = kind
        self.start = start
        self.end = end
        self.style = style
        self.text = text
    }

    /// Normalized bounding rect for rect-based kinds.
    var rect: CGRect {
        CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
               width: abs(end.x - start.x), height: abs(end.y - start.y))
    }

    func movedBy(dx: CGFloat, dy: CGFloat) -> Annotation {
        var copy = self
        copy.start = CGPoint(x: start.x + dx, y: start.y + dy)
        copy.end = CGPoint(x: end.x + dx, y: end.y + dy)
        return copy
    }
}
