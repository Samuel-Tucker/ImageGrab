import AppKit
import Foundation

/// Drives the OCR result popover in `CapturePreviewWindow`. Owns the recognize/
/// pasteboard side so the view controller stays a thin shell and the behavior
/// is unit-testable without exercising AppKit windowing.
@MainActor
final class OCRResultPresenter {
    enum State: Equatable {
        case idle
        case recognizing
        case text(String)
        case noText
        case failed
    }

    let image: NSImage
    private(set) var state: State = .idle
    private let pasteboard: NSPasteboard

    init(image: NSImage, pasteboard: NSPasteboard = .general) {
        self.image = image
        self.pasteboard = pasteboard
    }

    /// Run OCR and update `state`. The returned value is the same as
    /// `state` after the call settles — callers can read either.
    @discardableResult
    func recognize() async -> State {
        state = .recognizing
        do {
            let raw = try await TextRecognizer.recognizeText(in: image)
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            state = text.isEmpty ? .noText : .text(text)
        } catch TextRecognizerError.noTextFound {
            state = .noText
        } catch {
            state = .failed
        }
        return state
    }

    /// Write `text` to the configured pasteboard. Returns false (no-op) for
    /// empty strings so callers can short-circuit UI without inspecting the
    /// pasteboard afterwards.
    @discardableResult
    func copy(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        pasteboard.clearContents()
        pasteboard.setString(trimmed, forType: .string)
        return true
    }
}
