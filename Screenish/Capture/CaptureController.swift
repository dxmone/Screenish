//
//  CaptureController.swift
//  Screenish
//
//  Orchestrates a capture: ensures permission, drives the selection overlay,
//  and grabs pixels via ScreenCaptureKit (SCScreenshotManager).
//

import AppKit
import ScreenCaptureKit

enum CaptureMode { case region, window, screen }

@MainActor
final class CaptureController {
    private let overlay = SelectionOverlayController()

    /// Run a capture for the given mode. Returns nil on cancel/permission denial.
    func capture(_ mode: CaptureMode) async -> CGImage? {
        guard ensurePermission() else { return nil }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true)
        } catch {
            NSLog("Screenish: shareable content error: \(error)")
            return nil
        }

        switch mode {
        case .region:
            let result = await overlay.present(mode: .region)
            guard case let .region(globalRect) = result else { return nil }
            return await captureRegion(globalRect, content: content)
        case .window:
            let result = await overlay.present(mode: .window)
            guard case let .window(id) = result else { return nil }
            return await captureWindow(id, content: content)
        case .screen:
            return await captureScreenUnderCursor(content: content)
        }
    }

    // MARK: - Permission

    private func ensurePermission() -> Bool {
        if CapturePermission.isGranted { return true }
        CapturePermission.request()
        if !CapturePermission.isGranted {
            CapturePermission.openSettings()
            return false
        }
        return true
    }

    // MARK: - Region

    private func captureRegion(_ globalRect: CGRect, content: SCShareableContent) async -> CGImage? {
        guard let screen = screen(containing: CGPoint(x: globalRect.midX, y: globalRect.midY)),
              let display = display(for: screen, in: content),
              let full = await captureDisplay(display, screen: screen, content: content)
        else { return nil }

        // Derive the pixels-per-point scale from the captured image itself, so
        // the crop is correct regardless of the display's backing scale.
        let sx = CGFloat(full.width) / screen.frame.width
        let sy = CGFloat(full.height) / screen.frame.height
        let localX = (globalRect.minX - screen.frame.minX) * sx
        let localYTop = (screen.frame.maxY - globalRect.maxY) * sy   // flip Y to top-left
        let cropRect = CGRect(x: localX.rounded(), y: localYTop.rounded(),
                              width: (globalRect.width * sx).rounded(),
                              height: (globalRect.height * sy).rounded())
            .intersection(CGRect(x: 0, y: 0, width: full.width, height: full.height))
        guard !cropRect.isNull, cropRect.width >= 1, cropRect.height >= 1,
              let cropped = full.cropping(to: cropRect) else { return nil }
        // CGImage.cropping(to:) keeps a reference to the parent's full-display
        // backing store (100+ MB), so detach into a fresh standalone bitmap and
        // drop `full` to release it for the rest of the editing session.
        return detachedCopy(of: cropped) ?? cropped
    }

    /// Copy a CGImage into a freshly allocated bitmap so it no longer references
    /// any parent backing store. Pixel-identical to the input.
    private func detachedCopy(of image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        let colorSpace = image.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: bitmapInfo) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    // MARK: - Window

    private func captureWindow(_ id: CGWindowID, content: SCShareableContent) async -> CGImage? {
        guard let window = content.windows.first(where: { $0.windowID == id }) else { return nil }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let config = SCStreamConfiguration()
        config.width = Int((window.frame.width * scale).rounded())
        config.height = Int((window.frame.height * scale).rounded())
        config.showsCursor = false
        config.ignoreGlobalClipDisplay = true
        let filter = SCContentFilter(desktopIndependentWindow: window)
        return await screenshot(filter: filter, config: config)
    }

    // MARK: - Full screen

    private func captureScreenUnderCursor(content: SCShareableContent) async -> CGImage? {
        let screen = screen(containing: NSEvent.mouseLocation) ?? NSScreen.main
        guard let screen, let display = display(for: screen, in: content) else { return nil }
        return await captureDisplay(display, screen: screen, content: content)
    }

    private func captureDisplay(_ display: SCDisplay, screen: NSScreen,
                                content: SCShareableContent) async -> CGImage? {
        // Use the NSScreen point size × backing scale for native pixels; avoids
        // ambiguity in SCDisplay.width's units across mixed-DPI displays.
        let scale = screen.backingScaleFactor
        let config = SCStreamConfiguration()
        config.width = Int((screen.frame.width * scale).rounded())
        config.height = Int((screen.frame.height * scale).rounded())
        config.showsCursor = false
        // Exclude our own windows (selection overlay dimming, stack panel, editor)
        // so they never end up in the capture.
        let ownApps = content.applications.filter { $0.processID == getpid() }
        let filter = SCContentFilter(display: display,
                                     excludingApplications: ownApps,
                                     exceptingWindows: [])
        return await screenshot(filter: filter, config: config)
    }

    private func screenshot(filter: SCContentFilter, config: SCStreamConfiguration) async -> CGImage? {
        do {
            return try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config)
        } catch {
            NSLog("Screenish: capture failed: \(error)")
            return nil
        }
    }

    // MARK: - Display mapping

    private func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) }
    }

    private func display(for screen: NSScreen, in content: SCShareableContent) -> SCDisplay? {
        guard let number = screen.deviceDescription[
            NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
        let displayID = CGDirectDisplayID(number.uint32Value)
        return content.displays.first { $0.displayID == displayID }
    }
}
