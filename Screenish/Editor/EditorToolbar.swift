//
//  EditorToolbar.swift
//  Screenish
//
//  Top toolbar: tool selection + inline color/thickness + undo/redo/delete.
//

import SwiftUI

struct EditorToolbar: View {
    @ObservedObject var document: EditorDocument

    /// Help text for whatever the pointer is currently over. Shown instantly in
    /// the caption row below — no tooltip delay, no need to select first.
    @State private var hoverHelp: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                ForEach(EditorTool.allCases) { tool in
                    ToolButton(tool: tool, isSelected: document.tool == tool,
                               action: { document.tool = tool },
                               onHover: { setHelp(tool.helpText, $0) })
                }

                Divider().frame(height: 20)

                ColorPicker("", selection: colorBinding)
                    .labelsHidden()
                    .onHover { setHelp(String(localized: "Color"), $0) }
                Stepper(value: lineWidthBinding, in: 1...40, step: 1) {
                    Image(systemName: "lineweight")
                }
                .frame(width: 90)
                .onHover { setHelp(String(localized: "Thickness"), $0) }

                if showArrowStyle {
                    Picker("", selection: arrowStyleBinding) {
                        Image(systemName: "arrow.up.right").tag(ArrowStyle.straight)
                        Image(systemName: "arrow.turn.right.up").tag(ArrowStyle.curved)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 80)
                    .onHover { setHelp(String(localized: "Arrow style"), $0) }
                }

                if showTextSize {
                    Stepper(value: fontSizeBinding, in: 8...200, step: 2) {
                        Image(systemName: "textformat.size")
                    }
                    .frame(width: 90)
                    .onHover { setHelp(String(localized: "Text size"), $0) }
                }

                Divider().frame(height: 20)

                Button { document.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(!document.canUndo)
                    .onHover { setHelp(String(localized: "Undo"), $0) }
                Button { document.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                    .disabled(!document.canRedo)
                    .onHover { setHelp(String(localized: "Redo"), $0) }
                Button { document.deleteSelected() } label: { Image(systemName: "trash") }
                    .disabled(document.selectionID == nil)
                    .onHover { setHelp(String(localized: "Delete selected"), $0) }
                Button { document.clearAnnotations() } label: { Image(systemName: "trash.slash") }
                    .disabled(document.annotations.isEmpty)
                    .onHover { setHelp(String(localized: "Clear all edits"), $0) }
            }

            Text(hoverHelp ?? document.tool.helpText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func setHelp(_ text: String, _ hovering: Bool) {
        if hovering { hoverHelp = text }
        else if hoverHelp == text { hoverHelp = nil }
    }

    private struct ToolButton: View {
        let tool: EditorTool
        let isSelected: Bool
        let action: () -> Void
        let onHover: (Bool) -> Void

        var body: some View {
            Button(action: action) {
                Image(systemName: tool.systemImage)
                    .frame(width: 22, height: 18)
            }
            .buttonStyle(.bordered)
            .background(isSelected ? Color.accentColor.opacity(0.30) : Color.clear)
            .cornerRadius(6)
            .onHover(perform: onHover)
        }
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: document.style.color) },
            set: { document.style.color = NSColor($0); document.applyStyleToSelection() }
        )
    }

    private var lineWidthBinding: Binding<Double> {
        Binding(
            get: { Double(document.style.lineWidth) },
            set: { document.style.lineWidth = CGFloat($0); document.applyStyleToSelection() }
        )
    }

    /// Show the arrow-style picker when the arrow tool or an arrow is selected.
    private var showArrowStyle: Bool {
        document.tool == .arrow || document.selected?.kind == .arrow
    }

    private var arrowStyleBinding: Binding<ArrowStyle> {
        Binding(
            get: { document.selected?.style.arrowStyle ?? document.style.arrowStyle },
            set: { document.style.arrowStyle = $0; document.applyStyleToSelection() }
        )
    }

    /// Show the text-size control for the text tool or a selected text annotation.
    private var showTextSize: Bool {
        document.tool == .text || document.selected?.kind == .text
    }

    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { Double(document.selected?.style.fontSize ?? document.style.fontSize) },
            set: { document.style.fontSize = CGFloat($0); document.applyStyleToSelection() }
        )
    }
}
