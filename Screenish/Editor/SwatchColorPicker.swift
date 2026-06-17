//
//  SwatchColorPicker.swift
//  Screenish
//
//  In-app color control for the editor toolbar. Replaces SwiftUI `ColorPicker`,
//  which bridges to the shared `NSColorPanel` — a separate OS window that floats
//  at the wrong spot and outlives the editor. This control is a swatch button
//  whose popover is anchored to the toolbar, with preset swatches plus in-app
//  RGBA sliders. No `NSColorPanel` is ever summoned.
//

import SwiftUI

struct SwatchColorPicker: View {
    @Binding var color: Color
    @State private var showPopover = false

    var body: some View {
        Button { showPopover.toggle() } label: {
            RoundedRectangle(cornerRadius: 4)
                .fill(color)
                .frame(width: 22, height: 18)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.secondary, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            ColorPopover(color: $color)
        }
    }
}

private struct ColorPopover: View {
    @Binding var color: Color
    @Environment(\.dismiss) private var dismiss

    /// 2 rows × 6 — annotation-friendly palette.
    private static let presets: [Color] = [
        .red, .orange, .yellow, .green, .mint, .blue,
        .purple, .pink, .black, .white, .gray, .brown,
    ]
    private static let columns = Array(repeating: GridItem(.fixed(24), spacing: 8), count: 6)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: Self.columns, spacing: 8) {
                ForEach(Self.presets.indices, id: \.self) { i in
                    let preset = Self.presets[i]
                    Button {
                        color = preset
                        dismiss()
                    } label: {
                        Circle()
                            .fill(preset)
                            .frame(width: 22, height: 22)
                            .overlay(Circle().strokeBorder(.secondary.opacity(0.5), lineWidth: 1))
                            .overlay(
                                Circle()
                                    .strokeBorder(.primary, lineWidth: 2)
                                    .padding(-2)
                                    .opacity(matches(preset) ? 1 : 0)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            VStack(spacing: 6) {
                slider("R", rgba.red, tint: .red)
                slider("G", rgba.green, tint: .green)
                slider("B", rgba.blue, tint: .blue)
                slider("A", rgba.alpha, tint: .gray)
            }
        }
        .padding(12)
        .frame(width: 220)
    }

    private func slider(_ label: String, _ value: Binding<Double>, tint: Color) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.caption.monospaced()).frame(width: 12, alignment: .leading)
            Slider(value: value, in: 0...1).tint(tint)
        }
    }

    private func matches(_ preset: Color) -> Bool {
        let a = RGBA(preset), b = RGBA(color)
        let e = 0.01
        return abs(a.red - b.red) < e && abs(a.green - b.green) < e
            && abs(a.blue - b.blue) < e && abs(a.alpha - b.alpha) < e
    }

    /// Bridge `color` <-> sRGB components for the sliders.
    private var rgba: Binding<RGBA> {
        Binding(
            get: { RGBA(color) },
            set: { color = $0.color }
        )
    }
}

/// sRGB component bridge between SwiftUI `Color` and individual sliders.
private struct RGBA {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .black
        red = Double(ns.redComponent)
        green = Double(ns.greenComponent)
        blue = Double(ns.blueComponent)
        alpha = Double(ns.alphaComponent)
    }

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}
