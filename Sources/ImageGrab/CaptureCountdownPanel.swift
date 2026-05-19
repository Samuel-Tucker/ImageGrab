import AppKit

/// Floating borderless panel shown during a delayed capture. Displays the
/// remaining seconds in a dark capsule centered on the active screen, ticks
/// down once per second, and surfaces Esc-to-cancel.
@MainActor
final class CaptureCountdownPanel: NSPanel {
    private let totalSeconds: Int
    private let onFinished: @MainActor () -> Void

    private var remaining: Int
    private var timer: Timer?
    private let label: NSTextField
    private let hintLabel: NSTextField

    private static let panelSize = NSSize(width: 200, height: 200)

    init(
        seconds: Int,
        screen: NSScreen? = nil,
        onFinished: @escaping @MainActor () -> Void
    ) {
        precondition(seconds > 0, "CaptureCountdownPanel requires a positive duration")
        self.totalSeconds = seconds
        self.remaining = seconds
        self.onFinished = onFinished

        let target = screen ?? NSScreen.main ?? NSScreen.screens[0]
        let frame = NSRect(
            x: target.frame.midX - Self.panelSize.width / 2,
            y: target.frame.midY - Self.panelSize.height / 2,
            width: Self.panelSize.width,
            height: Self.panelSize.height
        )

        self.label = NSTextField(labelWithString: "\(seconds)")
        self.hintLabel = NSTextField(labelWithString: "Trigger hotkey again to cancel")

        super.init(
            contentRect: frame,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let container = NSView(frame: NSRect(origin: .zero, size: Self.panelSize))
        container.wantsLayer = true
        container.layer?.cornerRadius = 24
        container.layer?.masksToBounds = true
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.78).cgColor
        container.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        container.layer?.borderWidth = 1

        label.font = .systemFont(ofSize: 96, weight: .semibold)
        label.alignment = .center
        label.textColor = .white
        label.backgroundColor = .clear
        label.drawsBackground = false
        label.isBordered = false
        label.frame = NSRect(x: 0, y: 50, width: Self.panelSize.width, height: 120)
        container.addSubview(label)

        hintLabel.font = .systemFont(ofSize: 11, weight: .medium)
        hintLabel.alignment = .center
        hintLabel.textColor = NSColor.white.withAlphaComponent(0.78)
        hintLabel.backgroundColor = .clear
        hintLabel.drawsBackground = false
        hintLabel.isBordered = false
        hintLabel.frame = NSRect(x: 0, y: 22, width: Self.panelSize.width, height: 16)
        container.addSubview(hintLabel)

        contentView = container
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func start() {
        orderFrontRegardless()
        scheduleTick()
    }

    /// Stops the timer and removes the panel without calling either callback.
    /// Used by the host when the countdown should disappear because of an
    /// external signal (the popover started a new capture, the app is
    /// quitting, etc.).
    func teardown() {
        timer?.invalidate()
        timer = nil
        orderOut(nil)
    }

    private func scheduleTick() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        remaining -= 1
        if remaining <= 0 {
            teardown()
            onFinished()
            return
        }
        label.stringValue = "\(remaining)"
    }
}
