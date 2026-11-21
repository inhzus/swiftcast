import AppKit

/// Rounded surfaces for the launcher: Liquid Glass on macOS 26 and later, a frosted
/// `NSVisualEffectView` before that.
@MainActor
enum GlassSurface {
    /// A surface with `cornerRadius`, and the view its content goes in. The content view
    /// always fills the surface.
    static func make(cornerRadius: CGFloat) -> (surface: NSView, content: NSView) {
        let content = NSView()
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = cornerRadius
            glass.contentView = content
            return (glass, content)
        }
        let effect = NSVisualEffectView()
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = cornerRadius
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        content.autoresizingMask = [.width, .height]
        effect.addSubview(content)
        return (effect, content)
    }

    /// Groups surfaces so glass renders them together, and the view they go in. Spacing 0
    /// keeps the capsule and card from melting into each other.
    static func container() -> (container: NSView, content: NSView) {
        let content = NSView()
        if #available(macOS 26.0, *) {
            let container = NSGlassEffectContainerView()
            container.spacing = 0
            container.contentView = content
            return (container, content)
        }
        let container = NSView()
        content.autoresizingMask = [.width, .height]
        container.addSubview(content)
        return (container, content)
    }
}
