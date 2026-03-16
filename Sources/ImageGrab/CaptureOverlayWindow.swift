import AppKit

// Preview window shown AFTER native screencapture, for review before saving
@MainActor
final class CapturePreviewWindow: NSWindow {
    private let onSave: @MainActor (NSImage, Bool) -> Void
    private let onCancel: @MainActor () -> Void
    private let capturedImage: NSImage
    private var annotationOverlay: AnnotationOverlayView!
    private var undoBtn: NSButton!
    private var colorButtons: [NSButton] = []

    private let presetColors: [NSColor] = [.systemRed, .systemBlue, .systemGreen, .systemYellow, .white]

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

        let bottomBarH: CGFloat = 50
        let annotBarH: CGFloat = 40

        let scale = min(1.0, min(maxW / imgW, (maxH - bottomBarH - annotBarH) / imgH))
        let displayW = imgW * scale
        let displayH = imgH * scale
        let totalH = displayH + bottomBarH + annotBarH

        let windowRect = NSRect(
            x: (screen.frame.width - displayW) / 2,
            y: (screen.frame.height - totalH) / 2,
            width: displayW,
            height: totalH
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

        let container = NSView(frame: NSRect(x: 0, y: 0, width: displayW, height: totalH))

        // Image view with yellow border
        let imageView = NSImageView(frame: NSRect(x: 0, y: bottomBarH, width: displayW, height: displayH))
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.borderColor = NSColor.systemYellow.cgColor
        imageView.layer?.borderWidth = 3
        container.addSubview(imageView)

        // Annotation overlay (on top of image, same frame)
        let overlay = AnnotationOverlayView(frame: NSRect(x: 0, y: bottomBarH, width: displayW, height: displayH))
        overlay.onAnnotationsChanged = { [weak self, weak overlay] in
            self?.undoBtn.isEnabled = overlay?.hasAnnotations ?? false
        }
        annotationOverlay = overlay
        container.addSubview(overlay)

        // Annotation toolbar (above image)
        let annotBar = NSView(frame: NSRect(x: 0, y: bottomBarH + displayH, width: displayW, height: annotBarH))
        annotBar.wantsLayer = true
        annotBar.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        setupAnnotationBar(annotBar)
        container.addSubview(annotBar)

        // Bottom toolbar (save/cancel)
        let bottomBar = NSView(frame: NSRect(x: 0, y: 0, width: displayW, height: bottomBarH))
        setupBottomBar(bottomBar, width: displayW, imgW: imgW, imgH: imgH)
        container.addSubview(bottomBar)

        contentView = container
    }

    // MARK: - Annotation toolbar

