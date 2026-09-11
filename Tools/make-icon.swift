import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let S: CGFloat = 1024

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: a)
}

struct Palette {
    var sky: [CGColor]
    var sun: CGColor
    var sunCenter: CGPoint
    var sunRadius: CGFloat
    var glow: CGColor
    var glowCenter: CGPoint
    var temple: CGColor
    var waves: [CGColor]
    var glint: CGColor
}

let day = Palette(
    sky: [rgb(0xD94C7A), rgb(0xF58A4B), rgb(0xFFC65C)],
    sun: rgb(0xFFF1C9),
    sunCenter: CGPoint(x: 512, y: 440),
    sunRadius: 215,
    glow: rgb(0xFFE3A0, 0.7),
    glowCenter: CGPoint(x: 512, y: 440),
    temple: rgb(0x4A1D3F),
    waves: [rgb(0x1FA39A), rgb(0x137C80), rgb(0x0C5663)],
    glint: rgb(0xFFF4D6, 0.85)
)

let night = Palette(
    sky: [rgb(0x120F33), rgb(0x2E1D5C), rgb(0x6B3868)],
    sun: rgb(0xF4E6C8),
    sunCenter: CGPoint(x: 790, y: 225),
    sunRadius: 78,
    glow: rgb(0xF2B544, 0.38),
    glowCenter: CGPoint(x: 512, y: 540),
    temple: rgb(0xF2B544),
    waves: [rgb(0x1D3F66), rgb(0x152F52), rgb(0x0E2140)],
    glint: rgb(0xF2B544, 0.8)
)

func wave(_ ctx: CGContext, baseY: CGFloat, amp: CGFloat, length: CGFloat, phase: CGFloat, color: CGColor) {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 0, y: S))
    var x: CGFloat = 0
    while x <= S + 8 {
        path.addLine(to: CGPoint(x: x, y: baseY + amp * sin(phase + x / length * 2 * .pi)))
        x += 8
    }
    path.addLine(to: CGPoint(x: S, y: S))
    path.closeSubpath()
    ctx.addPath(path)
    ctx.setFillColor(color)
    ctx.fillPath()
}

func roundedBar(_ ctx: CGContext, halfWidth: CGFloat, top: CGFloat, bottom: CGFloat, radius: CGFloat) {
    let rect = CGRect(x: 512 - halfWidth, y: top, width: halfWidth * 2, height: bottom - top)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.fillPath()
}

// Sukhothai/Ayutthaya-style bell chedi: stepped base, flared bell, harmika, tapering rings, spire.
func drawChedi(_ ctx: CGContext, color: CGColor) {
    ctx.setFillColor(color)
    roundedBar(ctx, halfWidth: 178, top: 702, bottom: 820, radius: 14)
    roundedBar(ctx, halfWidth: 146, top: 662, bottom: 708, radius: 12)
    roundedBar(ctx, halfWidth: 118, top: 628, bottom: 668, radius: 10)

    let bell = CGMutablePath()
    bell.move(to: CGPoint(x: 386, y: 634))
    bell.addCurve(to: CGPoint(x: 512, y: 470), control1: CGPoint(x: 424, y: 620), control2: CGPoint(x: 428, y: 472))
    bell.addCurve(to: CGPoint(x: 638, y: 634), control1: CGPoint(x: 596, y: 472), control2: CGPoint(x: 600, y: 620))
    bell.closeSubpath()
    ctx.addPath(bell)
    ctx.fillPath()

    roundedBar(ctx, halfWidth: 42, top: 448, bottom: 482, radius: 8)

    for i in 0..<6 {
        let top = 448 - CGFloat(i + 1) * 20
        roundedBar(ctx, halfWidth: 34 - CGFloat(i) * 4, top: top, bottom: top + 23, radius: 8)
    }

    let spire = CGMutablePath()
    spire.move(to: CGPoint(x: 512, y: 150))
    spire.addLine(to: CGPoint(x: 525, y: 334))
    spire.addLine(to: CGPoint(x: 499, y: 334))
    spire.closeSubpath()
    ctx.addPath(spire)
    ctx.fillPath()
}

func draw(_ ctx: CGContext, _ p: Palette) {
    ctx.translateBy(x: 0, y: S)
    ctx.scaleBy(x: 1, y: -1)
    let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

    let sky = CGGradient(colorsSpace: srgb, colors: p.sky as CFArray, locations: [0, 0.45, 0.75])!
    ctx.drawLinearGradient(sky, start: .zero, end: CGPoint(x: 0, y: S), options: [.drawsAfterEndLocation])

    let glow = CGGradient(colorsSpace: srgb, colors: [p.glow, p.glow.copy(alpha: 0)!] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: p.glowCenter, startRadius: 160, endCenter: p.glowCenter, endRadius: 440, options: [.drawsBeforeStartLocation])

    ctx.setFillColor(p.sun)
    ctx.fillEllipse(in: CGRect(x: p.sunCenter.x - p.sunRadius, y: p.sunCenter.y - p.sunRadius,
                               width: p.sunRadius * 2, height: p.sunRadius * 2))

    drawChedi(ctx, color: p.temple)

    wave(ctx, baseY: 748, amp: 18, length: 512, phase: 0, color: p.waves[0])
    wave(ctx, baseY: 822, amp: 16, length: 400, phase: 1.6, color: p.waves[1])
    wave(ctx, baseY: 898, amp: 14, length: 340, phase: 3.1, color: p.waves[2])

    ctx.setStrokeColor(p.glint)
    ctx.setLineCap(.round)
    ctx.setLineWidth(9)
    for (y, half) in [(794.0, 64.0), (862.0, 42.0), (936.0, 22.0)] {
        ctx.move(to: CGPoint(x: 512 - half, y: y))
        ctx.addLine(to: CGPoint(x: 512 + half, y: y))
    }
    ctx.strokePath()
}

func render(_ palette: Palette, gray: Bool, to path: String) {
    let space = gray ? CGColorSpaceCreateDeviceGray() : CGColorSpace(name: CGColorSpace.sRGB)!
    let alpha = gray ? CGImageAlphaInfo.none : CGImageAlphaInfo.noneSkipLast
    guard let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0,
                              space: space, bitmapInfo: alpha.rawValue) else { fatalError("context") }
    draw(ctx, palette)
    let url = URL(fileURLWithPath: path)
    guard let image = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fatalError("image") }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("write \(path)") }
    print("wrote \(path)")
}

// usage: swift Tools/make-icon.swift [out dir]   (run from the repo root)
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Journey/Assets.xcassets/AppIcon.appiconset"
render(day, gray: false, to: "\(out)/AppIcon.png")
render(night, gray: false, to: "\(out)/AppIcon-Dark.png")
render(night, gray: true, to: "\(out)/AppIcon-Tinted.png")
