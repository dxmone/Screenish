//
//  SettingsView.swift
//  Screenish
//
//  Tray-accessible settings: save location, launch behavior, JPG compression,
//  and the global capture shortcuts.
//

import SwiftUI
import ServiceManagement
import KeyboardShortcuts

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            ShortcutsSettingsView()
                .tabItem { Label("Shortcuts", systemImage: "command") }
        }
        .frame(width: 460)
        // Accessory apps don't auto-activate, so the Settings window can open
        // behind other apps. Force it front whenever it appears.
        .background(WindowAccessor { window in
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        })
    }
}

/// Opens the SwiftUI Settings scene AND activates the app, so the window lands
/// in front for this menu-bar (accessory) app. `SettingsLink` gives no
/// activation hook, hence the private selector.
enum SettingsWindow {
    static func open() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}

/// Reaches the hosting NSWindow once SwiftUI has attached it.
private struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window { onWindow(window) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

private struct GeneralSettingsView: View {
    @AppStorage(Prefs.saveLocationKey) private var saveLocationPath: String = ""
    @AppStorage(Prefs.hideAtLaunchKey) private var hideAtLaunch: Bool = true
    @AppStorage(Prefs.compressJPEGKey) private var compressJPEG: Bool = false
    @AppStorage(Prefs.launchAtLoginKey) private var launchAtLogin: Bool = false
    @AppStorage(Prefs.removeAfterDragKey) private var removeAfterDrag: Bool = false
    @AppStorage(Prefs.openEditorAfterCaptureKey) private var openEditorAfterCapture: Bool = true

    @State private var language: AppLanguage = .current
    @State private var showRelaunchPrompt = false

    private var displayPath: String {
        saveLocationPath.isEmpty ? Prefs.defaultSaveDirectory.path : saveLocationPath
    }

    var body: some View {
        Form {
            Picker("Language", selection: $language) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(lang.label).tag(lang)
                }
            }
            .onChange(of: language) { _, newValue in
                newValue.apply()
                showRelaunchPrompt = true
            }

            LabeledContent("Save to") {
                HStack {
                    Text(displayPath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Choose…", action: chooseSaveLocation)
                }
            }

            Toggle("Open editor after capture", isOn: $openEditorAfterCapture)
            Toggle("Always hide window at launch", isOn: $hideAtLaunch)
            Toggle("Compress to JPG when saving", isOn: $compressJPEG)
            Toggle("Remove from stack after drag and drop", isOn: $removeAfterDrag)
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    LoginItem.set(enabled)
                }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { launchAtLogin = LoginItem.isEnabled }
        .alert("Restart required", isPresented: $showRelaunchPrompt) {
            Button("Relaunch now") { AppRelauncher.relaunch() }
            Button("Later", role: .cancel) {}
        } message: {
            Text("Restart Screenish to apply the new language.")
        }
    }

    private func chooseSaveLocation() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = Prefs.saveLocation
        if panel.runModal() == .OK, let url = panel.url {
            saveLocationPath = url.path
        }
    }
}

private struct ShortcutsSettingsView: View {
    var body: some View {
        Form {
            KeyboardShortcuts.Recorder(String(localized: "Capture Area"), name: .captureRegion)
            KeyboardShortcuts.Recorder(String(localized: "Capture Window"), name: .captureWindow)
            KeyboardShortcuts.Recorder(String(localized: "Capture Full Screen"), name: .captureScreen)
        }
        .formStyle(.grouped)
        .padding()
    }
}

/// Thin wrapper over SMAppService for the login-item toggle.
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Screenish: login item update failed: \(error)")
        }
    }
}
