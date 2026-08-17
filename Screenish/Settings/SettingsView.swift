//
//  SettingsView.swift
//  Screenish
//
//  Tray-accessible settings: save location, launch behavior, JPG compression,
//  the global capture shortcuts, and an About tab.
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
            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
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
/// in front for this menu-bar (accessory) app. macOS 14 retired the
/// `showSettingsWindow:` selector — it logs "Please use SettingsLink for opening
/// the Settings scene." and does nothing — so we fire the same action the
/// standard App ▸ Settings… menu item carries (the one `SettingsLink` triggers).
/// Activation is handled by `SettingsView`'s `WindowAccessor`.
@MainActor
enum SettingsWindow {
    static func open() {
        NSApp.activate(ignoringOtherApps: true)
        guard let item = settingsMenuItem(), let action = item.action else { return }
        NSApp.sendAction(action, to: item.target, from: item)
    }

    /// The App ▸ Settings… item SwiftUI installs whenever a `Settings` scene exists.
    private static func settingsMenuItem() -> NSMenuItem? {
        NSApp.mainMenu?.items
            .compactMap(\.submenu)
            .flatMap(\.items)
            .first { $0.keyEquivalent == "," && $0.keyEquivalentModifierMask == .command }
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

private struct AboutSettingsView: View {
    private static let repoURL = URL(string: "https://github.com/dxmone/Screenish")!

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        if let build = info?["CFBundleVersion"] as? String, build != short {
            return "\(short) (\(build))"
        }
        return short
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text(verbatim: "Screenish")
                .font(.title2.bold())
            Text("Version \(version)")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Created by Thomas Strömberg with AI coding.")
                .font(.callout)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
            Link("github.com/dxmone/Screenish", destination: Self.repoURL)
                .font(.callout)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal)
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
