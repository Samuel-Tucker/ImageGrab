import AppKit
import CoreImage

enum AnnotationTool {
    case pen, box, arrow, text, blur, badge
}

struct Annotation {
    let tool: AnnotationTool
    var color: NSColor
    var textBackgroundColor: NSColor = .white
    var points: [CGPoint]
    var lineWidth: CGFloat
    var arrowHeadSize: CGFloat = 14
    var text: String = ""
    var fontSize: CGFloat = 0
    var blurRadius: CGFloat = 0
}

/// Text view used for in-place editing of a text annotation. It defers to the
/// system for caret movement, selection, copy/paste and undo, and only special
/// cases the keys that finalize or resize the annotation.
@MainActor
final class AnnotationTextView: NSTextView {
    var onCommit: (() -> Void)?
    var onFontSizeShortcut: ((CGFloat) -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // The preview window's "Save" button uses Return as its key equivalent.
        // While editing, claim Return first so it can't steal the keystroke:
        // plain Return inserts a newline, Shift+Return finalizes the annotation.
        if event.keyCode == 36 || event.keyCode == 76 {
            if event.modifierFlags.contains(.shift) {
                onCommit?()
            } else {
                insertNewline(nil)
            }
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        // Escape finalizes the annotation.
        if event.keyCode == 53 {
            onCommit?()
            return
        }
        // Shift+Return finalizes (backup where key-equivalent routing doesn't run).
        if event.keyCode == 36 || event.keyCode == 76, event.modifierFlags.contains(.shift) {
            onCommit?()
            return
        }
        // Cmd +/- adjusts the font size, matching the toolbar.
        if event.modifierFlags.contains(.command),
           let chars = event.charactersIgnoringModifiers,
           let delta = Self.fontSizeDelta(for: chars),
           onFontSizeShortcut?(delta) == true {
            return
        }
        super.keyDown(with: event)
    }

    private static func fontSizeDelta(for chars: String) -> CGFloat? {
        switch chars {
        case "+", "=": return 2
        case "-": return -2
        default: return nil
        }
    }
}

/// Pure geometry for drawing an arrow whose filled head always stays ahead of
/// the shaft: the head length is floored relative to the shaft thickness and
/// the shaft stops at the head's base, so a thick tail can never poke through
/// or swallow a small head. Kept AppKit-free so it can be unit-tested.
struct ArrowRenderGeometry {
    static let headAngle: CGFloat = .pi / 6
    /// Minimum head length as a multiple of the shaft (tail) width.
    static let minimumHeadToTailRatio: CGFloat = 2.5

    let headLength: CGFloat
    let tip: CGPoint
    let wingLeft: CGPoint
    let wingRight: CGPoint
    /// Where the shaft stroke ends: the base of the head triangle, not the tip.
    let shaftEnd: CGPoint
    /// False when the arrow is shorter than its own head; the head alone is drawn.
    let hasShaft: Bool

    init(start: CGPoint, end: CGPoint, headSize: CGFloat, lineWidth: CGFloat) {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let length = hypot(end.x - start.x, end.y - start.y)
        headLength = max(headSize, lineWidth * Self.minimumHeadToTailRatio)
        tip = end
        wingLeft = CGPoint(
            x: end.x - headLength * cos(angle - Self.headAngle),
            y: end.y - headLength * sin(angle - Self.headAngle)
        )
        wingRight = CGPoint(
            x: end.x - headLength * cos(angle + Self.headAngle),
            y: end.y - headLength * sin(angle + Self.headAngle)
        )
        let baseDistance = headLength * cos(Self.headAngle)
        shaftEnd = CGPoint(
            x: end.x - baseDistance * cos(angle),
            y: end.y - baseDistance * sin(angle)
        )
        hasShaft = length > baseDistance
    }
}

@MainActor
final class AnnotationOverlayView: NSView {
    var currentTool: AnnotationTool = .box {
        didSet {
            window?.invalidateCursorRects(for: self)
            onSelectionChanged?()
        }
    }
    var currentColor: NSColor = .systemRed {
        didSet {
            applyEditingTextAttributes()
            updateSelectedAnnotationColor()
        }
    }
    var currentTextBackgroundColor: NSColor = .white {
        didSet { applyEditingTextAttributes() }
    }
    var currentBlurRadius: CGFloat = 18 {
        didSet {
            guard !isSynchronizingSelectionControls,
                  let selectedAnnotationIndex,
                  annotations.indices.contains(selectedAnnotationIndex),
                  annotations[selectedAnnotationIndex].tool == .blur else { return }
            annotations[selectedAnnotationIndex].blurRadius = currentBlurRadius
            clearRedoStack()
            blurCache.removeAll()
            needsDisplay = true
            onAnnotationsChanged?()
        }
    }
    var currentArrowHeadSize: CGFloat = 14 {
        didSet {
            let clamped = min(max(currentArrowHeadSize, 6), 48)
            if currentArrowHeadSize != clamped {
                currentArrowHeadSize = clamped
                return
            }
            updateSelectedArrow { $0.arrowHeadSize = clamped }
        }
    }
    var currentArrowTailWidth: CGFloat = 2.5 {
        didSet {
            let clamped = min(max(currentArrowTailWidth, 1), 12)
            if currentArrowTailWidth != clamped {
                currentArrowTailWidth = clamped
                return
            }
            updateSelectedArrow { $0.lineWidth = clamped }
        }
    }
    var onAnnotationsChanged: (@MainActor () -> Void)?
    var onSelectionChanged: (@MainActor () -> Void)?

