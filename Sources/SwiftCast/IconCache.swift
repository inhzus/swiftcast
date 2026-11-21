import AppKit

/// Caches app icons by path, pre-rendered to small bitmaps so drawing a row never rasterizes
/// a full-size icon on the main thread.
@MainActor
final class IconCache {
    static let shared = IconCache()

    nonisolated private static let pointSize = NSSize(width: 32, height: 32)
    private var icons: [String: NSImage] = [:]

    /// Returns the cached icon, rendering it synchronously on a miss.
    func icon(for path: String) -> NSImage {
        if let icon = icons[path] { return icon }
        let icon = Self.image(from: Self.render(path)) ?? NSWorkspace.shared.icon(forFile: path)
        icons[path] = icon
        return icon
    }

    /// Renders icons for paths not cached yet, off the main thread.
    func preload(_ paths: [String]) async {
        let missing = paths.filter { icons[$0] == nil }
        guard !missing.isEmpty else { return }
        let rendered = await Task.detached(priority: .utility) {
            missing.compactMap { path in Self.render(path).map { (path, $0) } }
        }.value
        for (path, cgImage) in rendered where icons[path] == nil {
            icons[path] = Self.image(from: cgImage)
        }
    }

    private static func image(from cgImage: CGImage?) -> NSImage? {
        cgImage.map { NSImage(cgImage: $0, size: pointSize) }
    }

    /// Draws the file's icon into a 2x bitmap of `pointSize`. Safe to call off the main thread.
    nonisolated private static func render(_ path: String) -> CGImage? {
        let pixels = Int(pointSize.width * 2)
        guard let context = CGContext(
            data: nil,
            width: pixels,
            height: pixels,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Resolve symlinks (e.g. /Applications/Safari.app), whose icons carry an alias badge.
        let icon = NSWorkspace.shared.icon(forFile: URL(filePath: path).resolvingSymlinksInPath().path)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        icon.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }
}
