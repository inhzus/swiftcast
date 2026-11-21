import AppKit

/// Borderless floating panel that hosts the launcher UI. Its top edge stays put while its
/// height follows the content (see `setHeight(_:)`).
final class LauncherPanel: NSPanel {
    static let width: CGFloat = 680

    var onCancel: () -> Void = {}

    init(content: NSView) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 60),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        // Appear in a single frame instead of fading in.
        animationBehavior = .none

        let background = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: Self.width, height: 60))
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 14
        background.layer?.masksToBounds = true
        background.autoresizingMask = [.width, .height]

        content.frame = background.bounds
        content.autoresizingMask = [.width, .height]
        background.addSubview(content)

        contentView = background
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel()
    }

    /// Centers the panel horizontally, its top a fifth of the way down the screen under the mouse.
    func positionOnActiveScreen() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
            ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let top = visible.maxY - visible.height * 0.2
        setFrameOrigin(NSPoint(x: visible.midX - Self.width / 2, y: top - frame.height))
    }

    /// Resizes the panel, keeping its top edge in place.
    func setHeight(_ height: CGFloat) {
        guard frame.height != height else { return }
        var newFrame = frame
        newFrame.origin.y += newFrame.height - height
        newFrame.size.height = height
        setFrame(newFrame, display: isVisible)
        // The shadow follows the window's shape, which just changed.
        invalidateShadow()
    }
}
