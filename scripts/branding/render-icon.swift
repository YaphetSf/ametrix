#!/usr/bin/env swift
// Renders the Ametrix app icon: a pointed pixel "A" filled with bright matrix
// glyphs over a dim matrix field, on a dark green squircle. Reproducible via a
// fixed RNG seed. Outputs AppIcon.icns plus PNG masters.
//
// Usage: swift scripts/branding/render-icon.swift [output-dir]
//        (output-dir defaults to ./assets)

import AppKit
import CoreText

struct RNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

let glyphs = Array("ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾅﾆﾇﾈﾊﾋﾌﾍﾎ0123456789ABCDEFGHKMXYZ#$%&*+<>=?")

// Finalised "c" parameters.
let gridN = 13
let fillFactor: CGFloat = 0.80
let bgMax: CGFloat = 0.30
let seed: UInt64 = 99

func ctxForSize(_ s: Int) -> CGContext {
    CGContext(data: nil, width: s, height: s, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB)!,
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}
func savePNG(_ ctx: CGContext, _ path: String) {
    guard let img = ctx.makeImage() else { return }
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
}
func squircle(_ r: CGRect) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: r.width * 0.2237, cornerHeight: r.width * 0.2237, transform: nil)
}
func green(_ a: CGFloat) -> NSColor { NSColor(srgbRed: 0.0, green: 0.95, blue: 0.37, alpha: a) }
func brightGreen(_ a: CGFloat) -> NSColor { NSColor(srgbRed: 0.82, green: 1.0, blue: 0.88, alpha: a) }

func drawGlyph(_ ch: Character, center c: CGPoint, size: CGFloat, color: NSColor, glow: CGFloat) {
    let font = NSFont(name: "Menlo-Bold", size: size) ?? .monospacedSystemFont(ofSize: size, weight: .bold)
    var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
    if glow > 0 {
        let sh = NSShadow(); sh.shadowColor = color.withAlphaComponent(0.97)
        sh.shadowBlurRadius = glow; sh.shadowOffset = .zero
        attrs[.shadow] = sh
    }
    let s = NSAttributedString(string: String(ch), attributes: attrs)
    let z = s.size()
    s.draw(at: CGPoint(x: c.x - z.width / 2, y: c.y - z.height / 2))
}

