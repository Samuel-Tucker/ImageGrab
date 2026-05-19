import AppKit
import XCTest
@testable import ImageGrabKit

@MainActor
final class OCRResultPresenterTests: XCTestCase {
    func testRecognizeReturnsTextForRenderedImage() async throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(rawValue: "OCRResultPresenterTests-text"))
        let presenter = OCRResultPresenter(image: renderedImage(text: "Bridge OK"), pasteboard: pasteboard)

        let state = await presenter.recognize()

        guard case .text(let text) = state else {
            XCTFail("Expected .text, got \(state)")
            return
        }
        XCTAssertTrue(
            text.localizedCaseInsensitiveContains("Bridge"),
            "Expected recognized text to contain 'Bridge', got: \(text)"
        )
        XCTAssertEqual(presenter.state, state)
    }

    func testRecognizeReturnsNoTextForBlankImage() async {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(rawValue: "OCRResultPresenterTests-blank"))
        let presenter = OCRResultPresenter(image: blankImage(width: 240, height: 80), pasteboard: pasteboard)

        let state = await presenter.recognize()

        XCTAssertEqual(state, .noText)
        XCTAssertEqual(presenter.state, .noText)
    }

    func testCopyWritesTrimmedTextToInjectedPasteboard() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(rawValue: "OCRResultPresenterTests-copy"))
        pasteboard.clearContents()
        let presenter = OCRResultPresenter(image: blankImage(width: 10, height: 10), pasteboard: pasteboard)

        let copied = presenter.copy("  hello world  \n")

        XCTAssertTrue(copied)
        XCTAssertEqual(pasteboard.string(forType: .string), "hello world")
    }

    func testCopyEmptyOrWhitespaceIsNoOp() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(rawValue: "OCRResultPresenterTests-empty"))
        pasteboard.clearContents()
        pasteboard.setString("untouched", forType: .string)
        let presenter = OCRResultPresenter(image: blankImage(width: 10, height: 10), pasteboard: pasteboard)

        XCTAssertFalse(presenter.copy(""))
        XCTAssertFalse(presenter.copy("   \n  "))
        XCTAssertEqual(pasteboard.string(forType: .string), "untouched")
    }

    private func renderedImage(text: String) -> NSImage {
        let font = NSFont.systemFont(ofSize: 48, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let padding: CGFloat = 24
        let imageSize = NSSize(width: textSize.width + padding * 2, height: textSize.height + padding * 2)
        let image = NSImage(size: imageSize)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: imageSize).fill()
        (text as NSString).draw(at: NSPoint(x: padding, y: padding), withAttributes: attributes)
        image.unlockFocus()
        return image
    }

    private func blankImage(width: CGFloat, height: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: NSSize(width: width, height: height)).fill()
        image.unlockFocus()
        return image
    }
}