    /// When false the overlay ignores all pointer events (hit-testing falls through
    /// to the view below). Used to hand clicks to the sprite layer in rearrange mode.
    var interactionEnabled = true {
        didSet { window?.invalidateCursorRects(for: self) }
    }

    private var annotations: [Annotation] = []
    private var redoStack: [Annotation] = []
    private var currentAnnotation: Annotation?
    private var selectedAnnotationIndex: Int?
    private var movingAnnotationIndex: Int?
    private var lastDragPoint: CGPoint?
    private var didMoveSelection = false
    private var isSynchronizingSelectionControls = false
    /// Set on mouse-down over a text annotation that should re-open for editing if
    /// the gesture turns out to be a click rather than a drag. Resolved on mouse-up.
    private var pendingTextEditOnUpIndex: Int?
    private let baseLineWidth: CGFloat = 3.0
    private var sourceImage: NSImage?
    private var blurCache: [Int: NSImage] = [:]

    // Text editing state. While a text annotation is being edited, a real
    // `AnnotationTextView` is installed as a subview so the system provides the
    // caret, arrow-key navigation, mouse selection, copy/paste and undo. On
    // commit the text is baked back into an `Annotation` and drawn/saved by the
    // same renderer used for every other annotation.
    private var editingTextView: AnnotationTextView?
    private var editingAnnotationIndex: Int?
    private var editingPosition: CGPoint = .zero
    private var currentFontSize: CGFloat = 18

    private let editorPadding: CGFloat = 4
    private let editorBackgroundAlpha: CGFloat = 0.88
    private let minEditorWidth: CGFloat = 12
    private let caretSlack: CGFloat = 3

    var isEditingText: Bool { editingTextView != nil }

