import Carbon
import Foundation

final class GlobalHotKeyManager {
    private struct Registration {
        let ref: EventHotKeyRef
        let action: () -> Void
    }

    private static let signature: OSType = 0x49475242 // IGRB

    private var nextID: UInt32 = 1
    private var registrations: [UInt32: Registration] = [:]
    private var eventHandlers: [EventHandlerRef] = []

    init() {
        installEventHandlerIfNeeded()
    }

    deinit {
        unregisterAll()
    }

    func register(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) -> Bool {
        let id = nextID
        nextID += 1

        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let eventTarget = GetApplicationEventTarget()

        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            eventTarget,
            0,
            &hotKeyRef
        )

        guard status == noErr, let hotKeyRef else {
            NSLog("ImageGrab: RegisterEventHotKey failed id=\(id) keyCode=\(keyCode) modifiers=\(modifiers) status=\(status)")
            return false
        }

        registrations[id] = Registration(ref: hotKeyRef, action: action)
        return true
    }

    func unregisterAll() {
        for registration in registrations.values {
            UnregisterEventHotKey(registration.ref)
        }
        registrations.removeAll()
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandlers.isEmpty else { return }

        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, event, userData in
            guard let event else { return noErr }
            guard let userData else { return noErr }

            let manager = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.handleHotKeyEvent(event)
            return noErr
        }

        for target in [GetApplicationEventTarget(), GetEventDispatcherTarget()] {
            var handler: EventHandlerRef?
            let status = InstallEventHandler(
                target,
                callback,
                1,
                &eventSpec,
                UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
                &handler
            )

            if status == noErr, let handler {
                eventHandlers.append(handler)
            } else {
                NSLog("ImageGrab: InstallEventHandler failed status=\(status)")
            }
        }
    }

    private func handleHotKeyEvent(_ event: EventRef) {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        guard status == noErr else { return }
        guard hotKeyID.signature == Self.signature else { return }
        guard let registration = registrations[hotKeyID.id] else { return }
        registration.action()
    }
}
