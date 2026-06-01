import AppKit
import XCTest
@testable import ImageGrabKit

@MainActor
final class AnnotationOverlayViewTests: XCTestCase {
    func testBoxAnnotationCanBeDraggedAfterSelection() throws {
        let overlay = makeOverlay()

        overlay.currentTool = .box

        overlay.handlePointerDown(at: CGPoint(x: 20, y: 20))
        overlay.handlePointerDragged(to: CGPoint(x: 80, y: 90))
        overlay.handlePointerUp(at: CGPoint(x: 80, y: 90))

        XCTAssertEqual(overlay.debugAnnotations.count, 1)
        assertPoint(overlay.debugAnnotations[0].points[0], x: 20, y: 20)
        assertPoint(overlay.debugAnnotations[0].points[1], x: 80, y: 90)

        overlay.handlePointerDown(at: CGPoint(x: 40, y: 40))
        overlay.handlePointerDragged(to: CGPoint(x: 60, y: 70))
        overlay.handlePointerUp(at: CGPoint(x: 60, y: 70))

        XCTAssertEqual(overlay.debugAnnotations.count, 1)
        assertPoint(overlay.debugAnnotations[0].points[0], x: 40, y: 50)
        assertPoint(overlay.debugAnnotations[0].points[1], x: 100, y: 120)
    }

    func testArrowAnnotationCanBeDraggedFromLineHit() throws {
        let overlay = makeOverlay()

        overlay.currentTool = .arrow

        overlay.handlePointerDown(at: CGPoint(x: 20, y: 20))
        overlay.handlePointerDragged(to: CGPoint(x: 100, y: 60))
        overlay.handlePointerUp(at: CGPoint(x: 100, y: 60))

        XCTAssertEqual(overlay.debugAnnotations.count, 1)

        overlay.handlePointerDown(at: CGPoint(x: 60, y: 40))
        overlay.handlePointerDragged(to: CGPoint(x: 70, y: 50))
        overlay.handlePointerUp(at: CGPoint(x: 70, y: 50))

        assertPoint(overlay.debugAnnotations[0].points[0], x: 30, y: 30)
        assertPoint(overlay.debugAnnotations[0].points[1], x: 110, y: 70)
    }

    func testTextAnnotationCommitsAndCanBeDragged() throws {
        let overlay = makeOverlay()

        overlay.currentTool = .text

        overlay.handlePointerDown(at: CGPoint(x: 40, y: 40))
        XCTAssertTrue(overlay.debugIsEditingText)

        overlay.debugEditingText = "Hi"
        overlay.debugCommitEditing()

        XCTAssertFalse(overlay.debugIsEditingText)
        XCTAssertEqual(overlay.debugAnnotations.count, 1)
        XCTAssertEqual(overlay.debugAnnotations[0].text, "Hi")
        assertPoint(overlay.debugAnnotations[0].points[0], x: 40, y: 40)

        overlay.currentTool = .box
        overlay.handlePointerDown(at: CGPoint(x: 44, y: 44))
        overlay.handlePointerDragged(to: CGPoint(x: 64, y: 74))
        overlay.handlePointerUp(at: CGPoint(x: 64, y: 74))

        XCTAssertEqual(overlay.debugAnnotations.count, 1)
        assertPoint(overlay.debugAnnotations[0].points[0], x: 60, y: 70)
    }

    func testCommittingEmptyTextDiscardsAnnotation() throws {
        let overlay = makeOverlay()

        overlay.currentTool = .text
        overlay.handlePointerDown(at: CGPoint(x: 40, y: 40))
        XCTAssertTrue(overlay.debugIsEditingText)

        // Leaving the editor without typing should not create an annotation.
        overlay.debugCommitEditing()
        XCTAssertFalse(overlay.debugIsEditingText)
        XCTAssertEqual(overlay.debugAnnotations.count, 0)
    }

    func testClickingTextReopensEditingOnExistingAnnotation() throws {
        let overlay = makeOverlay()

        overlay.currentTool = .text

        overlay.handlePointerDown(at: CGPoint(x: 30, y: 30))
        overlay.debugEditingText = "Hi"
        overlay.debugCommitEditing()

        // Clicking the text with the Text tool active reopens it for editing,
        // seeded with the existing contents.
        overlay.handlePointerDown(at: CGPoint(x: 34, y: 34))
        XCTAssertTrue(overlay.debugIsEditingText)
        XCTAssertEqual(overlay.debugEditingText, "Hi")

        overlay.debugEditingText = "Hi!"
        overlay.debugCommitEditing()

        XCTAssertEqual(overlay.debugAnnotations.count, 1)
        XCTAssertEqual(overlay.debugAnnotations[0].text, "Hi!")
    }

    func testMultiLineTextCommits() throws {
        let overlay = makeOverlay()

        overlay.currentTool = .text
        overlay.handlePointerDown(at: CGPoint(x: 40, y: 100))

        overlay.debugEditingText = "Hi\nThere"
        overlay.debugCommitEditing()

        XCTAssertFalse(overlay.debugIsEditingText)
        XCTAssertEqual(overlay.debugAnnotations.count, 1)
        XCTAssertEqual(overlay.debugAnnotations[0].text, "Hi\nThere")
    }

