import AppKit

/// Liquid Glass surfaces for the launcher.
@MainActor
enum GlassSurface {
    /// A surface with `cornerRadius`, and the view its content goes in. The content view
    /// always fills the surface.
    static func make(cornerRadius: CGFloat) -> (surface: NSView, content: NSView) {
        let content = NSView()
        let glass = NSGlassEffectView()
        glass.cornerRadius = cornerRadius
        glass.contentView = content
        return (glass, content)
    }

    /// Groups surfaces so glass renders them together, and the view they go in. Spacing 0
    /// keeps the capsule and card from melting into each other.
    static func container() -> (container: NSView, content: NSView) {
        let content = NSView()
        let container = NSGlassEffectContainerView()
        container.spacing = 0
        container.contentView = content
        return (container, content)
    }
}
