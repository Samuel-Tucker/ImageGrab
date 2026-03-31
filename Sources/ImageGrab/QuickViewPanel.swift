import AppKit

final class QuickViewPanel: NSPanel, NSWindowDelegate {
    var onClose: (() -> Void)?

    private let imageView = NSImageView()
    private var outsideClickMonitor: Any?

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
    }

    override var canBecomeKey: Bool { true }

    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            close()
            return
        }

        super.keyDown(with: event)
    }

    func show() {
        makeKeyAndOrderFront(nil)
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
        stopOutsideClickMonitor()
        onClose?()
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
