import AppKit
import Carbon

/// Registers a system-wide hotkey via the Carbon Event Manager —
/// no accessibility or input-monitoring permission required.
/// The manager is passed unretained into the C callback, so it
/// creates no retain cycle.
final class HotKeyManager {
    static let shared = HotKeyManager()

    struct Preset: Equatable {
        let name: String
        let keyCode: UInt32
        let modifiers: UInt32

        static let all: [Preset] = [
            Preset(name: "⌘⇧V", keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey) | UInt32(shiftKey)),
            Preset(name: "⌥V", keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(optionKey)),
            Preset(name: "⌃⌥V", keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(controlKey) | UInt32(optionKey)),
            Preset(name: "⌘⇧C", keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(cmdKey) | UInt32(shiftKey)),
        ]
    }

    var onHotKey: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    private init() {}

    func register(preset: Preset) {
        unregister()

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        let handler: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var pressedID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &pressedID
            )
            guard status == noErr else { return status }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                manager.onHotKey?()
            }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventSpec,
            selfPointer,
            &handlerRef
        )

        let hotKeyID = EventHotKeyID(signature: OSType(0x4353544B), id: 1) // 'CSTK'
        RegisterEventHotKey(
            preset.keyCode,
            preset.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }

    deinit {
        unregister()
    }
}
