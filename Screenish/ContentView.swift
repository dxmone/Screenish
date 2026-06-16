//
//  ContentView.swift
//  Screenish
//
//  The tray menu shown from the MenuBarExtra.
//

import SwiftUI
import KeyboardShortcuts

struct MenuContent: View {
    private let coordinator = AppCoordinator.shared

    var body: some View {
        Button("Capture Area") { coordinator.run(.region) }
            .keyboardShortcut("1", modifiers: [.control, .shift])
        Button("Capture Window") { coordinator.run(.window) }
            .keyboardShortcut("2", modifiers: [.control, .shift])
        Button("Capture Full Screen") { coordinator.run(.screen) }
            .keyboardShortcut("3", modifiers: [.control, .shift])

        Divider()

        Button("Settings…") { SettingsWindow.open() }
            .keyboardShortcut(",", modifiers: .command)

        Button("Quit Screenish") { NSApp.terminate(nil) }
            .keyboardShortcut("q", modifiers: .command)
    }
}
