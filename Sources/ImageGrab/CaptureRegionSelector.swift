import AppKit

@MainActor
final class CaptureRegionSelector {
    private var windows: [RegionSelectionWindow] = []
    private let onComplete: @MainActor (CaptureRegion?) -> Void

    init(onComplete: @escaping @MainActor (CaptureRegion?) -> Void) {
        self.onComplete = onComplete
    }

    func start() {
        let screens = NSScreen.screens
        windows = screens.map { screen in
            RegionSelectionWindow(screen: screen) { [weak self] region in
                self?.finish(region)
            }
        }
        windows.forEach { $0.orderFrontRegardless() }
        windows.first?.makeKey()
    }

    func cancel() {
        finish(nil)
    }

    private func finish(_ region: CaptureRegion?) {
        let windowsToClose = windows
        windows = []
        windowsToClose.forEach { $0.close() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { [onComplete] in
            onComplete(region?.isUsable == true ? region : nil)
        }
    }
}

private final class RegionSelectionWindow: NSPanel {
    init(screen: NSScreen, onComplete: @escaping @MainActor (CaptureRegion?) -> Void) {
        let screenFrame = screen.frame
        let selectionView = RegionSelectionView(screenFrame: screenFrame, onComplete: onComplete)

        super.init(
            contentRect: screenFrame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        ignoresMouseEvents = false
        isReleasedWhenClosed = false
        contentView = selectionView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            (contentView as? RegionSelectionView)?.cancel()
            return
        }
        super.keyDown(with: event)
    }
}

private final class RegionSelectionView: NSView {
    private let screenFrame: CGRect
    private let onComplete: @MainActor (CaptureRegion?) -> Void
    private var dragStart: CGPoint?
    private var dragEnd: CGPoint?

    init(screenFrame: CGRect, onComplete: @escaping @MainActor (CaptureRegion?) -> Void) {
        self.screenFrame = screenFrame
        self.onComplete = onComplete
        super.init(frame: NSRect(origin: .zero, size: screenFrame.size))
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.18).cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        dragStart = point
        dragEnd = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        dragEnd = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        dragEnd = convert(event.locationInWindow, from: nil)
        guard let selection = selectionRect else {
            cancel()
            return
        }

        let globalRect = selection.offsetBy(dx: screenFrame.minX, dy: screenFrame.minY)
        onComplete(CaptureRegion(screenFrame: screenFrame, rect: globalRect))
    }

    func cancel() {
        onComplete(nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        drawHintIfNeeded()

        guard let selection = selectionRect else { return }

        NSColor.clear.setFill()
        selection.fill(using: .clear)

        NSColor.systemBlue.setStroke()
        let path = NSBezierPath(rect: selection)
        path.lineWidth = 2
        path.stroke()

        NSColor.systemBlue.withAlphaComponent(0.12).setFill()
        selection.fill()
    }

    private func drawHintIfNeeded() {
        guard selectionRect == nil else { return }

        let text = "Drag to select area • Esc to cancel"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let padding = CGSize(width: 18, height: 10)
        let bubble = CGRect(
            x: bounds.midX - (size.width + padding.width * 2) / 2,
            y: bounds.midY - (size.height + padding.height * 2) / 2,
            width: size.width + padding.width * 2,
            height: size.height + padding.height * 2
        )

        NSColor.black.withAlphaComponent(0.72).setFill()
        let path = NSBezierPath(roundedRect: bubble, xRadius: 10, yRadius: 10)
        path.fill()

        (text as NSString).draw(
            at: CGPoint(x: bubble.minX + padding.width, y: bubble.minY + padding.height),
            withAttributes: attributes
        )
    }

    private var selectionRect: CGRect? {
        guard let dragStart, let dragEnd else { return nil }
        let rect = CGRect(
            x: min(dragStart.x, dragEnd.x),
            y: min(dragStart.y, dragEnd.y),
            width: abs(dragEnd.x - dragStart.x),
            height: abs(dragEnd.y - dragStart.y)
        ).standardized
        return rect.width >= 4 && rect.height >= 4 ? rect : nil
    }
}
