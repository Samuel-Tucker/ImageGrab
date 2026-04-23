import AppKit

enum AnnotationTool {
    case pen, box, arrow, text
}

struct Annotation {
    let tool: AnnotationTool
    let color: NSColor
    var textBackgroundColor: NSColor = .white
    var points: [CGPoint]
    let lineWidth: CGFloat
    var text: String = ""
    var fontSize: CGFloat = 0
}

@MainActor
final class AnnotationOverlayView: NSView {
    var currentTool: AnnotationTool = .box {
        didSet { window?.invalidateCursorRects(for: self) }
    }
    var currentColor: NSColor = .systemRed
    var currentTextBackgroundColor: NSColor = .white {
        didSet {
            if isEditingText { needsDisplay = true }
        }
    }
    var onAnnotationsChanged: (@MainActor () -> Void)?

    private var annotations: [Annotation] = []
    private var currentAnnotation: Annotation?
    private var selectedAnnotationIndex: Int?
    private var movingAnnotationIndex: Int?
    private var lastDragPoint: CGPoint?
    private var didMoveSelection = false
    private let baseLineWidth: CGFloat = 3.0
    private let arrowLineWidth: CGFloat = 2.5

    // Text editing state
    private var isEditingText = false
    private var editingAnnotationIndex: Int?
    private var editingText = ""
    private var editingPosition: CGPoint = .zero
    private var currentFontSize: CGFloat = 18
    private var cursorVisible = true
    private var cursorTimer: Timer?

