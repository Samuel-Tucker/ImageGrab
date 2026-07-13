import AppKit

public enum QuickViewCloseReason {
    case escape
    case outsideClick
    case window
    case programmatic
}

final class QuickViewPanel: NSPanel, NSWindowDelegate {
    var onClose: ((QuickViewCloseReason) -> Void)?

    private let imageView = NSImageView()
    private var outsideClickMonitor: Any?
    private var escapeKeyMonitor: Any?
    private var pendingCloseReason: QuickViewCloseReason = .window
    private let pinButton = NSButton()

    private(set) var isPinned = false {
        didSet { updatePinButtonAppearance() }
    }

    init(image: NSImage, filename: String, screen: NSScreen?) {
        let contentSize = QuickViewPanel.panelContentSize(on: screen)
        super.init(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.nonactivatingPanel, .titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        level = .floating
        isFloatingPanel = true
        titlebarAppearsTransparent = true
        titleVisibility = .visible
        isMovableByWindowBackground = true
        collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        delegate = self

        imageView.imageScaling = .scaleProportionallyDown
        imageView.imageAlignment = .alignCenter

        let contentView = NSView(frame: NSRect(origin: .zero, size: contentSize))
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        imageView.frame = NSRect(
            x: 16,
            y: 16,
            width: max(contentSize.width - 32, 0),
            height: max(contentSize.height - 32, 0)
        )
        imageView.autoresizingMask = [.width, .height]
        contentView.addSubview(imageView)
        self.contentView = contentView

        installPinButton()
        update(image: image, filename: filename, screen: screen, centerOnScreen: true)
        startOutsideClickMonitor()
        startEscapeKeyMonitor()
    }

    private func installPinButton() {
        pinButton.bezelStyle = .texturedRounded
        pinButton.isBordered = false
        pinButton.target = self
        pinButton.action = #selector(togglePin)
        updatePinButtonAppearance()

        let accessoryView = NSView(frame: NSRect(x: 0, y: 0, width: 30, height: 24))
        pinButton.frame = NSRect(x: 4, y: 2, width: 22, height: 20)
        accessoryView.addSubview(pinButton)

        let accessory = NSTitlebarAccessoryViewController()
        accessory.view = accessoryView
        accessory.layoutAttribute = .trailing
        addTitlebarAccessoryViewController(accessory)
    }

    @objc private func togglePin() {
        isPinned.toggle()
    }

    private func updatePinButtonAppearance() {
        let symbolName = isPinned ? "pin.fill" : "pin"
        let description = isPinned ? "Unpin preview" : "Pin preview on top"
        pinButton.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)
        pinButton.contentTintColor = isPinned ? .controlAccentColor : .secondaryLabelColor
        pinButton.toolTip = isPinned
            ? "Unpin — preview will close when you click elsewhere"
            : "Pin on top — keep this preview above other windows"
    }

    override var canBecomeKey: Bool { true }

    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, !isPinned {
            pendingCloseReason = .escape
            close()
            return
        }

        super.keyDown(with: event)
    }

    func show() {
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func update(image: NSImage, filename: String, screen: NSScreen?, centerOnScreen: Bool) {
        title = filename
        imageView.image = image

        if centerOnScreen {
            let contentSize = QuickViewPanel.panelContentSize(on: screen)
            let centeredFrame = QuickViewPanel.centeredFrame(for: contentSize, on: screen, panel: self)
            setFrame(centeredFrame, display: true, animate: true)
        }
    }

    func windowWillClose(_ notification: Notification) {
        let reason = pendingCloseReason
        pendingCloseReason = .window
        stopOutsideClickMonitor()
        stopEscapeKeyMonitor()
        onClose?(reason)
    }

    func closeProgrammatically() {
        pendingCloseReason = .programmatic
        close()
    }

    private func startOutsideClickMonitor() {
        stopOutsideClickMonitor()
        // Global monitor catches clicks outside the app (desktop, other apps)
        // In-app clicks (popover eye button) are handled by the toggle logic
        // in PopoverViewModel.showQuickView(for:), not by auto-dismissal
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, self.isVisible, !self.isPinned else { return }
            let mouseLocation = NSEvent.mouseLocation
            if !self.frame.contains(mouseLocation) {
                self.pendingCloseReason = .outsideClick
                self.close()
            }
        }
    }

    private func stopOutsideClickMonitor() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
    }

    private func startEscapeKeyMonitor() {
        stopEscapeKeyMonitor()
        escapeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible, !self.isPinned, event.keyCode == 53 else {
                return event
            }
            self.pendingCloseReason = .escape
            self.close()
            return nil
        }
    }

    private func stopEscapeKeyMonitor() {
        if let escapeKeyMonitor {
            NSEvent.removeMonitor(escapeKeyMonitor)
            self.escapeKeyMonitor = nil
        }
    }

    private static func panelContentSize(on screen: NSScreen?) -> NSSize {
        let targetScreen = screen ?? screenContainingMouse() ?? NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = targetScreen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        return NSSize(width: visibleFrame.width * 0.60, height: visibleFrame.height * 0.60)
    }

    private static func centeredFrame(for contentSize: NSSize, on screen: NSScreen?, panel: NSPanel) -> NSRect {
        let targetScreen = screen ?? screenContainingMouse() ?? NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = targetScreen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let frameSize = panel.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize)).size
        let origin = NSPoint(
            x: visibleFrame.midX - (frameSize.width / 2),
            y: visibleFrame.midY - (frameSize.height / 2)
        )
        return NSRect(origin: origin, size: frameSize)
    }

    private static func screenContainingMouse() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) })
    }

}
