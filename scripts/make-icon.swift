// Builds Assets/AppIcon.icns in the macOS 26 style: a gradient background and a few big, simple
// glass shapes. Apple's Icon Composer renders those layers with Liquid Glass (translucency,
// blurred refraction of what's behind, specular rims, soft shadows); Xcode's actool is needed to
// ship a live layered icon, so this renders the same treatment into a flattened .icns.
//
//   swift scripts/make-icon.swift build/AppIcon.icns [--concept snow|petals|breeze] [--style blue|light]
//                                  [--preview preview.png]

import AppKit
import CoreImage
import SwiftUI

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("usage: make-icon.swift out.icns [--concept snow|petals|breeze] [--style blue|light] [--preview preview.png]")
    exit(1)
}
let outURL = URL(fileURLWithPath: args[1])
let previewURL = args.firstIndex(of: "--preview").map { URL(fileURLWithPath: args[$0 + 1]) }
let style = args.firstIndex(of: "--style").map { args[$0 + 1] } ?? "blue"
let concept = args.firstIndex(of: "--concept").map { args[$0 + 1] } ?? "snow"

let canvas = CGSize(width: 1024, height: 1024)
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let space = CGColorSpace(name: CGColorSpace.displayP3)!
let ci = CIContext(options: [.workingColorSpace: space])

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255,
                                            CGFloat(hex & 0xFF) / 255, a])!
}

func continuous(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    Path(roundedRect: rect, cornerRadius: radius, style: .continuous).cgPath
}

/// A petal of air: narrow where it leaves the blade, flaring wider as it travels, rounded at the
/// end. `angle` tilts it away from straight down (radians).
func petal(from origin: CGPoint, length L: CGFloat, width W: CGFloat, angle: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: -W * 0.07, y: 0))
    p.addCurve(to: CGPoint(x: -W * 0.5, y: L * 0.8), control1: CGPoint(x: -W * 0.18, y: L * 0.28), control2: CGPoint(x: -W * 0.56, y: L * 0.52))
    p.addCurve(to: CGPoint(x: W * 0.5, y: L * 0.8), control1: CGPoint(x: -W * 0.42, y: L * 1.06), control2: CGPoint(x: W * 0.42, y: L * 1.06))
    p.addCurve(to: CGPoint(x: W * 0.07, y: 0), control1: CGPoint(x: W * 0.56, y: L * 0.52), control2: CGPoint(x: W * 0.18, y: L * 0.28))
    p.closeSubpath()
    var t = CGAffineTransform(translationX: origin.x, y: origin.y).rotated(by: angle)
    return p.copy(using: &t)!
}

/// The cool-mode snowflake: six arms with a V near each tip, as one filled glass outline.
func snowflake(center c: CGPoint, radius r: CGFloat, weight: CGFloat) -> CGPath {
    let p = CGMutablePath()
    for i in 0..<6 {
        let a = CGFloat(i) * .pi / 3 - .pi / 2
        let dir = CGPoint(x: cos(a), y: sin(a))
        let tip = CGPoint(x: c.x + dir.x * r, y: c.y + dir.y * r)
        p.move(to: c)
        p.addLine(to: tip)
        let fork = CGPoint(x: c.x + dir.x * r * 0.62, y: c.y + dir.y * r * 0.62)
        for side in [-1.0, 1.0] {
            let b = a + CGFloat(side) * .pi / 4
            p.move(to: fork)
            p.addLine(to: CGPoint(x: fork.x + cos(b) * r * 0.3, y: fork.y + sin(b) * r * 0.3))
        }
    }
    return p.copy(strokingWithWidth: weight, lineCap: .round, lineJoin: .round, miterLimit: 1).normalized()
}

/// A ribbon of air: a thick curve with round ends, as a filled outline so it can be glass.
func ribbon(_ points: [CGPoint], width: CGFloat) -> CGPath {
    let path = CGMutablePath()
    path.move(to: points[0])
    path.addCurve(to: points[3], control1: points[1], control2: points[2])
    return path.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 1)
}

struct Glass {
    let path: CGPath
    let top: CGColor
    let bottom: CGColor
    /// How much of what's behind shows through, blurred.
    let clarity: CGFloat
    let shadow: CGColor
}

struct Design {
    let background: [CGColor]
    let layers: [Glass]
}

