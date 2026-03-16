import AppKit

enum AnnotationTool {
    case pen, box, arrow, text
}

struct Annotation {
    let tool: AnnotationTool
    let color: NSColor
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
    var onAnnotationsChanged: (@MainActor () -> Void)?

    private var annotations: [Annotation] = []
    private var currentAnnotation: Annotation?
    private let baseLineWidth: CGFloat = 3.0
    private let arrowLineWidth: CGFloat = 2.5

    // Text editing state
    private var isEditingText = false
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
        annotations.removeLast()
        needsDisplay = true
        onAnnotationsChanged?()
    }

    /// Finalize any in-progress text annotation
    func commitTextIfNeeded() {
        guard isEditingText else { return }
        if !editingText.isEmpty {
            let annotation = Annotation(
                tool: .text,
                color: currentColor,
                points: [editingPosition],
                lineWidth: 0,
                text: editingText,
                fontSize: currentFontSize
            )
            annotations.append(annotation)
            onAnnotationsChanged?()
        }
        isEditingText = false
        editingText = ""
        stopCursorBlink()
        needsDisplay = true
    }

    /// Handle a key event during text editing. Returns true if consumed.
    func handleKeyDown(_ event: NSEvent) -> Bool {
        guard isEditingText else { return false }

        // Cmd+Z while editing: cancel current text
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "z" {
            isEditingText = false
            editingText = ""
            stopCursorBlink()
            needsDisplay = true
            onAnnotationsChanged?()
            return true
        }

        switch event.keyCode {
        case 36: // Return — finalize
            commitTextIfNeeded()
            return true
        case 53: // Escape — finalize
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

    // MARK: - Mouse handling

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if currentTool == .text {
            commitTextIfNeeded()
            // Start new text editing
            isEditingText = true
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
        let point = convert(event.locationInWindow, from: nil)
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
        guard let annotation = currentAnnotation else { return }
        if annotation.points.count >= 2 {
            annotations.append(annotation)
            onAnnotationsChanged?()
        }
        currentAnnotation = nil
        needsDisplay = true
    }

    // MARK: - Scroll wheel (font size)

    override func scrollWheel(with event: NSEvent) {
        guard currentTool == .text else {
            super.scrollWheel(with: event)
            return
        }
        currentFontSize = max(10, min(48, currentFontSize + event.scrollingDeltaY * 0.5))
        if isEditingText { needsDisplay = true }
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

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        for annotation in annotations {
            drawAnnotation(annotation)
        }
        if let current = currentAnnotation {
            drawAnnotation(current)
        }
        // Draw in-progress text
        if isEditingText {
            drawTextContent(editingText, at: editingPosition, fontSize: currentFontSize, color: currentColor, showCursor: cursorVisible)
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
            drawTextContent(annotation.text, at: pos, fontSize: annotation.fontSize, color: annotation.color, showCursor: false)
        }
    }

    private func drawTextContent(_ text: String, at position: CGPoint, fontSize: CGFloat, color: NSColor, showCursor: Bool) {
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

        // Semi-transparent background pill
        NSColor.black.withAlphaComponent(0.5).setFill()
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
