//
//  ShotStore.swift
//  Screenish
//
//  Owns the live set of Shots shown in the floating Stack and the
//  lifecycle of their temp files. Shots persist until manually dismissed;
//  temp files are cleaned up on quit.
//

import AppKit
import Combine

@MainActor
final class ShotStore: ObservableObject {
    /// Newest first.
    @Published private(set) var shots: [Shot] = []

    /// Capture → Stack. The in-memory rendered composite is authoritative, so the
    /// shot is built and shown synchronously; the PNG is encoded + written to its
    /// deterministic temp URL off-main. Returns the created Shot.
    @discardableResult
    func add(_ capturedImage: CGImage) -> Shot? {
        let id = UUID()
        let background = Prefs.defaultBackground   // remembered beautify
        let rendered = background.isEmpty ? capturedImage
            : (EditorRenderer.renderComposite(base: capturedImage, annotations: [],
                                              cropRect: nil, background: background) ?? capturedImage)
        let thumbnail = ImageExport.thumbnail(rendered)
        let url = ImageExport.tempURL(for: id)
        let shot = Shot(id: id, baseImage: capturedImage, background: background,
                        cgImage: rendered, thumbnail: thumbnail, tempURL: url)
        shots.insert(shot, at: 0)
        Self.writeTempOffMain(rendered, to: url)
        return shot
    }

    /// Apply edited annotations/crop to a Shot non-destructively: keep the original
    /// `baseImage`, store the layers, and cache a freshly rendered composite. Keeps
    /// id/position/timestamp and bumps `revision` so the Stack updates live.
    /// Returns the rendered composite.
    @discardableResult
    func applyEdits(_ shot: Shot, annotations: [Annotation], cropRect: CGRect?,
                    background: BackgroundStyle) -> CGImage? {
        guard let idx = shots.firstIndex(where: { $0.id == shot.id }) else { return nil }
        let base = shot.baseImage
        let rendered = EditorRenderer.renderComposite(base: base, annotations: annotations,
                                                      cropRect: cropRect,
                                                      background: background) ?? base
        let thumbnail = ImageExport.thumbnail(rendered)
        let url = ImageExport.tempURL(for: shot.id)
        shots[idx] = Shot(id: shot.id, baseImage: base, annotations: annotations,
                          cropRect: cropRect, background: background, cgImage: rendered,
                          thumbnail: thumbnail, tempURL: url, createdAt: shot.createdAt,
                          revision: shot.revision + 1)
        Self.writeTempOffMain(rendered, to: url)
        return rendered
    }

    /// PNG-encode + write a composite to its temp URL off the main actor. The
    /// in-memory `cgImage` is authoritative, so failures are logged, not surfaced.
    /// CGImage isn't Sendable but is immutable and safe to read off-main, so it's
    /// passed through a minimal `@unchecked Sendable` box.
    private static func writeTempOffMain(_ cgImage: CGImage, to url: URL) {
        struct Box: @unchecked Sendable { let image: CGImage }
        let box = Box(image: cgImage)
        Task.detached(priority: .utility) {
            guard let data = ImageExport.encode(box.image, as: .png) else {
                NSLog("Screenish: failed to encode temp shot at \(url.lastPathComponent)")
                return
            }
            do {
                try data.write(to: url)
            } catch {
                NSLog("Screenish: failed to write temp shot: \(error)")
            }
        }
    }

    func remove(_ shot: Shot) {
        try? FileManager.default.removeItem(at: shot.tempURL)
        shots.removeAll { $0.id == shot.id }
    }

    func clearAll() {
        for shot in shots {
            try? FileManager.default.removeItem(at: shot.tempURL)
        }
        shots.removeAll()
    }

    /// Remove the entire temp directory; call on app termination.
    func cleanupTempDirectory() {
        try? FileManager.default.removeItem(at: ImageExport.tempDirectory)
    }
}
