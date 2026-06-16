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

struct AnnotationStyle {
    var color: NSColor
    var lineWidth: CGFloat
    var fontSize: CGFloat
    var arrowStyle: ArrowStyle = .straight

    static let `default` = AnnotationStyle(color: .systemRed, lineWidth: 9, fontSize: 54)
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
