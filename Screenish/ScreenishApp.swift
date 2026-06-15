//
//  ScreenishApp.swift
//  Screenish
//
//  Menu-bar agent: no dock icon, a tray menu with capture commands and
//  Settings. Wires global hotkeys → capture → temp + clipboard + Stack.
//

import SwiftUI
import KeyboardShortcuts

@main
struct ScreenishApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Screenish", systemImage: "camera.viewfinder") {
            MenuContent()
        }
        Settings {
            SettingsView()
        }
    }
}

// MARK: - App lifecycle

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)   // tray only, no dock icon
        Prefs.registerDefaults()
        AppCoordinator.shared.start()

        if !Prefs.hideAtLaunch {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppCoordinator.shared.store.cleanupTempDirectory()
    }
}

// MARK: - Coordinator

/// Single owner of the capture pipeline shared by hotkeys and the tray menu.
@MainActor
final class AppCoordinator {
    static let shared = AppCoordinator()

    let store = ShotStore()
    private let capture = CaptureController()
    private lazy var stack = StackController(store: store)
    private var editors: [Shot.ID: EditorWindowController] = [:]

    private init() {}

    func start() {
        _ = stack   // instantiate the floating panel controller
        KeyboardShortcuts.onKeyUp(for: .captureRegion) { [weak self] in self?.run(.region) }
        KeyboardShortcuts.onKeyUp(for: .captureWindow) { [weak self] in self?.run(.window) }
        KeyboardShortcuts.onKeyUp(for: .captureScreen) { [weak self] in self?.run(.screen) }
    }

    func run(_ mode: CaptureMode) {
        Task { @MainActor in
            guard let cgImage = await capture.capture(mode) else { return }
            Pasteboard.copy(cgImage)
            if let shot = store.add(cgImage) {
                openEditor(for: shot)   // editor opens immediately; shot stays in the stack
            }
        }
    }

    /// Open (or focus) the annotation editor for a Shot.
    func openEditor(for shot: Shot) {
        if let existing = editors[shot.id] {
            existing.show()
            return
        }
        let controller = EditorWindowController(shot: shot) { [weak self] annotations, cropRect, background in
            guard let self else { return }
            if let rendered = self.store.applyEdits(shot, annotations: annotations,
                                                    cropRect: cropRect, background: background) {
                Pasteboard.copy(rendered)
            }
        }
        controller.onClosed = { [weak self] in self?.editors[shot.id] = nil }
        editors[shot.id] = controller
        controller.show()
    }
}
