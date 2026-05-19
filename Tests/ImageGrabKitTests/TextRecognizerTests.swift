import AppKit
import XCTest
@testable import ImageGrabKit

@MainActor
final class TextRecognizerTests: XCTestCase {
    func testRecognizeTextFromRenderedImage() async throws {
        let phrase = "Hello OCR"
        let image = renderedImage(text: phrase)

        let recognizedText = try await TextRecognizer.recognizeText(in: image)

        XCTAssertTrue(
            recognizedText.localizedCaseInsensitiveContains("Hello"),
            "Expected OCR result to contain 'Hello', got: \(recognizedText)"
        )
    }

    func testBlankImageThrowsNoTextFound() async throws {
        let image = blankImage(width: 220, height: 80)

        do {
            _ = try await TextRecognizer.recognizeText(in: image)
            XCTFail("Expected noTextFound error for blank image")
        } catch let error as TextRecognizerError {
            XCTAssertEqual(error, .noTextFound)
        }
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
        let imageSize = NSSize(width: width, height: height)
        let image = NSImage(size: imageSize)

        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: imageSize).fill()
        image.unlockFocus()

        return image
    }
}
