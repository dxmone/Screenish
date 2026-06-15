//
//  ShotDrag.swift
//  Screenish
//
//  Builds the drag-out item provider for a Shot. Writes the file lazily with
//  the user-facing name and the format implied by the JPG preference, so the
//  dropped file lands with the right name + extension.
//

import AppKit
import UniformTypeIdentifiers

enum ShotDrag {
    static let dragDirectory: URL = {
        let dir = ImageExport.tempDirectory.appendingPathComponent("drag", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// `onDelivered` fires on the main actor once the drop target has actually
    /// requested (received) the file — the success signal for a completed drag.
    static func itemProvider(for shot: Shot,
                             onDelivered: (@MainActor () -> Void)? = nil) -> NSItemProvider {
        itemProvider(image: shot.cgImage, date: shot.createdAt, onDelivered: onDelivered)
    }

    /// Drag provider for an arbitrary image (e.g. the live editor render).
    static func itemProvider(image cgImage: CGImage, date: Date,
                             onDelivered: (@MainActor () -> Void)? = nil) -> NSItemProvider {
        let format = Prefs.format
        let fileName = ImageExport.fileName(for: date, format: format)

        let provider = NSItemProvider()
        // Suggested name must be WITHOUT extension — the file representation's
        // type adds the extension. Including it here produced "name.jpg.jpeg".
        provider.suggestedName = ImageExport.baseName(for: date)
        provider.registerFileRepresentation(
            forTypeIdentifier: format.utType.identifier,
            fileOptions: [],
            visibility: .all
        ) { completion in
            do {
                guard let data = ImageExport.encode(cgImage, as: format) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                let url = dragDirectory.appendingPathComponent(fileName)
                try data.write(to: url)
                completion(url, false, nil)
                if let onDelivered {
                    Task { @MainActor in onDelivered() }
                }
            } catch {
                completion(nil, false, error)
            }
            return nil
        }
        return provider
    }

    /// Save a shot to a folder with its user-facing name + format. Returns the URL.
    @discardableResult
    static func save(_ shot: Shot, to directory: URL) -> URL? {
        ImageExport.write(shot.cgImage, to: directory, format: Prefs.format, date: shot.createdAt)
    }
}
