//
//  BackgroundStyle.swift
//  Screenish
//
//  Non-destructive beautify state: padding, background fill, corner radius,
//  shadow, and aspect ratio. All sizes are fractions of the inner image so the
//  look is resolution-independent.
//

import AppKit

enum BackgroundFill: Equatable {
    case none
    case solid(NSColor)
    case gradient(GradientPreset)

    static func == (lhs: BackgroundFill, rhs: BackgroundFill) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none): return true
        case let (.solid(a), .solid(b)): return a == b
        case let (.gradient(a), .gradient(b)): return a.id == b.id
        default: return false
        }
    }
}

enum AspectRatioOption: String, CaseIterable, Identifiable {
    case auto, square, fourThree, sixteenNine, threeTwo

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto:        return String(localized: "Auto")
        case .square:      return "1:1"
        case .fourThree:   return "4:3"
        case .sixteenNine: return "16:9"
        case .threeTwo:    return "3:2"
        }
    }

    /// Target width/height ratio, or nil for Auto (no forced ratio).
    var value: CGFloat? {
        switch self {
        case .auto:        return nil
        case .square:      return 1
        case .fourThree:   return 4.0 / 3.0
        case .sixteenNine: return 16.0 / 9.0
        case .threeTwo:    return 3.0 / 2.0
        }
    }
}

struct BackgroundStyle: Equatable {
    var paddingFraction: CGFloat = 0        // 0…0.4 of the inner image's longest side
    var insetFraction: CGFloat = 0          // 0…0.1 colored frame between image and padding
    var insetColor: NSColor = .white
    var cornerRadiusFraction: CGFloat = 0   // 0…0.25 of the card's shortest side
    var shadowRadiusFraction: CGFloat = 0.04
    var shadowOpacity: CGFloat = 0
    var fill: BackgroundFill = .none
    var ratio: AspectRatioOption = .auto

    static let none = BackgroundStyle()

    /// True when the style would not change the image at all (renderer no-op).
    var isEmpty: Bool {
        fill == .none && paddingFraction == 0 && insetFraction == 0
            && cornerRadiusFraction == 0 && shadowOpacity == 0 && ratio == .auto
    }
}
