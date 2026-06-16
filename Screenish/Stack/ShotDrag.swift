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
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Save a shot to a folder with its user-facing name + format. Returns the URL.
    @discardableResult
    static func save(_ shot: Shot, to directory: URL) -> URL? {
        ImageExport.write(shot.cgImage, to: directory, format: Prefs.format, date: shot.createdAt)
    }
}