    var hasAnnotations: Bool { !annotations.isEmpty || (isEditingText && !editingText.isEmpty) }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: currentTool == .text ? .iBeam : .crosshair)
    }

    func undo() {
        guard !annotations.isEmpty else { return }
        commitTextIfNeeded()
        annotations.removeLast()
        selectedAnnotationIndex = nil
        needsDisplay = true
        onAnnotationsChanged?()
    }

    /// Finalize any in-progress text annotation
    func commitTextIfNeeded() {
        guard isEditingText else { return }
        if !editingText.isEmpty {
            if let editingAnnotationIndex, annotations.indices.contains(editingAnnotationIndex) {
                annotations[editingAnnotationIndex] = Annotation(
                    tool: .text,
                    color: currentColor,
                    textBackgroundColor: currentTextBackgroundColor,
                    points: [editingPosition],
                    lineWidth: 0,
                    text: editingText,
                    fontSize: currentFontSize
                )
                selectedAnnotationIndex = editingAnnotationIndex
            } else {
                let annotation = Annotation(
                    tool: .text,
                    color: currentColor,
                    textBackgroundColor: currentTextBackgroundColor,
                    points: [editingPosition],
                    lineWidth: 0,
                    text: editingText,
                    fontSize: currentFontSize
                )
                annotations.append(annotation)
                selectedAnnotationIndex = annotations.indices.last
            }
            onAnnotationsChanged?()
        } else if let editingAnnotationIndex, annotations.indices.contains(editingAnnotationIndex) {
            annotations.remove(at: editingAnnotationIndex)
            selectedAnnotationIndex = nil
            onAnnotationsChanged?()
        }
        isEditingText = false
        editingAnnotationIndex = nil
        editingText = ""
        stopCursorBlink()
        needsDisplay = true
    }

    /// Handle a key event during text editing. Returns true if consumed.
    func handleKeyDown(_ event: NSEvent) -> Bool {
        if isEditingText {
            // Cmd+Z while editing: cancel current text
            if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "z" {
                isEditingText = false
                editingAnnotationIndex = nil
                editingText = ""
                stopCursorBlink()
                needsDisplay = true
                onAnnotationsChanged?()
                return true
            }

            if event.modifierFlags.contains(.command),
               let chars = event.charactersIgnoringModifiers,
               handleTextSizeShortcut(chars) {
                return true
            }

            switch event.keyCode {
            case 36: // Return - finalize
                commitTextIfNeeded()
                return true
            case 53: // Escape - finalize
                commitTextIfNeeded()
                return true
            case 51: // Backspace
                if !editingText.isEmpty {
                    editingText.removeLast()
                    needsDisplay = true
                    onAnnotationsChanged?()
                }
                return true
            default:
                break
            }

            // Regular character input (no Cmd/Ctrl modifiers)
            if !event.modifierFlags.contains(.command),
               !event.modifierFlags.contains(.control),
               let chars = event.characters, !chars.isEmpty {
                let filtered = String(chars.unicodeScalars.filter {
                    $0.value >= 0x20 && $0.value < 0xF700
                })
                if !filtered.isEmpty {
                    editingText.append(filtered)
                    cursorVisible = true // reset blink on typing
                    needsDisplay = true
                    onAnnotationsChanged?()
                }
            }
            return true // consume all keys while editing
        }

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
        case 51: // Backspace - delete selected annotation
            annotations.remove(at: selectedAnnotationIndex)
            self.selectedAnnotationIndex = nil
            needsDisplay = true
            onAnnotationsChanged?()
            return true
        case 53: // Escape - clear selection
            self.selectedAnnotationIndex = nil
            needsDisplay = true
            return true
        default:
            break
        }

        return false
    }

    // MARK: - Mouse handling

    override func mouseDown(with event: NSEvent) {
        handlePointerDown(at: convert(event.locationInWindow, from: nil))
    }

    func handlePointerDown(at point: CGPoint) {
        commitTextIfNeeded()

        if let hitIndex = hitTestAnnotation(at: point) {
            currentAnnotation = nil
            selectedAnnotationIndex = hitIndex
            movingAnnotationIndex = hitIndex
            lastDragPoint = point
            didMoveSelection = false
            needsDisplay = true
            return
        }

        selectedAnnotationIndex = nil

        if currentTool == .text {
            // Start new text editing
            isEditingText = true
            editingAnnotationIndex = nil
            editingText = ""
            editingPosition = point
            startCursorBlink()
            needsDisplay = true
            return
        }

        let lw = currentTool == .arrow ? arrowLineWidth : baseLineWidth
        currentAnnotation = Annotation(tool: currentTool, color: currentColor, points: [point], lineWidth: lw)
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
        case .box, .arrow:
            if currentAnnotation!.points.count == 1 {
                currentAnnotation!.points.append(point)
            } else {
                currentAnnotation!.points[1] = point
            }
        case .text:
            break
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        handlePointerUp(at: convert(event.locationInWindow, from: nil))
    }

    func handlePointerUp(at point: CGPoint) {
        _ = point
        if let movingAnnotationIndex {
            if !didMoveSelection,
               annotations.indices.contains(movingAnnotationIndex),
               annotations[movingAnnotationIndex].tool == .text {
                beginEditingTextAnnotation(at: movingAnnotationIndex)
            }
            self.movingAnnotationIndex = nil
            lastDragPoint = nil
            didMoveSelection = false
            needsDisplay = true
            return
        }

        guard let annotation = currentAnnotation else { return }
        if annotation.points.count >= 2 {
            annotations.append(annotation)
            selectedAnnotationIndex = annotations.indices.last
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

    // MARK: - Cursor blink

    private func startCursorBlink() {
        cursorVisible = true
        cursorTimer?.invalidate()
        cursorTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isEditingText else { return }
                self.cursorVisible.toggle()
                self.needsDisplay = true
            }
        }
    }

    private func stopCursorBlink() {
        cursorTimer?.invalidate()
        cursorTimer = nil
        cursorVisible = false
    }

    private func beginEditingTextAnnotation(at index: Int) {
        guard annotations.indices.contains(index), annotations[index].tool == .text else { return }
        let annotation = annotations[index]
        guard let position = annotation.points.first else { return }

        selectedAnnotationIndex = index
        editingAnnotationIndex = index
        editingText = annotation.text
        editingPosition = position
        currentFontSize = annotation.fontSize
        currentColor = annotation.color
        currentTextBackgroundColor = annotation.textBackgroundColor
        isEditingText = true
        startCursorBlink()
        needsDisplay = true
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

        if isEditingText {
            adjustEditingFontSize(by: delta)
            return true
        }

        if let selectedAnnotationIndex,
           annotations.indices.contains(selectedAnnotationIndex),
           annotations[selectedAnnotationIndex].tool == .text {
            adjustSelectedTextFontSize(at: selectedAnnotationIndex, by: delta)
            return true
        }

        return false
    }

    private func adjustEditingFontSize(by delta: CGFloat) {
        currentFontSize = clampedFontSize(currentFontSize + delta)
        needsDisplay = true
        onAnnotationsChanged?()
    }

    private func adjustSelectedTextFontSize(at index: Int, by delta: CGFloat) {
        annotations[index].fontSize = clampedFontSize(annotations[index].fontSize + delta)
        needsDisplay = true
        onAnnotationsChanged?()
    }

    private func clampedFontSize(_ value: CGFloat) -> CGFloat {
        max(10, min(72, value))
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        for (index, annotation) in annotations.enumerated() {
            if isEditingText, editingAnnotationIndex == index { continue }
            drawAnnotation(annotation)
        }
        if let current = currentAnnotation {
            drawAnnotation(current)
        }

        if let selectedAnnotationIndex,
           annotations.indices.contains(selectedAnnotationIndex),
           !(isEditingText && editingAnnotationIndex == selectedAnnotationIndex) {
            drawSelection(for: annotations[selectedAnnotationIndex])
        }

        // Draw in-progress text
        if isEditingText {
            drawTextContent(
                editingText,
                at: editingPosition,
                fontSize: currentFontSize,
                color: currentColor,
                backgroundColor: currentTextBackgroundColor,
                showCursor: cursorVisible
            )
        }
    }

    private func drawAnnotation(_ annotation: Annotation) {
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
            let start = annotation.points[0]
            let end = annotation.points[1]

            let shaft = NSBezierPath()
            shaft.lineWidth = annotation.lineWidth
            shaft.lineCapStyle = .round
            shaft.move(to: start)
            shaft.line(to: end)
            shaft.stroke()

            let angle = atan2(end.y - start.y, end.x - start.x)
            let headLen = annotation.lineWidth * 5
            let headAngle: CGFloat = .pi / 6

            let p1 = CGPoint(
                x: end.x - headLen * cos(angle - headAngle),
                y: end.y - headLen * sin(angle - headAngle)
            )
            let p2 = CGPoint(
                x: end.x - headLen * cos(angle + headAngle),
                y: end.y - headLen * sin(angle + headAngle)
            )

            annotation.color.setFill()
            let head = NSBezierPath()
            head.move(to: p1)
            head.line(to: end)
            head.line(to: p2)
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
                showCursor: false
            )
        }
    }

    private func drawTextContent(_ text: String, at position: CGPoint, fontSize: CGFloat, color: NSColor, backgroundColor: NSColor, showCursor: Bool) {
        let displayText = text.isEmpty && showCursor ? " " : text
        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
        ]
        let attrStr = NSAttributedString(string: displayText, attributes: attrs)
        let textSize = attrStr.size()

        let padding: CGFloat = 4
        let bgRect = NSRect(
            x: position.x - padding,
            y: position.y - padding,
            width: textSize.width + padding * 2,
            height: textSize.height + padding * 2
        )

        // The text backing stays translucent so annotations remain readable without fully hiding the screenshot.
        let fillColor = backgroundColor.usingColorSpace(.deviceRGB) ?? backgroundColor
        fillColor.withAlphaComponent(0.88).setFill()
        NSBezierPath(roundedRect: bgRect, xRadius: 4, yRadius: 4).fill()

        // Text
        attrStr.draw(at: position)

        // Blinking cursor
        if showCursor {
            let cursorX = position.x + (text.isEmpty ? 0 : textSize.width)
            let cursorPath = NSBezierPath()
            cursorPath.move(to: CGPoint(x: cursorX, y: position.y + 2))
            cursorPath.line(to: CGPoint(x: cursorX, y: position.y + textSize.height - 2))
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

    // MARK: - Hit testing

    private func hitTestAnnotation(at point: CGPoint) -> Int? {
        for index in annotations.indices.reversed() {
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

        case .box:
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
        case .box, .arrow, .pen:
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

    private func textBackgroundRect(text: String, at position: CGPoint, fontSize: CGFloat) -> NSRect {
        let displayText = text.isEmpty ? " " : text
        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        let textSize = NSAttributedString(string: displayText, attributes: [.font: font]).size()
        let padding: CGFloat = 4
        return NSRect(
            x: position.x - padding,
            y: position.y - padding,
            width: textSize.width + padding * 2,
            height: textSize.height + padding * 2
        )
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
                text: annotation.text,
                fontSize: annotation.fontSize * scale
            )
            drawAnnotation(scaled)
        }

        result.unlockFocus()
        return result
    }
}

#if DEBUG
extension AnnotationOverlayView {
    var debugAnnotations: [Annotation] { annotations }
    var debugIsEditingText: Bool { isEditingText }
}
#endif
