import AppKit

// Preview window shown AFTER native screencapture, for review before saving
@MainActor
final class CapturePreviewWindow: NSWindow {
    private let onSave: @MainActor (NSImage, Bool) -> Void
    private let onCancel: @MainActor () -> Void
    private let capturedImage: NSImage

    init(image: NSImage, onSave: @escaping @MainActor (NSImage, Bool) -> Void, onCancel: @escaping @MainActor () -> Void) {
        self.capturedImage = image
        self.onSave = onSave
        self.onCancel = onCancel

        // Size the window to fit the image (capped at 80% of screen)
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let maxW = screen.frame.width * 0.8
        let maxH = screen.frame.height * 0.8
        let imgW = image.size.width
        let imgH = image.size.height
        let scale = min(1.0, min(maxW / imgW, maxH / imgH))
        let displayW = imgW * scale
        let displayH = imgH * scale

        // Window size: image + toolbar at bottom
        let toolbarH: CGFloat = 50
        let windowRect = NSRect(
            x: (screen.frame.width - displayW) / 2,
            y: (screen.frame.height - displayH - toolbarH) / 2,
            width: displayW,
            height: displayH + toolbarH
        )

        super.init(
            contentRect: windowRect,
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        title = "ImageGrab Preview"
        level = .floating
        isReleasedWhenClosed = false

        let container = NSView(frame: NSRect(x: 0, y: 0, width: displayW, height: displayH + toolbarH))

        // Image view with yellow border
        let imageView = NSImageView(frame: NSRect(x: 0, y: toolbarH, width: displayW, height: displayH))
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.borderColor = NSColor.systemYellow.cgColor
        imageView.layer?.borderWidth = 3
        container.addSubview(imageView)

        // Toolbar
        let toolbar = NSView(frame: NSRect(x: 0, y: 0, width: displayW, height: toolbarH))

        // Size label
        let sizeLabel = NSTextField(labelWithString: "\(Int(imgW)) × \(Int(imgH)) px")
        sizeLabel.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        sizeLabel.textColor = .secondaryLabelColor
        sizeLabel.frame = NSRect(x: 12, y: 14, width: 150, height: 20)
        toolbar.addSubview(sizeLabel)

        // Cancel button
        let cancelBtn = NSButton(title: "Cancel", target: self, action: #selector(cancelClicked))
        cancelBtn.bezelStyle = .rounded
        cancelBtn.controlSize = .large
        cancelBtn.keyEquivalent = "\u{1b}"
        cancelBtn.frame = NSRect(x: displayW - 440, y: 10, width: 100, height: 30)
        toolbar.addSubview(cancelBtn)

        // Save button
        let saveBtn = NSButton(title: "Save", target: self, action: #selector(saveClicked))
        saveBtn.bezelStyle = .rounded
        saveBtn.controlSize = .large
        saveBtn.frame = NSRect(x: displayW - 330, y: 10, width: 80, height: 30)
        toolbar.addSubview(saveBtn)

        // Save & Copy Path button (primary action)
        let saveCopyBtn = NSButton(title: "Save & Copy Path", target: self, action: #selector(saveAndCopyPathClicked))
        saveCopyBtn.bezelStyle = .rounded
        saveCopyBtn.controlSize = .large
        saveCopyBtn.keyEquivalent = "\r"
        saveCopyBtn.frame = NSRect(x: displayW - 240, y: 10, width: 230, height: 30)
        toolbar.addSubview(saveCopyBtn)

        container.addSubview(toolbar)
        contentView = container
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func show() {
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func saveClicked() {
        orderOut(nil)
        onSave(capturedImage, false)
    }

    @objc private func saveAndCopyPathClicked() {
        orderOut(nil)
        onSave(capturedImage, true)
    }

    @objc private func cancelClicked() {
        orderOut(nil)
        onCancel()
    }
}
