import AppKit

/// The menu bar icon: the app icon's glyph (a magnifying glass with a spark in the lens) as a
/// template image, so the menu bar tints it for light, dark and highlighted states. Drawn as
/// vectors, so it's sharp at any scale.
enum StatusIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            draw()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "SwiftCast"
        return image
    }()

    private static func draw() {
        NSColor.black.set()

        let lens = NSPoint(x: 7.5, y: 10.5)
        let radius: CGFloat = 5.4
        let ring = NSBezierPath(ovalIn: NSRect(
            x: lens.x - radius, y: lens.y - radius, width: radius * 2, height: radius * 2
        ))
        ring.lineWidth = 1.7
        ring.stroke()

        // Handle, from the ring's lower right edge.
        let angle = -CGFloat.pi / 4
        let start = NSPoint(x: lens.x + cos(angle) * (radius + 0.5), y: lens.y + sin(angle) * (radius + 0.5))
        let handle = NSBezierPath()
        handle.move(to: start)
        handle.line(to: NSPoint(x: start.x + cos(angle) * 4.6, y: start.y + sin(angle) * 4.6))
        handle.lineWidth = 2.4
        handle.lineCapStyle = .round
        handle.stroke()

        sparkle(center: lens, radius: 3.2).fill()
    }

    /// A four-pointed star with concave sides, as in the app icon.
    private static func sparkle(center: NSPoint, radius r: CGFloat) -> NSBezierPath {
        let tips = [NSPoint(x: 0, y: r), NSPoint(x: r, y: 0), NSPoint(x: 0, y: -r), NSPoint(x: -r, y: 0)]
        let pinch = r * 0.2
        let path = NSBezierPath()
        path.move(to: NSPoint(x: center.x + tips[0].x, y: center.y + tips[0].y))
        for i in 0..<4 {
            let from = tips[i], to = tips[(i + 1) % 4]
            let control = NSPoint(
                x: center.x + pinch * (from.x + to.x) / r,
                y: center.y + pinch * (from.y + to.y) / r
            )
            path.curve(to: NSPoint(x: center.x + to.x, y: center.y + to.y), controlPoint1: control, controlPoint2: control)
        }
        path.close()
        return path
    }
}
