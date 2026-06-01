import AppKit

/// A region lifted out of the screenshot into a free-floating, draggable layer.
/// `sourceRect` is the original location in view coordinates (bottom-left origin,
/// matching the overlay); `offset` is how far the user has since dragged it.
struct Sprite {
    let id: UUID
    let image: NSImage          // the lifted pixels, cropped from the full-res capture
    let sourceRect: CGRect      // original location, in view coordinates
    var offset: CGSize          // current drag offset from the source location

    var currentRect: CGRect {
        sourceRect.offsetBy(dx: offset.width, dy: offset.height)
    }
}

/// A permanent patch over a vacated region. Created when a region is lifted and kept
/// independently of the sprite, so deleting the sprite leaves the hole filled (the
/// element stays gone) and moving the sprite leaves its origin patched.
struct Patch {
    let rect: CGRect
    let color: NSColor
}

/// Snapshot of the editable state for undo/redo — patches and sprites must move
/// together (lifting adds both; deleting removes only the sprite).
private struct LayerState {
    var patches: [Patch]
    var sprites: [Sprite]
}

/// Overlay that turns a static screenshot into movable pieces. The user marquees a
/// region to "lift" it into a `Sprite`, then drags the sprite around; the hole left
/// behind is patched with a colour sampled from the screenshot just outside the
/// lifted region. This is the manual-manipulation layer of the "rearrange" feature:
/// no model is in the loop, so dragging is instant.
///
/// It sits directly above the screenshot's `NSImageView` and below the annotation
/// overlay. When `isActive` is false it draws the current sprite layout but ignores
/// all events (so the annotation tools above it receive clicks instead).
@MainActor
final class SpriteLayerView: NSView {
    var onSpritesChanged: (@MainActor () -> Void)?

    /// When false the view is display-only: it renders sprites but `hitTest` returns
    /// nil so clicks fall through to the annotation overlay.
    var isActive = false {
        didSet { window?.invalidateCursorRects(for: self) }
    }

    private var sprites: [Sprite] = []
    private var patches: [Patch] = []
    private var undoStack: [LayerState] = []
    private var redoStack: [LayerState] = []

    private var selectedIndex: Int?
    private var movingIndex: Int?
    private var lastDragPoint: CGPoint?
    private var didMove = false

    /// In-progress marquee for lifting a new region (view coordinates).
    private var marqueeOrigin: CGPoint?
    private var marqueeRect: CGRect?

    /// Cached RGBA bytes of the source capture (top-left origin, row-major) so the
    /// background colour around a lifted region can be sampled cheaply.
    private var sourceCGImage: CGImage?
    private var pixels: [UInt8]?
    private var pixelWidth = 0
    private var pixelHeight = 0

    private let minLiftSize: CGFloat = 8

    var hasSprites: Bool { !sprites.isEmpty || !patches.isEmpty }
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    // MARK: - Source

    /// Provide the captured screenshot so regions can be cropped at full resolution
    /// and background colours sampled. Call once, before any interaction.
    func setSource(_ image: NSImage) {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        sourceCGImage = cg
        pixelWidth = cg.width
        pixelHeight = cg.height

        var data = [UInt8](repeating: 0, count: pixelWidth * pixelHeight * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        data.withUnsafeMutableBytes { raw in
            if let ctx = CGContext(
                data: raw.baseAddress,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: pixelWidth * 4,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) {
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
            }
        }
        pixels = data
    }

    // MARK: - View

    override var isFlipped: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Display-only when inactive: let the annotation overlay above us handle clicks.
        isActive ? super.hitTest(point) : nil
    }

    override func resetCursorRects() {
        guard isActive else { return }
        // Precise crosshair over empty space so you can see exactly where the marquee
        // edge falls; open hand over an existing piece (you'll move it). Later cursor
        // rects win on overlap, so the hand rects are added after the full-bounds one.
        addCursorRect(bounds, cursor: .crosshair)
        for sprite in sprites {
            let rect = sprite.currentRect.intersection(bounds)
            if !rect.isEmpty {
                addCursorRect(rect, cursor: .openHand)
            }
        }
    }

