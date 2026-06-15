//
//  AppLanguage.swift
//  Screenish
//
//  Per-app language override. macOS reads the `AppleLanguages` default at
//  launch, so changing language requires relaunching the app.
//

import AppKit

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case swedish = "sv"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system:  return String(localized: "System")
        case .english: return "English"
        case .swedish: return "Svenska"
        }
    }

    /// The language currently configured for this app.
    static var current: AppLanguage {
        guard let langs = UserDefaults.standard.stringArray(forKey: "AppleLanguages"),
              let first = langs.first else { return .system }
        if first.hasPrefix("sv") { return .swedish }
        if first.hasPrefix("en") { return .english }
        return .system
    }

    /// Apply the choice to UserDefaults. Takes effect on next launch.
    func apply() {
        let defaults = UserDefaults.standard
        switch self {
        case .system:
            defaults.removeObject(forKey: "AppleLanguages")
        case .english, .swedish:
            defaults.set([rawValue], forKey: "AppleLanguages")
        }
    }
}

enum AppRelauncher {
    static func relaunch() {
        let url = Bundle.main.bundleURL
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
