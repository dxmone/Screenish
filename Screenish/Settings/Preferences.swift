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

    /// Remembered beautify style, applied to new captures and updated on each edit.
    /// First run defaults to a gentle gradient with a little padding.
    static var defaultBackground: BackgroundStyle {
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
