// Draws the app icon at 1024×1024 and writes it as a PNG: a magnifying glass with a spark on
// an indigo squircle, laid out on Apple's macOS icon grid (an 824 pt body with a shadow).
//
//   swift scripts/make-icon.swift <out.png>
//
// scripts/make-icon.sh turns that into Resources/AppIcon.icns.
import AppKit

let size: CGFloat = 1024
let body = CGRect(x: 100, y: 100, width: 824, height: 824)

/// A superellipse, which is close to the continuous-corner shape of macOS icons.
func squircle(in rect: CGRect, exponent n: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let a = rect.width / 2, b = rect.height / 2
    let steps = 720
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = rect.midX + a * copysign(pow(abs(c), 2 / n), c)
        let y = rect.midY + b * copysign(pow(abs(s), 2 / n), s)
        i == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
    }
    path.closeSubpath()
    return path
}

/// A four-pointed star with concave sides.
func sparkle(center: CGPoint, radius r: CGFloat) -> CGPath {
    // Tips clockwise from the top; each side bows in toward a point near the centre.
    let tips = [CGPoint(x: 0, y: r), CGPoint(x: r, y: 0), CGPoint(x: 0, y: -r), CGPoint(x: -r, y: 0)]
    let pinch = r * 0.14
    let path = CGMutablePath()
    path.move(to: center.offsetBy(tips[0].x, tips[0].y))
    for i in 0..<4 {
        let from = tips[i], to = tips[(i + 1) % 4]
        let control = center.offsetBy(pinch * ((from.x + to.x) / r), pinch * ((from.y + to.y) / r))
        path.addQuadCurve(to: center.offsetBy(to.x, to.y), control: control)
    }
    path.closeSubpath()
    return path
}

extension CGPoint {
    func offsetBy(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint { CGPoint(x: x + dx, y: y + dy) }
}

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func linear(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locations)!
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(
    data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
    space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!
let shape = squircle(in: body)

// Drop shadow under the body.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
ctx.addPath(shape)
ctx.setFillColor(color(0x2B1D8F))
ctx.fillPath()
ctx.restoreGState()

// Body: indigo to violet, lit from the top.
ctx.saveGState()
ctx.addPath(shape)
ctx.clip()
ctx.drawLinearGradient(
    linear([color(0x7B5CFF), color(0x4A33E0), color(0x23167A)], [0, 0.55, 1]),
    start: CGPoint(x: body.minX, y: body.maxY), end: CGPoint(x: body.maxX, y: body.minY), options: []
)
// Soft glow behind the lens.
ctx.drawRadialGradient(
    linear([color(0xB7A6FF, 0.45), color(0xB7A6FF, 0)], [0, 1]),
    startCenter: CGPoint(x: 470, y: 560), startRadius: 0,
    endCenter: CGPoint(x: 470, y: 560), endRadius: 420, options: []
)
// Top sheen.
ctx.drawLinearGradient(
    linear([color(0xFFFFFF, 0.22), color(0xFFFFFF, 0)], [0, 1]),
    start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.midY + 40), options: []
)
ctx.restoreGState()

// Inner rim: a thin light edge just inside the body.
ctx.saveGState()
ctx.addPath(shape)
ctx.clip()
ctx.addPath(squircle(in: body.insetBy(dx: 3, dy: 3)))
ctx.setStrokeColor(color(0xFFFFFF, 0.25))
ctx.setLineWidth(6)
ctx.strokePath()
ctx.restoreGState()

// Magnifying glass.
let lensCenter = CGPoint(x: 462, y: 566)
let lensRadius: CGFloat = 196
let ringWidth: CGFloat = 58
let handleAngle = -CGFloat.pi / 4
let handleStart = CGPoint(
    x: lensCenter.x + cos(handleAngle) * (lensRadius + ringWidth / 2 - 6),
    y: lensCenter.y + sin(handleAngle) * (lensRadius + ringWidth / 2 - 6)
)
let handleEnd = CGPoint(x: handleStart.x + cos(handleAngle) * 190, y: handleStart.y + sin(handleAngle) * 190)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: color(0x0E0740, 0.45))
ctx.beginTransparencyLayer(auxiliaryInfo: nil)

// Lens glass: faint fill with a highlight toward the top left.
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: lensCenter.x - lensRadius, y: lensCenter.y - lensRadius, width: lensRadius * 2, height: lensRadius * 2))
ctx.clip()
ctx.drawRadialGradient(
    linear([color(0xFFFFFF, 0.30), color(0xFFFFFF, 0.06)], [0, 1]),
    startCenter: lensCenter.offsetBy(-70, 80), startRadius: 0,
    endCenter: lensCenter, endRadius: lensRadius, options: [.drawsAfterEndLocation]
)
ctx.restoreGState()

// Handle, then ring, both white with a slight vertical shade.
let metal = linear([color(0xFFFFFF), color(0xE4DEFF)], [0, 1])
func fillShaded(_ path: CGPath) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let box = path.boundingBox
    ctx.drawLinearGradient(metal, start: CGPoint(x: 0, y: box.maxY), end: CGPoint(x: 0, y: box.minY), options: [])
    ctx.restoreGState()
}
let handle = CGMutablePath()
handle.move(to: handleStart)
handle.addLine(to: handleEnd)
fillShaded(handle.copy(strokingWithWidth: 92, lineCap: .round, lineJoin: .round, miterLimit: 10))

let ring = CGPath(
    ellipseIn: CGRect(x: lensCenter.x - lensRadius, y: lensCenter.y - lensRadius, width: lensRadius * 2, height: lensRadius * 2),
    transform: nil
).copy(strokingWithWidth: ringWidth, lineCap: .round, lineJoin: .round, miterLimit: 10)
fillShaded(ring)

// Spark inside the lens: the "fast" in the name.
fillShaded(sparkle(center: lensCenter.offsetBy(6, -4), radius: 104))
ctx.endTransparencyLayer()
ctx.restoreGState()

// A small companion spark outside, top right.
ctx.saveGState()
ctx.setShadow(offset: .zero, blur: 18, color: color(0xFFFFFF, 0.6))
ctx.addPath(sparkle(center: CGPoint(x: 724, y: 772), radius: 46))
ctx.setFillColor(color(0xFFFFFF, 0.95))
ctx.fillPath()
ctx.restoreGState()

let out = URL(filePath: CommandLine.arguments[1])
let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try rep.representation(using: .png, properties: [:])!.write(to: out)