    var hasAnnotations: Bool {
        !annotations.isEmpty || !(editingTextView?.string.isEmpty ?? true)
    }
    var canUndo: Bool { !annotations.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var selectedAnnotationTool: AnnotationTool? {
        guard let selectedAnnotationIndex, annotations.indices.contains(selectedAnnotationIndex) else { return nil }
        return annotations[selectedAnnotationIndex].tool
    }

    func setSourceImage(_ image: NSImage) {
        sourceImage = image
        blurCache.removeAll()
        needsDisplay = true
    }

    func deselectAnnotation() {
        guard selectedAnnotationIndex != nil else {
            onSelectionChanged?()
            return
        }
        selectedAnnotationIndex = nil
        movingAnnotationIndex = nil
        pendingTextEditOnUpIndex = nil
        synchronizeControlsFromSelection()
        needsDisplay = true
    }

    private func synchronizeControlsFromSelection() {
        guard let selectedAnnotationIndex,
              annotations.indices.contains(selectedAnnotationIndex) else {
            onSelectionChanged?()
            return
        }

        let annotation = annotations[selectedAnnotationIndex]
        isSynchronizingSelectionControls = true
        if [.pen, .box, .arrow, .text].contains(annotation.tool) {
            currentColor = annotation.color
        }
        if annotation.tool == .text {
            currentTextBackgroundColor = annotation.textBackgroundColor
        } else if annotation.tool == .arrow {
            currentArrowHeadSize = annotation.arrowHeadSize
            currentArrowTailWidth = annotation.lineWidth
        } else if annotation.tool == .blur {
            currentBlurRadius = annotation.blurRadius
        }
        isSynchronizingSelectionControls = false
        onSelectionChanged?()
    }

    private func updateSelectedAnnotationColor() {
        guard !isSynchronizingSelectionControls,
              let selectedAnnotationIndex,
              annotations.indices.contains(selectedAnnotationIndex),
              [.pen, .box, .arrow, .text].contains(annotations[selectedAnnotationIndex].tool),
              !annotations[selectedAnnotationIndex].color.isEqual(currentColor) else { return }

        annotations[selectedAnnotationIndex].color = currentColor
        clearRedoStack()
        needsDisplay = true
        onAnnotationsChanged?()
    }

    private func updateSelectedArrow(_ update: (inout Annotation) -> Void) {
        guard !isSynchronizingSelectionControls,
              let selectedAnnotationIndex,
              annotations.indices.contains(selectedAnnotationIndex),
              annotations[selectedAnnotationIndex].tool == .arrow else { return }

        update(&annotations[selectedAnnotationIndex])
        clearRedoStack()
        needsDisplay = true
        onAnnotationsChanged?()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        interactionEnabled ? super.hitTest(point) : nil
    }

    override func resetCursorRects() {
        guard interactionEnabled else { return }
        addCursorRect(bounds, cursor: currentTool == .text ? .iBeam : .crosshair)

        // Committed text annotations stay editable, so show an I-beam when hovering
        // over them (regardless of the active tool) to signal they can be re-edited.
        if currentTool != .text, !isEditingText {
            for annotation in annotations where annotation.tool == .text {
                let rect = textBackgroundRect(
                    text: annotation.text,
                    at: annotation.points.first ?? .zero,
                    fontSize: annotation.fontSize
                )
                .insetBy(dx: -5, dy: -5)
                .intersection(bounds)
                if !rect.isEmpty {
                    addCursorRect(rect, cursor: .iBeam)
                }
            }
        }
    }

    override var acceptsFirstResponder: Bool { true }

    func undo() {
        commitTextIfNeeded(preservingRedo: true)
        guard !annotations.isEmpty else { return }
        redoStack.append(annotations.removeLast())
        selectedAnnotationIndex = nil
        synchronizeControlsFromSelection()
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
        onAnnotationsChanged?()
    }

    func redo() {
        commitTextIfNeeded(preservingRedo: true)
        guard let annotation = redoStack.popLast() else { return }
        annotations.append(annotation)
        selectedAnnotationIndex = annotations.indices.last
        synchronizeControlsFromSelection()
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
        onAnnotationsChanged?()
    }

    /// Finalize any in-progress text annotation
    func commitTextIfNeeded() {
        commitTextIfNeeded(preservingRedo: false)
    }

    private func commitTextIfNeeded(preservingRedo: Bool) {
        guard let textView = editingTextView else { return }
        let text = textView.string
        let existingIndex = editingAnnotationIndex
        let position = editingPosition

        removeEditingTextView()

        if !text.isEmpty {
            if !preservingRedo { clearRedoStack() }
            let annotation = Annotation(
                tool: .text,
                color: currentColor,
                textBackgroundColor: currentTextBackgroundColor,
                points: [position],
                lineWidth: 0,
                text: text,
                fontSize: currentFontSize
            )
            if let existingIndex, annotations.indices.contains(existingIndex) {
                annotations[existingIndex] = annotation
                selectedAnnotationIndex = existingIndex
            } else {
                annotations.append(annotation)
                selectedAnnotationIndex = annotations.indices.last
            }
            synchronizeControlsFromSelection()
            onAnnotationsChanged?()
        } else if let existingIndex, annotations.indices.contains(existingIndex) {
            // Editing left the text empty: drop the annotation entirely.
            if !preservingRedo { clearRedoStack() }
            annotations.remove(at: existingIndex)
            selectedAnnotationIndex = nil
            synchronizeControlsFromSelection()
            onAnnotationsChanged?()
        }

        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    private func removeEditingTextView() {
        guard let textView = editingTextView else { return }
        editingTextView = nil
        editingAnnotationIndex = nil
        if window?.firstResponder === textView {
            window?.makeFirstResponder(self)
        }
        textView.removeFromSuperview()
    }

    /// Handle a key event when no text editor is active. Returns true if consumed.
    /// While editing, the installed `AnnotationTextView` is first responder and
    /// receives keys directly, so this only covers the selection shortcuts.
    func handleKeyDown(_ event: NSEvent) -> Bool {
        guard !isEditingText else { return false }

        guard let selectedAnnotationIndex, annotations.indices.contains(selectedAnnotationIndex) else {
            return false
        }

        if event.modifierFlags.contains(.command),
           let chars = event.charactersIgnoringModifiers,
           handleTextSizeShortcut(chars) {
            return true
        }

        switch event.keyCode {
        case 36: // Return - edit selected text
            if annotations[selectedAnnotationIndex].tool == .text {
                beginEditingTextAnnotation(at: selectedAnnotationIndex)
                return true
            }
        case 51, 117: // Backspace / forward delete - delete selected annotation
            annotations.remove(at: selectedAnnotationIndex)
            clearRedoStack()
            self.selectedAnnotationIndex = nil
            synchronizeControlsFromSelection()
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
            onAnnotationsChanged?()
            return true
        case 53: // Escape - clear selection
            self.selectedAnnotationIndex = nil
            synchronizeControlsFromSelection()
            needsDisplay = true
            return true
        default:
            break
        }

        return false
    }

    // MARK: - Mouse handling

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        handlePointerDown(at: convert(event.locationInWindow, from: nil), clickCount: event.clickCount)
    }

    func handlePointerDown(at point: CGPoint, clickCount: Int = 1) {
        commitTextIfNeeded()

        // With the Text tool active, only text annotations are interactive, so a
        // click inside a box (or any other shape) starts a new text annotation on
        // top of it rather than grabbing the shape underneath.
        if let hitIndex = hitTestAnnotation(at: point, textOnly: currentTool == .text) {
            // A double-click (never a drag) re-enters editing immediately.
            if annotations[hitIndex].tool == .text, clickCount >= 2 {
                beginEditingTextAnnotation(at: hitIndex)
                return
            }

            // Otherwise arm a potential move. Whether this becomes an edit or a
            // drag is decided on mouse-up: a click that didn't move re-opens the
            // editor (Text tool only); any drag repositions the annotation.
            currentAnnotation = nil
            selectedAnnotationIndex = hitIndex
            synchronizeControlsFromSelection()
            movingAnnotationIndex = hitIndex
            lastDragPoint = point
            didMoveSelection = false
            pendingTextEditOnUpIndex =
                (annotations[hitIndex].tool == .text && currentTool == .text) ? hitIndex : nil
            needsDisplay = true
            return
        }

        selectedAnnotationIndex = nil
        synchronizeControlsFromSelection()

        if currentTool == .text {
            startEditing(at: point, existingIndex: nil, initialText: "")
            return
        }

        if currentTool == .badge {
            annotations.append(Annotation(
                tool: .badge,
                color: .black,
                textBackgroundColor: .white,
                points: [point],
                lineWidth: 0,
                text: "NOPE!",
                fontSize: 34
            ))
            clearRedoStack()
            selectedAnnotationIndex = annotations.indices.last
            synchronizeControlsFromSelection()
            needsDisplay = true
            onAnnotationsChanged?()
            return
        }

        let lw = currentTool == .arrow ? currentArrowTailWidth : baseLineWidth
        currentAnnotation = Annotation(
            tool: currentTool,
            color: currentColor,
            points: [point],
            lineWidth: lw,
            arrowHeadSize: currentArrowHeadSize,
            blurRadius: currentTool == .blur ? currentBlurRadius : 0
        )
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        handlePointerDragged(to: convert(event.locationInWindow, from: nil))
    }

    func handlePointerDragged(to point: CGPoint) {
        if let movingAnnotationIndex, annotations.indices.contains(movingAnnotationIndex), let lastDragPoint {
            let delta = CGPoint(x: point.x - lastDragPoint.x, y: point.y - lastDragPoint.y)
            if abs(delta.x) > 0 || abs(delta.y) > 0 {
                for pointIndex in annotations[movingAnnotationIndex].points.indices {
                    annotations[movingAnnotationIndex].points[pointIndex].x += delta.x
                    annotations[movingAnnotationIndex].points[pointIndex].y += delta.y
                }
                clearRedoStack()
                self.lastDragPoint = point
                didMoveSelection = true
                needsDisplay = true
                onAnnotationsChanged?()
            }
            return
        }

        guard currentAnnotation != nil else { return }

        switch currentAnnotation!.tool {
        case .pen:
            if let last = currentAnnotation!.points.last {
                let dist = hypot(point.x - last.x, point.y - last.y)
                if dist > 2 { currentAnnotation!.points.append(point) }
            }
        case .box, .arrow, .blur:
            if currentAnnotation!.points.count == 1 {
                currentAnnotation!.points.append(point)
            } else {
                currentAnnotation!.points[1] = point
            }
        case .text, .badge:
            break
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        handlePointerUp(at: convert(event.locationInWindow, from: nil))
    }

    func handlePointerUp(at point: CGPoint) {
        _ = point
        if movingAnnotationIndex != nil {
            let moved = didMoveSelection
            let editIndex = pendingTextEditOnUpIndex
            movingAnnotationIndex = nil
            lastDragPoint = nil
            didMoveSelection = false
            pendingTextEditOnUpIndex = nil
            // A click that didn't drag re-opens the text editor; a drag just moved it.
            if !moved, let editIndex, annotations.indices.contains(editIndex),
               annotations[editIndex].tool == .text {
                beginEditingTextAnnotation(at: editIndex)
            } else {
                needsDisplay = true
            }
            return
        }

        guard let annotation = currentAnnotation else { return }
        if annotation.points.count >= 2 {
            annotations.append(annotation)
            clearRedoStack()
            selectedAnnotationIndex = annotations.indices.last
            synchronizeControlsFromSelection()
            onAnnotationsChanged?()
        }
        currentAnnotation = nil
        needsDisplay = true
    }

    // MARK: - Scroll wheel (font size)

    override func scrollWheel(with event: NSEvent) {
        if isEditingText {
            adjustEditingFontSize(by: event.scrollingDeltaY * 0.5)
        } else if let selectedAnnotationIndex,
                  annotations.indices.contains(selectedAnnotationIndex),
                  annotations[selectedAnnotationIndex].tool == .text {
            adjustSelectedTextFontSize(at: selectedAnnotationIndex, by: event.scrollingDeltaY * 0.5)
        } else if currentTool == .text {
            currentFontSize = clampedFontSize(currentFontSize + event.scrollingDeltaY * 0.5)
        } else {
            super.scrollWheel(with: event)
        }
    }

    // MARK: - Text editing

    private func beginEditingTextAnnotation(at index: Int) {
        guard annotations.indices.contains(index), annotations[index].tool == .text else { return }
        let annotation = annotations[index]
        guard let position = annotation.points.first else { return }

        selectedAnnotationIndex = index
        synchronizeControlsFromSelection()
        currentFontSize = annotation.fontSize
        startEditing(at: position, existingIndex: index, initialText: annotation.text)
    }

    private func startEditing(at position: CGPoint, existingIndex: Int?, initialText: String) {
        commitTextIfNeeded()

        editingPosition = position
        editingAnnotationIndex = existingIndex

        let textView = AnnotationTextView(frame: .zero)
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.textContainerInset = NSSize(width: editorPadding, height: editorPadding)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.lineBreakMode = .byWordWrapping
        textView.textContainer?.widthTracksTextView = false
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.minSize = .zero
        textView.wantsLayer = true
        textView.layer?.cornerRadius = 4
        textView.string = initialText
        textView.delegate = self
        textView.onCommit = { [weak self] in self?.commitTextIfNeeded() }
        textView.onFontSizeShortcut = { [weak self] delta in
            guard let self else { return false }
            self.adjustEditingFontSize(by: delta)
            return true
        }

        editingTextView = textView
        addSubview(textView)
        applyEditingTextAttributes()
        layoutEditingTextView()

        window?.makeFirstResponder(textView)
        let end = (textView.string as NSString).length
        textView.setSelectedRange(NSRange(location: end, length: 0))

        needsDisplay = true
        window?.invalidateCursorRects(for: self)
    }

    private func currentEditorFont() -> NSFont {
        NSFont.systemFont(ofSize: currentFontSize, weight: .medium)
    }

    private func applyEditingTextAttributes() {
        guard let textView = editingTextView else { return }
        let font = currentEditorFont()
        textView.font = font
        textView.textColor = currentColor
        textView.insertionPointColor = currentColor
        textView.backgroundColor = currentTextBackgroundColor.withAlphaComponent(editorBackgroundAlpha)
        textView.typingAttributes = [.font: font, .foregroundColor: currentColor]
        let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
        textView.textStorage?.addAttributes([.font: font, .foregroundColor: currentColor], range: fullRange)
    }

    /// Size the editor to its content and anchor its top-left to the spot the
    /// committed annotation will occupy, so committing doesn't visibly shift text.
    private func layoutEditingTextView() {
        guard let textView = editingTextView,
              let container = textView.textContainer,
              let layoutManager = textView.layoutManager else { return }

        let wrapWidth = textWrapWidth(at: editingPosition, in: bounds)
        container.size = NSSize(width: wrapWidth, height: CGFloat.greatestFiniteMagnitude)
        textView.maxSize = NSSize(
            width: wrapWidth + editorPadding * 2 + caretSlack,
            height: CGFloat.greatestFiniteMagnitude
        )
        layoutManager.ensureLayout(for: container)
        let used = layoutManager.usedRect(for: container).size
        let contentWidth = min(wrapWidth, max(minEditorWidth, ceil(used.width)))
        let width = contentWidth + editorPadding * 2 + caretSlack
        let height = max(textLineHeight(for: currentEditorFont()), ceil(used.height)) + editorPadding * 2

        let lineHeight = textLineHeight(for: currentEditorFont())
        let topY = editingPosition.y + lineHeight + editorPadding
        textView.frame = NSRect(
            x: editingPosition.x - editorPadding,
            y: topY - height,
            width: width,
            height: height
        )
    }

    private func handleTextSizeShortcut(_ chars: String) -> Bool {
        let delta: CGFloat
        switch chars {
        case "+", "=":
            delta = 2
        case "-":
            delta = -2
        default:
            return false
        }

        guard let selectedAnnotationIndex,
              annotations.indices.contains(selectedAnnotationIndex),
              annotations[selectedAnnotationIndex].tool == .text else {
            return false
        }
        adjustSelectedTextFontSize(at: selectedAnnotationIndex, by: delta)
        return true
    }

    private func adjustEditingFontSize(by delta: CGFloat) {
        currentFontSize = clampedFontSize(currentFontSize + delta)
        applyEditingTextAttributes()
        layoutEditingTextView()
        onAnnotationsChanged?()
    }

    private func adjustSelectedTextFontSize(at index: Int, by delta: CGFloat) {
        annotations[index].fontSize = clampedFontSize(annotations[index].fontSize + delta)
        clearRedoStack()
        needsDisplay = true
        onAnnotationsChanged?()
    }

    private func clampedFontSize(_ value: CGFloat) -> CGFloat {
        max(10, min(72, value))
    }

    private func clearRedoStack() {
        if !redoStack.isEmpty {
            redoStack.removeAll()
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        for (index, annotation) in annotations.enumerated() {
            // The annotation being edited is shown by the live text view instead.
            if editingAnnotationIndex == index { continue }
            drawAnnotation(annotation, blurSource: sourceImage, blurTargetRect: bounds, blurCache: &blurCache)
        }
        if let current = currentAnnotation {
            drawAnnotation(current, blurSource: sourceImage, blurTargetRect: bounds, blurCache: &blurCache)
        }

        if !isEditingText,
           let selectedAnnotationIndex,
           annotations.indices.contains(selectedAnnotationIndex) {
            drawSelection(for: annotations[selectedAnnotationIndex])
            if annotations[selectedAnnotationIndex].tool == .text {
                drawEditHint(for: annotations[selectedAnnotationIndex])
            }
        }
    }

    private func drawAnnotation(
        _ annotation: Annotation,
        blurSource: NSImage?,
        blurTargetRect: NSRect,
        blurCache: inout [Int: NSImage]
    ) {
        annotation.color.setStroke()

        switch annotation.tool {
        case .pen:
            guard annotation.points.count >= 2 else { return }
            let path = NSBezierPath()
            path.lineWidth = annotation.lineWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: annotation.points[0])
            for i in 1..<annotation.points.count {
                path.line(to: annotation.points[i])
            }
            path.stroke()

        case .box:
            guard annotation.points.count == 2 else { return }
            let origin = annotation.points[0]
            let corner = annotation.points[1]
            let rect = NSRect(
                x: min(origin.x, corner.x),
                y: min(origin.y, corner.y),
                width: abs(corner.x - origin.x),
                height: abs(corner.y - origin.y)
            )
            let path = NSBezierPath(rect: rect)
            path.lineWidth = annotation.lineWidth
            path.stroke()

        case .arrow:
            guard annotation.points.count == 2 else { return }
            let geometry = ArrowRenderGeometry(
                start: annotation.points[0],
                end: annotation.points[1],
                headSize: annotation.arrowHeadSize,
                lineWidth: annotation.lineWidth
            )

            if geometry.hasShaft {
                let shaft = NSBezierPath()
                shaft.lineWidth = annotation.lineWidth
                shaft.lineCapStyle = .round
                shaft.move(to: annotation.points[0])
                shaft.line(to: geometry.shaftEnd)
                shaft.stroke()
            }

            annotation.color.setFill()
            let head = NSBezierPath()
            head.move(to: geometry.wingLeft)
            head.line(to: geometry.tip)
            head.line(to: geometry.wingRight)
            head.close()
            head.fill()

        case .text:
            guard !annotation.text.isEmpty, let pos = annotation.points.first else { return }
            drawTextContent(
                annotation.text,
                at: pos,
                fontSize: annotation.fontSize,
                color: annotation.color,
                backgroundColor: annotation.textBackgroundColor,
                showCursor: false,
                targetBounds: blurTargetRect
            )

        case .badge:
            guard let pos = annotation.points.first else { return }
            drawBadge(annotation.text, at: pos, fontSize: annotation.fontSize)

        case .blur:
            guard annotation.points.count == 2, let blurSource else { return }
            let rect = normalizedRect(from: annotation.points[0], to: annotation.points[1])
            guard rect.width >= 1, rect.height >= 1 else { return }
            let cacheKey = Int(annotation.blurRadius.rounded())
            let blurred: NSImage
            if let cached = blurCache[cacheKey] {
                blurred = cached
            } else if let rendered = blurredImage(blurSource, radius: annotation.blurRadius) {
                blurCache[cacheKey] = rendered
                blurred = rendered
            } else {
                return
            }
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: rect).addClip()
            blurred.draw(in: blurTargetRect)
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    private func drawBadge(_ text: String, at position: CGPoint, fontSize: CGFloat) {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .black)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let attributed = NSAttributedString(string: text, attributes: attrs)
        let size = attributed.size()
        let paddingX: CGFloat = 14
        let paddingY: CGFloat = 8
        let rect = NSRect(
            x: position.x - paddingX,
            y: position.y - paddingY,
            width: size.width + paddingX * 2,
            height: size.height + paddingY * 2
        )
        NSColor.white.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        attributed.draw(at: position)
    }

    private func blurredImage(_ image: NSImage, radius: CGFloat) -> NSImage? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let input = CIImage(cgImage: cgImage)
        let filter = CIFilter(name: "CIGaussianBlur")
        filter?.setValue(input, forKey: kCIInputImageKey)
        filter?.setValue(max(1, radius), forKey: kCIInputRadiusKey)
        guard let output = filter?.outputImage?.cropped(to: input.extent),
              let rendered = Self.ciContext.createCGImage(output, from: input.extent) else { return nil }
        return NSImage(cgImage: rendered, size: image.size)
    }

    private static let ciContext = CIContext(options: [.cacheIntermediates: true])

    private func drawTextContent(
        _ text: String,
        at position: CGPoint,
        fontSize: CGFloat,
        color: NSColor,
        backgroundColor: NSColor,
        showCursor: Bool,
        targetBounds: NSRect
    ) {
        let displayText = text.isEmpty && showCursor ? " " : text
        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
        ]
        let lines = wrappedTextLines(
            for: displayText,
            font: font,
            maxWidth: textWrapWidth(at: position, in: targetBounds)
        )
        let lineHeight = textLineHeight(for: font)
        let textSize = multilineTextSize(lines: lines, font: font, lineHeight: lineHeight)

        let padding: CGFloat = 4
        let bgRect = NSRect(
            x: position.x - padding,
            y: position.y - (textSize.height - lineHeight) - padding,
            width: textSize.width + padding * 2,
            height: textSize.height + padding * 2
        )

        // The text backing stays translucent so annotations remain readable without fully hiding the screenshot.
        let fillColor = backgroundColor.usingColorSpace(.deviceRGB) ?? backgroundColor
        fillColor.withAlphaComponent(0.88).setFill()
        NSBezierPath(roundedRect: bgRect, xRadius: 4, yRadius: 4).fill()

        // Text
        for (index, line) in lines.enumerated() {
            let lineText = line.isEmpty ? " " : line
            NSAttributedString(string: lineText, attributes: attrs)
                .draw(at: CGPoint(x: position.x, y: position.y - CGFloat(index) * lineHeight))
        }

        // Blinking cursor
        if showCursor {
            let lastLine = lines.last ?? ""
            let lastLineWidth = lastLine.isEmpty ? 0 : NSAttributedString(string: lastLine, attributes: attrs).size().width
            let cursorX = position.x + lastLineWidth
            let cursorY = position.y - CGFloat(max(lines.count - 1, 0)) * lineHeight
            let cursorPath = NSBezierPath()
            cursorPath.move(to: CGPoint(x: cursorX, y: cursorY + 2))
            cursorPath.line(to: CGPoint(x: cursorX, y: cursorY + lineHeight - 2))
            cursorPath.lineWidth = 1.5
            color.setStroke()
            cursorPath.stroke()
        }
    }

