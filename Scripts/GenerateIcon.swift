#!/usr/bin/env swift

// Renders the WhisperLocal app icon to a 1024x1024 PNG.
// Usage: swift Scripts/GenerateIcon.swift Resources/icon.png

import AppKit
import CoreGraphics

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write("usage: GenerateIcon.swift <out.png>\n".data(using: .utf8)!)
    exit(1)
}

let outURL = URL(fileURLWithPath: CommandLine.arguments[1])
let size: CGFloat = 1024
let rect = NSRect(x: 0, y: 0, width: size, height: size)

let image = NSImage(size: rect.size)
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// 1. Rounded-square mask
let cornerRadius = size * 0.2237            // Apple's macOS icon mask radius
let bgPath = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
ctx.saveGState()
bgPath.addClip()

// 2. Diagonal gradient: deep purple → vivid cyan
let gradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.40, green: 0.30, blue: 1.00, alpha: 1.0),
    NSColor(calibratedRed: 0.10, green: 0.55, blue: 1.00, alpha: 1.0),
    NSColor(calibratedRed: 0.00, green: 0.80, blue: 1.00, alpha: 1.0),
])!
gradient.draw(in: rect, angle: -45)

// 3. Subtle radial highlight top-left for depth
let highlight = NSGradient(colors: [
    NSColor(white: 1.0, alpha: 0.18),
    NSColor(white: 1.0, alpha: 0.0),
])!
highlight.draw(fromCenter: NSPoint(x: size * 0.3, y: size * 0.75),
               radius: 0,
               toCenter: NSPoint(x: size * 0.3, y: size * 0.75),
               radius: size * 0.55,
               options: [])

// 4. Microphone body (vertical pill, white). NSGraphicsContext origin is
// bottom-left, so larger y = higher up. Mic body sits in the upper half.
let micW = size * 0.21
let micH = size * 0.345
let centerX = size / 2
let micBottom = size * 0.40
let micRect = NSRect(x: centerX - micW/2, y: micBottom, width: micW, height: micH)
let micPath = NSBezierPath(roundedRect: micRect, xRadius: micW/2, yRadius: micW/2)
NSColor.white.setFill()
micPath.fill()

// 5. Microphone stand — U-shape opening UPWARD, cradling the mic.
let stroke = size * 0.035
let standArcCenterY = micBottom + stroke * 0.5    // just under the mic body
let standArcRadius = size * 0.17
let standPath = NSBezierPath()
standPath.appendArc(
    withCenter: NSPoint(x: centerX, y: standArcCenterY),
    radius: standArcRadius,
    startAngle: 180,           // left side
    endAngle: 360,             // right side, sweeping through the bottom
    clockwise: false
)
NSColor.white.setStroke()
standPath.lineWidth = stroke
standPath.lineCapStyle = .round
standPath.stroke()

// Vertical post hanging down from the U's lowest point to the base.
let postBottom = size * 0.18
let postTop = standArcCenterY - standArcRadius + stroke/2
let postX = centerX - stroke / 2
NSBezierPath(rect: NSRect(x: postX, y: postBottom, width: stroke, height: postTop - postBottom)).fill()

// Horizontal base.
let baseWidth = size * 0.16
let basePath = NSBezierPath(
    roundedRect: NSRect(x: centerX - baseWidth/2, y: postBottom - stroke,
                        width: baseWidth, height: stroke),
    xRadius: stroke/2, yRadius: stroke/2
)
basePath.fill()

// 6. Soundwave arcs (left + right of microphone)
func drawWaves(center: NSPoint, mirrored: Bool) {
    let baseRadius = size * 0.16
    let radii: [CGFloat] = [baseRadius, baseRadius * 1.35, baseRadius * 1.7]
    let opacities: [CGFloat] = [0.85, 0.55, 0.30]
    let arcSpan: CGFloat = 50
    let baseAngle: CGFloat = mirrored ? 180 : 0
    for (i, r) in radii.enumerated() {
        NSColor(white: 1.0, alpha: opacities[i]).setStroke()
        let path = NSBezierPath()
        path.appendArc(
            withCenter: center,
            radius: r,
            startAngle: baseAngle - arcSpan,
            endAngle: baseAngle + arcSpan,
            clockwise: false
        )
        path.lineWidth = size * 0.022
        path.lineCapStyle = .round
        path.stroke()
    }
}

let waveCenter = NSPoint(x: size / 2, y: size * 0.55)
drawWaves(center: waveCenter, mirrored: false)   // right side
drawWaves(center: waveCenter, mirrored: true)    // left side

ctx.restoreGState()

// 7. Subtle inset stroke for crisp edge
NSColor(white: 0, alpha: 0.10).setStroke()
let innerStrokeWidth: CGFloat = 2
let innerRect = rect.insetBy(dx: innerStrokeWidth/2, dy: innerStrokeWidth/2)
let innerPath = NSBezierPath(
    roundedRect: innerRect,
    xRadius: cornerRadius - innerStrokeWidth/2,
    yRadius: cornerRadius - innerStrokeWidth/2
)
innerPath.lineWidth = innerStrokeWidth
innerPath.stroke()

image.unlockFocus()

// Save as PNG
guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:])
else {
    FileHandle.standardError.write("failed to encode PNG\n".data(using: .utf8)!)
    exit(2)
}
try png.write(to: outURL)
print("wrote \(outURL.path) (\(png.count) bytes)")
