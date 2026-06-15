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

    /// Register defaults that differ from the zero value (hideAtLaunch is on).
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            hideAtLaunchKey: true,
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

    /// The export format implied by the compress-to-JPG preference.
    static var format: ImageFormat {
        ImageFormat.preferred(jpeg: compressJPEG)
    }
}