    private func drawSelection(for annotation: Annotation) {
        let bounds = annotationBounds(annotation).insetBy(dx: -6, dy: -6)
        guard !bounds.isEmpty else { return }

        NSGraphicsContext.current?.saveGraphicsState()
        NSColor.controlAccentColor.setStroke()
        let path = NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5)
        path.lineWidth = 1.5
        path.setLineDash([4, 3], count: 2, phase: 0)
        path.stroke()
        NSGraphicsContext.current?.restoreGraphicsState()
    }

    /// Caption shown next to a selected text annotation so it's discoverable that
    /// committed text can be re-opened for editing.
    private func drawEditHint(for annotation: Annotation) {
        let selectionBounds = annotationBounds(annotation).insetBy(dx: -6, dy: -6)
        let hint = "Double-click to edit"
        let font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white,
        ]
        let textSize = NSAttributedString(string: hint, attributes: attrs).size()
        let padX: CGFloat = 6
        let padY: CGFloat = 3
        let labelW = textSize.width + padX * 2
        let labelH = textSize.height + padY * 2

        // Prefer placing the hint just below the selection; flip above if there's no room.
        var labelX = selectionBounds.minX
        var labelY = selectionBounds.minY - labelH - 4
        if labelY < 2 {
            labelY = selectionBounds.maxY + 4
        }
        labelX = max(2, min(labelX, bounds.maxX - labelW - 2))
        labelY = max(2, min(labelY, bounds.maxY - labelH - 2))
        let labelRect = NSRect(x: labelX, y: labelY, width: labelW, height: labelH)

