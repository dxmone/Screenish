//
//  ScreenishApp.swift
//  Screenish
//
//  Menu-bar agent: no dock icon, a tray menu with capture commands and
//  Settings. Wires global hotkeys → capture → temp + clipboard + Stack.
//

import SwiftUI
import OSLog
import UserNotifications
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
        Log.installCrashHandlers()
        NSApp.setActivationPolicy(.accessory)   // tray only, no dock icon
        Prefs.registerDefaults()
        AppCoordinator.shared.start()

        if CrashReporter.lastSessionCrashed {
            notifyPreviousCrash()
        }
        if !Prefs.hideAtLaunch {
            // Defer one runloop tick: SwiftUI installs the main menu (which holds
            // the Settings… item we trigger) right after launch finishes.
            DispatchQueue.main.async { SettingsWindow.open() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        CrashReporter.markCleanShutdown()
        AppCoordinator.shared.store.cleanupTempDirectory()
    }

    // MARK: - Crash notification

    /// The previous session died without a clean shutdown. Tell the user so they
    /// can grab the report; tapping it reveals the crash-log folder. If notifs are
    /// unavailable, the tray menu's "Reveal Crash Logs" is the guaranteed path.
    private func notifyPreviousCrash() {
        let center = UNUserNotificationCenter.current()
        center.delegate = AppDelegate.notificationDelegate
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Screenish crashed last session")
            content.body = String(localized: "Click to reveal the crash log so you can share it.")
            let request = UNNotificationRequest(
                identifier: "screenish.crash", content: content, trigger: nil)
            center.add(request)
        }
    }

    static let notificationDelegate = CrashNotificationDelegate()
}

/// Reveals the crash-log folder when the crash notification is tapped, and lets it
/// show even while the app is frontmost.
final class CrashNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
                                @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        CrashReporter.revealInFinder()
        completionHandler()
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
    private var isCapturing = false

    private init() {}

    func start() {
        _ = stack   // instantiate the floating panel controller
        KeyboardShortcuts.onKeyUp(for: .captureRegion) { [weak self] in self?.run(.region) }
        KeyboardShortcuts.onKeyUp(for: .captureWindow) { [weak self] in self?.run(.window) }
        KeyboardShortcuts.onKeyUp(for: .captureScreen) { [weak self] in self?.run(.screen) }
    }

    func run(_ mode: CaptureMode) {
        // Ignore overlapping captures — a second one would replace the shared
        // overlay's continuation and leak the first (hung Task).
        guard !isCapturing else {
            Log.general.log("capture ignored: already capturing")
            return
        }
        isCapturing = true
        Log.breadcrumb("capture begin: \(mode)")
        Task { @MainActor in
            defer { isCapturing = false }
            guard let cgImage = await capture.capture(mode) else {
                Log.breadcrumb("capture end: no image (\(mode))")
                return
            }
            Log.breadcrumb("capture end: got image (\(mode))")
            if let shot = store.add(cgImage) {
                Pasteboard.copy(shot.cgImage)   // rendered (incl. remembered beautify)
                if Prefs.openEditorAfterCapture {
                    openEditor(for: shot)       // else it just sits in the stack
                }
            } else {
                Pasteboard.copy(cgImage)
            }
        }
    }

    /// Discard a shot from the stack and close any editor open for it, so a removed
    /// shot never leaves an orphaned editor window behind. Used by the Stack's
    /// dismiss / remove / drag-out actions.
    func discardShot(_ shot: Shot) {
        editors[shot.id]?.close()   // sync close → windowWillClose → onClosed clears the dict
        store.remove(shot)
    }

    /// Open (or focus) the annotation editor for a Shot.
    func openEditor(for shot: Shot) {
        Log.breadcrumb("openEditor \(shot.id) existing=\(self.editors[shot.id] != nil)")
        if let existing = editors[shot.id] {
            existing.show()
            return
        }
        let controller = EditorWindowController(
            shot: shot,
            onDone: { [weak self] annotations, cropRect, background in
                guard let self else { return }
                Prefs.lastUsedBackground = background   // remember beautify for next captures
                if let rendered = self.store.applyEdits(shot, annotations: annotations,
                                                        cropRect: cropRect, background: background) {
                    Pasteboard.copy(rendered)
                }
            },
            onDragDelivered: { [weak self] in
                self?.store.remove(shot)   // dropped into another app → leave the stack
            },
            onDiscard: { [weak self] in
                self?.store.remove(shot)   // Esc → throw the shot away
            })
        controller.onClosed = { [weak self] in self?.editors[shot.id] = nil }
        editors[shot.id] = controller
        controller.show()
    }
}
