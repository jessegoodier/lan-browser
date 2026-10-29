// Renders a 1024×1024 opaque app icon: "LAN" in gold on dark gray.
// Usage: swift Scripts/make_icon.swift LANBrowser/Assets.xcassets/AppIcon.appiconset/AppIcon.png
import AppKit
import CoreText

let size = 1024
let out = CommandLine.arguments[1]
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

// Dark gray background, slightly lighter at the top.
let background = CGGradient(colorsSpace: space, colors: [rgb(0x3A3A3D), rgb(0x1E1E20)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(background, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])

// "LAN" in the heaviest system font, sized to about 72% of the icon width.
let base = NSFont.systemFont(ofSize: 100, weight: .black)
let rounded = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 100) } ?? base
func line(_ font: NSFont) -> CTLine {
    CTLineCreateWithAttributedString(NSAttributedString(string: "LAN", attributes: [.font: font, .kern: 4]))
}
let probe = CTLineGetImageBounds(line(rounded), ctx)
let pointSize = 100 * (CGFloat(size) * 0.72) / probe.width
let font = NSFont(descriptor: rounded.fontDescriptor, size: pointSize)!
let text = line(font)
let bounds = CTLineGetImageBounds(text, ctx)
let origin = CGPoint(x: (CGFloat(size) - bounds.width) / 2 - bounds.minX,
                     y: (CGFloat(size) - bounds.height) / 2 - bounds.minY)

// Soft shadow under the letters for depth.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: CGColor(gray: 0, alpha: 0.55))
ctx.setFillColor(rgb(0xC99A2E))
ctx.textPosition = origin
CTLineDraw(text, ctx)
ctx.restoreGState()

// Gold gradient clipped to the letters.
ctx.saveGState()
ctx.setTextDrawingMode(.clip)
ctx.textPosition = origin
CTLineDraw(text, ctx)
let gold = CGGradient(colorsSpace: space, colors: [rgb(0xFBE7A1), rgb(0xE2B84E), rgb(0xB8862B)] as CFArray,
                      locations: [0, 0.5, 1])!
ctx.drawLinearGradient(gold, start: CGPoint(x: 0, y: origin.y + bounds.maxY), end: CGPoint(x: 0, y: origin.y + bounds.minY), options: [])
ctx.restoreGState()

let image = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
precondition(CGImageDestinationFinalize(dest), "Could not write \(out)")
print("Wrote \(out)")
