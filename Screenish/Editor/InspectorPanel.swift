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

                paddingRow
                slider("Corner Radius", value: cornerBinding, range: 0...0.2)
                slider("Shadow", value: shadowBinding, range: 0...0.8)
                backgroundPicker
                ratioPicker
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .frame(width: 248)
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

    /// A thin, adjustable border so a newly chosen background is visible
    /// without forcing a big default — drag Padding to 0 to remove it.
    private func ensureVisiblePadding() {
        if document.background.paddingFraction == 0 { document.background.paddingFraction = 0.04 }
    }

    private func gradientSwatch(_ preset: GradientPreset) -> some View {
        Button {
            document.beginInteraction()
            document.background.fill = .gradient(preset)
            ensureVisiblePadding()
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

    /// Fine-grained padding slider over a small amount range (no percentage,
    /// gentle increments) with a numeric readout.
    private var paddingRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Padding").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(paddingSliderBinding.wrappedValue.rounded()))")
                    .font(.caption).monospacedDigit().foregroundStyle(.tertiary)
            }
            Slider(value: paddingSliderBinding, in: 0...100) { editing in
                if editing { document.beginInteraction() }
            }
        }
    }

    // MARK: - Slider helper

    private func slider(_ title: LocalizedStringKey, value: Binding<Double>,
                        range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int((value.wrappedValue / range.upperBound * 100).rounded()))%")
                    .font(.caption).foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
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

    /// Unitless 0…100 amount mapped to a small fraction (100 ≈ 0.13 of longest side).
    private var paddingSliderBinding: Binding<Double> {
        Binding(get: { Double(document.background.paddingFraction * 750) },
                set: { document.background.paddingFraction = CGFloat($0) / 750 })
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
}
