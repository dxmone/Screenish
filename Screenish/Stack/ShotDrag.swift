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
    /// Drag scratch lives in Caches, not the volatile /var/folders temp reaper, so a
    /// dragged file's path keeps resolving for the whole session — path-referencing
    /// targets like Terminal read the file after the drag ends. Swept at next launch.
    static let dragDirectory: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? ImageExport.tempDirectory
        let dir = caches
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "Screenish", isDirectory: true)
            .appendingPathComponent("drag", isDirectory: true)
        // Owner-only (0700): the drag scratch holds user screenshots, so keep others off it.
        try? FileManager.default.createDirectory(
            at: dir, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        return dir
    }()

    /// Purge drag copies left by previous sessions. Drag copies outlive their drag
    /// (so path-referencing targets like Terminal can read them afterwards), so they
    /// accumulate until swept here at launch. Keeps the directory for subsequent writes.
    static func sweepDragDirectory() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: dragDirectory, includingPropertiesForKeys: nil) else { return }
        for url in entries {
            try? fm.removeItem(at: url)
        }
    }

    /// Write the drag file owner-only (0600) — it is a transient copy of the user's
    /// screenshot living in the app cache directory.
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
