// Generates the Fishy app icons (iPad + Apple TV layered icons and top shelf images).
// Usage: swift Tools/make_icons.swift   (run from the repo root)
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let assets = URL(fileURLWithPath: "Fishy/Assets.xcassets")

// MARK: - Colours

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}
let waterTop = rgb(0.07, 0.42, 0.50)
let waterBottom = rgb(0.03, 0.22, 0.30)
let goldBody = rgb(1.00, 0.55, 0.10)
let goldFin = rgb(1.00, 0.76, 0.38, 0.92)

// MARK: - Drawing

func makeContext(_ w: Int, _ h: Int, opaque: Bool) -> CGContext {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: opaque ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.setShouldAntialias(true)
    return ctx
}

func save(_ ctx: CGContext, _ url: URL) {
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
}

/// Deterministic random numbers so the icons are reproducible.
struct Rng { var s: UInt64; mutating func next() -> CGFloat { s = s &* 6364136223846793005 &+ 1442695040888963407; return CGFloat(s >> 33) / CGFloat(1 << 31) } }

func drawWater(_ ctx: CGContext, _ w: CGFloat, _ h: CGFloat, seed: UInt64) {
    let grad = CGGradient(colorsSpace: nil, colors: [waterTop, waterBottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: h), end: CGPoint(x: w * 0.4, y: 0), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    var r = Rng(s: seed)
    let unit = min(w, h)
    // Soft light patches
    for _ in 0..<9 {
        let rad = unit * (0.15 + r.next() * 0.3)
        ctx.saveGState()
        ctx.translateBy(x: r.next() * w, y: r.next() * h)
        ctx.rotate(by: r.next() * .pi)
        ctx.setFillColor(rgb(0.45, 0.88, 0.88, 0.05 + r.next() * 0.06))
        ctx.fillEllipse(in: CGRect(x: -rad * 0.8, y: -rad * 0.5, width: rad * 1.6, height: rad))
        ctx.restoreGState()
    }
    // Pebbles
    for _ in 0..<Int(w * h / (unit * unit) * 14) {
        let rad = unit * (0.012 + r.next() * 0.03)
        ctx.saveGState()
        ctx.translateBy(x: r.next() * w, y: r.next() * h)
        ctx.rotate(by: r.next() * .pi)
        ctx.setFillColor(rgb(0.02, 0.17, 0.22, 0.55))
        ctx.fillEllipse(in: CGRect(x: -rad * 0.7, y: -rad * 0.5, width: rad * 1.4, height: rad))
        ctx.restoreGState()
    }
}

func drawRipples(_ ctx: CGContext, center: CGPoint, radius: CGFloat) {
    for (i, f) in [1.0, 0.68, 0.40].enumerated() {
        let rr = radius * CGFloat(f)
        ctx.setStrokeColor(rgb(1, 1, 1, 0.16 + CGFloat(i) * 0.08))
        ctx.setLineWidth(radius * 0.035)
        ctx.strokeEllipse(in: CGRect(x: center.x - rr, y: center.y - rr * 0.92, width: rr * 2, height: rr * 1.84))
    }
}

/// Same shape as FishNode, head along +x, centred on the origin.
func drawFish(_ ctx: CGContext, at p: CGPoint, length L: CGFloat, angle: CGFloat, tailBend: CGFloat, shadow: Bool) {
    let w = L * 0.32
    ctx.saveGState()
    ctx.translateBy(x: p.x, y: p.y)
    ctx.rotate(by: angle)

    if shadow {
        ctx.setFillColor(rgb(0, 0, 0, 0.28))
        ctx.fillEllipse(in: CGRect(x: -L * 0.34 + L * 0.06, y: -w / 2 - L * 0.11, width: L * 0.8, height: w))
    }

    func fin(_ y: CGFloat, flip: CGFloat) {
        let path = CGMutablePath()
        let o = CGPoint(x: L * 0.12, y: y)
        let fw = w * 0.9, fh = w * 0.45 * flip
        path.move(to: o)
        path.addQuadCurve(to: CGPoint(x: o.x - fw, y: o.y + fh), control: CGPoint(x: o.x - fw * 0.2, y: o.y + fh * 1.2))
        path.addQuadCurve(to: o, control: CGPoint(x: o.x - fw * 0.6, y: o.y + fh * 0.2))
        ctx.addPath(path); ctx.setFillColor(goldFin); ctx.fillPath()
    }
    fin(w * 0.38, flip: 1)
    fin(-w * 0.38, flip: -1)

    // Tail
    ctx.saveGState()
    ctx.translateBy(x: -L * 0.30, y: 0)
    ctx.rotate(by: tailBend)
    let tail = CGMutablePath()
    tail.move(to: .zero)
    tail.addCurve(to: CGPoint(x: -L * 0.30, y: w * 0.75), control1: CGPoint(x: -L * 0.10, y: w * 0.10), control2: CGPoint(x: -L * 0.22, y: w * 0.70))
    tail.addQuadCurve(to: CGPoint(x: -L * 0.30, y: -w * 0.75), control: CGPoint(x: -L * 0.18, y: 0))
    tail.addCurve(to: .zero, control1: CGPoint(x: -L * 0.22, y: -w * 0.70), control2: CGPoint(x: -L * 0.10, y: -w * 0.10))
    ctx.addPath(tail); ctx.setFillColor(goldFin); ctx.fillPath()
    ctx.restoreGState()

    // Body
    let body = CGMutablePath()
    let nose = CGPoint(x: L * 0.38, y: 0), back = CGPoint(x: -L * 0.34, y: 0)
    body.move(to: nose)
    body.addCurve(to: back, control1: CGPoint(x: L * 0.36, y: w * 0.62), control2: CGPoint(x: -L * 0.10, y: w * 0.55))
    body.addCurve(to: nose, control1: CGPoint(x: -L * 0.10, y: -w * 0.55), control2: CGPoint(x: L * 0.36, y: -w * 0.62))
    ctx.addPath(body); ctx.setFillColor(goldBody); ctx.fillPath()

    // Highlight
    ctx.setFillColor(rgb(1, 1, 1, 0.28))
    ctx.fillEllipse(in: CGRect(x: -L * 0.245, y: -w * 0.09, width: L * 0.45, height: w * 0.18))

    // Eyes
    for side: CGFloat in [1, -1] {
        let er = w * 0.11
        let c = CGPoint(x: L * 0.25, y: side * w * 0.27)
        ctx.setFillColor(rgb(1, 1, 1, 0.9))
        ctx.fillEllipse(in: CGRect(x: c.x - er * 1.25, y: c.y - er * 1.25, width: er * 2.5, height: er * 2.5))
        ctx.setFillColor(rgb(0, 0, 0))
        ctx.fillEllipse(in: CGRect(x: c.x - er, y: c.y - er, width: er * 2, height: er * 2))
    }
    ctx.restoreGState()
}

// MARK: - Asset catalog helpers

func writeJSON(_ obj: Any, _ url: URL) {
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = try! JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
    try! data.write(to: url)
}
let info: [String: Any] = ["author": "xcode", "version": 1]

// MARK: - iPad / iOS icon (1024, opaque, single size)

do {
    let s: CGFloat = 1024
    let ctx = makeContext(1024, 1024, opaque: true)
    drawWater(ctx, s, s, seed: 7)
    let c = CGPoint(x: s * 0.53, y: s * 0.52)
    drawRipples(ctx, center: CGPoint(x: s * 0.36, y: s * 0.38), radius: s * 0.36)
    drawFish(ctx, at: c, length: s * 0.72, angle: .pi / 4.6, tailBend: -0.28, shadow: true)
    let dir = assets.appendingPathComponent("AppIcon.appiconset")
    save(ctx, dir.appendingPathComponent("AppIcon.png"))
    writeJSON(["images": [["filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"]], "info": info],
              dir.appendingPathComponent("Contents.json"))
}

// MARK: - Apple TV layered icon (back: water, middle: ripples, front: fish)

let brand = assets.appendingPathComponent("App Icon & Top Shelf Image.brandassets")

func tvLayer(_ w: Int, _ h: Int, layer: String, scale: CGFloat) -> CGContext {
    let W = CGFloat(w), H = CGFloat(h)
    let ctx = makeContext(w, h, opaque: layer == "Back")
    let fishCenter = CGPoint(x: W * 0.52, y: H * 0.5)
    switch layer {
    case "Back":
        drawWater(ctx, W, H, seed: 11)
    case "Middle":
        drawRipples(ctx, center: CGPoint(x: W * 0.38, y: H * 0.45), radius: H * 0.42)
    default:
        drawFish(ctx, at: fishCenter, length: H * 0.82, angle: .pi / 9, tailBend: -0.3, shadow: true)
    }
    return ctx
}

func writeImageStack(name: String, base: CGSize, scales: [Int]) {
    let stack = brand.appendingPathComponent("\(name).imagestack")
    let layers = ["Front", "Middle", "Back"]
    writeJSON(["layers": layers.map { ["filename": "\($0).imagestacklayer"] }, "info": info], stack.appendingPathComponent("Contents.json"))
    for layer in layers {
        let lDir = stack.appendingPathComponent("\(layer).imagestacklayer")
        writeJSON(["info": info], lDir.appendingPathComponent("Contents.json"))
        let iDir = lDir.appendingPathComponent("Content.imageset")
        var images: [[String: Any]] = []
        for sc in scales {
            let file = "\(layer)@\(sc)x.png"
            let ctx = tvLayer(Int(base.width) * sc, Int(base.height) * sc, layer: layer, scale: CGFloat(sc))
            save(ctx, iDir.appendingPathComponent(file))
            images.append(["filename": file, "idiom": "tv", "scale": "\(sc)x"])
        }
        writeJSON(["images": images, "info": info], iDir.appendingPathComponent("Contents.json"))
    }
}

writeImageStack(name: "App Icon", base: CGSize(width: 400, height: 240), scales: [1, 2])
writeImageStack(name: "App Icon - App Store", base: CGSize(width: 1280, height: 768), scales: [1])

// MARK: - Top shelf (wide pond with a fish swimming across)

func writeTopShelf(name: String, base: CGSize, seed: UInt64) {
    let dir = brand.appendingPathComponent("\(name).imageset")
    var images: [[String: Any]] = []
    for sc in [1, 2] {
        let W = base.width * CGFloat(sc), H = base.height * CGFloat(sc)
        let ctx = makeContext(Int(W), Int(H), opaque: true)
        drawWater(ctx, W, H, seed: seed)
        drawRipples(ctx, center: CGPoint(x: W * 0.62, y: H * 0.42), radius: H * 0.32)
        drawFish(ctx, at: CGPoint(x: W * 0.70, y: H * 0.52), length: H * 0.6, angle: .pi / 12, tailBend: -0.3, shadow: true)
        let file = "\(name.replacingOccurrences(of: " ", with: ""))@\(sc)x.png"
        save(ctx, dir.appendingPathComponent(file))
        images.append(["filename": file, "idiom": "tv", "scale": "\(sc)x"])
    }
    writeJSON(["images": images, "info": info], dir.appendingPathComponent("Contents.json"))
}

writeTopShelf(name: "Top Shelf Image", base: CGSize(width: 1920, height: 720), seed: 21)
writeTopShelf(name: "Top Shelf Image Wide", base: CGSize(width: 2320, height: 720), seed: 21)

writeJSON([
    "assets": [
        ["filename": "App Icon - App Store.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "1280x768"],
        ["filename": "App Icon.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "400x240"],
        ["filename": "Top Shelf Image Wide.imageset", "idiom": "tv", "role": "top-shelf-image-wide", "size": "2320x720"],
        ["filename": "Top Shelf Image.imageset", "idiom": "tv", "role": "top-shelf-image", "size": "1920x720"],
    ],
    "info": info,
], brand.appendingPathComponent("Contents.json"))

print("Icons written to \(assets.path)")
