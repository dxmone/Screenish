//
//  ShotDrag.swift
//  Screenish
//
//  Shared drag-out scratch directory + folder-save helper for Shots. The drag
//  itself is an AppKit drag source (StackDragSourceView / DragOutHandle) that
//  writes a real file URL — file promises only land in Finder.
//

import AppKit
import UniformTypeIdentifiers

enum ShotDrag {
    static let dragDirectory: URL = {
        let dir = ImageExport.tempDirectory.appendingPathComponent("drag", isDirectory: true)
        // Owner-only (0700): the drag scratch holds user screenshots in a shared
        // temp location, so keep other users off it.
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        return dir
    }()

    /// Purge drag copies orphaned by a previous crash. Each session's copy is
    /// deleted when its drag ends, but a crash mid-drag leaves it behind, so sweep
    /// the directory contents at launch. Keeps the directory for subsequent writes.
    static func sweepDragDirectory() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: dragDirectory, includingPropertiesForKeys: nil) else { return }
        for url in entries {
            try? fm.removeItem(at: url)
        }
    }

    /// Write the drag file owner-only (0600) — it is a transient copy of the user's
    /// screenshot living in a shared temp directory.
    static func writeDragFile(_ data: Data, to url: URL) throws {
        try data.write(to: url)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static let fm = FileManager.default

    /// Save a shot to a folder with its user-facing name + format. Throws so the
    /// caller can alert the user instead of silently reporting success.
    @discardableResult
    static func save(_ shot: Shot, to directory: URL) throws -> URL {
        try ImageExport.write(shot.cgImage, to: directory, format: Prefs.format, date: shot.createdAt)
    }

    /// Modal alert telling the user a save failed — used by every save call site so a
    /// failed write is never reported as success.
    @MainActor
    static func presentSaveError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "Couldn’t save the screenshot")
        alert.informativeText = saveErrorMessage(error)
        alert.runModal()
    }

    private static func saveErrorMessage(_ error: Error) -> String {
        switch error {
        case ImageExportError.encodeFailed:
            return String(localized: "The image couldn’t be encoded.")
        case ImageExportError.writeFailed(let underlying):
            return underlying.localizedDescription
        default:
            return error.localizedDescription
        }
    }
}
