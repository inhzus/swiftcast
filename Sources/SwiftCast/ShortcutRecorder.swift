import AppKit
import SwiftCastCore
import SwiftUI

/// A button that shows a shortcut and, once clicked, records the next key combination.
struct ShortcutRecorder: NSViewRepresentable {
    var shortcut: Shortcut
    /// Called with a valid recorded shortcut.
    var onRecord: (Shortcut) -> Void
    /// Called when recording starts and stops, so the global hotkey can step aside meanwhile.
    var onRecordingChange: (Bool) -> Void

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.onRecord = onRecord
        button.onRecordingChange = onRecordingChange
        button.shortcut = shortcut
        return button
    }

    func updateNSView(_ button: RecorderButton, context: Context) {
        button.onRecord = onRecord
        button.onRecordingChange = onRecordingChange
        button.shortcut = shortcut
    }
}

final class RecorderButton: NSButton {
    var onRecord: (Shortcut) -> Void = { _ in }
    var onRecordingChange: (Bool) -> Void = { _ in }
    var shortcut = Shortcut.default {
        didSet { if shortcut != oldValue { updateTitle() } }
    }

    private var isRecording = false {
        didSet {
            guard isRecording != oldValue else { return }
            hint = nil
            updateTitle()
            onRecordingChange(isRecording)
        }
    }
    /// Shown in place of the prompt after an unusable combination.
    private var hint: String?

    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(toggleRecording)
        setContentHuggingPriority(.required, for: .horizontal)
        updateTitle()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var acceptsFirstResponder: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: max(super.intrinsicContentSize.width, 140), height: super.intrinsicContentSize.height)
    }

    @objc private func toggleRecording() {
        if isRecording {
            isRecording = false
        } else {
            window?.makeFirstResponder(self)
            isRecording = true
        }
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return super.keyDown(with: event) }
        record(event)
    }

    // ⌘ combinations arrive here rather than in `keyDown`.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording, event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        record(event)
        return true
    }

    private func record(_ event: NSEvent) {
        let candidate = Shortcut(event: event)
        if candidate.keyCode == 53, candidate.modifiers == 0 {  // Esc cancels
            isRecording = false
        } else if candidate.isValid {
            isRecording = false
            onRecord(candidate)
        } else {
            hint = "Add ⌘, ⌥ or ⌃"
            updateTitle()
        }
    }

    private func updateTitle() {
        title = isRecording ? (hint ?? "Type shortcut…") : shortcut.displayString
        invalidateIntrinsicContentSize()
    }
}
