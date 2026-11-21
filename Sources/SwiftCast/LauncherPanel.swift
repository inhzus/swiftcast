import AppKit

/// Borderless floating panel that hosts the launcher UI.
///
/// It's one fixed size and fully transparent: the search capsule and results card inside it
/// change shape with Core Animation instead. Resizing a window costs one to two frames on
/// screen; clicks on the transparent parts fall through to whatever is below.
final class LauncherPanel: NSPanel {
    var onCancel: () -> Void = {}
    var onSettings: () -> Void = {}

    init(content: NSView) {
        super.init(
            contentRect: NSRect(origin: .zero, size: LauncherViewController.windowSize),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        // The surfaces draw their own shadows; a window shadow would outline the empty area.
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        // The content animates itself in; the window should just appear.
        animationBehavior = .none
        contentView = content
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel()
    }

    /// Edit commands for the search field, ⌘, and ⌘Q. These normally come from the main menu,
    /// which an accessory app's non-activating panel never gets to use.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.type == .keyDown, flags == .command {
            if event.charactersIgnoringModifiers == "," {
                onSettings()
                return true
            }
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

    /// Centers the panel horizontally, with the search capsule's top a fifth of the way down
    /// the screen under the mouse.
    func positionOnActiveScreen() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
            ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let capsuleTop = visible.maxY - visible.height * 0.2
        setFrameOrigin(NSPoint(
            x: visible.midX - frame.width / 2,
            y: capsuleTop + LauncherViewController.margin - frame.height
        ))
    }
}