        NSColor.controlAccentColor.withAlphaComponent(0.92).setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 5, yRadius: 5).fill()
        NSAttributedString(string: hint, attributes: attrs)
            .draw(at: CGPoint(x: labelRect.minX + padX, y: labelRect.minY + padY))
    }

    // MARK: - Hit testing

    private func hitTestAnnotation(at point: CGPoint, textOnly: Bool = false) -> Int? {
        for index in annotations.indices.reversed() {
            if textOnly, annotations[index].tool != .text { continue }
            if annotation(annotations[index], contains: point) {
                return index
            }
        }
        return nil
    }

    private func annotation(_ annotation: Annotation, contains point: CGPoint) -> Bool {
        switch annotation.tool {
        case .text:
            return textBackgroundRect(
                text: annotation.text,
                at: annotation.points.first ?? .zero,
                fontSize: annotation.fontSize
            )
            .insetBy(dx: -5, dy: -5)
            .contains(point)

        case .badge:
            return badgeRect(for: annotation).insetBy(dx: -5, dy: -5).contains(point)

        case .box, .blur:
            guard annotation.points.count == 2 else { return false }
            return normalizedRect(from: annotation.points[0], to: annotation.points[1])
                .insetBy(dx: -8, dy: -8)
                .contains(point)

        case .arrow, .pen:
            guard annotation.points.count >= 2 else { return false }
            let tolerance = max(8, annotation.lineWidth + 5)
            for index in 1..<annotation.points.count {
                if distance(from: point, toSegmentStart: annotation.points[index - 1], end: annotation.points[index]) <= tolerance {
                    return true
                }
            }
            return false
        }
    }

    private func annotationBounds(_ annotation: Annotation) -> NSRect {
        switch annotation.tool {
        case .text:
            return textBackgroundRect(
                text: annotation.text,
                at: annotation.points.first ?? .zero,
                fontSize: annotation.fontSize
            )
        case .badge:
            return badgeRect(for: annotation)
        case .arrow:
            guard let first = annotation.points.first else { return .zero }
            var minX = first.x
            var maxX = first.x
            var minY = first.y
            var maxY = first.y
            for point in annotation.points.dropFirst() {
                minX = min(minX, point.x)
                maxX = max(maxX, point.x)
                minY = min(minY, point.y)
                maxY = max(maxY, point.y)
            }
            let padding = max(annotation.arrowHeadSize * 0.55, annotation.lineWidth)
            return NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
                .insetBy(dx: -padding, dy: -padding)
        case .box, .pen, .blur:
            guard let first = annotation.points.first else { return .zero }
            var minX = first.x
            var maxX = first.x
            var minY = first.y
            var maxY = first.y
            for point in annotation.points.dropFirst() {
                minX = min(minX, point.x)
                maxX = max(maxX, point.x)
                minY = min(minY, point.y)
                maxY = max(maxY, point.y)
            }
            return NSRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
    }

    private func badgeRect(for annotation: Annotation) -> NSRect {
        guard let position = annotation.points.first else { return .zero }
        let font = NSFont.systemFont(ofSize: annotation.fontSize, weight: .black)
        let size = NSAttributedString(string: annotation.text, attributes: [.font: font]).size()
        return NSRect(x: position.x - 14, y: position.y - 8, width: size.width + 28, height: size.height + 16)
    }

    private func textBackgroundRect(text: String, at position: CGPoint, fontSize: CGFloat) -> NSRect {
        let displayText = text.isEmpty ? " " : text
        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        let lineHeight = textLineHeight(for: font)
        let textSize = multilineTextSize(
            lines: wrappedTextLines(
                for: displayText,
                font: font,
                maxWidth: textWrapWidth(at: position, in: bounds)
            ),
            font: font,
            lineHeight: lineHeight
        )
        let padding: CGFloat = 4
        return NSRect(
            x: position.x - padding,
            y: position.y - (textSize.height - lineHeight) - padding,
            width: textSize.width + padding * 2,
            height: textSize.height + padding * 2
        )
    }

    /// Width available to text beginning at `position`, leaving room for the
    /// translucent backing and the live editor caret at the target's right edge.
    private func textWrapWidth(at position: CGPoint, in targetBounds: NSRect) -> CGFloat {
        max(1, targetBounds.maxX - position.x - editorPadding - caretSlack)
    }

    /// Return the visual lines produced by AppKit word wrapping. Using the same
    /// text system as the live editor keeps committed annotations from changing
    /// shape when the NSTextView is removed.
    private func wrappedTextLines(for text: String, font: NSFont, maxWidth: CGFloat) -> [String] {
        guard !text.isEmpty else { return [""] }

        let storage = NSTextStorage(
            attributedString: NSAttributedString(string: text, attributes: [.font: font])
        )
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(
            size: NSSize(width: max(1, maxWidth), height: CGFloat.greatestFiniteMagnitude)
        )
        container.lineFragmentPadding = 0
        container.lineBreakMode = .byWordWrapping
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: container)

        let glyphRange = layoutManager.glyphRange(for: container)
        guard glyphRange.length > 0 else { return [""] }

        let source = text as NSString
        var lines: [String] = []
        var glyphIndex = glyphRange.location
        while glyphIndex < NSMaxRange(glyphRange) {
            var lineGlyphRange = NSRange()
            _ = layoutManager.lineFragmentUsedRect(
                forGlyphAt: glyphIndex,
                effectiveRange: &lineGlyphRange
            )
            let characterRange = layoutManager.characterRange(
                forGlyphRange: lineGlyphRange,
                actualGlyphRange: nil
            )
            var line = source.substring(with: characterRange)
            if line.hasSuffix("\n") {
                line.removeLast()
            }
            lines.append(line)
            glyphIndex = NSMaxRange(lineGlyphRange)
        }

        if text.hasSuffix("\n") {
            lines.append("")
        }
        return lines.isEmpty ? [""] : lines
    }

    private func textLineHeight(for font: NSFont) -> CGFloat {
        ceil(font.ascender - font.descender + font.leading)
    }

    private func multilineTextSize(lines: [String], font: NSFont, lineHeight: CGFloat) -> NSSize {
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let width = lines
            .map { line in
                NSAttributedString(string: line.isEmpty ? " " : line, attributes: attrs).size().width
            }
            .max() ?? 0
        return NSSize(width: width, height: lineHeight * CGFloat(max(lines.count, 1)))
    }

    private func normalizedRect(from start: CGPoint, to end: CGPoint) -> NSRect {
        NSRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    private func distance(from point: CGPoint, toSegmentStart start: CGPoint, end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else {
            return hypot(point.x - start.x, point.y - start.y)
        }

        let t = max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        let projection = CGPoint(x: start.x + t * dx, y: start.y + t * dy)
        return hypot(point.x - projection.x, point.y - projection.y)
    }

    // MARK: - Compositing

    func compositeOnto(image: NSImage) -> NSImage {
        guard !annotations.isEmpty else { return image }

        let scale = image.size.width / bounds.size.width

        let result = NSImage(size: image.size)
        result.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: image.size))

        var compositeBlurCache: [Int: NSImage] = [:]
        for annotation in annotations {
            let scaledPoints = annotation.points.map {
                CGPoint(x: $0.x * scale, y: $0.y * scale)
            }
            let scaled = Annotation(
                tool: annotation.tool,
                color: annotation.color,
                textBackgroundColor: annotation.textBackgroundColor,
                points: scaledPoints,
                lineWidth: annotation.lineWidth * scale,
                arrowHeadSize: annotation.arrowHeadSize * scale,
                text: annotation.text,
                fontSize: annotation.fontSize * scale,
                // Blur strength is stored in source-image pixels (the value shown
                // by the toolbar), so it must not scale with preview coordinates.
                blurRadius: annotation.blurRadius
            )
            drawAnnotation(
                scaled,
                blurSource: image,
                blurTargetRect: NSRect(origin: .zero, size: image.size),
                blurCache: &compositeBlurCache
            )
        }

        result.unlockFocus()
        return result
    }
}

extension AnnotationOverlayView: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        layoutEditingTextView()
    }
}

#if DEBUG
extension AnnotationOverlayView {
    var debugAnnotations: [Annotation] { annotations }
    var debugIsEditingText: Bool { isEditingText }
    var debugEditingText: String {
        get { editingTextView?.string ?? "" }
        set {
            editingTextView?.string = newValue
            applyEditingTextAttributes()
            layoutEditingTextView()
        }
    }
    var debugEditingTextFrame: NSRect { editingTextView?.frame ?? .zero }
    func debugAnnotationBounds(at index: Int) -> NSRect {
        guard annotations.indices.contains(index) else { return .zero }
        return annotationBounds(annotations[index])
    }
    func debugCommitEditing() { commitTextIfNeeded() }
}
#endif
