//
//  Pasteboard.swift
//  Screenish
//
//  Copies a captured image to the general pasteboard at full quality.
//

import AppKit

enum Pasteboard {
    static func copy(_ cgImage: CGImage) {
        let image = NSImage(cgImage: cgImage,
                            size: CGSize(width: cgImage.width, height: cgImage.height))
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
    }
}