    // MARK: - Mouse handling
    //
    // Mirrors AnnotationOverlayView: the override methods just forward to the
    // `handlePointer*` entry points, which are also driven directly by tests.

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        handlePointerDown(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseDragged(with event: NSEvent) {
        handlePointerDragged(to: convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        handlePointerUp(at: convert(event.locationInWindow, from: nil))
    }

    func handlePointerDown(at point: CGPoint) {
        if let hit = hitTestSprite(at: point) {
            selectedIndex = hit
            movingIndex = hit
            lastDragPoint = point
            didMove = false
            NSCursor.closedHand.set() // grabbing
            needsDisplay = true
            return
        }

        // Empty space: start a marquee to lift a new region.
        selectedIndex = nil
        marqueeOrigin = point
        marqueeRect = CGRect(origin: point, size: .zero)
        needsDisplay = true
    }

    func handlePointerDragged(to point: CGPoint) {
        if let movingIndex, sprites.indices.contains(movingIndex), let last = lastDragPoint {
            let dx = point.x - last.x
            let dy = point.y - last.y
            if dx != 0 || dy != 0 {
                if !didMove {
                    // Capture one undo step for the whole move, before mutating.
                    pushUndoSnapshot()
                    didMove = true
                }
                sprites[movingIndex].offset.width += dx
                sprites[movingIndex].offset.height += dy
                lastDragPoint = point
                needsDisplay = true
                onSpritesChanged?()
            }
            return
        }

        if let origin = marqueeOrigin {
            marqueeRect = CGRect(
                x: min(origin.x, point.x),
                y: min(origin.y, point.y),
                width: abs(point.x - origin.x),
                height: abs(point.y - origin.y)
            )
            needsDisplay = true
        }
    }

    func handlePointerUp(at point: CGPoint) {
        _ = point
        if movingIndex != nil {
            movingIndex = nil
            lastDragPoint = nil
            didMove = false
            needsDisplay = true
            window?.invalidateCursorRects(for: self) // hand rects follow the moved piece
            return
        }

        if let rect = marqueeRect {
            marqueeOrigin = nil
            marqueeRect = nil
            if rect.width >= minLiftSize, rect.height >= minLiftSize {
                liftRegion(rect)
            }
            needsDisplay = true
        }
    }

    override func keyDown(with event: NSEvent) {
        // Handle delete/escape directly while we're first responder, rather than
        // relying on the event walking back up to the window.
        if isActive, handleKeyDown(event) { return }
        super.keyDown(with: event)
    }

    /// Handle a key event while rearrange mode is active. Returns true if consumed.
    func handleKeyDown(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 51, 117: // Delete / Forward-delete: remove the selected sprite (and its element).
            return deleteSelectedSprite()
        case 53: // Escape: clear selection first; only fall through to close when nothing is selected.
            if selectedIndex != nil {
                selectedIndex = nil
                needsDisplay = true
                return true
            }
            return false
        default:
            return false
        }
    }

    /// Remove the selected sprite, leaving its patched hole behind ("remove this
    /// element"). Returns true if something was deleted. Shared by the Delete key
    /// and the right-click menu.
    @discardableResult
    func deleteSelectedSprite() -> Bool {
        guard let index = selectedIndex, sprites.indices.contains(index) else { return false }
        pushUndoSnapshot()
        sprites.remove(at: index)
        selectedIndex = nil
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
        onSpritesChanged?()
        return true
    }

    // MARK: - Right-click menu

    override func menu(for event: NSEvent) -> NSMenu? {
        guard isActive else { return nil }
        let point = convert(event.locationInWindow, from: nil)
        guard let hit = hitTestSprite(at: point) else { return nil }
        selectedIndex = hit
        needsDisplay = true

        let menu = NSMenu()
        let delete = NSMenuItem(title: "Delete", action: #selector(deleteMenuAction), keyEquivalent: "")
        delete.target = self
        menu.addItem(delete)
        return menu
    }

    @objc private func deleteMenuAction() {
        deleteSelectedSprite()
    }

    // MARK: - Lift / undo

    private func liftRegion(_ rect: CGRect) {
        guard let cropped = crop(viewRect: rect) else { return }
        let fill = backgroundColor(around: rect) ?? .windowBackgroundColor
        pushUndoSnapshot()
        // The patch permanently covers the original location; the sprite is the
        // movable copy. They're separate so deleting the sprite leaves the hole filled.
        patches.append(Patch(rect: rect, color: fill))
        sprites.append(Sprite(id: UUID(), image: cropped, sourceRect: rect, offset: .zero))
        selectedIndex = sprites.indices.last
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
        onSpritesChanged?()
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(LayerState(patches: patches, sprites: sprites))
        restore(previous)
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(LayerState(patches: patches, sprites: sprites))
        restore(next)
    }

    private func restore(_ state: LayerState) {
        patches = state.patches
        sprites = state.sprites
        selectedIndex = nil
        needsDisplay = true
        window?.invalidateCursorRects(for: self)
        onSpritesChanged?()
    }

    private func pushUndoSnapshot() {
        undoStack.append(LayerState(patches: patches, sprites: sprites))
        redoStack.removeAll()
    }

    // MARK: - Hit testing

    private func hitTestSprite(at point: CGPoint) -> Int? {
        // Topmost (last drawn) wins.
        for index in sprites.indices.reversed() where sprites[index].currentRect.contains(point) {
            return index
        }
        return nil
    }

    // MARK: - Cropping & colour sampling

    /// Map a view-space rect (bottom-left origin) to the full-res capture and crop it.
    private func crop(viewRect: CGRect) -> NSImage? {
        guard let cg = sourceCGImage, bounds.width > 0, bounds.height > 0 else { return nil }
        let sx = CGFloat(cg.width) / bounds.width
        let sy = CGFloat(cg.height) / bounds.height
        // Flip Y: the view's origin is bottom-left, the CGImage's is top-left.
        let pixelRect = CGRect(
            x: viewRect.minX * sx,
            y: (bounds.height - viewRect.maxY) * sy,
            width: viewRect.width * sx,
            height: viewRect.height * sy
        ).integral
        guard let cropped = cg.cropping(to: pixelRect) else { return nil }
        return NSImage(cgImage: cropped, size: viewRect.size)
    }

    /// Average colour of the screenshot just outside a lifted region, used to patch
    /// the hole. Samples a ring of points a few pixels beyond each edge — good enough
    /// for the flat / gradient backgrounds typical of app UIs.
    private func backgroundColor(around viewRect: CGRect) -> NSColor? {
        guard pixels != nil, bounds.width > 0, bounds.height > 0 else { return nil }
        let sx = CGFloat(pixelWidth) / bounds.width
        let sy = CGFloat(pixelHeight) / bounds.height
        let margin: CGFloat = 3

        // Work in top-left pixel space.
        let left = viewRect.minX * sx
        let right = viewRect.maxX * sx
        let top = (bounds.height - viewRect.maxY) * sy
        let bottom = (bounds.height - viewRect.minY) * sy

        var samples: [(Int, Int)] = []
        let mx = margin * sx
        let my = margin * sy
        for t in stride(from: 0.0, through: 1.0, by: 0.25) {
            let x = Int(left + (right - left) * t)
            let y = Int(top + (bottom - top) * t)
            samples.append((x, Int(top - my)))       // above
            samples.append((x, Int(bottom + my)))    // below
            samples.append((Int(left - mx), y))      // left
            samples.append((Int(right + mx), y))     // right
        }

        var r = 0.0, g = 0.0, b = 0.0, count = 0.0
        for (x, y) in samples {
            guard let c = pixelColor(x: x, yTop: y) else { continue }
            r += c.0; g += c.1; b += c.2; count += 1
        }
        guard count > 0 else { return nil }
        return NSColor(srgbRed: r / count, green: g / count, blue: b / count, alpha: 1)
    }

    /// Read a pixel by top-left coordinate from the cached RGBA buffer. The buffer was
    /// produced by a CGContext (bottom-left origin), so the row is flipped on read.
    private func pixelColor(x: Int, yTop: Int) -> (Double, Double, Double)? {
        guard let data = pixels, x >= 0, x < pixelWidth, yTop >= 0, yTop < pixelHeight else { return nil }
        let yBottom = pixelHeight - 1 - yTop
        let i = (yBottom * pixelWidth + x) * 4
        return (Double(data[i]) / 255, Double(data[i + 1]) / 255, Double(data[i + 2]) / 255)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        // Patch every vacated hole first (these persist even after a sprite is
        // deleted), then draw the movable sprites on top.
        for patch in patches {
            patch.color.setFill()
            patch.rect.fill()
        }
        for sprite in sprites {
            sprite.image.draw(in: sprite.currentRect)
        }

        if let index = selectedIndex, sprites.indices.contains(index) {
            drawSelection(sprites[index].currentRect)
        }
        if let rect = marqueeRect {
            drawMarquee(rect)
        }
    }

    private func drawSelection(_ rect: CGRect) {
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 1.5
        NSColor.controlAccentColor.setStroke()
        path.setLineDash([5, 3], count: 2, phase: 0)
        path.stroke()
    }

    private func drawMarquee(_ rect: CGRect) {
        NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
        rect.fill()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 1
        NSColor.controlAccentColor.setStroke()
        path.setLineDash([4, 3], count: 2, phase: 0)
        path.stroke()
    }

    // MARK: - Compositing

    /// Flatten the sprite layout onto `image`: fill the vacated holes, then draw each
    /// sprite at its moved location. Mirrors AnnotationOverlayView.compositeOnto.
    func compositeOnto(image: NSImage) -> NSImage {
        guard !patches.isEmpty || !sprites.isEmpty, bounds.width > 0 else { return image }

        let scale = image.size.width / bounds.width
        let result = NSImage(size: image.size)
        result.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: image.size))

        for patch in patches {
            patch.color.setFill()
            scaleRect(patch.rect, by: scale).fill()
        }
        for sprite in sprites {
            sprite.image.draw(in: scaleRect(sprite.currentRect, by: scale))
        }

        result.unlockFocus()
        return result
    }

    private func scaleRect(_ rect: CGRect, by scale: CGFloat) -> CGRect {
        CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
    }
}

#if DEBUG
extension SpriteLayerView {
    var debugSprites: [Sprite] { sprites }
    var debugPatches: [Patch] { patches }
    var debugSelectedIndex: Int? { selectedIndex }
}
#endif
