//
//  Preferences.swift
//  Screenish
//
//  Centralized access to user preferences stored in UserDefaults.
//  Views bind via @AppStorage using the same keys; non-view code reads here.
//

import Foundation

enum Prefs {
    static let saveLocationKey = "saveLocationPath"
    static let hideAtLaunchKey = "hideAtLaunch"
    static let compressJPEGKey = "compressJPEG"
    static let launchAtLoginKey = "launchAtLogin"
    static let removeAfterDragKey = "removeAfterDrag"
    static let openEditorAfterCaptureKey = "openEditorAfterCapture"
    static let defaultBackgroundKey = "defaultBackgroundStyle"
    static let savedPresetsKey = "beautyPresets"
    static let defaultPresetKey = "defaultPresetID"

    /// Register defaults that differ from the zero value (hideAtLaunch is on).
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            hideAtLaunchKey: true,
            openEditorAfterCaptureKey: true,
            // Make AppKit tooltips appear almost instantly (ms).
            "NSInitialToolTipDelay": 250,
        ])
    }

    static var defaultSaveDirectory: URL {
        FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
    }

    static var saveLocation: URL {
        if let path = UserDefaults.standard.string(forKey: saveLocationKey), !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return defaultSaveDirectory
    }

    static var compressJPEG: Bool {
        UserDefaults.standard.bool(forKey: compressJPEGKey)
    }

    static var hideAtLaunch: Bool {
        UserDefaults.standard.bool(forKey: hideAtLaunchKey)
    }

    static var removeAfterDrag: Bool {
        UserDefaults.standard.bool(forKey: removeAfterDragKey)
    }

    static var openEditorAfterCapture: Bool {
        UserDefaults.standard.bool(forKey: openEditorAfterCaptureKey)
    }

    /// Last-used beautify style, updated on each edit (Done). First run is a gentle
    /// gradient with a little padding.
    static var lastUsedBackground: BackgroundStyle {
        get {
            guard let data = UserDefaults.standard.data(forKey: defaultBackgroundKey),
                  let style = try? JSONDecoder().decode(BackgroundStyle.self, from: data)
            else {
                var style = BackgroundStyle()
                if let preset = GradientPresets.all.first { style.fill = .gradient(preset) }
                style.paddingFraction = 0.06
                style.cornerRadiusFraction = 0.03
                return style
            }
            return style
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: defaultBackgroundKey)
            }
        }
    }

    /// A pinned default preset, if the user set one. Overrides last-used for new captures.
    static var defaultPresetID: UUID? {
        get { UserDefaults.standard.string(forKey: defaultPresetKey).flatMap(UUID.init) }
        set { UserDefaults.standard.set(newValue?.uuidString, forKey: defaultPresetKey) }
    }

    /// Beautify applied to a new capture: the pinned default preset if set (and it
    /// still exists), otherwise the last-used style.
    static var defaultBackground: BackgroundStyle {
        if let id = defaultPresetID, let preset = savedPresets.first(where: { $0.id == id }) {
            return preset.style
        }
        return lastUsedBackground
    }

    /// Named beautify presets the user has saved.
    static var savedPresets: [BeautyPreset] {
        get {
            guard let data = UserDefaults.standard.data(forKey: savedPresetsKey),
                  let presets = try? JSONDecoder().decode([BeautyPreset].self, from: data)
            else { return [] }
            return presets
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: savedPresetsKey)
            }
        }
    }

    /// The export format implied by the compress-to-JPG preference.
    static var format: ImageFormat {
        ImageFormat.preferred(jpeg: compressJPEG)
    }
}
