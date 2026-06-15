//
//  InspectorPanel.swift
//  Screenish
//
//  Right-hand beautify panel: padding, background fill, corner radius, shadow,
//  and aspect ratio. Bound to document.background; off by default.
//

import SwiftUI

struct InspectorPanel: View {
    @ObservedObject var document: EditorDocument

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Background")
                    .font(.headline)

                backgroundPicker
                slider("Padding", value: paddingBinding, range: 0...0.25)
                insetRow
                slider("Corner Radius", value: cornerBinding, range: 0...0.2)
                slider("Shadow", value: shadowBinding, range: 0...0.8)
                ratioPicker
            }
            .padding(14)
        }
        .frame(width: 220)
    }

    // MARK: - Background fill

    private var backgroundPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Fill").font(.subheadline).foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                      spacing: 8) {
                noneSwatch
                ForEach(GradientPresets.all) { preset in
                    gradientSwatch(preset)
                }
            }
            HStack {
                Text("Solid")
                Spacer()
                ColorPicker("", selection: solidColorBinding).labelsHidden()
            }
        }
    }

    private var noneSwatch: some View {
        Button {
            document.beginInteraction()
            document.background.fill = .none
        } label: {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isNone ? Color.accentColor : Color.secondary.opacity(0.4),
                              lineWidth: isNone ? 2 : 1)
                .background(Image(systemName: "nosign").foregroundStyle(.secondary))
                .frame(height: 28)
        }
        .buttonStyle(.plain)
        .help(String(localized: "No background"))
    }

    private func gradientSwatch(_ preset: GradientPreset) -> some View {
        Button {
            document.beginInteraction()
            document.background.fill = .gradient(preset)
        } label: {
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(colors: preset.colors.map { Color(nsColor: $0) },
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(height: 28)
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.accentColor,
                                  lineWidth: isGradient(preset) ? 2 : 0))
        }
        .buttonStyle(.plain)
        .help(preset.id)
    }

    private var ratioPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Aspect Ratio").font(.subheadline).foregroundStyle(.secondary)
            Picker("", selection: ratioBinding) {
                ForEach(AspectRatioOption.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private var insetRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Inset").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                ColorPicker("", selection: insetColorBinding).labelsHidden()
            }
            Slider(value: insetBinding, in: 0...0.06) { editing in
                if editing { document.beginInteraction() }
            }
        }
    }

    // MARK: - Slider helper

    private func slider(_ title: LocalizedStringKey, value: Binding<Double>,
                        range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Slider(value: value, in: range) { editing in
                if editing { document.beginInteraction() }
            }
        }
    }

    // MARK: - Bindings

    private var isNone: Bool { document.background.fill == .none }
    private func isGradient(_ preset: GradientPreset) -> Bool {
        document.background.fill == .gradient(preset)
    }

    private var paddingBinding: Binding<Double> {
        Binding(get: { Double(document.background.paddingFraction) },
                set: { document.background.paddingFraction = CGFloat($0) })
    }
    private var insetBinding: Binding<Double> {
        Binding(get: { Double(document.background.insetFraction) },
                set: { document.background.insetFraction = CGFloat($0) })
    }
    private var insetColorBinding: Binding<Color> {
        Binding(get: { Color(nsColor: document.background.insetColor) },
                set: { document.beginInteraction(); document.background.insetColor = NSColor($0) })
    }
    private var cornerBinding: Binding<Double> {
        Binding(get: { Double(document.background.cornerRadiusFraction) },
                set: { document.background.cornerRadiusFraction = CGFloat($0) })
    }
    private var shadowBinding: Binding<Double> {
        Binding(get: { Double(document.background.shadowOpacity) },
                set: { document.background.shadowOpacity = CGFloat($0) })
    }
    private var ratioBinding: Binding<AspectRatioOption> {
        Binding(get: { document.background.ratio },
                set: { document.beginInteraction(); document.background.ratio = $0 })
    }
    private var solidColorBinding: Binding<Color> {
        Binding(
            get: {
                if case let .solid(color) = document.background.fill {
                    return Color(nsColor: color)
                }
                return .white
            },
            set: {
                document.beginInteraction()
                document.background.fill = .solid(NSColor($0))
            })
    }
}