// Grayscale coverage mask from the actual "A" glyph outline, scaled to fill the grid.
func makeAMask(_ mw: Int, _ mh: Int) -> [UInt8] {
    var data = [UInt8](repeating: 0, count: mw * mh)
    let m = data.withUnsafeMutableBytes {
        CGContext(data: $0.baseAddress, width: mw, height: mh, bitsPerComponent: 8, bytesPerRow: mw,
                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    }
    m.setFillColor(gray: 0, alpha: 1); m.fill(CGRect(x: 0, y: 0, width: mw, height: mh))
    let ct = NSFont.systemFont(ofSize: 100, weight: .black) as CTFont
    var u = Array("A".utf16); var gl = [CGGlyph](repeating: 0, count: 1)
    CTFontGetGlyphsForCharacters(ct, &u, &gl, 1)
    guard let path = CTFontCreatePathForGlyph(ct, gl[0], nil) else { return data }
    let bb = path.boundingBoxOfPath
    let scale = min(CGFloat(mw) * fillFactor / bb.width, CGFloat(mh) * fillFactor / bb.height)
    let tx = (CGFloat(mw) - bb.width * scale) / 2 - bb.minX * scale
    let ty = (CGFloat(mh) - bb.height * scale) / 2 - bb.minY * scale
    var t = CGAffineTransform(translationX: tx, y: ty).scaledBy(x: scale, y: scale)
    let sp = path.copy(using: &t)!
    m.addPath(sp); m.setFillColor(gray: 1, alpha: 1); m.fillPath()
    return data
}

func renderIcon(_ size: Int) -> CGContext {
    let ctx = ctxForSize(size); let s = CGFloat(size)
    let sq = CGRect(x: s * 0.085, y: s * 0.085, width: s * 0.83, height: s * 0.83)
    ctx.saveGState(); ctx.addPath(squircle(sq)); ctx.clip()
    let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: [
        NSColor(srgbRed: 0.045, green: 0.08, blue: 0.055, alpha: 1).cgColor,
        NSColor(srgbRed: 0.006, green: 0.015, blue: 0.01, alpha: 1).cgColor
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: sq.maxY), end: CGPoint(x: 0, y: sq.minY), options: [])
    ctx.restoreGState()

    let pad = sq.width * 0.06
    let inner = sq.insetBy(dx: pad, dy: pad)
    let cw = inner.width / CGFloat(gridN), chh = inner.height / CGFloat(gridN)
    let mw = max(96, Int(inner.width)), mh = max(96, Int(inner.height))
    let mask = makeAMask(mw, mh)
    let cwM = CGFloat(mw) / CGFloat(gridN), chM = CGFloat(mh) / CGFloat(gridN)
    func samp(_ mx: CGFloat, _ my: CGFloat) -> CGFloat {
        let c = min(max(Int(mx), 0), mw - 1), r = min(max(mh - 1 - Int(my), 0), mh - 1)
        return CGFloat(mask[r * mw + c]) / 255
    }
    func on(_ ci: Int, _ ri: Int) -> Bool {
        let cx = (CGFloat(ci) + 0.5) * cwM, cy = CGFloat(mh) - (CGFloat(ri) + 0.5) * chM
        var sum: CGFloat = 0, n: CGFloat = 0
        for dx in stride(from: -0.3, through: 0.3, by: 0.3) {
            for dy in stride(from: -0.3, through: 0.3, by: 0.3) { sum += samp(cx + dx * cwM, cy + dy * chM); n += 1 }
        }
        return sum / n > 0.45
    }

    var rng = RNG(seed: seed)
    ctx.saveGState(); ctx.addPath(squircle(sq)); ctx.clip()
    let gns = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = gns
    for ri in 0..<gridN {
        for ci in 0..<gridN {
            let x = inner.minX + (CGFloat(ci) + 0.5) * cw, y = inner.maxY - (CGFloat(ri) + 0.5) * chh
            let ch = glyphs[Int.random(in: 0..<glyphs.count, using: &rng)]
            if on(ci, ri) {
                drawGlyph(ch, center: CGPoint(x: x, y: y), size: chh * 0.95, color: brightGreen(1.0), glow: cw * 0.34)
            } else {
                let a = CGFloat.random(in: 0.10...bgMax, using: &rng)
                drawGlyph(ch, center: CGPoint(x: x, y: y), size: chh * 0.80, color: green(a), glow: 0)
            }
        }
    }
    NSGraphicsContext.restoreGraphicsState(); ctx.restoreGState()

    ctx.saveGState(); ctx.addPath(squircle(sq.insetBy(dx: 1, dy: 1)))
    ctx.setStrokeColor(green(0.22).cgColor); ctx.setLineWidth(sq.width * 0.006); ctx.strokePath()
    ctx.restoreGState()
    return ctx
}

// ---- Output ----
let fm = FileManager.default
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : fm.currentDirectoryPath + "/assets"
try? fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let iconset = NSTemporaryDirectory() + "AppIcon.iconset"
try? fm.removeItem(atPath: iconset)
try? fm.createDirectory(atPath: iconset, withIntermediateDirectories: true)

let specs: [(Int, Int, String)] = [
    (16, 1, "icon_16x16.png"), (16, 2, "icon_16x16@2x.png"),
    (32, 1, "icon_32x32.png"), (32, 2, "icon_32x32@2x.png"),
    (128, 1, "icon_128x128.png"), (128, 2, "icon_128x128@2x.png"),
    (256, 1, "icon_256x256.png"), (256, 2, "icon_256x256@2x.png"),
    (512, 1, "icon_512x512.png"), (512, 2, "icon_512x512@2x.png")
]
for (pt, scale, name) in specs { savePNG(renderIcon(pt * scale), "\(iconset)/\(name)") }

let icns = "\(outDir)/AppIcon.icns"
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset, "-o", icns]
try p.run(); p.waitUntilExit()
try? fm.removeItem(atPath: iconset)

savePNG(renderIcon(1024), "\(outDir)/ametrix-icon-1024.png")
savePNG(renderIcon(256), "\(outDir)/ametrix-icon-256.png")

print("Wrote \(icns)")
print("Wrote \(outDir)/ametrix-icon-1024.png")
print("Wrote \(outDir)/ametrix-icon-256.png")
print(p.terminationStatus == 0 ? "iconutil OK" : "iconutil FAILED (\(p.terminationStatus))")
