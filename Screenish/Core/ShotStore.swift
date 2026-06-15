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

    /// Capture → temp file → Stack. Returns the created Shot, or nil on write failure.
    @discardableResult
    func add(_ capturedImage: CGImage) -> Shot? {
        let id = UUID()
        do {
            let url = try ImageExport.writeTemp(capturedImage, id: id)
            let shot = Shot(id: id, baseImage: capturedImage, cgImage: capturedImage, tempURL: url)
            shots.insert(shot, at: 0)
            return shot
        } catch {
            NSLog("Screenish: failed to write temp shot: \(error)")
            return nil
        }
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
        do {
            let url = try ImageExport.writeTemp(rendered, id: shot.id)
            shots[idx] = Shot(id: shot.id, baseImage: base, annotations: annotations,
                              cropRect: cropRect, background: background, cgImage: rendered,
                              tempURL: url, createdAt: shot.createdAt,
                              revision: shot.revision + 1)
            return rendered
        } catch {
            NSLog("Screenish: failed to update shot: \(error)")
            return nil
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
