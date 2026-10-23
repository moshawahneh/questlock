// Renders the QuestLock app icon (1024×1024, no transparency) with CoreGraphics.
// Run: swift design/make-app-icon.swift <output.png>
// Drawn from scratch: Apple's licence doesn't allow SF Symbols in app icons.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

// Background: diagonal indigo → violet, with a soft glow behind the lock. (CG origin is bottom-left.)
let bg = CGGradient(colorsSpace: space, colors: [rgb(0x2A1B8C), rgb(0x5B2FD6), rgb(0x8A45EC)] as CFArray, locations: [0, 0.55, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: 1024), end: CGPoint(x: 1024, y: 0), options: [])
let glow = CGGradient(colorsSpace: space, colors: [rgb(0xFFFFFF, 0.18), rgb(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 500), startRadius: 0,
                       endCenter: CGPoint(x: 512, y: 500), endRadius: 470, options: [])

let white = rgb(0xFFFFFF)

// Shackle: lifted and open. Left leg runs into the body; the right leg stops short of it.
let shackle = CGMutablePath()
let radius: CGFloat = 132, cx: CGFloat = 512, legTop: CGFloat = 742
shackle.move(to: CGPoint(x: cx - radius, y: 600))
shackle.addLine(to: CGPoint(x: cx - radius, y: legTop))
shackle.addArc(center: CGPoint(x: cx, y: legTop), radius: radius, startAngle: .pi, endAngle: 0, clockwise: true)
shackle.addLine(to: CGPoint(x: cx + radius, y: 700))
ctx.addPath(shackle)
ctx.setStrokeColor(white)
ctx.setLineWidth(80)
ctx.setLineCap(.round)
ctx.strokePath()

// Body.
let body = CGPath(roundedRect: CGRect(x: 262, y: 196, width: 500, height: 410), cornerWidth: 80, cornerHeight: 80, transform: nil)
ctx.addPath(body)
ctx.setFillColor(white)
ctx.fillPath()

// Keyhole shaped like a map pin, cut out in the background colour.
let pin = CGMutablePath()
let pinCenter = CGPoint(x: 512, y: 432), pinR: CGFloat = 66
pin.addArc(center: pinCenter, radius: pinR, startAngle: .pi * 1.18, endAngle: -.pi * 0.18, clockwise: true)
pin.addLine(to: CGPoint(x: 512, y: 300))
pin.closeSubpath()
ctx.addPath(pin)
ctx.setFillColor(rgb(0x4A27C4))
ctx.fillPath()
ctx.addEllipse(in: CGRect(x: pinCenter.x - 26, y: pinCenter.y - 26, width: 52, height: 52))
ctx.setFillColor(white)
ctx.fillPath()

// Sparkle: a four-point star, top right.
func sparkle(at c: CGPoint, r: CGFloat) {
    let p = CGMutablePath()
    let inner = r * 0.28
    for i in 0..<8 {
        let angle = CGFloat(i) * .pi / 4 + .pi / 2
        let len = i % 2 == 0 ? r : inner
        let pt = CGPoint(x: c.x + cos(angle) * len, y: c.y + sin(angle) * len)
        i == 0 ? p.move(to: pt) : p.addLine(to: pt)
    }
    p.closeSubpath()
    ctx.addPath(p)
    ctx.setFillColor(rgb(0xFFD54A))
    ctx.fillPath()
}
sparkle(at: CGPoint(x: 800, y: 842), r: 74)
sparkle(at: CGPoint(x: 878, y: 724), r: 34)

let image = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
precondition(CGImageDestinationFinalize(dest), "Couldn't write \(out)")
print("Wrote \(out)")
