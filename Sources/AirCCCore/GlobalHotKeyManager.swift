import Carbon
import Foundation

public final class GlobalHotKeyManager {
    public static let shared = GlobalHotKeyManager()

    private var registeredRefs: [ShortcutActionID: EventHotKeyRef] = [:]
    private var cachedShortcuts: [ShortcutActionID: KeyShortcut] = [:]
    private var eventHandlerRef: EventHandlerRef?
    private var isSuspended: Bool = false

    public var onActionTriggered: ((ShortcutActionID) -> Void)?

    private let signature: OSType = 0x41524343 // 'ARCC'

    private init() {}

    public func syncShortcuts(_ shortcuts: [ShortcutActionID: KeyShortcut]) {
        cachedShortcuts = shortcuts
        guard !isSuspended else { return }
        applyRegistration()
    }

    public func suspendForRecording() {
        guard !isSuspended else { return }
        isSuspended = true
        unregisterAll()
    }

    public func resumeAfterRecording() {
        guard isSuspended else { return }
        isSuspended = false
        applyRegistration()
    }

    public func unregisterAll() {
        for (_, ref) in registeredRefs {
            UnregisterEventHotKey(ref)
        }
        registeredRefs.removeAll()
    }

    private func applyRegistration() {
        unregisterAll()
        installHandlerIfNeeded()

        for action in ShortcutActionID.globalActions {
            guard let shortcut = cachedShortcuts[action] else { continue }
            let hotKeyID = EventHotKeyID(signature: signature, id: action.carbonHotKeyID)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                shortcut.carbonKeyCode,
                shortcut.carbonModifiers,
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &ref
            )
            if status == noErr, let ref {
                registeredRefs[action] = ref
            }
        }
    }

    private func installHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hkID = EventHotKeyID()
            let err = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hkID
            )
            if err == noErr {
                let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                if hkID.signature == manager.signature,
                   let action = ShortcutActionID.fromCarbonHotKeyID(hkID.id) {
                    DispatchQueue.main.async {
                        manager.onActionTriggered?(action)
                    }
                    return noErr
                }
            }
            return OSStatus(eventNotHandledErr)
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        var handler: EventHandlerRef?
        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            selfPtr,
            &handler
        )
        self.eventHandlerRef = handler
    }
}
