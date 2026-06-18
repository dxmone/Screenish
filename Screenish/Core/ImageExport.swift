//
//  ImageExport.swift
//  Screenish
//
//  Encodes a CGImage to PNG/JPG, owns the temp directory, and builds
//  user-facing file names like "Screenish 2026-06-15 kl 14.32.png".
//

import AppKit
import UniformTypeIdentifiers

enum ImageFormat {
    case png
    case jpeg(quality: CGFloat)

    var ext: String {
        switch self {
        case .png: return "png"
        case .jpeg: return "jpg"
        }
    }

    var utType: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        }
    }

    /// The export format implied by the user's "compress to JPG" preference.
    static func preferred(jpeg: Bool) -> ImageFormat {
        jpeg ? .jpeg(quality: 0.8) : .png
    }
}

enum ImageExport {

    /// Per-launch temp directory holding shots until saved, dragged out, or quit.
    static let tempDirectory: URL = {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Screenish", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Downsample a composite into a small thumbnail for the Stack card. The long
    /// side is capped at `maxLongSide` (≈ card width × max screen scale) so the card
    /// uploads a tiny GPU texture instead of the full multi-MB composite. Falls back
    /// to the original image if a context can't be made.
    static func thumbnail(_ cgImage: CGImage, maxLongSide: CGFloat = 360) -> CGImage {
        let w = CGFloat(cgImage.width), h = CGFloat(cgImage.height)
        let longSide = max(w, h, 1)
        guard longSide > maxLongSide else { return cgImage }   // already small enough
        let scale = maxLongSide / longSide
        let tw = max(Int((w * scale).rounded()), 1)
        let th = max(Int((h * scale).rounded()), 1)

        let colorSpace = cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: tw, height: th, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return cgImage }
        ctx.interpolationQuality = .high
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: tw, height: th))
        return ctx.makeImage() ?? cgImage
    }

    /// Encode a CGImage to PNG or JPEG data.
    static func encode(_ cgImage: CGImage, as format: ImageFormat) -> Data? {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        switch format {
        case .png:
            return rep.representation(using: .png, properties: [:])
        case .jpeg(let quality):
            return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
        }
    }

    /// Always write a PNG to temp (full fidelity); format choice applies on save/drag.
    @discardableResult
    static func writeTemp(_ cgImage: CGImage, id: UUID) throws -> URL {
        let url = tempDirectory.appendingPathComponent("\(id.uuidString).png")
        guard let data = encode(cgImage, as: .png) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url)
        return url
    }

    /// Write a CGImage to a directory using the user-facing name + format.
    @discardableResult
    static func write(_ cgImage: CGImage, to directory: URL,
                      format: ImageFormat = Prefs.format, date: Date = Date()) -> URL? {
        let url = directory.appendingPathComponent(fileName(for: date, format: format))
        guard let data = encode(cgImage, as: format) else { return nil }
        do {
            try data.write(to: url)
            return url
        } catch {
            NSLog("Screenish: write failed: \(error)")
            return nil
        }
    }

    /// Base name without extension, e.g. "Screenish 2026-06-15 kl 14.32".
    static func baseName(for date: Date) -> String {
        "Screenish " + nameFormatter.string(from: date)
    }

    static func fileName(for date: Date, format: ImageFormat) -> String {
        baseName(for: date) + "." + format.ext
    }

    private static let nameFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "sv_SE")
        f.dateFormat = "yyyy-MM-dd 'kl' HH.mm"
        return f
    }()
}
