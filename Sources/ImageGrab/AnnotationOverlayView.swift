import AppKit

enum AnnotationTool {
    case pen, box, arrow
}

struct Annotation {
    let tool: AnnotationTool
    let color: NSColor
    var points: [CGPoint]
    let lineWidth: CGFloat
}

@MainActor
final class AnnotationOverlayView: NSView {
    var currentTool: AnnotationTool = .box
    var currentColor: NSColor = .systemRed
    var onAnnotationsChanged: (@MainActor () -> Void)?

    private var annotations: [Annotation] = []
    private var currentAnnotation: Annotation?
    private let baseLineWidth: CGFloat = 3.0
    private let arrowLineWidth: CGFloat = 2.5

    var hasAnnotations: Bool { !annotations.isEmpty }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    func undo() {
        guard !annotations.isEmpty else { return }
        annotations.removeLast()
        needsDisplay = true
        onAnnotationsChanged?()
    }

    // MARK: - Mouse handling

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
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

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        for annotation in annotations {
            drawAnnotation(annotation)
        }
        if let current = currentAnnotation {
            drawAnnotation(current)
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

            // Shaft
            let shaft = NSBezierPath()
            shaft.lineWidth = annotation.lineWidth
            shaft.lineCapStyle = .round
            shaft.move(to: start)
            shaft.line(to: end)
            shaft.stroke()

            // Arrowhead — sized proportional to line width
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
                lineWidth: annotation.lineWidth * scale
            )
            drawAnnotation(scaled)
        }

        result.unlockFocus()
        return result
    }
}
