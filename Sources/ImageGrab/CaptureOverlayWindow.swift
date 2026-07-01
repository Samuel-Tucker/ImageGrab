import AppKit

private final class PreviewActionButton: NSButton {
    var normalBackgroundColor: NSColor = .controlBackgroundColor {
        didSet { updateBackground() }
    }
    var highlightedBackgroundColor: NSColor = .selectedControlColor {
        didSet { updateBackground() }
    }

    override var isHighlighted: Bool {
        didSet { updateBackground() }
    }

    override var isEnabled: Bool {
        didSet { updateBackground() }
    }

    private func updateBackground() {
        alphaValue = isEnabled ? 1 : 0.55
        layer?.backgroundColor = (isHighlighted ? highlightedBackgroundColor : normalBackgroundColor).cgColor
    }
}

// Preview window shown AFTER native screencapture, for review before saving
@MainActor
final class CapturePreviewWindow: NSWindow {
    private let onSave: @MainActor (NSImage, Bool, String?) -> Void
    private let onCancel: @MainActor () -> Void
    private let capturedImage: NSImage
    private var annotationOverlay: AnnotationOverlayView!
    private var spriteLayer: SpriteLayerView!
    private var rearrangeBtn: PreviewActionButton!
    private var rearrangeActive = false
    private var undoBtn: NSButton!
    private var redoBtn: NSButton!
    private var textBackgroundColorWell: NSColorWell!
    private var filenameField: NSTextField!
    private var copyTextBtn: NSButton!
    private var colorButtons: [NSButton] = []
    private var ocrPopover: NSPopover?
    private var ocrPopoverDelegate: OCRPopoverCloseHandler?

    private let presetColors: [NSColor] = [.systemRed, .systemBlue, .systemGreen, .systemYellow, .white]

    init(
        image: NSImage,
        initialBaseName: String? = nil,
        onSave: @escaping @MainActor (NSImage, Bool, String?) -> Void,
        onCancel: @escaping @MainActor () -> Void
    ) {
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

        // Minimum width so toolbars/buttons are always visible
        let minWindowW: CGFloat = 680
        let windowW = max(displayW, minWindowW)
        let totalH = displayH + bottomBarH + annotBarH

        let windowRect = NSRect(
            x: (screen.frame.width - windowW) / 2,
            y: (screen.frame.height - totalH) / 2,
            width: windowW,
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

        let container = NSView(frame: NSRect(x: 0, y: 0, width: windowW, height: totalH))

        // Center image horizontally if window is wider than image
        let imageX = (windowW - displayW) / 2

        // Image view with yellow border
        let imageView = NSImageView(frame: NSRect(x: imageX, y: bottomBarH, width: displayW, height: displayH))
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.borderColor = NSColor.systemYellow.cgColor
        imageView.layer?.borderWidth = 3
        container.addSubview(imageView)

        // Sprite layer (between image and annotations): lifts regions of the
        // screenshot into draggable pieces. Display-only until rearrange mode is on.
        let sprites = SpriteLayerView(frame: NSRect(x: imageX, y: bottomBarH, width: displayW, height: displayH))
        sprites.setSource(image)
        sprites.onSpritesChanged = { [weak self] in self?.updateUndoRedoButtons() }
        spriteLayer = sprites
        container.addSubview(sprites)

        // Annotation overlay (on top of image + sprites, same frame)
        let overlay = AnnotationOverlayView(frame: NSRect(x: imageX, y: bottomBarH, width: displayW, height: displayH))
        overlay.onAnnotationsChanged = { [weak self] in self?.updateUndoRedoButtons() }
        annotationOverlay = overlay
        container.addSubview(overlay)

        // Annotation toolbar (above image)
        let annotBar = NSView(frame: NSRect(x: 0, y: bottomBarH + displayH, width: windowW, height: annotBarH))
        annotBar.wantsLayer = true
        annotBar.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        setupAnnotationBar(annotBar)
        container.addSubview(annotBar)

        // Bottom toolbar (save/cancel)
        let bottomBar = NSView(frame: NSRect(x: 0, y: 0, width: windowW, height: bottomBarH))
        setupBottomBar(bottomBar, width: windowW, imgW: imgW, imgH: imgH)
        container.addSubview(bottomBar)

        contentView = container
        initialFirstResponder = overlay
        filenameField.stringValue = initialBaseName ?? defaultCaptureBaseName()
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

        // Text background color
        let textBgWell = NSColorWell(frame: NSRect(x: x, y: 6, width: 28, height: 28))
        textBgWell.color = annotationOverlay.currentTextBackgroundColor
        textBgWell.toolTip = "Text background color"
        if #available(macOS 13.0, *) {
            textBgWell.colorWellStyle = .minimal
        }
        textBgWell.target = self
        textBgWell.action = #selector(textBackgroundColorChanged(_:))
        textBackgroundColorWell = textBgWell
        bar.addSubview(textBgWell)
        x += 34

        // Separator
        let sep3 = separatorView(at: x, height: 24, y: 8)
        bar.addSubview(sep3)
        x += 13

        // Undo button
        let undo = NSButton(frame: NSRect(x: x, y: 6, width: 28, height: 28))
        undo.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: "Undo")!
        undo.isBordered = false
        undo.target = self
        undo.action = #selector(undoClicked)
        undo.isEnabled = false
        undo.toolTip = "Undo (Cmd+Z)"
        undoBtn = undo
        bar.addSubview(undo)
        x += 32

