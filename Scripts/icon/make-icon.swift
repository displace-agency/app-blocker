// Draws the FocusGuard macOS app icon (1024 canvas) with CoreGraphics.
// Usage: swift Scripts/icon/make-icon.swift <output.png>
// Source art: Resources/brand/focusguard-icon.svg (512 viewBox, glyph translated 14,-21).
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-master-1024.png"
let canvas: CGFloat = 1024
let body: CGFloat = 824                       // Apple icon grid: 824 body on a 1024 canvas
let inset = (canvas - body) / 2
let k = body / 512                            // glyph scale (512 units -> body)

let cs = CGColorSpace(name: CGColorSpace.sRGB)!
guard let ctx = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8, bytesPerRow: 0,
                          space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("ctx") }

// Continuous-corner squircle (superellipse, n = 5) centred in the canvas.
func squircle(in r: CGRect, n: Double = 5, steps: Int = 720) -> CGPath {
    let p = CGMutablePath()
    let cx = Double(r.midX), cy = Double(r.midY), a = Double(r.width / 2), b = Double(r.height / 2)
    for i in 0..<steps {
        let t = Double(i) / Double(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = cx + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
        let y = cy + b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
        i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
    }
    p.closeSubpath()
    return p
}

let bodyRect = CGRect(x: inset, y: inset, width: body, height: body)
let bodyPath = squircle(in: bodyRect)
let ink = CGColor(colorSpace: cs, components: [0x0F/255.0, 0x0F/255.0, 0x10/255.0, 1])!

// Body with the standard soft drop shadow (down 12, blur 24, 35% black). Offset is in
// unflipped base space, so a negative height pushes the shadow down.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 24,
              color: CGColor(colorSpace: cs, components: [0, 0, 0, 0.35])!)
ctx.addPath(bodyPath)
ctx.setFillColor(ink)
ctx.fillPath()
ctx.restoreGState()

// Glyph: flip to a top-left origin so SVG coordinates apply directly.
ctx.saveGState()
ctx.translateBy(x: inset, y: canvas - inset)
ctx.scaleBy(x: k, y: -k)
ctx.translateBy(x: 14, y: -21)
ctx.setFillColor(CGColor(colorSpace: cs, components: [1, 1, 1, 1])!)

let slash = CGMutablePath()
slash.move(to: CGPoint(x: 137, y: 183)); slash.addLine(to: CGPoint(x: 166, y: 183))
slash.addLine(to: CGPoint(x: 138, y: 330)); slash.addLine(to: CGPoint(x: 108, y: 330))
slash.closeSubpath()

let shield = CGMutablePath()
shield.move(to: CGPoint(x: 176, y: 183)); shield.addLine(to: CGPoint(x: 376, y: 183))
shield.addLine(to: CGPoint(x: 376, y: 250))
shield.addCurve(to: CGPoint(x: 276, y: 372), control1: CGPoint(x: 376, y: 308), control2: CGPoint(x: 334, y: 348))
shield.addCurve(to: CGPoint(x: 176, y: 250), control1: CGPoint(x: 218, y: 348), control2: CGPoint(x: 176, y: 308))
shield.closeSubpath()

ctx.addPath(slash); ctx.fillPath()
ctx.addPath(shield); ctx.fillPath()
ctx.restoreGState()

guard let img = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, UTType.png.identifier as CFString, 1, nil)
else { fatalError("png") }
CGImageDestinationAddImage(dest, img, nil)
guard CGImageDestinationFinalize(dest) else { fatalError("write") }
print("Wrote \(out)")