    func testClickingExistingTextWithTextToolReopensEditingImmediately() throws {
        let overlay = makeOverlay()

        overlay.currentTool = .text
        overlay.handlePointerDown(at: CGPoint(x: 40, y: 100))
        overlay.debugEditingText = "Hi\nThere"
        overlay.debugCommitEditing()

        overlay.handlePointerDown(at: CGPoint(x: 44, y: 82))
        XCTAssertTrue(overlay.debugIsEditingText)
        XCTAssertEqual(overlay.debugEditingText, "Hi\nThere")

        overlay.debugEditingText = "Hi\nThere!"
        overlay.debugCommitEditing()

        XCTAssertEqual(overlay.debugAnnotations.count, 1)
        XCTAssertEqual(overlay.debugAnnotations[0].text, "Hi\nThere!")
    }

    func testSingleClickWithNonTextToolSelectsWithoutEditing() throws {
        let overlay = makeOverlay()

        overlay.currentTool = .text
        overlay.handlePointerDown(at: CGPoint(x: 40, y: 100))
        overlay.debugEditingText = "Hi"
        overlay.debugCommitEditing()
        XCTAssertFalse(overlay.debugIsEditingText)

        // A single click with a non-text tool should select (for dragging), not edit.
        overlay.currentTool = .box
        overlay.handlePointerDown(at: CGPoint(x: 44, y: 100))
        overlay.handlePointerUp(at: CGPoint(x: 44, y: 100))
        XCTAssertFalse(overlay.debugIsEditingText)
        XCTAssertEqual(overlay.debugAnnotations.count, 1)
        XCTAssertEqual(overlay.debugAnnotations[0].text, "Hi")
    }

    func testDoubleClickReopensTextEditingWithNonTextTool() throws {
        let overlay = makeOverlay()

        overlay.currentTool = .text
        overlay.handlePointerDown(at: CGPoint(x: 40, y: 100))
        overlay.debugEditingText = "Hi"
        overlay.debugCommitEditing()

        // Double-click with a non-text tool re-enters editing on the existing text.
        overlay.currentTool = .box
        overlay.handlePointerDown(at: CGPoint(x: 44, y: 100), clickCount: 2)
        XCTAssertTrue(overlay.debugIsEditingText)
        XCTAssertEqual(overlay.debugEditingText, "Hi")

        overlay.debugEditingText = "Hi!"
        overlay.debugCommitEditing()

        XCTAssertEqual(overlay.debugAnnotations.count, 1)
        XCTAssertEqual(overlay.debugAnnotations[0].text, "Hi!")
    }

    func testRedoRestoresLastUndoneAnnotation() throws {
        let overlay = makeOverlay()

        overlay.currentTool = .box
        overlay.handlePointerDown(at: CGPoint(x: 20, y: 20))
        overlay.handlePointerDragged(to: CGPoint(x: 80, y: 90))
        overlay.handlePointerUp(at: CGPoint(x: 80, y: 90))

        XCTAssertTrue(overlay.canUndo)
        XCTAssertFalse(overlay.canRedo)

        overlay.undo()

        XCTAssertEqual(overlay.debugAnnotations.count, 0)
        XCTAssertFalse(overlay.canUndo)
        XCTAssertTrue(overlay.canRedo)

        overlay.redo()

        XCTAssertEqual(overlay.debugAnnotations.count, 1)
        XCTAssertTrue(overlay.canUndo)
        XCTAssertFalse(overlay.canRedo)
        assertPoint(overlay.debugAnnotations[0].points[0], x: 20, y: 20)
        assertPoint(overlay.debugAnnotations[0].points[1], x: 80, y: 90)
    }

    func testNewAnnotationClearsRedoStack() throws {
        let overlay = makeOverlay()

        overlay.currentTool = .box
        overlay.handlePointerDown(at: CGPoint(x: 20, y: 20))
        overlay.handlePointerDragged(to: CGPoint(x: 80, y: 90))
        overlay.handlePointerUp(at: CGPoint(x: 80, y: 90))
        overlay.undo()
        XCTAssertTrue(overlay.canRedo)

        overlay.handlePointerDown(at: CGPoint(x: 30, y: 30))
        overlay.handlePointerDragged(to: CGPoint(x: 70, y: 75))
        overlay.handlePointerUp(at: CGPoint(x: 70, y: 75))

        XCTAssertFalse(overlay.canRedo)
        XCTAssertEqual(overlay.debugAnnotations.count, 1)
        assertPoint(overlay.debugAnnotations[0].points[0], x: 30, y: 30)
        assertPoint(overlay.debugAnnotations[0].points[1], x: 70, y: 75)
    }

    private func makeOverlay() -> AnnotationOverlayView {
        AnnotationOverlayView(frame: NSRect(x: 0, y: 0, width: 240, height: 180))
    }

    private func assertPoint(_ point: CGPoint, x: CGFloat, y: CGFloat, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(point.x, x, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(point.y, y, accuracy: 0.01, file: file, line: line)
    }
}
