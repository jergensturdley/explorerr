// Renders the Explorerr app icon (Win11 folder on a Fluent-blue rounded square)
// into an .iconset and runs iconutil to produce AppIcon.icns.
// Run: swift scripts/gen-icon.swift

import AppKit
import CoreGraphics

func renderIcon(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { return img }
    let s = size

    // Rounded-square background (Win11 accent blue gradient)
    let bgRect = CGRect(x: 0, y: 0, width: s, height: s)
    let bgPath = CGPath(roundedRect: bgRect, cornerWidth: s * 0.225, cornerHeight: s * 0.225, transform: nil)
    let bgColors = [
        CGColor(red: 0.10, green: 0.45, blue: 0.86, alpha: 1),
        CGColor(red: 0.05, green: 0.30, blue: 0.68, alpha: 1),
    ]
    if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: bgColors as CFArray, locations: [0, 1]) {
        ctx.addPath(bgPath)
        ctx.saveGState()
        ctx.clip()
        // vertical gradient
        ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])
        ctx.restoreGState()
    }

    // Folder geometry (square-ish, centered)
    let fw = s * 0.74, fh = s * 0.60
    let fx = (s - fw) / 2, fy = s * 0.17

    func rounded(_ rect: CGRect, r: CGFloat) -> CGPath {
        CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
    }

    // Shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.03), blur: s * 0.045,
                  color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.35))
    // Back: tab + body, darker gold
    let tab = CGRect(x: fx, y: fy + fh * 0.72, width: fw * 0.44, height: fh * 0.28)
    ctx.addPath(rounded(tab, r: s * 0.02))
    let body = CGRect(x: fx, y: fy, width: fw, height: fh * 0.84)
    ctx.addPath(rounded(body, r: s * 0.025))
    ctx.setFillColor(CGColor(red: 0.83, green: 0.53, blue: 0.15, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    // Front face gradient gold
    let front = CGRect(x: fx, y: fy, width: fw, height: fh * 0.72)
    let frontPath = rounded(front, r: s * 0.025)
    if let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [CGColor(red: 1.0, green: 0.88, blue: 0.52, alpha: 1), CGColor(red: 1.0, green: 0.76, blue: 0.30, alpha: 1)] as CFArray, locations: [0, 1]) {
        ctx.saveGState()
        ctx.addPath(frontPath)
        ctx.clip()
        ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: fy + front.height), end: CGPoint(x: 0, y: fy), options: [])
        ctx.restoreGState()
    }

    // Top highlight line
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.55))
    ctx.setLineWidth(s * 0.012)
    ctx.addPath(CGPath(roundedRect: CGRect(x: fx + fw * 0.01, y: fy + front.height - s * 0.012, width: fw * 0.98, height: s * 0.012),
                       cornerWidth: s * 0.006, cornerHeight: s * 0.006, transform: nil))
    ctx.strokePath()

    img.unlockFocus()
    return img
}

let sizes: [(String, CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

let fm = FileManager.default
let iconset = URL(fileURLWithPath: "build/AppIcon.iconset", isDirectory: true)
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)

for (name, px) in sizes {
    let image = renderIcon(size: CGFloat(px))
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("png encode failed for \(name)")
    }
    try! png.write(to: iconset.appendingPathComponent("\(name).png"))
}
print("iconset written to \(iconset.path)")
