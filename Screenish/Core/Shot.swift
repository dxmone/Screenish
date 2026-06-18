//
//  Shot.swift
//  Screenish
//
//  A Shot is a captured image — the artifact produced by a Capture.
//  Editing is non-destructive: `baseImage` is the original capture, `annotations`
//  + `cropRect` are the editable layers, and `cgImage` is the rendered composite
//  used for display, clipboard, drag-out, and save. `revision` bumps on every
//  edit so SwiftUI re-renders the Stack thumbnail.
//

import AppKit

struct Shot: Identifiable, Hashable {
    let id: UUID
    let baseImage: CGImage        // original capture, never mutated
    var annotations: [Annotation] // editable layers
    var cropRect: CGRect?         // editable crop (image-pixel space)
    var background: BackgroundStyle // editable beautify (padding/bg/radius/shadow/ratio)
    let cgImage: CGImage          // rendered composite (base + annotations + crop + background)
    let thumbnail: CGImage        // small downsampled composite for the Stack card
    let tempURL: URL
    let createdAt: Date
    let revision: Int

    init(id: UUID = UUID(), baseImage: CGImage, annotations: [Annotation] = [],
         cropRect: CGRect? = nil, background: BackgroundStyle = .none,
         cgImage: CGImage, thumbnail: CGImage, tempURL: URL,
         createdAt: Date = Date(), revision: Int = 0) {
        self.id = id
        self.baseImage = baseImage
        self.annotations = annotations
        self.cropRect = cropRect
        self.background = background
        self.cgImage = cgImage
        self.thumbnail = thumbnail
        self.tempURL = tempURL
        self.createdAt = createdAt
        self.revision = revision
    }

    /// Pixel dimensions of the rendered composite.
    var pixelSize: CGSize {
        CGSize(width: cgImage.width, height: cgImage.height)
    }

    /// An `NSImage` sized to the pixel dimensions, for display and clipboard.
    var nsImage: NSImage {
        NSImage(cgImage: cgImage, size: pixelSize)
    }

    /// A small `NSImage` backed by the downsampled `thumbnail`, for the Stack card.
    /// Sized to the composite's aspect ratio so SwiftUI lays it out like `nsImage`.
    var nsThumbnail: NSImage {
        NSImage(cgImage: thumbnail, size: pixelSize)
    }

    // Identity + revision so edits are detected by SwiftUI's view diffing.
    static func == (lhs: Shot, rhs: Shot) -> Bool {
        lhs.id == rhs.id && lhs.revision == rhs.revision
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(revision)
    }
}