func design(_ style: String) -> Design {
    // The unit: 1055 × 299 mm, so ~3.5 : 1, wide and high in the tile so the air has room.
    let body = continuous(CGRect(x: 178, y: 236, width: 668, height: 200), 66)
    // The blade along the bottom, as its own overlapping layer.
    let blade = continuous(CGRect(x: 218, y: 384, width: 588, height: 44), 22)
    let waves: [CGPath]
    switch concept {
    case "snow":
        // The unit sits in front; the snowflake glows from behind it, like the sun behind a cloud.
        waves = [snowflake(center: CGPoint(x: 512, y: 560), radius: 250, weight: 50)]
    case "breeze":
        // Wind streams curling at their ends, flowing from under the blade.
        func breeze(_ y: CGFloat, from x0: CGFloat, to x1: CGFloat, curl: CGFloat) -> CGPath {
            let p = CGMutablePath()
            p.move(to: CGPoint(x: x0, y: y))
            p.addLine(to: CGPoint(x: x1 - curl, y: y))
            p.addArc(center: CGPoint(x: x1 - curl, y: y - curl), radius: curl, startAngle: .pi / 2, endAngle: -.pi * 0.35, clockwise: true)
            return p.copy(strokingWithWidth: 48, lineCap: .round, lineJoin: .round, miterLimit: 1)
        }
        waves = [breeze(560, from: 250, to: 760, curl: 62), breeze(670, from: 300, to: 640, curl: 54), breeze(770, from: 360, to: 560, curl: 44)]
    default:
        // Cool air fanning out of the blade: three overlapping translucent petals.
        waves = [
            petal(from: CGPoint(x: 452, y: 418), length: 360, width: 230, angle: 0.5),
            petal(from: CGPoint(x: 572, y: 418), length: 360, width: 230, angle: -0.5),
            petal(from: CGPoint(x: 512, y: 418), length: 400, width: 250, angle: 0),
        ]
    }
    switch style {
    case "blue":
        return Design(
            background: [rgb(0x6FD0FF), rgb(0x2E8BFF), rgb(0x1560E8)],
            layers: waves.map { Glass(path: $0, top: rgb(0xFFFFFF, 0.85), bottom: rgb(0xBFE6FF, 0.35), clarity: 0.55, shadow: rgb(0x0A3FA8, 0.2)) }
                + [Glass(path: body, top: rgb(0xFFFFFF, 0.97), bottom: rgb(0xE4EDF7, 0.92), clarity: 0.25, shadow: rgb(0x0A3FA8, 0.35)),
                   Glass(path: blade, top: rgb(0xCFE4FA, 0.75), bottom: rgb(0xFFFFFF, 0.85), clarity: 0.6, shadow: rgb(0x0A3FA8, 0.12))])
    default:
        return Design(
            background: [rgb(0xFFFFFF), rgb(0xF2F5F9), rgb(0xE3E8EF)],
            layers: waves.map { Glass(path: $0, top: rgb(0x2F9BFF, 0.9), bottom: rgb(0x8FDCFF, 0.45), clarity: 0.5, shadow: rgb(0x0B5BD6, 0.2)) }
                + [Glass(path: body, top: rgb(0x48B6FF, 0.96), bottom: rgb(0x0A6CF0, 0.96), clarity: 0.2, shadow: rgb(0x0B4FBF, 0.35)),
                   Glass(path: blade, top: rgb(0xFFFFFF, 0.55), bottom: rgb(0xE6F3FF, 0.75), clarity: 0.6, shadow: rgb(0x0B4FBF, 0.15))])
    }
}

func makeContext(_ size: Int) -> CGContext {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let s = CGFloat(size) / canvas.width
    ctx.scaleBy(x: s, y: s)
    ctx.translateBy(x: 0, y: canvas.height)
    ctx.scaleBy(x: 1, y: -1)
    ctx.interpolationQuality = .high
    return ctx
}

/// Blurs what's been drawn so far (the "backdrop" a glass layer refracts).
func blurredBackdrop(_ ctx: CGContext, radius: CGFloat, size: Int) -> CGImage {
    let image = CIImage(cgImage: ctx.makeImage()!)
    let blurred = image.clampedToExtent()
        .applyingGaussianBlur(sigma: Double(radius) * Double(size) / Double(canvas.width))
        .cropped(to: image.extent)
    return ci.createCGImage(blurred, from: image.extent)!
}

