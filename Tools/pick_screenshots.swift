// Picks the best App Store screenshots from a sequence of frames: ones where a whole fish is on
// screen (not cut off by an edge), preferring different-coloured fish.
// Usage: swift Tools/pick_screenshots.swift <count> frame1.png frame2.png …   (prints chosen paths)
import CoreGraphics
import Foundation
import ImageIO

struct Frame { let path: String; let colour: (Double, Double, Double); let size: Double }

func analyse(_ path: String) -> Frame? {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
    // Downscale for speed.
    let w = image.width / 8, h = image.height / 8
    var pixels = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

    // Fish pixels: anything that isn't the teal water, i.e. bright, or warm/saturated away from teal.
    var minX = w, minY = h, maxX = 0, maxY = 0, n = 0
    var sum = (0.0, 0.0, 0.0)
    for y in 0..<h {
        for x in 0..<w {
            let i = (y * w + x) * 4
            let r = Double(pixels[i]) / 255, g = Double(pixels[i + 1]) / 255, b = Double(pixels[i + 2]) / 255
            let bright = max(r, g, b) > 0.62
            let notTeal = r > g + 0.08 || b > g + 0.12
            guard bright || notTeal else { continue }
            n += 1
            sum = (sum.0 + r, sum.1 + g, sum.2 + b)
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    let area = Double(w * h)
    guard Double(n) > area * 0.002 else { return nil }                       // no fish in view
    let mx = Int(Double(w) * 0.04), my = Int(Double(h) * 0.04)
    guard minX > mx, minY > my, maxX < w - mx, maxY < h - my else { return nil } // cut off by an edge
    // Reject frames where the "fish" is spread over the screen (not one compact fish).
    guard Double((maxX - minX) * (maxY - minY)) < area * 0.25 else { return nil }
    // Keep the fish away from the edges: its centre in the middle 70% each way.
    let cx = Double(minX + maxX) / 2 / Double(w), cy = Double(minY + maxY) / 2 / Double(h)
    guard (0.15...0.85).contains(cx), (0.15...0.85).contains(cy) else { return nil }
    // The iPhone simulator sometimes draws a black Dynamic Island at the top; skip those frames.
    // (Bitmap rows run top to bottom, so the top of the screen is the first rows.)
    for y in 0..<max(1, h / 25) {
        for x in (w * 3 / 8)..<(w * 5 / 8) {
            let i = (y * w + x) * 4
            if max(pixels[i], pixels[i + 1], pixels[i + 2]) < 20 { return nil }
        }
    }
    return Frame(path: path, colour: (sum.0 / Double(n), sum.1 / Double(n), sum.2 / Double(n)), size: Double(n))
}

let args = CommandLine.arguments
let count = Int(args[1])!
let frames = args.dropFirst(2).compactMap(analyse)

func distance(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
    let d = (a.0 - b.0, a.1 - b.1, a.2 - b.2)
    return (d.0 * d.0 + d.1 * d.1 + d.2 * d.2).squareRoot()
}

// Greedy: start with the frame showing the most fish, then keep adding the most differently coloured.
var chosen: [Frame] = []
if let first = frames.max(by: { $0.size < $1.size }) { chosen.append(first) }
while chosen.count < count {
    let rest = frames.filter { f in !chosen.contains { $0.path == f.path } }
    guard let next = rest.max(by: { a, b in
        chosen.map { distance($0.colour, a.colour) }.min()! < chosen.map { distance($0.colour, b.colour) }.min()!
    }) else { break }
    chosen.append(next)
}
for f in chosen.sorted(by: { $0.path < $1.path }) { print(f.path) }
