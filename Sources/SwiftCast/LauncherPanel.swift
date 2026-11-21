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

        let background = BorderedEffectView(frame: NSRect(x: 0, y: 0, width: Self.width, height: 60))
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 14
        background.layer?.masksToBounds = true
        background.updateBorder()
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

    /// Edit commands for the search field, and ⌘Q. These normally come from the main menu,
    /// which an accessory app's non-activating panel never gets to use.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.type == .keyDown, flags == .command {
            let action: Selector? = switch event.charactersIgnoringModifiers {
            case "a": #selector(NSText.selectAll(_:))
            case "c": #selector(NSText.copy(_:))
            case "v": #selector(NSText.paste(_:))
            case "x": #selector(NSText.cut(_:))
            case "q": #selector(NSApplication.terminate(_:))
            default: nil
            }
            if let action, NSApp.sendAction(action, to: nil, from: self) {
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
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

/// The panel's frosted background, with a hairline border that adapts to light and dark.
private final class BorderedEffectView: NSVisualEffectView {
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBorder()
    }

    /// A CGColor doesn't follow the appearance, so it's resolved again on every change.
    func updateBorder() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.borderWidth = 1
            layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.12).cgColor
        }
    }
}