func drawGlass(_ g: Glass, in ctx: CGContext, size: Int) {
    let bounds = g.path.boundingBoxOfPath
    let k = CGFloat(size) / canvas.width

    // Soft shadow onto whatever is behind, tinted by the layer's colour.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14 * k), blur: 30 * k, color: g.shadow)
    ctx.addPath(g.path)
    ctx.setFillColor(rgb(0xFFFFFF, 0.01))
    ctx.fillPath()
    ctx.restoreGState()

    // Refraction: the backdrop, blurred, shows through the glass.
    let backdrop = blurredBackdrop(ctx, radius: 22, size: size)
    ctx.saveGState()
    ctx.addPath(g.path)
    ctx.clip()
    ctx.saveGState()
    ctx.translateBy(x: 0, y: canvas.height)
    ctx.scaleBy(x: 1, y: -1)
    ctx.setAlpha(g.clarity)
    ctx.draw(backdrop, in: CGRect(origin: .zero, size: canvas))
    ctx.restoreGState()

    // Body colour, lighter at the top where the light hits.
    let fill = CGGradient(colorsSpace: space, colors: [g.top, g.bottom] as CFArray, locations: [0, 1])!
    ctx.setAlpha(1 - g.clarity * 0.5)
    ctx.drawLinearGradient(fill, start: CGPoint(x: bounds.midX, y: bounds.minY), end: CGPoint(x: bounds.midX, y: bounds.maxY), options: [])
    ctx.setAlpha(1)

    // A soft sheen across the upper half.
    let sheen = CGGradient(colorsSpace: space, colors: [rgb(0xFFFFFF, 0.35), rgb(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(sheen, start: CGPoint(x: bounds.midX, y: bounds.minY), end: CGPoint(x: bounds.midX, y: bounds.midY), options: [])

    // Specular rim: bright along the top edge, faint along the bottom.
    ctx.addPath(g.path)
    ctx.setLineWidth(7)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    let rim = CGGradient(colorsSpace: space, colors: [rgb(0xFFFFFF, 0.95), rgb(0xFFFFFF, 0.1), rgb(0xFFFFFF, 0.45)] as CFArray,
                         locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(rim, start: CGPoint(x: bounds.midX, y: bounds.minY), end: CGPoint(x: bounds.midX, y: bounds.maxY), options: [])
    ctx.restoreGState()
}

func render(size: Int) -> CGImage {
    let d = design(style)
    let ctx = makeContext(size)
    let shape = continuous(tile, 185.4)
    let k = CGFloat(size) / canvas.width

    // The tile itself: template shadow, gradient, then the glass layers inside it.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * k), blur: 20 * k, color: rgb(0x000000, 0.28))
    ctx.addPath(shape)
    ctx.setFillColor(d.background[1])
    ctx.fillPath()
    ctx.restoreGState()

    // Layers render on their own canvas (clipped to the tile) so backdrop blurs stay inside it.
    let inner = makeContext(size)
    inner.addPath(shape)
    inner.clip()
    let bg = CGGradient(colorsSpace: space, colors: d.background as CFArray, locations: [0, 0.6, 1])!
    inner.drawLinearGradient(bg, start: CGPoint(x: 512, y: tile.minY), end: CGPoint(x: 512, y: tile.maxY), options: [])
    for layer in d.layers { drawGlass(layer, in: inner, size: size) }
    // The tile's own glass edge.
    inner.addPath(shape)
    inner.setLineWidth(6)
    inner.replacePathWithStrokedPath()
    inner.clip()
    let edge = CGGradient(colorsSpace: space, colors: [rgb(0xFFFFFF, 0.9), rgb(0xFFFFFF, 0.05), rgb(0xFFFFFF, 0.3)] as CFArray,
                          locations: [0, 0.5, 1])!
    inner.drawLinearGradient(edge, start: CGPoint(x: 512, y: tile.minY), end: CGPoint(x: 512, y: tile.maxY), options: [])

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    ctx.translateBy(x: 0, y: canvas.height)
    ctx.scaleBy(x: 1, y: -1)
    ctx.draw(inner.makeImage()!, in: CGRect(origin: .zero, size: canvas))
    ctx.restoreGState()
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    writePNG(render(size: base), to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    writePNG(render(size: base * 2), to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
if let previewURL { writePNG(render(size: 1024), to: previewURL) }

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", outURL.path]
try! task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "wrote \(outURL.path)" : "iconutil failed")
