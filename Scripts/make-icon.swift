#!/usr/bin/env swift
// Renders the app icon with Core Graphics into App/Assets.xcassets/AppIcon.appiconset:
// rounded macOS icons at every size, plus a full-bleed, opaque variant for iOS (the system
// applies the rounded mask there).
// Usage: swift Scripts/make-icon.swift   (run from the repository root)
import AppKit
import Foundation

let canvas: CGFloat = 1024

func renderIcon(size: Int, fullBleed: Bool = false) -> Data {
    let px = CGFloat(size)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    cg.scaleBy(x: px / canvas, y: px / canvas)

    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
        CGColor(colorSpace: space, components: [
            CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255,
            CGFloat(hex & 0xFF) / 255, alpha])!
    }

    // macOS icon grid: 824pt rounded square centred on a 1024pt canvas.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath: CGPath
    if fullBleed {
        // iOS: scale the tile up to fill the canvas, square corners, no shadow.
        cg.translateBy(x: 512, y: 512)
        cg.scaleBy(x: canvas / tile.width, y: canvas / tile.height)
        cg.translateBy(x: -512, y: -512)
        tilePath = CGPath(rect: tile, transform: nil)
    } else {
        tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
    }

    // Drop shadow under the tile.
    cg.saveGState()
    if !fullBleed {
        cg.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
    }
    cg.addPath(tilePath)
    cg.setFillColor(color(0xF26B1D))
    cg.fillPath()
    cg.restoreGState()

    // Warm orange gradient background.
    cg.saveGState()
    cg.addPath(tilePath)
    cg.clip()
    let bg = CGGradient(colorsSpace: space,
                        colors: [color(0xFFB347), color(0xFF7A2F), color(0xE8461E)] as CFArray,
                        locations: [0, 0.55, 1])!
    cg.drawLinearGradient(bg, start: CGPoint(x: 300, y: 924), end: CGPoint(x: 724, y: 100), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

    // Soft glow in the upper-left and a subtle top sheen.
    let glow = CGGradient(colorsSpace: space,
                          colors: [color(0xFFFFFF, 0.28), color(0xFFFFFF, 0)] as CFArray,
                          locations: [0, 1])!
    cg.drawRadialGradient(glow, startCenter: CGPoint(x: 280, y: 820), startRadius: 0,
                          endCenter: CGPoint(x: 280, y: 820), endRadius: 560, options: [])
    let sheen = CGGradient(colorsSpace: space,
                           colors: [color(0xFFFFFF, 0.18), color(0xFFFFFF, 0)] as CFArray,
                           locations: [0, 1])!
    cg.drawLinearGradient(sheen, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 640), options: [])
    cg.restoreGState()

    // Feed glyph: a dot and two concentric quarter arcs.
    let s: CGFloat = 430                       // glyph box size
    let o = CGPoint(x: 512 - s * 0.53, y: 512 - s * 0.53)  // glyph box origin (visually centred)
    let c = CGPoint(x: o.x + s * 0.15, y: o.y + s * 0.15)  // shared centre of dot and arcs
    let stroke = s * 0.16

    let glyph = CGMutablePath()
    glyph.addEllipse(in: CGRect(x: c.x - s * 0.12, y: c.y - s * 0.12, width: s * 0.24, height: s * 0.24))
    for radius in [s * 0.47, s * 0.82] {
        let arc = CGMutablePath()
        arc.addArc(center: c, radius: radius, startAngle: 0, endAngle: .pi / 2, clockwise: false)
        glyph.addPath(arc.copy(strokingWithWidth: stroke, lineCap: .round, lineJoin: .round, miterLimit: 10))
    }

    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -10), blur: 22, color: color(0x8A2A00, 0.45))
    cg.addPath(glyph)
    cg.setFillColor(color(0xFFFFFF))
    cg.fillPath()
    cg.restoreGState()

    // Very light vertical shading on the glyph so it doesn't look flat.
    cg.saveGState()
    cg.addPath(glyph)
    cg.clip()
    let shade = CGGradient(colorsSpace: space,
                           colors: [color(0xFFFFFF, 0), color(0xFFE2C8, 0.55)] as CFArray,
                           locations: [0, 1])!
    cg.drawLinearGradient(shade, start: CGPoint(x: 512, y: o.y + s), end: CGPoint(x: 512, y: o.y), options: [])
    cg.restoreGState()

    NSGraphicsContext.current = nil
    if fullBleed { return opaquePNG(rep.cgImage!) }
    return rep.representation(using: .png, properties: [:])!
}

/// Re-encodes without an alpha channel, which App Store icons must not have.
func opaquePNG(_ image: CGImage) -> Data {
    let ctx = CGContext(
        data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let data = NSMutableData()
    let dest = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
    return data as Data
}

let fm = FileManager.default
let root = URL(fileURLWithPath: fm.currentDirectoryPath)
let iconset = root.appendingPathComponent("App/Assets.xcassets/AppIcon.appiconset")
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)

var images: [[String: String]] = []

// iOS/iPadOS: one opaque, full-bleed 1024px image; the system masks and scales it.
try renderIcon(size: 1024, fullBleed: true).write(to: iconset.appendingPathComponent("AppIcon-iOS.png"))
images.append(["filename": "AppIcon-iOS.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"])

// macOS: the rounded tile with shadow, at every size the asset catalog expects.
for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "AppIcon-mac-\(base)@\(scale)x.png"
        try renderIcon(size: base * scale).write(to: iconset.appendingPathComponent(name))
        images.append(["filename": name, "idiom": "mac", "scale": "\(scale)x", "size": "\(base)x\(base)"])
    }
}

let contents: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
    .write(to: iconset.appendingPathComponent("Contents.json"))
print("Wrote App/Assets.xcassets/AppIcon.appiconset")
