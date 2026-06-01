import AppKit
import XCTest
@testable import ImageGrabKit

@MainActor
final class SpriteLayerViewTests: XCTestCase {
    func testMarqueeLiftsRegionIntoSprite() throws {
        let layer = makeLayer()

        layer.handlePointerDown(at: CGPoint(x: 20, y: 20))
        layer.handlePointerDragged(to: CGPoint(x: 90, y: 100))
        layer.handlePointerUp(at: CGPoint(x: 90, y: 100))

        XCTAssertEqual(layer.debugSprites.count, 1)
        XCTAssertEqual(layer.debugSelectedIndex, 0)
        let rect = layer.debugSprites[0].sourceRect
        assertRect(rect, x: 20, y: 20, width: 70, height: 80)
        // Freshly lifted: sits exactly over its origin until dragged.
        XCTAssertEqual(layer.debugSprites[0].offset.width, 0, accuracy: 0.01)
        XCTAssertEqual(layer.debugSprites[0].offset.height, 0, accuracy: 0.01)
    }

    func testMarqueeNormalizesWhenDraggedUpAndLeft() throws {
        let layer = makeLayer()

        layer.handlePointerDown(at: CGPoint(x: 100, y: 120))
        layer.handlePointerDragged(to: CGPoint(x: 40, y: 50))
        layer.handlePointerUp(at: CGPoint(x: 40, y: 50))

        XCTAssertEqual(layer.debugSprites.count, 1)
        assertRect(layer.debugSprites[0].sourceRect, x: 40, y: 50, width: 60, height: 70)
    }

    func testTinyMarqueeDoesNotLift() throws {
        let layer = makeLayer()

        layer.handlePointerDown(at: CGPoint(x: 20, y: 20))
        layer.handlePointerDragged(to: CGPoint(x: 24, y: 24)) // below minLiftSize
        layer.handlePointerUp(at: CGPoint(x: 24, y: 24))

        XCTAssertTrue(layer.debugSprites.isEmpty)
    }

    func testLiftedSpriteCanBeDragged() throws {
        let layer = makeLayer()

        // Lift a region.
        layer.handlePointerDown(at: CGPoint(x: 20, y: 20))
        layer.handlePointerDragged(to: CGPoint(x: 90, y: 100))
        layer.handlePointerUp(at: CGPoint(x: 90, y: 100))
        XCTAssertEqual(layer.debugSprites.count, 1)

        // Press inside it and drag: the sprite moves, no new sprite is created.
        layer.handlePointerDown(at: CGPoint(x: 55, y: 60))
        layer.handlePointerDragged(to: CGPoint(x: 75, y: 90))
        layer.handlePointerUp(at: CGPoint(x: 75, y: 90))

        XCTAssertEqual(layer.debugSprites.count, 1)
        XCTAssertEqual(layer.debugSprites[0].offset.width, 20, accuracy: 0.01)
        XCTAssertEqual(layer.debugSprites[0].offset.height, 30, accuracy: 0.01)
    }

    func testDeleteRemovesSpriteButKeepsPatch() throws {
        let layer = makeLayer()

        // Lift a region (creates a patch + a selected sprite).
        layer.handlePointerDown(at: CGPoint(x: 20, y: 20))
        layer.handlePointerDragged(to: CGPoint(x: 90, y: 100))
        layer.handlePointerUp(at: CGPoint(x: 90, y: 100))
        XCTAssertEqual(layer.debugSprites.count, 1)
        XCTAssertEqual(layer.debugPatches.count, 1)
        XCTAssertEqual(layer.debugSelectedIndex, 0)

        // Deleting must remove the movable sprite but keep the hole patched, so the
        // element actually disappears instead of the original showing through.
        XCTAssertTrue(layer.deleteSelectedSprite())
        XCTAssertTrue(layer.debugSprites.isEmpty)
        XCTAssertEqual(layer.debugPatches.count, 1)
        XCTAssertNil(layer.debugSelectedIndex)

        // The patch alone still changes the exported image.
        let base = makeImage(width: 240, height: 180, color: .systemBlue)
        XCTAssertFalse(layer.compositeOnto(image: base) === base)
    }

    func testDeleteWithNoSelectionDoesNothing() throws {
        let layer = makeLayer()
        XCTAssertFalse(layer.deleteSelectedSprite())
    }

    func testUndoRestoresDeletedSprite() throws {
        let layer = makeLayer()

        layer.handlePointerDown(at: CGPoint(x: 20, y: 20))
        layer.handlePointerDragged(to: CGPoint(x: 90, y: 100))
        layer.handlePointerUp(at: CGPoint(x: 90, y: 100))
        layer.deleteSelectedSprite()
        XCTAssertTrue(layer.debugSprites.isEmpty)

        layer.undo()
        XCTAssertEqual(layer.debugSprites.count, 1)
        XCTAssertEqual(layer.debugPatches.count, 1)
    }

    func testUndoRedoLift() throws {
        let layer = makeLayer()

        layer.handlePointerDown(at: CGPoint(x: 20, y: 20))
        layer.handlePointerDragged(to: CGPoint(x: 90, y: 100))
        layer.handlePointerUp(at: CGPoint(x: 90, y: 100))

        XCTAssertTrue(layer.canUndo)
        XCTAssertFalse(layer.canRedo)

        layer.undo()
        XCTAssertTrue(layer.debugSprites.isEmpty)
        XCTAssertFalse(layer.canUndo)
        XCTAssertTrue(layer.canRedo)

        layer.redo()
        XCTAssertEqual(layer.debugSprites.count, 1)
        XCTAssertTrue(layer.canUndo)
        XCTAssertFalse(layer.canRedo)
    }

    func testCompositeReturnsImageOfSourceSize() throws {
        let layer = makeLayer()

        layer.handlePointerDown(at: CGPoint(x: 20, y: 20))
        layer.handlePointerDragged(to: CGPoint(x: 90, y: 100))
        layer.handlePointerUp(at: CGPoint(x: 90, y: 100))
        layer.handlePointerDown(at: CGPoint(x: 55, y: 60))
        layer.handlePointerDragged(to: CGPoint(x: 75, y: 90))
        layer.handlePointerUp(at: CGPoint(x: 75, y: 90))

        let base = makeImage(width: 240, height: 180, color: .systemBlue)
        let result = layer.compositeOnto(image: base)
        XCTAssertEqual(result.size.width, 240, accuracy: 0.01)
        XCTAssertEqual(result.size.height, 180, accuracy: 0.01)
    }

    func testCompositeWithoutSpritesReturnsOriginal() throws {
        let layer = makeLayer()
        let base = makeImage(width: 240, height: 180, color: .systemRed)
        XCTAssertTrue(layer.compositeOnto(image: base) === base)
    }

    // MARK: - Helpers

    private func makeLayer() -> SpriteLayerView {
        let layer = SpriteLayerView(frame: NSRect(x: 0, y: 0, width: 240, height: 180))
        layer.setSource(makeImage(width: 240, height: 180, color: .systemBlue))
        return layer
    }

    private func makeImage(width: Int, height: Int, color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        color.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        image.unlockFocus()
        return image
    }

    private func assertRect(_ rect: CGRect, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat,
                            file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(rect.minX, x, accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(rect.minY, y, accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(rect.width, width, accuracy: 0.5, file: file, line: line)
        XCTAssertEqual(rect.height, height, accuracy: 0.5, file: file, line: line)
    }
}
