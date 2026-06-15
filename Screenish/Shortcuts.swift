//
//  Shortcuts.swift
//  Screenish
//
//  Global hotkey names. Defaults use Control+Shift+number to avoid clashing
//  with the macOS system screenshot shortcuts (Cmd+Shift+3/4/5).
//

import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let captureRegion = Self("captureRegion",
        default: .init(.one, modifiers: [.control, .shift]))
    static let captureWindow = Self("captureWindow",
        default: .init(.two, modifiers: [.control, .shift]))
    static let captureScreen = Self("captureScreen",
        default: .init(.three, modifiers: [.control, .shift]))
}