        let redo = NSButton(frame: NSRect(x: x, y: 6, width: 28, height: 28))
        redo.image = NSImage(systemSymbolName: "arrow.uturn.forward", accessibilityDescription: "Redo")!
        redo.isBordered = false
        redo.target = self
        redo.action = #selector(redoClicked)
        redo.isEnabled = false
        redo.toolTip = "Redo (Cmd+Shift+Z)"
        redoBtn = redo
        bar.addSubview(redo)

        let copyTextW: CGFloat = 116
        let rearrangeW: CGFloat = 110
        let rearrange = styledPreviewButton(
            title: "Rearrange",
            frame: NSRect(x: bar.frame.width - copyTextW - 12 - 8 - rearrangeW, y: 6, width: rearrangeW, height: 28),
            backgroundColor: .controlBackgroundColor,
            highlightedColor: .selectedControlColor,
            textColor: .labelColor,
            action: #selector(toggleRearrange),
            borderColor: NSColor.separatorColor
        )
        rearrange.toolTip = "Lift parts of the screenshot and drag them to mock up changes"
        rearrangeBtn = rearrange as? PreviewActionButton
        bar.addSubview(rearrange)

        let copyTextBtn = styledPreviewButton(
            title: "Copy Text",
            frame: NSRect(x: bar.frame.width - copyTextW - 12, y: 6, width: copyTextW, height: 28),
            backgroundColor: NSColor.systemGreen.withAlphaComponent(0.18),
            highlightedColor: NSColor.systemGreen.withAlphaComponent(0.28),
            textColor: .labelColor,
            action: #selector(copyTextClicked)
        )
        copyTextBtn.toolTip = "Copy recognized text from this capture"
        self.copyTextBtn = copyTextBtn
        bar.addSubview(copyTextBtn)
    }

    private func separatorView(at x: CGFloat, height: CGFloat, y: CGFloat) -> NSView {
        let sep = NSView(frame: NSRect(x: x, y: y, width: 1, height: height))
        sep.wantsLayer = true
        sep.layer?.backgroundColor = NSColor.separatorColor.cgColor
        return sep
    }

    // MARK: - Bottom toolbar

    private func setupBottomBar(_ bar: NSView, width: CGFloat, imgW: CGFloat, imgH: CGFloat) {
        // Right-align buttons, size label and rename field take the left side.
        let saveCopyW: CGFloat = 180
        let saveW: CGFloat = 70
        let cancelW: CGFloat = 80
        let pad: CGFloat = 10
        let gap: CGFloat = 8

        let saveCopyX = width - pad - saveCopyW
        let saveX = saveCopyX - gap - saveW
        let cancelX = saveX - gap - cancelW

        let sizeLabel = NSTextField(labelWithString: "\(Int(imgW)) × \(Int(imgH)) px")
        sizeLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        sizeLabel.textColor = .secondaryLabelColor
        sizeLabel.frame = NSRect(x: 12, y: 14, width: 96, height: 20)
        bar.addSubview(sizeLabel)

        let nameFieldX: CGFloat = 116
        let nameFieldW = max(cancelX - nameFieldX - gap, 120)
        let nameField = NSTextField(frame: NSRect(x: nameFieldX, y: 10, width: nameFieldW, height: 30))
        nameField.font = .systemFont(ofSize: 13, weight: .medium)
        nameField.placeholderString = "Name this capture"
        nameField.bezelStyle = .roundedBezel
        nameField.lineBreakMode = .byTruncatingMiddle
        nameField.toolTip = "Rename capture before saving"
        filenameField = nameField
        bar.addSubview(nameField)

        let cancelBtn = styledPreviewButton(
            title: "Cancel",
            frame: NSRect(x: cancelX, y: 10, width: cancelW, height: 30),
            backgroundColor: NSColor.systemRed.withAlphaComponent(0.14),
            highlightedColor: NSColor.systemRed.withAlphaComponent(0.24),
            textColor: .labelColor,
            action: #selector(cancelClicked)
        )
        bar.addSubview(cancelBtn)

        let saveBtn = NSButton(title: "Save", target: self, action: #selector(saveClicked))
        saveBtn.bezelStyle = .rounded
        saveBtn.controlSize = .large
        saveBtn.frame = NSRect(x: saveX, y: 10, width: saveW, height: 30)
        bar.addSubview(saveBtn)

        let saveCopyBtn = styledPreviewButton(
            title: "Save & Copy Image",
            frame: NSRect(x: saveCopyX, y: 10, width: saveCopyW, height: 30),
            backgroundColor: NSColor.systemBlue.withAlphaComponent(0.16),
            highlightedColor: NSColor.systemBlue.withAlphaComponent(0.26),
            textColor: .labelColor,
            action: #selector(saveAndCopyImageClicked),
            borderColor: NSColor.systemBlue.withAlphaComponent(0.45)
        )
        saveCopyBtn.keyEquivalent = "\r"
        bar.addSubview(saveCopyBtn)
    }

    private func styledPreviewButton(
        title: String,
        frame: NSRect,
        backgroundColor: NSColor,
        highlightedColor: NSColor,
        textColor: NSColor,
        action: Selector,
        borderColor: NSColor? = nil
    ) -> NSButton {
        let button = PreviewActionButton(title: title, target: self, action: action)
        button.frame = frame
        button.isBordered = false
        button.wantsLayer = true
        button.layer?.cornerRadius = 8
        button.normalBackgroundColor = backgroundColor
        button.highlightedBackgroundColor = highlightedColor
        button.layer?.backgroundColor = backgroundColor.cgColor
        if let borderColor {
            button.layer?.borderColor = borderColor.cgColor
            button.layer?.borderWidth = 1
        }
        button.controlSize = .large
        setPreviewButtonTitle(button, title, textColor: textColor)
        return button
    }

    private func setPreviewButtonTitle(_ button: NSButton, _ title: String, textColor: NSColor = .labelColor) {
        button.title = title
        let attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .foregroundColor: textColor,
                .font: NSFont.systemFont(ofSize: 13, weight: .medium)
            ]
        )
        button.attributedTitle = attributedTitle
        button.attributedAlternateTitle = attributedTitle
    }

    // MARK: - Window

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func show() {
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    override func keyDown(with event: NSEvent) {
        if isFilenameFieldEditing {
            super.keyDown(with: event)
            return
        }

        // The active layer gets first crack at key events (text editing / sprite
        // selection-delete).
        if rearrangeActive {
            if spriteLayer.handleKeyDown(event) { return }
        } else if annotationOverlay.handleKeyDown(event) {
            return
        }
        if event.modifierFlags.contains(.command),
           event.modifierFlags.contains(.shift),
           event.charactersIgnoringModifiers == "z" {
            redoClicked()
            return
        }
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "z" {
            undoClicked()
            return
        }
        // Escape closes the window (when not editing text)
        if event.keyCode == 53 {
            cancelClicked()
            return
        }
        super.keyDown(with: event)
    }

    private var isFilenameFieldEditing: Bool {
        guard let editor = filenameField.currentEditor() else { return false }
        return firstResponder === editor
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

    @objc private func textBackgroundColorChanged(_ sender: NSColorWell) {
        annotationOverlay.currentTextBackgroundColor = sender.color
    }

    @objc private func toggleRearrange() {
        annotationOverlay.commitTextIfNeeded()
        rearrangeActive.toggle()
        spriteLayer.isActive = rearrangeActive
        annotationOverlay.interactionEnabled = !rearrangeActive

        let activeColor = NSColor.controlAccentColor
        rearrangeBtn.normalBackgroundColor = rearrangeActive ? activeColor : .controlBackgroundColor
        rearrangeBtn.highlightedBackgroundColor = rearrangeActive
            ? activeColor.withAlphaComponent(0.85) : .selectedControlColor
        setPreviewButtonTitle(rearrangeBtn, "Rearrange", textColor: rearrangeActive ? .white : .labelColor)

        makeFirstResponder(rearrangeActive ? spriteLayer : annotationOverlay)
        updateUndoRedoButtons()
    }

    @objc private func undoClicked() {
        if rearrangeActive { spriteLayer.undo() } else { annotationOverlay.undo() }
    }

    @objc private func redoClicked() {
        if rearrangeActive { spriteLayer.redo() } else { annotationOverlay.redo() }
    }

    private func updateUndoRedoButtons() {
        undoBtn.isEnabled = rearrangeActive ? spriteLayer.canUndo : annotationOverlay.canUndo
        redoBtn.isEnabled = rearrangeActive ? spriteLayer.canRedo : annotationOverlay.canRedo
    }

    @objc private func copyTextClicked() {
        // Toggle: clicking again while open closes the popover.
        if let existing = ocrPopover, existing.isShown {
            existing.performClose(nil)
            return
        }

        let presenter = OCRResultPresenter(image: capturedImage)
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true

        let controller = OCRResultViewController(
            presenter: presenter,
            onCopy: { [weak self] in self?.ocrPopover?.performClose(nil) },
            onDismiss: { [weak self] in self?.ocrPopover?.performClose(nil) }
        )
        popover.contentViewController = controller

        let delegate = OCRPopoverCloseHandler { [weak self] in
            guard let self else { return }
            self.ocrPopover = nil
            self.ocrPopoverDelegate = nil
        }
        popover.delegate = delegate
        ocrPopoverDelegate = delegate

        ocrPopover = popover
        popover.show(relativeTo: copyTextBtn.bounds, of: copyTextBtn, preferredEdge: .maxY)
    }

    private func finalImage() -> NSImage {
        annotationOverlay.commitTextIfNeeded()
        // Bake the moved sprites into the image first, then draw annotations on top.
        let plate = spriteLayer.compositeOnto(image: capturedImage)
        return annotationOverlay.compositeOnto(image: plate)
    }

    private func requestedBaseName() -> String? {
        filenameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func defaultCaptureBaseName() -> String {
        "capture-\(Self.timestampFormatter.string(from: Date()))"
    }

    @objc private func saveClicked() {
        orderOut(nil)
        onSave(finalImage(), false, requestedBaseName())
    }

    @objc private func saveAndCopyImageClicked() {
        orderOut(nil)
        onSave(finalImage(), true, requestedBaseName())
    }

    @objc private func cancelClicked() {
        orderOut(nil)
        onCancel()
    }

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f
    }()
}
