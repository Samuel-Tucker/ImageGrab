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

    init(image: NSImage, filename: String, screen: NSScreen?) {
        let contentRect = QuickViewPanel.contentRect(for: image.size, on: screen)
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        isReleasedWhenClosed = false
        level = .floating
        isFloatingPanel = true
        titlebarAppearsTransparent = true
        titleVisibility = .visible
        isMovableByWindowBackground = true
        collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        delegate = self

        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.translatesAutoresizingMaskIntoConstraints = false

        let contentView = NSView(frame: NSRect(origin: .zero, size: contentRect.size))
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        contentView.addSubview(imageView)
        self.contentView = contentView

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16)
        ])

        update(image: image, filename: filename, screen: screen, centerOnScreen: true)
        startOutsideClickMonitor()
        startEscapeKeyMonitor()
    }

    override var canBecomeKey: Bool { true }

    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
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

        let newContentRect = QuickViewPanel.contentRect(for: image.size, on: screen)
        setContentSize(newContentRect.size)
        if centerOnScreen {
            let centeredFrame = QuickViewPanel.centeredFrame(for: newContentRect.size, on: screen, panel: self)
            setFrame(centeredFrame, display: true, animate: true)
        } else {
            let resizedFrame = NSRect(origin: frame.origin, size: frameRect(forContentRect: newContentRect).size)
            setFrame(resizedFrame, display: true, animate: true)
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
            guard let self, self.isVisible else { return }
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
            guard let self, self.isVisible, event.keyCode == 53 else {
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

    private static func contentRect(for imageSize: NSSize, on screen: NSScreen?) -> NSRect {
        let fallbackSize = NSSize(width: 640, height: 400)
        let resolvedImageSize = imageSize.width > 0 && imageSize.height > 0 ? imageSize : fallbackSize

        let targetScreen = screen ?? screenContainingMouse() ?? NSScreen.main ?? NSScreen.screens.first
        let visibleFrame = targetScreen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let maxWidth = visibleFrame.width * 0.8
        let maxHeight = visibleFrame.height * 0.8

        let widthScale = maxWidth / resolvedImageSize.width
        let heightScale = maxHeight / resolvedImageSize.height
        let scale = min(widthScale, heightScale, 1.0)

        let panelWidth = resolvedImageSize.width * scale
        let panelHeight = resolvedImageSize.height * scale

        return NSRect(origin: .zero, size: NSSize(width: panelWidth, height: panelHeight))
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
