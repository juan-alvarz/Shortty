import Carbon.HIToolbox

/// Registers global hotkeys via Carbon, one per `CaptureAction`. No Accessibility permission needed.
final class HotkeyManager {
    static let shared = HotkeyManager()

    var onPress: ((CaptureAction) -> Void)?
    private var registered: [EventHotKeyRef] = []
    private var handlerRef: EventHandlerRef?

    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handler: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated {
                if let action = CaptureAction.allCases.first(where: { $0.hotkeyID == hotKeyID.id }) {
                    manager.onPress?(action)
                }
            }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &spec,
                            Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }

    /// Replaces all registrations. `.none` hotkeys are skipped.
    func register(_ hotkeys: [CaptureAction: Hotkey]) {
        unregisterAll()
        for (action, hotkey) in hotkeys where !hotkey.isNone {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: 0x5348_5254 /* 'SHRT' */, id: action.hotkeyID)
            if RegisterEventHotKey(hotkey.keyCode, hotkey.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr,
               let ref {
                registered.append(ref)
            }
        }
    }

    func unregisterAll() {
        registered.forEach { UnregisterEventHotKey($0) }
        registered.removeAll()
    }
}