    private func setupAnnotationBar(_ bar: NSView) {
        var x: CGFloat = 12

        // Tool segmented control
        let tools = NSSegmentedControl()
        tools.segmentCount = 4
        tools.trackingMode = .selectOne
        tools.setImage(NSImage(systemSymbolName: "pencil.tip", accessibilityDescription: "Pen")!, forSegment: 0)
        tools.setImage(NSImage(systemSymbolName: "rectangle", accessibilityDescription: "Box")!, forSegment: 1)
        tools.setImage(NSImage(systemSymbolName: "arrow.up.right", accessibilityDescription: "Arrow")!, forSegment: 2)
        tools.setImage(NSImage(systemSymbolName: "textformat", accessibilityDescription: "Text")!, forSegment: 3)
        tools.setWidth(36, forSegment: 0)
        tools.setWidth(36, forSegment: 1)
        tools.setWidth(36, forSegment: 2)
        tools.setWidth(36, forSegment: 3)
        tools.selectedSegment = 1 // default to box
        tools.target = self
        tools.action = #selector(toolChanged(_:))
        tools.frame = NSRect(x: x, y: 6, width: 150, height: 28)
        bar.addSubview(tools)
        x += 150 + 16

        // Separator
        let sep1 = separatorView(at: x, height: 24, y: 8)
        bar.addSubview(sep1)
        x += 13

        // Color buttons
        for (i, color) in presetColors.enumerated() {
            let btn = NSButton(frame: NSRect(x: x, y: 8, width: 24, height: 24))
            btn.title = ""
            btn.isBordered = false
            btn.wantsLayer = true
            btn.layer?.cornerRadius = 12
            btn.layer?.backgroundColor = color.cgColor
            btn.tag = i
            btn.target = self
            btn.action = #selector(colorChanged(_:))

            if i == 0 {
                btn.layer?.borderColor = NSColor.controlAccentColor.cgColor
                btn.layer?.borderWidth = 2.5
            } else {
                btn.layer?.borderColor = NSColor.gray.withAlphaComponent(0.5).cgColor
                btn.layer?.borderWidth = 1
            }

            bar.addSubview(btn)
            colorButtons.append(btn)
            x += 30
        }
        x += 4

        // Separator
        let sep2 = separatorView(at: x, height: 24, y: 8)
        bar.addSubview(sep2)
        x += 13

        // Undo button
        let undo = NSButton(frame: NSRect(x: x, y: 6, width: 28, height: 28))
        undo.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: "Undo")!
        undo.isBordered = false
        undo.target = self
        undo.action = #selector(undoClicked)
        undo.isEnabled = false
        undoBtn = undo
        bar.addSubview(undo)
    }

    private func separatorView(at x: CGFloat, height: CGFloat, y: CGFloat) -> NSView {
        let sep = NSView(frame: NSRect(x: x, y: y, width: 1, height: height))
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor.separatorColor.cgColor
        return sep
    }

    // MARK: - Bottom toolbar

    private func setupBottomBar(_ bar: NSView, width: CGFloat, imgW: CGFloat, imgH: CGFloat) {
        let sizeLabel = NSTextField(labelWithString: "\(Int(imgW)) × \(Int(imgH)) px")
        sizeLabel.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        sizeLabel.textColor = .secondaryLabelColor
        sizeLabel.frame = NSRect(x: 12, y: 14, width: 150, height: 20)
        bar.addSubview(sizeLabel)

        let cancelBtn = NSButton(title: "Cancel", target: self, action: #selector(cancelClicked))
        cancelBtn.bezelStyle = .rounded
        cancelBtn.controlSize = .large
        // Escape handled in keyDown so text editing can intercept it
        cancelBtn.frame = NSRect(x: width - 440, y: 10, width: 100, height: 30)
        bar.addSubview(cancelBtn)

        let saveBtn = NSButton(title: "Save", target: self, action: #selector(saveClicked))
        saveBtn.bezelStyle = .rounded
        saveBtn.controlSize = .large
        saveBtn.frame = NSRect(x: width - 330, y: 10, width: 80, height: 30)
        bar.addSubview(saveBtn)

        let saveCopyBtn = NSButton(title: "Save & Copy Path", target: self, action: #selector(saveAndCopyPathClicked))
        saveCopyBtn.bezelStyle = .rounded
        saveCopyBtn.controlSize = .large
        saveCopyBtn.keyEquivalent = "\r"
        saveCopyBtn.frame = NSRect(x: width - 240, y: 10, width: 230, height: 30)
        bar.addSubview(saveCopyBtn)
    }

    // MARK: - Window

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func show() {
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    override func keyDown(with event: NSEvent) {
        // Text editing gets first crack at key events
        if annotationOverlay.handleKeyDown(event) {
            return
        }
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "z" {
            annotationOverlay.undo()
            return
        }
        // Escape closes the window (when not editing text)
        if event.keyCode == 53 {
            cancelClicked()
            return
        }
        super.keyDown(with: event)
    }

    // MARK: - Actions

    @objc private func toolChanged(_ sender: NSSegmentedControl) {
        annotationOverlay.commitTextIfNeeded()
        let tools: [AnnotationTool] = [.pen, .box, .arrow, .text]
        annotationOverlay.currentTool = tools[sender.selectedSegment]
    }

    @objc private func colorChanged(_ sender: NSButton) {
        annotationOverlay.currentColor = presetColors[sender.tag]
        for (i, btn) in colorButtons.enumerated() {
            if i == sender.tag {
                btn.layer?.borderColor = NSColor.controlAccentColor.cgColor
                btn.layer?.borderWidth = 2.5
            } else {
                btn.layer?.borderColor = NSColor.gray.withAlphaComponent(0.5).cgColor
                btn.layer?.borderWidth = 1
            }
        }
    }

    @objc private func undoClicked() {
        annotationOverlay.undo()
    }

    private func finalImage() -> NSImage {
        annotationOverlay.commitTextIfNeeded()
        return annotationOverlay.compositeOnto(image: capturedImage)
    }

    @objc private func saveClicked() {
        orderOut(nil)
        onSave(finalImage(), false)
    }

    @objc private func saveAndCopyPathClicked() {
        orderOut(nil)
        onSave(finalImage(), true)
    }

    @objc private func cancelClicked() {
        orderOut(nil)
        onCancel()
    }
}
