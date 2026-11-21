import Carbon.HIToolbox

/// A system-wide hotkey registered through Carbon. Needs no Accessibility permission.
@MainActor
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    /// - Parameters:
    ///   - keyCode: A virtual key code such as `kVK_Space`.
    ///   - modifiers: Carbon modifier flags such as `optionKey | cmdKey`.
    init?(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        self.action = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
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

        let id = EventHotKeyID(signature: OSType(0x5357_4354), id: 1) // "SWCT"
        let registered = RegisterEventHotKey(
            UInt32(keyCode),
            UInt32(modifiers),
            id,
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
