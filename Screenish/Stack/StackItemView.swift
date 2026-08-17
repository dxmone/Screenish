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
        Group {
            if store.shots.count <= StackMetrics.collapseThreshold {
                VStack(spacing: 8) {
                    ForEach(store.shots) { shot in
                        StackItemView(shot: shot, store: store)
                    }
                }
            } else {
                collapsedPile
            }
        }
        .padding(10)
        .frame(width: StackMetrics.cardWidth + 20)
    }

    /// More than `collapseThreshold` shots → pile them with a small peek so the
    /// stack stays compact. Newest is on top and fully visible.
    private var collapsedPile: some View {
        let count = store.shots.count
        let peek = StackMetrics.pilePeek
        return ZStack(alignment: .top) {
            ForEach(Array(store.shots.enumerated()), id: \.element.id) { index, shot in
                StackItemView(shot: shot, store: store)
                    .offset(y: CGFloat(index) * peek)
                    .zIndex(Double(count - index))
            }
        }
        .frame(height: CGFloat(count - 1) * peek + StackMetrics.maxThumbHeight,
               alignment: .top)
    }
}

enum StackMetrics {
    static let cardWidth: CGFloat = 160
    static let maxThumbHeight: CGFloat = 110
    static let collapseThreshold = 5
    static let pilePeek: CGFloat = 28
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
        // Draw the downsampled thumbnail — the full composite would upload a
        // multi-MB GPU texture just to fill a ~160pt card. Drag/copy/editor still
        // use the full-resolution cgImage below.
        Image(nsImage: shot.nsThumbnail)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: thumbSize.width, height: thumbSize.height)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.white.opacity(0.15)))
            .shadow(radius: 6, y: 3)
            // AppKit drag source owns click / hover / right-click and drags a
            // real file URL (works in Electron/chat apps, not just Finder).
            .overlay {
                StackDragSourceView(
                    image: { shot.cgImage },
                    date: shot.createdAt,
                    onTap: { open() },
                    onHoverChange: { hovering = $0 },
                    onSaveToFolder: { saveToFolder() },
                    onCopy: { Pasteboard.copy(shot.cgImage) },
                    onCopyAndRemove: {
                        Pasteboard.copy(shot.cgImage)
                        AppCoordinator.shared.discardShot(shot)
                    },
                    onRemove: { AppCoordinator.shared.discardShot(shot) },
                    onDelivered: { if Prefs.removeAfterDrag { AppCoordinator.shared.discardShot(shot) } }
                )
            }
            // Added last → sits above the drag overlay so its taps win.
            .overlay(alignment: .topTrailing) { dismissButton }
    }

    @ViewBuilder private var dismissButton: some View {
        if hovering {
            Button {
                AppCoordinator.shared.discardShot(shot)
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
        do {
            let url = try ShotDrag.save(shot, to: Prefs.saveLocation)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            ShotDrag.presentSaveError(error)
        }
    }
}
