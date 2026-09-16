#!/usr/bin/env swift
// Generates a 1024x1024 app icon PNG for NightCat using CoreGraphics
// (headless-safe, no window server needed). The mark is a black cat
// silhouette against a night sky with an orange crescent moon — night +
// cat, with the moon in the lid tier's orange and the eyes in the idle
// tier's teal so the icon carries the app's own tier palette.
// Run: swift scripts/make_icon.swift Resources/icon_1024.png
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"

guard let ctx = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("ctx") }

let s = CGFloat(size)
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: r/255, green: g/255, blue: b/255, alpha: a)
}

// Rounded-rect background with a vertical gradient (night indigo -> near black).
let inset: CGFloat = s * 0.06
let rect = CGRect(x: inset, y: inset, width: s - inset*2, height: s - inset*2)
let radius = (s - inset*2) * 0.235
let cs = CGColorSpaceCreateDeviceRGB()
let bgGrad = CGGradient(colorsSpace: cs,
                        colors: [rgb(52, 44, 104), rgb(10, 9, 30)] as CFArray,
                        locations: [0, 1])!

func drawBackgroundGradient() {
    ctx.drawLinearGradient(bgGrad, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])
}

ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
ctx.clip()
drawBackgroundGradient()

// Stars (kept clear of the moon and the cat).
let stars: [(x: CGFloat, y: CGFloat, r: CGFloat, a: CGFloat)] = [
    (250, 850, 6.0, 0.9), (180, 620, 4.0, 0.6), (860, 470, 5.0, 0.75),
    (320, 320, 4.0, 0.5), (880, 880, 3.5, 0.8)
]
for star in stars {
    ctx.setFillColor(rgb(244, 247, 255, star.a))
    ctx.fillEllipse(in: CGRect(x: star.x - star.r, y: star.y - star.r,
                               width: star.r*2, height: star.r*2))
}

// Crescent moon: fill the disc with a warm radial gradient, then repaint the
// bite area with the *same* background gradient — the repaint is pixel-
// identical to what's underneath, so the seam is invisible and the crescent
// needs no hand-computed intersection arcs.
let moonC = CGPoint(x: 712, y: 715), moonR: CGFloat = 148
let moonGrad = CGGradient(colorsSpace: cs,
                          colors: [rgb(255, 200, 90), rgb(239, 159, 39)] as CFArray,
                          locations: [0, 1])!
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: moonC.x - moonR, y: moonC.y - moonR, width: moonR*2, height: moonR*2))
ctx.clip()
ctx.drawRadialGradient(moonGrad,
                       startCenter: CGPoint(x: moonC.x - moonR*0.25, y: moonC.y + moonR*0.25),
                       startRadius: 0, endCenter: moonC, endRadius: moonR,
                       options: [.drawsAfterEndLocation])
ctx.restoreGState()

let biteC = CGPoint(x: 790, y: 772), biteR: CGFloat = 126
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: biteC.x - biteR, y: biteC.y - biteR, width: biteR*2, height: biteR*2))
ctx.clip()
drawBackgroundGradient()
ctx.restoreGState()

// Cat silhouette (seated, back to us, looking up at the moon): a bell body,
// a round head, two triangle ears, and a curled tail. Painted after the moon
// so an ear tip crossing it reads as sitting in front of it.
let cat = rgb(10, 9, 26)
ctx.setFillColor(cat)

let body = CGMutablePath()
body.move(to: CGPoint(x: 350, y: 0))
body.addQuadCurve(to: CGPoint(x: 515, y: 420), control: CGPoint(x: 365, y: 300))
body.addQuadCurve(to: CGPoint(x: 680, y: 0), control: CGPoint(x: 665, y: 300))
body.closeSubpath()
ctx.addPath(body)
ctx.fillPath()

ctx.fillEllipse(in: CGRect(x: 515 - 132, y: 548 - 132, width: 264, height: 264))  // head

let ears: [(root1: CGPoint, tip: CGPoint, root2: CGPoint)] = [
    (CGPoint(x: 448, y: 640), CGPoint(x: 426, y: 800), CGPoint(x: 516, y: 678)),
    (CGPoint(x: 582, y: 640), CGPoint(x: 604, y: 800), CGPoint(x: 514, y: 678))
]
for ear_ in ears {
    let ear = CGMutablePath()
    ear.move(to: ear_.root1)
    ear.addLine(to: ear_.tip)
    ear.addLine(to: ear_.root2)
    ear.closeSubpath()
    ctx.addPath(ear)
    ctx.fillPath()
}

let tail = CGMutablePath()
tail.move(to: CGPoint(x: 640, y: 80))   // starts inside the body so it reads attached
tail.addCurve(to: CGPoint(x: 720, y: 330),
              control1: CGPoint(x: 830, y: 90), control2: CGPoint(x: 870, y: 260))
ctx.addPath(tail)
ctx.setLineWidth(46)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
ctx.strokePath()

// Eyes glowing in the idle tier's teal: a soft halo under a bright core.
for eyeX in [468.0, 562.0] {
    ctx.setFillColor(rgb(93, 202, 165, 0.35))
    ctx.fillEllipse(in: CGRect(x: eyeX - 30, y: 566 - 36, width: 60, height: 72))
    ctx.setFillColor(rgb(93, 202, 165))
    ctx.fillEllipse(in: CGRect(x: eyeX - 17, y: 566 - 22, width: 34, height: 44))
}

guard let img = ctx.makeImage() else { fatalError("img") }
let url = URL(fileURLWithPath: out)
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
else { fatalError("dest") }
CGImageDestinationAddImage(dest, img, nil)
if CGImageDestinationFinalize(dest) {
    print("wrote \(out)")
} else {
    fatalError("write failed")
}
