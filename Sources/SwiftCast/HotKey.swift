import Carbon.HIToolbox

/// A system-wide hotkey registered through Carbon. Needs no Accessibility permission.
@MainActor
final class HotKey {
    /// The last ID handed out; each hotkey's handler acts only on presses of its own ID.
    private static var lastID: UInt32 = 0

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let id: UInt32
    private let action: () -> Void

    /// - Parameters:
    ///   - keyCode: A virtual key code such as `kVK_Space`.
    ///   - modifiers: Carbon modifier flags such as `optionKey | cmdKey`.
    init?(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        self.action = action
        Self.lastID += 1
        id = Self.lastID

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
                var pressed = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed)
                // Another of SwiftCast's hotkeys: let its own handler take it.
                guard status == noErr, MainActor.assumeIsolated({ pressed.id == hotKey.id }) else {
                    return OSStatus(eventNotHandledErr)
                }
                let eventTime = GetEventTime(event)
                MainActor.assumeIsolated {
                    PerfLog.mark("hotkey", eventTime: eventTime)
                    hotKey.action()
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        guard status == noErr else { return nil }

        let hotKeyID = EventHotKeyID(signature: OSType(0x5357_4354), id: id) // "SWCT"
        let registered = RegisterEventHotKey(
            UInt32(keyCode),
            UInt32(modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard registered == noErr else {
            RemoveEventHandler(handlerRef)
            return nil
        }
    }

    isolated deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
