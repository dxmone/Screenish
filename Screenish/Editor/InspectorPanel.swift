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

    @State private var presets: [BeautyPreset] = Prefs.savedPresets
    @State private var showingSaveDialog = false
    @State private var newPresetName = ""
    @State private var selectedPresetID: BeautyPreset.ID?
    @State private var defaultPresetID: BeautyPreset.ID? = Prefs.defaultPresetID

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Background")
                    .font(.headline)

                presetRow
                paddingRow
                insetSection
                slider("Corner Radius", value: cornerBinding, range: 0...0.2)
                slider("Shadow", value: shadowBinding, range: 0...0.8)
                backgroundPicker
                ratioPicker
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .frame(width: 248)
        .alert("Save preset", isPresented: $showingSaveDialog) {
            TextField("Preset name", text: $newPresetName)
            Button("Save") { savePreset() }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear(perform: matchSelectedPreset)
    }

    /// Show the active preset's name when the shot opened with a style that matches
    /// a saved preset (e.g. a new capture using the pinned default preset).
    private func matchSelectedPreset() {
        guard selectedPresetID == nil else { return }
        if let id = defaultPresetID, presets.first(where: { $0.id == id })?.style == document.background {
            selectedPresetID = id
        } else if let match = presets.first(where: { $0.style == document.background }) {
            selectedPresetID = match.id
        }
    }

    // MARK: - Presets

    private var presetRow: some View {
        HStack {
            Text("Preset").font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Menu {
                if presets.isEmpty {
                    Text("No saved presets").disabled(true)
                } else {
                    ForEach(presets) { preset in
                        Button {
                            applyPreset(preset)
                        } label: {
                            // Active preset gets a check; the pinned default a star.
                            let icon = preset.id == defaultPresetID ? "star.fill"
                                : (preset.id == selectedPresetID ? "checkmark" : "")
                            Label(preset.name, systemImage: icon)
                        }
                    }
                    Menu("Set as default") {
                        ForEach(presets) { preset in
                            Button(preset.name) { setDefaultPreset(preset) }
                        }
                        if defaultPresetID != nil {
                            Divider()
                            Button("None") { clearDefaultPreset() }
                        }
                    }
                    Menu("Delete") {
                        ForEach(presets) { preset in
                            Button(preset.name, role: .destructive) { deletePreset(preset) }
                        }
                    }
                }
                Divider()
                Button("Save current…") { newPresetName = ""; showingSaveDialog = true }
            } label: {
                Text(selectedPresetName)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(width: 130)
        }
    }

    /// Name shown on the preset button — the active preset, or a placeholder.
    private var selectedPresetName: String {
        presets.first { $0.id == selectedPresetID }?.name ?? String(localized: "Preset")
    }

    private func applyPreset(_ preset: BeautyPreset) {
        document.beginInteraction()
        document.background = preset.style
        selectedPresetID = preset.id
    }

    private func savePreset() {
        let name = newPresetName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let preset = BeautyPreset(name: name, style: document.background)
        var list = Prefs.savedPresets
        list.append(preset)
        Prefs.savedPresets = list
        presets = list
        selectedPresetID = preset.id   // a just-saved preset is the active one
    }

    private func deletePreset(_ preset: BeautyPreset) {
        var list = Prefs.savedPresets
        list.removeAll { $0.id == preset.id }
        Prefs.savedPresets = list
        presets = list
        if selectedPresetID == preset.id { selectedPresetID = nil }
        if defaultPresetID == preset.id { clearDefaultPreset() }
    }

    private func setDefaultPreset(_ preset: BeautyPreset) {
        Prefs.defaultPresetID = preset.id
        defaultPresetID = preset.id
    }

    private func clearDefaultPreset() {
        Prefs.defaultPresetID = nil
        defaultPresetID = nil
    }

    // MARK: - Inset

    private var insetSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            slider("Inset", value: insetBinding, range: 0...0.06)
            HStack {
                Toggle("Balance", isOn: balanceBinding)
                    .toggleStyle(.checkbox)
                Spacer()
                if !document.background.balanceInset {
                    ColorPicker("", selection: insetColorBinding).labelsHidden()
                }
            }
        }
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
                ForEach(AspectRatioOption.basic) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Menu {
                ForEach(AspectRatioOption.social) { option in
                    Button(option.label) { ratioBinding.wrappedValue = option }
                }
            } label: {
                Label(socialMenuLabel, systemImage: "rectangle.portrait.on.rectangle.portrait")
            }
        }
    }

    private var socialMenuLabel: String {
        AspectRatioOption.social.contains(document.background.ratio)
            ? document.background.ratio.label : String(localized: "Social size")
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
    private var insetBinding: Binding<Double> {
        Binding(get: { Double(document.background.insetFraction) },
                set: { document.background.insetFraction = CGFloat($0) })
    }
    private var insetColorBinding: Binding<Color> {
        Binding(get: { Color(nsColor: document.background.insetColor) },
                set: { document.beginInteraction(); document.background.insetColor = NSColor($0) })
    }
    private var balanceBinding: Binding<Bool> {
        Binding(get: { document.background.balanceInset },
                set: { document.beginInteraction(); document.background.balanceInset = $0 })
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
