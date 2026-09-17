//
//  GradientPresets.swift
//  Screenish
//
//  Named gradient backgrounds for the beautify panel.
//

import AppKit

struct GradientPreset: Identifiable, Equatable, Hashable, Codable {
    let id: String
    let colors: [NSColor]
    let angle: Double   // degrees, 0 = left→right

    static func == (lhs: GradientPreset, rhs: GradientPreset) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    // Persist by id only; rehydrate colors/angle from the preset table.
    init(id: String, colors: [NSColor], angle: Double) {
        self.id = id; self.colors = colors; self.angle = angle
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let id = try c.decode(String.self)
        self = GradientPresets.all.first { $0.id == id } ?? GradientPresets.all[0]
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(id)
    }
}

enum GradientPresets {
    static let all: [GradientPreset] = [
        GradientPreset(id: "Sunset",
                       colors: [rgb(0xFF7E5F), rgb(0xFEB47B)], angle: 45),
        GradientPreset(id: "Ocean",
                       colors: [rgb(0x2193B0), rgb(0x6DD5ED)], angle: 45),
        GradientPreset(id: "Berry",
                       colors: [rgb(0x8E2DE2), rgb(0x4A00E0)], angle: 45),
        GradientPreset(id: "Forest",
                       colors: [rgb(0x11998E), rgb(0x38EF7D)], angle: 45),
        GradientPreset(id: "Candy",
                       colors: [rgb(0xFF6FD8), rgb(0x3813C2)], angle: 45),
        GradientPreset(id: "Slate",
                       colors: [rgb(0x434343), rgb(0x000000)], angle: 45),
    ]

    private static func rgb(_ hex: Int) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1)
    }
}
