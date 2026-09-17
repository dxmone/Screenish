//
//  CapturePermission.swift
//  Screenish
//
//  Screen Recording (TCC) permission check + prompt for ScreenCaptureKit.
//

import AppKit
import CoreGraphics

enum CapturePermission {
    /// True if Screen Recording access is already granted.
    static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Triggers the system Screen Recording prompt the first time. Returns
    /// whether access is granted right now (the prompt itself is async to grant).
    @discardableResult
    static func request() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    /// Open System Settings at the Screen Recording pane.
    static func openSettings() {
        let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }
}
