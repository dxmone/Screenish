//
//  BackgroundStyle.swift
//  Screenish
//
//  Non-destructive beautify state: padding, background fill, corner radius,
//  shadow, and aspect ratio. All sizes are fractions of the inner image so the
//  look is resolution-independent.
//

import AppKit

enum BackgroundFill: Equatable, Codable {
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

    private enum CodingKeys: String, CodingKey { case kind, colorHex, gradient }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .none:
            try c.encode("none", forKey: .kind)
        case .solid(let color):
            try c.encode("solid", forKey: .kind)
            try c.encode(color.hexRGBA, forKey: .colorHex)
        case .gradient(let preset):
            try c.encode("gradient", forKey: .kind)
            try c.encode(preset, forKey: .gradient)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "solid":
            let hex = try c.decode(String.self, forKey: .colorHex)
            self = .solid(NSColor(hexRGBA: hex) ?? .white)
        case "gradient":
            self = .gradient(try c.decode(GradientPreset.self, forKey: .gradient))
        default:
            self = .none
        }
    }
}

enum AspectRatioOption: String, CaseIterable, Identifiable {
    case auto, square, fourThree, sixteenNine, threeTwo
    // Social presets (named ratios).
    case instagramPortrait, story, wide, pinterest, youtube

    var id: String { rawValue }

    /// Generic ratio shown in the segmented control.
    static let basic: [AspectRatioOption] = [.auto, .square, .fourThree, .sixteenNine, .threeTwo]
    /// Named social presets shown in the "Size" menu.
    static let social: [AspectRatioOption] = [.instagramPortrait, .story, .wide, .pinterest, .youtube]

    var label: String {
        switch self {
        case .auto:              return String(localized: "Auto")
        case .square:            return "1:1"
        case .fourThree:         return "4:3"
        case .sixteenNine:       return "16:9"
        case .threeTwo:          return "3:2"
        case .instagramPortrait: return String(localized: "Instagram 4:5")
        case .story:             return String(localized: "Story 9:16")
        case .wide:              return String(localized: "Facebook/LinkedIn 1.91:1")
        case .pinterest:         return String(localized: "Pinterest 2:3")
        case .youtube:           return String(localized: "YouTube 16:9")
        }
    }

    /// Target width/height ratio, or nil for Auto (no forced ratio).
    var value: CGFloat? {
        switch self {
        case .auto:              return nil
        case .square:            return 1
        case .fourThree:         return 4.0 / 3.0
        case .sixteenNine:       return 16.0 / 9.0
        case .threeTwo:          return 3.0 / 2.0
        case .instagramPortrait: return 4.0 / 5.0
        case .story:             return 9.0 / 16.0
        case .wide:              return 1.91
        case .pinterest:         return 2.0 / 3.0
        case .youtube:           return 16.0 / 9.0
        }
    }
}

struct BackgroundStyle: Equatable, Codable {
    var paddingFraction: CGFloat = 0        // 0…0.4 of the inner image's longest side
    var insetFraction: CGFloat = 0          // 0…0.1 colored frame between image and padding
    var insetColor: NSColor = .white
    var balanceInset: Bool = false          // inset color auto-sampled from the image
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

    // MARK: - Codable (insetColor stored as a hex string)

    private enum CodingKeys: String, CodingKey {
        case paddingFraction, insetFraction, insetColorHex, balanceInset, cornerRadiusFraction
        case shadowRadiusFraction, shadowOpacity, fill, ratio
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        paddingFraction = try c.decode(CGFloat.self, forKey: .paddingFraction)
        insetFraction = try c.decode(CGFloat.self, forKey: .insetFraction)
        insetColor = NSColor(hexRGBA: try c.decode(String.self, forKey: .insetColorHex)) ?? .white
        balanceInset = try c.decodeIfPresent(Bool.self, forKey: .balanceInset) ?? false
        cornerRadiusFraction = try c.decode(CGFloat.self, forKey: .cornerRadiusFraction)
        shadowRadiusFraction = try c.decode(CGFloat.self, forKey: .shadowRadiusFraction)
        shadowOpacity = try c.decode(CGFloat.self, forKey: .shadowOpacity)
        fill = try c.decode(BackgroundFill.self, forKey: .fill)
        ratio = try c.decode(AspectRatioOption.self, forKey: .ratio)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(paddingFraction, forKey: .paddingFraction)
        try c.encode(insetFraction, forKey: .insetFraction)
        try c.encode(insetColor.hexRGBA, forKey: .insetColorHex)
        try c.encode(balanceInset, forKey: .balanceInset)
        try c.encode(cornerRadiusFraction, forKey: .cornerRadiusFraction)
        try c.encode(shadowRadiusFraction, forKey: .shadowRadiusFraction)
        try c.encode(shadowOpacity, forKey: .shadowOpacity)
        try c.encode(fill, forKey: .fill)
        try c.encode(ratio, forKey: .ratio)
    }
}

/// A named, persisted beautify preset.
struct BeautyPreset: Codable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var style: BackgroundStyle
}

extension AspectRatioOption: Codable {}

extension NSColor {
    /// "#RRGGBBAA" in sRGB.
    var hexRGBA: String {
        let c = usingColorSpace(.sRGB) ?? self
        let r = Int((c.redComponent * 255).rounded())
        let g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        let a = Int((c.alphaComponent * 255).rounded())
        return String(format: "#%02X%02X%02X%02X", r, g, b, a)
    }

    convenience init?(hexRGBA: String) {
        var s = hexRGBA
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 8, let v = UInt32(s, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((v >> 24) & 0xFF) / 255,
                  green: CGFloat((v >> 16) & 0xFF) / 255,
                  blue: CGFloat((v >> 8) & 0xFF) / 255,
                  alpha: CGFloat(v & 0xFF) / 255)
    }
}
