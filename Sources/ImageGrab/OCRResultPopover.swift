import AppKit

/// Popover content for the preview-window Copy Text action. Anchored to the
/// Copy Text button by `CapturePreviewWindow`; renders the four presenter
/// states (recognizing / text / no-text / failed) inside one fixed bubble.
@MainActor
final class OCRResultViewController: NSViewController {
    private let presenter: OCRResultPresenter
    private let onCopy: @MainActor () -> Void
    private let onDismiss: @MainActor () -> Void

    private var headerLabel: NSTextField!
    private var bodyLabel: NSTextField!
    private var progressIndicator: NSProgressIndicator!
    private var textScrollView: NSScrollView!
    private var textView: NSTextView!
    private var primaryButton: NSButton!
    private var secondaryButton: NSButton!

    private static let bubbleSize = NSSize(width: 360, height: 240)

    init(
        presenter: OCRResultPresenter,
        onCopy: @escaping @MainActor () -> Void = {},
        onDismiss: @escaping @MainActor () -> Void = {}
    ) {
        self.presenter = presenter
        self.onCopy = onCopy
        self.onDismiss = onDismiss
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override func loadView() {
        preferredContentSize = Self.bubbleSize

        let bubble = NSView(frame: NSRect(origin: .zero, size: Self.bubbleSize))
        bubble.wantsLayer = true

        // Header row: title + small inline progress indicator.
        let header = NSTextField(labelWithString: "")
        header.font = .systemFont(ofSize: 13, weight: .semibold)
        header.textColor = .labelColor
        header.frame = NSRect(x: 16, y: bubble.bounds.height - 32, width: bubble.bounds.width - 64, height: 18)
        bubble.addSubview(header)
        headerLabel = header

        let spinner = NSProgressIndicator(frame: NSRect(x: bubble.bounds.width - 32, y: bubble.bounds.height - 32, width: 16, height: 16))
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        bubble.addSubview(spinner)
        progressIndicator = spinner

        // Body label for no-text / failed messages (hidden when text is shown).
        let body = NSTextField(wrappingLabelWithString: "")
        body.font = .systemFont(ofSize: 12)
        body.textColor = .secondaryLabelColor
        body.frame = NSRect(x: 16, y: 56, width: bubble.bounds.width - 32, height: bubble.bounds.height - 56 - 40)
        body.isHidden = true
        bubble.addSubview(body)
        bodyLabel = body

        // Scrollable read-only text view for the recognized text (hidden until we have any).
        let scroll = NSScrollView(frame: NSRect(x: 16, y: 56, width: bubble.bounds.width - 32, height: bubble.bounds.height - 56 - 40))
        scroll.hasVerticalScroller = true
        scroll.borderType = .lineBorder
        scroll.autohidesScrollers = true
        scroll.isHidden = true

        let text = NSTextView(frame: scroll.contentView.bounds)
        text.isEditable = false
        text.isSelectable = true
        text.drawsBackground = true
        text.backgroundColor = .textBackgroundColor
        text.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        text.textContainerInset = NSSize(width: 6, height: 6)
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        scroll.documentView = text
        bubble.addSubview(scroll)
        textScrollView = scroll
        textView = text

        // Bottom action row.
        let secondary = NSButton(title: "Dismiss", target: self, action: #selector(secondaryClicked))
        secondary.bezelStyle = .rounded
        secondary.controlSize = .regular
        secondary.frame = NSRect(x: 16, y: 12, width: 100, height: 28)
        bubble.addSubview(secondary)
        secondaryButton = secondary

        let primary = NSButton(title: "Copy", target: self, action: #selector(primaryClicked))
        primary.bezelStyle = .rounded
        primary.controlSize = .regular
        primary.keyEquivalent = "\r"
        primary.frame = NSRect(x: bubble.bounds.width - 16 - 100, y: 12, width: 100, height: 28)
        bubble.addSubview(primary)
        primaryButton = primary

        view = bubble
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        render(presenter.state == .idle ? .recognizing : presenter.state)
        if presenter.state == .idle {
            Task { @MainActor [weak self] in
                guard let self else { return }
                let final = await presenter.recognize()
                render(final)
            }
        }
    }

    /// Update the visible content to match a state. Public-internal so the
    /// preview window can re-render after seeding state from a background
    /// recognize() if it ever wants to (currently it does not).
    func render(_ state: OCRResultPresenter.State) {
        switch state {
        case .idle, .recognizing:
            headerLabel.stringValue = "Recognizing Text…"
            progressIndicator.startAnimation(nil)
            bodyLabel.isHidden = false
            bodyLabel.stringValue = "Reading text from the captured image."
            textScrollView.isHidden = true
            primaryButton.isEnabled = false
            primaryButton.title = "Copy"
            secondaryButton.title = "Cancel"
        case .text(let text):
            headerLabel.stringValue = "Recognized Text"
            progressIndicator.stopAnimation(nil)
            bodyLabel.isHidden = true
            textView.string = text
            textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
            textScrollView.isHidden = false
            primaryButton.isEnabled = true
            primaryButton.title = "Copy"
            secondaryButton.title = "Done"
        case .noText:
            headerLabel.stringValue = "No Text Found"
            progressIndicator.stopAnimation(nil)
            bodyLabel.isHidden = false
            bodyLabel.stringValue = "No readable text was detected in this capture."
            textScrollView.isHidden = true
            primaryButton.isEnabled = false
            primaryButton.title = "Copy"
            secondaryButton.title = "Dismiss"
        case .failed:
            headerLabel.stringValue = "OCR Failed"
            progressIndicator.stopAnimation(nil)
            bodyLabel.isHidden = false
            bodyLabel.stringValue = "Text recognition could not complete. Try again, or use a clearer capture."
            textScrollView.isHidden = true
            primaryButton.isEnabled = false
            primaryButton.title = "Copy"
            secondaryButton.title = "Dismiss"
        }
    }

    @objc private func primaryClicked() {
        guard case .text(let text) = presenter.state else { return }
        if presenter.copy(text) {
            onCopy()
        }
    }

    @objc private func secondaryClicked() {
        onDismiss()
    }
}

/// Bridges `NSPopover`'s close notification back to a closure. The popover's
/// `delegate` reference is weak, so `CapturePreviewWindow` retains an instance
/// alongside the popover and releases both when the popover closes.
final class OCRPopoverCloseHandler: NSObject, NSPopoverDelegate {
    private let onClose: @MainActor () -> Void

    init(onClose: @escaping @MainActor () -> Void) {
        self.onClose = onClose
    }

    func popoverDidClose(_ notification: Notification) {
        Task { @MainActor in onClose() }
    }
}
