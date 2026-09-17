//
//  StackPanel.swift
//  Screenish
//
//  A non-activating floating panel pinned to the bottom-left of the primary
//  screen, hosting the Stack of shots. Shown while shots exist, hidden when empty.
//

import AppKit
import SwiftUI
import Combine

@MainActor
final class StackController {
    private let store: ShotStore
    private let panel: StackPanel
    private var cancellable: AnyCancellable?

    init(store: ShotStore) {
        self.store = store
        self.panel = StackPanel(store: store)
        cancellable = store.$shots
            .receive(on: RunLoop.main)
            .sink { [weak self] shots in
                self?.update(isEmpty: shots.isEmpty)
            }
    }

    private func update(isEmpty: Bool) {
        if isEmpty {
            panel.orderOut(nil)
        } else {
            panel.refreshLayout()
            panel.orderFrontRegardless()
        }
    }
}

final class StackPanel: NSPanel {
    private let hostingView: NSHostingView<AnyView>
    private let margin: CGFloat = 20

    init(store: ShotStore) {
        let root = ScrollView(.vertical, showsIndicators: false) {
            StackView(store: store)
        }
        hostingView = NSHostingView(rootView: AnyView(root))

        super.init(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
                   styleMask: [.nonactivatingPanel, .borderless],
                   backing: .buffered, defer: false)

        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        contentView = hostingView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func refreshLayout() {
        // Always the primary screen (menu-bar screen). NSScreen.main is the screen
        // with the key window, so the stack would follow whatever app has focus.
        guard let screen = NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        let maxHeight = visible.height - margin * 2

        hostingView.layoutSubtreeIfNeeded()
        var size = hostingView.fittingSize
        if size.width <= 0 { size.width = StackMetrics.cardWidth + 20 }
        size.height = min(size.height, maxHeight)

        let origin = CGPoint(x: visible.minX + margin, y: visible.minY + margin)
        setFrame(CGRect(origin: origin, size: size), display: true)
    }
}
