import Carbon
import CoreGraphics
import Foundation

final class RegionHotKeyEventTap {
    private var eventTaps: [CFMachPort] = []
    private var runLoopSources: [CFRunLoopSource] = []
    private let action: () -> Void
    private let onObservedGKey: (String) -> Void
    private var lastTriggerTime = Date.distantPast

    init(onObservedGKey: @escaping (String) -> Void, action: @escaping () -> Void) {
        self.onObservedGKey = onObservedGKey
        self.action = action
    }

    deinit {
        stop()
    }

    func start() -> Bool {
        guard eventTaps.isEmpty else { return true }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        for tapLocation in [CGEventTapLocation.cghidEventTap, .cgSessionEventTap] {
            guard let tap = CGEvent.tapCreate(
                tap: tapLocation,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: mask,
                callback: Self.callback,
                userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
            ) else {
                continue
            }

            guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
                continue
            }
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)

            eventTaps.append(tap)
            runLoopSources.append(source)
        }

        return !eventTaps.isEmpty
    }

    func stop() {
        for tap in eventTaps {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        for source in runLoopSources {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTaps.removeAll()
        runLoopSources.removeAll()
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            for tap in eventTaps {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == Int64(kVK_ANSI_G) else {
            return Unmanaged.passUnretained(event)
        }

        let flags = event.flags
        let summary = Self.flagSummary(flags)
        onObservedGKey("Opt+G tap saw G flags=\(summary)")

        guard flags.contains(.maskAlternate),
              !flags.contains(.maskCommand),
              !flags.contains(.maskShift),
              !flags.contains(.maskControl) else {
            return Unmanaged.passUnretained(event)
        }

        let now = Date()
        guard now.timeIntervalSince(lastTriggerTime) > 0.75 else {
            return Unmanaged.passUnretained(event)
        }
        lastTriggerTime = now
        action()
        return Unmanaged.passUnretained(event)
    }

    private static func flagSummary(_ flags: CGEventFlags) -> String {
        var parts: [String] = []
        if flags.contains(.maskAlternate) { parts.append("opt") }
        if flags.contains(.maskCommand) { parts.append("cmd") }
        if flags.contains(.maskShift) { parts.append("shift") }
        if flags.contains(.maskControl) { parts.append("ctrl") }
        if flags.contains(.maskAlphaShift) { parts.append("caps") }
        if flags.contains(.maskSecondaryFn) { parts.append("fn") }
        return parts.isEmpty ? "none" : parts.joined(separator: "+")
    }

    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let tap = Unmanaged<RegionHotKeyEventTap>.fromOpaque(userInfo).takeUnretainedValue()
        return tap.handle(type: type, event: event)
    }
}
