# Annotation Editor Design

## Purpose

Add simple image markup to the capture preview window so users can draw boxes, arrows, and freehand pen strokes on screenshots before saving.

## Scope

- Tools: Pen (freehand), Box (stroked rectangle), Arrow (line with arrowhead)
- Colors: 5 presets — red, blue, green, yellow, white
- Undo: Cmd+Z removes last annotation; undo button in toolbar
- No layers, no text, no fill, no resize-after-drawing

## Architecture

All annotation code lives in a new `AnnotationOverlayView.swift` file. The existing `CapturePreviewWindow` gains:
1. An annotation toolbar (tool + color selection + undo)
2. An `AnnotationOverlayView` layered on top of the image view

### AnnotationOverlayView (NSView)

Transparent view overlaying the image. Handles mouse events and renders annotations.

**Data model:**

```swift
enum AnnotationTool { case pen, box, arrow }

struct Annotation {
    let tool: AnnotationTool
    let color: NSColor
    let points: [CGPoint] // pen: all points, box/arrow: [start, end]
    let lineWidth: CGFloat
}
```

**Mouse handling:**
- `mouseDown`: start new annotation, record start point
- `mouseDragged`: for pen, append point; for box/arrow, update end point
- `mouseUp`: finalize annotation, append to `annotations` array

**Rendering (`draw(_:)`):**
- Pen: `NSBezierPath` through all points, round line join/cap
- Box: `NSBezierPath(rect:)` from start to end corner, stroke only
- Arrow: Line from start to end, with a triangular arrowhead at the end point

### Annotation Toolbar

Horizontal bar above the image in the preview window.

**Layout:** `[Pen] [Box] [Arrow]  |  (red) (blue) (green) (yellow) (white)  |  [Undo]`

- Tool buttons: SF Symbols (`pencil.tip`, `rectangle`, `arrow.up.right`)
- Selected tool gets highlighted background
- Color dots: small circles, selected gets a ring/border
- Undo button: SF Symbol `arrow.uturn.backward`, disabled when no annotations

### Compositing on Save

When the user clicks Save or Save & Copy Path:
1. Create a copy of the full-resolution `NSImage`
2. Lock focus on the copy
3. Scale annotation coordinates from view-space to image-space (view size vs image size ratio)
4. Draw all annotations using the same rendering logic, with line widths scaled proportionally
5. Unlock focus
6. Pass the composited image to the existing save flow

### Stroke Sizing

- Base line width: 3pt for pen and box, 2.5pt for arrow shaft
- On save compositing: multiply by (image dimension / view dimension) so strokes look consistent at full resolution
- Arrowhead size: 12pt in view, scaled similarly

## Files Changed

- `CaptureOverlayWindow.swift` — add annotation toolbar, overlay view, wire up compositing on save
- `AnnotationOverlayView.swift` (new) — overlay view with mouse handling, rendering, annotation data model

## Out of Scope

- Text annotations
- Filled shapes
- Move/resize existing annotations
- Annotation persistence (annotations exist only during preview)
- Export annotations separately from image
