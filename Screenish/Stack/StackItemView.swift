//
//  StackItemView.swift
//  Screenish
//
//  SwiftUI content for the floating Stack: a column of thumbnail cards,
//  newest on top. Each card is a drag source and offers save/copy/dismiss.
//

import SwiftUI

struct StackView: View {
    @ObservedObject var store: ShotStore

    var body: some View {
        VStack(spacing: 8) {
            ForEach(store.shots) { shot in
                StackItemView(shot: shot, store: store)
            }
        }
        .padding(10)
        .frame(width: StackMetrics.cardWidth + 20)
    }
}

enum StackMetrics {
    static let cardWidth: CGFloat = 160
    static let maxThumbHeight: CGFloat = 110
}

struct StackItemView: View {
    let shot: Shot
    @ObservedObject var store: ShotStore
    @State private var hovering = false

    private var thumbSize: CGSize {
        let w = StackMetrics.cardWidth
        let ratio = shot.pixelSize.height / max(shot.pixelSize.width, 1)
        let h = min(w * ratio, StackMetrics.maxThumbHeight)
        return CGSize(width: w, height: h)
    }

    var body: some View {
        Image(nsImage: shot.nsImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: thumbSize.width, height: thumbSize.height)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.15)))
            .shadow(radius: 6, y: 3)
            .overlay(alignment: .topTrailing) { dismissButton }
            .onHover { hovering = $0 }
            .onTapGesture { open() }
            .onDrag {
                ShotDrag.itemProvider(for: shot) {
                    if Prefs.removeAfterDrag { store.remove(shot) }
                }
            } preview: {
                Image(nsImage: shot.nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: thumbSize.width, height: thumbSize.height)
            }
            .contextMenu {
                Button("Save to Folder") { saveToFolder() }
                Button("Copy") { Pasteboard.copy(shot.cgImage) }
                Divider()
                Button("Remove", role: .destructive) { store.remove(shot) }
            }
    }

    @ViewBuilder private var dismissButton: some View {
        if hovering {
            Button {
                store.remove(shot)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white, .black.opacity(0.6))
            }
            .buttonStyle(.plain)
            .padding(4)
        }
    }

    private func open() {
        AppCoordinator.shared.openEditor(for: shot)
    }

    private func saveToFolder() {
        if let url = ShotDrag.save(shot, to: Prefs.saveLocation) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}
