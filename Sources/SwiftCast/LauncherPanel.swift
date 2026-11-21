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

    // MARK: - Placement

    /// Where the panel opens; `onPlacementChange` reports a new one after a drag.
    var placement = LauncherPlacement.default
    var onPlacementChange: (LauncherPlacement) -> Void = { _ in }

    /// How close, in points, a drag has to come to the default center or height to snap to it.
    private static let snapDistance: CGFloat = 12
    /// The origin when the current drag started; nil when not dragging.
    private var dragStart: NSPoint?
    private var snapped = (x: false, y: false)

    /// Places the panel at `placement` on the screen under the mouse.
    func positionOnActiveScreen() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })
            ?? NSScreen.main else { return }
        setFrameOrigin(origin(for: placement, in: screen.visibleFrame))
    }

    func beginDrag() {
        dragStart = frame.origin
        snapped = (false, false)
    }

    /// Moves the panel `offset` from where the drag started, snapping each axis to the
    /// default placement when it comes within `snapDistance`.
    func drag(by offset: NSSize) {
        guard let dragStart else { return }
        var origin = NSPoint(x: dragStart.x + offset.width, y: dragStart.y + offset.height)
        let capsuleCenter = NSPoint(
            x: origin.x + frame.width / 2,
            y: origin.y + frame.height - LauncherViewController.margin - LauncherViewController.capsuleHeight / 2
        )
        guard let screen = NSScreen.screens.first(where: { NSPointInRect(capsuleCenter, $0.frame) })
            ?? screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let target = self.origin(for: .default, in: visible)
        let snapX = abs(origin.x - target.x) <= Self.snapDistance
        let snapY = abs(origin.y - target.y) <= Self.snapDistance
        if snapX { origin.x = target.x }
        if snapY { origin.y = target.y }
        if (snapX && !snapped.x) || (snapY && !snapped.y) {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        snapped = (snapX, snapY)
        setFrameOrigin(clamped(origin, in: visible))
    }

    /// Saves where a drag left the panel. A snapped axis is saved as the default exactly, so
    /// it stays centered on screens of any size.
    func endDrag() {
        defer { dragStart = nil }
        guard let dragStart, frame.origin != dragStart, let visible = screen?.visibleFrame else { return }
        let capsuleTop = frame.maxY - LauncherViewController.margin
        placement = LauncherPlacement(
            centerX: snapped.x ? LauncherPlacement.default.centerX : (frame.midX - visible.minX) / visible.width,
            topFromTop: snapped.y ? LauncherPlacement.default.topFromTop : (visible.maxY - capsuleTop) / visible.height
        )
        onPlacementChange(placement)
    }

    /// Moves the panel back to the default placement.
    func resetPlacement() {
        placement = .default
        onPlacementChange(placement)
        if let visible = screen?.visibleFrame {
            setFrameOrigin(origin(for: placement, in: visible))
        }
    }

    /// The origin that puts the capsule at `placement` within `visible`.
    private func origin(for placement: LauncherPlacement, in visible: NSRect) -> NSPoint {
        let capsuleMidX = visible.minX + visible.width * placement.centerX
        let capsuleTop = visible.maxY - visible.height * placement.topFromTop
        return clamped(
            NSPoint(x: capsuleMidX - frame.width / 2, y: capsuleTop + LauncherViewController.margin - frame.height),
            in: visible
        )
    }

    /// Keeps the capsule inside `visible`; the transparent margins may go past it.
    private func clamped(_ origin: NSPoint, in visible: NSRect) -> NSPoint {
        let margin = LauncherViewController.margin
        let capsuleHeight = LauncherViewController.capsuleHeight
        return NSPoint(
            x: min(max(origin.x, visible.minX - margin), visible.maxX + margin - frame.width),
            y: min(
                max(origin.y, visible.minY + capsuleHeight + margin - frame.height),
                visible.maxY + margin - frame.height
            )
        )
    }
}

/// Where the launcher's search capsule sits, as fractions of the screen's visible frame: its
/// center from the left, and its top from the top. Fractions carry over to any screen.
struct LauncherPlacement: Codable, Equatable {
    var centerX: Double
    var topFromTop: Double

    static let `default` = LauncherPlacement(centerX: 0.5, topFromTop: 0.2)
}

/// The search capsule's background: dragging it moves the panel, double-clicking it puts the
/// panel back in its default place. The search field and clear button keep their own clicks.
final class DragHandleView: NSView {
    override func mouseDown(with event: NSEvent) {
        guard let panel = window as? LauncherPanel else { return super.mouseDown(with: event) }
        if event.clickCount == 2 {
            panel.resetPlacement()
            return
        }
        let start = NSEvent.mouseLocation
        panel.beginDrag()
        panel.trackEvents(
            matching: [.leftMouseDragged, .leftMouseUp],
            timeout: NSEvent.foreverDuration,
            mode: .eventTracking
        ) { event, stop in
            guard let event else { return }
            MainActor.assumeIsolated {
                if event.type == .leftMouseUp {
                    panel.endDrag()
                    stop.pointee = true
                    return
                }
                let mouse = NSEvent.mouseLocation
                panel.drag(by: NSSize(width: mouse.x - start.x, height: mouse.y - start.y))
            }
        }
    }
}
