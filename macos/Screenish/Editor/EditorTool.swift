//
//  EditorTool.swift
//  Screenish
//
//  The tools available in the editor toolbar.
//

import Foundation

enum EditorTool: String, CaseIterable, Identifiable {
    case select
    case arrow
    case line
    case rectangle
    case rectangleFilled
    case ellipse
    case highlight
    case text
    case blur
    case pixelate
    case counter
    case spotlight
    case pencil
    case crop

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .select:          return "cursorarrow"
        case .arrow:           return "arrow.up.right"
        case .line:            return "line.diagonal"
        case .rectangle:       return "rectangle"
        case .rectangleFilled: return "rectangle.fill"
        case .ellipse:         return "circle"
        case .highlight:       return "highlighter"
        case .text:            return "textformat"
        case .blur:            return "drop.fill"
        case .pixelate:        return "mosaic"
        case .counter:         return "1.circle.fill"
        case .spotlight:       return "circle.dashed.inset.filled"
        case .pencil:          return "pencil.tip"
        case .crop:            return "crop"
        }
    }

    var label: String {
        switch self {
        case .select:          return String(localized: "Select")
        case .arrow:           return String(localized: "Arrow")
        case .line:            return String(localized: "Line")
        case .rectangle:       return String(localized: "Rectangle")
        case .rectangleFilled: return String(localized: "Filled Rectangle")
        case .ellipse:         return String(localized: "Ellipse")
        case .highlight:       return String(localized: "Highlight")
        case .text:            return String(localized: "Text")
        case .blur:            return String(localized: "Blur")
        case .pixelate:        return String(localized: "Pixelate")
        case .counter:         return String(localized: "Counter")
        case .spotlight:       return String(localized: "Spotlight")
        case .pencil:          return String(localized: "Pencil")
        case .crop:            return String(localized: "Crop")
        }
    }

    /// Longer tooltip describing what the tool does.
    var helpText: String {
        switch self {
        case .select:          return String(localized: "Select and move objects")
        case .arrow:           return String(localized: "Draw an arrow")
        case .line:            return String(localized: "Draw a line")
        case .rectangle:       return String(localized: "Draw a rectangle outline")
        case .rectangleFilled: return String(localized: "Draw a filled rectangle")
        case .ellipse:         return String(localized: "Draw an ellipse or circle")
        case .highlight:       return String(localized: "Highlight an area (marker)")
        case .text:            return String(localized: "Add text")
        case .blur:            return String(localized: "Blur an area to hide sensitive info")
        case .pixelate:        return String(localized: "Pixelate an area to hide sensitive info")
        case .counter:         return String(localized: "Add a numbered step marker")
        case .spotlight:       return String(localized: "Spotlight an area (darken the rest)")
        case .pencil:          return String(localized: "Draw freehand")
        case .crop:            return String(localized: "Crop the image")
        }
    }

    /// The annotation kind this tool creates, if any.
    var annotationKind: AnnotationKind? {
        switch self {
        case .select, .crop:   return nil
        case .arrow:           return .arrow
        case .line:            return .line
        case .rectangle:       return .rectangle
        case .rectangleFilled: return .rectangleFilled
        case .ellipse:         return .ellipse
        case .highlight:       return .highlight
        case .text:            return .text
        case .blur:            return .blur
        case .pixelate:        return .pixelate
        case .counter:         return .counter
        case .spotlight:       return .spotlight
        case .pencil:          return .pencil
        }
    }
}
