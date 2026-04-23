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

        XCTAssertTrue(overlay.handleKeyDown(key("H")))
        XCTAssertTrue(overlay.handleKeyDown(key("i")))
        XCTAssertTrue(overlay.handleKeyDown(key("\r", keyCode: 36)))

        XCTAssertEqual(overlay.debugAnnotations.count, 1)
        XCTAssertEqual(overlay.debugAnnotations[0].text, "Hi")
        assertPoint(overlay.debugAnnotations[0].points[0], x: 40, y: 40)

        overlay.handlePointerDown(at: CGPoint(x: 44, y: 44))
        overlay.handlePointerDragged(to: CGPoint(x: 64, y: 74))
        overlay.handlePointerUp(at: CGPoint(x: 64, y: 74))

        XCTAssertEqual(overlay.debugAnnotations.count, 1)
        assertPoint(overlay.debugAnnotations[0].points[0], x: 60, y: 70)
    }

    func testClickingTextReopensEditingOnExistingAnnotation() throws {
        let overlay = makeOverlay()

        overlay.currentTool = .text

        overlay.handlePointerDown(at: CGPoint(x: 30, y: 30))
        _ = overlay.handleKeyDown(key("H"))
        _ = overlay.handleKeyDown(key("i"))
        _ = overlay.handleKeyDown(key("\r", keyCode: 36))

        overlay.handlePointerDown(at: CGPoint(x: 34, y: 34))
        overlay.handlePointerUp(at: CGPoint(x: 34, y: 34))
        XCTAssertTrue(overlay.debugIsEditingText)

        _ = overlay.handleKeyDown(key("!"))
        _ = overlay.handleKeyDown(key("\r", keyCode: 36))

        XCTAssertEqual(overlay.debugAnnotations.count, 1)
        XCTAssertEqual(overlay.debugAnnotations[0].text, "Hi!")
    }

    private func makeOverlay() -> AnnotationOverlayView {
        AnnotationOverlayView(frame: NSRect(x: 0, y: 0, width: 240, height: 180))
    }

    private func key(_ characters: String, keyCode: UInt16 = 0) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )!
    }

    private func assertPoint(_ point: CGPoint, x: CGFloat, y: CGFloat, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(point.x, x, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(point.y, y, accuracy: 0.01, file: file, line: line)
    }
}
